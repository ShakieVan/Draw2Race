extends SceneTree

# Reifenqualm (nur Darstellung, Leitplanke 4): Knoten an Klötzchen- und KI-Karosserie, Ausstoßrate aus rear_spin und Querrutschen
# (je gerendertem Bild, bei jeder Bildrate), Grafikstufen, Wetter, loser Belag (Staub statt Qualm, im Regen Matsch), Lineal-Deck, Pause,
# Geist, schneller drehende Hinterräder, Lenkanzeige, Gummispuren der Hinterräder – und die Simulation bleibt mit und ohne Modelle
# bitgleich.
var failures := 0
var checks := 0
var app: Node
var store_path := ""

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ",message)
	else: print("PASS: ",message)

func _initialize() -> void:
	call_deferred("run")

func wild_route(c: Circuit) -> Array[Dictionary]:
	# Wie test_air/test_race: ruhige KI-Linie, Kurven 85 % zu schnell – damit kommt der Drift King mit bicycle-7 quer.
	var wild := c.ai_route(1.5)
	for p in wild:
		if c.curvature(float(p.s)) > 0.03:
			p.speed = float(p.speed) * 1.85
	return wild

func emitters(model: Node3D) -> Array:
	return model.get_node("Smoke").get_children() if model.has_node("Smoke") else []

func on_share(model: Node3D, frames: int, ticks_per_frame := 1.0) -> float:
	# Anteil der gerenderten Bilder mit Ausstoß: je Bild ticks_per_frame Physiktakte (update_models) und ein pulse_tyre_smoke wie in
	# _process (1 = 60 Bilder/s, 2 = 30, 0,5 = 120).
	var on := 0
	var due := 0.0
	for k in range(frames):
		due += ticks_per_frame
		while due >= 1.0:
			app.update_models()
			due -= 1.0
		app.pulse_tyre_smoke()
		if (emitters(model)[0] as CPUParticles3D).emitting:
			on += 1
	return float(on) / frames

func frame() -> void:
	# Ein Physiktakt samt gerendertem Bild (die Prüfung schaltet _process ab, damit nichts außer der Reihe läuft).
	app._physics_process(1.0 / 60.0)
	app.pulse_tyre_smoke()

func run() -> void:
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	await process_frame
	store_path = "user://test_smoke_%s.json" % Time.get_ticks_usec()
	app.store = ProgressStore.new(store_path)
	app.run_record_path = store_path + ".run"
	app.store.data["ghost"] = false
	# Eigenes Geisterverzeichnis: Die Prüfung schreibt einen Geist, die Geister des Spielers bleiben auch bei einem Abbruch unberührt.
	app.ghost_dir = store_path.get_basename() + "_ghosts"
	app.debug_data()["unlock"] = true
	test_nodes()
	test_emission()
	test_deck()
	test_ghost()
	test_wheels()
	test_tyre_marks()
	test_same_simulation()
	for suffix in ["", ".bak", ".tmp", ".run"]:
		if FileAccess.file_exists(store_path + suffix):
			DirAccess.remove_absolute(store_path + suffix)
	if DirAccess.dir_exists_absolute(app.ghost_dir):
		for f in DirAccess.get_files_at(app.ghost_dir):
			DirAccess.remove_absolute(app.ghost_dir + "/" + f)
		DirAccess.remove_absolute(app.ghost_dir)
	print("RESULT: ",checks-failures,"/",checks," passed")
	quit(1 if failures else 0)

# ---------- 1. Knoten ----------
func test_nodes() -> void:
	app.select_track("arena")
	var world: Diorama = app.world
	world.premium = false
	var classic: Node3D = world.car_model(Color("d35400"), false, "drift")
	var list := emitters(classic)
	var ok := list.size() == 2
	for node in list:
		var e := node as CPUParticles3D
		var mat := (e.mesh as QuadMesh).material as ShaderMaterial
		ok = ok and e != null and not e.local_coords and not e.emitting and e.draw_order == CPUParticles3D.DRAW_ORDER_INDEX and e.position.x < -0.5 and e.position.y > 0.0 and e.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF 			and mat != null and mat.shader.code.contains("lamp_at") and not mat.shader.code.contains("EMISSION")
	ok = ok and signf((list[0] as Node3D).position.z) != signf((list[1] as Node3D).position.z)
	# Shader als Datei (wie Nebel und Schnee), mit Ausgleich für den OpenGL-Rückfall (sRGB-Farbe, angehobene Deckkraft).
	var shader: Shader = (((list[0] as CPUParticles3D).mesh as QuadMesh).material as ShaderMaterial).shader
	check(shader.resource_path == "res://assets/tyre_smoke.gdshader" and shader.code.contains("RENDERER_COMPATIBILITY"),
		"Qualm-Shader aus assets/tyre_smoke.gdshader, mit Zweig für den OpenGL-Rückfall")
	check(ok, "Klötzchen: „Smoke“ mit 2 Emittern an den Hinterrädern (x %.2f, z ±%.2f), Wolke in der Welt, Licht aus Umgebung und Laternen, ohne Schatten" % [(list[0] as Node3D).position.x, absf((list[0] as Node3D).position.z)])
	# Nachts dunkel (kein Eigenleuchten): Tageslicht-Anteil des Qualms und des Staubs folgt der Tageszeit.
	var smoke_mat := (((list[0] as CPUParticles3D).mesh as QuadMesh).material) as ShaderMaterial
	var dust_mat := ((classic.get_node("Dust") as CPUParticles3D).mesh as QuadMesh).material as ShaderMaterial
	world.smoke_look(classic.get_node("Smoke"), "dry", 2, "day")
	var day: Vector3 = smoke_mat.get_shader_parameter("day_light")
	world.smoke_look(classic.get_node("Smoke"), "dry", 2, "night")
	var night: Vector3 = smoke_mat.get_shader_parameter("day_light")
	var dust_night: Vector3 = dust_mat.get_shader_parameter("day_light")
	check(day.x > 0.95 and night.length() < day.length() * 0.35 and dust_night == night,
		"Qualm und Staub leuchten nicht selbst: Tageslicht %.2f am Tag, %.2f nachts (dazu nur Laternenlicht)" % [day.length() / sqrt(3.0), night.length() / sqrt(3.0)])
	# KI-/Premium-Karosserie: Lage aus den Rad-Meshes (headless meldet der Grafikserver ggf. OpenGL, daher direkt aufgebaut).
	world.premium = true
	var premium := Node3D.new()
	world.add_child(premium)
	world.premium_car(premium, Color("d35400"), "drift")
	world.add_tyre_smoke(premium, world.CAR_STYLES.coupe)
	var hubs: Array[Vector3] = []
	for wheel: Node3D in premium.get_meta("wheels"):
		if not wheel.name.begins_with("Wheel_F"):
			hubs.append(premium.to_local(wheel.global_position))
	var near := hubs.size() == 2 and emitters(premium).size() == 2
	for node in emitters(premium):
		var e := node as Node3D
		var best := 99.0
		for h in hubs:
			best = minf(best, Vector2(e.position.x - (h.x - 0.12), e.position.z - h.z).length())
		near = near and best < 0.01
	check(near, "KI-Karosserie: Emitter an den echten Hinterrädern %s" % str(hubs))
	if world.uses_premium("drift"):
		var full: Node3D = world.car_model(Color("d35400"), false, "drift")
		check(emitters(full).size() == 2 and full.has_meta("wheels"), "car_model mit KI-Karosserie hat „Smoke“")
		full.queue_free()
	world.smoke_look(classic.get_node("Smoke"), "dry", 1)
	var reduced := (emitters(classic)[0] as CPUParticles3D).amount
	var reduced_rate := reduced / (emitters(classic)[0] as CPUParticles3D).lifetime
	world.smoke_look(classic.get_node("Smoke"), "dry", 2)
	var full_amount := (emitters(classic)[0] as CPUParticles3D).amount
	var full_rate := full_amount / (emitters(classic)[0] as CPUParticles3D).lifetime
	# Mittel spart an der Länge der Wolke, nicht an ihrer Dichte: gleich viele Ballen je Sekunde (vorher 14 statt 22, die Spur zerfiel).
	check(reduced < full_amount and full_amount == Diorama.SMOKE_AMOUNT[2] and absf(reduced_rate / full_rate - 1.0) < 0.1,
		"Grafikstufe Mittel %d, Hoch %d Partikel je Rad; Ausstoß %.1f bzw. %.1f Ballen je Sekunde" % [reduced, full_amount, reduced_rate, full_rate])
	world.smoke_look(classic.get_node("Smoke"), "rain", 2)
	var spray := emitters(classic)[0] as CPUParticles3D
	var mud := classic.get_node("Dust") as CPUParticles3D
	check(spray.lifetime < 1.2 and spray.gravity.y < 0.0 and mud.gravity.y < 0.0 and mud.color.r < 0.15,
		"Regen: Gischt (%.1f s, sinkt); Staub-Emitter schleudert Matsch (dunkel, fällt)" % spray.lifetime)
	world.smoke_look(classic.get_node("Smoke"), "dry", 2)
	check(mud.gravity.y > 0.0 and mud.color.r > 0.4, "Trocken: Staub hell und steigend")
	classic.queue_free()
	premium.queue_free()

# ---------- 2. Ausstoß ----------
func race_setup(id: String, car: int, route: Array[Dictionary]) -> void:
	app.select_track(id)
	app.stage = 0
	app.car_choice = car
	app.start_drawing()
	app.recorder.route = route
	app.recorder.complete = true
	app.begin_race()

func loose_point(c: Circuit) -> Vector2:
	# Ein Punkt mit losem Belag neben der Fahrbahn (Bankett, Wiese).
	for k in range(200):
		for side in [1.0, -1.0]:
			for off in [6.0, 9.0, 12.0, 16.0]:
				var p: Vector2 = c.at(k / 200.0, side * off)
				if str(c.surface_at(p).kind) in ["gravel","dirt","mud","sand","grass"]:
					return p
	return Vector2.INF

func test_emission() -> void:
	race_setup("arena", 7, Circuit.load_track("arena").ai_route(1.5))
	app.phase = "race"
	app.countdown = 0.0
	var v: RaceVehicle = app.vehicles[0]
	var model: Node3D = app.models[0]
	var road: Vector2 = app.track.at(0.1)
	v.pos = road
	v.heading = app.track.tangent(0.1).angle()
	v.velocity = Vector2.from_angle(v.heading) * 3.0
	v.rear_spin = 4.0
	var full := on_share(model, 60)
	v.rear_spin = 2.5
	var half := on_share(model, 60)
	v.rear_spin = 0.0
	var none := on_share(model, 60)
	check(full == 1.0 and absf(half - 0.5) < 0.05 and none == 0.0,
		"Ausstoßrate aus rear_spin: 4 m/s² %.0f %%, 2,5 m/s² %.0f %%, ohne Durchdrehen %.0f %% der Bilder" % [full * 100.0, half * 100.0, none * 100.0])
	# Bildrate: Die Partikel entscheiden je Bild. Mit dem Tastverhältnis im Physiktakt wurde bei 30 Bildern/s aus Stärke 0,5 nie Qualm
	# und aus 0,75 immer (Gegenprüfung); je Bild verteilt muss der Anteil bei 120, 60, 30 und 20 Bildern/s stimmen.
	var worst := 0.0
	var table := ""
	for power in [0.25, 0.5, 0.75]:
		v.rear_spin = 1.0 + 3.0 * power
		for fps in [120, 60, 30, 20]:
			var share := on_share(model, 240, 60.0 / fps)
			worst = maxf(worst, absf(share - power))
			table += " %d/s:%.0f%%" % [fps, share * 100.0]
		table += " |"
	v.rear_spin = 0.0
	check(worst < 0.03, "Stärke 25/50/75 %% bei 120, 60, 30 und 20 Bildern/s getroffen (größte Abweichung %.1f Punkte):%s" % [worst * 100.0, table])
	# Querrutschen: 30° Schwimmwinkel bei 14 m/s ohne Durchdrehen (Stärke 0,52); gerade Fahrt bei Tempo: nichts.
	v.velocity = Vector2.from_angle(v.heading + deg_to_rad(30.0)) * 14.0
	var slide := on_share(model, 60)
	v.velocity = Vector2.from_angle(v.heading + deg_to_rad(4.0)) * 14.0
	var grip := on_share(model, 60)
	check(slide > 0.4 and slide < 0.65 and grip == 0.0, "Querrutschen 30° bei 14 m/s: %.0f %% der Bilder; normale Kurvenfahrt (4°): %.0f %%" % [slide * 100.0, grip * 100.0])
	v.velocity = Vector2.from_angle(v.heading) * 3.0
	v.rear_spin = 4.0
	v.airborne = true
	var air := on_share(model, 20)
	v.airborne = false
	v.finish_time = 10.0
	var done := on_share(model, 20)
	v.finish_time = -1.0
	app.phase = "countdown"
	var waiting := on_share(model, 20)
	app.phase = "race"
	app.world.atmosphere.quality = 0
	var low := on_share(model, 20)
	app.world.atmosphere.quality = 2
	check(air == 0.0 and done == 0.0 and waiting == 0.0 and low == 0.0, "Kein Qualm in der Luft, im Ziel, vor dem Start und in der Grafikstufe Niedrig")
	# Wetter: Regen gibt Gischt (weniger dicht, kurz), kein Abschalten.
	var weather: Dictionary = app.world.atmosphere.conditions
	var saved := str(weather.weather)
	weather.weather = "rain"
	var wet := on_share(model, 20)
	var look := str(model.get_node("Smoke").get_meta("look", ""))
	var spray := emitters(model)[0] as CPUParticles3D
	weather.weather = saved
	check(wet == 1.0 and look.begins_with("rain/") and spray.lifetime < 1.2, "Regen: Ausstoß weiter an, Aussehen „%s“ (Gischt, %.1f s)" % [look, spray.lifetime])
	# Loser Belag: Staub statt Qualm, durchdrehend auch im Stand und weiter ausgeworfen.
	var loose := loose_point(app.track)
	if loose != Vector2.INF:
		v.pos = loose
		v.velocity = Vector2.ZERO
		var on_loose := on_share(model, 20)
		var dust := model.get_node("Dust") as CPUParticles3D
		check(on_loose == 0.0 and dust.emitting and dust.initial_velocity_max > 5.0,
			"Loser Belag (%s): kein Qualm, Staub auch im Stand, Auswurf %.1f m/s" % [str(app.track.surface_at(loose).kind), dust.initial_velocity_max])
		v.rear_spin = 0.0
		app.update_models()
		check(not dust.emitting, "Loser Belag ohne Durchdrehen im Stand: kein Staub (wie bisher erst ab 4 m/s)")
		# Regen auf losem Belag: Durchdrehen schleudert Matsch (vorher zeigte das Rad gar nichts), Rollen staubt nicht.
		weather.weather = "rain"
		v.rear_spin = 4.0
		var muddy := on_share(model, 10)
		var mud_on := dust.emitting and dust.gravity.y < 0.0 and dust.color.r < 0.15
		v.rear_spin = 0.0
		v.velocity = Vector2.from_angle(v.heading) * 10.0
		app.update_models()
		var rolling := dust.emitting
		weather.weather = saved
		app.update_models()
		check(muddy == 0.0 and mud_on and not rolling, "Regen auf losem Belag: durchdrehend Matsch statt Qualm, rollend nichts")
		v.velocity = Vector2.from_angle(v.heading) * 3.0
		v.pos = road
	else:
		check(false, "Arena: kein Punkt mit losem Belag gefunden")
	# Pause: Wolken stehen still, nichts kommt nach; danach wieder normal.
	v.rear_spin = 4.0
	app.update_models()
	app.pause_game()
	var frozen := true
	for e in emitters(model) + [model.get_node("Dust")]:
		frozen = frozen and (e as CPUParticles3D).speed_scale == 0.0 and not (e as CPUParticles3D).emitting
	app.pulse_tyre_smoke()   # in der Pause schaltet das Bild nichts wieder an
	for e in emitters(model):
		frozen = frozen and not (e as CPUParticles3D).emitting
	app.resume_game()
	app.update_models()
	app.pulse_tyre_smoke()
	var thawed := true
	for e in emitters(model):
		thawed = thawed and (e as CPUParticles3D).speed_scale == 1.0 and (e as CPUParticles3D).emitting
	check(frozen and thawed, "Pause friert Qualm und Staub ein, danach qualmt es weiter")
	v.rear_spin = 0.0
	app.show_menu()
	# Allrad (Auto 0) im echten Rennen mit Gegnern: kein Durchdrehen, kein Qualm am eigenen Auto.
	race_setup("azure", 0, Circuit.load_track("azure").ai_route(2.3))
	var spin_max := 0.0
	var smoked := 0
	for tick in range(60 * 18):
		frame()
		for i in range(app.vehicles.size()):
			spin_max = maxf(spin_max, app.vehicles[i].rear_spin)
		if (emitters(app.models[0])[0] as CPUParticles3D).emitting:
			smoked += 1
	check(spin_max == 0.0 and smoked == 0, "Allrad im Rennen (Küste, 18 s samt Ampel, mit Gegnern): rear_spin aller Autos %.2f, Qualm am eigenen Auto in %d Takten" % [spin_max, smoked])
	app.show_menu()

func test_deck() -> void:
	# Wippe im Kinderzimmer: Das Lineal liegt über einer Abkürzung mit Belag „dirt“. Auf dem Holz staubt es nicht, und durchdrehende
	# Hinterräder qualmen dort (Gegenprüfung: vorher 100 % der Takte auf dem Deck als loser Belag gezählt).
	var c := Circuit.load_track("kids")
	race_setup("kids", 7, c.ai_route(2.3, 0.0, 0))
	var on_deck := 0
	var wrong := 0
	var dusty := 0
	var marked := 0
	var marks: TyreTracks = app.world.tyre_tracks
	for tick in range(60 * 90):
		frame()
		var v: RaceVehicle = app.vehicles[0]
		if v.deck != null:
			on_deck += 1
			if app.loose_ground(v):
				wrong += 1
			if (app.models[0].get_node("Dust") as CPUParticles3D).emitting:
				dusty += 1
			# Neue Stücke dieses Takts (Zeit = Rennzeit) an den eigenen Rädern; die des Gegners liegen woanders.
			for k in range(marks.segments.size() - 1, -1, -1):
				var s: Dictionary = marks.segments[k]
				if float(s.time) != app.race_time:
					break
				if Vector2(s.b).distance_to(v.pos) < 2.0:
					marked += 1
		elif on_deck > 0:
			break   # einmal über das Lineal genügt
	check(on_deck > 60 and wrong == 0 and dusty == 0, "Lineal (Wippe): %d Takte auf dem Deck, davon %d als loser Belag, %d mit Staub" % [on_deck, wrong, dusty])
	# Spuren: Das Deck kippt, in der Welt liegende Spuren hingen danach in der Luft (vorher 482 braune Erdspuren je Überfahrt).
	check(marked == 0, "Lineal: keine Reifenspuren auf dem kippenden Holzdeck (%d Stücke)" % marked)
	app.show_menu()

func ghost_listing() -> String:
	# Namen und Prüfsummen der Geister des Spielers (wie test_party).
	var out := ""
	if DirAccess.dir_exists_absolute("user://ghosts"):
		for f in DirAccess.get_files_at("user://ghosts"):
			out += "%s:%s " % [f, FileAccess.get_md5("user://ghosts/" + f)]
	return out

func test_ghost() -> void:
	# Geist eines Drift King (Heckantrieb) auf einer Rennstrecke: qualmt beim Anfahren wie ein echtes Auto, aber durchscheinend.
	# Die Geisterdatei liegt im eigenen Verzeichnis der Prüfung (app.ghost_dir, siehe run).
	var player_ghosts := ghost_listing()
	app.select_track("azure")
	app.stage = 0
	var path: String = app.ghost_path()
	DirAccess.make_dir_recursive_absolute(app.ghost_dir)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"physics": RaceVehicle.VERSION, "track_hash": app.track.file_hash, "car": 7, "time": 30.0,
		"plan": LineRecorder.plan_to_data(app.track.ai_route(1.5)), "turbo": []}))
	file.close()
	app.store.data["ghost"] = true
	race_setup("azure", 0, Circuit.load_track("azure").ai_route(2.3))
	var found: bool = app.ghost != null and is_instance_valid(app.ghost_model)
	var smoked := 0
	var spin_max := 0.0
	var faded := found and emitters(app.ghost_model).size() == 2
	if found:
		for e in emitters(app.ghost_model):
			# Deckkraft über den Shader (fade): transparency wirkt bei eigenem ALPHA nicht und im Mobile-Renderer gar nicht.
			faded = faded and is_equal_approx(float((e as CPUParticles3D).get_instance_shader_parameter("fade")), 0.35)
		for tick in range(60 * 5):
			frame()
			spin_max = maxf(spin_max, app.ghost.rear_spin)
			if (emitters(app.ghost_model)[0] as CPUParticles3D).emitting:
				smoked += 1
	check(found and faded and smoked > 30 and spin_max > 1.0,
		"Geist (Drift King): qualmt beim Anfahren in %d Takten (rear_spin bis %.2f m/s²), Qualm durchscheinend (fade 0,35)" % [smoked, spin_max])
	app.store.data["ghost"] = false
	app.show_menu()
	DirAccess.remove_absolute(path)
	check(not path.begins_with("user://ghosts/") and ghost_listing() == player_ghosts,
		"Geisterdatei der Prüfung in %s; die Geister des Spielers (user://ghosts) unverändert" % app.ghost_dir)

# ---------- 3. Räder ----------
func test_wheels() -> void:
	# Durchdrehende Hinterräder laufen schneller als die Fahrt, die Vorderräder zeigen den vollen Lenkwinkel (nur Anzeige).
	race_setup("arena", 7, Circuit.load_track("arena").ai_route(1.5))
	var world: Diorama = app.world
	var premium := Node3D.new()
	world.add_child(premium)
	world.premium_car(premium, Color("d35400"), "drift")
	var old: Node3D = app.models[0]
	app.models[0] = premium
	var v: RaceVehicle = app.vehicles[0]
	v.velocity = Vector2.ZERO
	v.rear_spin = 5.0
	v.steering = 0.62
	for k in range(30):
		app.animate_car(0)
	var front_yaw := 0.0
	for wheel: Node3D in premium.get_meta("wheels"):
		if wheel.name.begins_with("Wheel_F"):
			front_yaw = (wheel.basis * Basis(wheel.get_meta("rest")).inverse()).get_euler().y
	check(float(premium.get_meta("spin_rear")) > 4.0 and absf(float(premium.get_meta("spin"))) < 1e-6,
		"Anfahren mit Durchdrehen: Hinterräder %.1f rad in 0,5 s, Vorderräder stehen" % float(premium.get_meta("spin_rear")))
	check(absf(front_yaw + 0.62) < 1e-3, "Vorderräder zeigen den Lenkwinkel unverkürzt (%.3f rad bei 0,62)" % -front_yaw)
	app.models[0] = old
	premium.queue_free()
	v.rear_spin = 0.0
	v.steering = 0.0
	app.show_menu()

# ---------- 4. Gummispuren ----------
func test_tyre_marks() -> void:
	var track := Circuit.new()
	var marks := TyreTracks.new()
	for i in range(30):
		marks.sample(0, Vector2(i * 0.04, 15), 0, 1.2, 0, 0, track, i / 60.0, 0.0, 5.0)
	var rear_only := not marks.segments.is_empty()
	for s in marks.segments:
		rear_only = rear_only and s.kind == "rubber" and Vector2(s.b).x < 29 * 0.04 - 0.5 and float(s.color.a) > 0.6
	check(rear_only, "Anfahren mit durchdrehenden Hinterrädern: %d dunkle Abriebstücke, nur hinter dem Auto (Hinterräder)" % marks.segments.size())
	marks.clear()
	for i in range(30):
		marks.sample(0, Vector2(i * 0.04, 15), 0, 1.2, 0, 0, track, i / 60.0, 0.0, 0.0)
	check(marks.segments.is_empty(), "Gleiches Anfahren ohne Durchdrehen: kein Abrieb")

# ---------- 5. Bitgleich ----------
func test_same_simulation() -> void:
	# Dieselbe Drift-Fahrt einmal im Spiel (Modelle, Qualm, Staub, Spuren, Räder) und einmal als nacktes Feld: Lage, Tempo und Punkte
	# müssen bitgleich sein (Darstellung liest nur).
	var c := Circuit.load_track("arena")
	race_setup("arena", 7, wild_route(c))
	for tick in range(60 * 3):
		frame()
	var ticks := 60 * 20
	var smoked := 0
	var spin_sum := 0.0
	for tick in range(ticks):
		frame()
		if (emitters(app.models[0])[0] as CPUParticles3D).emitting:
			smoked += 1
		spin_sum += app.vehicles[0].rear_spin
	var shown: RaceVehicle = app.vehicles[0]
	# Wie viele Takte das Spiel wirklich gerechnet hat (die Ampel endet je nach Rundung im 180. oder 181. Takt), mit derselben Uhr.
	var raced := roundi(app.race_time * 60.0)
	var bare := RaceField.new(c)
	bare.setup(wild_route(c), app.stage, 7)
	var clock := 0.0
	for tick in range(raced):
		clock += 1.0 / 60.0
		bare.step(1.0 / 60.0, clock, false)
	var raw: RaceVehicle = bare.cars[0]
	check(app.phase == "race" and smoked > 60, "Drift-Fahrt im Spiel: Qualm in %d von %d Takten (rear_spin im Mittel %.2f m/s²)" % [smoked, ticks, spin_sum / ticks])
	check(raw.pos == shown.pos and raw.velocity == shown.velocity and raw.heading == shown.heading and raw.drift_score == shown.drift_score and raw.rear_spin == shown.rear_spin,
		"Simulation mit und ohne Modelle bitgleich nach %d Takten (Punkte %.4f / %.4f, Abstand %s m)" % [raced, shown.drift_score, raw.drift_score, str(raw.pos.distance_to(shown.pos))])
	app.show_menu()
