extends SceneTree

# Manueller Audiotest: Drehzahlrampe über den Spiel-Mischer (EngineAudio), damit Stufen beim Überblenden hörbar würden.
# Je Auto: 1,5 s Leerlauf, RAMP s (Vorgabe 8) Vollgas von Leerlauf bis Rotgrenze, 1,5 s im Begrenzer, 5 s Gas weg bis Leerlauf.
# Aufruf: tools/godot_run.ps1 -Script res://tests/engine_sweep.gd -EnvPairs 'CARS=muscle'   (Hauptausgang stumm)
# Ausgabe: %APPDATA%\Godot\app_userdata\Draw2Race\engine_render\<auto>_rampe.wav

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var audio := EngineAudio.new()
	root.add_child(audio)
	audio.load_manifest()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://engine_render"))
	# Mitschnitt auf dem Kanal der Stimme (Eng0), Hauptausgang stumm: echter Audiotreiber, aber kein Ton aus den Lautsprechern
	var rec := AudioEffectRecord.new()
	rec.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(AudioServer.get_bus_index(audio.ensure_bus(0)), rec)
	AudioServer.set_bus_mute(0, true)
	var wanted: PackedStringArray = OS.get_environment("CARS").split(",", false)
	for id in audio.manifest.cars:
		if not wanted.is_empty() and not id in wanted:
			continue
		audio.setup([id])
		var v: EngineAudio.Voice = audio.voices[0]
		var idle := float(v.car.idle)
		var red := float(v.car.redline) * 0.97
		rec.set_recording_active(true)
		var ramp := float(OS.get_environment("RAMP")) if OS.get_environment("RAMP") != "" else 8.0
		var t := 0.0
		var last := Time.get_ticks_usec()
		while t < ramp + 8.0:
			await process_frame
			var now := Time.get_ticks_usec()
			var dt := (now - last) / 1000000.0
			last = now
			t += dt
			var goal := idle
			var thr := 0.0
			if t < 1.5:
				goal = idle
			elif t < 1.5 + ramp:
				goal = lerpf(idle, red, (t - 1.5) / ramp)
				thr = 1.0
			elif t < 3.0 + ramp:
				goal = red
				thr = 1.0
			else:
				goal = lerpf(red, idle, clampf((t - 3.0 - ramp) / 4.5, 0.0, 1.0))
			v.throttle += (thr - v.throttle) * (1.0 - exp(-dt * 12.0))
			v.rpm = goal
			audio.mix_voice(v, -10.0 + EngineAudio.BAKED_DB, dt, goal)
		rec.set_recording_active(false)
		var wav: AudioStreamWAV = rec.get_recording()
		if wav != null:
			wav.save_to_wav(ProjectSettings.globalize_path("user://engine_render/%s_rampe.wav" % id))
			print("AUFNAHME Rampe ", id)
		audio.clear()
	quit()
