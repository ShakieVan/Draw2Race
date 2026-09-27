extends SceneTree

# Bildschirmfotos aller Strecken in der Zeichenansicht (mit Fenster).
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var app: Node = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.store = ProgressStore.new("user://shots_%s.json" % Time.get_ticks_usec())
	for i in range(8):
		await process_frame
	root.get_texture().get_image().save_png("user://track_menu.png")
	for id in (OS.get_environment("ONLY").split(",") if OS.get_environment("ONLY") != "" else app.TRACKS):
		app.select_track(id)
		app.start_drawing()
		for i in range(40):
			await process_frame
		root.get_texture().get_image().save_png("user://track_%s.png" % id)
		print("TRACK ", id)
	quit()
