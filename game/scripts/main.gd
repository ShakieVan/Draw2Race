extends Node3D

# Streckenreihenfolge der Karriere; die nächste Strecke öffnet sich mit 3 Gold auf der vorigen.
const TRACKS := ["azure","city","forest","harbor","serra","fair","quarry","arena","kids"]
# Bonusstrecke: nicht über die Vorgängerstrecke, sondern über die Gesamtzahl an Gold freigeschaltet.
const BONUS_TRACKS := {"kids": 12}
var track_id := "azure"
var track := Circuit.new()
var recorder: LineRecorder
var store := ProgressStore.new()
var world := Diorama.new()
var hud := RaceHUD.new()
var camera := Camera3D.new()
# Perspektivische Kamera (wie DrawRace 2): beim Zeichnen senkrecht von oben, im Rennen leicht geneigt.
# "cam_zoom" ist die sichtbare Höhe im Blickzentrum (Meter, wie früher die Ortho-Größe); daraus folgt der Abstand.
const PITCH_DRAW := deg_to_rad(90.0)
const PITCH_RACE := deg_to_rad(72.0)
const CAM_FOV := 40.0
var cam_zoom := 60.0
var cam_pitch := PITCH_DRAW
var sound := RaceSound.new()
var updater := Updater.new()
var apk_share := ApkShare.new()    # eigene APK teilen bzw. im WLAN weitergeben (Updates-Dialog, NetLobby)
var vehicles: Array[RaceVehicle] = []
var models: Array[Node3D] = []
var phase := "menu"
var stage := 0
var car_choice := 0
var was_airborne: Array = []     # je Fahrzeug: Zustand im letzten Schritt (nur für Stoßgeräusche, Darstellung)
var was_crashed: Array = []
var last_vz: Array = []
var was_boosting := false
var race_time := 0.0
var countdown := 3.0
var paused := false
var turbo_held := false
var pointer := -99
var demonstration := false
var draw_clock := 0.0
# Handkamera beim Zeichnen: Ziehen verschiebt, zwei Finger zoomen, Doppeltipp zeigt die ganze Strecke.
# Gemalt wird nur, wenn der Finger im offenen (schimmernden) Linienende bzw. am Startpunkt aufsetzt.
const GRAB_PX := 64.0          # Greifradius in Bildpunkten (unabhängig vom Zoom)
const PINCH_GRACE := 0.15      # zweiter Finger so kurz nach Malbeginn -> Zoom statt Malen
const MOUSE_ID := 1000
var touches := {}              # Finger-Index -> Bildschirmposition
var pan_index := -99
var pinch_ids: Array = []
var pinch_dist := 0.0
var pinch_mid := Vector2.ZERO
var stroke_started := 0.0
var stroke_origin := Vector2.ZERO
var last_tap := -10.0
var last_tap_pos := Vector2.ZERO
var view_focus := Vector3.ZERO
var view_zoom := 60.0
var skid_tick := 0
var camera_target := Vector3.ZERO
var capture_frames := 0
var run_record_path := "user://last_run.json"
var turbo_actions: Array[Dictionary] = []
var crash_wait: Array[float] = []   # je Auto: Zeit seit dem Ausscheiden (nur Menschen; bis zum Ergebnis noch kurz zusehen)
# Mehrere Menschen (M2, docs/MULTIPLAYER_RECHERCHE.md 5.3). me: Index meines Autos in vehicles – nur Darstellung (Kamera, HUD, Ton,
# Halo, Ergebnis), die Simulation hängt nicht davon ab. Einzelspieler: 0.
# race_entries: Teilnehmerliste fürs nächste Rennen (RaceField.human_entry/ai_entry, z. B. RaceField.lineup); leer = Einzelspieler mit
# recorder.route und car_choice. race_me: mein Listenplatz darin. remote_turbo: Turbo-Eingabe der übrigen Menschen je Autoindex
# (Weitergeben, später das Netz); ohne Eintrag fährt ein Mensch ohne Turbo.
var me := 0
var race_entries: Array = []
var race_me := 0
var remote_turbo := {}
var turbo_input: Array[bool] = []
# Namen und Sprechblasen (M1, MULTIPLAYER_RECHERCHE.md 6) – nur Darstellung: car_names je Auto (NameTags.names_for), chatter liest
# nach jedem Takt die Fahrzeugzustände und erzeugt daraus die Blasen; gezeichnet wird beides von hud.tags.
var car_names: Array[String] = []
var chatter := RaceChatter.new()
# Geisterauto: beste eigene Fahrt je Strecke/Herausforderung (Linie + Turbo-Einsätze), ungestört wiedergegeben.
var ghost: RaceVehicle
var ghost_model: Node3D
var ghost_turbo: Array = []
var last_boost_input := false
var result_record := false
var result_won := false
# Starterfeld, Wippen und Takt (Aufstellung, Gegnerstärke und -spuren stehen in RaceField).
var field: RaceField
const RIVAL_LANES := RaceField.RIVAL_LANES
# Mehrspieler „Weitergeben“ (M2b): party = Einstellungen und Linien der laufenden Runde (PassParty), null im Einzelspieler.
# Phasen: party_setup → handover (Übergabekarte) → draw → drawn (Linie fertig) → … → reveal (alle Linien) → countdown → race → result.
# Nichts davon schreibt in den Spielstand; beim Verlassen gelten wieder Strecke und Herausforderung des Einzelspielers (solo_*).
var party: PassParty
var party_memory: PassParty      # zuletzt eingestellte Runde (nur in dieser Sitzung)
var solo_track := ""
var solo_stage := 0
var reveal_time := 0.0
var pad_touch := {}              # Finger-Index -> Autoindex (Turboknöpfe, mehrere Finger gleichzeitig)
var pad_held := {}               # Autoindex -> Knopf gehalten
const PLAYER_KEYS := [KEY_1, KEY_2, KEY_3, KEY_4]   # Turbo am PC je Spieler (zum Ausprobieren ohne Handy)
const RIVAL_SKILL := RaceField.RIVAL_SKILL
# Mehrspieler im WLAN (M3/M4): lobby = Netz-Lobby (NetLobby), solange der WLAN-Mehrspieler offen ist, sonst null. Phasen: net_menu
# (Eröffnen/Beitreten, Suche) → net_lobby (Spieler, Einstellungen, Bereit) → net_round (Strecke laden) → net_countdown (gemeinsames
# 3-2-1) → draw (jeder zeichnet seine Linie, normale Zeichenansicht) → net_drawn (Linie fertig, abgeben bzw. warten) → net_reveal
# (alle Linien in Spielerfarben) → countdown (gemeinsame Ampel) → race → result (M5: Wertung vom Gastgeber, Revanche oder Lobby).
# Zeitpunkte und Linien: lobby.draw (NetDraw), das Rennen: lobby.race (NetRace) – der Gastgeber rechnet dort, alle Geräte zeigen die
# Marionetten lobby.race.view mit der gemeinsamen Verzögerung (net_race_step). net_start bleibt nur als Rückfall ohne Rennen.
# net_round = Daten der laufenden Runde (NetLobby.current_round). Wie „Weitergeben“: alles frei, nichts in den Spielstand (außer dem
# eigenen Namen, den man in der Lobby wie in den Optionen ändert).
var lobby: NetLobby
var net_round := {}
var net_count := 0               # Ampel im Netz: zuletzt gezeigte Ziffer (Ton bei jedem Wechsel)
var net_music_won := false       # Musik der WLAN-Wertung (alle hören dasselbe Stück): Sieg-Stück, wenn ein Mensch gewonnen hat
var net_reported := -1           # Runde, für die „geladen“ schon gemeldet ist

func _ready() -> void:
	get_tree().auto_accept_quit = true
	get_tree().quit_on_go_back = false
	var saved := str(store.data.get("track","azure"))
	track_id = saved if saved in TRACKS and track_unlocked(TRACKS.find(saved)) else "azure"
	track = Circuit.load_track(track_id)
	car_choice = clampi(int(store.data.get("car",0)),0,RaceVehicle.CARS.size()-1)
	# Leere Welt (Atmosphäre, Marke, Linien), bis die eigentliche im Hintergrund steht: das Menü erscheint sofort.
	add_child(world)
	world.build_shell()
	get_tree().process_frame.connect(_load_tick)
	_start_world()
	apply_atmosphere()
	add_child(camera)
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = CAM_FOV
	camera.near = 0.5
	camera.far = 900
	cam_zoom = overview_size()
	camera_target = track_center()
	set_camera(camera_target)
	add_child(sound)
	add_child(updater)
	updater.setup(store)
	add_child(apk_share)
	apk_share.setup()
	add_child(hud)
	hud.setup(self)
	updater.changed.connect(func(): if phase == "menu" and not hud.overlay_open(): hud.menu())
	# Automatische Prüfung höchstens einmal täglich, nur auf dem Handy.
	if OS.get_name() == "Android":
		updater.check(false)
	show_menu()
	if "--demo" in OS.get_cmdline_user_args():
		demo()

var drift_limit_cache := {}

func drift_limit() -> float:
	# Zeitlimit im Drift-Modus: aus der Strecke oder – falls nicht angegeben – 1,4 × Fahrzeit einer
	# vorsichtigen KI-Fahrt (einmal je Strecke berechnet).
	if track.time_limit > 0.0:
		return track.time_limit
	if not drift_limit_cache.has(track_id):
		var bot := RaceVehicle.new(track, track.ai_route(1.0))
		for tick in range(60 * 240):
			bot.step(1.0 / 60.0, false, float(tick + 1) / 60.0)
			if bot.finish_time >= 0.0 or bot.crashed:
				break
		drift_limit_cache[track_id] = maxf(30.0, bot.finish_time * 1.4)
	return drift_limit_cache[track_id]

func drift_target() -> int:
	var targets: Array = track.drift_targets
	return int(targets[mini(stage, targets.size() - 1)]) if not targets.is_empty() else 1000

func lap_text(progress: float) -> String:
	# Rundkurs: „RUNDE x / n“; Sprintstrecke: zurückgelegter Anteil.
	if track.open:
		return "SPRINT %d %%" % int(clampf(progress, 0.0, 1.0) * 100.0)
	return "RUNDE %d / %d" % [mini(track.laps, maxi(1, int(progress) + 1)), track.laps]

func track_center() -> Vector3:
	var c := track.bounds.get_center()
	return Vector3(c.x,0,c.y)

func car_unlocked(index: int) -> bool:
	return debug_flag("unlock") or store.data.gold.size() >= int(RaceVehicle.CARS[index].unlock)

# Tageszeit/Wetter/Nebel gehören fest zur Herausforderung. Nur das versteckte Debug-Menü darf sie überschreiben.
func debug_data() -> Dictionary:
	if not store.data.get("debug") is Dictionary:
		store.data["debug"] = {}
	return store.data.debug

func debug_flag(key: String) -> bool:
	return bool(debug_data().get(key,false))

func current_conditions() -> Dictionary:
	var result := track.conditions_for(stage)
	var override = debug_data().get("override") if party == null and lobby == null else null
	if override is Dictionary:
		for key in ["time","weather","fog"]:
			if override.has(key):
				result[key] = override[key]
		result.fog = int(result.fog)
	return result

func apply_atmosphere() -> void:
	# Nur Darstellung plus Wetter-Haftung; Qualität 0-2 aus den Einstellungen.
	world.atmosphere.apply(current_conditions(),int(store.data.get("gfx",2)))
	RaceVehicle.weather_grip = world.atmosphere.grip_factor()

func select_car(index: int) -> void:
	car_choice = posmod(index, RaceVehicle.CARS.size())
	store.data["car"] = car_choice
	store.save()
	sound.preview_engine(str(RaceVehicle.CARS[car_choice].id))

func track_unlocked(index: int) -> bool:
	if index <= 0 or debug_flag("unlock"):
		return true
	if BONUS_TRACKS.has(TRACKS[index]):
		return store.data.gold.size() >= int(BONUS_TRACKS[TRACKS[index]])
	return store.gold_count(TRACKS[index-1]) >= 3

func select_track(new_id: String) -> void:
	# Strecke wählen und speichern, Welt am Stück (Prüfungen, Werkzeuge). Das Menü nimmt pick_track (Welt im Hintergrund).
	if new_id == track_id and track_ready():
		return
	store.data["track"] = new_id
	store.save()
	load_track(new_id)

func pick_track(new_id: String) -> void:
	# Streckenwahl im Menü: speichern, Welt im Hintergrund (Knöpfe zeigen bis dahin „Strecke lädt …“).
	if new_id == track_id:
		return
	store.data["track"] = new_id
	store.save()
	request_track(new_id)

func load_track(new_id: String) -> void:
	# Strecke laden und die Welt am Stück neu aufbauen, ohne den Spielstand anzufassen (Mehrspieler: Wahl gilt nur für die Runde).
	if new_id == track_id and track_ready():
		return
	request_track(new_id)
	finish_track_load()
	world.visible = phase != "menu"

# ---------- Strecke im Hintergrund laden (Nutzerwunsch 04.10.2026: Oberfläche bleibt bedienbar) ----------
# Die Streckendaten (Circuit samt Hindernissen aus der Diorama-Begleitdatei) lädt request_track sofort und vollständig – nur sie
# bestimmen die Simulation. Die sichtbare Welt entsteht danach im Hintergrund: Diorama.build_async in Zeitscheiben (LOAD_SLICE_USEC je
# Bild), das Diorama-Modell und die Lichtkarte in Arbeitsfäden. Netz, Musik und Bedienung laufen weiter. Bis die neue Welt steht, bleibt
# die bisherige (ausgeblendete) „world“; Knöpfe, die die Strecke zeigen, sind so lange gesperrt („Strecke lädt …“, RaceHUD.gate).
# Eine neue Wahl bricht einen laufenden Bau ab. Alte Welten werden Knoten für Knoten abgerissen (WRECK_SLICE_USEC je Bild).
# finish_track_load() stellt die Welt sofort fertig (am Stück) – Sicherheitsnetz für alles, was sie zeigt oder für ein Rennen braucht.
const LOAD_SLICE_USEC := 8000
const WRECK_SLICE_USEC := 4000
var next_world: Diorama            # Welt im Bau (null: world gehört zu track)
var wreck: Array = []              # Stapel abzureißender Knoten
var wreck_open := {}               # Knoten, deren Kinder schon auf dem Stapel liegen
signal track_loaded

func track_ready() -> bool:
	return next_world == null

func request_track(new_id: String) -> void:
	# Strecke wechseln: Streckendaten sofort, die Welt im Hintergrund (Ende: _world_done). Zurück zur gezeigten Welt kostet nichts.
	if new_id == track_id:
		return
	track_id = new_id
	if next_world != null:
		next_world.abort()
		next_world = null
	if world.built and world.track != null and world.track.id == new_id:
		track = world.track
		camera_target = track_center()
		apply_atmosphere()
		_loaded()
		return
	track = Circuit.load_track(new_id)
	camera_target = track_center()
	_start_world()

func _start_world() -> void:
	var next := Diorama.new()
	next.low_detail = int(store.data.get("gfx",2)) == 0
	next.visible = false
	next.slice_usec = LOAD_SLICE_USEC
	add_child(next)
	move_child(next, 0)
	next_world = next
	next.finished.connect(_world_done.bind(next), CONNECT_ONE_SHOT)
	if is_instance_valid(hud) and hud.root != null:
		hud.update_gates()
	next.build_async(track)

func _world_done(w: Diorama) -> void:
	# Bau beendet: fertige Welt einsetzen (Sichtbarkeit wie die bisherige), die alte abreißen. Abgebrochene Bauten nur abreißen.
	if w != next_world or not w.built:
		demolish(w)
		return
	next_world = null
	var old := world
	world = w
	world.visible = old.visible
	demolish(old)
	apply_atmosphere()
	_loaded()

func _loaded() -> void:
	if is_instance_valid(hud) and hud.root != null:
		hud.update_gates()
	track_loaded.emit()
	net_report_loaded()

func finish_track_load() -> void:
	# Welt sofort fertig (am Stück, blockiert): Sicherheitsnetz vor allem, was die Strecke zeigt (Zeichnen, Vorführfahrt, Rennen).
	if next_world == null:
		return
	sound.finish_crossfade()
	next_world.finish_now()

func demolish(w: Node) -> void:
	# Welt ausblenden, anhalten und Knoten für Knoten abreißen (_load_tick); ein queue_free der ganzen Welt kostete ein Bild bis 0,4 s.
	if not is_instance_valid(w) or wreck.has(w):
		return
	(w as Node3D).visible = false
	w.process_mode = Node.PROCESS_MODE_DISABLED
	wreck.push_front(w)

func _exit_tree() -> void:
	# Programmende, auch mitten im Laden: Bau abbrechen, Fäden und Ladeaufträge abschließen.
	if next_world != null:
		next_world.abort()
		next_world = null
	Diorama.shutdown()

func _load_tick() -> void:
	# Je Bild (auch ohne _process, z. B. in Prüfungen): Bau fortsetzen, abgebrochene Aufträge abholen, Altes abreißen.
	Diorama.reap()
	if next_world != null:
		next_world.resume.emit()
	var t0 := Time.get_ticks_usec()
	while not wreck.is_empty() and Time.get_ticks_usec() - t0 < WRECK_SLICE_USEC:
		var n = wreck[-1]
		if not is_instance_valid(n):
			wreck.pop_back()
			continue
		var id: int = n.get_instance_id()
		if not wreck_open.has(id) and n.get_child_count() > 0:
			wreck_open[id] = true
			wreck.append_array(n.get_children())
			continue
		wreck.pop_back()
		wreck_open.erase(id)
		n.free()

func set_camera(target: Vector3) -> void:
	# Abstand so, dass im Blickzentrum cam_zoom Meter (senkrecht zur Blickrichtung) sichtbar sind.
	var distance := cam_zoom*0.5/tan(deg_to_rad(CAM_FOV)*0.5)
	camera.position = target + Vector3(0,sin(cam_pitch),cos(cam_pitch))*distance
	if world != null and world.atmosphere != null:
		world.atmosphere.fit_shadow(distance)
		var screen := get_viewport().get_visible_rect().size
		world.atmosphere.follow_view(target, cam_zoom, screen.x / maxf(1.0, screen.y), cam_pitch)
	# Bildschirm oben = Welt −z (auch senkrecht von oben eindeutig).
	camera.look_at(target,Vector3(0,0,-1))

func rival_lineup(player_car: int) -> Array:
	return rival_lineup_excluding([player_car])

func rival_lineup_excluding(taken: Array) -> Array:
	# Gegner fahren (physikalisch das Grundmodell, aber) mit Karosserie, Farbe und Motorklang anderer Autos; je Strecke eine feste
	# Auswahl, die Autos der Menschen kommen nie doppelt vor.
	var others: Array = []
	for i in range(RaceVehicle.CARS.size()):
		if not (i in taken):
			others.append(i)
	if others.is_empty():
		for i in range(RaceVehicle.CARS.size()):
			others.append(i)
	var offset := posmod(hash(track_id),others.size())
	var picked: Array = []
	for i in range(others.size()):
		picked.append(others[(offset + i) % others.size()])
	return picked

func car_looks() -> Array:
	# Karosserie, Farbe und Motor je Auto des Feldes (Index in RaceVehicle.CARS, nur Darstellung): Menschen ihr Auto (Eintrag "look",
	# sonst "car"), die KI der Reihe nach die übrigen Autos (rival_lineup_excluding). Mehrspieler mit Spielerfarben ("paint"): Die KI
	# behält die Farben ihrer Autos, nimmt aber zuerst Autos, deren Farbe sich von allen Spielerfarben abhebt (PlayerColors.rival_order).
	var taken: Array = []
	var paints: Array = []
	for e in field.entries:
		if bool(e.human):
			taken.append(int(e.get("look", e.car)))
			if e.has("paint"):
				paints.append(e.paint)
	var pool := rival_lineup_excluding(taken) if paints.is_empty() else PlayerColors.rival_order(rival_lineup_excluding([]), taken, paints)
	var looks: Array = []
	var k := 0
	for e in field.entries:
		if bool(e.human):
			looks.append(int(e.get("look", e.car)))
		elif e.has("look"):
			looks.append(int(e.look))
		else:
			looks.append(pool[k % pool.size()])
			k += 1
	return looks

func solo() -> bool:
	# Einzelspieler: Gold, Bestenliste, Geist und letzte Fahrt gelten nur dann (Mehrspieler: 5.5). Nie im Weitergeben-Modus und nie,
	# solange der WLAN-Mehrspieler offen ist (Lobby, Runde, Rennen) – unabhängig davon, wie viele Menschen gerade im Feld stehen.
	return party == null and lobby == null and (field == null or field.human_count() <= 1)

func clear_cars() -> void:
	sound.clear_engines()
	for model in models:
		model.queue_free()
	models.clear()
	vehicles.clear()
	me = 0
	remote_turbo.clear()
	car_names.clear()
	chatter.reset(0)
	if is_instance_valid(ghost_model):
		ghost_model.queue_free()
	ghost = null
	field = null
	world.clear_seesaws()
	world.update_edge_posts({})   # Randpfosten wieder aufstellen

func ghost_path() -> String:
	return "user://ghosts/%s_%d.json" % [track_id, stage]

func save_ghost() -> void:
	DirAccess.make_dir_recursive_absolute("user://ghosts")
	var plan := LineRecorder.plan_to_data(recorder.route)
	var file := FileAccess.open(ghost_path(), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"physics": RaceVehicle.VERSION, "track_hash": track.file_hash, "car": car_choice, "time": vehicles[me].finish_time, "plan": plan, "turbo": turbo_actions}))

func spawn_ghost() -> void:
	if not bool(store.data.get("ghost", true)) or track.mode == "drift" or demonstration or not solo() or not FileAccess.file_exists(ghost_path()):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(ghost_path()))
	if not data is Dictionary or str(data.get("physics", "")) != RaceVehicle.VERSION:
		return
	# Geist gilt nur für dieselbe Streckendatei (ohne Hash nur bei Fassung 1, also Geister von vor dem Höhen-Paket).
	if (data.has("track_hash") and str(data.track_hash) != track.file_hash) or (not data.has("track_hash") and track.rev > 1):
		return
	var plan := LineRecorder.plan_from_data(data.plan)
	var car := clampi(int(data.get("car", 0)), 0, RaceVehicle.CARS.size() - 1)
	ghost = RaceVehicle.new(track, plan, 0.0, 0.0, car)
	if field != null:
		field.set_ghost(ghost)
	ghost_turbo = data.get("turbo", [])
	ghost_model = world.car_model(Color(0.75, 0.9, 1.0), false, str(RaceVehicle.CARS[car].style))
	for node in ghost_model.find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).transparency = 0.65
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func ghost_boost(time: float) -> bool:
	return RaceField.replay_turbo(ghost_turbo, time)

func show_menu() -> void:
	paused = false
	phase = "menu"
	pointer = -99
	turbo_held = false
	clear_cars()
	leave_party()
	leave_wlan()
	world.line_mesh.mesh = null
	world.marker.visible = false
	# Menü mit eigenem Hintergrund; die Strecke erscheint erst beim Zeichnen/Fahren.
	world.visible = false
	hud.menu()

func start_drawing() -> void:
	finish_track_load()
	paused = false
	demonstration = false
	phase = "draw"
	pointer = -99
	turbo_held = false
	clear_cars()
	world.visible = true
	apply_atmosphere()
	recorder = LineRecorder.new(track)
	recorder.tempo_factor = LineRecorder.tempo_from_setting(float(store.data.get("draw_tempo",0.5)))
	release_touches()
	reset_view()
	draw_clock = 0.0
	world.draw_route([])
	world.tyre_tracks.clear()
	skid_tick = 0
	world.update_tracks(0.0)
	world.marker.visible = true
	var start := track.at(0.0)
	world.marker.position = Vector3(start.x,0.31 + track.surface_z(0.0),start.y)
	camera_target = track_center()
	cam_zoom = overview_size()
	set_camera(camera_target)
	hud.drawing()

func demo() -> void:
	start_drawing()
	demonstration = true
	recorder.route = track.ai_route(1.5)
	recorder.complete = true
	begin_race()

func begin_race() -> void:
	finish_track_load()
	phase = "countdown"
	countdown = 3.0
	race_time = 0.0
	turbo_actions.clear()
	last_boost_input = false
	world.marker.visible = false
	release_pads()
	if not car_unlocked(car_choice):
		car_choice = 0
	# Drift-Modus: allein gegen Punkteziel und Zeitlimit, keine Rivalen.
	field = RaceField.new(track)
	if race_entries.is_empty():
		field.setup(recorder.route, stage, car_choice)
		me = 0
	else:
		# Teilnehmerliste gilt für genau dieses Rennen („Neue Linie“ danach ist wieder Einzelspieler, bis sie neu gesetzt wird).
		field.setup_entries(race_entries)
		me = clampi(race_me, 0, field.cars.size() - 1)
		race_entries = []
		if party != null:
			# Lobby-Schalter „Berührungen“; Drift zu mehreren immer ohne (alle gleichzeitig, Wertung nach Punkten).
			field.contacts = party.contacts and not party.is_drift()
	prepare_race_view()
	spawn_ghost()
	for i in range(vehicles.size()):
		record_tyre_tracks(i)
	hud.race()
	sound.start_signal(false)

func prepare_race_view() -> void:
	# Darstellung des Starterfelds field: Modelle, Linien, Namen, Motoren. Einzelspieler und „Weitergeben“: das gerechnete Feld;
	# WLAN-Mehrspieler: die Marionetten (NetRace.view). Reine Darstellung.
	vehicles = field.cars
	world.build_seesaws(field.seesaws)
	# Gegner in anderen Farben als die Autos der Menschen; sie fahren das Grundmodell. Mein Auto trägt den Halo.
	var looks := car_looks()
	# Farbe je Auto: Mehrspieler-Menschen ihre Spielerfarbe (Eintrag "paint": Lack, Schild, Lichtkranz, Linie, Turbo-Knopf, Wertung),
	# sonst die Farbe des Autos (Einzelspieler unverändert).
	var paints: Array[Color] = []
	for i in range(field.cars.size()):
		var e: Dictionary = field.entries[i]
		paints.append(e.paint if e.has("paint") else Color(RaceVehicle.CARS[looks[i]].color))
	# Linien im Rennen: im Einzelspieler die eigene; mit mehreren Menschen alle, jede in ihrer Farbe (Weitergeben, Netz).
	if field.human_count() > 1:
		var plans: Array = []
		var tints: Array = []
		for i in range(field.cars.size()):
			if field.is_human(i):
				plans.append(field.entries[i].plan)
				tints.append(paints[i])
		world.draw_routes(plans, tints, true)
	else:
		world.draw_route(recorder.route if recorder != null else field.entries[me].plan, true)
	var engine_ids: Array = []
	for i in range(vehicles.size()):
		var look: Dictionary = RaceVehicle.CARS[looks[i]]
		# Mehrspieler: jeder Mensch trägt einen Lichtkranz in seiner Farbe.
		var crowned := i == me or ((party != null or lobby != null) and field.is_human(i))
		models.append(world.car_model(paints[i],crowned,str(look.style)))
		models[i].set_meta("tag_color", paints[i])
		if (party != null or lobby != null) and crowned and models[i].has_node("Halo"):
			var halo_mat: StandardMaterial3D = (models[i].get_node("Halo") as MeshInstance3D).material_override
			halo_mat.albedo_color = Color(paints[i].lightened(0.25), 0.38)
		engine_ids.append(str(look.id))
	car_names = NameTags.names_for(field.entries, looks, me, store.player_name())
	chatter.reset(vehicles.size())
	crash_wait.clear()
	crash_wait.resize(vehicles.size())
	turbo_input.clear()
	turbo_input.resize(vehicles.size())
	was_airborne.clear()
	was_crashed.clear()
	last_vz.clear()
	for _v in vehicles:
		was_airborne.append(false)
		was_crashed.append(false)
		last_vz.append(0.0)
	was_boosting = false
	sound.prepare_engines(engine_ids, me)
	snapshot_vehicles()
	update_models()
	place_models()

func record_tyre_tracks(i: int) -> void:
	var v := vehicles[i]
	if v.airborne or v.in_loop or v.crashed:
		return
	world.tyre_tracks.sample(i,v.pos,v.heading,v.velocity.length(),v.braking,v.slip,track,race_time,v.z)

func update_tyre_tracks() -> void:
	for i in range(vehicles.size()):
		if vehicles[i].finish_time<0:
			record_tyre_tracks(i)
	skid_tick += 1
	# Ringpuffer: günstig genug für jeden zweiten Takt (flüssigeres Nachziehen der Spuren).
	if skid_tick%2==0:
		world.update_tracks(race_time)

# Darstellung zwischen zwei Physikschritten interpolieren: Die Simulation läuft mit 60 Hz, das Display oft mit
# 120 Hz. Ohne Zwischenwerte springt das Auto nur jedes zweite Bild, während die Kamera gleitet -> Zittern.
var prev_poses: Array[Vector2] = []
var prev_headings: Array[float] = []

func snapshot_vehicles() -> void:
	prev_poses.resize(vehicles.size())
	prev_headings.resize(vehicles.size())
	for i in range(vehicles.size()):
		prev_poses[i] = vehicles[i].pos
		prev_headings[i] = vehicles[i].heading

func render_pos(i: int) -> Vector2:
	if i >= prev_poses.size():
		return vehicles[i].pos
	return prev_poses[i].lerp(vehicles[i].pos, Engine.get_physics_interpolation_fraction())

func place_models() -> void:
	var alpha := Engine.get_physics_interpolation_fraction()
	for i in range(mini(vehicles.size(), models.size())):
		var p := render_pos(i)
		var h := vehicles[i].heading if i >= prev_headings.size() else lerp_angle(prev_headings[i], vehicles[i].heading, alpha)
		# 2,5D: Höhe (Fahrbahn, Sprung, Looping); im Looping dreht sich das Auto um seine Querachse.
		var drop := 0.0
		if vehicles[i].loop_fall:
			# Aus dem Looping gefallen: eigene Bewegung (nur Darstellung), siehe loop_fall_pose.
			var t: float = models[i].get_meta("fall_time", 0.0) + get_process_delta_time()
			models[i].set_meta("fall_time", t)
			models[i].transform = loop_fall_pose(vehicles[i], t)
			var halo_off := models[i].get_node_or_null("Halo") as Node3D
			if halo_off != null:
				halo_off.visible = false
			continue
		if vehicles[i].crashed and not vehicles[i].rolled_back and not vehicles[i].wrecked:
			# Absturz: nur Darstellung – das Auto fällt aus dem Bild, oder liegt auf dem Boden darunter, wenn der höchstens 8 m tiefer
			# liegt (Sohlenweg unter dem Sprung, Gelände neben der Brücke).
			var fall: float = models[i].get_meta("fall", 0.0) + get_process_delta_time() * 9.81 * 0.5
			models[i].set_meta("fall", fall)
			drop = fall * fall
			var floor_y := crash_floor(vehicles[i])
			if vehicles[i].z - floor_y <= 8.0:
				drop = minf(drop, maxf(0.0, vehicles[i].z - floor_y))
		models[i].position = Vector3(p.x,0.2 + vehicles[i].z - drop,p.y)
		if vehicles[i].in_loop:
			models[i].basis = track.loop_basis(vehicles[i].loop_forward, vehicles[i].loop_theta, vehicles[i].loop_radius, vehicles[i].loop_entry)
		else:
			models[i].rotation = Vector3(0, -h, car_pitch(models[i], vehicles[i]))
		var halo := models[i].get_node_or_null("Halo") as Node3D
		if halo != null:
			halo.visible = not vehicles[i].in_loop and not vehicles[i].loop_fall
	if ghost != null and is_instance_valid(ghost_model):
		ghost_model.position = Vector3(ghost.pos.x, 0.2 + ghost.z, ghost.pos.y)
		if ghost.in_loop:
			ghost_model.basis = track.loop_basis(ghost.loop_forward, ghost.loop_theta, ghost.loop_radius, ghost.loop_entry)
		else:
			ghost_model.rotation = Vector3(0, -ghost.heading, car_pitch(ghost_model, ghost))
		ghost_model.visible = ghost.finish_time < 0.0 and not ghost.crashed
	if field != null and not field.seesaws.is_empty():
		world.update_seesaws(field.seesaws, alpha)
	if field != null:
		world.update_edge_posts(field.post_state)   # umgefahrene Randpfosten (Schotterpiste) im Bild umlegen
	# Regen: Scheinwerfer- und Rücklicht-Positionen für die Beleuchtung der Tropfen.
	var lit: Array = []
	for i in range(mini(vehicles.size(), models.size())):
		lit.append([models[i].position, vehicles[i].heading])
	world.atmosphere.update_rain_cars(lit)

const CAR_HEIGHT := 0.65   # Höhe des Autos (Dach über den Rädern) für das Liegen auf dem Dach

func car_pitch(model: Node3D, v: RaceVehicle) -> float:
	# Nur Darstellung: Nicken mit der Fahrbahn (Steigung über den Radstand, ±1,25 m) am Boden, im Flug aus vz/u (±25°), weich gefiltert.
	var target := 0.0
	var forward := Vector2.from_angle(v.heading)
	if v.airborne:
		target = clampf(atan2(v.vz, maxf(absf(v.velocity.dot(forward)), 1.0)), -0.44, 0.44)
	elif not v.crashed or v.wrecked:
		var ahead := ground_y(v, v.pos + forward * 1.25)
		var behind := ground_y(v, v.pos - forward * 1.25)
		target = clampf(atan((ahead - behind) / 2.5), -0.44, 0.44)
	var pitch: float = lerpf(float(model.get_meta("pitch", 0.0)), target, 1.0 - exp(-get_process_delta_time() * 12.0))
	model.set_meta("pitch", pitch)
	return pitch

func ground_y(v: RaceVehicle, p: Vector2) -> float:
	# Bodenhöhe unter einem Punkt nahe dem Auto (Deck der Wippe, Abkürzungsgelände oder eigener Ast), nur für die Darstellung.
	if v.deck != null and v.deck.inside(p):
		return v.deck.deck_y(v.deck.local(p).x)
	if v.on_shortcut:
		return track.terrain_height(p)
	return track.ground_height(track.phase_near(p, v.previous_phase, 0.02))

func crash_floor(v: RaceVehicle) -> float:
	# Boden unter einem abgestürzten Auto: Gelände oder ein tieferer Ast, auf dessen Fahrbahn es fällt.
	var y := track.terrain_height(v.pos)
	var q := track.query(v.pos)
	if float(q.distance) <= track.hw(float(q.s)) + 0.5 and not track.in_gap(float(q.s)):
		var road := track.surface_z(float(q.s))
		if road <= v.z + 0.01:
			y = maxf(y, road)
	return y

func loop_band_point(v: RaceVehicle, th: float, lift := 0.0) -> Vector3:
	# Punkt auf der Innenseite des Loopingbandes; lift = Abstand zur Ringmitte hin.
	var r := v.loop_radius
	var side := Vector2(-v.loop_forward.y, v.loop_forward.x)
	var c: Vector2 = v.loop_origin + v.loop_forward * (r - lift) * sin(th) + side * track.loop_lateral(th, v.loop_entry)
	return Vector3(c.x, 0.2 + track.base_height(v.previous_phase) + r - (r - lift) * cos(th), c.y)

func on_roof(v: RaceVehicle, th: float) -> Basis:
	# Auto auf dem Dach liegend auf dem Band bei Winkel th (Räder zur Ringmitte).
	var b := track.loop_basis(v.loop_forward, th, v.loop_radius, v.loop_entry)
	return Basis(b.x, -b.y, -b.z)

func loop_fall_pose(v: RaceVehicle, t: float) -> Transform3D:
	# Absturz im Looping (jenseits der Senkrechten): das Auto löst sich vom Band, fällt senkrecht auf das
	# darunterliegende Bahnstück (Innenseite), dreht sich dabei aufs Dach und rutscht die Bahn hinunter bis zum
	# tiefsten Punkt. Nur Darstellung – die Simulation hat das Auto beim Ablösen als ausgeschieden gewertet.
	var r := v.loop_radius
	var th0 := v.loop_theta
	var start := loop_band_point(v, th0)
	# Landestelle: Bahnstück senkrecht darunter (gleicher Abstand in Fahrtrichtung), auf der Seite der Einfahrt
	# (vorne, sin > 0) oder der Ausfahrt (hinten).
	var along := clampf(sin(th0), -1.0, 1.0)
	var th_land: float = asin(along) if along >= 0.0 else TAU + asin(along)
	var land := loop_band_point(v, th_land, CAR_HEIGHT)
	var fall_h := maxf(0.0, start.y - land.y)
	var t_fall := sqrt(2.0 * fall_h / 9.81) + 0.05
	var start_basis := track.loop_basis(v.loop_forward, th0, r, v.loop_entry)
	if t < t_fall:
		var k := t / t_fall
		var y := start.y - 0.5 * 9.81 * t * t
		var pos := Vector3(lerpf(start.x, land.x, k), maxf(y, land.y), lerpf(start.z, land.z, k))
		var rot := Quaternion(start_basis.orthonormalized()).slerp(Quaternion(on_roof(v, th_land).orthonormalized()), smoothstep(0.0, 1.0, k))
		return Transform3D(Basis(rot), pos)
	# Rutschen auf dem Dach bis zum tiefsten Punkt (Einfahrt vorne: θ → 0, Ausfahrt hinten: θ → 2π).
	var goal: float = 0.0 if along >= 0.0 else TAU
	var ts := t - t_fall
	var slide := 1.0 - exp(-ts * 2.2)
	var th := lerpf(th_land, goal, slide)
	return Transform3D(on_roof(v, th), loop_band_point(v, th, CAR_HEIGHT))

func _physics_process(dt: float) -> void:
	if paused:
		return
	snapshot_vehicles()
	if lobby != null and lobby.race != null and phase in ["countdown", "race", "result"]:
		net_race_step(dt)
		return
	if phase == "draw":
		draw_clock += dt
	elif phase == "reveal":
		reveal_time += dt
		hud.party_ui.update_reveal(PassParty.REVEAL_TIME - reveal_time)
		if reveal_time >= PassParty.REVEAL_TIME:
			party_begin_race()
	elif phase == "countdown":
		var previous_count := ceili(countdown)
		countdown -= dt
		if ceili(countdown)!=previous_count:
			# Ampel: dreimal Rot (bei 3, 2, 1), dann Grün beim Start.
			sound.start_signal(countdown<=0.0)
		hud.center.text = str(ceili(countdown)) if countdown>0 else "LOS"
		if countdown <= 0.0:
			phase = "race"
	elif phase == "race":
		race_time += dt
		var boost: bool
		if party != null:
			boost = party_turbo()
		else:
			boost = (turbo_held or Input.is_physical_key_pressed(KEY_SPACE)) if not demonstration else RaceField.rival_boost(vehicles[me])
		if boost!=last_boost_input:
			turbo_actions.append({"time":race_time,"held":boost})
			last_boost_input = boost
		field.step_inputs(dt, race_time, turbo_inputs(boost), "race", ghost_boost(race_time))
		if bool(store.data.get("bubbles", true)):
			chatter.observe(vehicles, field.impacts, race_time, field.human_mask, me, true)   # nur lesen (Sprechblasen)
		for hit in field.impacts:
			contact_sparks(hit[0],hit[1],hit[2])
		update_tyre_tracks()
		update_models()
		race_sounds()
		# Nach einem Absturz noch kurz zusehen lassen (Fall, Zurückrollen), dann das Ergebnis – sobald alle Menschen fertig sind.
		if humans_done(dt) or (track.mode == "drift" and race_time > drift_limit()):
			finish_race()
		elif race_time > 180.0:
			pause_game()
	elif phase == "result":
		# Rivals finish normally; their interpolated times update the result table.
		race_time += dt
		var unfinished: Array[int] = []
		for i in range(vehicles.size()):
			if not field.is_human(i) and vehicles[i].finish_time<0:
				unfinished.append(i)
		field.step(dt, race_time, false, "result", ghost_boost(race_time))
		if bool(store.data.get("bubbles", true)):
			chatter.observe(vehicles, field.impacts, race_time, field.human_mask, me, false)
		for hit in field.impacts:
			contact_sparks(hit[0],hit[1],hit[2])
		var new_finish := false
		for i in unfinished:
			if vehicles[i].finish_time>=0 and hud.result_times.has(i):
				new_finish = true
		if new_finish:
			if party != null:
				hud.party_ui.results(party_rows())
			else:
				var rows := sorted_results()
				hud.results(rows,player_result_rank(rows),result_record)
		update_tyre_tracks()
		update_models()

func turbo_inputs(own: bool) -> Array[bool]:
	# Turbo je Auto für RaceField.step_inputs: mein Auto aus Knopf/Leertaste, die übrigen Menschen aus remote_turbo (KI: ignoriert).
	if turbo_input.size() != vehicles.size():
		turbo_input.resize(vehicles.size())
	for i in range(turbo_input.size()):
		turbo_input[i] = own if i == me else bool(remote_turbo.get(i, false))
	return turbo_input

func humans_done(dt: float) -> bool:
	# Alle Menschen im Ziel oder ausgeschieden; nach einem Absturz noch kurz zusehen (Fall 1,6 s, aus dem Looping 2,4 s).
	var people := field.human_indices()
	if people.is_empty():
		return field.done()
	if crash_wait.size() != vehicles.size():
		crash_wait.resize(vehicles.size())
	var done := true
	for i in people:
		var v := vehicles[i]
		if v.crashed:
			crash_wait[i] += dt
		if not (v.finish_time>=0 or crash_wait[i] > (2.4 if v.loop_fall else 1.6)):
			done = false
	return done

func update_models() -> void:
	for i in range(vehicles.size()):
		models[i].get_node("Turbo").visible = vehicles[i].boosting and phase=="race"
		models[i].get_node("Lights").visible = world.atmosphere.is_dark()
		# Staub nur auf losem Grund, ab Schrittgeschwindigkeit und nicht in der niedrigsten Grafikstufe.
		var dust: CPUParticles3D = models[i].get_node("Dust")
		var loose: bool = str(track.surface_at(vehicles[i].pos).kind) in ["gravel","dirt","mud","sand","grass"]
		dust.emitting = loose and world.atmosphere.quality>=1 and vehicles[i].velocity.length()>4.0 and world.atmosphere.conditions.weather!="rain"
		animate_car(i)
	if party != null or lobby != null:
		var beat := 0.5 + 0.5*sin(Time.get_ticks_msec()*0.004)
		for i in range(mini(models.size(), vehicles.size())):
			if i != me and field.is_human(i) and models[i].has_node("Halo"):
				var ring: MeshInstance3D = models[i].get_node("Halo")
				ring.material_override.albedo_color.a = 0.22 + 0.22*beat
				ring.scale = Vector3.ONE*(0.92 + 0.12*beat)
	if me < models.size() and models[me].has_node("Halo"):
		# Sanftes Pulsieren (nur Darstellung) hebt das eigene Auto hervor.
		var own := models[me]
		var pulse := 0.5 + 0.5*sin(Time.get_ticks_msec()*0.004)
		var halo: MeshInstance3D = own.get_node("Halo")
		halo.material_override.albedo_color.a = 0.22 + 0.22*pulse
		halo.scale = Vector3.ONE*(0.92 + 0.12*pulse)
		if own.has_meta("paint_shader"):
			own.get_meta("paint_shader").set_shader_parameter("glow",0.12 + 0.18*pulse)
		elif own.has_meta("paint"):
			var paint: StandardMaterial3D = own.get_meta("paint")
			paint.emission_energy_multiplier = 0.18 + 0.22*pulse

func screen_pan(pos: Vector2) -> float:
	# Lage eines Punktes im Bild als Stereowert (-1 links, 1 rechts).
	var size := get_viewport().get_visible_rect().size
	var p := camera.unproject_position(Vector3(pos.x, 0.4, pos.y))
	return clampf((p.x / maxf(1.0, size.x) - 0.5) * 1.7, -0.85, 0.85)

func sound_distance_db(pos: Vector2) -> float:
	# Leiser mit dem Abstand zum eigenen Auto.
	if me >= vehicles.size():
		return 0.0
	return -clampf((pos.distance_to(vehicles[me].pos) - 6.0) * 0.5, 0.0, 26.0)

func race_sounds() -> void:
	# Stoßgeräusche aus Zustandswechseln der Fahrzeuge (nur lesen; die Simulation bleibt unberührt): Landung, Absturz, Leitplanke, Turbo.
	for i in range(mini(vehicles.size(), was_airborne.size())):
		var v := vehicles[i]
		var pan := 0.0 if i == me else screen_pan(v.pos)
		var far := 0.0 if i == me else sound_distance_db(v.pos)
		if v.airborne:
			last_vz[i] = v.vz
		elif was_airborne[i] and not v.crashed:
			sound.impact("land", clampf(-float(last_vz[i]) / 7.0, 0.25, 1.0), pan, far)
		was_airborne[i] = v.airborne
		if v.crashed and not was_crashed[i]:
			sound.impact("crash", 1.0, pan, far)
		was_crashed[i] = v.crashed
		if v.guard_hit > 0.4:
			sound.impact("rail", clampf(v.guard_hit / 9.0, 0.25, 1.0), pan, far)
			world.sparks(Vector3(v.pos.x, 0.45, v.pos.y), Vector3(-v.velocity.y, 0, v.velocity.x).normalized(), clampf(v.guard_hit / 8.0, 0.2, 1.0))
		v.guard_hit = 0.0
		if v.obstacle_hit > 1.0:
			# Zusammenstoß mit Deko (Haus, Absperrung, Laterne …): Blech klirrt an Metall, sonst ein dumpfer Schlag.
			var metal := v.obstacle_kind in ["absperrung", "gitter", "mast"]
			sound.impact("rail" if metal else "car", clampf(v.obstacle_hit / 9.0, 0.25, 1.0), pan, far)
			if metal or v.obstacle_hit > 6.0:
				world.sparks(Vector3(v.pos.x, 0.45, v.pos.y), Vector3(-v.velocity.y, 0, v.velocity.x).normalized(), clampf(v.obstacle_hit / 8.0, 0.2, 1.0))
		v.obstacle_hit = 0.0
	if field != null:
		# Wippe schlägt an den Anschlag: leiser Landestoß (nur Ton).
		for w in field.seesaws:
			if w.clack > 0.15:
				sound.impact("land", clampf(w.clack * 0.6, 0.15, 0.5), screen_pan(w.c), sound_distance_db(w.c))
	if me < vehicles.size():
		if vehicles[me].boosting and not was_boosting:
			sound.impact("kick", 0.9)
		was_boosting = vehicles[me].boosting

func contact_sparks(a: int, b: int, impact: float) -> void:
	# Funken am Berührpunkt ab spürbarem Stoß (nur Darstellung), dazu der Stoß als Geräusch.
	if impact < 0.8:
		return
	var p := (vehicles[a].pos+vehicles[b].pos)*0.5
	var own := a == me or b == me
	sound.impact("car", clampf(impact/6.0,0.25,1.0), 0.0 if own else screen_pan(p), 0.0 if own else sound_distance_db(p))
	var away := (vehicles[b].pos-vehicles[a].pos).normalized().orthogonal()
	world.sparks(Vector3(p.x,0.45,p.y),Vector3(away.x,0,away.y),clampf(impact/5.0,0.2,1.0))

func animate_car(i: int) -> void:
	# Nur Darstellung (Leitplanke 4): Räder rollen mit dem gefahrenen Weg und lenken ein, die Karosserie
	# nickt beim Bremsen/Beschleunigen und wankt in Kurven – abgeleitet aus der Fahrzeugbewegung.
	var car := models[i]
	if not car.has_meta("wheels"):
		return
	var v := vehicles[i]
	var dt := 1.0/60.0
	var forward := Vector2(cos(v.heading),sin(v.heading))
	var speed := v.velocity.dot(forward)
	var spin: float = float(car.get_meta("spin",0.0)) + speed*dt/0.155
	car.set_meta("spin",spin)
	for wheel: Node3D in car.get_meta("wheels"):
		# Auf die Grundausrichtung aus dem Modell aufsetzen (nicht ersetzen): Einlenken um die Hochachse,
		# Rollen um die Radachse (lokal z).
		if not wheel.has_meta("rest"):
			wheel.set_meta("rest",wheel.basis)
		var steer := -v.steering*0.6 if wheel.name.begins_with("Wheel_F") else 0.0
		wheel.basis = Basis(Vector3.UP,steer)*Basis(Vector3.BACK,-spin)*Basis(wheel.get_meta("rest"))
	var last: Vector2 = car.get_meta("last_velocity",v.velocity)
	car.set_meta("last_velocity",v.velocity)
	var accel := (v.velocity-last)/dt
	var along := accel.dot(forward)
	var lateral := accel.dot(Vector2(-forward.y,forward.x))
	var body: Node3D = car.get_meta("body")
	if body != null:
		var target := Vector3(clampf(lateral*0.006,-0.07,0.07),0,clampf(along*0.005,-0.06,0.06))
		body.rotation = body.rotation.lerp(target,0.15)

func overview_size() -> float:
	# Strecke samt Bankett bildschirmfüllend: Breite und (geneigte) Tiefe müssen zwischen die HUD-Leisten passen.
	var screen := get_viewport().get_visible_rect().size
	var aspect := screen.x/maxf(1.0,screen.y)
	var half_x := track.bounds.size.x*0.5 + Circuit.HALF_WIDTH + 2.0
	var half_z := track.bounds.size.y*0.5 + Circuit.HALF_WIDTH + 2.0
	var pitch := maxf(0.5,sin(cam_pitch))
	return maxf(2.0*half_x/aspect, 2.0*half_z*pitch/0.74)

func reset_view() -> void:
	view_zoom = overview_size()
	view_focus = track_center()

const VIEW_MARGIN := 6.0      # so weit über die Streckenkante (samt Bankett) hinaus darf das sichtbare Stück Boden reichen (m)

func clamp_view_state() -> void:
	# Weitester Zoom = ganze Strecke im freien Sichtbereich, engster = Fahrbahn füllt die kürzere Seite.
	# Verschieben: Das sichtbare Stück Boden (zwischen den HUD-Leisten) bleibt innerhalb der Strecke samt schmalem Rand; ist es in einer
	# Richtung größer als die Strecke (breiter Bildschirm), bleibt die Ansicht dort mittig. So richtet sich die Grenze nach der
	# Strecke und nicht nach der Umgebung (Häuser, Bäume), und man sieht nie viel leere Fläche hinter dem Rand.
	var widest := overview_size()
	view_zoom = clampf(view_zoom,minf(road_fill_size()*1.2,widest),widest)
	if view_zoom >= widest*0.98:
		view_focus = track_center()
		return
	var screen := get_viewport().get_visible_rect().size
	var band: Vector2 = hud.free_band()
	var k := screen_scale()
	var limit := track.bounds.grow(Circuit.HALF_WIDTH+VIEW_MARGIN)
	view_focus.x = fit_axis(view_focus.x,limit.position.x,limit.end.x,screen.x*0.5*k.x)
	view_focus.z = fit_axis(view_focus.z,limit.position.y,limit.end.y,(band.y-band.x)*0.5*k.y)

func fit_axis(value: float, lo: float, hi: float, half: float) -> float:
	# Mitte der Ansicht so begrenzen, dass ihre Hälfte-Ausdehnung half zwischen lo und hi bleibt; passt sie nicht hinein: mittig.
	if hi-lo <= 2.0*half:
		return (lo+hi)*0.5
	return clampf(value,lo+half,hi-half)

func screen_scale() -> Vector2:
	# Meter pro Bildpunkt auf dem Boden (x, z) beim aktuellen Zoom.
	var h := maxf(1.0,get_viewport().get_visible_rect().size.y)
	return Vector2(view_zoom/h,view_zoom/h/maxf(0.5,sin(cam_pitch)))

func pan_view(delta: Vector2) -> void:
	var k := screen_scale()
	view_focus.x -= delta.x*k.x
	view_focus.z -= delta.y*k.y
	clamp_view_state()

func zoom_view(factor: float, anchor: Vector2) -> void:
	# Um den Punkt unter den Fingern zoomen: Er bleibt an seiner Stelle.
	var w := world_point(anchor)
	var old := view_zoom
	var widest := overview_size()
	view_zoom = clampf(view_zoom*factor,minf(road_fill_size()*1.2,widest),widest)
	var k := view_zoom/old
	view_focus.x = w.x-(w.x-view_focus.x)*k
	view_focus.z = w.y-(w.y-view_focus.z)*k
	clamp_view_state()
	cam_zoom = view_zoom
	set_camera(Vector3(view_focus.x,0,view_focus.z-band_shift(view_zoom)))

func band_shift(zoom: float) -> float:
	# Bildschirm nach unten = Welt +z: um so viel versetzen, dass der Fokus in der Mitte des freien Bereichs erscheint.
	var screen := get_viewport().get_visible_rect().size
	var band: Vector2 = hud.free_band()
	return ((band.x+band.y)*0.5-screen.y*0.5)*zoom/maxf(1.0,screen.y)/maxf(0.5,sin(cam_pitch))

func road_fill_size() -> float:
	# Ortho-Größe, bei der die Fahrbahn (plus Randsteine) die kürzere Bildschirmseite füllt.
	var screen := get_viewport().get_visible_rect().size
	var road := Circuit.HALF_WIDTH*2.0+1.0
	return road if screen.y<=screen.x else road*screen.y/screen.x

func _process(dt: float) -> void:
	if lobby != null and lobby.race != null and phase in ["countdown", "race", "result"] and lobby.race.view == field:
		# WLAN-Rennen: Marionetten je Bild genau auf die Anzeigezeit stellen (feiner als der 60-Hz-Takt), ohne Zwischenwerte.
		lobby.race.apply_view(lobby.race.display_ticks())
		snapshot_vehicles()
	if not vehicles.is_empty():
		place_models()
	# Detailstufe nach Zoom: nah volle KI-Modelle, in der Übersicht die vereinfachten.
	world.set_detail(cam_zoom < 26.0)
	world.atmosphere.limit_reflection(cam_zoom / maxf(1.0, overview_size()), cam_pitch)
	var target := track_center()
	var zoom := overview_size()
	if phase == "draw" and recorder != null:
		clamp_view_state()
		zoom = view_zoom
		target = view_focus
		target.z -= band_shift(zoom)
	elif phase in ["race","countdown"] and bool(store.data.camera) and party != null:
		var view := party_view()
		target = view[0]
		zoom = view[1]
	elif phase in ["race","countdown"] and bool(store.data.camera):
		# Zoom-Regler: 0 = bisherige Folgeansicht (48), 1 = Fahrbahnbreite füllt die kürzere Bildschirmseite.
		var f := clampf(float(store.data.get("camera_zoom",0.4)),0.0,1.0)
		var p := render_pos(me) + vehicles[me].velocity*0.28
		var follow := lerpf(0.45,1.0,sqrt(f))
		var c := track_center()
		zoom = minf(overview_size(),48.0*pow(road_fill_size()/48.0,f))
		# Vorhalt zur Streckenmitte (zeigt auf Rundkursen mehr Strecke), aber höchstens 30 % des Bildausschnitts: auf langen Strecken
		# (Serra-Pass) lag das eigene Auto sonst gut ein Viertel der Zeit außerhalb des Bildes (Prüfung 03.10.2026).
		var me_pos := Vector3(p.x,vehicles[me].z,p.y)
		target = me_pos + ((c-me_pos)*(1.0-follow)).limit_length(zoom*0.3)
	if not paused:
		var pitch_goal := PITCH_DRAW if phase in ["draw","menu","drawn","handover","reveal","party_setup","party_garage"] or phase.begins_with("net_") else PITCH_RACE
		cam_pitch = lerpf(cam_pitch,pitch_goal,1.0-exp(-dt*2.0))
		if phase=="draw":
			# Handkamera folgt den Fingern unmittelbar.
			camera_target = target
			cam_zoom = zoom
		else:
			camera_target = camera_target.lerp(target,1.0-exp(-dt*3.5))
			cam_zoom = lerpf(cam_zoom,zoom,1.0-exp(-dt*2.5))
		set_camera(camera_target)
		world.marker.scale = Vector3.ONE*(1.0+sin(Time.get_ticks_msec()*0.006)*0.10)
		# Malzeit läuft auch bei ruhendem Finger (Verweilen = langsam, Altern des offenen Bereichs, Probe).
		if phase=="draw" and pointer!=-99 and touches.has(pointer):
			record_point(touches[pointer])
		if phase=="draw" and recorder!=null:
			refresh_line()
	if (phase in ["menu","party_setup","party_garage"] or phase.begins_with("net_")) and hud.backdrop.visible:
		hud.backdrop.queue_redraw()
	if lobby != null and lobby.draw != null:
		net_tick()
	if phase == "draw" and hud.status!=null:
		hud.status.text = lap_text(recorder.progress)
		hud.detail.text = "%d %% geplant" % int(recorder.progress*100.0/track.laps)
		hud.progress_bar.value = recorder.progress*100.0/track.laps
		hud.instruction_label.text = recorder.hint
	elif phase in ["race","countdown"] and party != null:
		hud.party_ui.update_race()
	elif phase in ["race","countdown"]:
		var v := vehicles[me]
		hud.status.text = lap_text(v.progress)
		hud.time_label.text = format_time(race_time)
		hud.speed_label.text = str(int(v.velocity.length()*3.6))
		if track.mode == "drift":
			hud.rank_label.text = "%d" % int(v.drift_score)
			hud.status.text = "%s   ×%.1f   noch %d s" % [lap_text(v.progress), v.drift_multiplier, maxi(0, int(ceil(drift_limit() - race_time)))]
		else:
			hud.rank_label.text = "%d / %d" % [live_rank(),vehicles.size()]
		if hud.progress_bar != null:
			hud.progress_bar.value = v.turbo*100
		if phase=="race":
			hud.center.text = "LOS" if race_time<0.65 else ""
	# WLAN-Mehrspieler: Die Musik des Gastgebers gilt auf allen Handys (NetLobby.sync_music), sonst die eigene Playlist.
	if lobby != null:
		lobby.sync_music(sound)
	else:
		sound.set_net_role("")
	sound.enabled = bool(store.data.sound)
	sound.set_style(str(store.data.get("music_style","energie")))
	sound.set_volumes(float(store.data.get("music_volume",0.8)),float(store.data.get("sfx_volume",1.0)))
	var heard := sound_phase()
	if sound.context!=heard:
		sound.set_context(heard,net_music_won if lobby != null else result_won)
	sound.tick(vehicles[me] if me < vehicles.size() else null,phase=="race",paused,bool(store.data.sound),music_on(),track,dt)
	sound.tick_engines(dt,vehicles,camera,phase,countdown,paused,bool(store.data.sound),me)
	capture_frames += 1
	if "--capture" in OS.get_cmdline_user_args() and capture_frames==90:
		get_viewport().get_texture().get_image().save_png("user://preview.png")
		print("CAPTURE ",ProjectSettings.globalize_path("user://preview.png"))
		get_tree().quit()

func world_point(screen: Vector2) -> Vector2:
	# Blickstrahl mit der Fahrbahnebene schneiden; bei Höhenprofil (Brücke, Berg) die Ebene in zwei
	# Schritten auf die Fahrbahnhöhe an der getroffenen Stelle nachführen.
	var from := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	var plane := 0.20
	var hit := from + direction*((plane-from.y)/direction.y)
	if not track.elevation.is_empty() or not track.terrain.is_empty() or not track.seesaws.is_empty():
		# Fenster um den eigenen Ast höchstens 40 m (Äste übereinander liegen im Streckenverlauf weit auseinander).
		var window := minf(0.15, 40.0 / track.length)
		for _i in range(3):
			var p2 := Vector2(hit.x,hit.z)
			var near := track.phase(p2) if recorder == null else track.phase_near(p2, recorder.last_phase, window)
			var sc := track.shortcut_here(p2, recorder.last_phase) if recorder != null else {}
			plane = 0.20 + track.draw_height(near, int(sc.index) if not sc.is_empty() else -1, p2)
			hit = from + direction*((plane-from.y)/direction.y)
	return Vector2(hit.x,hit.z)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.physical_keycode==KEY_ESCAPE:
		if party != null or lobby != null:
			go_back()
			return
		if paused:
			resume_game()
		elif phase!="menu":
			pause_game()
		return
	if phase!="draw" or paused:
		return
	if event is InputEventMouseButton:
		# Auf dem Handy erzeugt Android zusätzlich Maus-Ereignisse aus Berührungen; die zählen nicht.
		if event.device==InputEvent.DEVICE_ID_EMULATION or not event.pressed:
			return
		if event.button_index==MOUSE_BUTTON_WHEEL_UP:
			zoom_view(0.9,event.position)
		elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN:
			zoom_view(1.1,event.position)
		elif event.button_index==MOUSE_BUTTON_LEFT:
			touch_down(MOUSE_ID,event.position)
	elif event is InputEventScreenTouch and event.pressed:
		touch_down(event.index,event.position)

func now_seconds() -> float:
	return float(Time.get_ticks_usec())/1000000.0

func touch_down(id: int, pos: Vector2) -> void:
	touches[id] = pos
	var now := now_seconds()
	if touches.size()==1:
		# Greifradius in Bildpunkten -> Meter beim aktuellen Zoom.
		if recorder.begin(world_point(pos),now,maxf(0.8,GRAB_PX*screen_scale().x)):
			pointer = id
			stroke_started = now
			stroke_origin = pos
			refresh_line()
			return
		if now-last_tap < 0.32 and pos.distance_to(last_tap_pos) < 90.0:
			reset_view()
			last_tap = -10.0
		else:
			last_tap = now
			last_tap_pos = pos
		pan_index = id
	elif touches.size()==2:
		if pointer!=-99:
			var first: Vector2 = touches.get(pointer,stroke_origin)
			if now-stroke_started < PINCH_GRACE and first.distance_to(stroke_origin) < 24.0:
				# Zwei Finger fast gleichzeitig: Zoomen gemeint, der Malbeginn wird verworfen.
				recorder.stop()
				pointer = -99
			else:
				touches.erase(id)
				return
		pan_index = -99
		pinch_ids = touches.keys()
		var a: Vector2 = touches[pinch_ids[0]]
		var b: Vector2 = touches[pinch_ids[1]]
		pinch_dist = maxf(1.0,a.distance_to(b))
		pinch_mid = (a+b)*0.5
	else:
		touches.erase(id)

func touch_move(id: int, pos: Vector2) -> void:
	var previous: Vector2 = touches[id]
	touches[id] = pos
	if id==pointer:
		record_point(pos)
	elif pinch_ids.size()==2 and id in pinch_ids:
		var a: Vector2 = touches[pinch_ids[0]]
		var b: Vector2 = touches[pinch_ids[1]]
		var dist := maxf(1.0,a.distance_to(b))
		var mid := (a+b)*0.5
		zoom_view(pinch_dist/dist,mid)
		pan_view(mid-pinch_mid)
		pinch_dist = dist
		pinch_mid = mid
	elif id==pan_index:
		pan_view(pos-previous)

func touch_up(id: int) -> void:
	if id==pointer:
		end_stroke()
	touches.erase(id)
	if id in pinch_ids:
		pinch_ids = []
		if touches.size()==1:
			pan_index = touches.keys()[0]
	if id==pan_index:
		pan_index = -99

func release_touches() -> void:
	touches.clear()
	pinch_ids = []
	pan_index = -99
	pointer = -99

func end_stroke() -> void:
	if recorder!=null:
		recorder.end()
		if recorder.discarded and hud.detail!=null:
			hud.detail.text = "Zu kurz – verworfen"
	pointer = -99
	refresh_line()

func refresh_line() -> void:
	if phase!="draw" or recorder==null:
		return
	world.draw_route(recorder.route,false,recorder.open_route_index(),recorder.ghost())
	var tip: Vector2 = recorder.last_pos if not recorder.route.is_empty() else track.at(0.0)
	var tip_sc := int(recorder.route[-1].get("sc", -1)) if not recorder.route.is_empty() else -1
	world.marker.position = Vector3(tip.x,0.31 + track.draw_height(recorder.last_phase, tip_sc, tip),tip.y)

func _input(event: InputEvent) -> void:
	# Mehrspieler: Turboknöpfe mit mehreren Fingern gleichzeitig (vor der Oberfläche, die nur einen Finger kennt).
	if party != null and phase in ["countdown","race"] and not paused and pad_input(event):
		get_viewport().set_input_as_handled()
		return
	# Ein begonnener Strich läuft weiter, auch wenn der Finger über eine Leiste gleitet.
	if phase=="draw" and not paused and recorder!=null:
		if event is InputEventMouseMotion and event.device!=InputEvent.DEVICE_ID_EMULATION and touches.has(MOUSE_ID):
			touch_move(MOUSE_ID,event.position)
		elif event is InputEventScreenDrag and touches.has(event.index):
			touch_move(event.index,event.position)
	# Loslassen über der Oberfläche beendet Strich, Zoom und Turbo trotzdem.
	if event is InputEventMouseButton and not event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		turbo_held = false
		if event.device!=InputEvent.DEVICE_ID_EMULATION:
			touch_up(MOUSE_ID)
	if event is InputEventScreenTouch and not event.pressed:
		touch_up(event.index)

func record_point(screen: Vector2) -> void:
	if recorder.sample(world_point(screen),now_seconds()):
		if recorder.complete:
			pointer = -99
			release_touches()
			line_complete()
	elif not recorder.active and pointer!=-99:
		end_stroke()
		hud.detail.text = "Im schimmernden Ende neu ansetzen"

func live_rank() -> int:
	# Platz meines Autos im laufenden Rennen.
	var rank := 1
	for i in range(vehicles.size()):
		if i != me and not vehicles[i].crashed and (vehicles[i].finish_time>=0 or vehicles[i].progress>vehicles[me].progress):
			rank += 1
	return rank

func sorted_results() -> Array:
	var rows: Array = []
	for i in range(vehicles.size()):
		# Abgestürzte Autos landen hinter allen anderen.
		rows.append({"index":i,"time":vehicles[i].finish_time,"progress":-1.0 if vehicles[i].crashed else vehicles[i].progress,"crashed":vehicles[i].crashed})
	rows.sort_custom(func(a: Dictionary,b: Dictionary):
		if a.time>=0 and b.time>=0: return a.time<b.time
		if a.time>=0: return true
		if b.time>=0: return false
		return a.progress>b.progress)
	for i in range(rows.size()):
		rows[i].rank = i+1
		if i>0 and rows[i].time>=0 and rows[i].time==rows[i-1].time:
			rows[i].rank = rows[i-1].rank
	return rows

func player_result_rank(rows: Array) -> int:
	for row in rows:
		if row.index==me:
			return row.rank
	return 1

func finish_race() -> void:
	if party != null:
		party_finish()
		return
	phase = "result"
	turbo_held = false
	var rows := sorted_results()
	var rank := player_result_rank(rows)
	var record := false
	var own := vehicles[me]
	if track.mode == "drift":
		# Drift: gewonnen = im Zeitlimit ins Ziel und Punkteziel der Herausforderung erreicht.
		var v0 := own
		var in_time := v0.finish_time >= 0.0 and v0.finish_time <= drift_limit() and not v0.crashed
		rank = 1 if in_time and v0.drift_score >= drift_target() else 2
		if not demonstration and in_time and solo():
			record = store.result_drift(track_id, stage, car_choice, int(v0.drift_score), rank == 1)
		result_record = record
		result_won = rank == 1
		hud.drift_results(int(v0.drift_score), drift_target(), in_time, record)
		if result_won:
			world.confetti(Vector3(v0.pos.x, 0.3 + v0.z, v0.pos.y))
		return
	if own.crashed:
		# Absturz: verloren, keine Zeit für Bestenliste oder Bestzeit.
		rank = vehicles.size()
		for row in rows:
			if row.index == me:
				row.rank = rank
	elif not demonstration and solo():
		# Mehrspieler (mehrere Menschen): kein Gold, keine Bestenliste, kein Geist (docs/MULTIPLAYER_RECHERCHE.md 5.5).
		record = store.result(track_id,stage,car_choice,own.finish_time,rank==1)
		if record:
			save_ghost()
		var plan: Array = []
		for point in recorder.route:
			plan.append({"x":point.p.x,"z":point.p.y,"speed":point.speed,"s":point.s})
		var run := {"version":1,"physics":RaceVehicle.VERSION,"track":track_id,"track_hash":track.file_hash,"rev":track.rev,"car":car_choice,"stage":stage,"time":own.finish_time,"raw":recorder.raw,"plan":plan,"turbo":turbo_actions}
		var file := FileAccess.open(run_record_path,FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify(run))
	result_record = record
	result_won = rank==1
	hud.results(rows,rank,record)
	if result_won and not own.crashed:
		world.confetti(Vector3(own.pos.x, 0.3 + own.z, own.pos.y))

func pause_game() -> void:
	if lobby != null:
		# WLAN-Mehrspieler: niemand hält das gemeinsame Spiel an (Zurück-Taste: go_back). Ein laufender Strich endet trotzdem.
		if phase == "draw" and recorder != null:
			recorder.end()
			release_touches()
			refresh_line()
		return
	if party != null and phase in ["party_setup","party_garage","result"]:
		return   # nichts anzuhalten; die Zurück-Taste führt hier über go_back() zurück
	if paused or phase in ["menu","result"]:
		if phase=="result": show_menu()
		return
	paused = true
	turbo_held = false
	release_pads()
	if recorder!=null: recorder.end()
	release_touches()
	refresh_line()
	hud.paused()

func resume_game() -> void:
	paused = false
	if party != null:
		match phase:
			"handover": hud.party_ui.handover()
			"drawn": hud.party_ui.drawn_card()
			"reveal": hud.party_ui.reveal()
			"draw": hud.drawing()
			_: hud.race()
		return
	if phase=="draw": hud.drawing()
	else: hud.race()

func _notification(what: int) -> void:
	# WLAN-Mehrspieler: Hintergrund melden, bevor Android die App anhält (die anderen sehen „im Hintergrund“).
	if lobby != null and lobby.race != null and (what==NOTIFICATION_APPLICATION_FOCUS_OUT or what==NOTIFICATION_APPLICATION_PAUSED):
		# WLAN-Rennen: Turbo loslassen, bevor Android die App anhält (sonst bliebe er beim Gastgeber gedrückt).
		turbo_held = false
		last_boost_input = false
		lobby.race.set_turbo(false)
	if lobby != null and (what==NOTIFICATION_APPLICATION_PAUSED or what==NOTIFICATION_APPLICATION_RESUMED):
		lobby.set_away(what==NOTIFICATION_APPLICATION_PAUSED)
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT or what==NOTIFICATION_APPLICATION_PAUSED:
		if is_instance_valid(hud) and hud.root!=null:
			pause_game()
	elif what==NOTIFICATION_WM_GO_BACK_REQUEST:
		go_back()

func format_time(value: float) -> String:
	var ms := maxi(0,int(value*1000))
	return "%02d:%02d.%03d" % [ms/60000,(ms/1000)%60,ms%1000]

func go_back() -> void:
	# Android-Zurück: offene Dialoge schließen; im Mehrspieler einen Schritt zurück (Einstellungen → Menü, Wertung → Einstellungen,
	# sonst Pause bzw. weiter); im Einzelspieler wie bisher die Pause. WLAN-Mehrspieler: siehe LobbyScreens.go_back().
	if lobby != null:
		hud.lobby_ui.go_back()
		return
	if phase in ["menu","party_setup","party_garage","result"] and hud.overlay_open():
		hud.close_overlays()
		return
	if party == null:
		pause_game()
		return
	match phase:
		"party_setup":
			show_menu()
		"party_garage":
			close_garage()
		"result":
			open_party()
		_:
			if paused:
				resume_game()
			else:
				pause_game()

func music_on() -> bool:
	# Eigene Einstellung; im WLAN-Mehrspieler kann der Gastgeber die Musik der Mitspieler für die Sitzung abschalten. Der Spielstand
	# bleibt dabei unberührt – nach der Sitzung gilt wieder genau die eigene Einstellung.
	return bool(store.data.music) and (lobby == null or not lobby.music_muted())

func sound_phase() -> String:
	# Musik-Zusammenhang je Phase (Mehrspieler-Phasen wie ihre Einzelspieler-Gegenstücke).
	match phase:
		"party_setup", "party_garage", "handover", "net_menu", "net_lobby", "net_garage", "net_round":
			return "menu"
		"drawn", "net_countdown", "net_drawn":
			return "draw"
		"reveal", "net_reveal", "net_start":
			return "countdown"
	return phase

func line_complete() -> void:
	# Linie fertig gezeichnet: Einzelspieler fährt sofort los, im Mehrspieler ist der Nächste dran.
	if party != null:
		party_line_done()
	elif lobby != null and lobby.draw != null:
		net_line_done()
	else:
		begin_race()

# ---------- Mehrspieler „Weitergeben“ (M2b) ----------
func open_party() -> void:
	# Einstellungen der Runde. Aus dem Menü: Einzelspieler-Strecke und -Herausforderung merken (danach wiederhergestellt), die Runde
	# beginnt mit dem gespeicherten Namen und Auto als Spieler 1. Aus einer laufenden Runde: Einstellungen bleiben erhalten.
	if party == null:
		solo_track = track_id
		solo_stage = stage
		if party_memory == null:
			party_memory = PassParty.create(store.player_name(), car_choice, track_id, stage)
		party = party_memory
	paused = false
	phase = "party_setup"
	turbo_held = false
	release_touches()
	release_pads()
	clear_cars()
	world.draw_routes([], [])
	world.marker.visible = false
	world.visible = false
	hud.party_ui.setup_screen()

func leave_party() -> void:
	# Zurück in den Einzelspieler: dessen Strecke und Herausforderung gelten wieder (nichts davon wurde gespeichert).
	if party == null:
		return
	party = null
	release_pads()
	world.draw_routes([], [])
	stage = solo_stage
	if solo_track != "" and track_id != solo_track:
		request_track(solo_track)
	apply_atmosphere()

func party_garage(k: int) -> void:
	# Garage für Spieler k (Auto und Spielerfarbe, wie im Einzelspieler; nichts wird gespeichert). Zurück: close_garage().
	if party == null or phase != "party_setup":
		return
	phase = "party_garage"
	hud.party_ui.garage_screen(k)

func close_garage() -> void:
	# Aus der Mehrspieler-Garage zurück zu den Einstellungen („Weitergeben“) bzw. in die Lobby (WLAN).
	if phase == "party_garage" and party != null:
		phase = "party_setup"
		hud.party_ui.setup_screen()
	elif phase == "net_garage" and lobby != null:
		phase = "net_lobby"
		hud.lobby_ui.lobby_screen()

func party_load() -> void:
	# Strecke und Herausforderung der Runde (ohne Speichern), Bedingungen wie in der Karriere.
	stage = party.stage
	if track_id != party.track_id:
		request_track(party.track_id)
	apply_atmosphere()

func party_start() -> void:
	party.start_round()
	party_load()
	party_handover()

func party_rematch() -> void:
	party.rematch()
	party_load()
	party_handover()

func party_handover() -> void:
	# Übergabekarte: verdeckt alle Linien; der nächste Spieler tippt, wenn er das Handy hat.
	paused = false
	phase = "handover"
	turbo_held = false
	release_touches()
	release_pads()
	clear_cars()
	world.draw_routes([], [])
	world.marker.visible = false
	world.visible = false
	hud.party_ui.handover()

func party_draw() -> void:
	# Der Spieler am Zug zeichnet mit der normalen Zeichenansicht (Neu zeichnen, Fahrhilfe, Handkamera).
	party.routes[party.turn] = []
	start_drawing()

func party_redraw() -> void:
	party_draw()

func party_line_done() -> void:
	phase = "drawn"
	party.store_line(recorder.route)
	world.marker.visible = false
	world.draw_route(recorder.route)
	hud.party_ui.drawn_card()

func party_pass() -> void:
	party.turn += 1
	if party.turn < party.count():
		party_handover()
	else:
		party_reveal()

func party_reveal() -> void:
	# Alle Linien gleichzeitig in den Spielerfarben, kurz vor dem Start (PassParty.REVEAL_TIME, Tippen startet sofort).
	finish_track_load()
	paused = false
	phase = "reveal"
	reveal_time = 0.0
	clear_cars()
	world.visible = true
	world.marker.visible = false
	apply_atmosphere()
	world.draw_routes(party.routes, party.colors(), false)
	camera_target = track_center()
	hud.party_ui.reveal()

func party_begin_race() -> void:
	if phase != "reveal":
		return
	race_entries = party.entries()
	race_me = party.slot_of(0)
	begin_race()

func party_turbo() -> bool:
	# Turbo aller Menschen aus ihren Knöpfen (Tastatur am PC: 1–4 je Spieler, Leertaste für Spieler 1); Rückgabe: mein Auto (me).
	for i in range(vehicles.size()):
		if field.is_human(i):
			var k := party.player_at(i)
			remote_turbo[i] = bool(pad_held.get(i, false)) or (k >= 0 and k < PLAYER_KEYS.size() and Input.is_physical_key_pressed(PLAYER_KEYS[k])) \
				or (k == 0 and Input.is_physical_key_pressed(KEY_SPACE))
	return bool(remote_turbo.get(me, false))

func pad_input(event: InputEvent) -> bool:
	# Jeder Finger hält genau einen Turboknopf, mehrere Finger gleichzeitig; Maus (PC) als eigener Finger.
	# Aus Berührungen nachgebildete Mausereignisse (Android) zählen nicht.
	var id := -1
	var pressed := false
	var pos := Vector2.ZERO
	if event is InputEventScreenTouch:
		id = event.index
		pressed = event.pressed
		pos = event.position
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.device != InputEvent.DEVICE_ID_EMULATION:
		id = MOUSE_ID
		pressed = event.pressed
		pos = event.position
	else:
		return false
	if pressed:
		var car := hud.pads.pad_at(pos)
		if car < 0:
			return false
		pad_touch[id] = car
	elif pad_touch.has(id):
		pad_touch.erase(id)
	else:
		return false
	pad_held.clear()
	for car in pad_touch.values():
		pad_held[car] = true
	return true

func release_pads() -> void:
	pad_touch.clear()
	pad_held.clear()

func leading_human() -> int:
	# Bester Mensch im Rennen (für Runde und Zeit oben): im Ziel vor unterwegs, sonst weitester Fortschritt.
	var best := -1
	for i in range(vehicles.size()):
		if field == null or not field.is_human(i):
			continue
		if best < 0 or car_rank(i) < car_rank(best):
			best = i
	return best

func car_rank(i: int) -> int:
	# Platz eines Autos im laufenden Rennen (alle Autos): im Ziel nach Zielzeit, unterwegs nach Fortschritt, Ausgeschiedene hinten.
	var v := vehicles[i]
	var rank := 1
	for j in range(vehicles.size()):
		if j == i:
			continue
		var o := vehicles[j]
		if v.crashed:
			if not o.crashed or o.progress > v.progress:
				rank += 1
		elif o.crashed:
			continue
		elif o.finish_time >= 0.0:
			if v.finish_time < 0.0 or o.finish_time < v.finish_time:
				rank += 1
		elif v.finish_time < 0.0 and o.progress > v.progress:
			rank += 1
	return rank

func party_view() -> Array:
	# Gemeinsame Rennkamera: alle Menschen, die noch fahren (sonst alle Menschen), sollen im Bild bleiben. Mitte ihres Rahmens (mit
	# etwas Vorhalt), herausgezoomt so weit wie nötig, mindestens der Folge-Zoom der Einstellungen, höchstens die Übersicht. Je weiter
	# herausgezoomt, desto mehr rückt die Mitte zur Streckenmitte (wie im Einzelspieler).
	var f := clampf(float(store.data.get("camera_zoom",0.4)),0.0,1.0)
	var widest := overview_size()
	var base := minf(widest,48.0*pow(road_fill_size()/48.0,f))
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var height := 0.0
	var n := 0
	for pass_all in [false, true]:
		for i in range(vehicles.size()):
			if not field.is_human(i):
				continue
			var v := vehicles[i]
			if not pass_all and (v.crashed or v.finish_time >= 0.0):
				continue
			var p := render_pos(i) + v.velocity*0.28
			lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
			hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
			height += v.z
			n += 1
		if n > 0:
			break
	var c := track_center()
	if n == 0:
		return [c, widest]
	var mid := (lo + hi)*0.5
	var screen := get_viewport().get_visible_rect().size
	var aspect := screen.x/maxf(1.0,screen.y)
	# Rand für Autos, Schilder und Vorausblick; nutzbar sind etwa 85 % der Breite und 70 % der Höhe (Kopfleiste, Knöpfe in den Ecken).
	var extent := hi - lo + Vector2(12.0, 12.0)
	var need := maxf(extent.x/aspect/0.85, extent.y*maxf(0.5,sin(cam_pitch))/0.7)
	var zoom := clampf(maxf(base, need), base, widest)
	var follow := lerpf(0.45,1.0,sqrt(f))
	var spread := clampf((zoom - base)/maxf(1.0, widest - base), 0.0, 1.0)
	var mid3 := Vector3(mid.x, height/float(n), mid.y)
	# Vorhalt zur Streckenmitte wie im Einzelspieler, aber nur so weit, wie der Bildausschnitt über den Rahmen der Menschen hinaus Luft
	# hat (zoom − need). Vorher wanderte die Mitte auf langen Strecken (Serra) so weit, dass 3 von 4 Autos unter dem Bildrand lagen.
	var room := maxf(0.0, (zoom - need)*0.5)
	var target := mid3 + ((c - mid3)*(1.0 - follow*(1.0 - spread*spread))).limit_length(room)
	return [target, zoom]

func party_rows() -> Array:
	# Wertung aller Autos: Rundkurs/Sprint wie sorted_results(); Drift nach Punkten (im Zeitlimit im Ziel vor allen anderen).
	if track.mode != "drift":
		return sorted_results()
	var rows: Array = []
	var limit := drift_limit()
	for i in range(vehicles.size()):
		var v := vehicles[i]
		var in_time := v.finish_time >= 0.0 and v.finish_time <= limit and not v.crashed
		rows.append({"index": i, "time": v.finish_time, "score": int(v.drift_score), "in_time": in_time, "crashed": v.crashed})
	rows.sort_custom(func(a: Dictionary, b: Dictionary):
		if a.in_time != b.in_time: return a.in_time
		if a.score != b.score: return a.score > b.score
		return a.index < b.index)
	for i in range(rows.size()):
		rows[i].rank = i + 1
		if i > 0 and rows[i].score == rows[i-1].score and rows[i].in_time == rows[i-1].in_time:
			rows[i].rank = rows[i-1].rank
	return rows

func party_finish() -> void:
	# Mehrspieler-Wertung: keine Bestenliste, kein Gold, kein Geist, keine letzte Fahrt (nichts wird gespeichert).
	phase = "result"
	turbo_held = false
	release_pads()
	var rows := party_rows()
	var order: Array = []
	for row in rows:
		order.append(int(row.index))
	party.note_result(order)
	result_record = false
	var winner: int = int(rows[0].index) if not rows.is_empty() else -1
	result_won = winner >= 0 and field.is_human(winner) and not vehicles[winner].crashed
	hud.party_ui.results(rows)
	if result_won:
		var v := vehicles[winner]
		world.confetti(Vector3(v.pos.x, 0.3 + v.z, v.pos.y))

# ---------- Mehrspieler im WLAN (M3: Lobby und Verbindung) ----------
func open_wlan() -> void:
	# „Mehrspieler → Im WLAN“: bindet das Spiel auf Android ans WLAN (NetLobby.enter) und zeigt Eröffnen/Beitreten mit laufender Suche.
	# Aus der Lobby zurück: Sitzung verlassen, wieder suchen.
	if lobby == null:
		solo_track = track_id
		solo_stage = stage
		lobby = NetLobby.new()
		lobby.name = "NetLobby"
		lobby.tracks = TRACKS.duplicate()
		add_child(lobby)
		lobby.joined.connect(net_joined)
		lobby.failed.connect(net_failed)
		lobby.closed.connect(net_closed)
		lobby.round_started.connect(net_round_started)
		lobby.round_ready.connect(net_round_ready)
		lobby.round_cancelled.connect(net_round_cancelled)
		lobby.changed.connect(hud.lobby_ui.refresh)
		lobby.status_changed.connect(hud.lobby_ui.refresh)
		lobby.games_changed.connect(hud.lobby_ui.refresh)
		lobby.notice.connect(hud.lobby_ui.toast)
		lobby.apk_changed.connect(hud.lobby_ui.apk_refresh)
		lobby.apk = apk_share       # neuere Version weitergeben (NetApk)
		lobby.enter(store.player_name(), car_choice)
	paused = false
	phase = "net_menu"
	net_round = {}
	turbo_held = false
	release_touches()
	clear_cars()
	world.marker.visible = false
	world.visible = false
	lobby.search()
	hud.lobby_ui.wlan_screen()

func leave_wlan() -> void:
	# Zurück in den Einzelspieler: Sitzung beenden, WLAN-Bindung lösen (Update-Suche und Internet gehen wieder), Strecke und
	# Herausforderung des Einzelspielers wiederherstellen (nichts davon wurde gespeichert).
	if lobby == null:
		return
	var old := lobby
	lobby = null
	net_round = {}
	old.dispose()
	world.draw_routes([], [])
	stage = solo_stage
	if solo_track != "" and track_id != solo_track:
		request_track(solo_track)
	apply_atmosphere()

func net_host() -> void:
	if lobby == null:
		return
	if lobby.host(track_id, stage) != OK:
		var reason: String = lobby.session.detail
		lobby.search()
		hud.lobby_ui.wlan_screen()
		hud.lobby_ui.message("Eröffnen nicht möglich.", reason)
		return
	phase = "net_lobby"
	hud.lobby_ui.lobby_screen()

func net_join(address: String, port: int, label := "") -> void:
	# Beitreten (gefundenes Spiel oder eingetippte Adresse); Ergebnis über net_joined / net_failed.
	if lobby == null:
		return
	lobby.join(address, port)
	if lobby != null and lobby.mode == "join" and not lobby.is_joined:
		hud.lobby_ui.connecting(label if label != "" else address)

func net_cancel_join() -> void:
	if lobby == null:
		return
	lobby.cancel_join()
	lobby.search()
	hud.lobby_ui.wlan_screen()

func net_joined() -> void:
	phase = "net_lobby"
	hud.lobby_ui.lobby_screen()

func net_failed(reason: String) -> void:
	# Beitritt abgelehnt (Version, Strecken, voll, Rennen läuft) oder Gastgeber nicht erreichbar: Grund zeigen, weiter suchen.
	if lobby == null:
		return
	phase = "net_menu"
	lobby.search()
	hud.lobby_ui.wlan_screen()
	hud.lobby_ui.rejected(reason)     # bei anderer Spielversion mit Angebot der neueren Version (NetApk)

func net_closed(reason: String) -> void:
	# Gastgeber hat beendet oder die Verbindung ist weg: zurück ins Menü mit Hinweis.
	show_menu()
	hud.lobby_ui.message("Mehrspieler beendet.", reason)

func net_set_name(text: String) -> void:
	# Eigener Name aus der Lobby: wie in den Optionen gespeichert, der Gastgeber macht ihn in der Runde eindeutig.
	if lobby == null or ProgressStore.clean_name(text) == "" or ProgressStore.clean_name(text) == store.player_name():
		return
	store.set_player_name(text)
	lobby.set_player_name(store.player_name())

func net_garage() -> void:
	# Garage im WLAN: eigenes Auto und eigene Farbe; jede Wahl geht sofort an den Gastgeber (NetLobby.set_car / set_color).
	if lobby == null or phase != "net_lobby" or lobby.phase != "lobby" or lobby.me().is_empty():
		return
	phase = "net_garage"
	hud.lobby_ui.garage_screen()

func net_start() -> void:
	if lobby != null:
		lobby.start_round()

func net_leave_lobby() -> void:
	# Lobby verlassen (Gastgeber: Spiel beenden, alle Mitspieler kehren ins Menü zurück) → wieder suchen.
	if lobby == null:
		return
	lobby.leave()
	open_wlan()

func net_back_to_lobby() -> void:
	if lobby != null:
		lobby.back_to_lobby()

func net_round_started(info: Dictionary) -> void:
	# Start: Strecke und Herausforderung der Runde laden (ohne Speichern, Bedingungen wie in der Karriere, keine Debug-Vorgaben),
	# dann „geladen“ mit der Prüfsumme melden. Der Gastgeber wartet auf alle.
	net_round = info
	phase = "net_round"
	turbo_held = false
	clear_cars()          # Revanche: Autos, Motoren und Linien des letzten Rennens weg
	world.draw_routes([], [])
	var settings: Dictionary = info.settings
	stage = int(settings.stage)
	net_reported = -1
	if track_id != str(settings.track):
		request_track(str(settings.track))
	apply_atmosphere()
	world.visible = false
	hud.lobby_ui.round_screen()
	net_report_loaded()

func net_report_loaded() -> void:
	# „Geladen“ an den Gastgeber erst, wenn die Welt wirklich steht (sonst nach dem Bau aus _loaded); einmal je Runde.
	if lobby == null or phase != "net_round" or net_round.is_empty() or not track_ready() or lobby.phase != "loading":
		return
	if net_reported == lobby.round_id:
		return
	net_reported = lobby.round_id
	lobby.report_loaded(track.file_hash, track)

func net_round_ready(info: Dictionary) -> void:
	net_round = info
	net_begin_drawing()

func net_begin_drawing() -> void:
	# M4: Alle Geräte haben Strecke und Herausforderung der Runde mit gleicher Prüfsumme geladen. Gemeinsames 3-2-1 bis
	# lobby.draw.draw_at (Host-Uhr), dann zeichnet jeder seine Linie; die der anderen bleiben bis zur Enthüllung verdeckt.
	if lobby == null or lobby.draw == null:
		return
	finish_track_load()
	var d: NetDraw = lobby.draw
	d.notice.connect(hud.lobby_ui.toast)
	d.rejected.connect(net_plan_rejected)
	paused = false
	phase = "net_countdown"
	pointer = -99
	release_touches()
	clear_cars()
	recorder = null
	world.visible = true
	apply_atmosphere()
	world.draw_routes([], [])
	world.draw_route([])
	world.tyre_tracks.clear()
	world.update_tracks(0.0)
	world.marker.visible = true
	var start := track.at(0.0)
	world.marker.position = Vector3(start.x,0.31 + track.surface_z(0.0),start.y)
	camera_target = track_center()
	cam_zoom = overview_size()
	set_camera(camera_target)
	hud.lobby_ui.draw_countdown()

func net_tick() -> void:
	# Gemeinsame Zeitpunkte des Zeichnens (Host-Uhr über den Uhrabgleich): Zeichenstart, Enthüllung, Ampel. Nur Ablauf und Anzeige.
	var d: NetDraw = lobby.draw
	match phase:
		"net_countdown":
			var left := d.seconds_until(d.draw_at)
			hud.lobby_ui.update_countdown(left)
			if left <= 0.0:
				start_drawing()
		"draw":
			if recorder != null:
				d.set_progress(recorder.progress / float(track.laps))
		"net_reveal":
			var left := d.seconds_until(d.start_at)
			hud.lobby_ui.update_reveal(left)
			if left <= 0.0:
				net_begin_race()
	if d.phase == "plans" and phase in ["net_countdown", "draw", "net_drawn"] and d.seconds_until(d.reveal_at) <= 0.0:
		net_reveal()

func net_line_done() -> void:
	# Linie fertig gezeichnet: ansehen, dann „Fertig“ (abgeben) oder neu zeichnen.
	phase = "net_drawn"
	lobby.draw.set_progress(1.0)
	world.marker.visible = false
	world.draw_route(recorder.route)
	hud.lobby_ui.drawn_card()

func net_submit() -> void:
	# „Fertig“: Linie an den Gastgeber (er prüft sie und wartet auf alle). Danach Warteansicht mit dem Stand der anderen.
	if lobby == null or lobby.draw == null or phase != "net_drawn" or recorder == null:
		return
	var problem: String = lobby.draw.submit(LineRecorder.plan_to_data(recorder.route))
	hud.lobby_ui.drawn_card()
	if problem != "":
		hud.lobby_ui.message("Linie nicht abgegeben.", problem)

func net_redraw() -> void:
	# Neu zeichnen – auch nach „Fertig“, solange noch nicht alle fertig sind (die abgegebene Linie wird zurückgezogen).
	if lobby == null or lobby.draw == null or lobby.draw.phase != "draw":
		return
	lobby.draw.withdraw()
	start_drawing()

func net_plan_rejected(reason: String) -> void:
	if phase == "net_drawn":
		hud.lobby_ui.drawn_card()
	hud.lobby_ui.message("Linie nicht angenommen.", reason)

func net_reveal() -> void:
	# Alle Linien gleichzeitig in den Spielerfarben (auf allen Geräten zur selben Zeit), bis zur gemeinsamen Ampel.
	finish_track_load()
	paused = false
	phase = "net_reveal"
	pointer = -99
	release_touches()
	clear_cars()
	world.visible = true
	world.marker.visible = false
	apply_atmosphere()
	var round_party: PassParty = lobby.draw.party()
	world.draw_routes(round_party.routes, round_party.colors(), false)
	camera_target = track_center()
	hud.lobby_ui.reveal_screen()

func net_begin_race() -> void:
	# M5: gemeinsame Ampel und Rennen. Der Gastgeber rechnet (lobby.race.sim, in NetLobby.poll – auch ohne Oberfläche), jedes Gerät zeigt
	# die Marionetten lobby.race.view mit derselben Verzögerung; die Ampel läuft nach der gemeinsamen Uhr. Ohne Rennen (sollte nicht
	# vorkommen) bleibt die Enthüllung mit einem Hinweis stehen.
	var r: NetRace = lobby.race if lobby != null else null
	finish_track_load()
	if r == null:
		phase = "net_start"
		hud.lobby_ui.start_screen()
		return
	paused = false
	demonstration = false
	pointer = -99
	release_touches()
	release_pads()
	clear_cars()
	world.draw_routes([], [])
	world.visible = true
	world.marker.visible = false
	world.tyre_tracks.clear()
	skid_tick = 0
	world.update_tracks(0.0)
	apply_atmosphere()
	turbo_held = false
	last_boost_input = false
	turbo_actions.clear()
	result_record = false
	result_won = false
	net_music_won = false
	field = r.view
	me = maxi(0, r.my_index)
	race_time = r.display_ticks() / 60.0
	countdown = -race_time
	net_count = mini(ceili(countdown), 4)
	phase = "countdown" if countdown > 0.0 else "race"
	prepare_race_view()
	for i in range(vehicles.size()):
		record_tyre_tracks(i)
	hud.race()
	hud.lobby_ui.race_overlay()
	if not r.results_changed.is_connected(net_results_changed):
		r.results_changed.connect(net_results_changed)
		r.notice.connect(hud.lobby_ui.toast)

func net_race_step(_dt: float) -> void:
	# Ein Darstellungstakt des WLAN-Rennens (nur Anzeige, die Simulation läuft beim Gastgeber): eigener Turbo an den Gastgeber,
	# Marionetten auf die Anzeigezeit, Ampel nach der gemeinsamen Uhr, Ereignisse (Funken, Ton, Blasen), Wertung vom Gastgeber.
	var r: NetRace = lobby.race
	var ticks := r.display_ticks()
	race_time = ticks / 60.0
	var held := (turbo_held or Input.is_physical_key_pressed(KEY_SPACE)) and phase != "result"
	if held != last_boost_input:
		last_boost_input = held
		r.set_turbo(held)
	r.apply_view(ticks)
	hud.lobby_ui.update_race(r)
	if phase == "countdown":
		countdown = -race_time
		var count := ceili(countdown)
		if count != net_count:
			net_count = count
			# Ampel: dreimal Rot (bei 3, 2, 1), dann Grün beim Start – auf allen Geräten zur selben Zeit.
			sound.start_signal(countdown <= 0.0)
		if hud.center != null:
			hud.center.text = str(count) if countdown > 0.0 else "LOS"
		if countdown > 0.0:
			return
		phase = "race"
	var hits := r.take_events(ticks)
	if bool(store.data.get("bubbles", true)):
		chatter.observe(vehicles, hits, race_time, field.human_mask, me, phase == "race")   # nur lesen (Sprechblasen)
	for hit in hits:
		contact_sparks(hit[0], hit[1], hit[2])
	update_tyre_tracks()
	update_models()
	if phase == "race":
		race_sounds()
		if r.result_shown(ticks):
			net_finish()

func net_finish() -> void:
	# Alle Menschen fertig (Anzeigezeit des Gastgebers erreicht): Wertung mit Namen und Zeiten bzw. Punkten. Nichts wird gespeichert.
	var r: NetRace = lobby.race
	phase = "result"
	turbo_held = false
	if last_boost_input:
		last_boost_input = false
		r.set_turbo(false)
	var mine := r.row_of(me)
	result_record = false
	result_won = not mine.is_empty() and int(mine.rank) == 1 and not bool(mine.crashed) and bool(mine.get("in_time", true)) and r.my_index >= 0
	# Musik der Wertung: alle hören dasselbe Stück (der Gastgeber entscheidet, die Mitspieler folgen) – Sieg-Stück, wenn ein Mensch
	# gewonnen hat, Niederlage-Stück, wenn die KI vorn liegt (statt je Handy eigener Sieg/Niederlage-Klänge).
	net_music_won = NetRace.human_won(r.rows, field)
	hud.lobby_ui.net_results(r.rows)
	if result_won and me < vehicles.size():
		var v := vehicles[me]
		world.confetti(Vector3(v.pos.x, 0.3 + v.z, v.pos.y))

func net_results_changed() -> void:
	# Neue Wertung (KI im Ziel, endgültig): Ergebnisbildschirm neu, solange keine Nachfrage offen ist.
	if lobby != null and lobby.race != null and phase == "result" and not hud.lobby_ui.dialog_open():
		hud.lobby_ui.net_results(lobby.race.rows)

func net_rematch() -> void:
	# Gastgeber: Revanche (neue Linien, gleiche Einstellungen, der Sieger startet hinten).
	if lobby != null and not lobby.rematch() and lobby.mode == "host" and lobby.phase == "ready":
		hud.lobby_ui.message("Revanche nicht möglich.", "Die Wertung ist noch nicht da.")

func net_round_cancelled(reason: String) -> void:
	net_round = {}
	phase = "net_lobby"
	release_touches()
	clear_cars()
	world.draw_routes([], [])
	world.marker.visible = false
	world.visible = false
	hud.lobby_ui.lobby_screen()
	if reason != "":
		hud.lobby_ui.message("Zurück in der Lobby.", reason)
