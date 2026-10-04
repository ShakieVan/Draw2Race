extends SceneTree
# Kontrollbilder des gemeinsamen Zeichnens im WLAN (M4) im Handyformat, aus Sicht eines Mitspielers („Shakie“): gemeinsames 3-2-1,
# Zeichnen mit dem Stand der anderen (Anna zeichnet, Ben fertig, Clara im Hintergrund), Linie fertig, Warten nach dem Abgeben,
# Enthüllung aller Linien und die Übergabe an M5. Die anderen sind Lobbys im selben Prozess (127.0.0.1, Testports 24790–24792).
# Aufruf (20:9):  tools/godot_run.ps1 -Script res://tests/draw_shots.gd -Resolution 2400x1080 -Timeout 180
# Bilder: user://draw_<name>.png; der Spielstand der Aufnahme wird am Ende gelöscht.
const STORE := "user://draw_shots_store.json"
const OVERRIDES := {"game_port": 24790, "discovery_port": 24791, "beacon_port": 24792, "probe_local": true, "use_broadcast": false,
	"use_binding": false, "log_path": ""}
const TRACKS := ["azure", "city", "forest", "harbor", "serra", "fair", "quarry", "arena", "kids"]
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
	var path := "user://draw_%s.png" % name
	root.get_texture().get_image().save_png(path)
	print("SHOT ", ProjectSettings.globalize_path(path))

func other(player_name: String, car: int) -> NetLobby:
	var lb := NetLobby.new()
	lb.tracks = TRACKS.duplicate()
	root.add_child(lb)
	lb.enter(player_name, car)
	others.append(lb)
	return lb

func bot(id: String, skill: float, lane := 0.0) -> Array:
	return LineRecorder.plan_to_data(Circuit.load_track(id).ai_route(skill, lane))

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
	var anna := other("Anna", 1)
	anna.host("city", 0)
	var ben := other("Ben", 2)
	ben.join("127.0.0.1", 24790)
	var clara := other("Clara", 3)
	clara.join("127.0.0.1", 24790)
	await until(func(): return ben.is_joined and clara.is_joined)
	app.open_wlan()
	app.net_join("127.0.0.1", 24790, "Anna")
	await until(func(): return app.phase == "net_lobby" and anna.players.size() == 4)
	for lb in [app.lobby, ben, clara]:
		lb.set_ready(true)
	await until(func(): return anna.start_problem() == "")
	anna.start_round()
	await until(func(): return app.phase == "net_round")
	var circuit := Circuit.load_track("city")
	for lb in [anna, ben, clara]:
		lb.report_loaded(circuit.file_hash, circuit)
	await until(func(): return app.phase == "net_countdown" and app.lobby.draw.seconds_until(app.lobby.draw.draw_at) < 2.3)
	await shot("countdown")
	await until(func(): return app.phase == "draw")
	# Eigene Linie zu gut 40 %, Anna bei 60 %, Ben fertig, Clara im Hintergrund
	var track: Circuit = app.track
	var pen: LineRecorder = app.recorder
	pen.begin(track.at(0.0), 0.0)
	var clock := 0.0
	var i := 1
	while pen.progress < 0.85:
		clock += 0.035 + 0.03 * (0.5 + 0.5 * sin(i * 0.045))
		pen.sample(track.at(float(i) / 260.0, 1.2 * sin(i * 0.04)), clock)
		i += 1
	pen.end()
	app.refresh_line()
	anna.draw.set_progress(0.6)
	clara.draw.set_progress(0.35)
	ben.draw.submit(bot("city", 2.5, -1.2))
	clara.set_away(true)
	await until(func(): return app.lobby.draw.state_text(ben.my_id()) == "fertig ✓" and app.lobby.player(clara.my_id()).away and int(app.lobby.draw.status_of(1).p) == 60)
	await frames(10)
	await shot("zeichnen")
	# Linie fertig zeichnen
	pen.begin(pen.last_pos, clock)
	while not pen.complete and i < 4000:
		clock += 0.035 + 0.03 * (0.5 + 0.5 * sin(i * 0.045))
		pen.sample(track.at(float(i) / 260.0, 1.2 * sin(i * 0.04)), clock)
		i += 1
	app.line_complete()
	await frames(10)
	await shot("fertig")
	app.net_submit()
	anna.draw.set_progress(0.85)
	await until(func(): return str(anna.draw.status_of(app.lobby.my_id()).st) == "done" and int(app.lobby.draw.status_of(1).p) == 85)
	await frames(10)
	await shot("warten")
	clara.set_away(false)
	anna.draw.submit(bot("city", 3.2, 1.2))
	clara.draw.submit(bot("city", 1.0, 0.0))
	await until(func(): return app.phase == "net_reveal")
	await frames(30)
	await shot("enthuellung")
	await until(func(): return app.phase in ["countdown", "race"])
	await frames(10)
	await shot("start")
	app.show_menu()
	for lb in others:
		if is_instance_valid(lb):
			lb.exit()
			lb.free()
	others.clear()
	await frames(4)
	NetLobby.overrides = {}
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(STORE + suffix):
			DirAccess.remove_absolute(STORE + suffix)
	app.queue_free()
	await frames(2)
	quit(0)
