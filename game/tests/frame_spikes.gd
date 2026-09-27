extends SceneTree
# Rechenzeit je Bild während eines Rennens: Mittel und Spitzen (Ruckler-Suche).
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var app: Node = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.store = ProgressStore.new("user://shots_%s.json" % Time.get_ticks_usec())
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for id in ["city","forest"]:
		app.select_track(id)
		app.debug_data()["override"] = {"time": "day", "weather": "dry", "fog": 0}
		app.stage = 2
		app.demo()
		for i in range(240):
			await process_frame
		var proc: Array[float] = []
		var phys: Array[float] = []
		var tracks_ms: Array[float] = []
		for i in range(600):
			await process_frame
			proc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
			phys.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		proc.sort()
		phys.sort()
		print("FPS ", Engine.get_frames_per_second())
		print("RUCKLER %-7s Bildlogik: Mittel %.2f ms, 99%% %.2f ms, max %.2f | Physik: Mittel %.2f, 99%% %.2f, max %.2f" % [id,
			proc.reduce(func(a,b): return a+b)/proc.size(), proc[int(proc.size()*0.99)], proc[-1],
			phys.reduce(func(a,b): return a+b)/phys.size(), phys[int(phys.size()*0.99)], phys[-1]])
	quit()
