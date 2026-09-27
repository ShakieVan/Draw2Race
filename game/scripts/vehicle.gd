class_name RaceVehicle
extends RefCounted

# Dynamic bicycle model. World position is integrated ONLY here.
const VERSION := "bicycle-3"
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

func _init(circuit: Circuit, plan: Array[Dictionary], start_s := 0.0, lane := 0.0, car := 0) -> void:
	track = circuit
	route = plan
	pos = track.at(start_s, lane)
	heading = track.tangent(start_s).angle()
	progress = start_s
	previous_phase = track.phase_near(pos, start_s)
	var spec: Dictionary = CARS[clampi(car, 0, CARS.size() - 1)]
	grip = float(spec.grip)
	power = float(spec.power)
	offroad = float(spec.offroad)
	turbo_factor = float(spec.turbo)

func step(dt: float, boost: bool, time: float) -> void:
	if finish_time >= 0.0:
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
		ahead_distance += Vector2(route[target_index].p).distance_to(route[target_index+1].p)
		target_index += 1
		if ahead_distance >= lookahead * 0.65:
			target_sum += Vector2(route[target_index].p)
			target_count += 1
	var target: Vector2 = target_sum / target_count if target_count > 0 else Vector2(route[target_index].p)
	if absf(avoid_offset) > 0.01:
		# Ausweichen (nur Gegner): Zielpunkt seitlich versetzen statt aufzufahren.
		target += (target - pos).normalized().orthogonal() * avoid_offset
	if progress > 1.985:
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
	var ground_drag: float = float(SURFACE_DRAG.get(ground, 0.0)) / offroad
	var longitudinal := drive - braking - 0.010 * u * absf(u) - u * (0.09 + ground_drag)
	var front_capacity := sqrt(maxf(1.0, pow(grip * ground_grip * 0.53, 2) - pow(longitudinal * 0.52, 2)))
	var rear_capacity := sqrt(maxf(1.0, pow(grip * ground_grip * 0.47, 2) - pow(longitudinal * 0.48, 2)))
	var alpha_front := atan2(v + yaw * 1.1, absf(u) + 1.8) - steering
	var alpha_rear := atan2(v - yaw * 1.2, absf(u) + 1.8)
	var front_force := clampf(-alpha_front * 36.0, -front_capacity, front_capacity)
	var rear_force := clampf(-alpha_rear * 40.0, -rear_capacity, rear_capacity)
	yaw += ((front_force * 1.1 - rear_force * 1.2) / 1.9 - yaw * 0.55) * dt
	yaw = clampf(yaw, -3.0, 3.0)
	velocity += (forward * longitudinal + side * (front_force + rear_force)) * dt
	heading += yaw * dt
	pos += velocity * dt
	slip = maxf(absf(alpha_front), absf(alpha_rear))
	max_slip = maxf(max_slip, slip)
	# Harte Grenze erst am Inselrand; davor entscheidet der Untergrund.
	if track.center_distance(pos) > ISLAND_LIMIT:
		var q := track.query(pos)
		var normal: Vector2 = (pos - q.point).normalized()
		pos = q.point + normal * ISLAND_LIMIT
		var outward := velocity.dot(normal)
		if outward > 0.0:
			velocity -= normal * outward * 1.35
		velocity *= 0.84
	var ph := track.phase_near(pos, previous_phase, 0.08)
	var ds := wrapf(ph - previous_phase, -0.5, 0.5)
	if absf(ds) < 0.08:
		progress += ds
	previous_phase = ph
	if before < 2.0 and progress >= 2.0:
		finish_time = time - dt + dt * clampf((2.0 - before) / maxf(0.00001, progress - before), 0.0, 1.0)

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

static func resolve_contact(a: RaceVehicle, b: RaceVehicle) -> void:
	var delta := b.pos - a.pos
	var dist := delta.length()
	if dist > 1.15 or dist < 0.001:
		return
	var normal := delta / dist
	var overlap := (1.15 - dist) * 0.5
	a.pos -= normal * overlap
	b.pos += normal * overlap
	var closing := (b.velocity - a.velocity).dot(normal)
	if closing < 0.0:
		var impulse := -closing * 0.65
		a.velocity -= normal * impulse
		b.velocity += normal * impulse
