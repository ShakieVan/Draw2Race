class_name ApkShare
extends Node

# Die installierte App weitergeben (Nutzerwunsch 04.10.2026: „dass die App die APK an benachbarte Geräte schicken kann (falls z. B.
# kein Internet verfügbar ist)“). Zwei Wege:
#   - „Draw2Race teilen“ (Updates-Dialog, nur Android): Teilen-Menü (Quick Share, Bluetooth, Messenger …) mit einer Kopie der
#     installierten APK unter files/share/Draw2Race-<Version>.apk – der FileProvider der Godot-Bibliothek gibt files/ frei.
#   - Quelle für die Weitergabe im WLAN-Mehrspieler (NetLobby/NetApk): Größe und SHA-256 der eigenen APK (einmal je installierter
#     Version berechnet und in CACHE gemerkt) und zum Senden dieselbe Kopie.
# Kopie und Prüfsumme rechnet Java (android/build/.../ApkShare.java) in einem eigenen Thread; hier wird nur abgefragt (poll).
# Aufgeräumt wird beim Programmstart (alte Kopien) und beim Verlassen des WLAN-Mehrspielers (release_file) – außer es wurde in dieser
# Sitzung über das Teilen-Menü verschickt: Die empfangende App liest die Datei womöglich noch, dann bleibt sie bis zum nächsten Start.
# Am PC (Tests): source_override {"path", "version", "receive"} statt der installierten App.

signal changed

const DIR := "user://share"
const CACHE := "user://apk_hash.json"
const POLL_MS := 100

var source_override := {}   # nur Tests: {"path": Datei, die als eigene APK gilt, "version": "x.y.z", "receive": darf empfangen}
var info := {}              # Android: {source, size, version, code, stamp, split}; Tests: {size, version}
var sha256 := ""            # Prüfsumme der eigenen APK ("" = noch unbekannt)
var copy_path := ""         # fertige Datei zum Senden und Teilen ("" = noch keine)
var job := ""               # "" | "hash" | "copy" (läuft gerade)
var percent := -1
var status := ""            # Klartext für den Teilen-Dialog
var shared := false         # in dieser Sitzung über das Teilen-Menü verschickt
var _copy_wanted := false
var _share_pending := false
var _next_poll_ms := 0
var _thread: Thread         # Tests: Prüfsumme der Ersatzdatei
var _mutex := Mutex.new()
var _thread_sha := ""

func setup() -> void:
	# Programmstart: Kopien früherer Sitzungen entfernen (jetzt kann keine Weitergabe mehr laufen).
	if source_override.is_empty():
		_clear_dir()

func _process(_dt: float) -> void:
	poll()

func _exit_tree() -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null

func _android() -> Array:
	# [Java-Klasse, Activity] oder [] außerhalb von Android (wie Updater.android).
	if OS.get_name() != "Android" or not Engine.has_singleton("AndroidRuntime"):
		return []
	var activity = Engine.get_singleton("AndroidRuntime").getActivity()
	var java = JavaClassWrapper.wrap("com.godot.game.ApkShare")
	return [java, activity] if java != null and activity != null else []

func _load_info() -> void:
	if not info.is_empty():
		return
	if not source_override.is_empty():
		var path := str(source_override.get("path", ""))
		if path != "" and FileAccess.file_exists(path):
			var f := FileAccess.open(path, FileAccess.READ)
			info = {"size": f.get_length(), "version": str(source_override.get("version", NetProtocol.game_version()))}
		return
	var a := _android()
	if a.is_empty():
		return
	var data = JSON.parse_string(str(a[0].info(a[1])))
	if not data is Dictionary or int(data.get("size", 0)) <= 0 or not Updater.valid_version(str(data.get("version", ""))):
		return
	info = data
	var cache = JSON.parse_string(FileAccess.get_file_as_string(CACHE)) if FileAccess.file_exists(CACHE) else null
	if cache is Dictionary and str(cache.get("stamp", "")) == str(info.get("stamp", "-")) and NetApk.is_sha(str(cache.get("sha256", ""))):
		sha256 = str(cache.sha256)

func available() -> bool:
	# Gibt es eine eigene APK zum Weitergeben? Android (eine einzelne, ganze APK) oder die Testdatei.
	_load_info()
	return not info.is_empty() and not bool(info.get("split", false))

func can_receive() -> bool:
	# Darf dieses Gerät eine neuere APK holen (und installieren)? Nur auf dem Handy (am PC nur in Tests).
	if not source_override.is_empty():
		return bool(source_override.get("receive", false))
	return OS.get_name() == "Android"

func version() -> String:
	_load_info()
	return str(info.get("version", NetProtocol.game_version()))

func size_bytes() -> int:
	_load_info()
	return int(info.get("size", 0))

func share_name() -> String:
	return "Draw2Race-%s.apk" % version()

func offer() -> Dictionary:
	# {size, sha256} der eigenen APK, {} solange unbekannt.
	return {"size": size_bytes(), "sha256": sha256} if sha256 != "" and available() else {}

func file_ready() -> bool:
	return copy_path != "" and sha256 != ""

func file_path() -> String:
	return copy_path

func prepare_hash() -> void:
	# Prüfsumme der eigenen APK im Hintergrund (einmal je installierter Version; danach aus CACHE).
	if not available() or sha256 != "" or job != "":
		return
	if not source_override.is_empty():
		job = "hash"
		_thread = Thread.new()
		_thread.start(_hash_file.bind(str(source_override.path)))
		return
	var a := _android()
	if not a.is_empty() and bool(a[0].start(a[1], "")):
		job = "hash"
		percent = 0

func want_file() -> void:
	# Datei zum Senden und Teilen bereitstellen (Android: Kopie der installierten APK samt Prüfsumme; Tests: die Datei selbst).
	if not available() or file_ready():
		return
	_copy_wanted = true
	if not source_override.is_empty():
		if sha256 != "":
			copy_path = str(source_override.path)
			_copy_wanted = false
		else:
			prepare_hash()
		return
	if job == "":
		_start_copy()

func _start_copy() -> void:
	var a := _android()
	if a.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(DIR)
	if bool(a[0].start(a[1], ProjectSettings.globalize_path(DIR + "/" + share_name()))):
		job = "copy"
		percent = 0
		status = "Bereite die Datei vor …"
		changed.emit()

func share() -> void:
	# „Draw2Race teilen“: Teilen-Menü öffnen, sobald die Kopie bereit ist.
	if OS.get_name() != "Android" or not available():
		status = "Teilen geht nur in der Android-App."
		changed.emit()
		return
	_share_pending = true
	if file_ready():
		_open_share()
		return
	want_file()
	status = "Bereite die Datei vor …"
	changed.emit()

func _open_share() -> void:
	_share_pending = false
	var a := _android()
	if a.is_empty():
		return
	var problem := str(a[0].share(a[1], ProjectSettings.globalize_path(copy_path), "Draw2Race %s (Android-App)" % version(), "Draw2Race teilen"))
	shared = shared or problem == ""
	status = "Teilen-Menü geöffnet – wähle Quick Share, Bluetooth oder eine andere App." if problem == "" else problem
	changed.emit()

func release_file() -> void:
	# Nach dem WLAN-Mehrspieler: Kopie löschen, außer sie wurde in dieser Sitzung geteilt oder wird gerade fürs Teilen vorbereitet.
	if not source_override.is_empty():
		copy_path = ""
		return
	if shared or _share_pending:
		return
	_copy_wanted = false
	if job == "copy":
		var a := _android()
		if not a.is_empty():
			a[0].cancel()
		return
	if copy_path != "":
		DirAccess.remove_absolute(copy_path)
		copy_path = ""

func _clear_dir() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for name in dir.get_files():
		dir.remove(name)

func poll() -> void:
	if job == "":
		return
	if not source_override.is_empty():
		_mutex.lock()
		var found := _thread_sha
		_mutex.unlock()
		if found == "" or _thread == null or _thread.is_alive():
			return
		_thread.wait_to_finish()
		_thread = null
		job = ""
		if found != "-":
			sha256 = found
			if _copy_wanted:
				copy_path = str(source_override.path)
				_copy_wanted = false
		changed.emit()
		return
	var now := Time.get_ticks_msec()
	if now < _next_poll_ms:
		return
	_next_poll_ms = now + POLL_MS
	var a := _android()
	if a.is_empty():
		job = ""
		return
	var st = JSON.parse_string(str(a[0].status()))
	if not st is Dictionary:
		return
	percent = int(100.0 * float(st.get("done", 0)) / maxf(1.0, float(st.get("total", 1))))
	match str(st.get("state", "")):
		"done":
			var was := job
			job = ""
			percent = -1
			sha256 = str(st.get("sha256", ""))
			var f := FileAccess.open(CACHE, FileAccess.WRITE)
			if f != null:
				f.store_string(JSON.stringify({"stamp": str(info.get("stamp", "")), "sha256": sha256}))
				f.close()
			if was == "copy" and _copy_wanted:
				copy_path = DIR + "/" + share_name()
				_copy_wanted = false
				status = "Datei bereit."
			elif was == "copy":
				DirAccess.remove_absolute(DIR + "/" + share_name())   # inzwischen nicht mehr gebraucht (release_file)
			if _copy_wanted and copy_path == "":
				_start_copy()
			elif _share_pending and file_ready():
				_open_share()
		"error":
			job = ""
			percent = -1
			_share_pending = false
			status = "Vorbereitung fehlgeschlagen: %s" % str(st.get("error", "?"))
	changed.emit()

func _hash_file(path: String) -> void:
	var out := "-"
	var f := FileAccess.open(path, FileAccess.READ)
	if f != null:
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		while f.get_position() < f.get_length():
			ctx.update(f.get_buffer(1 << 20))
		out = ctx.finish().hex_encode()
	_mutex.lock()
	_thread_sha = out
	_mutex.unlock()
