extends SceneTree
# Kontrollbild Hafen: Kräne und Frachter an der Kaikante (Spielkamera nah und Schrägansicht).
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var app: Node = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.store = ProgressStore.new("user://shots_%s.json" % Time.get_ticks_usec())
	app.debug_data()["override"] = {"time": "day", "weather": "dry", "fog": 0}
	app.select_track("harbor")
	app.start_drawing()
	app.view_zoom = 14.0
	app.view_focus = Vector3(-10, 0, -34)
	for k in range(30):
		await process_frame
	root.get_texture().get_image().save_png("user://harbor_nah.png")
	# Übersicht wie beim Zeichnen (weit herausgezoomt: hier greifen sonst die vereinfachten Modelle).
	app.view_zoom = 34.0
	app.view_focus = Vector3(0, 0, -30)
	for k in range(30):
		await process_frame
	root.get_texture().get_image().save_png("user://harbor_weit.png")
	var cam := Camera3D.new()
	cam.fov = 50.0
	app.add_child(cam)
	cam.position = Vector3(-38, 14, -14)
	cam.look_at(Vector3(-8, 8, -42), Vector3.UP)
	cam.current = true
	for k in range(4):
		await process_frame
	root.get_texture().get_image().save_png("user://harbor_schraeg.png")
	quit()
