extends SceneTree

# Gruppenfoto aller Premium-Autos auf der Startgeraden (Kontrollbild).
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var app: Node = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.store = ProgressStore.new("user://shots_%s.json" % Time.get_ticks_usec())
	app.debug_data()["override"] = {"time": OS.get_environment("LINEUP_TIME") if OS.get_environment("LINEUP_TIME") != "" else "day", "weather": "dry", "fog": 0}
	app.start_drawing()
	var t: Vector2 = app.track.tangent(0.0)
	var colors := ["f16c4c","5ac4d1","e8c866","a593cf","3a3f47"]
	var i := 0
	for spec in RaceVehicle.CARS:
		var car: Node3D = app.world.car_model(Color(str(spec.color)), false, str(spec.style))
		var p: Vector2 = app.track.at(0.0) + t*(i*2.6-9.1) + t.orthogonal()*(1.2 if i%2 else -1.2)
		car.position = Vector3(p.x,0.2,p.y)
		car.rotation.y = -t.angle()
		i += 1
	app.view_zoom = 12.0
	app.view_focus = Vector3(app.track.at(0.0).x,0,app.track.at(0.0).y)
	for k in range(30):
		await process_frame
	root.get_texture().get_image().save_png("user://car_lineup.png")
	print("SHOT")
	quit()
