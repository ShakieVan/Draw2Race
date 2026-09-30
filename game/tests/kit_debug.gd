extends SceneTree
# Diagnose der Bausatz-Materialien: Zustand von Emission und Texturen.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var app: Node = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.store = ProgressStore.new("user://shots_%s.json" % Time.get_ticks_usec())
	app.debug_data()["override"] = {"time": "night", "weather": "dry", "fog": 0}
	app.select_track("city")
	app.start_drawing()
	for k in range(20):
		await process_frame
	for key in app.world.kit_materials:
		var m: StandardMaterial3D = app.world.kit_materials[key]
		var e: Texture2D = m.emission_texture
		var line := "KIT %s emission=%s energy=%.2f tex=%s albedo=%s" % [key, m.emission_enabled, m.emission_energy_multiplier, e, m.albedo_texture]
		if e != null:
			var img := e.get_image()
			if img != null:
				if img.is_compressed():
					img.decompress()
				var sum := 0.0
				var mx := 0.0
				for y in range(0, img.get_height(), 8):
					for x in range(0, img.get_width(), 8):
						var c := img.get_pixel(x, y)
						sum += c.r + c.g + c.b
						mx = maxf(mx, c.r)
				line += " mittel=%.3f max=%.2f fmt=%s" % [sum / float((img.get_height() / 8) * (img.get_width() / 8) * 3), mx, img.get_format()]
		print(line)
	quit()
