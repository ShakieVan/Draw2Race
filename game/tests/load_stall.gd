extends SceneTree
# Ruckler beim Streckenwechsel: längste Bildzeit (Hauptfaden) je Wechsel, solange die Strecke lädt, und in den ersten Bildern danach
# (Zeichenansicht: Shader, erste Darstellung). Aufruf: tools/godot_run.ps1 -Script res://tests/load_stall.gd -Resolution 1600x720
# Umgebung: ONLY=city,forest (Auswahl), GFX=0 (Grafik „Niedrig“), SYNC=1 (select_track am Stück zum Vergleich). Zeilen „STALL …“; am Ende „STALL GESAMT …“.
var app: Node
var stamps: Array[int] = []

func _initialize() -> void:
	call_deferred("run")

func frame() -> int:
	# Ein Bild abwarten; Rückgabe: Dauer seit dem letzten Bild (µs).
	await process_frame
	var now := Time.get_ticks_usec()
	var dt := now - stamps[-1] if not stamps.is_empty() else 0
	stamps.append(now)
	return dt

func run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var path := "user://stall_%s.json" % Time.get_ticks_usec()
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.store = ProgressStore.new(path)
	if OS.get_environment("GFX") != "":
		app.store.data["gfx"] = int(OS.get_environment("GFX"))
	var only := OS.get_environment("ONLY")
	var order: Array = Array(only.split(",")) if only != "" else ["city", "forest", "harbor", "serra", "fair", "quarry", "arena", "kids", "azure"]
	if OS.get_environment("PASSES") == "2":
		order = order + order   # zweiter Durchgang: Shader und Lichtkarten schon bekannt (Wiederkehr zu einer Strecke)
	var async: bool = app.has_method("track_ready") and OS.get_environment("SYNC") == ""
	# Start: bis die erste Strecke steht und ein paar Bilder gelaufen sind.
	for i in range(30):
		await frame()
	if app.has_method("track_ready"):
		while not app.track_ready():
			await frame()
	var worst_load := 0
	var worst_show := 0
	for id in order:
		await frame()
		var t0 := Time.get_ticks_usec()
		# Wie die Streckenwahl im Menü: im Hintergrund (pick_track), vor dem Umbau am Stück (select_track).
		if async:
			app.pick_track(id)
		else:
			app.select_track(id)
		var call_us := Time.get_ticks_usec() - t0
		var load_max := 0
		var frames := 0
		var dt := await frame()
		load_max = maxi(load_max, dt)
		frames += 1
		if async:
			while not app.track_ready():
				dt = await frame()
				load_max = maxi(load_max, dt)
				frames += 1
		var load_total := Time.get_ticks_usec() - t0
		var step: float = app.world.longest_step / 1000.0 if async else 0.0
		# Strecke zeigen (wie „Linie zeichnen“): erste Bilder mit der neuen Welt.
		app.start_drawing()
		var show_max := 0
		for i in range(20):
			show_max = maxi(show_max, await frame())
		app.show_menu()
		for i in range(5):
			await frame()
		worst_load = maxi(worst_load, load_max)
		worst_show = maxi(worst_show, show_max)
		print("STALL %-7s Aufruf %6.1f ms | Laden: %4d Bilder, %7.1f ms gesamt, längstes Bild %6.1f ms (Bauschritt %5.1f ms) | erste Bilder danach: längstes %6.1f ms" % [id,
			call_us / 1000.0, frames, load_total / 1000.0, load_max / 1000.0, step, show_max / 1000.0])
	print("STALL GESAMT längstes Bild beim Laden %.1f ms, nach dem Laden %.1f ms (%s)" % [worst_load / 1000.0, worst_show / 1000.0,
		"im Hintergrund" if async else "am Stück"])
	for f in [path, path + ".bak"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	quit()
