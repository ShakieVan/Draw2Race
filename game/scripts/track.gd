class_name Circuit
extends RefCounted

# Strecke aus einer Streckendatei (game/tracks/<id>.json, Format 1; Erzeuger: tools/make_tracks.py).
# Die Mittellinie wird per Catmull-Rom geglättet und gleichmäßig abgetastet. s ist der Streckenanteil
# (0..1, darüber = weitere Runden), s=0 ist Start/Ziel. Positiver Seitenversatz = links vom Tangentenvektor
# gedreht (-t.y, t.x). Die Simulation bleibt eben (Leitplanke 8).
const HALF_WIDTH := 3.5
const STEP := 0.5
const GRID := 4.0
const GRID_REACH := HALF_WIDTH + 14.0
const DEFAULT_TRACK := "res://tracks/azure.json"

var id := ""
var name := ""
var subtitle := ""
var theme := "coast"
var road := "asphalt"
var props: Array = []
var surfaces: Array = []
var conditions: Array = []
var points: Array[Vector2] = []
var tangents: Array[Vector2] = []
var curvatures := PackedFloat32Array()
var length := 0.0
var bounds := Rect2()
var grid := {}

func _init(path := DEFAULT_TRACK) -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		push_error("Streckendatei fehlt oder ist ungültig: " + path)
		return
	id = str(data.get("id", "track"))
	name = str(data.get("name", id))
	subtitle = str(data.get("subtitle", ""))
	theme = str(data.get("theme", "coast"))
	road = str(data.get("road", "asphalt"))
	props = data.get("props", [])
	surfaces = data.get("surfaces", [])
	conditions = data.get("conditions", [])
	var control: Array[Vector2] = []
	for p in data.points:
		control.append(Vector2(float(p[0]), float(p[1])))
	build(control)

static func load_track(track_id: String) -> Circuit:
	return Circuit.new("res://tracks/%s.json" % track_id)

func build(control: Array[Vector2]) -> void:
	# 1. Catmull-Rom-Glättung (geschlossen), 2. gleichmäßige Abtastung im Abstand STEP.
	var fine: Array[Vector2] = []
	var n := control.size()
	for i in range(n):
		var p0 := control[(i - 1 + n) % n]
		var p1 := control[i]
		var p2 := control[(i + 1) % n]
		var p3 := control[(i + 2) % n]
		var sub := maxi(2, ceili(p1.distance_to(p2) / 0.25))
		for k in range(sub):
			var t := float(k) / sub
			fine.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
				+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t))
	var cum := PackedFloat32Array([0.0])
	for i in range(1, fine.size() + 1):
		cum.append(cum[i - 1] + fine[i - 1].distance_to(fine[i % fine.size()]))
	var total := cum[-1]
	var count := maxi(16, int(round(total / STEP)))
	points.clear()
	var j := 0
	for k in range(count):
		var d := total * k / count
		while cum[j + 1] < d:
			j += 1
		var f := (d - cum[j]) / maxf(1e-6, cum[j + 1] - cum[j])
		points.append(fine[j].lerp(fine[(j + 1) % fine.size()], f))
	length = total
	tangents.clear()
	for i in range(count):
		tangents.append((points[(i + 1) % count] - points[(i - 1 + count) % count]).normalized())
	# Krümmung aus Richtungsänderung, über ±2 m geglättet.
	var raw := PackedFloat32Array()
	for i in range(count):
		raw.append(absf(tangents[(i + 1) % count].angle_to(tangents[(i - 1 + count) % count])) / (2.0 * length / count))
	curvatures.clear()
	var win := int(2.0 / (length / count))
	for i in range(count):
		var acc := 0.0
		for k in range(-win, win + 1):
			acc += raw[(i + k + count) % count]
		curvatures.append(acc / (2 * win + 1))
	bounds = Rect2(points[0], Vector2.ZERO)
	for p in points:
		bounds = bounds.expand(p)
	build_grid()

func build_grid() -> void:
	grid.clear()
	var count := points.size()
	for i in range(count):
		var a := points[i]
		var b := points[(i + 1) % count]
		var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * GRID_REACH
		var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * GRID_REACH
		for gx in range(floori(lo.x / GRID), floori(hi.x / GRID) + 1):
			for gz in range(floori(lo.y / GRID), floori(hi.y / GRID) + 1):
				var key := Vector2i(gx, gz)
				if not grid.has(key):
					grid[key] = PackedInt32Array()
				grid[key].append(i)

func candidates(p: Vector2) -> PackedInt32Array:
	var key := Vector2i(floori(p.x / GRID), floori(p.y / GRID))
	return grid.get(key, PackedInt32Array())

func index_s(i: int) -> float:
	return float(i) / points.size()

func at(s: float, offset := 0.0) -> Vector2:
	var count := points.size()
	var f := fposmod(s, 1.0) * count
	var i := int(f) % count
	var frac := f - floorf(f)
	var p := points[i].lerp(points[(i + 1) % count], frac)
	var t := tangent(s)
	return p + Vector2(-t.y, t.x) * offset

func tangent(s: float) -> Vector2:
	var count := points.size()
	var f := fposmod(s, 1.0) * count
	var i := int(f) % count
	return tangents[i].lerp(tangents[(i + 1) % count], f - floorf(f)).normalized()

func curvature(s: float) -> float:
	var count := points.size()
	return curvatures[int(fposmod(s, 1.0) * count) % count]

func nearest(p: Vector2, indices) -> Dictionary:
	var count := points.size()
	var best := INF
	var near := Vector2.ZERO
	var index := 0
	var frac := 0.0
	for i in indices:
		var a := points[i]
		var b := points[(i + 1) % count]
		var q := Geometry2D.get_closest_point_to_segment(p, a, b)
		var d := p.distance_squared_to(q)
		if d < best:
			best = d
			near = q
			index = i
			frac = a.distance_to(q) / maxf(1e-6, a.distance_to(b))
	return {"distance": sqrt(best), "point": near, "index": index, "s": fposmod((index + frac) / count, 1.0)}

func query(p: Vector2) -> Dictionary:
	var c := candidates(p)
	return nearest(p, c if not c.is_empty() else range(points.size()))

func phase(p: Vector2) -> float:
	return float(query(p).s)

func phase_near(p: Vector2, hint: float, window := 0.12) -> float:
	# Lokale Projektion um den bisherigen Streckenanteil: an Kreuzungen (Acht) kein Sprung auf den anderen Ast.
	var count := points.size()
	var center := int(fposmod(hint, 1.0) * count)
	var reach := int(window * count)
	var indices := PackedInt32Array()
	for k in range(-reach, reach + 1):
		indices.append((center + k + count) % count)
	return float(nearest(p, indices).s)

func center_distance(p: Vector2) -> float:
	return float(query(p).distance)

func other_branch_distance(p: Vector2, s: float, gap := 0.12) -> float:
	# Abstand zu Streckenteilen, die im Streckenverlauf weit entfernt sind (Kreuzung der Acht).
	var count := points.size()
	var best := INF
	for i in candidates(p):
		var ds := absf(wrapf(index_s(i) - fposmod(s, 1.0), -0.5, 0.5))
		if ds > gap:
			best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, points[i], points[(i + 1) % count])))
	return best

func inside(p: Vector2, margin := 0.0) -> bool:
	return center_distance(p) <= HALF_WIDTH + margin

func surface_at(p: Vector2) -> Dictionary:
	var q := query(p)
	var distance := float(q.distance)
	if distance<=HALF_WIDTH:
		return {"kind":road,"height":0.207}
	if distance<4.05:
		# Schotterpisten haben keine Randsteine, dort beginnt direkt der Waldboden.
		return {"kind":"curb","height":0.295} if road == "asphalt" else {"kind":"dirt","height":0.16}
	var s := float(q.s)
	var t := tangent(s)
	var side := (p - Vector2(q.point)).dot(Vector2(-t.y, t.x))
	for zone in surfaces:
		var inside_zone: bool = s >= float(zone.from) and s <= float(zone.to)
		var side_ok: bool = zone.side == "both" or (zone.side == "outer") == (side > 0.0)
		if inside_zone and side_ok and distance <= 4.9:
			return {"kind":str(zone.kind),"height":0.147}
	return {"kind":"dirt","height":0.137 if distance<=4.9 else 0.105}

func valid_segment(a: Vector2, b: Vector2) -> bool:
	if a.distance_to(b) > 13.0:
		return false
	var count := maxi(1, ceili(a.distance_to(b) / 0.45))
	for i in range(count + 1):
		if not inside(a.lerp(b, float(i) / count)):
			return false
	return true

func conditions_for(stage: int) -> Dictionary:
	# Feste Bedingungen je Herausforderung (Tageszeit, Wetter, Nebel); Standard: Tag, trocken.
	if stage >= 0 and stage < conditions.size():
		return {"time": str(conditions[stage].get("time","day")), "weather": str(conditions[stage].get("weather","dry")),
			"fog": int(conditions[stage].get("fog",0))}
	return {"time": "day", "weather": "dry", "fog": 0}

func corner_factor(s: float) -> float:
	# 0 auf Geraden, 1 in engen Kurven (Radius <= 13 m); nur für Messwerkzeuge.
	return clampf(curvature(s) * 13.0, 0.0, 1.0)

func ai_route(skill := 0.0, lane := 0.0) -> Array[Dictionary]:
	# Tempoprofil aus der Krümmung: Kurventempo über die zulässige Querbeschleunigung, davor
	# rechtzeitig bremsen (Rückwärtsdurchlauf). skill 0 = vorsichtig, 3 = gemessenes Optimum (mehr überzieht).
	# Haftung des Fahrbahnbelags (Schotter) senkt das mögliche Kurventempo.
	var road_grip: float = RaceVehicle.SURFACE_GRIP.get(road, 1.0) * RaceVehicle.weather_grip
	var lateral := (6.0 + skill * 1.6) * road_grip
	var top := 15.0 + skill * 1.3
	var brake := 6.0 + skill * 1.0
	var count := points.size() * 2
	var speeds := PackedFloat32Array()
	for i in range(count):
		var s := float(i) / points.size()
		var k := maxf(curvature(s), 0.0005)
		# Außen-/Innenspur ändern den Radius (Versatz relativ zur Kurvenrichtung wird näherungsweise ignoriert).
		speeds.append(minf(top, sqrt(lateral / k)))
	var ds := length / points.size()
	for _round in range(2):
		for i in range(count - 2, -1, -1):
			speeds[i] = minf(speeds[i], sqrt(speeds[i + 1] * speeds[i + 1] + 2.0 * brake * ds))
		speeds[count - 1] = minf(speeds[count - 1], speeds[0])
	var route: Array[Dictionary] = []
	for i in range(count + 1):
		var s := float(i) / points.size()
		route.append({"p": at(s, lane), "speed": speeds[mini(i, count - 1)], "s": s})
	return route
