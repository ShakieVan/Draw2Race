class_name Seesaw
extends RefCounted

# Wippe (Lineal auf einem Stift, Kinderzimmer): erstes bewegtes Element der Spielebene. Ein Freiheitsgrad φ (Neigung,
# + = Ausfahrtsende oben), Winkelgeschwindigkeit ω; beides ist Simulationszustand und wird im 60-Hz-Takt vor den Fahrzeugen
# geschritten (RaceField). Achse a vom Drehpunkt (+ Richtung Ausfahrt), quer b. Deck-Oberseite y(a) = pivot_h + a·sin φ;
# Anschläge ±Θ mit Θ = asin(pivot_h / (length/2)) – das tiefe Ende liegt auf dem Boden. Ruhelage: Einfahrt unten (φ = +Θ),
# gehalten vom Gegengewicht bias (Ungleichgewicht in „Auto-Metern“ am Einfahrtsende).
# Bewegung: φ̈ = g·cos φ·(bias − Σaᵢ)/(inertia + Σaᵢ²) − damping·φ̇, halbimplizit; Anschlag mit Rückprall restitution.
# Last = jedes Auto am Boden (nicht im Flug, nicht ausgeschieden, nicht im Ziel) in der Grundfläche mit |z − y(a)| < LOAD_TOL.
# Streckendatei "seesaws": [{shortcut, at (Pfadmeter des Drehpunkts), length, width, thickness, pivot_h, inertia, bias, damping,
# restitution, rail, edge_ok, edge_wreck, decide, ai}] (docs/dioramen/HOEHEN_PLAN.md, A3).
const G := 9.81
const LOAD_TOL := 0.35        # Auto zählt als Last, wenn es so nah an der Deckhöhe steht
const REST_OMEGA := 0.05      # darunter bleibt die Wippe am Anschlag liegen
const T_RETURN := 1.7         # KI-Schätzung: Sekunden vom Verlassen des Lineals, bis die Einfahrtskante wieder unten ist
var spec := {}
var c := Vector2.ZERO         # Drehpunkt (Draufsicht)
var u := Vector2.RIGHT        # Achse Richtung Ausfahrt
var half_len := 12.0
var half_w := 2.0
var thickness := 0.3
var pivot_h := 1.1
var bias := 1.0
var inertia := 26.0
var damping := 0.4
var restitution := 0.2
var rail := 0.8
var edge_ok := 0.35
var edge_wreck := 0.6
var decide := -1.0
var ai := true
var shortcut := -1
var theta := 0.0              # Endanschlag |φ|
var phi := 0.0
var omega := 0.0
var prev_phi := 0.0           # φ des Vortakts (nur Darstellung: Zwischenbilder)
var load_count := 0
var clack := 0.0              # Aufprall-Winkelgeschwindigkeit am Anschlag im letzten Takt (nur Ton)

func _init(center: Vector2, axis: Vector2, d := {}) -> void:
	spec = d
	c = center
	u = axis.normalized()
	half_len = float(d.get("length", 24.0)) * 0.5
	half_w = float(d.get("width", 4.0)) * 0.5
	thickness = float(d.get("thickness", 0.3))
	pivot_h = float(d.get("pivot_h", 1.1))
	bias = float(d.get("bias", 1.0))
	inertia = float(d.get("inertia", 0.045 * pow(half_len * 2.0, 2)))
	damping = float(d.get("damping", 0.4))
	restitution = float(d.get("restitution", 0.2))
	rail = float(d.get("rail", 0.8))
	edge_ok = float(d.get("edge_ok", 0.35))
	edge_wreck = float(d.get("edge_wreck", 0.6))
	decide = float(d.get("decide", -1.0))
	ai = bool(d.get("ai", true))
	shortcut = int(d.get("shortcut", -1))
	theta = asin(clampf(pivot_h / half_len, 0.0, 1.0))
	phi = theta
	prev_phi = phi

static func from_track(track: Circuit) -> Array:
	# Wippen der Strecke in Ruhelage (je Rennen und für den Geist neu).
	var out: Array = []
	for d in track.seesaws:
		var k := int(d.get("shortcut", 0))
		if k < 0 or k >= track.shortcuts.size():
			push_error("Wippe ohne gültige Abkürzung (shortcut %d)" % k)
			continue
		var pose := track.path_pose(k, float(d.get("at", 0.0)))
		out.append(Seesaw.new(pose[0], pose[1], d))
	return out

func local(p: Vector2) -> Vector2:
	var r := p - c
	return Vector2(r.dot(u), r.dot(Vector2(-u.y, u.x)))

func world(a: float, b := 0.0) -> Vector2:
	return c + u * a + Vector2(-u.y, u.x) * b

func inside(p: Vector2, margin := 0.0) -> bool:
	var l := local(p)
	return absf(l.x) <= half_len + margin and absf(l.y) <= half_w + margin

func deck_y(a: float) -> float:
	return pivot_h + clampf(a, -half_len, half_len) * sin(phi)

func deck_vy(a: float) -> float:
	return clampf(a, -half_len, half_len) * cos(phi) * omega

func rest_y(a: float) -> float:
	# Deckhöhe in Ruhelage (Zeichnen: die Linie liegt auf der Ruhelage).
	return pivot_h + clampf(a, -half_len, half_len) * sin(theta)

func end_height(sign_: float) -> float:
	return deck_y(sign_ * half_len)

func entry_edge() -> float:
	return end_height(-1.0)

func is_load(car) -> bool:
	if car == null or car.crashed or car.airborne or car.in_loop or car.finish_time >= 0.0:
		return false
	var l := local(car.pos)
	return absf(l.x) <= half_len and absf(l.y) <= half_w and absf(car.z - deck_y(l.x)) < LOAD_TOL

func step(dt: float, cars: Array) -> void:
	prev_phi = phi
	var s1 := 0.0
	var s2 := 0.0
	load_count = 0
	for car in cars:
		if not is_load(car):
			continue
		var a: float = local(car.pos).x
		s1 += a
		s2 += a * a
		load_count += 1
	integrate(dt, s1, s2)

func integrate(dt: float, s1: float, s2: float) -> void:
	var acc := G * cos(phi) * (bias - s1) / (inertia + s2) - damping * omega
	omega += acc * dt
	phi += omega * dt
	clack = 0.0
	if phi >= theta:
		phi = theta
		if omega > 0.0:
			clack = omega
			omega = -omega * restitution if omega > REST_OMEGA else 0.0
	elif phi <= -theta:
		phi = -theta
		if omega < 0.0:
			clack = -omega
			omega = -omega * restitution if omega < -REST_OMEGA else 0.0

func predict_free(dt := 1.0 / 60.0, limit := 6.0) -> float:
	# Vorwärtsrechnung ohne Last aus dem jetzigen Zustand: Zeit, ab der die Einfahrtskante dauerhaft unter 60 % von edge_ok liegt.
	var keep_phi := phi
	var keep_omega := omega
	var keep_clack := clack
	var t := 0.0
	var last_bad := 0.0
	while t < limit:
		if entry_edge() > edge_ok * 0.6:
			last_bad = t + dt
		integrate(dt, 0.0, 0.0)
		t += dt
	phi = keep_phi
	omega = keep_omega
	clack = keep_clack
	return last_bad if last_bad < limit else limit

func state() -> Array:
	return [phi, omega]
