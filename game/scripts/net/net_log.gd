class_name NetLog
extends RefCounted

# Protokoll des Netztests: jede Zeile mit Ortszeit (ms) und Sekunden seit Start, sofort auf die Platte (die App kann auf dem Handy
# jederzeit beendet werden). Standard user://netztest.log – auf Android per
#   adb shell run-as de.draw2race.game cat files/netztest.log
# abholbar, am PC unter %APPDATA%\Godot\app_userdata\Draw2Race\. Ab 4 MB wird die alte Datei nach *.alt.log verschoben.

signal line_added(text: String)

const DEFAULT_PATH := "user://netztest.log"
const MAX_BYTES := 4 * 1024 * 1024
const KEEP_LINES := 200

var path := DEFAULT_PATH
var lines: Array = []               # letzte Zeilen für die Anzeige
var echo := false                   # zusätzlich auf stdout (Automatik-Modus)
var _start_usec := 0

func _init(file_path := DEFAULT_PATH, print_lines := false) -> void:
	path = file_path
	echo = print_lines
	_start_usec = Time.get_ticks_usec()
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null and f.get_length() > MAX_BYTES:
			f.close()
			var old := path.get_basename() + ".alt.log"
			DirAccess.remove_absolute(old)
			DirAccess.rename_absolute(path, old)

static func stamp() -> String:
	# Ortszeit mit Millisekunden, z. B. "2026-10-03 15:48:12.345".
	var unix := Time.get_unix_time_from_system()
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var whole := int(floor(unix))
	return "%s.%03d" % [Time.get_datetime_string_from_unix_time(whole + bias, true), int((unix - whole) * 1000.0) % 1000]

func write(text: String) -> void:
	var line := "%s [+%8.3f] %s" % [stamp(), (Time.get_ticks_usec() - _start_usec) / 1000000.0, text]
	lines.append(line)
	if lines.size() > KEEP_LINES:
		lines.pop_front()
	var f: FileAccess
	if FileAccess.file_exists(path):
		f = FileAccess.open(path, FileAccess.READ_WRITE)
		if f != null:
			f.seek_end()
	else:
		f = FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_line(line)
		f.close()
	if echo:
		print(line)
	line_added.emit(line)

func global_path() -> String:
	return ProjectSettings.globalize_path(path)
