extends SceneTree

# Manueller Audiotest mit Fenster (nicht headless): prüft, dass Musik läuft, wechselt und abgesenkt wird.
# Aufruf: Godot --path game --script res://tests/audio_smoke.gd

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var app: Node = load("res://main.tscn").instantiate()
	root.add_child(app)
	for i in range(30):
		await process_frame
	var s: RaceSound = app.sound
	print("Titel geladen: ", s.tracks.size(), ", Stil: ", s.music_style)
	print("Menü spielt: ", s.active.playing, " ", s.current.get("file",""), " @ ", s.active.volume_db)
	app.store.data.music_style = "ruhig"
	app.start_drawing()
	for i in range(90):
		await process_frame
	print("Zeichnen (abgesenkt): ", s.context, " ", s.active.volume_db)
	app.phase = "result"
	app.result_won = false
	for i in range(120):
		await process_frame
	print("Niederlage: ", s.special, " ", s.current.get("file",""), " spielt=", s.active.playing)
	app.show_menu()
	for i in range(200):
		await process_frame
	print("Zurück zur Playlist: ", s.special=="", " ", s.current.get("file",""))
	quit()
