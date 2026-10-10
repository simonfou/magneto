#pragma once
// LoopbackCapture: everything the PC is playing, minus one program
// (Discord by default), as stereo float frames for Godot to analyse.
// Windows 10 2004+ only (process-loopback API); elsewhere it reports
// "not supported" so the same project runs everywhere.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/string.hpp>

#include <atomic>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace godot {

class LoopbackCapture : public RefCounted {
	GDCLASS(LoopbackCapture, RefCounted)

public:
	static constexpr int MIX_RATE = 48000;

	~LoopbackCapture();

	bool is_supported() const;
	// Starts capturing on a background thread. exclude_process is an exe
	// name ("Discord.exe"); its whole process tree is left out.
	bool start(const String &exclude_process);
	void stop();
	// Pops up to max_frames captured frames (oldest first).
	PackedVector2Array take_frames(int max_frames);
	int get_mix_rate() const { return MIX_RATE; }
	String get_status() const;

protected:
	static void _bind_methods();

private:
	void run(std::wstring exclude);
	void set_status(const String &s);
	void push(const float *interleaved, uint32_t frames, bool silent);

	std::thread worker;
	std::atomic<bool> running{ false };
	mutable std::mutex mtx;
	std::vector<float> buffer; // interleaved L,R
	String status = "idle";
};

} // namespace godot
