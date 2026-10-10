extends Node
## Everything that talks to the outside world about Spotify, polled on a
## worker thread so the external commands never stall a frame:
##  - keeps our capture port wired to Spotify's output (pw-link), since
##    Godot can only open the default mic;
##  - reads the current track over MPRIS (gdbus) and signals song changes.

signal track_changed(title: String, artist: String)

# PipeWire node names (pw-link port prefixes). Ours is the project name.
const SPOTIFY_NODE := "spotify"
const OUR_NODE := "magneto"
const POLL_EVERY := 1.5

## Set by main.gd once the microphone stream is playing.
var capture_enabled := false

var _timer := 0.0
var _task := -1
var _track_id := ""
var _re_id := RegEx.create_from_string("'mpris:trackid': <(?:objectpath )?'([^']*)'>")
var _re_title := RegEx.create_from_string("'xesam:title': <(?:'((?:[^'\\\\]|\\\\.)*)'|\"((?:[^\"\\\\]|\\\\.)*)\")>")
var _re_artist := RegEx.create_from_string("'xesam:artist': <\\[(?:'((?:[^'\\\\]|\\\\.)*)'|\"((?:[^\"\\\\]|\\\\.)*)\")")


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0 or _task != -1:
		return
	_timer = POLL_EVERY
	_task = WorkerThreadPool.add_task(_poll)


func _exit_tree() -> void:
	if _task != -1:
		WorkerThreadPool.wait_for_task_completion(_task)


# --- worker thread ----------------------------------------------------------

func _poll() -> void:
	if capture_enabled:
		_route()
	_done.call_deferred(_read_track())


func _route() -> void:
	# Wire Spotify's output ports straight into our capture ports and drop
	# any other input (the default mic WirePlumber hooks up at start), so
	# Discord or game audio never drives the particles.
	var out := []
	if OS.execute("pw-link", ["-l"], out) != 0:
		return
	var spotify: Array[String] = []
	var ours: Array[String] = []
	var feeds := {}  # our input port -> ports linked into it
	var port := ""
	for line: String in out[0].split("\n"):
		if line.is_empty():
			continue
		if not line.begins_with(" "):
			port = line.strip_edges()
			if port.begins_with(SPOTIFY_NODE + ":output_") and port not in spotify:
				spotify.append(port)
			elif port.begins_with(OUR_NODE + ":input_") and port not in ours:
				ours.append(port)
				feeds[port] = []
		elif "|<-" in line and feeds.has(port):
			feeds[port].append(line.split("|<-")[1].strip_edges())
	# Ports with no links are not in -l output; ask for them explicitly.
	out.clear()
	OS.execute("pw-link", ["-i"], out)
	for line: String in out[0].split("\n"):
		var p := line.strip_edges()
		if p.begins_with(OUR_NODE + ":input_") and p not in ours:
			ours.append(p)
			feeds[p] = []
	out.clear()
	OS.execute("pw-link", ["-o"], out)
	for line: String in out[0].split("\n"):
		var p := line.strip_edges()
		if p.begins_with(SPOTIFY_NODE + ":output_") and p not in spotify:
			spotify.append(p)

	for dst: String in ours:
		for src: String in feeds[dst]:
			if src not in spotify:
				OS.execute("pw-link", ["-d", src, dst])
				print_verbose("unlink ", src, " -> ", dst)
		for src: String in spotify:
			if src not in feeds[dst]:
				OS.execute("pw-link", [src, dst])
				print_verbose("link ", src, " -> ", dst)


func _read_track() -> Dictionary:
	var out := []
	var code := OS.execute("gdbus", ["call", "--session",
		"--dest", "org.mpris.MediaPlayer2.spotify",
		"--object-path", "/org/mpris/MediaPlayer2",
		"--method", "org.freedesktop.DBus.Properties.Get",
		"org.mpris.MediaPlayer2.Player", "Metadata"], out)
	if code != 0 or out.is_empty():
		return {}
	var text: String = out[0]
	var id := _re_id.search(text)
	if id == null:
		return {}
	return {"id": id.get_string(1), "title": _first(_re_title, text), "artist": _first(_re_artist, text)}


func _first(re: RegEx, text: String) -> String:
	var m := re.search(text)
	if m == null:
		return ""
	var s := m.get_string(1) if m.get_string(1) != "" else m.get_string(2)
	return s.replace("\\'", "'").replace("\\\"", "\"")


# --- main thread ------------------------------------------------------------

func _done(track: Dictionary) -> void:
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	if track.is_empty() or track.id == _track_id:
		return
	_track_id = track.id
	track_changed.emit(track.title, track.artist)
