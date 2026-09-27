extends SceneTree

# Kontrollbild der Spiegelung: ganze Fahrbahn als Pfütze, Tag mit Regen, nah.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var app: Node = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.store = ProgressStore.new("user://shots_%s.json" % Time.get_ticks_usec())
	app.store.data["camera_zoom"] = 0.8
	app.debug_data()["override"] = {"time": "day", "weather": "rain", "fog": 0}
	app.stage = 1
	app.demo()
	var shader: ShaderMaterial = app.world.atmosphere.road_shader
	shader.set_shader_parameter("puddle_cover", -0.2)
	shader.set_shader_parameter("puddle_cover", float(OS.get_environment("COVER")) if OS.get_environment("COVER") != "" else -0.2)
	# Hoher roter Mast neben der Startlinie: Sein Spiegelbild muss am Fuß ansetzen.
	var pole := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.3, 4.0, 0.3)
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.9, 0.1, 0.1)
	box.material = red
	pole.mesh = box
	var at: Vector2 = app.track.at(0.02, 1.5)
	pole.position = Vector3(at.x, 2.2, at.y)
	app.world.add_child(pole)
	for i in range(240):
		await process_frame
	root.get_texture().get_image().save_png("user://mirror_test.png")
	print("SHOT flip=", shader.get_shader_parameter("flip_x"))
	quit()
