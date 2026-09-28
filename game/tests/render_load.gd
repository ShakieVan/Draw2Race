extends SceneTree
# Gezeichnete Dreiecke und Zeichenaufrufe je Bild (Leistungsprüfung der Kulisse).
func _initialize() -> void:
	call_deferred("run")
func measure(label: String) -> void:
	for i in range(8):
		await process_frame
	var tris := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var calls := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	print("LAST %-28s %8.2f Mio. Dreiecke  %5d Aufrufe" % [label, tris / 1e6, calls])
func run() -> void:
	var app: Node = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.store = ProgressStore.new("user://shots_%s.json" % Time.get_ticks_usec())
	for id in (OS.get_environment("ONLY").split(",") if OS.get_environment("ONLY") != "" else app.TRACKS):
		app.select_track(id)
		for tod in ["day","night"]:
			app.debug_data()["override"] = {"time": tod, "weather": "dry", "fog": 0}
			app.start_drawing()
			await measure("%s %s Übersicht" % [id, tod])
			app.demo()
			for i in range(200):
				await process_frame
			await measure("%s %s Rennen" % [id, tod])
	quit()
