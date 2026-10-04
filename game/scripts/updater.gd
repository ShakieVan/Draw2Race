class_name Updater
extends Node

# Update-Funktion: neuestes GitHub-Release prüfen, APK laden, Größe und SHA-256
# aus der GitHub-API prüfen, dann Paket/Version/Signatur (Java: android/build/.../Updater.java) und den
# System-Installer starten. Automatische Prüfung höchstens einmal am Tag; Download nur auf Wunsch.

signal changed

const REPOSITORY := "ShakieVan/Draw2Race"
const ENDPOINT := "https://api.github.com/repos/%s/releases/latest" % REPOSITORY
# Beta-Kanal: Testversionen liegen in einem eigenen Repo (optisch getrennt von den regulären Releases). Im Beta-Kanal
# werden beide Quellen abgefragt; die höchste Version gewinnt – ein neueres reguläres Release geht also nicht verloren.
const BETA_REPOSITORY := "ShakieVan/Draw2Race-Beta"
const ENDPOINT_BETA := "https://api.github.com/repos/%s/releases?per_page=20" % BETA_REPOSITORY
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
var pending: Array = []    # noch abzufragende Endpunkte dieser Suche
var best := {}             # bestes gefundenes Release dieser Suche
var answered := false      # mindestens eine Quelle hat geantwortet
var failed := false        # mindestens eine Quelle hat nicht geantwortet (kein Netz, GitHub-Limit, Serverfehler)
var failure := ""          # Klartext zum Fehlschlag (failure_text)
var download_dir := DIR    # Ablage der Downloads (Tests: eigener Ordner)

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
	# Reguläre Releases nur aus REPOSITORY; Vorabversionen und alles aus BETA_REPOSITORY nur mit allow_beta.
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
	var from_beta := url == "https://github.com/%s/releases/download/%s/%s" % [BETA_REPOSITORY, tag, name]
	if url != "https://github.com/%s/releases/download/%s/%s" % [REPOSITORY, tag, name] and not (from_beta and allow_beta):
		return {}
	return {"version": version, "notes": str(data.get("body", "")).left(6000), "size": size,
		"sha256": digest.substr(7).to_lower(), "url": url, "beta": from_beta or bool(data.get("prerelease", false)),
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

# HTTPRequest.timeout begrenzt die GESAMTE Anfrage, nicht die Pause zwischen zwei Paketen. Für die Versionsabfrage (klein) passt
# das; der Download (rund 180 MB) lief damit nach 30 s ab, egal wie gut die Verbindung war. Beim Download ist die Grenze daher aus,
# stattdessen bricht ein Wächter erst ab, wenn STALL_TIMEOUT Sekunden lang kein Byte mehr ankommt.
const CHECK_TIMEOUT := 30.0
const STALL_TIMEOUT := 30.0
var downloading := false
var last_bytes := -1
var stall := 0.0

func setup(progress_store: ProgressStore) -> void:
	store = progress_store
	http = HTTPRequest.new()
	http.use_threads = true
	http.timeout = CHECK_TIMEOUT
	add_child(http)
	var cached := parse(str(store.data.get("update_release", "")), beta())
	if not cached.is_empty() and compare_versions(cached.version, current_version()) > 0:
		release = cached
		status = "Neue Version verfügbar."
		apk_ready = FileAccess.file_exists(apk_path())
	# Aufräumen beim Start: Reste abgebrochener Downloads und schon installierte oder nicht mehr gebrauchte APKs (auch vom
	# Nachbargerät geholte, NetApk) – nur die APK des noch offenen GitHub-Updates bleibt.
	prune()

func available() -> bool:
	return not release.is_empty()

func publish(text: String) -> void:
	status = text
	changed.emit()

func check(manual: bool) -> void:
	if busy:
		return
	# Der Zeitpunkt der letzten Prüfung wird erst nach einer vollständigen Antwort gespeichert (finish_check): Ein Fehlschlag (kein
	# Netz, GitHub-Limit) sperrte die automatische Prüfung sonst für 24 h. Automatisch wird nur beim Programmstart geprüft, ein
	# Fehlschlag kostet also höchstens eine Anfrage je Start.
	var now := int(Time.get_unix_time_from_system() * 1000.0)
	if not manual and now - int(store.data.get("update_last_check", 0)) < DAY_MS:
		return
	busy = true
	percent = -1
	publish("Suche nach Updates …")
	pending =[ENDPOINT_BETA, ENDPOINT] if beta() else [ENDPOINT]
	best = {}
	answered = false
	failed = false
	failure = ""
	request_next()

func request_next() -> void:
	# Quellen nacheinander abfragen (ein HTTPRequest), danach auswerten.
	if pending.is_empty():
		finish_check()
		return
	var headers := PackedStringArray(["User-Agent: Draw2Race/%s" % current_version(),
		"Accept: application/vnd.github+json", "X-GitHub-Api-Version: 2022-11-28"])
	http.download_file = ""
	http.timeout = CHECK_TIMEOUT
	http.request_completed.connect(_checked, CONNECT_ONE_SHOT)
	if http.request(str(pending.pop_front()), headers) != OK:
		http.request_completed.disconnect(_checked)
		request_next()

func _checked(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and (code == 200 or code == 404):
		answered = true
	else:
		failed = true
		# Das GitHub-Limit hat Vorrang: Es betrifft alle Quellen desselben Netzes und erklärt den Fehlschlag am besten.
		if failure == "" or rate_limited(code):
			failure = failure_text(result, code, headers, int(Time.get_unix_time_from_system()))
	if result == HTTPRequest.RESULT_SUCCESS and code == 200 and body.size() <= 1024 * 1024:
		var found := parse(body.get_string_from_utf8(), beta())
		if not found.is_empty() and (best.is_empty() or compare_versions(found.version, best.version) > 0):
			best = found
	request_next()

func finish_check() -> void:
	# Eine neuere Version wird angeboten, auch wenn eine zweite Quelle (Beta-Kanal) nicht geantwortet hat. Ohne neuere Version zählt
	# ein Fehlschlag: Dann ist „Du hast die neueste Version.“ nicht sicher, und der Prüfzeitpunkt bleibt offen (nächster Start fragt neu).
	busy = false
	var newer := not best.is_empty() and compare_versions(best.version, current_version()) > 0
	if not failed:
		store.data["update_last_check"] = int(Time.get_unix_time_from_system() * 1000.0)
	if not best.is_empty() and (newer or not failed):
		store.data["update_release"] = str(best.raw)
	store.save()
	if newer:
		release = best
		apk_ready = FileAccess.file_exists(apk_path())
		publish("Neue Version verfügbar.")
	elif failed:
		publish(failure if failure != "" else "Keine Verbindung.")
	elif best.is_empty():
		release = {}
		publish("Noch kein passendes Release veröffentlicht.")
	else:
		release = {}
		publish("Du hast die neueste Version.")

static func rate_limited(code: int) -> bool:
	# GitHub beantwortet zu viele Anfragen ohne Anmeldung mit 403 (Hauptlimit: 60 je Stunde und IP-Adresse) oder 429.
	return code == 403 or code == 429

static func failure_text(result: int, code: int, headers: PackedStringArray, now_unix: int) -> String:
	# Klartext für eine gescheiterte Versionsabfrage. Im geteilten WLAN (Urlaub, Hotel, Schule) teilen sich alle Geräte eine öffentliche
	# Adresse und damit das Limit von 60 Abfragen je Stunde – das soll nicht als „Keine Verbindung.“ erscheinen. Die Antwort nennt in
	# x-ratelimit-reset (Unix-Zeit) bzw. retry-after (Sekunden), wann es wieder geht.
	if result != HTTPRequest.RESULT_SUCCESS:
		return "Keine Verbindung."
	if not rate_limited(code):
		return "GitHub antwortet gerade nicht (Fehler %d). Bitte später erneut versuchen." % code
	var retry := -1
	var remaining := ""
	var reset := -1
	for line in headers:
		var colon := line.find(":")
		if colon < 0:
			continue
		var key := line.left(colon).strip_edges().to_lower()
		var value := line.substr(colon + 1).strip_edges()
		if key == "retry-after" and value.is_valid_int():
			retry = int(value)
		elif key == "x-ratelimit-remaining":
			remaining = value
		elif key == "x-ratelimit-reset" and value.is_valid_int():
			reset = int(value)
	var wait := retry
	if wait < 0 and remaining == "0" and reset > 0:
		wait = maxi(0, reset - now_unix)
	var text := "Zu viele Update-Abfragen aus diesem Netz (GitHub erlaubt 60 pro Stunde)."
	if wait < 0:
		return text + " Bitte später erneut versuchen."
	var minutes := maxi(1, ceili(wait / 60.0))
	return text + " Wieder möglich in %d %s." % [minutes, "Minute" if minutes == 1 else "Minuten"]

static func release_page(rel: Dictionary, beta_channel: bool) -> String:
	# Ausweg ohne den Updater (Knopf „Im Browser herunterladen“): die GitHub-Seite des angebotenen Releases, sonst die Release-Liste des Kanals.
	# Dort lässt sich die APK auch dann laden und installieren, wenn der Updater selbst defekt ist (wie vor Hotfix 0.2.26).
	var url := str(rel.get("url", ""))
	var marker := "/releases/download/"
	if url.begins_with("https://github.com/") and url.contains(marker):
		return url.get_base_dir().replace(marker, "/releases/tag/")
	if beta_channel:
		return "https://github.com/%s/releases" % BETA_REPOSITORY
	return "https://github.com/%s/releases/latest" % REPOSITORY

func open_release_page() -> void:
	OS.shell_open(release_page(release, beta()))

func apk_path() -> String:
	return "%s/%s.apk" % [download_dir, release.get("sha256", "none")]

func download() -> void:
	if busy or release.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(download_dir)
	prune()
	busy = true
	percent = 0
	publish("Lade herunter …")
	http.download_file = apk_path() + ".part"
	http.timeout = 0.0
	downloading = true
	last_bytes = -1
	stall = 0.0
	http.request_completed.connect(_downloaded, CONNECT_ONE_SHOT)
	var headers := PackedStringArray(["User-Agent: Draw2Race/%s" % current_version(), "Accept: application/octet-stream"])
	if http.request(str(release.url), headers) != OK:
		http.request_completed.disconnect(_downloaded)
		busy = false
		downloading = false
		publish("Download fehlgeschlagen.")

func _process(dt: float) -> void:
	if downloading and http != null:
		# Wächter: solange Bytes ankommen, läuft der Download weiter; erst eine Pause von STALL_TIMEOUT bricht ab.
		var bytes := http.get_downloaded_bytes()
		if bytes != last_bytes:
			last_bytes = bytes
			stall = 0.0
		else:
			stall += dt
			if stall > STALL_TIMEOUT:
				http.cancel_request()
				downloading = false
				http.request_completed.disconnect(_downloaded)
				_downloaded(HTTPRequest.RESULT_TIMEOUT, 0, PackedStringArray(), PackedByteArray())
				return
	if busy and http != null and http.get_http_client_status() == HTTPClient.STATUS_BODY and not release.is_empty():
		var p := int(http.get_downloaded_bytes() * 100 / maxi(1, int(release.size)))
		if p != percent:
			percent = p
			changed.emit()

func _downloaded(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	downloading = false
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
	var problem := install_file(apk_path(), str(release.version))
	apk_ready = FileAccess.file_exists(apk_path())
	publish("Installer gestartet." if problem == "" else problem)

func install_file(file: String, version: String) -> String:
	# Gemeinsamer Weg für GitHub-Download und Nachbargerät (NetApk, schon per Größe und SHA-256 geprüft): Installationsberechtigung,
	# dann Paket, höhere Versionsnummer, angekündigte Version und identische Signatur (Updater.java), dann der System-Installer.
	# "" = Installer gestartet, sonst deutscher Grund; eine abgelehnte Datei wird gelöscht.
	var a := android()
	if a.is_empty():
		return "Installation nur auf dem Handy möglich."
	if not can_install():
		open_permission()
		return "Bitte „Apps installieren“ für Draw2Race erlauben (Android 7: „Unbekannte Herkunft“) und erneut tippen."
	var path := ProjectSettings.globalize_path(file)
	var problem := str(a[0].verify(a[1], path, version))
	if problem != "":
		DirAccess.remove_absolute(file)
		return "Update abgelehnt: " + problem
	return str(a[0].install(a[1], path))

func prune() -> void:
	# Alte Downloads entfernen (nur die aktuelle APK behalten).
	var dir := DirAccess.open(download_dir)
	if dir == null:
		return
	for name in dir.get_files():
		if download_dir + "/" + name != apk_path():
			dir.remove(name)
