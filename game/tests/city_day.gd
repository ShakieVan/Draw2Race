extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var app: Node = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.store = ProgressStore.new("user://shots_%s.json" % Time.get_ticks_usec())
	app.select_track("city")
	app.debug_data()["override"] = {"time": OS.get_environment("CITY_TIME") if OS.get_environment("CITY_TIME") != "" else "day", "weather": "dry", "fog": 0}
	app.start_drawing()
	app.view_zoom = 34.0
	for i in range(40):
		await process_frame
	root.get_texture().get_image().save_png("user://city_view.png")
	print("SHOT")
	quit()
