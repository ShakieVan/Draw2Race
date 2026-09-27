extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var app: Node = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.store = ProgressStore.new("user://shots_%s.json" % Time.get_ticks_usec())
	for i in range(10):
		await process_frame
	app.debug_data()["override"] = {"time":"dusk","weather":"snow","fog":1}
	app.hud.menu()
	for i in range(10):
		await process_frame
	root.get_texture().get_image().save_png("user://settings.png")
	print("SHOT")
	quit()
