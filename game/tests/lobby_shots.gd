extends SceneTree
# Kontrollbilder des WLAN-Mehrspielers (M3) im Handyformat: Eröffnen/Beitreten mit gefundenen Spielen, Hinweis ohne WLAN,
# Adresseingabe, Lobby beim Gastgeber (drei im selben Auto, je eigene Farbe) und bei einem Mitspieler, Garage (Autowahl in der
# Spielerfarbe), Startbildschirm und die Meldung, wenn der Gastgeber beendet.
# Die anderen Spieler sind Lobbys im selben Prozess (127.0.0.1, Testports 24790–24792); der Netzstatus ist vorgegeben (Android-WLAN).
# Aufruf (20:9):  tools/godot_run.ps1 -Script res://tests/lobby_shots.gd -Resolution 2400x1080 -Timeout 180
# Bilder: user://lobby_<name>.png; der Spielstand der Aufnahme wird am Ende gelöscht.
const STORE := "user://lobby_shots_store.json"
const OVERRIDES := {"game_port": 24790, "discovery_port": 24791, "beacon_port": 24792, "probe_local": true, "use_broadcast": false,
	"use_binding": false, "log_path": ""}
const TRACKS := ["azure", "city", "forest", "harbor", "serra", "fair", "quarry", "arena", "kids"]
const WIFI := {"android": true, "networks": [{"transport": "wifi", "handle": "100", "addresses": ["192.168.178.24/24"]}], "bound": {"transport": "wifi", "handle": "100"},
	"interfaces": [{"name": "wlan0", "address": "192.168.178.24"}], "wifi_gateway": "192.168.178.1"}
const NO_WIFI := {"android": true, "networks": [{"transport": "mobile", "addresses": ["10.64.12.7/30"]}], "interfaces": [{"name": "rmnet_data0", "address": "10.64.12.7"}]}
var app: Node
var others: Array = []

func _initialize() -> void:
	call_deferred("run")

func frames(n: int) -> void:
	for i in range(n):
		await process_frame

func until(done: Callable, timeout_ms := 5000) -> void:
	var end := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < end and not done.call():
		await process_frame

func shot(name: String) -> void:
	await frames(4)
	var path := "user://lobby_%s.png" % name
	root.get_texture().get_image().save_png(path)
	print("SHOT ", ProjectSettings.globalize_path(path))

func other(player_name: String, car: int) -> NetLobby:
	NetLobby.overrides = OVERRIDES
	var lb := NetLobby.new()
	lb.tracks = TRACKS.duplicate()
	root.add_child(lb)
	lb.enter(player_name, car)
	NetLobby.overrides = OVERRIDES.merged({"forced_status": WIFI})
	others.append(lb)
	return lb

func clear_others() -> void:
	for lb in others:
		if is_instance_valid(lb):
			lb.exit()
			lb.free()
	others.clear()

func run() -> void:
	NetLobby.overrides = OVERRIDES.merged({"forced_status": WIFI})
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await frames(2)
	app.store = ProgressStore.new(STORE)
	app.store.data["ghost"] = false
	app.store.set_player_name("Shakie")
	app.select_track("azure")
	app.car_choice = 0
	app.show_menu()
	# Eröffnen / Beitreten mit zwei gefundenen Spielen (eins passt nicht zur Version)
	var anna := other("Anna", 1)
	anna.host("city", 1)
	var ben := other("Ben", 2)
	ben.join("127.0.0.1", 24790)
	app.hud.party_ui.mode_dialog()
	await shot("auswahl")
	app.hud.close_overlays()
	app.open_wlan()
	await until(func(): return app.lobby.games().size() == 1 and int(app.lobby.games()[0].players) == 2)
	var now := Time.get_ticks_msec()
	app.lobby.discovery.games["alt"] = {"address": "192.168.178.31", "addresses": ["192.168.178.31"], "port": 24680, "name": "Lukas",
		"players": 1, "max": 4, "game": "0.2.28", "physics": "bicycle-5", "proto": 1, "compatible": false, "note": "andere Version 0.2.28",
		"busy": false, "via": {"bcast": 1}, "first_ms": 900, "last_ms": now + 60000, "sid": "alt"}
	app.lobby.games_changed.emit()
	await shot("wlan")
	app.lobby.forced_status = NO_WIFI
	app.lobby.refresh_status()
	await shot("kein_wlan")
	app.lobby.forced_status = WIFI
	app.lobby.refresh_status()
	app.hud.lobby_ui.address_dialog()
	await shot("adresse")
	app.hud.lobby_ui.close_dialogs()
	await frames(2)
	# Mitspieler-Ansicht: Anna ist Gastgeberin, Ben bereit, Clara im Hintergrund
	var clara := other("Clara", 3)
	clara.join("127.0.0.1", 24790)
	await until(func(): return clara.is_joined and ben.is_joined)
	app.net_join("127.0.0.1", 24790, "Anna")
	await until(func(): return app.phase == "net_lobby" and anna.players.size() == 4)
	ben.set_ready(true)
	clara.set_away(true)
	await until(func(): return app.lobby.players.size() == 4 and app.lobby.players.any(func(p): return p.away))
	await frames(70)   # Ping-Werte (geglättet, einmal je Sekunde)
	await shot("mitspieler")
	app.lobby.set_ready(true)
	clara.set_away(false)
	clara.set_ready(true)
	await until(func(): return anna.start_problem() == "")
	anna.start_round()
	await until(func(): return app.phase == "net_round")
	anna.report_loaded(NetLobby.track_file_hash("city"))
	for lb in [ben, clara]:
		lb.report_loaded(NetLobby.track_file_hash("city"))
	await until(func(): return app.lobby.phase == "ready")
	await shot("start")
	anna.leave()
	await until(func(): return app.phase == "menu")
	await shot("meldung")
	app.hud.close_overlays()
	clear_others()
	await frames(10)
	# Gastgeber-Ansicht: Hafen, Stufe 3, Ben bereit, Clara wählt noch, ein Platz frei
	app.open_wlan()
	app.net_host()
	app.lobby.set_track("harbor")
	app.lobby.set_stage(2)
	ben = other("Ben", 0)
	ben.join("127.0.0.1", 24790)
	clara = other("Clara", 0)
	clara.join("127.0.0.1", 24790)
	await until(func(): return app.lobby.players.size() == 3 and ben.is_joined and clara.is_joined)
	app.lobby.set_ai(1)
	ben.set_ready(true)
	await until(func(): return app.lobby.player(ben.my_id()).ready)
	await frames(70)
	await shot("gastgeber")
	app.net_garage()
	await frames(20)
	await shot("garage")
	app.close_garage()
	app.show_menu()
	clear_others()
	await frames(4)
	NetLobby.overrides = {}
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(STORE + suffix):
			DirAccess.remove_absolute(STORE + suffix)
	app.queue_free()
	await frames(2)
	quit(0)
