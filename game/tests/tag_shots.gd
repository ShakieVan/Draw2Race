extends SceneTree
# Kontrollbilder für Namensschilder und Sprechblasen (M1): Rennen mit 3 Gegnern (Herausforderung 3), TRACK (Standard city),
# TIME (day/night), NAME (Spielername). Läuft in Echtzeit wie im Spiel. Ist zum Aufnahmezeitpunkt keine Blase zu sehen, bekommt
# ein sichtbares Auto eine (nur Darstellung). Aufruf z. B.:
#   tools/godot_run.ps1 -Script res://tests/tag_shots.gd -Resolution 2340x1080 -EnvPairs 'TRACK=city','TIME=night'
func _initialize() -> void:
	call_deferred("run")

func env(key: String, fallback: String) -> String:
	return OS.get_environment(key) if OS.get_environment(key) != "" else fallback

func run() -> void:
	var id := env("TRACK", "city")
	var time := env("TIME", "day")
	var app: Node = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.store = ProgressStore.new("user://shots_%s.json" % Time.get_ticks_usec())
	app.store.data["ghost"] = false
	app.store.set_player_name(env("NAME", "Shakie"))
	app.debug_data()["override"] = {"time": time, "weather": env("WEATHER", "dry"), "fog": 0}
	app.select_track(id)
	app.stage = 2
	app.store.data["debug"]["unlock"] = true
	app.car_choice = int(env("CAR", "0"))
	app.start_drawing()
	app.demonstration = true    # keine Bestenliste/Geist; mein Auto zündet den Turbo wie die KI
	app.recorder.route = app.track.ai_route(float(env("SKILL", "2.1")), 0.0)
	app.recorder.complete = true
	app.begin_race()
	var size: Vector2 = root.get_visible_rect().size
	for shot in [[240, "start"], [420, "rennen"], [300, "pulk"]]:
		for i in range(int(shot[0])):
			await physics_frame
		var tags: NameTags = app.hud.tags
		var bubble := false
		for d in tags.drawn:
			if d.kind == "bubble":
				bubble = true
		if not bubble:
			# Sichtbares Auto (zuerst ein Gegner) bekommt eine Blase, kurz warten bis nach dem „Plopp“.
			var pick := -1
			for d in tags.drawn:
				if d.kind == "tag" and not d.pinned and (pick < 0 or d.car != app.me):
					pick = d.car
			if pick >= 0:
				app.chatter.say(pick, "overtake", app.race_time, "", pick)
			for i in range(18):
				await physics_frame
		for k in range(3):
			await process_frame
		var path := "user://tags_%s_%s_%s.png" % [id, time, shot[1]]
		root.get_texture().get_image().save_png(path)
		var parts: Array = []
		for d in tags.drawn:
			parts.append("%s%d%s„%s“" % [d.kind[0], d.car, "@" if d.pinned else "", d.text])
		print("SHOT ", ProjectSettings.globalize_path(path), " ", size, " ", " ".join(parts))
	# Einstellungen: Boxeneinstellungen und der Dialog für Name, Schilder und Sprechblasen.
	app.show_menu()
	app.hud.settings()
	for k in range(4):
		await process_frame
	root.get_texture().get_image().save_png("user://tags_settings.png")
	for c in app.hud.content.get_children():
		if c is ColorRect:
			c.queue_free()
	app.hud.name_settings()
	for k in range(4):
		await process_frame
	root.get_texture().get_image().save_png("user://tags_name_dialog.png")
	print("SHOT ", ProjectSettings.globalize_path("user://tags_name_dialog.png"))
	quit()
