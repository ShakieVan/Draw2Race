extends SceneTree
# Kontrollbilder des Loopings auf einer echten Strecke (TRACK, Standard quarry): Spielkamera während der
# Durchfahrt (Einfahrt, oben) und eine seitliche Zusatzkamera quer zur Fahrtrichtung.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var id := OS.get_environment("TRACK") if OS.get_environment("TRACK") != "" else "quarry"
	var app: Node = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.store = ProgressStore.new("user://shots_%s.json" % Time.get_ticks_usec())
	app.store.data["camera_zoom"] = 0.75
	app.debug_data()["override"] = {"time": "day", "weather": "dry", "fog": 0}
	app.select_track(id)
	app.demo()
	var loop: Dictionary = app.track.loops[0]
	var s := float(loop.s)
	var r := float(loop.radius)
	var shots := {"ein": false, "oben": false}
	if OS.get_environment("SLOW") != "":
		# Zu langsam: im Anlauf (35 m) nur 9 m/s geplant – reicht nicht über den Scheitel.
		for p in app.vehicles[0].route:
			var before: float = fposmod(float(loop.s) - float(p.s), 1.0) * app.track.length
			if before < 35.0:
				p.speed = minf(float(p.speed), float(OS.get_environment("SLOW")))
		var frames := 0
		var crash_at := -1
		# Feste Schrägkamera auf den Looping (seitlich-hinten, erhöht).
		var o0: Vector2 = app.track.at(s)
		var f0: Vector2 = app.track.tangent(s)
		var side0 := Vector2(-f0.y, f0.x)
		var b0: float = app.track.base_height(s)
		var cam0 := Camera3D.new()
		cam0.fov = 50.0
		app.add_child(cam0)
		cam0.position = Vector3(o0.x - f0.x * 7.0 - side0.x * 10.0, b0 + r + 5.0, o0.y - f0.y * 7.0 - side0.y * 10.0)
		cam0.look_at(Vector3(o0.x, b0 + r * 0.6, o0.y), Vector3.UP)
		cam0.current = true
		for i in range(6000):
			await process_frame
			var v: RaceVehicle = app.vehicles[0]
			if v.in_loop and frames == 0 and v.loop_theta > 1.2:
				root.get_texture().get_image().save_png("user://loop_%s_slow_1.png" % id); frames = 1
			if v.crashed and crash_at < 0:
				crash_at = i
				print("Ende: zurückgerollt=%s gefallen=%s Winkel %.0f Grad" % [v.rolled_back, v.loop_fall, rad_to_deg(v.loop_theta)])
			if v.in_loop and v.loop_speed < 0.0 and frames == 1 and v.loop_theta < 0.9:
				root.get_texture().get_image().save_png("user://loop_%s_slow_2.png" % id); frames = 2
			if v.crashed and v.loop_fall and frames == 1 and crash_at >= 0 and i == crash_at + 4:
				root.get_texture().get_image().save_png("user://loop_%s_slow_2.png" % id); frames = 2
			for k in [[14, 3], [30, 4], [90, 5]]:
				if crash_at >= 0 and i == crash_at + int(k[0]):
					root.get_texture().get_image().save_png("user://loop_%s_slow_%d.png" % [id, int(k[1])])
			if crash_at >= 0 and i == crash_at + 90:
				break
			if v.finish_time >= 0.0 or (v.progress > float(loop.s) + 0.05 and not v.in_loop and not v.crashed):
				print("KEIN ABSTURZ"); break
		quit()
		return
	for i in range(6000):
		await process_frame
		var v: RaceVehicle = app.vehicles[0]
		if v.in_loop and v.loop_theta > 0.9 and not shots.ein:
			root.get_texture().get_image().save_png("user://loop_%s_ein.png" % id); shots.ein = true
		if v.in_loop and v.loop_theta > 2.9 and not shots.oben:
			root.get_texture().get_image().save_png("user://loop_%s_oben.png" % id); shots.oben = true
			# Seitenansicht im selben Moment: Kamera quer zur Fahrtrichtung, auf Höhe der Ringmitte.
			var o: Vector2 = app.track.at(s)
			var f: Vector2 = app.track.tangent(s)
			var side := Vector2(-f.y, f.x)
			var base: float = app.track.base_height(s)
			var cam := Camera3D.new()
			cam.fov = 45.0
			app.add_child(cam)
			var eye: Vector2 = o + side * 16.0
			cam.position = Vector3(eye.x, base + r + 1.5, eye.y)
			cam.look_at(Vector3(o.x, base + r, o.y), Vector3.UP)
			cam.current = true
			await process_frame
			await process_frame
			root.get_texture().get_image().save_png("user://loop_%s_seite.png" % id)
			cam.position = Vector3(o.x - f.x * 18.0 + side.x * 3.0, base + r + 3.0, o.y - f.y * 18.0 + side.y * 3.0)
			cam.look_at(Vector3(o.x, base + r, o.y), Vector3.UP)
			await process_frame
			await process_frame
			root.get_texture().get_image().save_png("user://loop_%s_vorn.png" % id)
			cam.position = Vector3(o.x - f.x * 9.0 - side.x * 9.0, base + r + 9.0, o.y - f.y * 9.0 - side.y * 9.0)
			cam.look_at(Vector3(o.x, base + r * 0.7, o.y), Vector3.UP)
			await process_frame
			await process_frame
			root.get_texture().get_image().save_png("user://loop_%s_schraeg.png" % id)
			break
		if v.crashed or v.finish_time >= 0.0:
			break
	print("LOOP SHOTS ", shots)
	quit()
