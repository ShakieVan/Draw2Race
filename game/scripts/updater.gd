class_name Updater
extends Node

# Update-Funktion: neuestes GitHub-Release prüfen, APK laden, Größe und SHA-256
# aus der GitHub-API prüfen, dann Paket/Version/Signatur (Java: android/build/.../Updater.java) und den
# System-Installer starten. Automatische Prüfung höchstens einmal am Tag; Download nur auf Wunsch.

signal changed

const REPOSITORY := "ShakieVan/Draw2Race"
const ENDPOINT := "https://api.github.com/repos/%s/releases/latest" % REPOSITORY
# Beta-Kanal: alle Releases einschließlich Vorabversionen (GitHub „Pre-release“); die höchste Version gewinnt.
const ENDPOINT_ALL := "https://api.github.com/repos/%s/releases?per_page=20" % REPOSITORY
const MAX_APK_BYTES := 512 * 1024 * 1024
const DAY_MS := 24 * 60 * 60 * 1000
const DIR := "user://updates"

var store: ProgressStore
var status := "Noch nicht geprüft."
var release := {}          # version, notes, size, sha256, url
var busy := false
var percent := -1
var apk_ready := false
var http: HTTPRequest
var hash_thread: Thread

static func current_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))

static func valid_version(text: String) -> bool:
	var parts := text.split(".")
	if parts.size() != 3:
		return false
	for p in parts:
		if not p.is_valid_int() or int(p) < 0:
			return false
	return true

static func compare_versions(a: String, b: String) -> int:
	var x := a.split(".")
	var y := b.split(".")
	for i in range(3):
		if int(x[i]) != int(y[i]):
			return 1 if int(x[i]) > int(y[i]) else -1
	return 0

static func parse(json_text: String, allow_beta := false) -> Dictionary:
	# Nur fertige Releases mit genau einer passenden APK, Größe und SHA-256-Angabe; sonst {}.
	# Vorabversionen nur mit allow_beta. Eine Liste (Beta-Kanal) liefert das Release mit der höchsten Version.
	var json := JSON.new()
	if json_text.strip_edges() == "" or json.parse(json_text) != OK:
		return {}
	if json.data is Array:
		var best := {}
		for entry in json.data:
			var found := parse_release(entry, allow_beta)
			if not found.is_empty() and (best.is_empty() or compare_versions(found.version, best.version) > 0):
				best = found
		return best
	return parse_release(json.data, allow_beta)

static func parse_release(data, allow_beta := false) -> Dictionary:
	if not data is Dictionary or bool(data.get("draft", true)) or (bool(data.get("prerelease", true)) and not allow_beta):
		return {}
	var tag := str(data.get("tag_name", ""))
	if not tag.begins_with("v") or not valid_version(tag.substr(1)):
		return {}
	var version := tag.substr(1)
	var name := "Draw2Race-%s.apk" % version
	var matches: Array = (data.get("assets", []) as Array).filter(func(a): return a is Dictionary and a.get("name") == name)
	if matches.size() != 1:
		return {}
	var asset: Dictionary = matches[0]
	var size := int(asset.get("size", 0))
	var digest := str(asset.get("digest", ""))
	var url := str(asset.get("browser_download_url", ""))
	if size <= 0 or size > MAX_APK_BYTES or not digest.begins_with("sha256:") or digest.length() != 71:
		return {}
	if url != "https://github.com/%s/releases/download/%s/%s" % [REPOSITORY, tag, name]:
		return {}
	return {"version": version, "notes": str(data.get("body", "")).left(6000), "size": size,
		"sha256": digest.substr(7).to_lower(), "url": url, "beta": bool(data.get("prerelease", false)),
		"raw": JSON.stringify(data)}

func beta() -> bool:
	return bool(store.data.get("update_beta", false))

func set_beta(on: bool) -> void:
	# Kanal gewechselt: zwischengespeichertes Ergebnis verwerfen und sofort neu suchen.
	store.data["update_beta"] = on
	store.data.erase("update_release")
	store.save()
	release = {}
	apk_ready = false
	check(true)

func setup(progress_store: ProgressStore) -> void:
	store = progress_store
	http = HTTPRequest.new()
	http.use_threads = true
	http.timeout = 30.0
	add_child(http)
	var cached := parse(str(store.data.get("update_release", "")), beta())
	if not cached.is_empty() and compare_versions(cached.version, current_version()) > 0:
		release = cached
		status = "Neue Version verfügbar."
		apk_ready = FileAccess.file_exists(apk_path())

func available() -> bool:
	return not release.is_empty()

func publish(text: String) -> void:
	status = text
	changed.emit()

func check(manual: bool) -> void:
	if busy:
		return
	var now := int(Time.get_unix_time_from_system() * 1000.0)
	if not manual and now - int(store.data.get("update_last_check", 0)) < DAY_MS:
		return
	store.data["update_last_check"] = now
	store.save()
	busy = true
	percent = -1
	publish("Suche nach Updates …")
	var headers := PackedStringArray(["User-Agent: Draw2Race/%s" % current_version(),
		"Accept: application/vnd.github+json", "X-GitHub-Api-Version: 2022-11-28"])
	http.download_file = ""
	http.request_completed.connect(_checked, CONNECT_ONE_SHOT)
	if http.request(ENDPOINT_ALL if beta() else ENDPOINT, headers) != OK:
		http.request_completed.disconnect(_checked)
		busy = false
		publish("Keine Verbindung.")

func _checked(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	busy = false
	if result != HTTPRequest.RESULT_SUCCESS:
		publish("Keine Verbindung.")
		return
	if code == 404:
		release = {}
		publish("Noch kein Release veröffentlicht.")
		return
	if code != 200 or body.size() > 1024 * 1024:
		publish("Update-Prüfung fehlgeschlagen.")
		return
	var text := body.get_string_from_utf8()
	var found := parse(text, beta())
	if found.is_empty():
		publish("Das neueste Release enthält keine passende APK.")
		return
	store.data["update_release"] = str(found.raw)
	store.save()
	if compare_versions(found.version, current_version()) > 0:
		release = found
		apk_ready = FileAccess.file_exists(apk_path())
		publish("Neue Version verfügbar.")
	else:
		release = {}
		publish("Du hast die neueste Version.")

func apk_path() -> String:
	return "%s/%s.apk" % [DIR, release.get("sha256", "none")]

func download() -> void:
	if busy or release.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(DIR)
	prune()
	busy = true
	percent = 0
	publish("Lade herunter …")
	http.download_file = apk_path() + ".part"
	http.request_completed.connect(_downloaded, CONNECT_ONE_SHOT)
	var headers := PackedStringArray(["User-Agent: Draw2Race/%s" % current_version(), "Accept: application/octet-stream"])
	if http.request(str(release.url), headers) != OK:
		http.request_completed.disconnect(_downloaded)
		busy = false
		publish("Download fehlgeschlagen.")

func _process(_dt: float) -> void:
	if busy and http != null and http.get_http_client_status() == HTTPClient.STATUS_BODY and not release.is_empty():
		var p := int(http.get_downloaded_bytes() * 100 / maxi(1, int(release.size)))
		if p != percent:
			percent = p
			changed.emit()

func _downloaded(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	var part := apk_path() + ".part"
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		busy = false
		DirAccess.remove_absolute(part)
		publish("Download fehlgeschlagen.")
		return
	publish("Prüfe Download …")
	percent = -1
	hash_thread = Thread.new()
	hash_thread.start(_hash_file.bind(part))

func _hash_file(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	var ok := file != null and file.get_length() == int(release.size)
	if ok:
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		while file.get_position() < file.get_length():
			ctx.update(file.get_buffer(1024 * 1024))
		ok = ctx.finish().hex_encode() == str(release.sha256)
	if file != null:
		file.close()
	call_deferred("_hashed", path, ok)

func _hashed(path: String, ok: bool) -> void:
	hash_thread.wait_to_finish()
	busy = false
	if not ok:
		DirAccess.remove_absolute(path)
		publish("Download beschädigt (Prüfsumme falsch) – bitte erneut laden.")
		return
	DirAccess.rename_absolute(path, apk_path())
	apk_ready = true
	publish("Bereit zur Installation.")

# --- Android ---
func android() -> Array:
	# [Java-Klasse, Activity] oder [] außerhalb von Android.
	if OS.get_name() != "Android" or not Engine.has_singleton("AndroidRuntime"):
		return []
	var activity = Engine.get_singleton("AndroidRuntime").getActivity()
	var java = JavaClassWrapper.wrap("com.godot.game.Updater")
	return [java, activity] if java != null and activity != null else []

func can_install() -> bool:
	var a := android()
	return not a.is_empty() and bool(a[0].canInstall(a[1]))

func open_permission() -> void:
	var a := android()
	if not a.is_empty():
		a[0].openInstallPermission(a[1])

func install() -> void:
	var a := android()
	if a.is_empty():
		publish("Installation nur auf dem Handy möglich.")
		return
	if not can_install():
		open_permission()
		publish("Bitte „Apps installieren“ für Draw2Race erlauben und erneut tippen.")
		return
	var path := ProjectSettings.globalize_path(apk_path())
	var problem := str(a[0].verify(a[1], path, str(release.version)))
	if problem != "":
		apk_ready = false
		DirAccess.remove_absolute(apk_path())
		publish("Update abgelehnt: " + problem)
		return
	problem = str(a[0].install(a[1], path))
	publish("Installer gestartet." if problem == "" else problem)

func prune() -> void:
	# Alte Downloads entfernen (nur die aktuelle APK behalten).
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for name in dir.get_files():
		if DIR + "/" + name != apk_path():
			dir.remove(name)
