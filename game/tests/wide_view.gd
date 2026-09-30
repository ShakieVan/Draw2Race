extends SceneTree
# Weitwinkelbild der ganzen Diorama-Stadt von oben (nur zur Kontrolle der Bebauung). TRACK, TIME, ZOOM (Meter, Standard 220).
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var id := OS.get_environment("TRACK") if OS.get_environment("TRACK") != "" else "city"
	var time := OS.get_environment("TIME") if OS.get_environment("TIME") != "" else "day"
	var app: Node = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.store = ProgressStore.new("user://shots_%s.json" % Time.get_ticks_usec())
	app.debug_data()["override"] = {"time": time, "weather": "dry", "fog": 0}
	app.select_track(id)
	app.start_drawing()
	for k in range(30):
		await process_frame
	app.paused = true
	app.cam_pitch = PI / 2.0
	app.cam_zoom = float(OS.get_environment("ZOOM")) if OS.get_environment("ZOOM") != "" else 220.0
	app.set_camera(app.track_center())
	app.world.atmosphere.reflect_far = true
	for k in range(10):
		await process_frame
	root.get_texture().get_image().save_png("user://weit_%s_%s.png" % [id, time])
	quit()
