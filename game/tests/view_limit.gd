extends SceneTree
# Prüft die Ansichtsgrenze beim Zeichnen: Das sichtbare Stück Boden darf nie weit über die Strecke hinausreichen.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var id := OS.get_environment("TRACK") if OS.get_environment("TRACK") != "" else "city"
	var app: Node = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.store = ProgressStore.new("user://shots_%s.json" % Time.get_ticks_usec())
	app.select_track(id)
	app.start_drawing()
	for k in range(10):
		await process_frame
	var screen: Vector2 = app.get_viewport().get_visible_rect().size
	var band: Vector2 = app.hud.free_band()
	var bounds: Rect2 = app.track.bounds
	print("VIEW bildschirm=", screen, " band=", band, " strecke=", bounds, " weitester Zoom=", snappedf(app.overview_size(), 0.1))
	var worst := 0.0
	for zoom_fraction in [1.0, 0.8, 0.6, 0.4, 0.25, 0.12]:
		app.view_zoom = app.overview_size() * zoom_fraction
		for target in [Vector3(-500, 0, -500), Vector3(500, 0, -500), Vector3(500, 0, 500), Vector3(-500, 0, 500)]:
			app.view_focus = target
			app.clamp_view_state()
			var k: Vector2 = app.screen_scale()
			var rect := Rect2(Vector2(app.view_focus.x - screen.x * 0.5 * k.x, app.view_focus.z - (band.y - band.x) * 0.5 * k.y), Vector2(screen.x * k.x, (band.y - band.x) * k.y))
			var over := maxf(maxf(bounds.position.x - rect.position.x, rect.end.x - bounds.end.x), maxf(bounds.position.y - rect.position.y, rect.end.y - bounds.end.y))
			worst = maxf(worst, over)
			print("VIEW zoom=%.0f%% ziel=%s fokus=%s sichtfeld=%s ueberstand=%.1f m" % [zoom_fraction * 100.0, target, app.view_focus, rect, over])
	print("VIEW groesster Ueberstand: %.1f m" % worst)
	quit()
