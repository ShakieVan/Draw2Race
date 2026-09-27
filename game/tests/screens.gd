extends SceneTree

# Bildschirmfotos aller Ansichten zur Layoutprüfung (mit Fenster, z. B. --resolution 1560x720).
# Aufruf: Godot --path game --resolution 1560x720 --script res://tests/screens.gd

var app: Node

func shot(name: String) -> void:
	for i in range(8):
		await process_frame
	var path := "user://screen_%s.png" % name
	root.get_texture().get_image().save_png(path)
	print("SCREEN ", ProjectSettings.globalize_path(path))

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.store = ProgressStore.new("user://screens_%s.json" % Time.get_ticks_usec())
	await shot("menu")
	app.hud.settings()
	await shot("optionen")
	app.start_drawing()
	var track: Circuit = app.track
	app.recorder.begin(track.at(0.0), 0.0)
	for i in range(1, 300):
		app.recorder.sample(track.at(float(i)/240.0, 1.5*sin(i*0.05)), float(i)*0.05)
	app.world.draw_route(app.recorder.route)
	await shot("zeichnen")
	app.hud.help_overlay()
	await shot("fahrhilfe")
	app.start_drawing()
	app.recorder.route = track.ai_route(1.0)
	app.begin_race()
	for i in range(420):
		await physics_frame
	await shot("rennen")
	for i in range(3000):
		app._physics_process(1.0/60.0)
		if app.phase == "result":
			break
	await shot("ergebnis")
	quit()
