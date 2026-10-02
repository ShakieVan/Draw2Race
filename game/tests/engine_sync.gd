extends SceneTree

# Diagnose Gleichtakt: dieselbe Motorschleife zweimal; die zweite wird nach einer Wartezeit an der gemessenen Stelle des
# Arbeitsspiels der ersten gestartet. Gleichtakt -> Summe +6 dB, zufällige Lage -> etwa +3 dB.
# Aufruf: tools/godot_run.ps1 -Script res://tests/engine_sync.gd   (echter Treiber, Hauptausgang stumm)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var audio := EngineAudio.new()
	root.add_child(audio)
	audio.load_manifest()
	# Mitschnitt auf eigenem Kanal, Hauptausgang stumm (kein Ton aus den Lautsprechern, echter Audiotreiber)
	var recs: Array[AudioEffectRecord] = []
	for bus_name in ["DiagA", "DiagB"]:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")
		var r := AudioEffectRecord.new()
		r.format = AudioStreamWAV.FORMAT_16_BITS
		AudioServer.add_bus_effect(idx, r)
		recs.append(r)
	AudioServer.set_bus_mute(0, true)
	var car: Dictionary = audio.manifest.cars.grip
	var layer: Dictionary = car.layers[12]
	var st := audio.layer_stream(layer, "load")
	var a := AudioStreamPlayer.new()
	var b := AudioStreamPlayer.new()
	a.bus = "DiagA"
	b.bus = "DiagB"
	root.add_child(a)
	root.add_child(b)
	var cyc := float(st.loop_end) / float(layer.cycles)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://engine_render"))
	for trial in range(10):
		a.stream = st
		b.stream = st
		a.pitch_scale = 1.0 + 0.02 * trial
		b.pitch_scale = a.pitch_scale
		for r in recs:
			r.set_recording_active(true)
		a.play(0.0)
		for i in range(40 + trial * 7):
			await process_frame
		var pos := a.get_playback_position() * float(st.mix_rate)
		var ph := fposmod(pos / cyc, 1.0)
		b.play((2.0 + ph) * cyc / float(st.mix_rate))
		for i in range(60):
			await process_frame
		a.stop()
		b.stop()
		for r in range(2):
			recs[r].set_recording_active(false)
			recs[r].get_recording().save_to_wav(ProjectSettings.globalize_path("user://engine_render/sync_%d_%s.wav" % [trial, "ab"[r]]))
		print("SYNC ", trial, " Start b bei Phase ", snappedf(ph, 0.001), " Mischabstand ", snappedf(AudioServer.get_time_to_next_mix() * 1000.0, 0.1), " ms")
	quit()
