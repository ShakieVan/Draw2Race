extends SceneTree
# Kontrollbilder der Rennansicht (TRACK, TIME, WEATHER): mitten in der Fahrt, an der Kreuzung und im Ziel.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var id := OS.get_environment("TRACK") if OS.get_environment("TRACK") != "" else "city"
	var time := OS.get_environment("TIME") if OS.get_environment("TIME") != "" else "day"
	var app: Node = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.store = ProgressStore.new("user://shots_%s.json" % Time.get_ticks_usec())
	app.debug_data()["override"] = {"time": time, "weather": OS.get_environment("WEATHER") if OS.get_environment("WEATHER") != "" else "dry", "fog": 0}
	app.select_track(id)
	if OS.get_environment("STAGE") != "":
		app.stage = int(OS.get_environment("STAGE"))
	app.store.data["debug"]["unlock"] = true
	if OS.get_environment("CAR") != "":
		app.car_choice = int(OS.get_environment("CAR"))
	app.start_drawing()
	app.recorder.route = app.track.ai_route(1.0)
	app.begin_race()
	for stage in [[100, "gitter"], [500, "start"], [300, "kurve"]]:
		for i in range(stage[0]):
			await physics_frame
		for k in range(4):
			await process_frame
		root.get_texture().get_image().save_png("user://race_%s_%s_%s.png" % [id, time, stage[1]])
	quit()
