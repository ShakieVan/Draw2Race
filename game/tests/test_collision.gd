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
	check(azure.obstacle_source == "props" and azure.obstacles.size() > 20, "Azure: Hindernisse aus den Bausteinen (%d)" % azure.obstacles.size())

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
	print("RESULT: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures > 0 else 0)
