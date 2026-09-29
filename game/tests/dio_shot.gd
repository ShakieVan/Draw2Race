extends SceneTree
# Kontrollbilder einer Strecke mit Diorama: Zeichen-Übersicht (senkrecht) und geneigte Nahansicht wie im Rennen.
# TRACK (Standard city), TIME (day|dusk|night, Standard day).
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
	for k in range(40):
		await process_frame
	root.get_texture().get_image().save_png("user://dio_%s_%s_uebersicht.png" % [id, time])
	# Geneigte Nahansicht (wie Rennkamera) auf den Startbereich.
	app.cam_pitch = app.PITCH_RACE
	app.cam_zoom = 26.0
	var s: Vector2 = app.track.at(float(OS.get_environment("AT")) if OS.get_environment("AT") != "" else 0.02)
	app.camera_target = Vector3(s.x, 0, s.y)
	app.paused = true
	app.set_camera(app.camera_target)
	for k in range(10):
		await process_frame
	root.get_texture().get_image().save_png("user://dio_%s_%s_nah.png" % [id, time])
	quit()
