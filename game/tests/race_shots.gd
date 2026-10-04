extends SceneTree
# Kontrollbilder des gemeinsamen Rennens im WLAN (M5) im Handyformat, aus Sicht eines Mitspielers („Shakie“): gemeinsame Ampel,
# Rennen mit Namensschildern, eigener Turbo (Flamme sofort), Hinweis „Verbindung hakt“, Wertung vom Gastgeber. Die anderen sind
# Lobbys im selben Prozess (127.0.0.1, Testports 24805–24807): Anna eröffnet, Ben fährt mit, dazu eine KI.
# Aufruf (20:9):  tools/godot_run.ps1 -Script res://tests/race_shots.gd -Resolution 2400x1080 -Timeout 240
# Bilder: user://race_<name>.png; der Spielstand der Aufnahme wird am Ende gelöscht.
const STORE := "user://race_shots_store.json"
const OVERRIDES := {"game_port": 24805, "discovery_port": 24806, "beacon_port": 24807, "probe_local": true, "use_broadcast": false,
	"use_binding": false, "log_path": ""}
const TRACKS := ["azure", "city", "forest", "harbor", "serra", "fair", "quarry", "arena", "kids"]
const WIFI := {"android": true, "networks": [{"transport": "wifi", "handle": "100", "addresses": ["192.168.178.24/24"]}], "bound": {"transport": "wifi", "handle": "100"},
	"interfaces": [{"name": "wlan0", "address": "192.168.178.24"}], "wifi_gateway": "192.168.178.1"}
const TRACK := "azure"
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
	await frames(3)
	var path := "user://race_%s.png" % name
	root.get_texture().get_image().save_png(path)
	print("SHOT ", ProjectSettings.globalize_path(path))

func other(player_name: String, car: int) -> NetLobby:
	var lb := NetLobby.new()
	lb.tracks = TRACKS.duplicate()
	root.add_child(lb)
	lb.enter(player_name, car)
	others.append(lb)
	return lb

func bot(skill: float, lane := 0.0) -> Array:
	return LineRecorder.plan_to_data(Circuit.load_track(TRACK).ai_route(skill, lane))

func run() -> void:
	NetLobby.overrides = OVERRIDES.merged({"forced_status": WIFI})
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await frames(2)
	app.store = ProgressStore.new(STORE)
	app.store.data["ghost"] = false
	app.store.set_player_name("Shakie")
	app.select_track("city")
	app.car_choice = 0
	app.show_menu()
	var anna := other("Anna", 1)
	anna.host(TRACK, 0)
	var ben := other("Ben", 0)       # Autowahl: dasselbe Auto wie Shakie, andere Spielerfarbe
	ben.join("127.0.0.1", 24805)
	await until(func(): return ben.is_joined)
	app.open_wlan()
	app.net_join("127.0.0.1", 24805, "Anna")
	await until(func(): return app.phase == "net_lobby" and anna.players.size() == 3)
	anna.set_ai(1)
	for lb in [app.lobby, ben]:
		lb.set_ready(true)
	await until(func(): return anna.start_problem() == "")
	anna.start_round()
	await until(func(): return app.phase == "net_round")
	var circuit := Circuit.load_track(TRACK)
	for lb in [anna, ben]:
		lb.report_loaded(circuit.file_hash, circuit)
	await until(func(): return app.phase == "draw", 10000)
	var route: Array[Dictionary] = circuit.ai_route(2.4)
	app.recorder.route = route
	app.recorder.progress = float(app.track.laps)
	app.recorder.complete = true
	app.line_complete()
	app.net_submit()
	anna.draw.submit(bot(2.7, 1.2))
	ben.draw.submit(bot(2.1, -1.2))
	await until(func(): return app.phase == "countdown" and app.countdown < 2.4, 12000)
	await shot("ampel")
	await until(func(): return app.phase == "race" and app.race_time > 4.0, 12000)
	app.turbo_held = true
	await frames(4)
	await shot("turbo")
	app.turbo_held = false
	await until(func(): return app.race_time > 11.0, 12000)
	await shot("rennen")
	# Funkstille: Anna (Gastgeberin) kurz nicht mehr abfragen – Anzeige rechnet kurz weiter, dann der Hinweis
	anna.auto_poll = false
	await until(func(): return app.lobby.race.stale(), 3000)
	await frames(20)
	await shot("hakt")
	anna.auto_poll = true
	await until(func(): return app.phase == "result", 40000)
	await frames(30)
	await shot("wertung")
	await until(func(): return app.lobby.race.final, 40000)
	await frames(5)
	await shot("wertung_final")
	app.show_menu()
	for lb in others:
		lb.exit()
		lb.queue_free()
	await frames(5)
	NetLobby.overrides = {}
	for suffix in ["", ".bak", ".tmp", ".run"]:
		if FileAccess.file_exists(STORE + suffix):
			DirAccess.remove_absolute(STORE + suffix)
	quit()
