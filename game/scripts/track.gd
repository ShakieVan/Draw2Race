class_name Circuit
extends RefCounted

# Strecke aus einer Streckendatei (game/tracks/<id>.json, Format 1; Erzeuger: tools/make_tracks.py).
# Die Mittellinie wird per Catmull-Rom geglättet und gleichmäßig abgetastet. s ist der Streckenanteil
# (0..1, darüber = weitere Runden), s=0 ist Start/Ziel. Positiver Seitenversatz = links vom Tangentenvektor
# gedreht (-t.y, t.x). Fahrdynamik in der Ebene plus Höhe (Leitplanke 8, „2,5D“): optionale Felder
#   "elevation": [[s, Höhe m], ...]  Höhenprofil der Mittellinie (linear, geschlossen)
#   "ramps":     [{"s", "length" m, "height" m}]  Schanze: steigt über length an, endet mit Kante
#   "gaps":      [{"from", "to"}]  kein Boden (Sprung über eine andere Straße / Abgrund)
#   "loops":     [{"s", "radius" m}]  Looping an Stelle s (autonome Durchfahrt mit dem Schwung)
#   "shortcuts": [{"from", "to", "path": [[x,z],...], "width" m, "surface"}]  Abkürzung von Stelle from nach to;
#                auf dem Pfad läuft der Streckenanteil gleitend von from nach to, übersprungene Tore gelten.
#   "terrain":   {"origin": [x,z], "cell": m, "w": n, "h": m, "heights": [...]}  Gelände-Höhenraster (Zeilen in z)
#   "widths":    [[s, halbe Breite m], ...]  Breitenprofil (linear, geschlossen); ohne: HALF_WIDTH
#   "mode":      "race" (Standard) | "drift" (Punkte für Drifts, Zeitlimit "time_limit" s, Ziele "drift_targets")
#   "guardrails":[{"from", "to", "side": "left"|"right"}]  Leitplanke; bricht ab BREAK_SPEED senkrecht zur Planke
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
var elevation: Array = []
var ramps: Array = []
var gaps: Array = []
var loops: Array = []
var shortcuts: Array = []
var terrain := {}
var guardrails: Array = []
var widths: Array = []
var mode := "race"
var time_limit := 0.0
var drift_targets: Array = []
var max_half_width := HALF_WIDTH
const BREAK_SPEED := 9.0      # m/s senkrecht zur Leitplanke: darüber bricht sie
var open := false         # Sprintstrecke: Start und Ziel getrennt, eine Durchfahrt
var laps := 2
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
	elevation = data.get("elevation", [])
	ramps = data.get("ramps", [])
	gaps = data.get("gaps", [])
	loops = data.get("loops", [])
	open = bool(data.get("open", false))
	terrain = data.get("terrain", {})
	guardrails = data.get("guardrails", [])
	widths = data.get("widths", [])
	mode = str(data.get("mode", "race"))
	time_limit = float(data.get("time_limit", 0.0))
	drift_targets = data.get("drift_targets", [])
	for w in widths:
		max_half_width = maxf(max_half_width, float(w[1]))
	for sc in data.get("shortcuts", []):
		var trail: Array[Vector2] = []
		for q in sc.path:
			trail.append(Vector2(float(q[0]), float(q[1])))
		var cum := PackedFloat32Array([0.0])
		for i in range(1, trail.size()):
			cum.append(cum[-1] + trail[i - 1].distance_to(trail[i]))
		shortcuts.append({"from": float(sc.from), "to": float(sc.to), "path": trail, "cum": cum,
			"width": float(sc.get("width", 3.0)), "surface": str(sc.get("surface", "gravel"))})
	laps = 1 if open else int(data.get("laps", 2))
	var control: Array[Vector2] = []
	for p in data.points:
		control.append(Vector2(float(p[0]), float(p[1])))
	build(control)

static func load_track(track_id: String) -> Circuit:
	return Circuit.new("res://tracks/%s.json" % track_id)

func build(control: Array[Vector2]) -> void:
	# 1. Catmull-Rom-Glättung (geschlossen bzw. bei Sprintstrecken offen), 2. gleichmäßige Abtastung im Abstand STEP.
	var fine: Array[Vector2] = []
	var n := control.size()
	var segs := n - 1 if open else n
	for i in range(segs):
		var p0 := control[maxi(i - 1, 0)] if open else control[(i - 1 + n) % n]
		var p1 := control[i]
		var p2 := control[(i + 1) % n]
		var p3 := control[mini(i + 2, n - 1)] if open else control[(i + 2) % n]
		var sub := maxi(2, ceili(p1.distance_to(p2) / 0.25))
		for k in range(sub):
			var t := float(k) / sub
			fine.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
				+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t))
	if open:
		fine.append(control[n - 1])
	var cum := PackedFloat32Array([0.0])
	var last := fine.size() - 1 if open else fine.size()
	for i in range(1, last + 1):
		cum.append(cum[i - 1] + fine[i - 1].distance_to(fine[i % fine.size()]))
	var total := cum[-1]
	var count := maxi(16, int(round(total / STEP))) + (1 if open else 0)
	var span_count := count - 1 if open else count
	points.clear()
	var j := 0
	for k in range(count):
		var d := total * k / span_count
		while j < cum.size() - 2 and cum[j + 1] < d:
			j += 1
		var f := clampf((d - cum[j]) / maxf(1e-6, cum[j + 1] - cum[j]), 0.0, 1.0)
		points.append(fine[j].lerp(fine[(j + 1) % fine.size()], f))
	length = total
	tangents.clear()
	for i in range(count):
		tangents.append((points[wrap_index(i + 1)] - points[wrap_index(i - 1)]).normalized())
	# Krümmung aus Richtungsänderung, über ±2 m geglättet.
	var raw := PackedFloat32Array()
	for i in range(count):
		raw.append(absf(tangents[wrap_index(i + 1)].angle_to(tangents[wrap_index(i - 1)])) / (2.0 * length / span_count))
	curvatures.clear()
	var win := int(2.0 / (length / span_count))
	for i in range(count):
		var acc := 0.0
		for k in range(-win, win + 1):
			acc += raw[wrap_index(i + k)]
		curvatures.append(acc / (2 * win + 1))
	bounds = Rect2(points[0], Vector2.ZERO)
	for p in points:
		bounds = bounds.expand(p)
	build_grid()

func wrap_index(i: int) -> int:
	# Punktindex: ringförmig bei Rundkursen, an den Enden begrenzt bei Sprintstrecken.
	var count := points.size()
	return clampi(i, 0, count - 1) if open else (i % count + count) % count

func span() -> int:
	# Anzahl der Abschnitte zwischen Punkten (s = Index / span).
	return points.size() - 1 if open else points.size()

func unit(s: float) -> float:
	# Streckenanteil einer Runde: Rundkurs zyklisch, Sprintstrecke begrenzt.
	return clampf(s, 0.0, 1.0) if open else fposmod(s, 1.0)

func build_grid() -> void:
	grid.clear()
	for i in range(span()):
		var a := points[i]
		var b := points[wrap_index(i + 1)]
		var reach := GRID_REACH + max_half_width - HALF_WIDTH
		var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * reach
		var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * reach
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
	return float(i) / span()

func locate(s: float) -> Vector2:
	# (Abschnittsindex, Anteil im Abschnitt) zu Streckenanteil s.
	var f := unit(s) * span()
	var i := mini(int(f), span() - 1) if open else int(f) % points.size()
	return Vector2(i, f - i)

func at(s: float, offset := 0.0) -> Vector2:
	var l := locate(s)
	var i := int(l.x)
	var p := points[i].lerp(points[wrap_index(i + 1)], l.y)
	var t := tangent(s)
	return p + Vector2(-t.y, t.x) * offset

func tangent(s: float) -> Vector2:
	var l := locate(s)
	var i := int(l.x)
	return tangents[i].lerp(tangents[wrap_index(i + 1)], l.y).normalized()

func curvature(s: float) -> float:
	return curvatures[int(locate(s).x)]

func nearest(p: Vector2, indices) -> Dictionary:
	var count := points.size()
	var best := INF
	var near := Vector2.ZERO
	var index := 0
	var frac := 0.0
	for i in indices:
		if open and i >= count - 1:
			continue
		var a := points[i]
		var b := points[(i + 1) % count]
		var q := Geometry2D.get_closest_point_to_segment(p, a, b)
		var d := p.distance_squared_to(q)
		if d < best:
			best = d
			near = q
			index = i
			frac = a.distance_to(q) / maxf(1e-6, a.distance_to(b))
	var s_value := (index + frac) / span()
	return {"distance": sqrt(best), "point": near, "index": index, "s": s_value if open else fposmod(s_value, 1.0)}

func query(p: Vector2) -> Dictionary:
	var c := candidates(p)
	return nearest(p, c if not c.is_empty() else range(points.size()))

func phase(p: Vector2) -> float:
	return float(query(p).s)

func phase_near(p: Vector2, hint: float, window := 0.12) -> float:
	# Lokale Projektion um den bisherigen Streckenanteil: an Kreuzungen (Acht) kein Sprung auf den anderen Ast.
	# Auf einer Abkürzung (vom Einstieg her erreicht) läuft der Anteil gleitend entlang des Pfads.
	if not shortcuts.is_empty():
		var sc := shortcut_at(p)
		if not sc.is_empty():
			var entry := float(shortcuts[int(sc.index)].from)
			var exit := float(shortcuts[int(sc.index)].to)
			var h := unit(hint)
			if h >= entry - 0.03 and h <= exit + 0.01:
				return float(sc.s)
	var count := points.size()
	var center := int(unit(hint) * span())
	var reach := int(window * count)
	var indices := PackedInt32Array()
	for k in range(-reach, reach + 1):
		if open and (center + k < 0 or center + k > count - 2):
			continue
		indices.append(wrap_index(center + k))
	return float(nearest(p, indices).s)

func center_distance(p: Vector2) -> float:
	# Abstand zur befahrbaren Mitte: Hauptstrecke oder Abkürzungspfad.
	var d := float(query(p).distance)
	var sc := shortcut_at(p, d)
	return minf(d, float(sc.distance)) if not sc.is_empty() else d

func shortcut_at(p: Vector2, main_distance := -1.0) -> Dictionary:
	# Abkürzung, auf deren Pfad p liegt (näher am Pfad als an der Hauptstrecke, innerhalb Breite + 1 m):
	# Index, Abstand, Anteil u entlang des Pfads, zugehöriger Streckenanteil s und Normale.
	if shortcuts.is_empty():
		return {}
	if main_distance < 0.0:
		main_distance = float(query(p).distance)
	var best := {}
	for k in range(shortcuts.size()):
		var sc: Dictionary = shortcuts[k]
		var path: Array = sc.path
		var cum: PackedFloat32Array = sc.cum
		for i in range(path.size() - 1):
			var q := Geometry2D.get_closest_point_to_segment(p, path[i], path[i + 1])
			var d := p.distance_to(q)
			if d > float(sc.width) * 0.5 + 1.0 or d >= main_distance:
				continue
			if best.is_empty() or d < float(best.distance):
				var along: float = cum[i] + Vector2(path[i]).distance_to(q)
				var u: float = along / maxf(cum[-1], 0.001)
				var dir: Vector2 = (path[i + 1] - path[i]).normalized()
				best = {"index": k, "distance": d, "u": u, "s": lerpf(float(sc.from), float(sc.to), u),
					"normal": Vector2(-dir.y, dir.x), "point": q}
	return best

func place(s: float, offset: float, shortcut := -1) -> Vector2:
	# Punkt zu Streckenanteil s und Seitenversatz; auf einer Abkürzung entlang ihres Pfads.
	if shortcut < 0 or shortcut >= shortcuts.size():
		return at(s, offset)
	var sc: Dictionary = shortcuts[shortcut]
	var u := clampf((unit(s) - float(sc.from)) / maxf(float(sc.to) - float(sc.from), 1e-6), 0.0, 1.0)
	var cum: PackedFloat32Array = sc.cum
	var path: Array = sc.path
	var target := u * cum[-1]
	for i in range(path.size() - 1):
		if target <= cum[i + 1] or i == path.size() - 2:
			var f := clampf((target - cum[i]) / maxf(cum[i + 1] - cum[i], 1e-6), 0.0, 1.0)
			var dir: Vector2 = (path[i + 1] - path[i]).normalized()
			return path[i].lerp(path[i + 1], f) + Vector2(-dir.y, dir.x) * offset
	return path[-1]

func other_branch_distance(p: Vector2, s: float, gap := 0.12) -> float:
	# Abstand zu Streckenteilen, die im Streckenverlauf weit entfernt sind (Kreuzung der Acht).
	var count := points.size()
	var best := INF
	for i in candidates(p):
		var ds := absf(index_s(i) - unit(s)) if open else absf(wrapf(index_s(i) - fposmod(s, 1.0), -0.5, 0.5))
		if ds > gap:
			best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, points[i], points[wrap_index(i + 1)])))
	return best

func hw(s: float) -> float:
	# Halbe Fahrbahnbreite an Stelle s (Breitenprofil, linear und geschlossen).
	if widths.is_empty():
		return HALF_WIDTH
	var x := unit(s)
	var n := widths.size()
	for i in range(n):
		var a: Array = widths[i]
		var b: Array = widths[(i + 1) % n]
		var sa := float(a[0])
		var sb := float(b[0]) + (1.0 if i == n - 1 else 0.0)
		var xx := x + (1.0 if i == n - 1 and x < sa else 0.0)
		if xx >= sa and xx <= sb:
			return lerpf(float(a[1]), float(b[1]), (xx - sa) / maxf(sb - sa, 1e-6))
	return float(widths[0][1])

func edge_offset(s: float, o: float) -> float:
	# Versatz für Darstellung: innerhalb der Fahrbahn mit der Breite skaliert, außerhalb gleicher Abstand zur Kante.
	var h := hw(s)
	if absf(o) <= HALF_WIDTH:
		return o * h / HALF_WIDTH
	return signf(o) * (h + absf(o) - HALF_WIDTH)

func inside(p: Vector2, margin := 0.0) -> bool:
	var q := query(p)
	return float(q.distance) <= hw(float(q.s)) + margin

# --- Höhe (2,5D) ---
func base_height(s: float) -> float:
	if elevation.is_empty():
		return 0.0
	var x := unit(s)
	var n := elevation.size()
	for i in range(n):
		var a: Array = elevation[i]
		var b: Array = elevation[(i + 1) % n]
		var sa := float(a[0])
		var sb := float(b[0]) + (1.0 if i == n - 1 else 0.0)
		var xx := x + (1.0 if i == n - 1 and x < sa else 0.0)
		if xx >= sa and xx <= sb:
			var f := (xx - sa) / maxf(sb - sa, 1e-6)
			# Dichte Profile (Generator) linear, wenige Stützpunkte weich (Rampen, Brücken).
			if n <= 16:
				f = f * f * (3.0 - 2.0 * f)
			return lerpf(float(a[1]), float(b[1]), f)
	return float(elevation[0][1])

func ramp_height(s: float) -> float:
	# Schanze: linear ansteigend über "length" Meter, danach sofort Kante (Absprung).
	var h := 0.0
	var x := unit(s)
	for r in ramps:
		var d := fposmod(x - float(r.s), 1.0) * length
		if d <= float(r.length):
			h = maxf(h, float(r.height) * d / float(r.length))
	return h

func in_gap(s: float) -> bool:
	var x := unit(s)
	for g in gaps:
		if x >= float(g.from) and x <= float(g.to):
			return true
	return false

func ground_height(s: float) -> float:
	# Fahrbahnhöhe an Streckenstelle s; in einer Lücke gibt es keinen Boden.
	if in_gap(s):
		return base_height(s) - 40.0
	return base_height(s) + ramp_height(s)

func loop_between(a: float, b: float) -> Dictionary:
	# Looping, dessen Einfahrt zwischen den Streckenanteilen a und b liegt (in Fahrtrichtung).
	for l in loops:
		var d := fposmod(float(l.s) - a, 1.0)
		if d <= fposmod(b - a, 1.0) and fposmod(b - a, 1.0) < 0.5:
			return l
	return {}

func surface_z(s: float) -> float:
	# Sichtbare Fahrbahnhöhe (Höhenprofil + Schanze, Lücken ignoriert) – für Linie, Marker, Kamera.
	return base_height(s) + ramp_height(s)

func terrain_height(p: Vector2) -> float:
	# Gelände unter Punkt p (bilinear aus dem Höhenraster); ohne Raster eben (0).
	if terrain.is_empty():
		return 0.0
	var cell := float(terrain.cell)
	var fx := (p.x - float(terrain.origin[0])) / cell
	var fz := (p.y - float(terrain.origin[1])) / cell
	var w := int(terrain.w)
	var h := int(terrain.h)
	var ix := clampi(int(floor(fx)), 0, w - 2)
	var iz := clampi(int(floor(fz)), 0, h - 2)
	var tx := clampf(fx - ix, 0.0, 1.0)
	var tz := clampf(fz - iz, 0.0, 1.0)
	var hs: Array = terrain.heights
	var a := lerpf(float(hs[iz * w + ix]), float(hs[iz * w + ix + 1]), tx)
	var b := lerpf(float(hs[(iz + 1) * w + ix]), float(hs[(iz + 1) * w + ix + 1]), tx)
	return lerpf(a, b, tz)

func guardrail_at(s: float, side: float) -> bool:
	# side > 0 = links (positiver Seitenversatz), < 0 = rechts.
	var x := unit(s)
	for g in guardrails:
		var a := float(g.from)
		var b := float(g.to)
		var inside_range := (x >= a and x <= b) if a <= b else (x >= a or x <= b)   # über den Start hinweg
		if inside_range and ((g.side == "left") == (side > 0.0)):
			return true
	return false

func momentum_needs() -> Array:
	# Mindesttempo (m/s) vor Loopings (oben muss v²/R ≥ g gelten; Einfahrt ≈ √(5gR), plus Reserve für
	# Luftwiderstand) und vor Schanzen, hinter denen eine Lücke liegt (Weite ≈ 2v²·Steigung/g).
	var needs: Array = []
	for l in loops:
		needs.append({"s": float(l.s), "speed": sqrt(5.0 * RaceVehicle.GRAVITY * float(l.radius)) * 1.15, "extra": 0.0})
	for g in gaps:
		for r in ramps:
			var end_s := float(r.s) + float(r.length) / length
			if absf(float(g.from) - end_s) * length < 3.0:
				var slope := float(r.height) / float(r.length)
				var jump := (float(g.to) - float(g.from)) * length + 2.0
				needs.append({"s": float(r.s), "speed": sqrt(jump * RaceVehicle.GRAVITY / (2.0 * slope)) * 1.15, "extra": float(r.length) + jump})
	return needs

func surface_at(p: Vector2) -> Dictionary:
	var q := query(p)
	var distance := float(q.distance)
	var width := hw(float(q.s))
	if not shortcuts.is_empty() and distance > width:
		var sc := shortcut_at(p, distance)
		if not sc.is_empty() and float(sc.distance) <= float(shortcuts[int(sc.index)].width) * 0.5:
			return {"kind": str(shortcuts[int(sc.index)].surface), "height": 0.2}
	if distance<=width:
		return {"kind":road,"height":0.207}
	if distance<width + 0.55:
		# Schotterpisten haben keine Randsteine, dort beginnt direkt der Waldboden.
		return {"kind":"curb","height":0.295} if road == "asphalt" else {"kind":"dirt","height":0.16}
	var s := float(q.s)
	var t := tangent(s)
	var side := (p - Vector2(q.point)).dot(Vector2(-t.y, t.x))
	for zone in surfaces:
		var inside_zone: bool = s >= float(zone.from) and s <= float(zone.to)
		var side_ok: bool = zone.side == "both" or (zone.side == "outer") == (side > 0.0)
		if inside_zone and side_ok and distance <= width + 1.4:
			return {"kind":str(zone.kind),"height":0.147}
	return {"kind":"dirt","height":0.137 if distance<=width + 1.4 else 0.105}

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
	var count := span() * laps
	var speeds := PackedFloat32Array()
	for i in range(count):
		var s := float(i) / span()
		var k := maxf(curvature(s), 0.0005)
		# Außen-/Innenspur ändern den Radius (Versatz relativ zur Kurvenrichtung wird näherungsweise ignoriert).
		speeds.append(minf(top, sqrt(lateral / k)))
	var ds := length / span()
	for _round in range(2):
		for i in range(count - 2, -1, -1):
			speeds[i] = minf(speeds[i], sqrt(speeds[i + 1] * speeds[i + 1] + 2.0 * brake * ds))
		if not open:
			speeds[count - 1] = minf(speeds[count - 1], speeds[0])
	# Schwung für Loopings und Sprünge: im Anlauf (25 m) und auf der Schanze Mindesttempo halten.
	for need in momentum_needs():
		for i in range(count):
			var d := fposmod(float(i) / span() - float(need.s), 1.0) * length
			if d >= length - 25.0 or d <= float(need.extra):
				speeds[i] = maxf(speeds[i], float(need.speed))
	var route: Array[Dictionary] = []
	for i in range(count + 1):
		var s := float(i) / span()
		route.append({"p": at(s, lane), "speed": speeds[mini(i, count - 1)], "s": s})
	return route
