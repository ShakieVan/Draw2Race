extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var app: Node = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.store = ProgressStore.new("user://shots_%s.json" % Time.get_ticks_usec())
	app.store.data["camera_zoom"] = 0.7
	app.select_track("city")
	app.debug_data()["override"] = {"time": "night", "weather": "rain", "fog": 0}
	app.stage = 0
	app.demo()
	for i in range(300):
		await process_frame
	root.get_texture().get_image().save_png("user://night_city.png")
	print("SHOT")
	quit()
