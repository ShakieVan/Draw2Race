extends SceneTree

# Kontrollbilder Wiederansetzen: offener (schimmernder) Rest und laufende Probe mit altem Rest (blass).
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var app: Node = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.store = ProgressStore.new("user://shots_%s.json" % Time.get_ticks_usec())
	app.start_drawing()
	var track: Circuit = app.track
	var pen: LineRecorder = app.recorder
	pen.begin(track.at(0.0),0.0)
	for i in range(1,151):
		pen.sample(track.at(i/700.0,-1.0+0.02*i),i/60.0)
	pen.end()
	app.view_zoom = app.overview_size()*0.45
	var tip: Vector2 = pen.last_pos
	app.view_focus = Vector3(tip.x,0,tip.y)
	for i in range(20):
		await process_frame
	root.get_texture().get_image().save_png("user://resume_1.png")
	pen.begin(track.at(125/700.0,1.5),20.0,1.5)
	for i in range(1,16):
		pen.sample(track.at((125+i*2)/700.0,-2.0),20.0+i/60.0)
	for i in range(10):
		await process_frame
	root.get_texture().get_image().save_png("user://resume_2.png")
	print("SHOTS trial=", pen.trial)
	quit()
