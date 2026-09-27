class_name RaceSound
extends Node

# Klang und Musik. Liest den Simulationszustand nur aus; schreibt nie zurück (Leitplanke 4).
const RATE := 22050
const MUSIC_DIR := "res://assets/music/"
const CROSSFADE := 2.5
# Absenkung je Spielphase in dB (Zeichnen: konzentrieren; Rennen: volle Energie).
const PHASE_DUCK := {"menu": 0.0, "draw": -15.0, "countdown": -5.0, "race": -5.0, "result": 0.0}
const MUSIC_BASE_DB := -7.0
# Simulierte Getriebestufen (Spielgeschwindigkeit, m/s); nur für die Tonhöhe des Motors.
const GEARS := [0.0, 4.5, 8.0, 11.5, 15.0, 19.0, 26.0]

var engine_load := AudioStreamPlayer.new()
var engine_coast := AudioStreamPlayer.new()
var turbo_whine := AudioStreamPlayer.new()
var squeal := AudioStreamPlayer.new()
var gravel := AudioStreamPlayer.new()
var chime := AudioStreamPlayer.new()
var horn := AudioStreamPlayer.new()
var music_a := AudioStreamPlayer.new()
var music_b := AudioStreamPlayer.new()
var enabled := true
var music_style := "energie"
var context := "menu"
var won := false

var horn_red: AudioStreamWAV
var horn_green: AudioStreamWAV
var tracks: Array = []
var queue: Array = []
var current: Dictionary = {}
var active: AudioStreamPlayer
var fading: AudioStreamPlayer
var fade := 1.0
var fade_from_db := -80.0
var special := ""
var special_played: Array = []
var headless := false
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Eigene Audiokanäle für Musik und Geräusche; die Lautstärkeregler im Soundmenü steuern diese Kanäle.
	for bus in ["Music","SFX"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count-1, bus)
			AudioServer.set_bus_send(AudioServer.bus_count-1, "Master")
	for player in [engine_load,engine_coast,turbo_whine,squeal,gravel,chime,horn,music_a,music_b]:
		add_child(player)
		player.bus = "Music" if player in [music_a,music_b] else "SFX"
	active = music_a
	fading = music_b
	headless = DisplayServer.get_name()=="headless"
	if headless:
		return
	rng.randomize()
	engine_load.stream = engine_loop(true)
	engine_coast.stream = engine_loop(false)
	turbo_whine.stream = tone_loop(1.0,2)
	squeal.stream = tone_loop(1.0,0)
	gravel.stream = tone_loop(1.0,1)
	chime.stream = click_sound()
	horn_red = horn_sound(0.42,440.0)
	horn_green = horn_sound(1.1,880.0)
	for player in [engine_load,engine_coast,turbo_whine,squeal,gravel]:
		player.volume_db = -80
		player.play()
	load_manifest()

# ---------- Synthese ----------

func wav(bytes: PackedByteArray, loop: bool, count: int) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		# WAV-Loop-Endpunkte sind Sample-Indizes, nicht die Sample-Anzahl.
		w.loop_end = count - 1
	return w

func engine_loop(under_load: bool) -> AudioStreamWAV:
	# Grundton 80 Hz (ganzzahlig -> nahtloser 1-s-Loop; 40 Hz gaben Handylautsprecher kaum wieder). Zündimpulse mit leichtem Jitter,
	# unter Last mehr Obertöne und Rauheit, im Schiebebetrieb weicher mit vereinzeltem Blubbern.
	var count := RATE
	var bytes := PackedByteArray()
	bytes.resize(count*2)
	var r := RandomNumberGenerator.new()
	r.seed = 7 if under_load else 8
	var jitter := PackedFloat32Array()
	for i in range(81):
		jitter.append(r.randf_range(0.75,1.25))
	var low := 0.0
	for i in range(count):
		var t := float(i)/RATE
		var cycle := t*80.0
		var k := int(cycle)%80
		var ph := fmod(cycle,1.0)
		var pulse := exp(-ph*(9.0 if under_load else 14.0))*jitter[k]
		var value := 0.0
		var harmonics := 12 if under_load else 7
		for h in range(1,harmonics+1):
			value += sin(TAU*80.0*h*t + h*0.7)/pow(h,0.6 if under_load else 1.0)
		value = value*0.12*(0.55+pulse*0.9)
		low = lerpf(low,r.randf_range(-1.0,1.0),0.08)
		value += low*(0.10 if under_load else 0.05)*pulse
		if not under_load and k%13==0 and ph<0.15:
			value += r.randf_range(-0.35,0.35)
		bytes.encode_s16(i*2,int(clampf(value,-1,1)*30000))
	return wav(bytes,true,count)

func tone_loop(duration: float, kind: int) -> AudioStreamWAV:
	var count := int(duration*RATE)
	var bytes := PackedByteArray()
	bytes.resize(count*2)
	var r := RandomNumberGenerator.new()
	r.seed = 44+kind
	var band := 0.0
	var band2 := 0.0
	for i in range(count):
		var t := float(i)/RATE
		var value := 0.0
		match kind:
			0: # Reifenquietschen: schmalbandiges Rauschen um ~1,6 kHz mit leichtem Wabern
				var noise := r.randf_range(-1.0,1.0)
				band = lerpf(band,noise,0.35)
				band2 = lerpf(band2,band,0.35)
				value = (band-band2)*1.6*sin(TAU*1600.0*t + sin(TAU*6.0*t)*3.0)*0.9
				value += sin(TAU*1800.0*t + sin(TAU*4.0*t)*2.0)*0.18
			1: # Schotter/Erde: dumpfes Rauschen mit prasselnden Einzelkörnern
				band = lerpf(band,r.randf_range(-1.0,1.0),0.12)
				value = band*0.8
				if r.randf()<0.004:
					band2 = r.randf_range(0.4,0.9)*(1.0 if r.randf()<0.5 else -1.0)
				value += band2
				band2 *= 0.93
			2: # Turbo: helles Pfeifen mit Luftrauschen
				value = sin(TAU*2400.0*t)*0.35 + sin(TAU*4800.0*t)*0.08 + r.randf_range(-1.0,1.0)*0.06
		bytes.encode_s16(i*2,int(clampf(value,-1,1)*26000))
	return wav(bytes,true,count)

func horn_sound(duration: float, freq: float) -> AudioStreamWAV:
	# Signalhorn: rechteckähnlicher Klang (ungerade Obertöne), leicht verstimmt, weiche Hüllkurve.
	var count := int(duration*RATE)
	var bytes := PackedByteArray()
	bytes.resize(count*2)
	for i in range(count):
		var t := float(i)/RATE
		var env := minf(1.0,t/0.012)*minf(1.0,(duration-t)/0.06)
		var value := 0.0
		for h in [1,3,5,7]:
			value += (sin(TAU*freq*h*t)+sin(TAU*freq*1.004*h*t))/h
		bytes.encode_s16(i*2,int(clampf(value*0.22*env,-1,1)*30000))
	return wav(bytes,false,count)

func click_sound() -> AudioStreamWAV:
	var count := int(0.07*RATE)
	var bytes := PackedByteArray()
	bytes.resize(count*2)
	var r := RandomNumberGenerator.new()
	r.seed = 3
	for i in range(count):
		var t := float(i)/RATE
		var value := sin(TAU*1250.0*t)*exp(-t*70.0)*0.5 + r.randf_range(-1.0,1.0)*exp(-t*260.0)*0.35
		bytes.encode_s16(i*2,int(clampf(value,-1,1)*30000))
	return wav(bytes,false,count)

# ---------- Effekte ----------

func start_signal(green: bool) -> void:
	if headless or not enabled:
		return
	horn.stream = horn_green if green else horn_red
	horn.volume_db = -6.0
	horn.play()

func set_volumes(music_volume: float, sfx_volume: float) -> void:
	# 0..1 (linear, wie der Regler); 0 = stumm.
	for pair in [["Music",music_volume],["SFX",sfx_volume]]:
		var index := AudioServer.get_bus_index(pair[0])
		if index == -1:
			continue
		var v := clampf(float(pair[1]),0.0,1.0)
		AudioServer.set_bus_mute(index, v <= 0.001)
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(v,0.001)))

func click() -> void:
	if enabled and chime.stream!=null:
		chime.play()

func engine_pitch(speed: float) -> float:
	for g in range(1,GEARS.size()):
		if speed < GEARS[g] or g==GEARS.size()-1:
			var frac := clampf((speed-GEARS[g-1])/(GEARS[g]-GEARS[g-1]),0.0,1.0)
			return (0.62 if g==1 else 0.95) + frac*(1.35 if g==1 else 1.05)
	return 2.0

func tick(vehicle: RaceVehicle, racing: bool, paused: bool, sfx: bool, music_on: bool, track: Circuit = null, dt := 0.016) -> void:
	for player in [engine_load,engine_coast,turbo_whine,squeal,gravel]:
		player.stream_paused = paused
	update_music(paused,music_on,dt)
	if headless:
		return
	if not racing or vehicle == null or not sfx:
		for player in [engine_load,engine_coast,turbo_whine,squeal,gravel]:
			player.volume_db = -80
		return
	var speed := vehicle.velocity.length()
	var pitch := engine_pitch(speed)
	var throttle := clampf(vehicle.throttle,0.0,1.0)
	engine_load.pitch_scale = pitch
	engine_coast.pitch_scale = pitch
	engine_load.volume_db = linear_to_db(0.10+throttle*0.45) + 2.0
	engine_coast.volume_db = linear_to_db(0.08+(1.0-throttle)*0.25) + 1.0
	turbo_whine.pitch_scale = 0.8+speed*0.02
	turbo_whine.volume_db = -16.0 if vehicle.boosting else -80.0
	var skid := clampf((vehicle.slip-0.10)*2.2,0.0,1.0)*clampf(speed/6.0,0.0,1.0)
	skid = maxf(skid,clampf(vehicle.braking/12.0,0.0,1.0)*clampf(speed/8.0,0.0,1.0)*0.6)
	var kind := "asphalt"
	if track != null:
		kind = str(track.surface_at(vehicle.pos).kind)
	var loose := kind in ["dirt","mud","gravel"]
	var rolling := clampf(speed/10.0,0.0,1.0)
	squeal.pitch_scale = 0.9+speed*0.01
	squeal.volume_db = linear_to_db(maxf(0.0001,skid*0.5)) - 6.0 if not loose else -80.0
	gravel.pitch_scale = 0.7 if kind=="mud" else (1.25 if kind=="gravel" else 1.0)
	gravel.volume_db = linear_to_db(maxf(0.0001,(rolling*0.35+skid*0.45))) - 4.0 if loose else -80.0

# ---------- Musik ----------

func load_manifest() -> void:
	var path := MUSIC_DIR + "music.json"
	if not FileAccess.file_exists(path):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary and parsed.get("tracks") is Array:
		tracks = parsed.tracks

func candidates(role: String) -> Array:
	var list := tracks.filter(func(t): return t.role==role and t.set==music_style)
	if list.is_empty():
		list = tracks.filter(func(t): return t.role==role)
	return list

func next_playlist_track() -> Dictionary:
	if queue.is_empty():
		queue = candidates("playlist").duplicate()
		queue.shuffle()
	# Nicht dasselbe Stück direkt wiederholen (auch nach Stilwechsel).
	if queue.size()>1 and not current.is_empty() and queue[0].file==current.file:
		queue.push_back(queue.pop_front())
	return queue.pop_front() if not queue.is_empty() else {}

func next_special_track(role: String) -> Dictionary:
	var list := candidates(role).filter(func(t): return not t.file in special_played)
	if list.is_empty():
		special_played.clear()
		list = candidates(role)
	if list.is_empty():
		return {}
	var pick: Dictionary = list[rng.randi_range(0,list.size()-1)]
	special_played.append(pick.file)
	return pick

func start_track(t: Dictionary, crossfade := CROSSFADE) -> void:
	if t.is_empty():
		return
	var stream = load(MUSIC_DIR + str(t.file))
	if stream == null:
		return
	var old := active
	fade_from_db = old.volume_db if old.playing else -80.0
	active = fading
	fading = old
	current = t
	active.stream = stream
	active.volume_db = -80
	active.play(float(t.get("mix_in",0.0)))
	fade = 0.0 if crossfade>0.0 else 1.0
	set_meta("crossfade",maxf(crossfade,0.01))

func set_style(style: String) -> void:
	if style == music_style:
		return
	music_style = style
	queue.clear()
	special_played.clear()
	if not headless and not tracks.is_empty():
		start_track(next_special_track(special) if special!="" else next_playlist_track(),1.5)

func set_context(phase: String, result_won := false) -> void:
	var previous := context
	context = phase
	if headless or tracks.is_empty():
		return
	if phase=="result" and previous!="result":
		special = "sieg" if result_won else "niederlage"
		start_track(next_special_track(special),1.2)
	elif phase!="result" and special!="":
		special = ""
		start_track(next_playlist_track(),2.0)

func update_music(paused: bool, music_on: bool, dt: float) -> void:
	if headless or tracks.is_empty():
		return
	if current.is_empty():
		start_track(next_playlist_track(),0.0)
		return
	fade = minf(1.0,fade+dt/float(get_meta("crossfade",CROSSFADE)))
	var duck: float = PHASE_DUCK.get(context,0.0) + (-8.0 if paused else 0.0)
	var gain := MUSIC_BASE_DB + float(current.get("gain_db",0.0)) + duck
	if not music_on:
		active.volume_db = -80
		fading.volume_db = -80
		return
	active.volume_db = gain + linear_to_db(maxf(0.0001,fade))
	fading.volume_db = fade_from_db + linear_to_db(maxf(0.0001,1.0-fade))
	if fade>=1.0 and fading.playing:
		fading.stop()
	# Am vorab gemessenen Ausklingpunkt schon das nächste Stück einblenden.
	var mix_out := float(current.get("mix_out",0.0))
	var pos := active.get_playback_position()
	if (mix_out>0.0 and pos>=mix_out) or not active.playing:
		if special!="":
			# Niederlage/Sieg: in der Ergebnisansicht weitere Stücke derselben Rolle, sonst zurück zur Playlist.
			start_track(next_special_track(special) if context=="result" else next_playlist_track())
		else:
			start_track(next_playlist_track())

func _exit_tree() -> void:
	for player in [engine_load,engine_coast,turbo_whine,squeal,gravel,chime,horn,music_a,music_b]:
		player.stop()
		player.stream = null
