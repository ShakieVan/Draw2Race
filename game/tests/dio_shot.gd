extends SceneTree
# Kontrollbilder einer Strecke mit Diorama: Zeichen-Übersicht (senkrecht) und geneigte Nahansicht wie im Rennen.
# TRACK (Standard city), TIME (day|dusk|night, Standard day), WEATHER, AT (Streckenanteil der Nahansicht), NOOVERLAY=1 (Laternen-Zusatzlicht aus), NOWINDOWS=1 (Fensterlicht aus).
func _initialize() -> void:
	call_deferred("run")

func rgb_env(name: String, fallback: Color) -> Color:
	var parts := OS.get_environment(name).split(",")
	return Color(float(parts[0]), float(parts[1]), float(parts[2])) if parts.size() == 3 else fallback

func run() -> void:
	var id := OS.get_environment("TRACK") if OS.get_environment("TRACK") != "" else "city"
	var time := OS.get_environment("TIME") if OS.get_environment("TIME") != "" else "day"
	var app: Node = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.store = ProgressStore.new("user://shots_%s.json" % Time.get_ticks_usec())
	app.debug_data()["override"] = {"time": time, "weather": OS.get_environment("WEATHER") if OS.get_environment("WEATHER") != "" else "dry", "fog": int(OS.get_environment("FOG"))}
	app.select_track(id)
	app.start_drawing()
	for k in range(40):
		await process_frame
	if OS.get_environment("NOOVERLAY") == "1":
		app.world.set_overlays(false)
	if OS.get_environment("BGPINK") == "1":
		app.world.atmosphere.env.background_color = Color(1, 0, 1)
		app.world.atmosphere.env.fog_enabled = false
	var env: Environment = app.world.atmosphere.env
	if OS.get_environment("AMBIENT") != "":
		env.ambient_light_energy = float(OS.get_environment("AMBIENT"))
	if OS.get_environment("OLDAMB") == "1":
		# Vergleich: flache Umgebungsfarbe wie vor dem Himmelslicht
		var preset: Dictionary = Atmosphere.TIMES[time]
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.reflected_light_source = Environment.REFLECTION_SOURCE_BG
		env.ambient_light_color = Color(preset.ambient)
		env.ambient_light_energy = float(preset.ambient_energy)
		app.world.atmosphere.sun.light_energy = {"day": 0.8, "dusk": 0.6, "night": 0.12}[time]
		for sm in app.world.atmosphere.all_road_shaders():
			var c = sm.get_shader_parameter("albedo_tint")
			if c is Color and app.world.diorama:
				sm.set_shader_parameter("albedo_tint", Color(c.r, c.g, c.b) * (0.42 / 0.62))
	if OS.get_environment("SKYAMB") == "1":
		var sky_mat := ProceduralSkyMaterial.new()
		sky_mat.sky_top_color = rgb_env("SKYTOP", Color(0.40, 0.58, 0.85))
		sky_mat.sky_horizon_color = rgb_env("SKYHOR", Color(0.78, 0.84, 0.90))
		sky_mat.ground_horizon_color = rgb_env("SKYGH", Color(0.70, 0.68, 0.62))
		sky_mat.ground_bottom_color = rgb_env("SKYGND", Color(0.36, 0.33, 0.30))
		sky_mat.sky_energy_multiplier = float(OS.get_environment("SKYE")) if OS.get_environment("SKYE") != "" else 1.0
		var sky := Sky.new()
		sky.sky_material = sky_mat
		env.sky = sky
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		if OS.get_environment("REFLSKY") == "1":
			env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		env.ambient_light_energy = float(OS.get_environment("AMBIENT")) if OS.get_environment("AMBIENT") != "" else 0.6
	if OS.get_environment("SUNE") != "":
		app.world.atmosphere.sun.light_energy = float(OS.get_environment("SUNE"))
	if OS.get_environment("ROAD") != "":
		for sm in app.world.atmosphere.all_road_shaders():
			var c = sm.get_shader_parameter("albedo_tint")
			if c is Color:
				sm.set_shader_parameter("albedo_tint", Color(c.r, c.g, c.b) * float(OS.get_environment("ROAD")))
	if OS.get_environment("AOAFFECT") != "":
		for mi in app.world.find_children("*", "MeshInstance3D", true, false):
			if (mi as MeshInstance3D).mesh == null:
				continue
			for i in range((mi as MeshInstance3D).mesh.get_surface_count()):
				var m := (mi as MeshInstance3D).mesh.surface_get_material(i) as StandardMaterial3D
				if m != null and m.ao_enabled:
					m.ao_light_affect = float(OS.get_environment("AOAFFECT"))
	if OS.get_environment("TONEMAP") != "":
		env.tonemap_mode = int(OS.get_environment("TONEMAP"))
		env.tonemap_white = float(OS.get_environment("WHITE")) if OS.get_environment("WHITE") != "" else 6.0
	if OS.get_environment("CONTRAST") != "" or OS.get_environment("SATURATION") != "" or OS.get_environment("BRIGHTNESS") != "":
		env.adjustment_enabled = true
		env.adjustment_contrast = float(OS.get_environment("CONTRAST")) if OS.get_environment("CONTRAST") != "" else 1.0
		env.adjustment_saturation = float(OS.get_environment("SATURATION")) if OS.get_environment("SATURATION") != "" else 1.0
		env.adjustment_brightness = float(OS.get_environment("BRIGHTNESS")) if OS.get_environment("BRIGHTNESS") != "" else 1.0
	if OS.get_environment("NOGLOW") == "1":
		app.world.atmosphere.env.glow_enabled = false
	if OS.get_environment("WINLEVEL") != "":
		app.world.set_windows(float(OS.get_environment("WINLEVEL")))
	if OS.get_environment("NOWINDOWS") == "1":
		app.world.set_windows(0.0)
	for k in range(4):
		await process_frame
	root.get_texture().get_image().save_png("user://dio_%s_%s%s%s%s_uebersicht.png" % [id, time, OS.get_environment("TAG"), OS.get_environment("WEATHER"), ("_nebel" + OS.get_environment("FOG")) if OS.get_environment("FOG") != "" else ""])
	# Geneigte Nahansicht (wie Rennkamera) auf den Startbereich.
	app.cam_pitch = app.PITCH_RACE
	app.cam_zoom = 26.0
	var s: Vector2 = app.track.at(float(OS.get_environment("AT")) if OS.get_environment("AT") != "" else 0.02)
	app.camera_target = Vector3(s.x, 0, s.y)
	if OS.get_environment("CX") != "":
		app.camera_target = Vector3(float(OS.get_environment("CX")), 0, float(OS.get_environment("CZ")))
	app.paused = true
	app.set_camera(app.camera_target)
	for k in range(10):
		await process_frame
	root.get_texture().get_image().save_png("user://dio_%s_%s%s%s%s_nah.png" % [id, time, OS.get_environment("TAG"), OS.get_environment("WEATHER"), ("_nebel" + OS.get_environment("FOG")) if OS.get_environment("FOG") != "" else ""])
	quit()
