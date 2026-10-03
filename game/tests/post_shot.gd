extends SceneTree
# Kontrollbild Randpfosten der Schotterpiste (Circuit.edge_posts): Nahansicht wie im Rennen, einige Holzpfosten umgefahren
# (Zustand wie RaceVehicle.post_state, nur fürs Bild). TRACK (Standard quarry), AT (Streckenanteil), TIME, DOWN (Anzahl umgefahrener
# Pfosten nahe AT, Standard 3). Ablage: user://post_<track>_<time>.png
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var id := OS.get_environment("TRACK") if OS.get_environment("TRACK") != "" else "quarry"
	var time := OS.get_environment("TIME") if OS.get_environment("TIME") != "" else "day"
	var app: Node = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.store = ProgressStore.new("user://shots_%s.json" % Time.get_ticks_usec())
	app.debug_data()["override"] = {"time": time, "weather": "dry", "fog": 0}
	app.select_track(id)
	app.start_drawing()
	for k in range(40):
		await process_frame
	var at := float(OS.get_environment("AT")) if OS.get_environment("AT") != "" else 0.2
	var down := int(OS.get_environment("DOWN")) if OS.get_environment("DOWN") != "" else 3
	var state := {}
	var near: Array = []
	for post in app.track.edge_posts:
		if not post.stone and absf(float(post.s) - at) < 0.03:
			near.append(post)
	for k in range(mini(down, (near.size() + 1) / 2)):   # jeden zweiten Pfosten (sonst Index hinter dem Ende)
		var post: Dictionary = near[k * 2]
		state[int(post.o)] = {"load": 9.0, "down": true, "dir": app.track.tangent(float(post.s)).rotated(0.3 * post.side)}
	app.world.update_edge_posts(state)
	for k in range(30):
		await process_frame
		app.world.update_edge_posts(state)
	app.cam_pitch = app.PITCH_RACE
	app.cam_zoom = 18.0
	var s: Vector2 = app.track.at(at)
	app.camera_target = Vector3(s.x, app.track.surface_z(at), s.y)
	app.paused = true
	app.set_camera(app.camera_target)
	for k in range(10):
		await process_frame
	root.get_texture().get_image().save_png("user://post_%s_%s.png" % [id, time])
	print("Pfosten %d, umgefahren %d" % [app.track.edge_posts.size(), state.size()])
	quit()
