extends SceneTree
# Kontrollbild des Siegkonfettis in der Rennansicht. TRACK (Standard city), TIME.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var id := OS.get_environment("TRACK") if OS.get_environment("TRACK") != "" else "city"
	var app: Node = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.store = ProgressStore.new("user://shots_%s.json" % Time.get_ticks_usec())
	app.debug_data()["override"] = {"time": OS.get_environment("TIME") if OS.get_environment("TIME") != "" else "day", "weather": "dry", "fog": 0}
	app.select_track(id)
	app.start_drawing()
	app.recorder.route = app.track.ai_route(1.0)
	app.begin_race()
	for i in range(520):
		await physics_frame
	var v: RaceVehicle = app.vehicles[0]
	app.world.confetti(Vector3(v.pos.x, 0.3, v.pos.y))
	for i in range(45):
		await physics_frame
	for k in range(3):
		await process_frame
	root.get_texture().get_image().save_png("user://confetti_%s.png" % id)
	quit()
