extends SceneTree

# Gegenversuch zu engine_sweep.gd: alle Schichten eines Motors starten im selben Mischschritt bei 0 und laufen durchgehend
# (Gleichtakt durch Bauart, weil jede Schicht mit Drehzahl/Schichtdrehzahl abgespielt wird). Nur die Lautstärken wandern.
# Aufruf: tools/godot_run.ps1 -Script res://tests/engine_sweep_all.gd -EnvPairs 'CARS=grip'   (Hauptausgang stumm)
# Ausgabe: user://engine_render/<auto>_rampe_alle.wav

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var audio := EngineAudio.new()
	root.add_child(audio)
	audio.load_manifest()
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, "Diag")
	AudioServer.set_bus_send(idx, "Master")
	var rec := AudioEffectRecord.new()
	rec.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(idx, rec)
	AudioServer.set_bus_mute(0, true)
	var wanted: PackedStringArray = OS.get_environment("CARS").split(",", false)
	for id in audio.manifest.cars:
		if not wanted.is_empty() and not id in wanted:
			continue
		var car: Dictionary = audio.manifest.cars[id]
		var rpms: Array[float] = []
		var load_p: Array[AudioStreamPlayer] = []
		var coast_p: Array[AudioStreamPlayer] = []
		for layer in car.layers:
			rpms.append(float(layer.rpm))
			for mode in ["load", "coast"]:
				var pl := AudioStreamPlayer.new()
				pl.bus = "Diag"
				pl.stream = audio.layer_stream(layer, mode)
				pl.volume_db = -80.0
				root.add_child(pl)
				(load_p if mode == "load" else coast_p).append(pl)
		for pl in load_p + coast_p:
			pl.play(0.0)
		var idle := float(car.idle)
		var red := float(car.redline) * 0.97
		rec.set_recording_active(true)
		var t := 0.0
		var thr := 0.0
		var last := Time.get_ticks_usec()
		var t0 := Time.get_ticks_usec()
		while t < 15.0:
			await process_frame
			var now := Time.get_ticks_usec()
			var dt := (now - last) / 1000000.0
			last = now
			t += dt
			var goal := idle
			var want := 0.0
			if OS.get_environment("STATIC") != "":
				# feste Drehzahl genau zwischen zwei Schichten (Index STATIC und STATIC+1), Vollgas
				var j0 := int(OS.get_environment("STATIC"))
				goal = sqrt(rpms[j0] * rpms[j0 + 1])
				want = 1.0
			elif t < 1.5:
				goal = idle
			elif t < 9.5:
				goal = lerpf(idle, red, (t - 1.5) / 8.0)
				want = 1.0
			else:
				goal = lerpf(red, idle, clampf((t - 9.5) / 4.5, 0.0, 1.0))
			thr += (want - thr) * (1.0 - exp(-dt * 12.0))
			var r := clampf(goal, rpms[0], rpms[rpms.size() - 1])
			var k := 0
			while k < rpms.size() - 2 and r >= rpms[k + 1]:
				k += 1
			var w := clampf((r - rpms[k]) / (rpms[k + 1] - rpms[k]), 0.0, 1.0)
			for j in range(rpms.size()):
				var g := 0.0
				if j == k:
					g = cos(w * PI * 0.5)
				elif j == k + 1:
					g = sin(w * PI * 0.5)
				load_p[j].pitch_scale = goal / rpms[j]
				coast_p[j].pitch_scale = goal / float(car.layers[j].get("coast_rpm", rpms[j]))
				load_p[j].volume_db = -5.0 + linear_to_db(maxf(0.00001, g * sqrt(thr)))
				coast_p[j].volume_db = -5.0 + linear_to_db(maxf(0.00001, g * sqrt(1.0 - thr)))
		rec.set_recording_active(false)
		rec.get_recording().save_to_wav(ProjectSettings.globalize_path("user://engine_render/%s_%s.wav" % [id, "fest" if OS.get_environment("STATIC") != "" else "rampe_alle"]))
		print("AUFNAHME alle ", id, " Bildzeit ", snappedf((Time.get_ticks_usec() - t0) / 1000000.0, 0.1))
		for pl in load_p + coast_p:
			pl.queue_free()
	quit()
