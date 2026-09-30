extends SceneTree
# Misst GPU-Zeit (ms) von Hauptbild und Spiegelbild: Ansicht (Zeichen-Übersicht / Rennansicht) x Wetter x Spiegelung.
# TRACK (Standard city), TIME (Standard dusk), Q (Qualität, Standard 1). Ausgabe: COST <Ansicht> <Wetter> …
# Zusatzschalter (Abschalttests): NOSHADOW=1 (Sonnenschatten aus), NOLAMPS=1 (Laternen-Zusatzdurchgang aus).
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var id := OS.get_environment("TRACK") if OS.get_environment("TRACK") != "" else "city"
	var time := OS.get_environment("TIME") if OS.get_environment("TIME") != "" else "dusk"
	var quality := int(OS.get_environment("Q")) if OS.get_environment("Q") != "" else 1
	var app: Node = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.store = ProgressStore.new("user://shots_%s.json" % Time.get_ticks_usec())
	app.select_track(id)
	app.start_drawing()
	var main_rid := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(main_rid, true)
	app.store.data["gfx"] = quality
	var configs := [
		["uebersicht", "dry", "aus"], ["uebersicht", "rain", "aus"], ["uebersicht", "rain", "an"],
		["rennen", "dry", "aus"], ["rennen", "rain", "aus"], ["rennen", "rain", "an"],
	]
	for cfg in configs:
		app.debug_data()["override"] = {"time": time, "weather": cfg[1], "fog": 0}
		app.apply_atmosphere()
		app.set_process(true)
		if cfg[0] == "rennen":
			app.cam_pitch = app.PITCH_RACE
			app.cam_zoom = 24.0
			var s: Vector2 = app.track.at(0.02)
			app.camera_target = Vector3(s.x, 0, s.y)
			app.paused = true
			app.set_camera(app.camera_target)
		else:
			app.paused = false
			app.cam_pitch = PI / 2.0
			app.cam_zoom = app.overview_size()
			app.set_camera(app.track_center())
		var atm = app.world.atmosphere
		atm.reflect_far = cfg[2] == "aus"
		atm.set_process(true)
		if OS.get_environment("NOSHADOW") == "1":
			atm.sun.shadow_enabled = false
		app.set_process(false)          # Kamera und Spiegelgrenze bleiben wie gesetzt
		atm.apply_reflection()
		for k in range(40):
			await process_frame
		var refl_rid := RID()
		if atm.reflection_view != null:
			refl_rid = atm.reflection_view.get_viewport_rid()
			RenderingServer.viewport_set_measure_render_time(refl_rid, true)
		var sum_main := 0.0
		var sum_refl := 0.0
		var tris := 0.0
		var calls := 0.0
		for k in range(60):
			await process_frame
			sum_main += RenderingServer.viewport_get_measured_render_time_gpu(main_rid)
			if refl_rid.is_valid():
				sum_refl += RenderingServer.viewport_get_measured_render_time_gpu(refl_rid)
			tris = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
			calls = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		var reflecting_now: bool = atm.reflecting
		print("COST %-10s %-4s spiegel-%s haupt=%.2f spiegel=%.2f dreiecke=%.2f Mio aufrufe=%d aktiv=%s" % [cfg[0], cfg[1], cfg[2], sum_main / 60.0, sum_refl / 60.0, tris / 1e6, int(calls), reflecting_now])
	quit()
