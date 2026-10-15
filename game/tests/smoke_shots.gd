extends SceneTree
# Kontrollbilder des Reifenqualms (nur Darstellung): Drift King in der Drift-Arena auf einer deutlich zu schnellen Linie (ruhige KI-Linie,
# Kurven ×1,85 – damit driftet er mit bicycle-7) bei Tag, Nacht und Regen, dazu das Anfahren aus dem Stand mit durchdrehenden
# Hinterrädern und der Geist eines Drift King auf der Küste (smoke_geist).
# Aufruf (Handyformat):  tools/godot_run.ps1 -Script res://tests/smoke_shots.gd -Resolution 2340x1080 -Timeout 400
# Bilder: user://smoke_<name>.png; ZOOM (0..1, Standard 0,8) = Kamera-Zoom beim Folgen; GFX (0..2, Standard 2) = Grafikstufe, ab
# Stufe 0/1 mit Endung _g0/_g1; ONLY = Szenen mit Komma (start,tag,nacht,regen,geist), Standard alle.
const SCENES := [
	["tag", {"time": "day", "weather": "dry", "fog": 0}],
	["nacht", {"time": "night", "weather": "dry", "fog": 0}],
	["regen", {"time": "day", "weather": "rain", "fog": 0}],
]
var app: Node
var store_path := ""

func _initialize() -> void:
	call_deferred("run")

func wild_route(c: Circuit) -> Array[Dictionary]:
	var wild := c.ai_route(1.5)
	for p in wild:
		if c.curvature(float(p.s)) > 0.03:
			p.speed = float(p.speed) * 1.85
	return wild

func wanted(name: String) -> bool:
	var only := OS.get_environment("ONLY")
	return only == "" or name in only.split(",")

func shot(name: String) -> void:
	for i in range(3):
		await process_frame
	var gfx := int(app.store.data.get("gfx", 2))
	var path := "user://smoke_%s%s.png" % [name, "" if gfx == 2 else "_g%d" % gfx]
	root.get_texture().get_image().save_png(path)
	var v: RaceVehicle = app.vehicles[0]
	var beta := rad_to_deg(absf(wrapf(v.velocity.angle() - v.heading, -PI, PI))) if v.velocity.length() > 1.0 else 0.0
	print("SHOT %s  t=%.2f s  Tempo %.1f m/s  rear_spin %.2f  Schwimmwinkel %.0f°  Lenkung %.2f rad  Qualm %.2f" % [ProjectSettings.globalize_path(path),
		app.race_time, v.velocity.length(), v.rear_spin, beta, v.steering, float(app.models[0].get_node("Smoke").get_meta("power", 0.0))])
	if app.ghost != null and is_instance_valid(app.ghost_model):
		print("      Geist: rear_spin %.2f  Qualm %.2f" % [app.ghost.rear_spin, float(app.ghost_model.get_node("Smoke").get_meta("power", 0.0))])

func start(conditions: Dictionary) -> void:
	app.debug_data()["override"] = conditions
	app.car_choice = 7
	app.stage = 0
	app.start_drawing()
	app.recorder.route = wild_route(app.track)
	app.recorder.complete = true
	app.begin_race()

func ghost_shot() -> void:
	# Küste bei Tag: eigenes Allrad-Auto auf ruhiger Linie, daneben der Geist eines Drift King beim Anfahren – sein Qualm ist
	# durchscheinend (fade 0,35). Die Geisterdatei liegt in einem eigenen Verzeichnis (app.ghost_dir), die des Spielers bleiben unberührt.
	app.select_track("azure")
	app.stage = 0
	app.ghost_dir = store_path.get_basename() + "_ghosts"
	var path: String = app.ghost_path()
	DirAccess.make_dir_recursive_absolute(app.ghost_dir)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"physics": RaceVehicle.VERSION, "track_hash": app.track.file_hash, "car": 7, "time": 30.0,
		"plan": LineRecorder.plan_to_data(app.track.ai_route(1.5)), "turbo": []}))
	file.close()
	app.store.data["ghost"] = true
	app.debug_data()["override"] = SCENES[0][1]
	app.car_choice = 0
	app.start_drawing()
	app.recorder.route = app.track.ai_route(2.3)
	app.recorder.complete = true
	app.begin_race()
	while app.phase != "race" or app.race_time < 1.0:
		await physics_frame
	await shot("geist")
	app.store.data["ghost"] = false
	app.show_menu()
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(app.ghost_dir)

func run() -> void:
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	store_path = "user://smoke_shots_%s.json" % Time.get_ticks_usec()
	app.store = ProgressStore.new(store_path)
	app.store.data["camera_zoom"] = float(OS.get_environment("ZOOM")) if OS.get_environment("ZOOM") != "" else 0.8
	app.store.data["ghost"] = false
	app.store.data["sound"] = false
	app.store.data["gfx"] = int(OS.get_environment("GFX")) if OS.get_environment("GFX") != "" else 2
	app.debug_data()["unlock"] = true
	app.select_track("arena")
	# Anfahren aus dem Stand: Hinterräder drehen durch, das Auto rollt erst an (Qualm, schwarze Startstreifen).
	start(SCENES[0][1])
	while app.phase != "race" or app.race_time < 0.7:
		await physics_frame
	if wanted("start"):
		await shot("start")
	for scene in SCENES:
		if not wanted(scene[0]):
			continue
		if scene[0] != "tag":
			start(scene[1])
			while app.phase != "race":
				await physics_frame
		# Erst fotografieren, wenn der Drift schon eine Weile qualmt (die Wolke hängt dann hinter dem Auto).
		var streak := 0
		while app.phase == "race" and app.race_time < 40.0 and (app.race_time < 6.0 or streak < 50):
			await physics_frame
			streak = streak + 1 if float(app.models[0].get_node("Smoke").get_meta("power", 0.0)) > 0.6 else 0
		await shot(scene[0])
		# Zweites Bild etwas später (anderer Drift, andere Kurve).
		var later: float = app.race_time + 6.0
		streak = 0
		while app.phase == "race" and app.race_time < 45.0 and (app.race_time < later or streak < 40):
			await physics_frame
			streak = streak + 1 if float(app.models[0].get_node("Smoke").get_meta("power", 0.0)) > 0.6 else 0
		await shot(scene[0] + "_2")
	app.show_menu()
	if wanted("geist"):
		await ghost_shot()
	for suffix in ["", ".bak", ".tmp", ".run"]:
		if FileAccess.file_exists(store_path + suffix):
			DirAccess.remove_absolute(store_path + suffix)
	quit()
