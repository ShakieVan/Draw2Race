extends SceneTree

# Prüft, dass die Stoßgeräusche an den richtigen Ereignissen ausgelöst werden (Zähler in RaceSound.impact_log, auch ohne Audiogerät):
# Vorführrennen auf mehreren Strecken; erwartet werden Landungen (Schanzen), Berührungen der Autos und Turbo-Einsätze.
# Aufruf: Godot --headless --path game --script res://tests/impact_events.gd   (Umgebung: TRACKS=city,serra SECS=40)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var app: Node = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.store = ProgressStore.new("user://impact_events_%s.json" % Time.get_ticks_usec())
	app.store.data["debug"] = {"unlock": true}
	app.store.data["sound"] = true
	var ids := OS.get_environment("TRACKS").split(",", false) if OS.get_environment("TRACKS") != "" else PackedStringArray(["city", "serra", "quarry", "fair"])
	var seconds := float(OS.get_environment("SECS")) if OS.get_environment("SECS") != "" else 40.0
	for id in ids:
		app.select_track(id)
		app.stage = 2
		app.sound.enabled = true
		app.sound.impact_log.clear()
		app.demo()
		var frames := int(seconds * 60.0)
		for i in range(frames):
			await physics_frame
		print("STOESSE ", id, " ", app.sound.impact_log, " Fahrzeuge=", app.vehicles.size(), " Phase=", app.phase)
		app.show_menu()
		await process_frame
	quit()
