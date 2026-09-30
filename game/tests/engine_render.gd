extends SceneTree

# Manueller Audiotest mit Fenster (nicht headless): fährt mit jedem gewünschten Auto eine Vorführfahrt und nimmt den Master-Kanal
# (Motoren des Spielers und der Gegner, über den echten Spielablauf) als WAV auf, damit Pegel, Drehzahlverlauf und Stereolage
# objektiv geprüft werden können (Spektrogramm, Klassifikator).
# Aufruf: Godot --path game --script res://tests/engine_render.gd   (Umgebung: CARS=sprint,muscle TRACK=azure SECS=18 MUSIC=0)
# Ausgabe: %APPDATA%\Godot\app_userdata\Draw2Race\engine_render\<auto>.wav

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var app: Node = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.store = ProgressStore.new("user://engine_render_%s.json" % Time.get_ticks_usec())
	app.store.data["debug"] = {"unlock": true}
	app.store.data["sound"] = true
	app.store.data["music"] = OS.get_environment("MUSIC") == "1"
	var track_id := OS.get_environment("TRACK") if OS.get_environment("TRACK") != "" else "azure"
	var seconds := float(OS.get_environment("SECS")) if OS.get_environment("SECS") != "" else 18.0
	var wanted: PackedStringArray = OS.get_environment("CARS").split(",", false)
	app.select_track(track_id)
	if OS.get_environment("STAGE") != "":
		app.stage = int(OS.get_environment("STAGE"))
	for i in range(30):
		await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://engine_render"))
	var rec := AudioEffectRecord.new()
	rec.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(0, rec)
	for index in range(RaceVehicle.CARS.size()):
		var id := str(RaceVehicle.CARS[index].id)
		if not wanted.is_empty() and not id in wanted:
			continue
		app.car_choice = index
		if OS.get_environment("PREVIEW") == "1":
			# Probelauf wie bei der Autowahl im Menü
			app.show_menu()
			for i in range(10):
				await process_frame
			rec.set_recording_active(true)
			app.select_car(index)
			var t0 := Time.get_ticks_msec()
			while (Time.get_ticks_msec() - t0) / 1000.0 < EngineAudio.PREVIEW_LENGTH + 0.6:
				await process_frame
			rec.set_recording_active(false)
			var clip: AudioStreamWAV = rec.get_recording()
			if clip != null:
				clip.save_to_wav(ProjectSettings.globalize_path("user://engine_render/%s_auswahl.wav" % id))
				print("AUFNAHME Auswahl ", id)
			continue
		app.demo()
		rec.set_recording_active(true)
		var started := Time.get_ticks_msec()
		var next_log := 0.0
		while (Time.get_ticks_msec() - started) / 1000.0 < seconds:
			await process_frame
			var elapsed := (Time.get_ticks_msec() - started) / 1000.0
			if elapsed >= next_log and not app.sound.engines.voices.is_empty():
				next_log += 1.0
				var v: RaceVehicle = app.vehicles[0]
				var voice = app.sound.engines.voices[0]
				print("%s t=%4.1f phase=%s v=%5.1f m/s gas=%.2f rpm=%5.0f pegel=%.2f stimmen=%d" % [id, elapsed, app.phase, v.velocity.length(), v.throttle, voice.rpm, app.sound.engines.level, app.sound.engines.voices.size()])
		rec.set_recording_active(false)
		var wav: AudioStreamWAV = rec.get_recording()
		if wav != null:
			var path := ProjectSettings.globalize_path("user://engine_render/%s.wav" % id)
			wav.save_to_wav(path)
			print("AUFNAHME ", id, " ", path, " ", snappedf(float(wav.data.size()) / (4.0 * wav.mix_rate), 0.1), " s @ ", wav.mix_rate)
		app.show_menu()
		for i in range(30):
			await process_frame
	AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0) - 1)
	quit()
