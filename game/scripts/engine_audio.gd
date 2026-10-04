class_name EngineAudio
extends Node

# Motorklang aller Fahrzeuge (Spieler und Gegner) aus Drehzahlschichten, aufgenommen mit engine-sim (tools/record_engines.py;
# Turbo, Schubumluftventil und Fehlzündungen aus tools/make_engine_sounds.py).
# Je Fahrzeug und Schicht ein Abspieler für "Last" (Gas) und "Schub" (Gas weg); zwei benachbarte Schichten werden überblendet,
# die Tonhöhe ergibt sich aus gewünschter Drehzahl / Schichtdrehzahl. Die Drehzahl wird aus Geschwindigkeit und Gas nur für den
# Klang nachgebildet (Gangmodell); die Simulation wird ausschließlich gelesen (Leitplanke 4).

const DIR := "res://assets/sfx/engines/"
const BASE_GEARS := [4.5, 8.0, 11.5, 15.0, 19.0, 26.0]     # Geschwindigkeit (m/s) am Ende jedes Gangs (mal car.gears)
# Pegel: Die Schichten sind auf etwa -17 (Leerlauf) bis -12 dBFS (Nenndrehzahl) effektiv normiert.
const PLAYER_DB := -10.0
const RIVAL_DB := -12.0               # Gegner nur wenig leiser als das eigene Auto (Nutzerwunsch 01.10.2026)
const REV_DB := 5.0                # Zuschlag von Leerlauf bis Nenndrehzahl (nur synthetische Schichten ohne eigene Dynamik)
const BAKED_DB := 5.0              # Aufnahmen mit eingebauter Dynamik (lauteste Lastschicht -12 dBFS, Leerlauf deutlich leiser)
const LIMIT_AT := 0.985            # Anteil der Rotgrenze, ab dem bei Vollgas der Begrenzer eingreift
const MAX_VOICES := 6
const PAD_FRAMES := 4              # Randproben hinter dem Loop-Ende (Anfang des Loops) für die lineare Interpolation
const PREVIEW_LENGTH := 4.6        # Probelauf in der Auswahl (s)
const SLOTS := 3                   # Abspielerpaare (Last/Schub) je Stimme; die Schichten wechseln durch, wenn die Drehzahl wandert

class Voice extends RefCounted:
	var car: Dictionary = {}
	var load_players: Array[AudioStreamPlayer] = []
	var coast_players: Array[AudioStreamPlayer] = []
	var slot_layer: Array[int] = []    # Schicht, die ein Abspielerpaar gerade spielt (-1 frei)
	var rpms: Array[float] = []
	var turbo: AudioStreamPlayer
	var panner: AudioEffectPanner
	var bus := ""
	var is_player := false
	var rpm := 900.0
	var throttle := 0.0
	var prev_throttle := 0.0
	var prev_boost := false
	var pops_left := 0
	var pop_wait := 0.0
	var detune := 1.0
	var limiter: AudioStreamPlayer
	var limit_amt := 0.0
	var phase := 0.0                 # Stelle im Arbeitsspiel (0..1); neue Schichten setzen hier ein (Gleichtakt der Zündungen)

var manifest: Dictionary = {}
var streams := {}
var voices: Array[Voice] = []
var pop_players: Array[AudioStreamPlayer] = []
var bov_player := AudioStreamPlayer.new()
var rng := RandomNumberGenerator.new()
var headless := false
var level := 0.0                   # Gesamtblende (0 stumm, 1 voll), damit der Motor am Rennende ausklingt
var preview_time := -1.0           # >= 0: Probelauf eines Motors (Autoauswahl), sonst -1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	headless = DisplayServer.get_name() == "headless"
	rng.randomize()
	bov_player.bus = "SFX"
	add_child(bov_player)
	for i in range(2):
		var pop := AudioStreamPlayer.new()
		pop.bus = "SFX"
		add_child(pop)
		pop_players.append(pop)

func load_manifest() -> void:
	var path := DIR + "engines.json"
	if not FileAccess.file_exists(path):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary and parsed.get("cars") is Dictionary:
		manifest = parsed

static func make_loop(src: AudioStreamWAV, frames := 0) -> AudioStreamWAV:
	# Kopie mit Randproben hinter dem Loop-Ende, damit die Interpolation an der Naht nicht gegen Stille läuft.
	var s := AudioStreamWAV.new()
	s.format = src.format
	s.mix_rate = src.mix_rate
	s.stereo = src.stereo
	var bytes_per_frame := 2 if src.format == AudioStreamWAV.FORMAT_16_BITS else 1
	if src.stereo:
		bytes_per_frame *= 2
	var count := frames if frames > 0 else src.data.size() / bytes_per_frame
	s.data = src.data.slice(0, count * bytes_per_frame) + src.data.slice(0, PAD_FRAMES * bytes_per_frame)
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = count
	return s

func stream(file: String, frames := 0, loop := true) -> AudioStreamWAV:
	var key := file + ("#loop" if loop else "")
	if not streams.has(key):
		var src := load(DIR + file) as AudioStreamWAV
		streams[key] = src if (src == null or not loop) else make_loop(src, frames)
	return streams[key]

func ensure_bus(index: int) -> String:
	# Eigener Kanal je Stimme mit Stereoregler (Lage des Autos im Bild); Ausgabe über die Geräuschlautstärke.
	var bus_name := "Eng%d" % index
	if AudioServer.get_bus_index(bus_name) == -1:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "SFX" if AudioServer.get_bus_index("SFX") != -1 else "Master")
		AudioServer.add_bus_effect(idx, AudioEffectPanner.new())
	return bus_name

func setup(ids: Array, me := 0) -> void:
	# Stimmen für die Fahrzeuge eines Rennens anlegen (Index wie im Feld); ids[me] ist das eigene Auto.
	clear()
	if headless:
		return
	if manifest.is_empty():
		load_manifest()
	if manifest.is_empty():
		return
	var fallback: Dictionary = manifest.cars.values()[0]
	for i in range(mini(ids.size(), MAX_VOICES)):
		# Verstimmung nach Reihenfolge ohne das eigene Auto (eigenes 0, die übrigen 1, 2, 3 …)
		voices.append(make_voice(manifest.cars.get(str(ids[i]), fallback), i, i == me, 0 if i == me else (i if i > me else i + 1)))
	level = 0.0

func make_voice(car: Dictionary, index: int, player: bool, rank: int) -> Voice:
	# index: Kanal (= Fahrzeugindex); rank: Verstimmungsstufe (0 = eigenes Auto, unverstimmt).
	var v := Voice.new()
	v.car = car
	v.is_player = player
	v.bus = ensure_bus(index)
	v.panner = AudioServer.get_bus_effect(AudioServer.get_bus_index(v.bus), 0) as AudioEffectPanner
	v.rpm = float(car.idle)
	v.detune = 1.0 + (0.0 if rank == 0 else (0.012 if rank % 2 == 1 else -0.015) * float((rank + 1) / 2))
	for layer in car.layers:
		v.rpms.append(float(layer.rpm))
		layer_stream(layer, "load")              # vorab laden, damit der Wechsel im Rennen nicht hakt
		layer_stream(layer, "coast")
	for i in range(SLOTS):
		for mode in ["load", "coast"]:
			var pl := AudioStreamPlayer.new()
			pl.bus = v.bus
			pl.volume_db = -80.0
			add_child(pl)
			(v.load_players if mode == "load" else v.coast_players).append(pl)
		v.slot_layer.append(-1)
	if car.has("limiter"):
		v.limiter = AudioStreamPlayer.new()
		v.limiter.bus = v.bus
		v.limiter.stream = stream(str(car.limiter), int(car.get("limiter_frames", 0)))
		v.limiter.volume_db = -80.0
		add_child(v.limiter)
		v.limiter.play()
		v.limiter.stream_paused = true
	if v.is_player:
		v.turbo = AudioStreamPlayer.new()
		v.turbo.bus = "SFX"
		v.turbo.stream = stream("turbo_%s.wav" % str(car.turbo))
		v.turbo.volume_db = -80.0
		add_child(v.turbo)
		v.turbo.play()
		v.turbo.stream_paused = true
	return v

func layer_stream(layer: Dictionary, mode: String) -> AudioStreamWAV:
	return stream(str(layer[mode]), int(layer.get("coast_frames", layer.frames)) if mode == "coast" else int(layer.frames))

func clear() -> void:
	preview_time = -1.0
	for v in voices:
		for pl in v.load_players + v.coast_players:
			pl.stop()
			pl.queue_free()
		if v.limiter != null:
			v.limiter.stop()
			v.limiter.queue_free()
		if v.turbo != null:
			v.turbo.stop()
			v.turbo.queue_free()
	voices.clear()

func silence() -> void:
	for v in voices:
		for pl in v.load_players + v.coast_players:
			pl.stop()
		for i in range(v.slot_layer.size()):
			v.slot_layer[i] = -1
		if v.limiter != null:
			v.limiter.stream_paused = true
		if v.turbo != null:
			v.turbo.stream_paused = true

func target_rpm(v: Voice, speed: float, throttle: float, airborne: bool) -> float:
	# Gangmodell nur für den Klang: Drehzahl steigt im Gang mit der Geschwindigkeit, fällt beim Hochschalten zurück; beim Anfahren
	# schleift die Kupplung (Drehzahl folgt dem Gas); in der Luft dreht der Motor frei bis in den Begrenzer. Kurz vor dem
	# Hochschalten erreicht er bei Vollgas die Rotgrenze (der Begrenzer regelt ab); im letzten Gang begrenzt der Fahrtwind.
	var idle := float(v.car.idle)
	var red := float(v.car.redline) * 0.97
	var scale := float(v.car.get("gears", 1.0))
	var g := 0
	while g < BASE_GEARS.size() - 1 and speed >= float(BASE_GEARS[g]) * scale:
		g += 1
	var lo := 0.0 if g == 0 else float(BASE_GEARS[g - 1]) * scale
	var hi := float(BASE_GEARS[g]) * scale
	var frac := clampf((speed - lo) / maxf(0.1, hi - lo), 0.0, 1.0)
	var low_rpm := idle if g == 0 else red * 0.56
	var r := lerpf(low_rpm, red, pow(minf(1.0, frac / 0.95), 0.85))
	if g == BASE_GEARS.size() - 1:
		r = minf(r, red * 0.95)
	if speed < 3.5:
		r = maxf(r, idle + throttle * 0.42 * (red - idle))
	if airborne:
		r = lerpf(r, red, throttle)
	return r

func preview(id: String) -> void:
	# Kurzer Probelauf eines Motors (Leerlauf, Gas, Schalten, Turbo, Gas weg), z. B. bei der Autowahl im Menü.
	if headless:
		return
	setup([id])
	if voices.is_empty():
		return
	preview_time = 0.0
	level = 1.0

func preview_step(dt: float, sfx_on: bool) -> void:
	preview_time += dt
	var v := voices[0]
	var idle := float(v.car.idle)
	var red := float(v.car.redline) * 0.97
	var t := preview_time
	var goal := idle
	var thr := 0.0
	var boost := false
	if t < 0.45:
		goal = idle
	elif t < 1.75:
		goal = lerpf(idle, red, smoothstep(0.45, 1.45, t))
		thr = 1.0
	elif t < 2.0:
		goal = red * 0.58               # Hochschalten: Drehzahl fällt zurück
		thr = 0.6
	elif t < 3.2:
		goal = lerpf(red * 0.58, red * 0.97, smoothstep(2.0, 3.2, t))
		thr = 1.0
		boost = t > 2.2
	else:
		goal = idle * 1.15               # Gas weg: Schub, Motor fällt auf Leerlauf
	v.throttle += (thr - v.throttle) * (1.0 - exp(-dt * 12.0))
	v.rpm += (goal - v.rpm) * (1.0 - exp(-dt * (9.0 if goal > v.rpm else 3.2)))
	var fade := clampf((PREVIEW_LENGTH - t) / 0.6, 0.0, 1.0)
	var db := PLAYER_DB + float(v.car.get("gain_db", 0.0)) + rev_db(v) + linear_to_db(maxf(0.0001, fade))
	if not sfx_on:
		db = -80.0
	if v.panner != null:
		v.panner.pan = 0.0
	mix_voice(v, db, dt, goal)
	drive_turbo(v, boost and sfx_on, 12.0, false, fade)
	drive_pops(v, dt, db, true)
	v.prev_throttle = v.throttle
	if t >= PREVIEW_LENGTH:
		clear()

func update(dt: float, vehicles: Array, camera: Camera3D, phase: String, countdown: float, paused: bool, sfx_on: bool, me := 0) -> void:
	if headless or voices.is_empty():
		return
	if preview_time >= 0.0:
		preview_step(dt, sfx_on)
		return
	var wanted := (phase == "countdown" or phase == "race") and sfx_on and not paused
	if paused or not sfx_on:
		level = 0.0
	else:
		level = move_toward(level, 1.0 if wanted else 0.0, dt / (0.25 if wanted else 0.6))
	if level <= 0.001:
		silence()
		return
	var screen := camera.get_viewport().get_visible_rect().size if camera != null else Vector2(1600, 900)
	var own_pos: Vector2 = vehicles[me].pos if me >= 0 and me < vehicles.size() else Vector2.ZERO
	for i in range(mini(voices.size(), vehicles.size())):
		update_voice(voices[i], vehicles[i], dt, camera, screen, own_pos, phase, countdown)

func update_voice(v: Voice, vehicle: RaceVehicle, dt: float, camera: Camera3D, screen: Vector2, own_pos: Vector2, phase: String, countdown: float) -> void:
	var stopped: bool = vehicle.finish_time >= 0.0 or vehicle.crashed
	var speed := 0.0 if stopped else vehicle.velocity.length()
	var thr := 0.0 if stopped else clampf(vehicle.throttle, 0.0, 1.0)
	if vehicle.braking > 0.6:
		thr = 0.0
	if phase == "countdown":
		# An der Ampel: Leerlauf, in der letzten Sekunde dreht der Motor hoch.
		speed = 0.0
		thr = clampf((1.2 - countdown) / 1.2, 0.0, 1.0) * 0.75
	v.throttle += (thr - v.throttle) * (1.0 - exp(-dt * 12.0))
	var goal := target_rpm(v, speed, v.throttle, vehicle.airborne)
	v.rpm += (goal - v.rpm) * (1.0 - exp(-dt * (9.0 if goal > v.rpm else 4.0)))
	# Lautstärke: Gesamtpegel, Abstand zum eigenen Auto, außerhalb des Bildes leiser; Stereolage aus der Bildposition.
	var db := (PLAYER_DB if v.is_player else RIVAL_DB) + float(v.car.get("gain_db", 0.0)) + rev_db(v) + linear_to_db(maxf(0.0001, level))
	if not v.is_player and camera != null:
		var world_pos := Vector3(vehicle.pos.x, 0.4, vehicle.pos.y)
		var sp := camera.unproject_position(world_pos)
		var nx := sp.x / maxf(1.0, screen.x)
		var ny := sp.y / maxf(1.0, screen.y)
		var off := maxf(0.0, maxf(absf(nx - 0.5), absf(ny - 0.5)) - 0.5)
		if camera.is_position_behind(world_pos):
			off = 1.0
		db -= clampf((vehicle.pos.distance_to(own_pos) - 6.0) * 0.4, 0.0, 16.0) + off * 30.0
		if v.panner != null:
			v.panner.pan = clampf((nx - 0.5) * 1.7, -0.85, 0.85)
	elif v.panner != null:
		v.panner.pan = 0.0
	if stopped:
		db -= 10.0
	mix_voice(v, db, dt, goal)
	drive_turbo(v, vehicle.boosting and not stopped, speed, stopped, level)
	drive_pops(v, dt, db, v.is_player or vehicle.pos.distance_to(own_pos) < 25.0)
	v.prev_throttle = v.throttle

func rev_db(v: Voice) -> float:
	if str(v.car.get("dynamics", "")) == "baked":
		return BAKED_DB
	return REV_DB * clampf((v.rpm - float(v.car.idle)) / (float(v.car.redline) - float(v.car.idle)), 0.0, 1.0)

func mix_voice(v: Voice, db: float, dt := 0.0, goal := 0.0) -> void:
	# Zwei benachbarte Drehzahlschichten gleichleistig überblenden, Last gegen Schub nach Gas. Steht der Motor bei Vollgas an
	# der Rotgrenze, übernimmt die Begrenzer-Schleife (Zündunterbrechung, aufgenommen im Leerlauf mit Vollgas).
	v.phase = fposmod(v.phase + v.rpm * v.detune / 120.0 * dt, 1.0)
	var red := float(v.car.redline) * 0.97
	var at_limit := v.limiter != null and goal >= red * LIMIT_AT and v.rpm >= red * (LIMIT_AT - 0.02) and v.throttle > 0.7
	v.limit_amt = move_toward(v.limit_amt, 1.0 if at_limit else 0.0, dt * (14.0 if at_limit else 8.0))
	if v.limiter != null:
		var lim_on := v.limit_amt > 0.002
		if lim_on == v.limiter.stream_paused:
			v.limiter.stream_paused = not lim_on
			if lim_on:
				v.limiter.seek(0.0)
		if lim_on:
			v.limiter.pitch_scale = v.detune
			v.limiter.volume_db = db + linear_to_db(maxf(0.0001, sqrt(v.limit_amt)))
	var keep := sqrt(1.0 - v.limit_amt)
	var baked := str(v.car.get("dynamics", "")) == "baked"
	var rpms := v.rpms
	var r := clampf(v.rpm, rpms[0], rpms[rpms.size() - 1])
	var k := 0
	while k < rpms.size() - 2 and r >= rpms[k + 1]:
		k += 1
	var w := clampf((r - rpms[k]) / (rpms[k + 1] - rpms[k]), 0.0, 1.0)
	# Synthetische Schichten mischten immer etwas Last bei; in den Aufnahmen sind Last und Schub getrennt
	var load_w := (sqrt(v.throttle) if baked else sqrt(0.14 + 0.86 * v.throttle)) * keep
	var coast_w := (sqrt(maxf(0.0, 1.0 - v.throttle)) if baked else sqrt(maxf(0.0, 1.0 - 0.86 * v.throttle))) * keep
	var wanted := {}
	if cos(w * PI * 0.5) * keep > 0.002:
		wanted[k] = cos(w * PI * 0.5)
	if sin(w * PI * 0.5) * keep > 0.002:
		wanted[k + 1] = sin(w * PI * 0.5)
	# Abspielerpaare freigeben, deren Schicht nicht mehr gebraucht wird; neue Schichten auf freie Paare legen (sie beginnen
	# mit Gewicht nahe 0, der Neustart ist daher unhörbar)
	for i in range(SLOTS):
		if v.slot_layer[i] != -1 and not wanted.has(v.slot_layer[i]):
			v.load_players[i].stop()
			v.coast_players[i].stop()
			v.slot_layer[i] = -1
	for layer in wanted:
		if v.slot_layer.has(layer):
			continue
		var free := v.slot_layer.find(-1)
		if free == -1:
			continue
		v.slot_layer[free] = layer
		var info: Dictionary = v.car.layers[layer]
		# Stelle im Arbeitsspiel aus der tatsächlichen Abspielposition einer laufenden Schicht (genauer als mitgezählt). Godot meldet
		# dort das Ende des zuletzt gemischten Blocks; genau dort beginnt die neue Schicht mit dem nächsten Block.
		var ref_phase := slot_phase(v)
		if ref_phase >= 0.0:
			v.phase = ref_phase
		var start_phase := v.phase
		for mode in ["load", "coast"]:
			var pl: AudioStreamPlayer = (v.load_players if mode == "load" else v.coast_players)[free]
			var st := layer_stream(info, mode)
			pl.stream = st
			# Die Schleifen sind auf gleiche Zündlage gedreht (tools/record_engines.py): an derselben Stelle des Arbeitsspiels
			# einsetzen wie die laufende Schicht, in einem zufälligen ganzen Arbeitsspiel der Schleife
			var cycles := int(info.get("coast_cycles" if mode == "coast" else "cycles", 0))
			var at := rng.randf() * 0.9 * float(st.loop_end)
			if cycles > 0:
				at = (float(rng.randi_range(0, cycles - 1)) + start_phase) * float(st.loop_end) / float(cycles)
			pl.play(at / float(st.mix_rate))
	for i in range(SLOTS):
		var layer := v.slot_layer[i]
		if layer == -1:
			continue
		var g: float = wanted[layer]
		v.load_players[i].pitch_scale = v.rpm / rpms[layer] * v.detune
		v.coast_players[i].pitch_scale = v.rpm / float(v.car.layers[layer].get("coast_rpm", rpms[layer])) * v.detune
		v.load_players[i].volume_db = db + linear_to_db(maxf(0.0001, g * load_w))
		v.coast_players[i].volume_db = db + linear_to_db(maxf(0.0001, g * coast_w))

func slot_phase(v: Voice) -> float:
	# Stelle im Arbeitsspiel (0..1) der lautesten laufenden Lastschicht; -1 wenn keine läuft.
	var best := -1
	for i in range(SLOTS):
		if v.slot_layer[i] != -1 and v.load_players[i].playing and (best == -1 or v.load_players[i].volume_db > v.load_players[best].volume_db):
			best = i
	if best == -1:
		return -1.0
	var pl := v.load_players[best]
	var st := pl.stream as AudioStreamWAV
	var cycles := int(v.car.layers[v.slot_layer[best]].get("cycles", 0))
	if st == null or cycles <= 0:
		return -1.0
	var pos := pl.get_playback_position() * float(st.mix_rate)
	return fposmod(pos / (float(st.loop_end) / float(cycles)), 1.0)

func drive_turbo(v: Voice, boosting: bool, speed: float, stopped: bool, gain: float) -> void:
	# Nur eigenes Auto: Pfeifen solange der Turbo zündet, beim Ende das Schubumluftventil.
	if v.turbo == null:
		return
	if boosting == v.turbo.stream_paused:
		v.turbo.stream_paused = not boosting
	if boosting:
		v.turbo.pitch_scale = 0.8 + speed * 0.02
		v.turbo.volume_db = -16.0 + linear_to_db(maxf(0.0001, gain))
	if v.prev_boost and not boosting and not stopped:
		bov_player.stream = stream("bov_%s.wav" % str(v.car.turbo), 0, false)
		bov_player.volume_db = -10.0 + linear_to_db(maxf(0.0001, gain))
		bov_player.play()
	v.prev_boost = boosting

func drive_pops(v: Voice, dt: float, db: float, audible: bool) -> void:
	# Fehlzündungen im Schub (Rallye-, Muskel- und Driftauto)
	if not bool(v.car.get("pops", false)):
		return
	var frac_rpm := clampf((v.rpm - float(v.car.idle)) / (float(v.car.redline) - float(v.car.idle)), 0.0, 1.0)
	if v.prev_throttle > 0.65 and v.throttle < 0.35 and frac_rpm > 0.45 and audible:
		v.pops_left = rng.randi_range(1, 4)
		v.pop_wait = 0.03
	if v.pops_left > 0:
		v.pop_wait -= dt
		if v.pop_wait <= 0.0:
			var pop := pop_players[v.pops_left % pop_players.size()]
			pop.stream = stream("pop_%d.wav" % rng.randi_range(0, 3), 0, false)
			pop.volume_db = db - 9.0 + rng.randf_range(-3.0, 1.0)
			pop.play()
			v.pops_left -= 1
			v.pop_wait = rng.randf_range(0.07, 0.22)

func _exit_tree() -> void:
	clear()
