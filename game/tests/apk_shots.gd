extends SceneTree
# Kontrollbilder „Neuere Version weitergeben“ (NetApk, ApkShare) im Handyformat: Liste mit neuerer Version, Ablehnung mit Angebot,
# Laden mit Fortschritt, fertig geprüft, Angebot beim Gastgeber und der Teilen-Dialog. Die Gegenseite ist eine Lobby im selben Prozess
# (127.0.0.1, Testports 24790–24793) mit einer Zufallsdatei als „APK“; das eigene Spiel meldet sich als 0.2.31 an.
# Aufruf:  tools/godot_run.ps1 -Script res://tests/apk_shots.gd -Resolution 1600x720 -Timeout 120
# Bilder: user://apk_<name>.png; Spielstand und Testdateien werden am Ende gelöscht.
const STORE := "user://apk_shots_store.json"
const OVERRIDES := {"game_port": 24790, "discovery_port": 24791, "beacon_port": 24792, "probe_local": true, "use_broadcast": false,
	"use_binding": false, "log_path": "", "apk_port": 24793, "apk_dir": "user://apktest/shots/empfang"}
const WIFI := {"android": true, "networks": [{"transport": "wifi", "handle": "100", "addresses": ["192.168.178.24/24"]}], "bound": {"transport": "wifi", "handle": "100"},
	"interfaces": [{"name": "wlan0", "address": "192.168.178.24"}], "wifi_gateway": "192.168.178.1"}
var app: Node
var others: Array = []

func _initialize() -> void:
	call_deferred("run")

func frames(n: int) -> void:
	for i in range(n):
		await process_frame

func until(done: Callable, timeout_ms := 8000) -> void:
	var end := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < end and not done.call():
		await process_frame

func shot(name: String) -> void:
	await frames(4)
	var path := "user://apk_%s.png" % name
	root.get_texture().get_image().save_png(path)
	print("SHOT ", ProjectSettings.globalize_path(path))

func make_file(path: String, mb: int) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	var crypto := Crypto.new()
	for i in range(mb):
		f.store_buffer(crypto.generate_random_bytes(1048576))
	f.close()

func other(player_name: String, share: ApkShare, extra := {}) -> NetLobby:
	NetLobby.overrides = OVERRIDES.merged(extra, true)
	var lb := NetLobby.new()
	lb.tracks = ["azure", "city"]
	lb.apk = share
	root.add_child(lb)
	lb.enter(player_name, 0)
	NetLobby.overrides = OVERRIDES.merged({"forced_status": WIFI})
	others.append(lb)
	return lb

func share_of(override: Dictionary) -> ApkShare:
	var sh := ApkShare.new()
	sh.source_override = override
	root.add_child(sh)
	return sh

func run() -> void:
	make_file("user://apktest/shots/anna.bin", 24)
	make_file("user://apktest/shots/ben.bin", 4)
	NetLobby.overrides = OVERRIDES.merged({"forced_status": WIFI})
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await frames(2)
	app.store = ProgressStore.new(STORE)
	app.store.data["ghost"] = false
	app.store.set_player_name("Shakie")
	app.select_track("azure")
	app.show_menu()
	app.apk_share.source_override = {"receive": true}
	# Anna eröffnet mit der neueren Version (0.2.32 gegenüber 0.2.31 dieses Handys)
	var anna := other("Anna", share_of({"path": "user://apktest/shots/anna.bin", "version": NetProtocol.game_version(), "receive": true}), {"apk_rate": 3 * 1048576})
	await until(func(): return anna.apk.sha256 != "")
	anna.host("city", 1)
	app.open_wlan()
	app.lobby.hello_override = {"game": "0.2.31"}
	await until(func(): return app.lobby.games().size() == 1)
	var now := Time.get_ticks_msec()
	app.lobby.discovery.games["neu"] = {"address": "192.168.178.31", "addresses": ["192.168.178.31"], "port": 24680, "name": "Lukas",
		"players": 1, "max": 4, "game": "0.2.33", "physics": "bicycle-5", "proto": 8, "compatible": false, "note": "andere Version 0.2.33",
		"busy": false, "via": {"bcast": 1}, "first_ms": 900, "last_ms": now + 60000, "sid": "neu"}
	for g in app.lobby.discovery.games.values():
		if g.name == "Anna":
			g.compatible = false
			g.note = "andere Version"
	app.lobby.games_changed.emit()
	await shot("liste")
	app.lobby.discovery.games.erase("neu")
	app.net_join("127.0.0.1", 24790, "Anna")
	await until(func(): return app.hud.content.has_node("ApkDialog"))
	await shot("angebot")
	app.hud.lobby_ui._apk_action()
	await until(func(): return int(app.lobby.transfer.progress().get("received", 0)) > 8 * 1048576 and float(app.lobby.transfer.progress().eta) > 0.0)
	await shot("laden")
	await until(func(): return app.lobby.transfer.progress_raw().get("state") == "done", 15000)
	await shot("fertig")
	app.hud.lobby_ui.close_dialogs()
	app.lobby.exit()
	anna.exit()
	await frames(4)
	# Gastgeber-Ansicht: Ben hat die neuere Version 9.9.9 und bietet sie an
	app.open_wlan()
	app.lobby.hello_override = {}
	app.net_host()
	var ben := other("Ben", share_of({"path": "user://apktest/shots/ben.bin", "version": "9.9.9", "receive": true}), {"apk_port": 24794})
	ben.hello_override = {"game": "9.9.9"}
	await until(func(): return ben.apk.sha256 != "")
	ben.join("127.0.0.1", 24790)
	await until(func(): return app.hud.content.has_node("ApkDialog"))
	await frames(10)
	await shot("gastgeber")
	app.hud.lobby_ui.close_dialogs()
	app.show_menu()
	# Teilen-Dialog (am PC nur zur Ansicht; Größe wie die echte APK)
	app.apk_share.info = {"size": 325 * 1048576, "version": NetProtocol.game_version()}
	app.hud.share_dialog()
	await shot("teilen")
	app.hud.close_overlays()
	for lb in others:
		if is_instance_valid(lb):
			lb.exit()
			lb.free()
	NetLobby.overrides = {}
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(STORE + suffix)
	for f in ["anna.bin", "ben.bin"]:
		DirAccess.remove_absolute("user://apktest/shots/" + f)
	var dir := DirAccess.open("user://apktest/shots/empfang")
	if dir != null:
		for f in dir.get_files():
			dir.remove(f)
	print("APK-SHOTS FERTIG")
	quit()
