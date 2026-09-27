extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var app: Node = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.store = ProgressStore.new("user://shots_%s.json" % Time.get_ticks_usec())
	app.store.data["camera_zoom"] = 0.9
	app.select_track("forest")
	app.debug_data()["override"] = {"time": "day", "weather": "dry", "fog": 0}
	app.stage = 1
	app.demo()
	for i in range(700):
		await process_frame
	root.get_texture().get_image().save_png("user://track_marks.png")
	print("SHOT segs=", app.world.tyre_tracks.segments.size(), " sichtbar=", app.world.track_multi.visible_instance_count)
	quit()
