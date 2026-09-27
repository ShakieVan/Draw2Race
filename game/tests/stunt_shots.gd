extends SceneTree
# Sichtprüfung der 2,5D-Bauteile auf einer Testvariante der Küstenstrecke.
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var app: Node = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.store = ProgressStore.new("user://shots_%s.json" % Time.get_ticks_usec())
	app.store.data["camera_zoom"] = 0.75
	var t: Circuit = Circuit.load_track("azure")
	var m := func(x: float) -> float: return x / t.length
	t.ramps = [{"s": m.call(6.0), "length": 5.0, "height": 1.6}]
	t.gaps = [{"from": m.call(11.05), "to": m.call(19.0)}]
	t.loops = [{"s": 0.47, "radius": 3.5}]
	t.elevation = [[0.0, 0.0], [0.58, 0.0], [0.68, 3.0], [0.8, 3.0], [0.9, 0.0]]
	app.track = t
	app.world.queue_free()
	app.world = Diorama.new()
	app.add_child(app.world)
	app.move_child(app.world, 0)
	app.world.build(t)
	app.apply_atmosphere()
	app.demo()
	var shots := {"flug": false, "loop": false, "bruecke": false}
	for i in range(3000):
		await process_frame
		var v: RaceVehicle = app.vehicles[0]
		if v.airborne and not shots.flug and v.z > 1.4:
			root.get_texture().get_image().save_png("user://stunt_flug.png"); shots.flug = true; print("SHOT flug")
		if v.in_loop and v.loop_theta > 2.4 and not shots.loop:
			root.get_texture().get_image().save_png("user://stunt_loop.png"); shots.loop = true; print("SHOT loop")
		if v.z > 2.8 and not v.airborne and not v.in_loop and not shots.bruecke:
			root.get_texture().get_image().save_png("user://stunt_bruecke.png"); shots.bruecke = true; print("SHOT bruecke dist=", v.track.center_distance(v.pos), " s=", v.previous_phase, " z=", v.z, " base=", v.track.base_height(v.previous_phase))
		if shots.values().all(func(x): return x) or v.crashed or v.finish_time >= 0:
			break
	var vv: RaceVehicle = app.vehicles[0]
	print("ENDE crashed=", vv.crashed, " air=", vv.air_time, " progress=", vv.progress, " phase=", app.phase, " ramps=", vv.track.ramps.size(), " same=", vv.track == t)
	quit()
