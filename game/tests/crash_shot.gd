extends SceneTree
# Kontrollbilder eines Zusammenstoßes: eigene Linie mit zu hohem Tempo (Kurve wird nicht geschafft). TRACK, SPEED, AT1/AT2 (Bildzeitpunkte in s).
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var id := OS.get_environment("TRACK") if OS.get_environment("TRACK") != "" else "city"
	var speed := float(OS.get_environment("SPEED")) if OS.get_environment("SPEED") != "" else 24.0
	var app: Node = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.store = ProgressStore.new("user://shots_%s.json" % Time.get_ticks_usec())
	app.store.data["sound"] = true
	app.select_track(id)
	app.start_drawing()
	var route: Array[Dictionary] = app.track.ai_route(1.0)
	for p in route:
		p.speed = speed
	app.recorder.route = route
	app.begin_race()
	var shots := [float(OS.get_environment("AT1")) if OS.get_environment("AT1") != "" else 4.5, float(OS.get_environment("AT2")) if OS.get_environment("AT2") != "" else 6.0]
	var t := 0.0
	var k := 0
	while k < shots.size() and t < 30.0:
		await physics_frame
		t += 1.0 / 60.0
		var v: RaceVehicle = app.vehicles[0]
		if v.obstacle_hit > 0.0 or v.wrecked:
			print("t=%.2f stoss=%s %.1f m/s wrack=%s pos=%s" % [t - 3.0, v.obstacle_kind, v.obstacle_hit, v.wrecked, v.pos])
		if t - 3.0 >= shots[k]:
			for i in range(2):
				await process_frame
			root.get_texture().get_image().save_png("user://crash_%s_%d.png" % [id, k])
			k += 1
	print("STOESSE ", app.sound.impact_log, " Phase=", app.phase)
	quit()
