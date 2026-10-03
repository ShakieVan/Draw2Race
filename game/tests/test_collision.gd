extends SceneTree

# Zusammenstöße mit Deko-Hindernissen (Häuser, Absperrungen, Laternen, Bäume, parkende Autos): Abprall, Drehung, Totalschaden,
# Festfahren, Herkunft der Hindernisse und Reproduzierbarkeit.
var failures := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)
	else:
		print("PASS: ", message)

func straight_plan(track: Circuit, speed: float) -> Array[Dictionary]:
	var route := track.ai_route(2.0)
	for p in route:
		p.speed = speed
	return route

func wall_ahead(track: Circuit, metres: float, lateral := 0.0, angle := 0.0) -> Vector2:
	# Wand quer über die Fahrbahn (8 m breit, 0,6 m dick), optional schräg gedreht.
	track.obstacles.clear()
	track.obstacle_grid.clear()
	var s := metres / track.length
	var c := track.at(s, lateral)
	var t := track.tangent(s).rotated(angle)
	track.add_rect(c, t.orthogonal(), Vector2(4.0, 0.3), 3.0, "mauer")
	for gx in range(-3, 4):
		for gz in range(-3, 4):
			var key := Vector2i(floori(c.x / Circuit.OBSTACLE_CELL) + gx, floori(c.y / Circuit.OBSTACLE_CELL) + gz)
			track.obstacle_grid[key] = [0]
	return c

func run(track: Circuit, speed: float, seconds: float) -> RaceVehicle:
	var v := RaceVehicle.new(track, straight_plan(track, speed))
	v.velocity = Vector2.from_angle(v.heading) * speed
	var max_hit := 0.0
	for tick in range(int(seconds * 60)):
		v.step(1.0 / 60.0, false, float(tick + 1) / 60.0)
		max_hit = maxf(max_hit, v.obstacle_hit)
		if v.crashed:
			break
	v.set_meta("max_hit", max_hit)
	return v

func _init() -> void:
	var city := Circuit.load_track("city")
	check(city.obstacle_source == "layout" and city.obstacles.size() > 150, "Stadt: Hindernisse aus der Diorama-Begleitdatei (%d)" % city.obstacles.size())
	var kinds := {}
	for o in city.obstacles:
		kinds[o.k] = true
	check(kinds.has("mauer") and kinds.has("absperrung") and kinds.has("baum") and kinds.has("auto") and kinds.has("mast"), "Stadt: Häuser, Absperrungen, Bäume, Autos, Masten")
	var azure := Circuit.load_track("azure")
	check(azure.obstacle_source == "layout" and azure.obstacles.size() > 150, "Azure: Hindernisse aus der Diorama-Begleitdatei (%d)" % azure.obstacles.size())
	var azure_kinds := {}
	for o in azure.obstacles:
		azure_kinds[o.k] = true
	check(azure_kinds.has("mauer") and azure_kinds.has("reifen") and azure_kinds.has("auto") and azure_kinds.has("baum"), "Azure: Mauer, Reifenwand, Autos, Palmen")

	# Frontal mit 10 m/s gegen eine Wand: Abprall, kein Durchfahren, kein Totalschaden.
	var t1 := Circuit.load_track("azure")
	var wall := wall_ahead(t1, 20.0)
	var v1 := run(t1, 10.0, 3.0)
	var start := t1.at(0.0)
	check(v1.pos.distance_to(start) < wall.distance_to(start) - 0.9, "Wand: kein Durchfahren (Abstand %.1f m)" % (wall.distance_to(start) - v1.pos.distance_to(start)))
	check(float(v1.get_meta("max_hit")) > 6.0 and not v1.wrecked, "Wand: Aufprall gemeldet (%.1f m/s), kein Totalschaden" % float(v1.get_meta("max_hit")))

	# Schräg (30°) gegen die Wand: das Auto dreht sich.
	var t2 := Circuit.load_track("azure")
	wall_ahead(t2, 20.0, 0.0, 0.5)
	var v2 := RaceVehicle.new(t2, straight_plan(t2, 10.0))
	v2.velocity = Vector2.from_angle(v2.heading) * 10.0
	var max_yaw := 0.0
	for tick in range(150):
		v2.step(1.0 / 60.0, false, float(tick + 1) / 60.0)
		max_yaw = maxf(max_yaw, absf(v2.yaw))
	check(max_yaw > 0.8, "Schräger Treffer dreht das Auto (Gierrate %.2f rad/s)" % max_yaw)

	# Mit 22 m/s frontal: Totalschaden, das Auto bleibt stehen.
	var t3 := Circuit.load_track("azure")
	wall_ahead(t3, 14.0)
	var v3 := run(t3, 22.0, 3.0)
	check(v3.wrecked and v3.crashed, "Mit Vollgas in die Wand: Totalschaden (Aufprall %.1f m/s)" % float(v3.get_meta("max_hit")))

	# Linie führt durch die Wand, langsames Tempo: das Auto bleibt hängen und ist nach einigen Sekunden ein Wrack.
	var t4 := Circuit.load_track("azure")
	wall_ahead(t4, 20.0)
	var v4 := run(t4, 4.0, 14.0)
	check(v4.wrecked, "Festgefahren an der Wand: Rennen verloren")

	# Weiche Absperrung: weniger Rückprall als eine Mauer.
	var t5 := Circuit.load_track("azure")
	wall_ahead(t5, 20.0)
	t5.obstacles[0].k = "absperrung"
	var v5 := run(t5, 10.0, 2.0)
	check(v5.velocity.length() < v1.velocity.length() + 2.0, "Absperrung federt weicher ab")

	# Anliegen statt Aufprall (seit 03.10.2026): Absperrung längs der Fahrbahn ragt 0,25 m in die Linie, das Auto drückt mit Vollgas
	# dagegen. Es schrammt entlang (Reibung ∝ Normalstoß) statt festzukleben und zum Wrack zu werden.
	for kind in ["absperrung", "mauer"]:
		var t7 := Circuit.load_track("azure")
		t7.obstacles.clear()
		t7.obstacle_grid.clear()
		var sm := 25.0 / t7.length
		t7.add_rect(t7.at(sm, 1.0), t7.tangent(sm), Vector2(18.0, 0.3), 1.0, kind)
		for k in range(-6, 7):
			var q := t7.at(sm + k * 3.0 / t7.length, 1.0)
			t7.obstacle_grid[Vector2i(floori(q.x / Circuit.OBSTACLE_CELL), floori(q.y / Circuit.OBSTACLE_CELL))] = [0]
		var v7 := run(t7, 14.0, 3.0)
		check(not v7.wrecked and v7.progress * t7.length > 28.0 and v7.velocity.length() > 8.0,
			"Längs an der %s: schrammt entlang (%.1f m, %.1f m/s, Wrack %s)" % [kind, v7.progress * t7.length, v7.velocity.length(), v7.wrecked])

	# Reproduzierbar: zweimal dieselbe Fahrt ergibt dieselbe Lage.
	var t6 := Circuit.load_track("azure")
	wall_ahead(t6, 20.0, 0.0, 0.5)
	var a := run(t6, 12.0, 4.0)
	var b := run(t6, 12.0, 4.0)
	check(a.pos.is_equal_approx(b.pos) and is_equal_approx(a.heading, b.heading), "Zusammenstoß reproduzierbar")

	# KI fährt die Stadt mit allen Hindernissen ohne Unfall zu Ende.
	var bot := RaceVehicle.new(city, city.ai_route(1.6))
	var hits := 0
	for tick in range(60 * 120):
		bot.step(1.0 / 60.0, false, float(tick + 1) / 60.0)
		if bot.obstacle_hit > 1.0:
			hits += 1
		bot.obstacle_hit = 0.0
		if bot.finish_time >= 0.0 or bot.crashed:
			break
	check(bot.finish_time > 0.0 and not bot.crashed and hits == 0, "KI: Stadt ohne Zusammenstoß im Ziel (%.1f s, %d Stöße)" % [bot.finish_time, hits])
	test_edge_posts()
	print("RESULT: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures > 0 else 0)

# ---------- Randpfosten der Schotterpiste (seit 03.10.2026 Hindernisse der Spielebene, Circuit.edge_posts) ----------
func test_edge_posts() -> void:
	for id in ["quarry", "forest"]:
		var t := Circuit.load_track(id)
		var wood := 0
		var stones := 0
		var same := true
		var worst := 9.0
		var flagged := 0
		for o in t.obstacles:
			if o.has("e"):
				flagged += 1
		for post in t.edge_posts:
			var o: Dictionary = t.obstacles[int(post.o)]
			var stone := bool(post.stone)
			same = same and o.has("e") and Vector2(o.c).is_equal_approx(post.c) and o.has("w") != stone \
				and str(o.k) == ("feldstein" if stone else "pfosten") and is_equal_approx(float(o.b), float(post.y0))
			if stone:
				stones += 1
			else:
				wood += 1
			# Fairness: ein Auto (Kreis CAR_RADIUS), dessen Mitte auf der Fahrbahn bleibt, erreicht keinen Pfosten.
			worst = minf(worst, t.center_distance(post.c, float(post.s)) - float(o.r) - t.hw(float(post.s)) - RaceVehicle.CAR_RADIUS)
		check(wood > 50 and stones > 10 and same and flagged == t.edge_posts.size(),
			"%s: Randpfosten sind Hindernisse der Spielebene (%d Holz, %d Feldsteine, Liste und Hindernisse gleich)" % [id, wood, stones])
		check(worst > 0.0, "%s: Auto mit der Mitte auf der Fahrbahn erreicht keinen Randpfosten (Luft mindestens %.2f m)" % [id, worst])
	check(Circuit.load_track("city").edge_posts.is_empty(), "Asphaltstrecke ohne Randpfosten")

	var q := Circuit.load_track("quarry")
	var post := straight_post(q, false)
	var stone := straight_post(q, true)
	# Kräftiger Stoß (8 m/s frontal): der Holzpfosten bricht, das Auto verliert nur die Bruchenergie und fährt hindurch.
	var fast := push_into(q, post, 8.0, 0.0, 0.4)
	var fast_state: Dictionary = fast.post_state.get(int(post.o), {})
	check(bool(fast_state.get("down", false)) and fast.velocity.length() > 7.0 and fast.obstacle_kind == "pfosten" and not fast.wrecked,
		"Holzpfosten bricht bei 8 m/s, Auto behält %.1f m/s (Bruchenergie ½·%.1f²)" % [fast.velocity.length(), RaceVehicle.POST_BREAK_SPEED])
	# Langsames Drücken (0,5 m/s, Antrieb 1 m/s²): Abprall unter der Bruchgeschwindigkeit, die Stöße summieren sich, dann gibt der Pfosten
	# nach (Belastung über POST_LOAD, nicht Bruch) – kein Festfahren.
	var slow := push_into(q, post, 0.5, 1.0, RaceVehicle.STUCK_TIME)
	var slow_state: Dictionary = slow.post_state.get(int(post.o), {})
	check(slow.obstacle_hit > 0.0 and slow.obstacle_hit < RaceVehicle.POST_BREAK_SPEED and bool(slow_state.get("down", false))
		and float(slow_state.get("load", 0.0)) > RaceVehicle.POST_LOAD and not slow.wrecked,
		"Holzpfosten: langsames Drücken (Stoß %.1f m/s) prallt ab und schiebt ihn dann um (Belastung %.1f)" % [slow.obstacle_hit, float(slow_state.get("load", 0.0))])
	# Feldstein bleibt fest: Abprall, kein Durchfahren.
	var rock := push_into(q, stone, 8.0, 0.0, 1.0)
	var dir := (Vector2(stone.c) - q.at(float(stone.s))).normalized()
	var reach := float(q.obstacles[int(stone.o)].r) + RaceVehicle.CAR_RADIUS
	check(rock.post_state.is_empty() and rock.obstacle_kind == "feldstein" and (rock.pos + Vector2.from_angle(rock.heading) * RaceVehicle.CAR_REACH - Vector2(stone.c)).dot(dir) < -reach + 0.2,
		"Feldstein hält: Abprall (%.1f m/s), kein Durchfahren" % rock.obstacle_hit)
	# Seitlich rutschend mit der Wagenmitte auf den Pfosten (zwischen den beiden Kreisen): der dritte Kreis fängt ihn.
	var side := push_into(q, post, 1.5, 0.0, 2.0, true)
	check(side.obstacle_hit > 0.0 and side.pos.distance_to(post.c) > RaceVehicle.CAR_RADIUS,
		"Pfosten mittig an der Wagenflanke: Berührung (%.1f m/s), kein Durchrutschen (Abstand %.2f m)" % [side.obstacle_hit, side.pos.distance_to(post.c)])
	# Reproduzierbar
	var again := push_into(q, post, 8.0, 0.0, 0.4)
	check(again.pos.is_equal_approx(fast.pos) and again.velocity.is_equal_approx(fast.velocity), "Pfostenbruch reproduzierbar")

	# Ein Rennen teilt den Pfostenzustand (umgefahren für alle), ein Einzelauto (Geist, Test) hat einen eigenen.
	var f := RaceField.new(q)
	f.setup(q.ai_route(2.0), 1)
	check(is_same(f.cars[0].post_state, f.cars[1].post_state) and is_same(f.post_state, f.cars[1].post_state)
		and not is_same(RaceVehicle.new(q, q.ai_route(2.0)).post_state, f.post_state), "Pfostenzustand je Rennen geteilt, Einzelauto eigener")

	# Bild aus derselben Liste: Holzpfosten als MultiMesh-Instanzen am Fuß, Feldsteine als Kegel; umgefahren liegt er, neues Rennen stellt auf.
	var w := Diorama.new()
	w.track = q
	w.build_edge_posts()
	var on_spot := true
	var wood_n := 0
	var stone_n := 0
	for p in q.edge_posts:
		if p.stone:
			stone_n += 1
			continue
		wood_n += 1
		var slot_k := int(w.edge_post_slot.get(int(p.o), -1))
		on_spot = on_spot and slot_k >= 0 and is_same(w.edge_post_wood[slot_k], p) and w.edge_post_tilt[slot_k] == 0.0
	var cones := 0
	for key in w.batches:
		if str(key).begins_with("cone"):
			cones += w.batches[key].transforms.size()
	var pose: Array = Diorama.edge_post_transforms(post, 0.0, Vector2.RIGHT)
	on_spot = on_spot and Transform3D(pose[0]).origin.is_equal_approx(Vector3(post.c.x, float(post.y0) + 0.55, post.c.y))
	check(on_spot and w.edge_post_slot.size() == wood_n and w.edge_post_layers.size() == 2 and w.edge_post_layers[0].instance_count == wood_n and cones == stone_n,
		"Bild = Spielebene: %d Holzpfosten an ihren Plätzen, %d Feldsteine" % [wood_n, cones])
	var knocked := {int(post.o): {"load": 9.0, "down": true, "dir": q.tangent(float(post.s))}}
	w.update_edge_posts(knocked)
	OS.delay_msec(int(Diorama.EDGE_POST_FALL * 1000.0) + 100)
	w.update_edge_posts(knocked)
	var slot := int(w.edge_post_slot[int(post.o)])
	var lying := w.edge_post_tilt[slot]
	var neighbour := w.edge_post_tilt[(slot + 1) % wood_n]
	var fallen: Array = Diorama.edge_post_transforms(post, lying, q.tangent(float(post.s)))
	w.update_edge_posts({})
	check(lying > 1.3 and Transform3D(fallen[0]).basis.y.normalized().dot(Vector3.UP) < 0.3 and neighbour == 0.0 and w.edge_post_tilt[slot] == 0.0,
		"umgefahrener Pfosten liegt im Bild (Neigung %.2f rad), die anderen stehen; neues Rennen stellt ihn wieder auf" % lying)
	w.free()
	# Einfache Grafikstufe mit Diorama-Hindernissen: kein zweiter Klotz an einem Randpfosten.
	var blocks := Diorama.new()
	blocks.track = q
	blocks.build_obstacle_blocks()
	var doubled := 0
	for key in blocks.batches:
		for tf in blocks.batches[key].transforms:
			for p in q.edge_posts:
				if Vector2(tf.origin.x, tf.origin.z).distance_to(p.c) < 0.01:
					doubled += 1
	check(doubled == 0, "einfache Grafikstufe: Randpfosten nicht doppelt als Klotz (%d)" % doubled)
	blocks.free()

func straight_post(track: Circuit, stone: bool) -> Dictionary:
	# Pfosten bzw. Feldstein an einer geraden Stelle (Krümmung klein), Fuß auf Fahrbahnhöhe.
	for p in track.edge_posts:
		if bool(p.stone) == stone and track.curvature(float(p.s)) < 0.01 and absf(float(p.y0) - track.base_height(float(p.s))) < 0.3:
			return p
	return track.edge_posts[0]

func push_into(track: Circuit, post: Dictionary, speed: float, drive: float, seconds: float, sideways := false) -> RaceVehicle:
	# Nur die Stoßrechnung (collide_obstacles) ohne Fahrer: Auto 3 m vor dem Pfosten, fährt senkrecht zur Strecke auf ihn zu (sideways:
	# quer stehend, rutscht mit der Flanke darauf), drive = Antrieb (m/s²) in Fahrtrichtung.
	var v := RaceVehicle.new(track, track.ai_route(2.0))
	var dir := (Vector2(post.c) - track.at(float(post.s))).normalized()
	v.pos = Vector2(post.c) - dir * 3.0
	v.heading = dir.angle() + (PI * 0.5 if sideways else 0.0)
	v.velocity = dir * speed
	v.yaw = 0.0
	v.z = float(post.y0)
	v.progress = float(post.s)
	for tick in range(int(seconds * 60.0)):
		v.velocity += dir * drive / 60.0
		v.pos += v.velocity / 60.0
		v.heading += v.yaw / 60.0
		v.collide_obstacles(1.0 / 60.0)
		if v.wrecked:
			break
	return v
