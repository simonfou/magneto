#include "loopback_capture.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

void LoopbackCapture::_bind_methods() {
	ClassDB::bind_method(D_METHOD("is_supported"), &LoopbackCapture::is_supported);
	ClassDB::bind_method(D_METHOD("start", "exclude_process"), &LoopbackCapture::start);
	ClassDB::bind_method(D_METHOD("stop"), &LoopbackCapture::stop);
	ClassDB::bind_method(D_METHOD("take_frames", "max_frames"), &LoopbackCapture::take_frames);
	ClassDB::bind_method(D_METHOD("get_mix_rate"), &LoopbackCapture::get_mix_rate);
	ClassDB::bind_method(D_METHOD("get_status"), &LoopbackCapture::get_status);
}

LoopbackCapture::~LoopbackCapture() {
	stop();
}

void LoopbackCapture::set_status(const String &s) {
	std::lock_guard<std::mutex> g(mtx);
	status = s;
}

String LoopbackCapture::get_status() const {
	std::lock_guard<std::mutex> g(mtx);
	return status;
}

void LoopbackCapture::push(const float *interleaved, uint32_t frames, bool silent) {
	std::lock_guard<std::mutex> g(mtx);
	if (silent || interleaved == nullptr) {
		buffer.insert(buffer.end(), size_t(frames) * 2, 0.0f);
	} else {
		buffer.insert(buffer.end(), interleaved, interleaved + size_t(frames) * 2);
	}
	// Keep at most 0.25 s: if Godot falls behind, drop the oldest audio
	// rather than drifting further and further out of sync.
	const size_t cap = size_t(MIX_RATE / 4) * 2;
	if (buffer.size() > cap) {
		buffer.erase(buffer.begin(), buffer.begin() + (buffer.size() - cap));
	}
}

PackedVector2Array LoopbackCapture::take_frames(int max_frames) {
	PackedVector2Array out;
	std::lock_guard<std::mutex> g(mtx);
	const size_t n = std::min(size_t(max_frames > 0 ? max_frames : 0), buffer.size() / 2);
	out.resize(int64_t(n));
	for (size_t i = 0; i < n; i++) {
		out.set(int64_t(i), Vector2(buffer[i * 2], buffer[i * 2 + 1]));
	}
	buffer.erase(buffer.begin(), buffer.begin() + n * 2);
	return out;
}

bool LoopbackCapture::start(const String &exclude_process) {
	if (!is_supported()) {
		set_status("not supported on this platform");
		return false;
	}
	stop();
	running = true;
	std::wstring name;
	CharString utf8 = exclude_process.utf8();
	for (const char *p = utf8.get_data(); *p; p++) {
		name.push_back(wchar_t(*p)); // exe names are ASCII
	}
	worker = std::thread(&LoopbackCapture::run, this, name);
	return true;
}

void LoopbackCapture::stop() {
	running = false;
	if (worker.joinable()) {
		worker.join();
	}
}

#ifndef _WIN32

bool LoopbackCapture::is_supported() const {
	return false;
}

void LoopbackCapture::run(std::wstring) {
}

#else // _WIN32 ------------------------------------------------------------

#include <windows.h>

#include <audioclient.h>
#include <mmdeviceapi.h>
#include <tlhelp32.h>

// audioclientactivationparams.h (Windows SDK 10.0.20348+) is not in
// MinGW's headers yet; these are its declarations, values per Microsoft's
// docs for AUDIOCLIENT_ACTIVATION_PARAMS.
typedef enum AUDIOCLIENT_ACTIVATION_TYPE {
	AUDIOCLIENT_ACTIVATION_TYPE_DEFAULT = 0,
	AUDIOCLIENT_ACTIVATION_TYPE_PROCESS_LOOPBACK = 1,
} AUDIOCLIENT_ACTIVATION_TYPE;

typedef enum PROCESS_LOOPBACK_MODE {
	PROCESS_LOOPBACK_MODE_INCLUDE_TARGET_PROCESS_TREE = 0,
	PROCESS_LOOPBACK_MODE_EXCLUDE_TARGET_PROCESS_TREE = 1,
} PROCESS_LOOPBACK_MODE;

typedef struct AUDIOCLIENT_PROCESS_LOOPBACK_PARAMS {
	DWORD TargetProcessId;
	PROCESS_LOOPBACK_MODE ProcessLoopbackMode;
} AUDIOCLIENT_PROCESS_LOOPBACK_PARAMS;

typedef struct AUDIOCLIENT_ACTIVATION_PARAMS {
	AUDIOCLIENT_ACTIVATION_TYPE ActivationType;
	union {
		AUDIOCLIENT_PROCESS_LOOPBACK_PARAMS ProcessLoopbackParams;
	};
} AUDIOCLIENT_ACTIVATION_PARAMS;

#define VIRTUAL_AUDIO_DEVICE_PROCESS_LOOPBACK L"VAD\\Process_Loopback"

#include <cwctype>
#include <map>

namespace {

typedef HRESULT(WINAPI *ActivateFn)(LPCWSTR, REFIID, PROPVARIANT *,
		IActivateAudioInterfaceCompletionHandler *, IActivateAudioInterfaceAsyncOperation **);

// Minimal COM object Windows calls back when activation finishes. It must
// be agile (callable from any thread), hence IAgileObject.
class ActivationHandler : public IActivateAudioInterfaceCompletionHandler {
public:
	HANDLE done = CreateEventW(nullptr, TRUE, FALSE, nullptr);

	HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **out) override {
		if (riid == IID_IUnknown || riid == __uuidof(IActivateAudioInterfaceCompletionHandler) ||
				riid == IID_IAgileObject) {
			*out = static_cast<IActivateAudioInterfaceCompletionHandler *>(this);
			AddRef();
			return S_OK;
		}
		*out = nullptr;
		return E_NOINTERFACE;
	}
	ULONG STDMETHODCALLTYPE AddRef() override { return InterlockedIncrement(&refs); }
	ULONG STDMETHODCALLTYPE Release() override {
		ULONG r = InterlockedDecrement(&refs);
		if (r == 0) {
			CloseHandle(done);
			delete this;
		}
		return r;
	}
	HRESULT STDMETHODCALLTYPE ActivateCompleted(IActivateAudioInterfaceAsyncOperation *) override {
		SetEvent(done);
		return S_OK;
	}

private:
	LONG refs = 1;
};

std::wstring lower(std::wstring s) {
	for (auto &c : s) {
		c = wchar_t(std::towlower(c));
	}
	return s;
}

// The root of a program's process tree: a process with that exe name whose
// parent is not the same program. 0 if it isn't running.
DWORD find_root_pid(const std::wstring &exe) {
	if (exe.empty()) {
		return 0;
	}
	HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
	if (snap == INVALID_HANDLE_VALUE) {
		return 0;
	}
	std::map<DWORD, std::pair<DWORD, std::wstring>> procs; // pid -> (parent, exe)
	PROCESSENTRY32W e{};
	e.dwSize = sizeof(e);
	for (BOOL ok = Process32FirstW(snap, &e); ok; ok = Process32NextW(snap, &e)) {
		procs[e.th32ProcessID] = { e.th32ParentProcessID, lower(e.szExeFile) };
	}
	CloseHandle(snap);
	const std::wstring want = lower(exe);
	for (auto &[pid, info] : procs) {
		if (info.second != want) {
			continue;
		}
		auto parent = procs.find(info.first);
		if (parent == procs.end() || parent->second.second != want) {
			return pid;
		}
	}
	return 0;
}

String hr_text(const char *what, HRESULT hr) {
	return String(what) + " failed (0x" + String::num_int64(uint32_t(hr), 16) + ")";
}

} // namespace

bool LoopbackCapture::is_supported() const {
	return true;
}

void LoopbackCapture::run(std::wstring exclude) {
	CoInitializeEx(nullptr, COINIT_MULTITHREADED);
	ActivateFn activate = nullptr;
	if (HMODULE mm = LoadLibraryW(L"Mmdevapi.dll")) {
		activate = reinterpret_cast<ActivateFn>(GetProcAddress(mm, "ActivateAudioInterfaceAsync"));
	}
	if (!activate) {
		set_status("ActivateAudioInterfaceAsync missing (Windows too old?)");
		running = false;
		CoUninitialize();
		return;
	}

	while (running) {
		// Exclude the program's tree; if it isn't running, exclude ourselves
		// (we play nothing), which means "capture everything".
		DWORD excluded = find_root_pid(exclude);
		DWORD target = excluded ? excluded : GetCurrentProcessId();

		AUDIOCLIENT_ACTIVATION_PARAMS params{};
		params.ActivationType = AUDIOCLIENT_ACTIVATION_TYPE_PROCESS_LOOPBACK;
		params.ProcessLoopbackParams.TargetProcessId = target;
		params.ProcessLoopbackParams.ProcessLoopbackMode = PROCESS_LOOPBACK_MODE_EXCLUDE_TARGET_PROCESS_TREE;
		PROPVARIANT pv{};
		pv.vt = VT_BLOB;
		pv.blob.cbSize = sizeof(params);
		pv.blob.pBlobData = reinterpret_cast<BYTE *>(&params);

		ActivationHandler *handler = new ActivationHandler();
		IActivateAudioInterfaceAsyncOperation *op = nullptr;
		IAudioClient *client = nullptr;
		IAudioCaptureClient *capture = nullptr;
		HANDLE ready = nullptr;
		HRESULT hr = activate(VIRTUAL_AUDIO_DEVICE_PROCESS_LOOPBACK, __uuidof(IAudioClient), &pv, handler, &op);
		if (SUCCEEDED(hr)) {
			WaitForSingleObject(handler->done, 5000);
			HRESULT act = E_FAIL;
			IUnknown *unk = nullptr;
			hr = op->GetActivateResult(&act, &unk);
			if (SUCCEEDED(hr)) {
				hr = act;
			}
			if (SUCCEEDED(hr)) {
				hr = unk->QueryInterface(__uuidof(IAudioClient), reinterpret_cast<void **>(&client));
				unk->Release();
			}
		}
		if (FAILED(hr)) {
			set_status(hr_text("activation", hr));
		} else {
			WAVEFORMATEX fmt{};
			fmt.wFormatTag = WAVE_FORMAT_IEEE_FLOAT;
			fmt.nChannels = 2;
			fmt.nSamplesPerSec = MIX_RATE;
			fmt.wBitsPerSample = 32;
			fmt.nBlockAlign = fmt.nChannels * fmt.wBitsPerSample / 8;
			fmt.nAvgBytesPerSec = fmt.nSamplesPerSec * fmt.nBlockAlign;
			hr = client->Initialize(AUDCLNT_SHAREMODE_SHARED,
					AUDCLNT_STREAMFLAGS_LOOPBACK | AUDCLNT_STREAMFLAGS_EVENTCALLBACK | AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM,
					200000, 0, &fmt, nullptr); // 20 ms buffer, in 100 ns units
			ready = CreateEventW(nullptr, FALSE, FALSE, nullptr);
			if (SUCCEEDED(hr)) {
				hr = client->SetEventHandle(ready);
			}
			if (SUCCEEDED(hr)) {
				hr = client->GetService(__uuidof(IAudioCaptureClient), reinterpret_cast<void **>(&capture));
			}
			if (SUCCEEDED(hr)) {
				hr = client->Start();
			}
			if (FAILED(hr)) {
				set_status(hr_text("audio client setup", hr));
			}
		}

		if (SUCCEEDED(hr)) {
			set_status(excluded ? String("capturing all audio except ") + String(exclude.c_str()) + " (pid " + String::num_int64(excluded) + ")"
								: String("capturing all audio (") + String(exclude.c_str()) + " not running)");
			ULONGLONG next_check = GetTickCount64() + 5000;
			while (running) {
				WaitForSingleObject(ready, 100);
				UINT32 packet = 0;
				while (running && SUCCEEDED(capture->GetNextPacketSize(&packet)) && packet > 0) {
					BYTE *data = nullptr;
					UINT32 frames = 0;
					DWORD flags = 0;
					if (FAILED(capture->GetBuffer(&data, &frames, &flags, nullptr, nullptr))) {
						break;
					}
					push(reinterpret_cast<const float *>(data), frames, (flags & AUDCLNT_BUFFERFLAGS_SILENT) != 0);
					capture->ReleaseBuffer(frames);
				}
				// Discord started or quit: rebuild the capture so the
				// exclusion follows it.
				if (GetTickCount64() > next_check) {
					next_check = GetTickCount64() + 5000;
					if (find_root_pid(exclude) != excluded) {
						break;
					}
				}
			}
			client->Stop();
		}

		if (capture) {
			capture->Release();
		}
		if (client) {
			client->Release();
		}
		if (op) {
			op->Release();
		}
		if (ready) {
			CloseHandle(ready);
		}
		handler->Release();
		if (FAILED(hr)) {
			// Don't spin: try again in a few seconds.
			for (int i = 0; i < 30 && running; i++) {
				Sleep(100);
			}
		}
	}
	CoUninitialize();
}

#endif // _WIN32
