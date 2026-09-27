extends SceneTree

# Kontrollbilder der Premium-Autos aus der Rennkamera (nah), Tag und Nacht mit Regen.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var app: Node = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.store = ProgressStore.new("user://shots_%s.json" % Time.get_ticks_usec())
	app.store.data["camera_zoom"] = float(OS.get_environment("CAR_ZOOM")) if OS.get_environment("CAR_ZOOM") != "" else 0.9
	app.debug_data()["unlock"] = true
	app.car_choice = int(OS.get_environment("CAR_INDEX")) if OS.get_environment("CAR_INDEX") != "" else 0
	var cases := [["day","dry"],["night","rain"]]
	for c in cases:
		app.debug_data()["override"] = {"time": c[0], "weather": c[1], "fog": 0}
		app.stage = 1
		app.demo()
		for i in range(int(OS.get_environment("CAR_FRAMES")) if OS.get_environment("CAR_FRAMES") != "" else 330):
			await process_frame
		root.get_texture().get_image().save_png("user://car_%s_%s.png" % c)
		print("SHOT ", c)
	quit()
