extends SceneTree
# Prüft die Ansichtsgrenze beim Zeichnen (main.gd view_room): Leere hinter der Fahrbahnkante höchstens VIEW_MARGIN oder der Randstreifen,
# den die Übersicht selbst zeigt – bei Zoom z von Übersicht Z je Achse VIEW_MARGIN·(1 − z/Z) + Randstreifen·z/Z, mindestens VIEW_MARGIN –,
# und in der Übersicht genau die Übersicht. Aufruf: tools/godot_run.ps1 -Script res://tests/view_limit.gd -Headless -EnvPairs 'TRACK=city'
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
	var track: Circuit = app.track
	var margin := float(app.get_script().get_script_constant_map()["VIEW_MARGIN"])
	var edge := track.bounds.grow(track.max_half_width)   # Fahrbahnkante (breiteste Stelle)
	var widest: float = app.overview_size()
	var half_over := Vector2(screen.x*0.5,(band.y-band.x)*0.5)*widest/screen.y
	var strip := half_over - edge.size*0.5
	print("VIEW bildschirm=", screen, " band=", band, " fahrbahnkante=", edge, " weitester Zoom=", snappedf(widest, 0.1), " randstreifen der Uebersicht=", strip)
	var worst := -INF
	for zoom_fraction in [1.0, 0.95, 0.8, 0.6, 0.4, 0.25, 0.12]:
		app.view_zoom = widest * zoom_fraction
		for target in [Vector3(-500, 0, -500), Vector3(500, 0, -500), Vector3(500, 0, 500), Vector3(-500, 0, 500)]:
			app.view_focus = Vector3(target.x, app.view_focus.y, target.z)
			app.clamp_view_state()
			var k: Vector2 = app.screen_scale()
			var rect := Rect2(Vector2(app.view_focus.x - screen.x * 0.5 * k.x, app.view_focus.z - (band.y - band.x) * 0.5 * k.y), Vector2(screen.x * k.x, (band.y - band.x) * k.y))
			var over := Vector2(maxf(edge.position.x - rect.position.x, rect.end.x - edge.end.x), maxf(edge.position.y - rect.position.y, rect.end.y - edge.end.y))
			var t: float = app.view_zoom / widest
			var allow := Vector2(maxf(margin, lerpf(margin, strip.x, t)), maxf(margin, lerpf(margin, strip.y, t)))
			worst = maxf(worst, maxf(over.x - allow.x, over.y - allow.y))
			print("VIEW zoom=%.0f%% ziel=%s fokus=%s sichtfeld=%s ueberstand=%s schranke=%s" % [zoom_fraction * 100.0, target, app.view_focus, rect, over, allow])
	print("VIEW groesste Ueberschreitung der Schranke: %.3f m (<= 0: eingehalten)" % worst)
	quit()
