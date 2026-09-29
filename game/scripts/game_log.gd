class_name GameLog
extends Logger
## Captures engine/script errors so they can be shown on screen and saved (user://log.txt),
## which makes problems on phones diagnosable without a USB cable.

static var lines := PackedStringArray()
static var _mutex := Mutex.new()


func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array) -> void:
	if error_type == ERROR_TYPE_WARNING:
		return
	add("%s  [%s:%d %s]" % [rationale if rationale != "" else code, file.get_file(), line, function])


func _log_message(message: String, error: bool) -> void:
	if error:
		add(message.strip_edges())


static func add(text: String) -> void:
	_mutex.lock()
	lines.append(text)
	if lines.size() > 40:
		lines.remove_at(0)
	_mutex.unlock()


static func recent(n := 6) -> String:
	_mutex.lock()
	var out := "\n".join(lines.slice(maxi(0, lines.size() - n)))
	_mutex.unlock()
	return out


static func save_to_disk() -> void:
	var f := FileAccess.open("user://log.txt", FileAccess.WRITE)
	if f:
		_mutex.lock()
		f.store_string("\n".join(lines))
		_mutex.unlock()
