class_name RaceVehicle
extends RefCounted

# Dynamic bicycle model. World position is integrated ONLY here.
const VERSION := "bicycle-4"
# Fahrer-Regler; gemessen mit tests/tune_controller.gd.
static var LOOK_BASE := 4.0
static var LOOK_GAIN := 0.40
static var YAW_DAMPING := 0.18
static var STEER_RATE := 2.6
# Haftungsfaktor des aktuellen Wetters (1 trocken, 0,85 nass, 0,7 Schnee); setzt main.gd je Rennen.
static var weather_grip := 1.0
const SURFACE_GRIP := {"asphalt": 1.0, "curb": 0.95, "gravel": 0.8, "dirt": 0.65, "mud": 0.5}
const SURFACE_DRAG := {"asphalt": 0.0, "curb": 0.05, "gravel": 0.18, "dirt": 0.55, "mud": 1.1}
const ISLAND_LIMIT := Circuit.HALF_WIDTH + 10.0
# Fahrzeuge der Karriere. grip/power wirken in der Reifen- bzw. Antriebsphysik, offroad teilt die Strafen
# neben der Fahrbahn (2 = halbe Strafe), turbo skaliert Laden und Verbrauchsdauer. unlock = benötigtes Gold.
const CARS := [
	{"id":"sprint","name":"Sprint","grip":12.0,"power":9.0,"offroad":1.0,"turbo":1.0,"color":"f16c4c","style":"coupe","unlock":0,"text":"Leicht & schnell – der Allrounder."},
	{"id":"grip","name":"Grip","grip":13.8,"power":7.8,"offroad":1.0,"turbo":1.0,"color":"5ac4d1","style":"hatch","unlock":1,"text":"Mehr Haftung, sanfterer Antrieb."},
	{"id":"rally","name":"Dirt Hawk","grip":12.6,"power":9.4,"offroad":2.2,"turbo":1.0,"color":"e8c866","style":"rally","unlock":3,"text":"Rallye: kaum Tempoverlust neben der Straße."},
	{"id":"muscle","name":"Thunder V8","grip":11.4,"power":11.2,"offroad":0.9,"turbo":0.85,"color":"a593cf","style":"muscle","unlock":6,"text":"Brachiale Kraft, braucht Gefühl in Kurven."},
	{"id":"gt","name":"Apex GT","grip":14.2,"power":10.6,"offroad":0.9,"turbo":1.3,"color":"ececec","style":"gt","unlock":9,"text":"Die Spitze: Haftung, Kraft, starker Turbo."},
	{"id":"roadster","name":"Col Racer","grip":14.6,"power":9.6,"offroad":1.1,"turbo":1.1,"color":"2e86c1","style":"roadster","unlock":12,"text":"Leicht und wendig – gemacht für Kehren."},
	{"id":"pickup","name":"Quarry Truck","grip":12.4,"power":10.4,"offroad":2.6,"turbo":0.9,"color":"7d8c4a","style":"pickup","unlock":15,"text":"Unverwüstlich auf Schotter und Matsch."},
	{"id":"drift","name":"Drift King","grip":13.0,"power":10.8,"offroad":0.9,"turbo":1.0,"rear":0.36,"color":"d35400","style":"drift","unlock":18,"text":"Leichtes Heck: bricht willig aus – für Drift-Punkte."},
]
var pos := Vector2.ZERO
var velocity := Vector2.ZERO
var heading := 0.0
var yaw := 0.0
var steering := 0.0
var turbo := 0.35
var boosting := false
var braking := 0.0
var slip := 0.0
# Nur für den Motorklang ausgelesen (0 = Schub, 1 = Vollgas); beeinflusst die Simulation nicht.
var throttle := 0.0
# Seitlicher Ausweichversatz des Zielpunkts; setzt main.gd nur für Gegner.
var avoid_offset := 0.0
var progress := 0.0
var previous_phase := 0.0
var finish_time := -1.0
var cursor := 0
var grip := 12.0
var power := 9.0
var offroad := 1.0
var turbo_factor := 1.0
var route: Array[Dictionary] = []
var track: Circuit
var max_slip := 0.0
var rear_share := 0.47     # Anteil der Haftung an der Hinterachse (Drift-Auto: weniger)
# --- Drift-Wertung (nur im Drift-Modus ausgewertet; beeinflusst die Fahrt nicht) ---
var drift_score := 0.0
var drift_multiplier := 1.0
var drift_time := 0.0      # Dauer des aktuellen Drifts
var drift_angle := 0.0     # aktueller Driftwinkel (Grad)
var wall_hits := 0
var wall_contact := false
# --- Höhe und Flug (2,5D, Leitplanke 8) ---
const GRAVITY := 9.81
const LANDING_TIME := 0.35
var z := 0.0              # Höhe über Null (m)
var vz := 0.0             # senkrechte Geschwindigkeit (m/s)
var airborne := false
var landing := 0.0        # Restzeit, in der die Haftung nach der Landung wieder aufgebaut wird
var crashed := false      # abgestürzt (Lücke zu kurz übersprungen, Looping zu langsam, Abgrund)
var air_time := 0.0       # Summe der Flugzeit (für Tests/Anzeige)
var in_loop := false
var loop_theta := 0.0     # Winkel im Looping (0 unten, PI oben)
var loop_speed := 0.0
var loop_radius := 0.0
var loop_origin := Vector2.ZERO    # Punkt der Mittellinie auf Höhe der Einfahrt
var loop_forward := Vector2.RIGHT
var loop_entry := 0.0              # seitlicher Versatz bei der Einfahrt
var loop_fall := false             # im Looping abgestürzt (jenseits der Senkrechten ohne Anpresskraft)
var rolled_back := false           # im Looping vor der Senkrechten stehen geblieben und zurückgerollt

func _init(circuit: Circuit, plan: Array[Dictionary], start_s := 0.0, lane := 0.0, car := 0) -> void:
	track = circuit
	route = plan
	pos = track.at(start_s, lane)
	heading = track.tangent(start_s).angle()
	progress = start_s
	previous_phase = track.phase_near(pos, start_s)
	z = track.ground_height(previous_phase)
	var spec: Dictionary = CARS[clampi(car, 0, CARS.size() - 1)]
	grip = float(spec.grip)
	power = float(spec.power)
	offroad = float(spec.offroad)
	turbo_factor = float(spec.turbo)
	rear_share = float(spec.get("rear", 0.47))

func step(dt: float, boost: bool, time: float) -> void:
	if finish_time >= 0.0 or crashed:
		return
	if in_loop:
		step_loop(dt)
		return
	var before := progress
	var speed := velocity.length()
	# Only search forward through a bounded part of the drawn route.
	while cursor < route.size() - 2 and float(route[cursor + 1].s) <= maxf(progress, 0.0):
		cursor += 1
	# Fahrer-Regler (Pure Pursuit): Zielpunkt = Mittel der Linienpunkte in einem Fenster um den
	# tempoabhängigen Vorausblick. Das filtert Zacken der gezeichneten Linie heraus.
	var lookahead := LOOK_BASE + speed * LOOK_GAIN
	var target_index := cursor
	var ahead_distance := 0.0
	var target_sum := Vector2.ZERO
	var target_count := 0
	while target_index < route.size() - 1 and ahead_distance < lookahead * 1.35:
		# Nicht über eine Looping-Einfahrt hinaus zielen: dahinter liegt die Ausfahrtsspur (seitlich versetzt).
		# Stattdessen geradeaus auf der Einfahrtsspur weiterzielen (gedachte Punkte in Streckenrichtung).
		if not track.loops.is_empty() and not track.loop_between(float(route[target_index].s), float(route[target_index+1].s)).is_empty():
			var last := Vector2(route[target_index].p)
			var dir := track.tangent(float(route[target_index].s))
			var extra := 0.0
			while ahead_distance + extra < lookahead * 1.35:
				extra += 0.5
				if ahead_distance + extra >= lookahead * 0.65:
					target_sum += last + dir * extra
					target_count += 1
			break
		ahead_distance +=Vector2(route[target_index].p).distance_to(route[target_index+1].p)
		target_index += 1
		if ahead_distance >= lookahead * 0.65:
			target_sum += Vector2(route[target_index].p)
			target_count += 1
	var target: Vector2 = target_sum / target_count if target_count > 0 else Vector2(route[target_index].p)
	if absf(avoid_offset) > 0.01:
		# Ausweichen (nur Gegner): Zielpunkt seitlich versetzen statt aufzufahren.
		target += (target - pos).normalized().orthogonal() * avoid_offset
	if progress > track.laps - 0.015:
		target = track.at(progress + 0.025)
	var error := wrapf((target - pos).angle() - heading, -PI, PI)
	var target_distance := maxf(2.3, pos.distance_to(target))
	var desired_steer := atan2(4.6 * sin(clampf(error,-1.4,1.4)), target_distance)
	# Gierdämpfung: dreht das Auto schneller als der Bogen zum Ziel verlangt, wird Lenkung zurückgenommen.
	var expected_yaw := speed * 2.0 * sin(clampf(error,-1.4,1.4)) / target_distance
	desired_steer = clampf(desired_steer + YAW_DAMPING * (expected_yaw - yaw), -0.62, 0.62)
	steering = move_toward(steering, desired_steer, dt * STEER_RATE)
	var desired_speed: float = route[cursor].speed
	# Recover after an actual excursion; this never anticipates future curvature.
	if absf(error)>0.85 or pos.distance_to(route[cursor].p)>3.0:
		desired_speed = minf(desired_speed,7.0)
	var forward := Vector2.from_angle(heading)
	var side := forward.orthogonal()
	var u := velocity.dot(forward)
	var v := velocity.dot(side)
	braking = clampf((u - desired_speed) * 1.6, 0.0, 12.0)
	boosting = boost and turbo > 0.005 and braking < 0.5
	var drive := clampf((desired_speed - u) * 2.2, 0.0, power)
	throttle = drive / power
	if boosting:
		drive += 8.5
		throttle = 1.0
		turbo = maxf(0.0, turbo - dt * 0.30 / turbo_factor)
	elif braking > 0.2 and u > 3.0:
		# Regeneration is proportional to energy actually removed, never time alone.
		turbo = minf(1.0, turbo + braking * u * dt * 0.00065 * turbo_factor)
	# Untergrund: Erde/Matsch bremsen über Rollwiderstand und mindern die Haftung (Leitplanke 3).
	var ground := str(track.surface_at(pos).kind)
	var ground_grip: float = (1.0 - (1.0 - float(SURFACE_GRIP.get(ground, 1.0))) / offroad) * weather_grip
	if landing > 0.0:
		# Nach der Landung baut sich die Haftung erst wieder auf.
		ground_grip *= lerpf(1.0, 0.3, landing / LANDING_TIME)
		landing = maxf(0.0, landing - dt)
	var ground_drag: float = float(SURFACE_DRAG.get(ground, 0.0)) / offroad
	var longitudinal := drive - braking - 0.010 * u * absf(u) - u * (0.09 + ground_drag)
	if not airborne:
		# Steigung/Gefälle (2,5D): Hangabtrieb entlang der Fahrtrichtung.
		var ahead_s := previous_phase + signf(u) * 1.0 / track.length
		var grade := (track.ground_height(ahead_s) - track.ground_height(previous_phase)) * signf(u)
		if absf(grade) < 2.0:
			longitudinal -= GRAVITY * grade / sqrt(1.0 + grade * grade)
	var front_capacity := sqrt(maxf(1.0, pow(grip * ground_grip * (1.0 - rear_share), 2) - pow(longitudinal * 0.52, 2)))
	var rear_capacity := sqrt(maxf(1.0, pow(grip * ground_grip * rear_share, 2) - pow(longitudinal * 0.48, 2)))
	var alpha_front := atan2(v + yaw * 1.1, absf(u) + 1.8) - steering
	var alpha_rear := atan2(v - yaw * 1.2, absf(u) + 1.8)
	var front_force := clampf(-alpha_front * 36.0, -front_capacity, front_capacity)
	var rear_force := clampf(-alpha_rear * 40.0, -rear_capacity, rear_capacity)
	if airborne:
		# In der Luft: keine Reifenkräfte (kein Grip, keine Lenkung, kein Antrieb/Bremsen), nur Luftwiderstand.
		front_force = 0.0
		rear_force = 0.0
		longitudinal = -0.010 * u * absf(u)
		braking = 0.0
		boosting = false
	yaw += ((front_force * 1.1 - rear_force * 1.2) / 1.9 - yaw * 0.55) * dt
	yaw = clampf(yaw, -3.0, 3.0)
	velocity += (forward * longitudinal + side * (front_force + rear_force)) * dt
	heading += yaw * dt
	pos += velocity * dt
	slip = maxf(absf(alpha_front), absf(alpha_rear))
	max_slip = maxf(max_slip, slip)
	# Harte Grenze erst am Inselrand; davor entscheidet der Untergrund.
	if track.center_distance(pos) > ISLAND_LIMIT + track.hw(previous_phase) - Circuit.HALF_WIDTH:
		var q := track.query(pos)
		var normal: Vector2 = (pos - q.point).normalized()
		pos = q.point + normal * (ISLAND_LIMIT + track.hw(previous_phase) - Circuit.HALF_WIDTH)
		var outward := velocity.dot(normal)
		if outward > 0.0:
			velocity -= normal * outward * 1.35
		velocity *= 0.84
	collide_obstacles(dt)
	if track.mode == "drift":
		score_drift(dt)
	var ph := track.phase_near(pos, previous_phase, 0.08)
	var ds := wrapf(ph - previous_phase, -0.5, 0.5)
	if absf(ds) < 0.08:
		progress += ds
	update_height(ph, dt)
	if not airborne and not crashed:
		var loop := track.loop_between(previous_phase, ph)
		if not loop.is_empty():
			enter_loop(loop)
	previous_phase = ph
	var goal := float(track.laps)
	if before < goal and progress >= goal:
		finish_time = time - dt + dt * clampf((goal - before) / maxf(0.00001, progress - before), 0.0, 1.0)

func score_drift(dt: float) -> void:
	# Punkte = Driftwinkel (Grad) × Tempo × Zeit × Multiplikator. Der Multiplikator wächst mit der Dauer eines
	# durchgehenden Drifts (bis ×4). Berührt das Auto die Fahrbahnbegrenzung, sind 60 Punkte weg und der
	# Multiplikator fällt auf 1 zurück.
	var speed := velocity.length()
	var angle := 0.0
	if speed > 1.0:
		angle = absf(wrapf(velocity.angle() - heading, -PI, PI))
	drift_angle = rad_to_deg(angle)
	if not airborne and speed > 6.0 and angle > deg_to_rad(12.0) and angle < deg_to_rad(75.0):
		drift_time += dt
		drift_multiplier = minf(4.0, 1.0 + drift_time * 0.6)
		drift_score += drift_angle * speed * dt * 0.25 * drift_multiplier
	else:
		drift_time = maxf(0.0, drift_time - dt * 3.0)
		if drift_time <= 0.0:
			drift_multiplier = 1.0
	var q := track.query(pos)
	var touching := float(q.distance) > track.hw(float(q.s)) - 0.5
	if touching and not wall_contact:
		wall_hits += 1
		drift_score = maxf(0.0, drift_score - 60.0)
		drift_multiplier = 1.0
		drift_time = 0.0
	wall_contact = touching

func update_height(ph: float, dt: float) -> void:
	# Senkrechte Bewegung: am Boden folgt z der Fahrbahn; fällt der Boden schneller weg als der freie Fall
	# (Schanzenkante, Kuppe, Lücke), hebt das Auto mit seiner senkrechten Geschwindigkeit ab.
	var ground := track.ground_height(ph)
	if not airborne and not in_loop and edge_check(ph, ground):
		return
	if airborne:
		vz -= GRAVITY * dt
		z += vz * dt
		air_time += dt
		if z <= ground:
			airborne = false
			landing = LANDING_TIME
			# Harte Landung kostet etwas Tempo.
			velocity *= clampf(1.0 + vz * 0.01, 0.85, 1.0)
			z = ground
			vz = 0.0
		elif z < track.base_height(ph) - 3.0:
			crashed = true
		return
	var follow := (ground - z) / dt
	# Abheben nur, wenn der Boden deutlich (> 5 cm) unter die Flugbahn wegfällt; kleinere Knicke schluckt die Federung.
	var ballistic := z + vz * dt - 0.5 * GRAVITY * dt * dt
	if ground < ballistic - 0.05:
		airborne = true
		vz -= GRAVITY * dt
		z += vz * dt
		return
	# Steigrate begrenzen: Sprünge im Höhenprofil dürfen das Auto nicht katapultieren.
	vz = clampf(follow, -25.0, 25.0)
	z = ground

var fall_speed := 0.0      # nur Darstellung: Absturz ins Tal / von der Brücke

func edge_check(ph: float, road: float) -> bool:
	# Neben der Fahrbahn fällt das Gelände steil ab (Brücke, Bergstraße, Steilküste)?
	# Mit Leitplanke: Abprallen, ab BREAK_SPEED senkrecht zur Planke bricht sie -> Absturz. Ohne: Absturz.
	var q := track.query(pos)
	var distance := float(q.distance)
	var edge := track.hw(float(q.s)) + 0.7
	if distance <= edge:
		return false
	var drop := road - track.terrain_height(pos)
	if drop < 2.5:
		return false
	var normal: Vector2 = (pos - Vector2(q.point)).normalized()
	var t := track.tangent(float(q.s))
	var side := normal.dot(Vector2(-t.y, t.x))
	var impact := velocity.dot(normal)
	if track.guardrail_at(float(q.s), side) and impact < Circuit.BREAK_SPEED:
		pos = Vector2(q.point) + normal * edge
		if impact > 0.0:
			velocity -= normal * impact * 1.4
		velocity *= 0.8
		guard_hit = impact
		return false
	crashed = true
	broke_rail = track.guardrail_at(float(q.s), side)
	return true

var guard_hit := 0.0       # Aufprallgeschwindigkeit an der Leitplanke (Funken/Geräusch), vom Aufrufer zurückgesetzt
var broke_rail := false

func enter_loop(loop: Dictionary) -> void:
	in_loop = true
	loop_theta = 0.0
	loop_radius = float(loop.radius)
	loop_forward = track.tangent(float(loop.s))
	loop_speed = maxf(0.0, velocity.dot(loop_forward))
	var center := track.at(float(loop.s))
	var side := Vector2(-loop_forward.y, loop_forward.x)
	loop_entry = clampf((pos - center).dot(side), -Circuit.HALF_WIDTH, Circuit.HALF_WIDTH)
	loop_origin = center + loop_forward * (pos - center).dot(loop_forward)
	heading = loop_forward.angle()

func step_loop(dt: float) -> void:
	# Autonome Durchfahrt mit dem Schwung: tangentiale Verzögerung durch Schwerkraft und Luftwiderstand.
	# Vor der Senkrechten (θ < 90°) drückt die Bahn immer an: reicht der Schwung nicht, rollt das Auto rückwärts
	# wieder hinunter. Jenseits davon fällt es ab, sobald die Anpresskraft (v²/R + g·cos θ) fehlt.
	loop_speed += (-GRAVITY * sin(loop_theta) - 0.010 * loop_speed * absf(loop_speed)) * dt
	loop_theta += loop_speed / loop_radius * dt
	var normal := loop_speed * loop_speed / loop_radius + GRAVITY * cos(loop_theta)
	if loop_theta > PI * 0.5 and (normal < 0.0 or loop_speed < 0.5):
		crashed = true
		in_loop = false
		loop_fall = true
		return
	if loop_theta <= 0.0:
		# Rückwärts aus der Einfahrt gerollt: ausgeschieden, das Auto bleibt unten stehen.
		in_loop = false
		crashed = true
		rolled_back = true
		loop_theta = 0.0
		pos = loop_origin + Vector2(-loop_forward.y, loop_forward.x) * track.loop_lateral(0.0, loop_entry)
		z = track.ground_height(previous_phase)
		velocity = Vector2.ZERO
		return
	var forward := loop_forward
	var side := Vector2(-forward.y, forward.x)
	pos = loop_origin + forward * loop_radius * sin(loop_theta) + side * track.loop_lateral(loop_theta, loop_entry)
	z = track.base_height(previous_phase) + loop_radius * (1.0 - cos(loop_theta))
	if loop_theta >= TAU:
		in_loop = false
		pos = loop_origin - side * Circuit.LOOP_LANE
		z = track.ground_height(previous_phase)
		velocity = forward * loop_speed
		yaw = 0.0

static func update_avoidance(cars: Array, dt: float) -> void:
	# Gegner (Index > 0) weichen Autos aus, die schräg vor oder neben ihnen fahren.
	for i in range(1, cars.size()):
		var me: RaceVehicle = cars[i]
		var goal := 0.0
		var forward := Vector2.from_angle(me.heading)
		for j in range(cars.size()):
			if j == i or cars[j].finish_time >= 0.0:
				continue
			var d: Vector2 = cars[j].pos - me.pos
			var ahead := d.dot(forward)
			var side := d.dot(forward.orthogonal())
			if ahead > -0.6 and ahead < 4.5 and absf(side) < 1.9:
				goal = -signf(side if absf(side) > 0.05 else 1.0) * 1.7
		me.avoid_offset = move_toward(me.avoid_offset, goal, dt * 3.0)

static func resolve_contact(a: RaceVehicle, b: RaceVehicle) -> float:
	# Rückgabe: Aufprallgeschwindigkeit (m/s) für Funken/Geräusch; 0 = keine Berührung. Nur Information,
	# die Simulation selbst bleibt unverändert.
	var delta := b.pos - a.pos
	var dist := delta.length()
	if dist > 1.15 or dist < 0.001:
		return 0.0
	if absf(a.z - b.z) > 1.0 or a.crashed or b.crashed or a.in_loop or b.in_loop:
		return 0.0   # übereinander (Sprung über die Kreuzung, Looping) oder ausgeschieden: keine Berührung
	var normal := delta / dist
	var overlap := (1.15 - dist) * 0.5
	a.pos -= normal * overlap
	b.pos += normal * overlap
	var closing := (b.velocity - a.velocity).dot(normal)
	if closing < 0.0:
		var impulse := -closing * 0.65
		a.velocity -= normal * impulse
		b.velocity += normal * impulse
		return -closing
	return 0.0

# ---------- Zusammenstoß mit Hindernissen (Häuser, Absperrungen, Laternen, Bäume, parkende Autos …) ----------
# Das Auto ist zwei Kreise (vorn, hinten). Der Stoß wirkt an der Berührstelle: Abprall entlang der Normalen (Rückprall je nach
# Art), Reibung quer dazu und ein Drehimpuls um die Hochachse – schräge Treffer drehen das Auto. Bleibt das Auto an einem
# Hindernis hängen (die Linie führt hindurch), ist es nach STUCK_TIME ein Wrack: das Rennen ist dann verloren.
const CAR_REACH := 1.25
const CAR_RADIUS := 0.95
const CAR_INERTIA := 1.8
const STUCK_TIME := 3.0
const WRECK_SPEED := 17.0      # m/s senkrecht in eine Wand oder ein Auto: Totalschaden
var obstacle_hit := 0.0         # stärkster Aufprall (m/s) seit dem letzten Abholen, für Geräusch/Funken (Aufrufer setzt zurück)
var obstacle_kind := ""
var stuck := 0.0
var stuck_from := 0.0
var last_touch := 9.0
var wrecked := false

func collide_obstacles(dt: float) -> void:
	if track.obstacles.is_empty():
		return
	var forward := Vector2.from_angle(heading)
	var touching := false
	for off in [CAR_REACH, -CAR_REACH]:
		var c: Vector2 = pos + forward * off
		for idx in track.obstacles_near(c):
			var o: Dictionary = track.obstacles[idx]
			if airborne and z > float(o.y):
				continue
			var hit := track.obstacle_contact(o, c, CAR_RADIUS)
			if hit.z <= 0.0:
				continue
			touching = true
			var n := Vector2(hit.x, hit.y)
			pos += n * hit.z
			c += n * hit.z
			var r := c - pos
			var vc := velocity + Vector2(-r.y, r.x) * yaw
			var vn := vc.dot(n)
			if vn >= 0.0:
				continue
			var soft: bool = str(o.k) in Circuit.SOFT_OBSTACLES
			var e := 0.12 if soft else 0.3
			var rn := r.x * n.y - r.y * n.x
			var j := -(1.0 + e) * vn / (1.0 + rn * rn / CAR_INERTIA)
			velocity += n * j
			yaw = clampf(yaw + rn * j / CAR_INERTIA, -3.0, 3.0)
			var t := Vector2(-n.y, n.x)
			velocity -= t * vc.dot(t) * (0.35 if soft else 0.22)
			if soft:
				velocity *= 0.9
			if -vn > obstacle_hit:
				obstacle_hit = -vn
				obstacle_kind = str(o.k)
			if not soft and -vn > WRECK_SPEED and str(o.k) in ["mauer", "auto"]:
				wreck()
				return
	# Festgefahren: berührt (oder eben noch berührt) und kaum Fortschritt entlang der Strecke.
	last_touch = 0.0 if touching else last_touch + dt
	if last_touch < 0.6:
		if stuck == 0.0:
			stuck_from = progress
		stuck += dt
		if (progress - stuck_from) * track.length > 2.0:
			stuck = 0.0
		elif stuck > STUCK_TIME:
			wreck()
	else:
		stuck = 0.0

func wreck() -> void:
	# Totalschaden bzw. festgefahren: das Auto bleibt stehen (kein Absturz aus dem Bild).
	crashed = true
	wrecked = true
	velocity = Vector2.ZERO
	yaw = 0.0
