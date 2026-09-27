extends SceneTree

# Kontrollbild der Kollisionsfunken (Stoß direkt ausgelöst).
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var app: Node = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.store = ProgressStore.new("user://shots_%s.json" % Time.get_ticks_usec())
	app.store.data["camera_zoom"] = 1.0
	app.debug_data()["override"] = {"time": "dusk", "weather": "dry", "fog": 0}
	app.stage = 1
	app.demo()
	for i in range(150):
		await process_frame
	var p: Vector2 = app.vehicles[0].pos
	app.world.sparks(Vector3(p.x+0.4,0.45,p.y+0.5),Vector3(0,0,1),1.0)
	for i in range(6):
		await process_frame
	root.get_texture().get_image().save_png("user://spark_test.png")
	print("SHOT")
	quit()
