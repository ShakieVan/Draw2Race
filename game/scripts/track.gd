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
var quay_z := 1e9          # Kaikante: Land nur bei z < quay_z (quay_dir 1) bzw. z > quay_z (−1), dahinter offenes Meer
var quay_dir := 1.0
var time_limit := 0.0
var drift_targets: Array = []
var max_half_width := HALF_WIDTH
const BREAK_SPEED := 9.0      # m/s senkrecht zur Leitplanke: darüber bricht sie
var open := false         # Sprintstrecke: Start und Ziel getrennt, eine Durchfahrt
var laps := 2
var rev := 1              # Fassung der Geometrie: Bestzeiten, Bestenliste und Geister gelten je Fassung
var file_hash := ""       # SHA-256 der Streckendatei (Gültigkeit von Diorama-Begleitdatei, Geist und Lauf)
var seesaws: Array = []   # Wippen-Einträge der Streckendatei (Zustand: Seesaw, je Rennen in RaceField)
var path := ""
var points: Array[Vector2] = []
var tangents: Array[Vector2] = []
var curvatures := PackedFloat32Array()
var length := 0.0
var bounds := Rect2()
var grid := {}

func _init(file_path := DEFAULT_TRACK) -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(file_path))
	if not data is Dictionary:
		push_error("Streckendatei fehlt oder ist ungültig: " + file_path)
		return
	path = file_path
	file_hash = FileAccess.get_sha256(file_path)
	rev = int(data.get("rev", 1))
	seesaws = data.get("seesaws", [])
	id = str(data.get("id", "track"))
	name = str(data.get("name", id))
	subtitle = str(data.get("subtitle", ""))
	theme = str(data.get("theme", "coast"))
	road = str(data.get("road", "asphalt"))
	quay_z = float(data.get("quay_z", 1e9))
	quay_dir = float(data.get("quay_dir", 1.0))
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
	for message in validate():
		push_error("%s: %s" % [file_path, message])
	load_obstacles()

func validate() -> Array:
	# Formatprüfung: Höhen- und Breitenprofil nach s sortiert, keine doppelten s (unsortiert entstünde eine Stufe, die das Auto
	# hochschleudert). Liefert die Fehlertexte; _init meldet sie per push_error.
	var out: Array = []
	for field in ["elevation", "widths"]:
		var list: Array = get(field)
		for i in range(1, list.size()):
			if float(list[i][0]) <= float(list[i - 1][0]):
				out.append("%s nicht streng nach s sortiert (Eintrag %d: %.4f nach %.4f)" % [field, i, float(list[i][0]), float(list[i - 1][0])])
	for d in seesaws:
		if int(d.get("shortcut", -1)) < 0 or int(d.get("shortcut", -1)) >= shortcuts.size():
			out.append("Wippe verweist auf keine Abkürzung")
	return out

func layout_valid(layout: Dictionary) -> bool:
	# Diorama-Begleitdatei passt zur Streckendatei: gleicher SHA-256 beim Bau, oder (ältere Dioramen ohne Schlüssel) Fassung 1.
	if layout.has("track_hash"):
		return str(layout.track_hash) == file_hash
	return rev <= 1

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

func query_branch(p: Vector2, hint: float) -> Dictionary:
	# Astbezug für Ebenen übereinander: wie query(p), aber liegt die nächste Mittellinie mehr als 1 m höher oder tiefer als die
	# Fahrbahn am bisherigen Streckenanteil hint (Brücke über den unteren Ast, Sprung über den eigenen Sohlenweg), gilt die nächste
	# Mittellinie im Fenster ±0,08 um hint. Ebene Kreuzungen (Acht, Jahrmarkt) bleiben exakt wie query(p).
	var q := query(p)
	if hint < 0.0 or (elevation.is_empty() and ramps.is_empty()):
		return q
	if absf(surface_z(float(q.s)) - surface_z(hint)) <= 1.0:
		return q
	var count := points.size()
	var center := int(unit(hint) * span())
	var reach := int(0.08 * count)
	var indices := PackedInt32Array()
	for k in range(-reach, reach + 1):
		if open and (center + k < 0 or center + k > count - 2):
			continue
		indices.append(wrap_index(center + k))
	return nearest(p, indices)

func center_distance(p: Vector2, hint := -1.0) -> float:
	# Abstand zur befahrbaren Mitte: Hauptstrecke (mit Astbezug, falls hint) oder Abkürzungspfad.
	var d := float(query_branch(p, hint).distance)
	var sc := shortcut_at(p, d)
	return minf(d, float(sc.distance)) if not sc.is_empty() else d

func shortcut_here(p: Vector2, hint: float) -> Dictionary:
	# Abkürzung, auf der ein Auto mit bisherigem Streckenanteil hint gerade fährt (wie in phase_near: vom Einstieg her erreicht).
	if shortcuts.is_empty():
		return {}
	var sc := shortcut_at(p)
	if sc.is_empty():
		return {}
	var h := unit(hint)
	if h >= float(shortcuts[int(sc.index)].from) - 0.03 and h <= float(shortcuts[int(sc.index)].to) + 0.01:
		return sc
	return {}

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

func path_pose(k: int, meters: float) -> Array:
	# Punkt und Richtung auf dem Pfad der Abkürzung k bei „meters“ Pfadmetern ab dem Abzweig.
	var sc: Dictionary = shortcuts[k]
	var cum: PackedFloat32Array = sc.cum
	var trail: Array = sc.path
	var target := clampf(meters, 0.0, cum[-1])
	for i in range(trail.size() - 1):
		if target <= cum[i + 1] or i == trail.size() - 2:
			var f := clampf((target - cum[i]) / maxf(cum[i + 1] - cum[i], 1e-6), 0.0, 1.0)
			return [Vector2(trail[i]).lerp(trail[i + 1], f), (Vector2(trail[i + 1]) - Vector2(trail[i])).normalized()]
	return [Vector2(trail[-1]), Vector2.RIGHT]

func shortcut_length(k: int) -> float:
	return float(shortcuts[k].cum[-1])

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

func gap_lip(s: float) -> float:
	# Landelippe der Lücke an Stelle s (m); -1 = keine Angabe (wie bisher: Hochziehen bis 3 m unter der Fahrbahn).
	var x := unit(s)
	for g in gaps:
		if x >= float(g.from) and x <= float(g.to):
			return float(g.lip) if g.has("lip") else -1.0
	return -1.0

func ground_height(s: float) -> float:
	# Fahrbahnhöhe an Streckenstelle s; in einer Lücke gibt es keinen Boden.
	if in_gap(s):
		return base_height(s) - 40.0
	return base_height(s) + ramp_height(s)

# Looping wie eine Spielzeugbahn: Einfahrt auf der linken Fahrbahnhälfte, Ausfahrt auf der rechten. Die Bahn
# ist ein Stück Schraubenlinie – ausgerollt eine gerade, schräg nach rechts führende Spur – und läuft so an
# sich selbst vorbei. Beim Hineinfahren lenkt man also leicht nach rechts.
const LOOP_LANE := 1.75        # Abstand der Spurmitten von der Mittellinie (m)
const LOOP_BAND := 1.45        # halbe Breite des Loopingbandes (m)

func loop_lateral(theta: float, entry := LOOP_LANE) -> float:
	# Seitlicher Versatz (links positiv) bei Winkel theta: gleichmäßig von der linken zur rechten Spur.
	# entry = tatsächlicher Versatz des Autos bei der Einfahrt; die Bahn führt es im ersten Zehntel in die Spur.
	var u := clampf(theta / TAU, 0.0, 1.0)
	var start := lerpf(entry, LOOP_LANE, smoothstep(0.0, 0.1, u))
	return lerpf(start, -LOOP_LANE, u)

func loop_basis(forward: Vector2, theta: float, radius: float, entry := LOOP_LANE) -> Basis:
	# Lage des Autos auf der Schraubenlinie (nur Darstellung): x = Fahrtrichtung, y = Dach zur Ringmitte.
	var f := Vector3(forward.x, 0.0, forward.y)
	var side := Vector3(-forward.y, 0.0, forward.x)
	var dl := (loop_lateral(theta + 0.01, entry) - loop_lateral(theta - 0.01, entry)) / 0.02
	var t := (f * radius * cos(theta) + Vector3.UP * radius * sin(theta) + side * dl).normalized()
	var n := (-f * sin(theta) + Vector3.UP * cos(theta)).normalized()
	var z := t.cross(n).normalized()
	return Basis(t, z.cross(t).normalized(), z)

func loop_lane_bias(s: float) -> float:
	# Für die KI: nach einem Looping von der Ausfahrtsspur zurück zur Mitte. Vor der Einfahrt kein Spurwechsel –
	# der kostet Anlauftempo; in die Einfahrtsspur führt die Bahn beim Aufstieg (loop_lateral).
	for l in loops:
		var after := fposmod(s - float(l.s), 1.0) * length
		if after < 18.0:
			return -LOOP_LANE * smoothstep(18.0, 6.0, after)
	return 0.0

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
	# Mindesttempo (m/s) vor Loopings (oben muss v²/R ≥ g gelten; Einfahrt ≈ √(5gR), plus Reserve für Luftwiderstand).
	# Sprünge über Lücken plant ai_route über jump_windows (ballistische Vorausrechnung wie im Fahrzeug).
	var needs: Array = []
	for l in loops:
		needs.append({"s": float(l.s), "speed": sqrt(5.0 * RaceVehicle.GRAVITY * float(l.radius)) * 1.15, "extra": 0.0})
	return needs

# ---------- Sprungfenster (KI, docs/dioramen/HOEHEN_PLAN.md A2 a/b/f) ----------
const JUMP_SKILL := 2.3          # Kurventempo hinter der Landung wird mit dieser Stufe bewertet
const JUMP_RUNUP := 40.0         # m: längster Anlauf (gerade, seit dem letzten Kurvenende) vor dem Absprung
const STRAIGHT_K := 1.0 / 60.0   # Krümmung, unter der ein Stück als gerade gilt
const JUMP_AIM := 1.0            # m/s: Ist-Ziel der KI mindestens so weit über der Fensteruntergrenze lo (die 2D-Fahrt bleibt 0,2–0,5 m/s unter der
                                 # 1D-Rechnung; Prüfung 03.10.: Hafen sprang mit 9,0–9,3 m/s bei lo 9,5 ab, nur 1,5 m/s über v_min)
const LOCK_BEFORE := 40.0        # Gegner-Turbosperre: m vor dem Absprung …
const LOCK_AFTER := 20.0         # … bis m hinter dem Lückenende
var jump_cache := {}             # Wetterhaftung -> Fenster
var jump_problems: Array = []    # Text je Sprung, dessen Fenster leer oder dessen Plan unerreichbar ist (Test FAIL)

func gap_kicker(g: Dictionary) -> Dictionary:
	# Schanze, die höchstens 3 m vor dem Lückenanfang endet (Kicker), sonst {}.
	for r in ramps:
		var end_s := float(r.s) + float(r.length) / length
		var before := wrapf(float(g.from) - end_s, -0.5, 0.5) * length
		if before >= -0.5 and before <= 3.0:
			return r
	return {}

func flight(s_t: float, z0: float, slope: float, u0: float, g: Dictionary) -> Dictionary:
	# Flug ab der Kante wie im Fahrzeug (60 Hz, Schwerkraft, waagrecht nur Luftwiderstand, Fortschritt entlang der Mittellinie).
	var dt := 1.0 / 60.0
	var u := u0
	var z := z0
	var vz := u0 * slope
	var s := s_t
	var was_gap := true
	var lip := float(g.lip) if g.has("lip") else 3.0
	for _tick in range(900):
		u -= 0.010 * u * u * dt
		s += u * dt / length
		vz -= RaceVehicle.GRAVITY * dt
		z += vz * dt
		var gap_now := in_gap(s)
		var ground := ground_height(s)
		if z <= ground:
			if gap_now:
				return {"ok": false, "why": "Lücke"}
			if was_gap and ground - z > lip:
				return {"ok": false, "why": "Lippe", "s": s}
			return {"ok": true, "s": s, "u": u, "vz": vz}
		if z < base_height(s) - 3.0:
			return {"ok": false, "why": "tief"}
		was_gap = gap_now
	return {"ok": false, "why": "Zeit"}

func jump_windows() -> Array:
	# Je Lücke: Absprung s_t = gap.from, Tempofenster [lo, hi] der KI aus der Vorausrechnung für u = 4 … 32 m/s.
	# v_min = kleinstes u mit Landung hinter der Lücke ohne Lippenverstoß; v_hi = größtes u, bei dem Landepunkt + 0,35 s·u
	# (Haftungsaufbau) vor der ersten Stelle liegt, deren Kurventempo √(lat/k) unter 0,9·Landetempo fällt.
	var key := snappedf(RaceVehicle.weather_grip, 0.001)
	if jump_cache.has(key):
		return jump_cache[key]
	var out: Array = []
	var road_grip: float = RaceVehicle.SURFACE_GRIP.get(road, 1.0) * RaceVehicle.weather_grip
	var lat_ref := (6.0 + JUMP_SKILL * 1.6) * road_grip
	for gi in range(gaps.size()):
		var g: Dictionary = gaps[gi]
		var s_t := float(g.from)
		var kicker := gap_kicker(g)
		var edge := s_t - 0.02 / length
		var slope := float(kicker.height) / float(kicker.length) if not kicker.is_empty() else (ground_height(edge) - ground_height(edge - 1.0 / length))
		var z0 := ground_height(edge)
		var v_min := -1.0
		var v_hi := -1.0
		for ui in range(113):
			var u0 := 4.0 + ui * 0.25
			var f := flight(s_t, z0, slope, u0, g)
			if not bool(f.ok):
				continue
			if v_min < 0.0:
				v_min = u0
			# erste Stelle hinter der Landung, deren Kurventempo unter 0,9 · Landetempo liegt
			var land := float(f.s)
			var lu := float(f.u)
			var limit := INF
			var m := 0.0
			while m < 160.0:
				var sx := land + m / length
				if sqrt(lat_ref / maxf(curvature(sx), 0.0005)) < 0.9 * lu:
					limit = m
					break
				m += 0.5
			if 0.35 * lu <= limit:
				v_hi = u0
		var lo := maxf(v_min + 2.0, 1.2 * v_min)
		var hi := v_hi - 1.5
		var w := {"gap": gi, "s_t": s_t, "to": float(g.to), "kicker": not kicker.is_empty(), "slope": slope,
			"v_min": v_min, "v_hi": v_hi, "lo": lo, "hi": hi, "ok": v_min > 0.0 and v_hi > 0.0 and lo <= hi}
		w["start"] = float(kicker.s) if not kicker.is_empty() else s_t
		out.append(w)
	jump_cache[key] = out
	return out

func boost_locked(progress_value: float) -> bool:
	# Gegner-Turbosperre vor und hinter Sprüngen (ohne Sperre landen Gegner mit Turbo zu weit, mitten in der nächsten Kurve).
	if gaps.is_empty():
		return false
	var x := unit(progress_value)
	for g in gaps:
		var a := (float(g.from) - LOCK_BEFORE / length)
		var b := (float(g.to) + LOCK_AFTER / length)
		if fposmod(x - a, 1.0) <= fposmod(b - a, 1.0):
			return true
	return false

const LOOP_CALM := 60.0         # m vor einem Looping ohne Ausweichen (ein Schlenker schaukelt sich bis zur Einfahrt auf und kostet Schwung)
const JUMP_CALM := 45.0         # m vor einem Absprung ohne Ausweichen (Feldtest Steinbruch Stufe 3: ein Schlenker 42 m vor der Kante pendelte bis
                                # auf den Kicker, Absprung schräg in die Grube)
var calm_zones := PackedByteArray()   # je Stützstelle 1 = kein Ausweichversatz (Schwungzone, erhöhte Fahrbahn)

func calm_at(s: float) -> bool:
	# Kein Ausweichen der Gegner: JUMP_CALM vor dem Absprung bis Lückenende + 15 m, LOOP_CALM vor einem Looping bis zur Ausfahrt + 10 m, und auf erhöhter
	# Fahrbahn (Fahrbahn mehr als 1 m über dem Gelände am Rand). Ohne Sprünge, Loopings und Höhen immer false.
	if gaps.is_empty() and loops.is_empty() and elevation.is_empty():
		return false
	if calm_zones.is_empty():
		calm_zones.resize(span())
		for i in range(span()):
			var x := float(i) / span()
			var calm := false
			for g in gaps:
				var a := float(g.from) - JUMP_CALM / length
				if fposmod(x - a, 1.0) <= fposmod(float(g.to) + 15.0 / length - a, 1.0):
					calm = true
			for l in loops:
				var a := float(l.s) - LOOP_CALM / length
				if fposmod(x - a, 1.0) <= (LOOP_CALM + 10.0) / length:
					calm = true
			if not calm and not elevation.is_empty():
				var base := base_height(x)
				for side in [-1.0, 1.0]:
					if base - terrain_height(at(x, side * hw(x))) > 1.0:
						calm = true
			calm_zones[i] = 1 if calm else 0
	return calm_zones[int(unit(s) * span()) % calm_zones.size()] == 1

func draw_height(s: float, sc := -1, p := Vector2.INF) -> float:
	# Sichtbare Höhe der Linie: Hauptstrecke surface_z(s); Abkürzung Gelände bzw. Wippendeck in Ruhelage.
	if sc < 0 or sc >= shortcuts.size():
		return surface_z(s)
	var q := place(s, 0.0, sc) if p == Vector2.INF else p
	for w in rest_seesaws():
		if w.shortcut == sc and w.inside(q):
			return w.rest_y(w.local(q).x)
	return terrain_height(q)

var level_cache := PackedByteArray()   # je Stützstelle: Bit 1 = über einem anderen Ast (≥ 2 m höher), Bit 2 = darunter

func level_flags() -> PackedByteArray:
	# Äste übereinander (Brücke über den Hohlweg, Sprung über den Sohlenweg): für Darstellung (Deck durchscheinend, Linie gestrichelt).
	if level_cache.is_empty():
		level_cache.resize(span())
		if elevation.is_empty():
			return level_cache
		for i in range(span()):
			var s := float(i) / span()
			var mine := base_height(s)
			var flag := 0
			for j in candidates(points[i]):
				var ds := absf(index_s(j) - s) if open else absf(wrapf(index_s(j) - s, -0.5, 0.5))
				if ds <= 0.12:
					continue
				var d := points[i].distance_to(Geometry2D.get_closest_point_to_segment(points[i], points[j], points[wrap_index(j + 1)]))
				if d < hw(s) + 1.0:
					var other := base_height(index_s(j))
					if mine - other >= 2.0:
						flag |= 1
					elif other - mine >= 2.0:
						flag |= 2
			level_cache[i] = flag
	return level_cache

func deck_over(s: float) -> bool:
	var f := level_flags()
	return not f.is_empty() and (f[int(unit(s) * span()) % f.size()] & 1) != 0

func under_deck(s: float) -> bool:
	var f := level_flags()
	return not f.is_empty() and (f[int(unit(s) * span()) % f.size()] & 2) != 0

func has_decks() -> bool:
	for v in level_flags():
		if v != 0:
			return true
	return false

func supported(s: float) -> bool:
	# Abschnitt, dessen Fahrbahn das Diorama trägt (Begleitdatei "supports"): keine Laufzeit-Pfeiler.
	var x := unit(s)
	for r in supports:
		if x >= float(r[0]) and x <= float(r[1]):
			return true
	return false

var rest_cache: Array = []

func rest_seesaws() -> Array:
	# Wippen in Ruhelage (nur Geometrie: Zeichnen, Darstellung, KI-Vorplanung).
	if rest_cache.is_empty() and not seesaws.is_empty():
		rest_cache = Seesaw.from_track(self)
	return rest_cache

func surface_at(p: Vector2, hint := -1.0) -> Dictionary:
	var q := query_branch(p, hint)
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

const WET_WALL_REACH := 6.0     # m neben dem Fahrbahnrand, in denen ein Hindernis die Nässeplanung vorsichtiger macht
const WET_WALL_FACTOR := 0.86   # zulässige Querbeschleunigung direkt an einer Wand bei Regen (Anteil)
const SNOW_WALL_FACTOR := 0.8   # dito bei Schnee (weniger Haftung, längeres Rutschen)
static var wet_caution := 0.8   # Querbeschleunigung der KI bei Schnee (Anteil; Regen 0,85 anteilig 0,9; trocken 1; Feldtest)
const WET_SOFT_SHARE := 0.5     # weiche Hindernisse (Absperrung, Bank, Gitter) fangen ebenfalls fest: halbe Wirkung

func wet_wall_margins() -> PackedFloat32Array:
	# Bei Nässe plant die KI dort vorsichtiger, wo ein Hindernis nah am Fahrbahnrand steht: Rutscht sie dort hinaus, gibt es keine
	# Auslaufzone (Stadion der Küste), und auch an Absperrungen, Bänken und Gittern bleibt ein Auto hängen (Wrack nach STUCK_TIME).
	# Je Stützstelle ein Faktor für die Querbeschleunigung (1 = nichts in Reichweite); Schnee staffelt stärker als Regen.
	# Hindernisse mit Unterkante zählen nur, wenn sie die Fahrbahnhöhe erreichen. Trocken wird das nie aufgerufen.
	var factor := lerpf(SNOW_WALL_FACTOR, WET_WALL_FACTOR, clampf((RaceVehicle.weather_grip - 0.7) / 0.15, 0.0, 1.0))
	var out := PackedFloat32Array()
	out.resize(span())
	for i in range(span()):
		var s := float(i) / span()
		var road_z := surface_z(s)
		var worst := 1.0
		for side in [-1.0, 1.0]:
			var d := 0.0
			while d < WET_WALL_REACH:
				var p := at(s, side * (HALF_WIDTH + d))
				var hit := 0.0
				for idx in obstacles_near(p):
					var o: Dictionary = obstacles[idx]
					if not obstacle_reaches(o, road_z):
						continue
					if obstacle_contact(o, p, 0.9).z > 0.0:
						hit = maxf(hit, WET_SOFT_SHARE if str(o.k) in SOFT_OBSTACLES else 1.0)
						if hit >= 1.0:
							break
				if hit > 0.0:
					var f := lerpf(factor, 1.0, clampf(d / WET_WALL_REACH, 0.0, 1.0))
					worst = minf(worst, lerpf(1.0, f, hit))
					if hit >= 1.0:
						break
				d += 0.5
		out[i] = worst
	return out

func ai_route(skill := 0.0, lane := 0.0, shortcut := -1) -> Array[Dictionary]:
	# Tempoprofil aus der Krümmung: Kurventempo über die zulässige Querbeschleunigung, davor
	# rechtzeitig bremsen (Rückwärtsdurchlauf). skill 0 = vorsichtig, 3 = gemessenes Optimum (mehr überzieht).
	# Haftung des Fahrbahnbelags (Schotter) senkt das mögliche Kurventempo. shortcut >= 0: zweite Route über diese Abkürzung
	# mit denselben s-Stützstellen (Wippe: RaceField tauscht beim Entscheidungspunkt nur das Routen-Array).
	var road_grip: float = RaceVehicle.SURFACE_GRIP.get(road, 1.0) * RaceVehicle.weather_grip
	var lateral := (6.0 + skill * 1.6) * road_grip
	var top := 15.0 + skill * 1.3
	var brake := 6.0 + skill * 1.0
	var count := span() * laps
	var speeds := PackedFloat32Array()
	var caps := PackedFloat32Array()      # Kurventempo je Stützstelle (Stufe der KI)
	# Deckel für Mindesttempi (Looping): nie über dem Kurventempo an der Haftungsgrenze des Grundautos (Gegner fahren es) an dieser Stelle.
	var need_caps := PackedFloat32Array()
	var need_lat := float(RaceVehicle.CARS[0].grip) * road_grip
	var margins := wet_wall_margins() if RaceVehicle.weather_grip < 0.999 else PackedFloat32Array()
	# Bei Nässe/Schnee etwas Reserve unter der Haftungsgrenze: Rutscher, Kontakte und Ausweichen kosten dort mehr (trocken 1).
	var caution := 1.0 if RaceVehicle.weather_grip >= 0.999 else lerpf(1.0, wet_caution, clampf((1.0 - RaceVehicle.weather_grip) / 0.3, 0.0, 1.0))
	for i in range(count):
		var s := float(i) / span()
		var k := maxf(curvature(s), 0.0005)
		# Außen-/Innenspur ändern den Radius (Versatz relativ zur Kurvenrichtung wird näherungsweise ignoriert).
		var lat := lateral * (margins[i % margins.size()] if not margins.is_empty() else 1.0) * caution
		caps.append(sqrt(lat / k))
		speeds.append(minf(top, caps[i]))
		need_caps.append(sqrt(maxf(lat, need_lat * (lat / maxf(lateral, 0.001))) / k))
	var ds := length / span()
	var slopes := PackedFloat32Array()
	if not elevation.is_empty():
		# Hangbewusst: bergab liegt der Bremsregler um g·|k|/1,6 über dem Plan (Plan absenken); im Rückwärtsdurchlauf mindert
		# Gefälle die verfügbare Verzögerung, Steigung erhöht sie.
		for i in range(count):
			var s0 := float(i) / span()
			slopes.append((ground_height(s0 + ds / length) - ground_height(s0)) / ds)
			if slopes[i] < 0.0:
				speeds[i] = maxf(5.0, speeds[i] - RaceVehicle.GRAVITY * -slopes[i] / 1.6)
		for _round in range(2):
			for i in range(count - 2, -1, -1):
				var b := maxf(2.0, brake + RaceVehicle.GRAVITY * slopes[i])
				speeds[i] = minf(speeds[i], sqrt(speeds[i + 1] * speeds[i + 1] + 2.0 * b * ds))
			if not open:
				speeds[count - 1] = minf(speeds[count - 1], speeds[0])
	for _round in range(2):
		for i in range(count - 2, -1, -1):
			speeds[i] = minf(speeds[i], sqrt(speeds[i + 1] * speeds[i + 1] + 2.0 * brake * ds))
		if not open:
			speeds[count - 1] = minf(speeds[count - 1], speeds[0])
	# Schwung für Loopings: im Anlauf (25 m) Mindesttempo halten, nie über dem Kurventempo der Stelle (Kurvendeckel). Das Plantempo trägt seit
	# 03.10.2026 den Reglerversatz wie bei Sprüngen (Antrieb (soll − ist)·2,2 deckt Luft- und Rollwiderstand): sonst kam die KI 1,5–2 m/s unter
	# dem Mindesttempo an und fiel im Pulk mit dem kleinsten Kontakt aus dem Looping.
	var loop_drag: float = RaceVehicle.SURFACE_DRAG.get(road, 0.0)
	for need in momentum_needs():
		var v_need := float(need.speed)
		var v_plan := v_need + (0.010 * v_need * v_need + v_need * (0.09 + loop_drag)) / 2.2
		for i in range(count):
			var d := fposmod(float(i) / span() - float(need.s), 1.0) * length
			if d >= length - 25.0 or d <= float(need.extra):
				speeds[i] = maxf(speeds[i], minf(v_plan, need_caps[i]))
	speeds = plan_jumps(speeds, caps, brake, skill)
	var route: Array[Dictionary] = []
	for i in range(count + 1):
		var s := float(i) / span()
		var bias := loop_lane_bias(s)
		var o: float = lane if bias == 0.0 else lerpf(lane, bias, absf(bias) / LOOP_LANE)
		route.append({"p": at(s, o), "speed": speeds[mini(i, count - 1)], "s": s, "o": o})
	if shortcut >= 0 and shortcut < shortcuts.size():
		return shortcut_route(route, shortcut, skill)
	return route

func plan_jumps(speeds: PackedFloat32Array, caps: PackedFloat32Array, brake: float, skill: float) -> PackedFloat32Array:
	# Sprünge: im geraden Anlauf (seit dem letzten Kurvenende, höchstens 40 m vor dem Absprung) Ist-Ziel u* = Plan geklemmt auf das
	# Fenster [lo, hi]; das Plantempo trägt den Reglerversatz (Antrieb (soll − ist)·2,2 deckt im Gleichgewicht Luft-, Roll- und
	# Hangwiderstand). Erreichbarkeit: 1D-Vorwärtsrechnung des Reglers (Grundauto, ohne Turbo) ab dem Kurventempo.
	if gaps.is_empty():
		return speeds
	var count := speeds.size()
	var n := span()
	var drag: float = RaceVehicle.SURFACE_DRAG.get(road, 0.0)
	for w in jump_windows():
		if not bool(w.ok):
			add_jump_problem("Sprung bei s %.4f: leeres Fenster (v_min %.2f, v_hi %.2f)" % [float(w.s_t), float(w.v_min), float(w.v_hi)])
			continue
		var i_t := int(round(float(w.s_t) * n))
		for lap in range(laps):
			var it := i_t + lap * n
			if it >= count:
				break
			# Anlauf: rückwärts bis zum Kurvenende (Schanzen selbst gelten als gerade), höchstens JUMP_RUNUP
			var i_a := it
			var i_kick := int(round(float(w.start) * n)) + lap * n
			while i_a > 0 and (it - i_a) * length / n < JUMP_RUNUP:
				if i_a - 1 < i_kick and curvature(float(i_a - 1) / n) >= STRAIGHT_K:
					break
				i_a -= 1
			var u_star := clampf(speeds[it], minf(float(w.lo) + JUMP_AIM, float(w.hi)), float(w.hi))
			for i in range(i_a, mini(it + 1, count)):
				var s0 := float(i) / n
				# Steigung der Fahrbahn (Höhenprofil), auf der Schanze deren Neigung (die Kante selbst ist keine Steigung).
				var slope := float(w.slope) if bool(w.kicker) and i >= i_kick else (base_height(s0 + 1.0 / length) - base_height(s0))
				speeds[i] = u_star + (0.010 * u_star * u_star + u_star * (0.09 + drag) + RaceVehicle.GRAVITY * slope) / 2.2
			# davor rechtzeitig auf das Plantempo bremsen
			# (nicht über den Absprung der Vorrunde hinweg: dahinter liegt deren Lücke, das Tempo dort zählt nicht)
			for i in range(i_a - 1, maxi(maxi(-1, i_a - 400), it - n), -1):
				speeds[i] = minf(speeds[i], sqrt(speeds[i + 1] * speeds[i + 1] + 2.0 * brake * length / n))
			# Erreichbarkeit
			# Stehender Start, wenn der Anlauf an der Startlinie der ersten Runde beginnt.
			var u := 0.0 if lap == 0 and i_a == 0 else minf(speeds[maxi(i_a - 1, 0)], caps[maxi(i_a - 1, 0)])
			var x := float(i_a) / n * length
			var x_end := float(it) / n * length
			var dt := 1.0 / 60.0
			var guard := 0
			while x < x_end and guard < 3600:
				guard += 1
				var idx := clampi(int(x / length * n), 0, count - 1)
				var plan := speeds[idx]
				var s0 := x / length
				var slope := float(w.slope) if bool(w.kicker) and idx >= i_kick else (base_height(s0 + 1.0 / length) - base_height(s0))
				var drive := clampf((plan - u) * 2.2, 0.0, 9.0)
				var braking := clampf((u - plan) * 1.6, 0.0, 12.0)
				u += (drive - braking - 0.010 * u * u - u * (0.09 + drag) - RaceVehicle.GRAVITY * slope / sqrt(1.0 + slope * slope)) * dt
				x += u * dt
			if lap == 0:
				w["planned"] = u_star
				w["reached"] = u
				w["skill"] = skill
			if u < float(w.lo) - 0.25:
				add_jump_problem("Sprung bei s %.4f (Stufe %.1f): Anlauf erreicht nur %.2f m/s, Fenster ab %.2f" % [float(w.s_t), skill, u, float(w.lo)])
	return speeds

func add_jump_problem(text: String) -> void:
	if not text in jump_problems:
		jump_problems.append(text)
		push_warning(id + ": " + text)

func path_curvature(k: int, m: float) -> float:
	# Krümmung des Abkürzungspfads bei m Pfadmetern: Knickwinkel je Stützpunkt (auch an Abzweig und Einmündung) über die halbe
	# Länge der Nachbarstücke verteilt, mindestens 2 m.
	var sc: Dictionary = shortcuts[k]
	var trail: Array = sc.path
	var cum: PackedFloat32Array = sc.cum
	var best := 0.0
	for j in range(trail.size()):
		var d_in: Vector2 = tangent(float(sc.from)) if j == 0 else (Vector2(trail[j]) - Vector2(trail[j - 1])).normalized()
		var d_out: Vector2 = tangent(float(sc.to)) if j == trail.size() - 1 else (Vector2(trail[j + 1]) - Vector2(trail[j])).normalized()
		var turn := absf(d_in.angle_to(d_out))
		var reach := 2.0
		if j > 0:
			reach = maxf(reach, (cum[j] - cum[j - 1]) * 0.5)
		if j < trail.size() - 1:
			reach = maxf(reach, (cum[j + 1] - cum[j]) * 0.5)
		if absf(m - cum[j]) <= reach:
			best = maxf(best, turn / (2.0 * reach))
	return best

const DECK_TOP_SPEED := 16.0    # KI höchstens so schnell über ein Lineal
const SHORTCUT_BLEND := 12.0    # m vor dem Abzweig Spur auf 0, ebenso lang dahinter zurück

func shortcut_route(base: Array[Dictionary], k: int, skill: float) -> Array[Dictionary]:
	# Route über die Abkürzung k mit denselben s-Stützstellen wie base: auf dem Pfad mittig, Tempo aus der Pfadkrümmung, auf dem
	# Lineal höchstens DECK_TOP_SPEED; Rückwärtsdurchlauf mit den wirklichen Abständen der Stützpunkte.
	var sc: Dictionary = shortcuts[k]
	var from := float(sc.from)
	var to := float(sc.to)
	var plen := float(sc.cum[-1])
	var grip: float = RaceVehicle.SURFACE_GRIP.get(str(sc.surface), 1.0) * RaceVehicle.weather_grip
	var lateral := (6.0 + skill * 1.6) * grip
	var top := 15.0 + skill * 1.3
	var brake := 6.0 + skill * 1.0
	var decks: Array = []
	for d in seesaws:
		if int(d.get("shortcut", 0)) == k:
			decks.append([float(d.get("at", 0.0)), float(d.get("length", 24.0)) * 0.5])
	var blend := SHORTCUT_BLEND / length
	var route: Array[Dictionary] = []
	for i in range(base.size()):
		var e: Dictionary = base[i].duplicate()
		var x := unit(float(e.s))
		if float(e.s) >= float(laps):
			x = 1.0 if open else 0.0
		if x >= from and x <= to:
			var m := (x - from) / maxf(to - from, 1e-6) * plen
			var v := minf(top, sqrt(lateral / maxf(path_curvature(k, m), 0.0005)))
			for d in decks:
				if absf(m - float(d[0])) <= float(d[1]) + 2.0:
					v = minf(v, DECK_TOP_SPEED)
			e.p = place(x, 0.0, k)
			e.o = 0.0
			e.sc = k
			e.speed = v
		else:
			var before := fposmod(from - x, 1.0)
			var after := fposmod(x - to, 1.0)
			var o := float(e.o)
			if before < blend:
				o = lerpf(o, 0.0, smoothstep(0.0, 1.0, 1.0 - before / blend))
			elif after < blend:
				o = lerpf(0.0, o, smoothstep(0.0, 1.0, after / blend))
			e.o = o
			e.p = at(float(e.s), o)
		route.append(e)
	for _round in range(2):
		for i in range(route.size() - 2, -1, -1):
			var dist := Vector2(route[i].p).distance_to(route[i + 1].p)
			route[i].speed = minf(float(route[i].speed), sqrt(float(route[i + 1].speed) * float(route[i + 1].speed) + 2.0 * brake * dist))
	return route

# ---------- Hindernisse (Deko mit Körper: Häuser, Absperrungen, Laternen, Bäume …) ----------
# Teil der Spielebene: dieselben Hindernisse in jeder Grafikstufe. Quelle ist die Begleitdatei des Dioramas
# (tools/diorama.py, "obstacles"), sonst die Bausteine der Streckendatei mit Maßen aus PROP_CIRCLES/AI_RADIUS.
const OBSTACLE_CELL := 8.0
const DIORAMA_BAKED := ["building", "street_tree", "fountain"]
const PROP_CIRCLES := {"lamp": 0.18, "lantern": 0.15, "floodlight": 0.35, "street_tree": 0.35, "palm": 0.3, "pine": 0.35,
	"oak": 0.45, "rock": 0.9, "parasol": 0.12, "tower": 1.2, "billboard": 0.25, "fountain": 3.4}
const AI_RADIUS := {"drift_zuschauer_container": 3.0, "hafen_faesser": 0.8, "hafen_gabelstapler": 1.3, "hafen_kran": 1.2,
	"hafen_paletten": 0.9, "hafen_poller": 0.3, "jahrmarkt_autoscooter": 6.0, "jahrmarkt_bude": 2.0, "jahrmarkt_karussell": 4.5,
	"jahrmarkt_losbude": 2.0, "jahrmarkt_riesenrad": 3.5, "jahrmarkt_zelt": 5.5, "kinder_ball": 2.8, "kinder_bauklotz": 1.3,
	"kinder_bausteinturm": 2.0, "kinder_kreisel": 2.0, "kinder_teddy": 3.0, "serra_agave": 0.6, "serra_aussicht": 1.0,
	"serra_fels": 1.3, "serra_kapelle": 3.5, "serra_leuchtturm": 2.5, "serra_olivenbaum": 0.4, "serra_pinie": 0.4,
	"steinbruch_bagger": 2.5, "steinbruch_brecher": 4.0, "steinbruch_buero": 3.0, "steinbruch_kieshaufen": 3.0, "steinbruch_kipper": 2.5}
const SOFT_OBSTACLES := ["absperrung", "gitter", "bank", "reifen"]
var obstacles: Array = []        # {k: Art, c: Mitte, u: a-Achse, h: halbe Maße (Rechteck) | r: Radius (Kreis), y: Höhe}
var obstacle_grid := {}
var baked_types: Array = DIORAMA_BAKED   # Bausteintypen, die das Diorama selbst enthält (Begleitdatei "baked"); "ai:<modell>" = nur dieses KI-Modell
var obstacle_source := "props"   # "layout": Hindernisse aus der Diorama-Begleitdatei (Häuser stehen dort, nicht an den Bausteinen)
var layout_ok := true            # false: Begleitdatei veraltet (Hash/rev) -> weder Diorama noch dessen Hindernisse
var supports: Array = []         # Begleitdatei "supports": [[s0, s1], ...] Abschnitte, deren Fahrbahn das Diorama trägt (keine Laufzeit-Pfeiler)

func add_circle(c: Vector2, r: float, height: float, kind: String) -> void:
	obstacles.append({"k": kind, "c": c, "r": r, "y": height})

func add_rect(c: Vector2, u: Vector2, half: Vector2, height: float, kind: String) -> void:
	obstacles.append({"k": kind, "c": c, "u": u.normalized(), "h": half, "y": height})

static func obstacle_reaches(o: Dictionary, z: float) -> bool:
	# Höhenüberlappung eines Autos (Unterkante z, 1,4 m hoch) mit einem Hindernis mit Unterkante "b" (Höhe "y" darüber).
	# Ohne "b" steht das Hindernis auf dem Boden (Aufrufer prüft wie bisher nur den Flug darüber).
	if not o.has("b"):
		return true
	var b := float(o.b)
	return z < b + float(o.y) and z + 1.4 > b

func load_obstacles() -> void:
	obstacles.clear()
	obstacle_grid.clear()
	obstacle_source = "props"
	var layout_path := "res://dioramas/%s_layout.json" % id
	var blocked: Array = []
	var from_layout := false
	layout_ok = true
	supports = []
	if FileAccess.file_exists(layout_path):
		var layout = JSON.parse_string(FileAccess.get_file_as_string(layout_path))
		if layout is Dictionary and not layout_valid(layout):
			# Veraltetes Diorama (Streckendatei seit dem Bau geändert): weder Bild noch Hindernisse benutzen (World.build prüft dasselbe).
			layout_ok = false
			push_warning("Diorama-Begleitdatei %s passt nicht zur Streckendatei (track_hash/rev): Laufzeitgrafik und Bausteine" % layout_path)
		elif layout is Dictionary and layout.has("obstacles"):
			from_layout = true
			obstacle_source = "layout"
			blocked = layout.get("blocked", [])
			baked_types = layout.get("baked", DIORAMA_BAKED)
			supports = layout.get("supports", [])
			for o in layout.obstacles:
				var c := Vector2(float(o.c[0]), float(o.c[1]))
				if o.has("r"):
					add_circle(c, float(o.r), float(o.y), str(o.k))
				else:
					add_rect(c, Vector2(float(o.u[0]), float(o.u[1])), Vector2(float(o.h[0]), float(o.h[1])), float(o.y), str(o.k))
				if o.has("v") and not bool(o.v):
					obstacles[-1]["v"] = false      # unsichtbarer Begrenzer: kollidiert, wird in der einfachen Grafikstufe aber nicht als Klotz gezeichnet
				if o.has("b"):
					obstacles[-1]["b"] = float(o.b)  # Unterkante (m, absolut): Kontakt nur bei Höhenüberlappung
			for lamp in layout.get("lamps", []):
				add_circle(Vector2(float(lamp.x), float(lamp.z)), 0.18, 4.0, "mast")
	for prop in props:
		var kind := str(prop.get("type", ""))
		if kind != "collider" and from_layout and (is_baked(prop) or on_layout_road(prop, blocked)):
			continue
		prop_obstacle(prop)
	for i in range(obstacles.size()):
		var o: Dictionary = obstacles[i]
		var reach: float = float(o.r) if o.has("r") else Vector2(o.h).length()
		var c: Vector2 = o.c
		for gx in range(floori((c.x - reach) / OBSTACLE_CELL), floori((c.x + reach) / OBSTACLE_CELL) + 1):
			for gz in range(floori((c.y - reach) / OBSTACLE_CELL), floori((c.y + reach) / OBSTACLE_CELL) + 1):
				var key := Vector2i(gx, gz)
				if not obstacle_grid.has(key):
					obstacle_grid[key] = []
				obstacle_grid[key].append(i)

func is_baked(prop: Dictionary) -> bool:
	# Steckt der Baustein im Diorama (Typ in "baked", bei KI-Modellen auch "ai:<modell>")? Dann entfallen Laufzeit-Bauteil und -Hindernis.
	var kind := str(prop.get("type", ""))
	return kind in baked_types or (kind == "ai" and ("ai:" + str(prop.get("model", ""))) in baked_types)

static func on_layout_road(prop: Dictionary, blocked: Array) -> bool:
	# Wie World.diorama_blocks: Laufzeit-Bauteile auf einer Diorama-Straße entfallen (und mit ihnen ihr Hindernis).
	var x := float(prop.get("x", 0.0))
	var z := float(prop.get("z", 0.0))
	for r in blocked:
		var rx: float = x - float(r[0])
		var rz: float = z - float(r[1])
		var a: float = rx * float(r[2]) + rz * float(r[3])
		var b: float = rx * float(r[4]) + rz * float(r[5])
		if a >= float(r[6]) and a <= float(r[7]) and b >= float(r[8]) and b <= float(r[9]):
			return true
	return false

func prop_obstacle(prop: Dictionary) -> void:
	var kind := str(prop.get("type", ""))
	var c := Vector2(float(prop.get("x", 0.0)), float(prop.get("z", 0.0)))
	var rot := deg_to_rad(float(prop.get("rot", 0.0)))
	var u := Vector2(cos(rot), sin(rot))
	var sc := float(prop.get("scale", 1.0))
	match kind:
		"collider":
			# Körper der Spielebene ohne eigenes Modell (Bruchwand, Wall, Stift, Hohlwegwand): Rechteck mit Unterkante b und Höhe h darüber.
			add_rect(c, u, Vector2(float(prop.get("w", 1.0)), float(prop.get("d", 1.0))) * 0.5, float(prop.get("h", 1.0)), str(prop.get("kind", "mauer")))
			obstacles[-1]["b"] = float(prop.get("b", 0.0))
			obstacles[-1]["v"] = bool(prop.get("visible", false))
		"building", "pavilion":
			add_rect(c, u, Vector2(float(prop.get("w", 4.0)), float(prop.get("d", 4.0))) * 0.5, float(prop.get("h", 3.0)), "mauer")
		"planter":
			add_rect(c, u, Vector2(float(prop.get("w", 2.0)), float(prop.get("d", 0.6))) * 0.5, 0.6, "mauer")
		"stand":
			add_rect(c, u, Vector2(float(prop.get("w", 8.0)), float(prop.get("d", 3.0)) + 2.0) * 0.5, 3.0, "mauer")
		"cabin":
			add_rect(c, u, Vector2(2.5, 2.0), 2.4, "mauer")
		"boathouse":
			add_rect(c, u, Vector2(2.25, 2.5), 2.5, "mauer")
		"log":
			add_rect(c, u, Vector2(1.6, 0.35), 0.7, "mauer")
		"ai":
			var model := str(prop.get("model", ""))
			if float(prop.get("y", 0.0)) < -1.0:
				return                                   # im Wasser (Schiffsrumpf)
			if prop.has("w") and prop.has("d"):
				var soft := "reifen" if model == "drift_reifenwand" else "mauer"
				add_rect(c, u, Vector2(float(prop.w), float(prop.d)) * 0.5, float(prop.get("h", 3.0)), soft)
			elif AI_RADIUS.has(model):
				add_circle(c, float(AI_RADIUS[model]), float(prop.get("h", 3.0)), "mauer")
			if model == "hafen_kran" and prop.has("feet"):
				add_circle(Vector2(float(prop.feet[0]), float(prop.feet[1])), 1.2, 20.0, "mauer")
		_:
			if PROP_CIRCLES.has(kind):
				add_circle(c, float(PROP_CIRCLES[kind]) * (sc if kind in ["pine", "oak", "rock"] else 1.0), 4.0, "baum" if kind in ["street_tree", "palm", "pine", "oak"] else "mast")

func obstacles_near(p: Vector2) -> Array:
	var key := Vector2i(floori(p.x / OBSTACLE_CELL), floori(p.y / OBSTACLE_CELL))
	return obstacle_grid.get(key, [])

func obstacle_contact(o: Dictionary, p: Vector2, radius: float) -> Vector3:
	# Kreis (Mitte p, Radius) gegen Hindernis: (Normale x, Normale z, Eindringtiefe); Tiefe <= 0 = keine Berührung.
	var c: Vector2 = o.c
	if o.has("r"):
		var d := p - c
		var dist := d.length()
		var n := d / dist if dist > 0.0001 else Vector2.RIGHT
		return Vector3(n.x, n.y, float(o.r) + radius - dist)
	var u: Vector2 = o.u
	var v := Vector2(-u.y, u.x)
	var half: Vector2 = o.h
	var rel := p - c
	var a := rel.dot(u)
	var b := rel.dot(v)
	var q := Vector2(clampf(a, -half.x, half.x), clampf(b, -half.y, half.y))
	var diff := Vector2(a, b) - q
	var dist := diff.length()
	var nl: Vector2
	var depth: float
	if dist > 0.0001:
		nl = diff / dist
		depth = radius - dist
	else:
		var ex := half.x - absf(a)
		var ez := half.y - absf(b)
		if ex < ez:
			nl = Vector2(signf(a) if a != 0.0 else 1.0, 0.0)
			depth = radius + ex
		else:
			nl = Vector2(0.0, signf(b) if b != 0.0 else 1.0)
			depth = radius + ez
	var n := u * nl.x + v * nl.y
	return Vector3(n.x, n.y, depth)
