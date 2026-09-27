extends Node3D

# Streckenreihenfolge der Karriere; die nächste Strecke öffnet sich mit 3 Gold auf der vorigen.
const TRACKS := ["azure","city","forest"]
var track_id := "azure"
var track := Circuit.new()
var recorder: LineRecorder
var store := ProgressStore.new()
var world := Diorama.new()
var hud := RaceHUD.new()
var camera := Camera3D.new()
var sound := RaceSound.new()
var updater := Updater.new()
var vehicles: Array[RaceVehicle] = []
var models: Array[Node3D] = []
var phase := "menu"
var stage := 0
var car_choice := 0
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
var last_boost_input := false
var result_record := false
var result_won := false
# Eigene Spuren der Gegner mit Seitenabstand zur (meist mittigen) Spielerlinie.
const RIVAL_LANES := [1.0, -1.0, 0.4]
# Spielstärke je Herausforderung (1, 2, 3 Rivalen) und Gegner; 3 = nahe am physikalischen Limit.
const RIVAL_SKILL := [[1.6], [2.3, 1.9], [3.0, 2.7, 2.3]]

func _ready() -> void:
	get_tree().auto_accept_quit = true
	get_tree().quit_on_go_back = false
	var saved := str(store.data.get("track","azure"))
	track_id = saved if saved in TRACKS and track_unlocked(TRACKS.find(saved)) else "azure"
	track = Circuit.load_track(track_id)
	car_choice = clampi(int(store.data.get("car",0)),0,RaceVehicle.CARS.size()-1)
	add_child(world)
	world.build(track)
	apply_atmosphere()
	add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = overview_size()
	camera.far = 300
	camera_target = track_center()
	set_camera(camera_target)
	add_child(sound)
	add_child(updater)
	updater.setup(store)
	add_child(hud)
	hud.setup(self)
	updater.changed.connect(func(): if phase == "menu" and not hud.overlay_open(): hud.menu())
	# Automatische Prüfung höchstens einmal täglich, nur auf dem Handy.
	if OS.get_name() == "Android":
		updater.check(false)
	show_menu()
	if "--demo" in OS.get_cmdline_user_args():
		demo()

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
	var override = debug_data().get("override")
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

func track_unlocked(index: int) -> bool:
	return index <= 0 or debug_flag("unlock") or store.gold_count(TRACKS[index-1]) >= 3

func select_track(new_id: String) -> void:
	if new_id == track_id:
		return
	track_id = new_id
	store.data["track"] = new_id
	store.save()
	track = Circuit.load_track(new_id)
	# Welt komplett neu aufbauen (Thema, Deko, Fahrbahn).
	world.queue_free()
	world = Diorama.new()
	add_child(world)
	move_child(world,0)
	world.build(track)
	apply_atmosphere()
	world.visible = phase != "menu"
	camera_target = track_center()

func set_camera(target: Vector3) -> void:
	camera.position = target + Vector3(0,64,48)
	camera.look_at(target,Vector3.UP)

func clear_cars() -> void:
	for model in models:
		model.queue_free()
	models.clear()
	vehicles.clear()

func show_menu() -> void:
	paused = false
	phase = "menu"
	pointer = -99
	turbo_held = false
	clear_cars()
	world.line_mesh.mesh = null
	world.marker.visible = false
	# Menü mit eigenem Hintergrund; die Strecke erscheint erst beim Zeichnen/Fahren.
	world.visible = false
	hud.menu()

func start_drawing() -> void:
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
	world.marker.position = Vector3(start.x,0.31,start.y)
	camera_target = track_center()
	camera.size = overview_size()
	set_camera(camera_target)
	hud.drawing()

func demo() -> void:
	start_drawing()
	demonstration = true
	recorder.route = track.ai_route(1.5)
	recorder.complete = true
	begin_race()

func begin_race() -> void:
	phase = "countdown"
	countdown = 3.0
	race_time = 0.0
	turbo_actions.clear()
	last_boost_input = false
	world.marker.visible = false
	world.draw_route(recorder.route,true)
	if not car_unlocked(car_choice):
		car_choice = 0
	var spec: Dictionary = RaceVehicle.CARS[car_choice]
	# Gegner in anderen Farben als das eigene Auto; sie fahren das Grundmodell.
	var rival_colors: Array = ["5ac4d1","e8c866","a593cf","f16c4c","7fb77e"].filter(func(c): return c != spec.color)
	for i in range(stage+2):
		var plan: Array[Dictionary] = recorder.route if i==0 else track.ai_route(RIVAL_SKILL[stage][i-1],RIVAL_LANES[i-1])
		var vehicle := RaceVehicle.new(track,plan,-float(i)*0.012,0 if i==0 else (1.2 if i%2 else -1.2),car_choice if i==0 else 0)
		vehicles.append(vehicle)
		if i == 0:
			models.append(world.car_model(Color(spec.color),true,str(spec.style)))
		else:
			models.append(world.car_model(Color(rival_colors[i-1]),false,"coupe"))
	snapshot_vehicles()
	update_models()
	place_models()
	for i in range(vehicles.size()):
		record_tyre_tracks(i)
	hud.race()
	sound.start_signal(false)

func record_tyre_tracks(i: int) -> void:
	var v := vehicles[i]
	world.tyre_tracks.sample(i,v.pos,v.heading,v.velocity.length(),v.braking,v.slip,track,race_time)

func update_tyre_tracks() -> void:
	for i in range(vehicles.size()):
		if vehicles[i].finish_time<0:
			record_tyre_tracks(i)
	skid_tick += 1
	if skid_tick%8==0:
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
		models[i].position = Vector3(p.x,0.2,p.y)
		models[i].rotation.y = -h
	# Regen: Scheinwerfer- und Rücklicht-Positionen für die Beleuchtung der Tropfen.
	var lit: Array = []
	for i in range(mini(vehicles.size(), models.size())):
		lit.append([models[i].position, vehicles[i].heading])
	world.atmosphere.update_rain_cars(lit)

func _physics_process(dt: float) -> void:
	if paused:
		return
	snapshot_vehicles()
	if phase == "draw":
		draw_clock += dt
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
		RaceVehicle.update_avoidance(vehicles,dt)
		for i in range(vehicles.size()):
			var v := vehicles[i]
			var boost: bool = (turbo_held or Input.is_physical_key_pressed(KEY_SPACE)) if i==0 and not demonstration else absf(sin(v.progress*TAU))<0.35 and v.turbo>0.25
			if i==0 and boost!=last_boost_input:
				turbo_actions.append({"time":race_time,"held":boost})
				last_boost_input = boost
			v.step(dt,boost,race_time)
		for a in range(vehicles.size()):
			for b in range(a+1,vehicles.size()):
				if vehicles[a].finish_time<0 and vehicles[b].finish_time<0:
					contact_sparks(a,b,RaceVehicle.resolve_contact(vehicles[a],vehicles[b]))
		update_tyre_tracks()
		update_models()
		if vehicles[0].finish_time>=0:
			finish_race()
		elif race_time > 180.0:
			pause_game()
	elif phase == "result":
		# Rivals finish normally; their interpolated times update the result table.
		race_time += dt
		RaceVehicle.update_avoidance(vehicles,dt)
		var new_finish := false
		for i in range(1,vehicles.size()):
			var v := vehicles[i]
			if v.finish_time<0:
				v.step(dt,absf(sin(v.progress*TAU))<0.35 and v.turbo>0.25,race_time)
				if v.finish_time>=0 and hud.result_times.has(i):
					new_finish = true
		for a in range(1,vehicles.size()):
			for b in range(a+1,vehicles.size()):
				if vehicles[a].finish_time<0 and vehicles[b].finish_time<0:
					contact_sparks(a,b,RaceVehicle.resolve_contact(vehicles[a],vehicles[b]))
		if new_finish:
			var rows := sorted_results()
			hud.results(rows,player_result_rank(rows),result_record)
		update_tyre_tracks()
		update_models()

func update_models() -> void:
	for i in range(vehicles.size()):
		models[i].get_node("Turbo").visible = vehicles[i].boosting and phase=="race"
		models[i].get_node("Lights").visible = world.atmosphere.is_dark()
		# Staub nur auf losem Grund, ab Schrittgeschwindigkeit und nicht in der niedrigsten Grafikstufe.
		var dust: CPUParticles3D = models[i].get_node("Dust")
		var loose: bool = str(track.surface_at(vehicles[i].pos).kind) in ["gravel","dirt","mud","sand","grass"]
		dust.emitting = loose and world.atmosphere.quality>=1 and vehicles[i].velocity.length()>4.0 and world.atmosphere.conditions.weather!="rain"
		animate_car(i)
	if not models.is_empty() and models[0].has_node("Halo"):
		# Sanftes Pulsieren (nur Darstellung) hebt das eigene Auto hervor.
		var pulse := 0.5 + 0.5*sin(Time.get_ticks_msec()*0.004)
		var halo: MeshInstance3D = models[0].get_node("Halo")
		halo.material_override.albedo_color.a = 0.22 + 0.22*pulse
		halo.scale = Vector3.ONE*(0.92 + 0.12*pulse)
		if models[0].has_meta("paint_shader"):
			models[0].get_meta("paint_shader").set_shader_parameter("glow",0.12 + 0.18*pulse)
		elif models[0].has_meta("paint"):
			var paint: StandardMaterial3D = models[0].get_meta("paint")
			paint.emission_energy_multiplier = 0.18 + 0.22*pulse

func contact_sparks(a: int, b: int, impact: float) -> void:
	# Funken am Berührpunkt ab spürbarem Stoß (nur Darstellung).
	if impact < 0.8:
		return
	var p := (vehicles[a].pos+vehicles[b].pos)*0.5
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
	var pitch := sin(atan2(64.0,48.0))
	return maxf(2.0*half_x/aspect, 2.0*half_z*pitch/0.74)

func reset_view() -> void:
	view_zoom = overview_size()
	view_focus = track_center()

func clamp_view_state() -> void:
	# Weitester Zoom = ganze Strecke im freien Sichtbereich, engster = Fahrbahn füllt die kürzere Seite.
	# Verschieben: Die Streckenkante (mit Bankett) darf bis in die Mitte des freien Bereichs kommen.
	var widest := overview_size()
	view_zoom = clampf(view_zoom,minf(road_fill_size()*1.2,widest),widest)
	var area := track.bounds.grow(Circuit.HALF_WIDTH+2.0)
	if view_zoom >= widest*0.98:
		view_focus = track_center()
	view_focus.x = clampf(view_focus.x,area.position.x,area.end.x)
	view_focus.z = clampf(view_focus.z,area.position.y,area.end.y)

func screen_scale() -> Vector2:
	# Meter pro Bildpunkt auf dem Boden (x, z) beim aktuellen Zoom.
	var h := maxf(1.0,get_viewport().get_visible_rect().size.y)
	return Vector2(view_zoom/h,view_zoom/h/sin(atan2(64.0,48.0)))

func pan_view(delta: Vector2) -> void:
	var k := screen_scale()
	view_focus.x -= delta.x*k.x
	view_focus.z -= delta.y*k.y
	clamp_view_state()

func zoom_view(factor: float, anchor: Vector2) -> void:
	# Um den Punkt unter den Fingern zoomen: Er bleibt an seiner Stelle.
	var w := world_point(anchor)
	var old := view_zoom
	view_zoom *= factor
	clamp_view_state()
	var k := view_zoom/old
	view_focus.x = w.x-(w.x-view_focus.x)*k
	view_focus.z = w.y-(w.y-view_focus.z)*k
	clamp_view_state()
	camera.size = view_zoom
	set_camera(Vector3(view_focus.x,0,view_focus.z-band_shift(view_zoom)))

func band_shift(zoom: float) -> float:
	# Bildschirm nach unten = Welt +z: um so viel versetzen, dass der Fokus in der Mitte des freien Bereichs erscheint.
	var screen := get_viewport().get_visible_rect().size
	var band: Vector2 = hud.free_band()
	return ((band.x+band.y)*0.5-screen.y*0.5)*zoom/maxf(1.0,screen.y)/sin(atan2(64.0,48.0))

func road_fill_size() -> float:
	# Ortho-Größe, bei der die Fahrbahn (plus Randsteine) die kürzere Bildschirmseite füllt.
	var screen := get_viewport().get_visible_rect().size
	var road := Circuit.HALF_WIDTH*2.0+1.0
	return road if screen.y<=screen.x else road*screen.y/screen.x

func _process(dt: float) -> void:
	if not vehicles.is_empty():
		place_models()
	var target := track_center()
	var zoom := overview_size()
	if phase == "draw" and recorder != null:
		clamp_view_state()
		zoom = view_zoom
		target = view_focus
		target.z -= band_shift(zoom)
	elif phase in ["race","countdown"] and bool(store.data.camera):
		# Zoom-Regler: 0 = bisherige Folgeansicht (48), 1 = Fahrbahnbreite füllt die kürzere Bildschirmseite.
		var f := clampf(float(store.data.get("camera_zoom",0.4)),0.0,1.0)
		var p := render_pos(0) + vehicles[0].velocity*0.28
		var follow := lerpf(0.45,1.0,sqrt(f))
		var c := track_center()
		target = c + (Vector3(p.x,0,p.y)-c)*follow
		zoom = minf(overview_size(),48.0*pow(road_fill_size()/48.0,f))
	if not paused:
		if phase=="draw":
			# Handkamera folgt den Fingern unmittelbar.
			camera_target = target
			camera.size = zoom
		else:
			camera_target = camera_target.lerp(target,1.0-exp(-dt*3.5))
			camera.size = lerpf(camera.size,zoom,1.0-exp(-dt*2.5))
		set_camera(camera_target)
		world.marker.scale = Vector3.ONE*(1.0+sin(Time.get_ticks_msec()*0.006)*0.10)
		# Malzeit läuft auch bei ruhendem Finger (Verweilen = langsam, Altern des offenen Bereichs, Probe).
		if phase=="draw" and pointer!=-99 and touches.has(pointer):
			record_point(touches[pointer])
		if phase=="draw" and recorder!=null:
			refresh_line()
	if phase == "menu" and hud.backdrop.visible:
		hud.backdrop.queue_redraw()
	if phase == "draw" and hud.status!=null:
		hud.status.text = "RUNDE %d / 2" % mini(2,int(recorder.progress)+1)
		hud.detail.text = "%d %% geplant" % int(recorder.progress*50)
		hud.progress_bar.value = recorder.progress*50
		hud.instruction_label.text = recorder.hint
	elif phase in ["race","countdown"]:
		var v := vehicles[0]
		hud.status.text = "RUNDE %d / 2" % mini(2,maxi(1,int(v.progress)+1))
		hud.time_label.text = format_time(race_time)
		hud.speed_label.text = str(int(v.velocity.length()*3.6))
		hud.rank_label.text = "%d / %d" % [live_rank(),vehicles.size()]
		hud.progress_bar.value = v.turbo*100
		if phase=="race":
			hud.center.text = "LOS" if race_time<0.65 else ""
	sound.enabled = bool(store.data.sound)
	sound.set_style(str(store.data.get("music_style","energie")))
	sound.set_volumes(float(store.data.get("music_volume",0.8)),float(store.data.get("sfx_volume",1.0)))
	if sound.context!=phase:
		sound.set_context(phase,result_won)
	sound.tick(vehicles[0] if not vehicles.is_empty() else null,phase=="race",paused,bool(store.data.sound),bool(store.data.music),track,dt)
	capture_frames += 1
	if "--capture" in OS.get_cmdline_user_args() and capture_frames==90:
		get_viewport().get_texture().get_image().save_png("user://preview.png")
		print("CAPTURE ",ProjectSettings.globalize_path("user://preview.png"))
		get_tree().quit()

func world_point(screen: Vector2) -> Vector2:
	var from := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	var hit := from + direction*((0.20-from.y)/direction.y)
	return Vector2(hit.x,hit.z)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.physical_keycode==KEY_ESCAPE:
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
	world.marker.position = Vector3(tip.x,0.31,tip.y)

func _input(event: InputEvent) -> void:
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
			begin_race()
	elif not recorder.active and pointer!=-99:
		end_stroke()
		hud.detail.text = "Im schimmernden Ende neu ansetzen"

func live_rank() -> int:
	var rank := 1
	for i in range(1,vehicles.size()):
		if vehicles[i].finish_time>=0 or vehicles[i].progress>vehicles[0].progress:
			rank += 1
	return rank

func sorted_results() -> Array:
	var rows: Array = []
	for i in range(vehicles.size()):
		rows.append({"index":i,"time":vehicles[i].finish_time,"progress":vehicles[i].progress})
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
		if row.index==0:
			return row.rank
	return 1

func finish_race() -> void:
	phase = "result"
	turbo_held = false
	var rows := sorted_results()
	var rank := player_result_rank(rows)
	var record := false
	if not demonstration:
		record = store.result(track_id,stage,car_choice,vehicles[0].finish_time,rank==1)
		var plan: Array = []
		for point in recorder.route:
			plan.append({"x":point.p.x,"z":point.p.y,"speed":point.speed,"s":point.s})
		var run := {"version":1,"physics":RaceVehicle.VERSION,"track":track_id,"car":car_choice,"stage":stage,"time":vehicles[0].finish_time,"raw":recorder.raw,"plan":plan,"turbo":turbo_actions}
		var file := FileAccess.open(run_record_path,FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify(run))
	result_record = record
	result_won = rank==1
	hud.results(rows,rank,record)

func pause_game() -> void:
	if paused or phase in ["menu","result"]:
		if phase=="result": show_menu()
		return
	paused = true
	turbo_held = false
	if recorder!=null: recorder.end()
	release_touches()
	refresh_line()
	hud.paused()

func resume_game() -> void:
	paused = false
	if phase=="draw": hud.drawing()
	else: hud.race()

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT or what==NOTIFICATION_APPLICATION_PAUSED:
		if is_instance_valid(hud) and hud.root!=null:
			pause_game()
	elif what==NOTIFICATION_WM_GO_BACK_REQUEST:
		pause_game()

func format_time(value: float) -> String:
	var ms := maxi(0,int(value*1000))
	return "%02d:%02d.%03d" % [ms/60000,(ms/1000)%60,ms%1000]
