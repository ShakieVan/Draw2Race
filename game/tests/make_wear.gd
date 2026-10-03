extends SceneTree

# Werkzeug (keine Suite): Spurenkarten der Laufzeit-Fahrbahnen, vorab gelegte Nutzungsspuren (docs/dioramen/HOEHEN_PLAN.md 2.3 und 8,
# docs/dioramen/README.md Abschnitt „Nutzungsspuren“). Nur Darstellung: Die Simulation liest die Karten nie.
#   TRACK=<id>|all   (Standard all; nur Strecken mit Laufzeit-Fahrbahn, siehe TRACKS)
# Aufruf: tools/godot_run.ps1 -Script res://tests/make_wear.gd -Headless -Timeout 900 -EnvPairs 'TRACK=all'
# Ergebnis: game/assets/wear/<id>.png (RGBA8 im Streckenraum: Spalte = Seitenversatz −lat … +lat, 0,0625 m je Pixel; Zeile = Bogenlänge
# ab s 0, ≈ 0,25 m je Pixel) und <id>.json ({version, lat, px_lat, step, length, hash, …}). Kanäle: R Gummi (Abdunklung),
# G Politur/Glanz, B Spurrinne (nur Schotter), A 255.
# Herkunft der Spuren: echte Solo-Fahrten mit RaceVehicle (trocken), skill 1,6/1,9/2,3/2,7/3,0 × Spur 1/−1/0,4/0, dazu zehn „Fahrer“
# auf einer geglätteten Ideallinie (langwelliger Versatz σ 0,35 m, Bremspunkt ±3 m, dreifaches Gewicht). Deterministisch (feste Saat).
const TRACKS := ["forest", "quarry", "harbor", "fair", "serra", "arena", "kids"]
const DT := 1.0 / 60.0
const PX_LAT := 0.0625
const STEP := 0.25
const MAX_ROWS := 4096                 # Texturhöhe: auf allen Zielgeräten sicher
const SKILLS := [1.6, 1.9, 2.3, 2.7, 3.0]
const LANES := [1.0, -1.0, 0.4, 0.0]
const IDEAL_DRIVERS := 10
const IDEAL_WEIGHT := 3.0
const IDEAL_MARGIN := 1.4              # Ideallinie bleibt so weit innerhalb der Fahrbahnkante (m)
const STREAK_KEEP := 0.15              # Anteil der Brems-/Rutschepisoden, die einen sichtbaren Strich hinterlassen
const DRIFT_KEEP := 0.45               # Drift-Arena: dort bleibt viel mehr Gummi liegen (Driftbögen)
const WHEEL_KEEP := 0.65               # … und davon je Rad (nicht jedes Rad blockiert gleich)
const LANDING_KEEP := 0.4              # Anteil der Landungen mit Abriebfleck
const HAZE_MAX := 0.22                 # weicher Gummischleier (alt, gräulich) höchstens so stark (R-Anteil)
const CLUMP_R := 0.45                  # geschlossene Gummifläche: R über diesem Wert …
const CLUMP_PX := 24                   # … höchstens so viele Pixel quer am Stück (1,5 m < 1,6 m)
const OLD_RUT := 0.95                  # alte Forst-/Fahrzeugrinnen: Seitenversatz (m)

var W := 0
var H := 0
var lat := 0.0
var step_m := STEP
var length := 0.0
var track: Circuit
var streak := PackedFloat32Array()
var haze := PackedFloat32Array()
var polish := PackedFloat32Array()
var rut := PackedFloat32Array()
var rng := RandomNumberGenerator.new()
var streak_keep := STREAK_KEEP

func _init() -> void:
	var which := OS.get_environment("TRACK")
	var ids: Array = TRACKS if which == "" or which == "all" else [which]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/wear"))
	for id in ids:
		make(str(id))
	quit()

func make(id: String) -> void:
	RaceVehicle.weather_grip = 1.0
	track = Circuit.load_track(id)
	length = track.length
	lat = ceilf((track.max_half_width + 0.25) / PX_LAT) * PX_LAT
	W = int(round(2.0 * lat / PX_LAT))
	H = ceili(length / STEP)
	if H > MAX_ROWS:
		push_error("%s: %d Zeilen > %d (Strecke zu lang für eine Karte)" % [id, H, MAX_ROWS])
		return
	step_m = length / H
	for arr in ["streak", "haze", "polish", "rut"]:
		var a := PackedFloat32Array()
		a.resize(W * H)
		a.fill(0.0)
		set(arr, a)
	rng.seed = hash(id + "-wear")
	streak_keep = DRIFT_KEEP if track.mode == "drift" else STREAK_KEEP
	var drivers := 0
	var crashed := 0
	var drift_car := -1
	for c in range(RaceVehicle.CARS.size()):
		if str(RaceVehicle.CARS[c].id) == "drift":
			drift_car = c
	# 1. Gegner-ähnliche Fahrer: Stufen × Spuren, Start auf den Startplätzen wie im Rennen.
	var slot := 0
	for skill in SKILLS:
		for lane in LANES:
			var route := track.ai_route(float(skill), float(lane))
			var car := drift_car if track.mode == "drift" and slot % 2 == 1 and drift_car >= 0 else 0
			if not drive(route, slot % 4, 1.0, car):
				crashed += 1
			drivers += 1
			slot += 1
	# 2. Ideallinie mit zehn Fahrern (langwelliger Versatz, Bremspunkt ±3 m).
	var ideal := ideal_offsets()
	for d in range(IDEAL_DRIVERS):
		var skill := 2.0 + 0.8 * float(d) / float(IDEAL_DRIVERS - 1)
		var route := ideal_route(skill, ideal, d)
		var car := drift_car if track.mode == "drift" and d % 2 == 1 and drift_car >= 0 else 0
		if not drive(route, d % 4, IDEAL_WEIGHT, car):
			crashed += 1
		drivers += 1
	start_marks()
	var img := compose()
	var png := "res://assets/wear/%s.png" % id
	img.save_png(ProjectSettings.globalize_path(png))
	var meta := {"version": 1, "lat": lat, "px_lat": PX_LAT, "step": snappedf(step_m, 0.000001), "length": snappedf(length, 0.0001),
		"rows": H, "cols": W, "hash": track.file_hash, "rev": track.rev, "drivers": drivers, "crashed": crashed,
		"note": "Nutzungsspuren (game/tests/make_wear.gd): R Gummi, G Politur, B Spurrinne; nur Darstellung"}
	var f := FileAccess.open("res://assets/wear/%s.json" % id, FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "\t") + "\n")
	f.close()
	print("WEAR %-7s %4d x %4d  Länge %.1f m  Fahrer %d  ausgeschieden %d  -> %s" % [id, W, H, length, drivers, crashed, png])

# --- Fahrten ---------------------------------------------------------------------------------------------------------------

func start_pose(slot: int) -> Array:
	# Startplatz wie RaceField: Rundkurs −0,012·i auf Spur 0/±1,2; Sprintstrecke alle auf der Linie (das Vorfeld hat keine Karte).
	var lane := RaceField.lane_for(slot)
	if track.open:
		return [0.0, lane]
	return [-float(slot) * RaceField.START_GAP, lane]

func drive(route: Array[Dictionary], slot: int, weight: float, car: int) -> bool:
	var pose := start_pose(slot)
	var v := RaceVehicle.new(track, route, float(pose[0]), float(pose[1]), car)
	var prev: Array = [null, null, null, null]
	var prev_speed := 0.0
	var was_air := false
	var air := 0.0
	var episode := 0
	var in_episode := false
	var keep := false
	var factor := 1.0
	var wheels_on := [true, true, true, true]
	var ep_dist := 0.0
	var landing_left := 0.0
	for tick in range(60 * 400):
		v.step(DT, false, float(tick + 1) * DT)
		if v.finish_time >= 0.0:
			return true
		if v.crashed or v.wrecked:
			print("  ausgeschieden: Gewicht %.0f, Auto %d, s %.4f, %s" % [weight, car, v.progress, v.wreck_cause if v.wrecked else "Absturz"])
			return false
		var speed := v.velocity.length()
		var accel := (speed - prev_speed) / DT
		prev_speed = speed
		if v.in_loop or v.airborne or v.deck != null or v.progress < 0.0:
			prev = [null, null, null, null]
			if v.airborne:
				was_air = true
				air += DT
			continue
		if was_air:
			# Landung: Gummiabrieb beim Aufsetzen (Räder werden auf Tempo gerissen), nur nach echtem Flug.
			if air > 0.25 and rng.randf() < LANDING_KEEP:
				landing_left = 1.6
			was_air = false
			air = 0.0
		var s_c := v.previous_phase
		var t := track.tangent(s_c)
		var n := Vector2(-t.y, t.x)
		var base := track.at(s_c)
		var fwd := Vector2.from_angle(v.heading)
		var side := fwd.orthogonal()
		# Ereignisse für Gummistriche: Verzögerung > 3 m/s², Schlupf, Anfahren unter 12 m/s.
		var e_brake := clampf((-accel - 3.0) / 5.0, 0.0, 1.0)
		var e_slip := clampf((v.slip - 0.14) / 0.45, 0.0, 1.0)
		var e_launch := clampf((12.0 - speed) / 12.0, 0.0, 1.0) * clampf((accel - 1.5) / 3.0, 0.0, 1.0) * 0.8
		var e := maxf(e_brake, e_slip)
		if e > 0.05 or e_launch > 0.05:
			if not in_episode:
				in_episode = true
				episode += 1
				keep = rng.randf() < streak_keep
				factor = rng.randf_range(0.6, 1.0)
				ep_dist = 0.0
				for w in range(4):
					wheels_on[w] = rng.randf() < WHEEL_KEEP
			ep_dist += speed * DT
		else:
			in_episode = false
		var gravel := track.road == "gravel"
		# Schlammzonen neben der Fahrbahn: Rinnen dort breiter und tiefer, mit 5 m weichem Übergang an den Zonenenden.
		var mud := 0.0
		for zone in track.surfaces:
			if str(zone.kind) == "mud":
				mud = maxf(mud, clampf(minf(s_c - float(zone.from), float(zone.to) - s_c) * length / 5.0, 0.0, 1.0))
		var rut_sigma := lerpf(0.19, 0.30, mud)
		for w in range(4):
			var wheel: Vector2 = TyreTracks.WHEELS[w]
			var p := v.pos + fwd * wheel.x + side * wheel.y
			var d := p - base
			var cur := Vector2(s_c * length + d.dot(t), d.dot(n))
			var last = prev[w]
			prev[w] = cur
			if last == null:
				continue
			var a: Vector2 = last
			var dm := cur.x - a.x
			if not track.open and absf(dm) > length * 0.5:
				a.x += signf(dm) * length
				dm = cur.x - a.x
			if absf(dm) > 3.0 or absf(cur.y - a.y) > 1.0:
				continue
			var seg := a.distance_to(cur)
			if seg < 0.0005:
				continue
			stamp_segment(polish, a, cur, 0.10, weight, true)
			if gravel:
				stamp_segment(rut, a, cur, rut_sigma, weight * (0.19 / rut_sigma) * (1.0 + 0.3 * mud), true)
			var rear := wheel.x < 0.0
			var ev := e * (1.0 if not rear else 0.75)
			if rear:
				ev = maxf(ev, e_launch)
			if landing_left > 0.0:
				ev = maxf(ev, 0.85)
			if gravel:
				ev *= 0.5
			if ev > 0.05:
				stamp_segment(haze, a, cur, 0.22, ev * weight, true)
				if (keep and wheels_on[w]) or landing_left > 0.0:
					# Striche setzen weich ein (Rad blockiert nicht schlagartig).
					stamp_streak(a, cur, ev * factor * (clampf(ep_dist / 2.5, 0.15, 1.0) if landing_left <= 0.0 else 1.0))
		if landing_left > 0.0:
			landing_left -= speed * DT
	return false

func start_marks() -> void:
	# Startplätze: kurze dunkle Anfahrflecken der Hinterräder (Rundkurse; auf der Sprintstrecke stehen die Gegner auf dem Vorfeld).
	if track.open:
		return
	for slot in range(4):
		var pose := start_pose(slot)
		var s0 := float(pose[0])
		for side in [0.5, -0.5]:
			var o: float = float(pose[1]) + side
			var m0 := s0 * length - 0.63
			for k in range(10):
				var m := m0 + 0.18 * k
				stamp_streak(Vector2(m, o), Vector2(m + 0.18, o), 0.9 - 0.06 * k)
				stamp_segment(haze, Vector2(m, o), Vector2(m + 0.18, o), 0.22, 2.0, true)

# --- Ideallinie ------------------------------------------------------------------------------------------------------------

func locked(s: float) -> bool:
	# Hier bleibt die Ideallinie bei der Spur der KI: Looping-Zone, Schanzen-Anlauf und Lücken (Fenster der Sprungplanung).
	var x := track.unit(s)
	for l in track.loops:
		var dm := fposmod(x - float(l.s) + 0.5, 1.0) - 0.5
		if dm * length > -30.0 and dm * length < float(l.radius) + 12.0:
			return true
	for g in track.gaps:
		var from := float(g.from) * length - 25.0
		var to := float(g.to) * length + 15.0
		var m := x * length
		if m >= from and m <= to:
			return true
	return false

func ideal_offsets() -> PackedFloat32Array:
	# Gummiband: jeder Punkt rückt zur Mitte seiner Nachbarn (Abstand m), Versatz begrenzt auf ±(hw − 1,2). Mehrere Maßstäbe.
	var n := track.span()
	var o := PackedFloat32Array()
	o.resize(n + 1)
	o.fill(0.0)
	var limit := PackedFloat32Array()
	var lock := PackedByteArray()
	var normals: Array[Vector2] = []
	var centers: Array[Vector2] = []
	for i in range(n + 1):
		var s := float(i) / n
		limit.append(maxf(0.0, track.hw(s) - IDEAL_MARGIN))
		lock.append(1 if locked(s) else 0)
		var t := track.tangent(s)
		normals.append(Vector2(-t.y, t.x))
		centers.append(track.at(s))
	for m in [24, 12, 6]:
		for _it in range(160):
			for i in range(n + 1):
				if lock[i] == 1:
					continue
				var ia: int = i - m
				var ib: int = i + m
				if track.open:
					if ia < 0 or ib > n:
						continue
				else:
					ia = posmod(ia, n)
					ib = posmod(ib, n)
				var pa: Vector2 = centers[ia] + normals[ia] * o[ia]
				var pb: Vector2 = centers[ib] + normals[ib] * o[ib]
				var p: Vector2 = centers[i] + normals[i] * o[i]
				var delta := ((pa + pb) * 0.5 - p).dot(normals[i])
				o[i] = clampf(o[i] + 0.6 * delta, -limit[i], limit[i])
	if not track.open:
		o[n] = o[0]
	# Gesperrte Stücke weich anbinden (kein Querruck vor Schanzen und Loopings).
	var out := o.duplicate()
	for i in range(n + 1):
		if lock[i] == 1:
			out[i] = 0.0
	for _r in range(40):
		var tmp := out.duplicate()
		for i in range(1, n):
			if lock[i] == 1:
				continue
			tmp[i] = (out[i - 1] + out[i] + out[i + 1]) / 3.0
		out = tmp
	return out

func ideal_route(skill: float, ideal: PackedFloat32Array, d: int) -> Array[Dictionary]:
	var base := track.ai_route(skill, 0.0)
	var n := track.span()
	# Langwelliger Versatz (Wellenlängen 35, 70, 140 m, zufällige Phasen), Effektivwert 0,35 m; Bremspunkt ±3 m.
	var phases := [rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU]
	var shift := int(round(rng.randf_range(-3.0, 3.0) / (length / n)))
	var amp := 0.35 / sqrt(0.5 * (1.0 + 0.36 + 0.16))
	var route: Array[Dictionary] = []
	for i in range(base.size()):
		var e: Dictionary = base[i].duplicate()
		var s := float(e.s)
		var k := posmod(i, n) if not track.open else mini(i, n)
		var m := s * length
		var wave := amp * (sin(TAU * m / 35.0 + phases[0]) + 0.6 * sin(TAU * m / 70.0 + phases[1]) + 0.4 * sin(TAU * m / 140.0 + phases[2]))
		var o := float(e.o)
		if not locked(s):
			var lim := maxf(0.0, track.hw(s) - 1.25)
			o = clampf(ideal[k] + wave, -lim, lim)
		e.o = o
		e.p = track.at(s, o)
		e.speed = float(base[clampi(i - shift, 0, base.size() - 1)].speed)
		route.append(e)
	return route

# --- Stempeln ------------------------------------------------------------------------------------------------------------

func row_of(m: float) -> int:
	var r := int(floor(m / step_m))
	if track.open:
		return r if r >= 0 and r < H else -1
	return posmod(r, H)

func stamp_segment(arr: PackedFloat32Array, a: Vector2, b: Vector2, sigma: float, value: float, per_meter: bool) -> void:
	# Weiche Querverteilung (Gauß, σ) entlang der Strecke a → b (x = Meter entlang, y = Seitenversatz); Wert je Meter Weg.
	var seg := a.distance_to(b)
	var pieces := maxi(1, ceili(seg / (step_m * 0.5)))
	var share := (seg / pieces) / step_m if per_meter else 1.0
	var reach := ceili(3.0 * sigma / PX_LAT)
	for k in range(pieces):
		var q := a.lerp(b, (k + 0.5) / pieces)
		var r := row_of(q.x)
		if r < 0:
			continue
		var c0 := (q.y + lat) / PX_LAT - 0.5
		var ci := int(round(c0))
		for c in range(maxi(0, ci - reach), mini(W, ci + reach + 1)):
			var dd := (float(c) - c0) * PX_LAT
			arr[r * W + c] += value * share * exp(-dd * dd / (2.0 * sigma * sigma))

func stamp_streak(a: Vector2, b: Vector2, value: float) -> void:
	# Schmaler Gummistrich (≈ 0,14 m breit, weiche Kante), Maximum statt Summe: Striche bleiben einzeln erkennbar.
	var seg := a.distance_to(b)
	var pieces := maxi(1, ceili(seg / (step_m * 0.5)))
	for k in range(pieces):
		var q := a.lerp(b, (k + 0.5) / pieces)
		var r := row_of(q.x)
		if r < 0:
			continue
		var c0 := (q.y + lat) / PX_LAT - 0.5
		var ci := int(round(c0))
		for c in range(maxi(0, ci - 2), mini(W, ci + 3)):
			var dd := absf((float(c) - c0) * PX_LAT)
			var g := clampf(1.0 - (dd - 0.035) / 0.045, 0.0, 1.0)
			var idx := r * W + c
			streak[idx] = maxf(streak[idx], value * g)

# --- Zusammensetzen ----------------------------------------------------------------------------------------------------

func percentile(arr: PackedFloat32Array, q: float) -> float:
	var vals := PackedFloat32Array()
	for x in arr:
		if x > 1e-4:
			vals.append(x)
	if vals.is_empty():
		return 1.0
	vals.sort()
	return maxf(vals[clampi(int(q * vals.size()), 0, vals.size() - 1)], 1e-4)

func blur(arr: PackedFloat32Array) -> PackedFloat32Array:
	# 1 px weichzeichnen (Binomial 1-2-1 quer und längs; Zeilen ringförmig auf Rundkursen).
	var tmp := arr.duplicate()
	for r in range(H):
		for c in range(1, W - 1):
			tmp[r * W + c] = 0.25 * arr[r * W + c - 1] + 0.5 * arr[r * W + c] + 0.25 * arr[r * W + c + 1]
	var out := tmp.duplicate()
	for r in range(H):
		var ra := r - 1
		var rb := r + 1
		if track.open:
			ra = maxi(ra, 0)
			rb = mini(rb, H - 1)
		else:
			ra = posmod(ra, H)
			rb = posmod(rb, H)
		for c in range(W):
			out[r * W + c] = 0.25 * tmp[ra * W + c] + 0.5 * tmp[r * W + c] + 0.25 * tmp[rb * W + c]
	return out

static func spared_rows(circuit: Circuit, rows: int) -> PackedByteArray:
	# Zeilen ohne Spuren: Start-/Ziellinie ±1 m, Lücken, Looping-Zone, Schanzen (auch test_wear.gd benutzt diese Regel).
	var out := PackedByteArray()
	out.resize(rows)
	out.fill(0)
	var len_m := circuit.length
	var step := len_m / rows
	for r in range(rows):
		var m := (r + 0.5) * step
		var spare := m < 1.0 + step or m > len_m - 1.0 - step
		for g in circuit.gaps:
			if m >= float(g.from) * len_m - 0.5 - step and m <= float(g.to) * len_m + 0.5 + step:
				spare = true
		for l in circuit.loops:
			var dm := fposmod(m - float(l.s) * len_m + len_m * 0.5, len_m) - len_m * 0.5
			if absf(dm) <= float(l.radius) + 2.0 + step:
				spare = true
		for rp in circuit.ramps:
			var dm := fposmod(m - float(rp.s) * len_m + len_m * 0.5, len_m) - len_m * 0.5
			if dm >= -0.5 - step and dm <= float(rp.length) + 0.5 + step:
				spare = true
		out[r] = 1 if spare else 0
	return out

func compose() -> Image:
	var hz := blur(haze)
	var hz_ref := percentile(hz, 0.98)
	var pol := blur(polish)
	var pol_ref := percentile(pol, 0.98)
	var rt := blur(rut)
	var rt_ref := percentile(rt, 0.97)
	var st := blur(streak)
	var spare := spared_rows(track, H)
	var gravel := track.road == "gravel"
	var data := PackedByteArray()
	data.resize(W * H * 4)
	var rr := PackedFloat32Array()
	rr.resize(W)
	var row_fac := PackedFloat32Array()
	row_fac.resize(H)
	var red_rows := PackedFloat32Array()
	red_rows.resize(W * H)
	for r in range(H):
		var m := (r + 0.5) * step_m
		var s := m / length
		var half := track.hw(s) - 0.05
		for c in range(W):
			var idx := r * W + c
			var o := -lat + (c + 0.5) * PX_LAT
			var red := 0.0
			var green := 0.0
			var blue := 0.0
			if spare[r] == 0 and absf(o) <= half:
				var h := HAZE_MAX * clampf(hz[idx] / hz_ref, 0.0, 1.0)
				red = clampf(h + st[idx] * 0.95 * (1.0 - h), 0.0, 1.0)
				green = pow(clampf(pol[idx] / pol_ref, 0.0, 1.0), 0.8)
				if gravel:
					var old := 0.45 * (exp(-pow((absf(o) - OLD_RUT) / 0.16, 2.0) * 0.5))
					blue = clampf(maxf(old, pow(clampf(rt[idx] / rt_ref, 0.0, 1.0), 0.9)), 0.0, 1.0)
				# Kante weich auslaufen lassen (kein harter Rand an der Fahrbahnkante).
				var edge := clampf((half - absf(o)) / 0.25, 0.0, 1.0)
				red *= edge
				green *= edge
				blue *= edge
			rr[c] = red
			data[idx * 4 + 1] = int(round(green * 255.0))
			data[idx * 4 + 2] = int(round(blue * 255.0))
			data[idx * 4 + 3] = 255
		# Keine geschlossene Gummifläche: Zeilen, in denen ein querer Lauf über CLUMP_R breiter als CLUMP_PX ist, bekommen einen
		# Dämpfungsfaktor (unten über Nachbarzeilen geglättet, damit keine waagrechten Kanten entstehen).
		var fac := 1.0
		# größtes Minimum eines Fensters von CLUMP_PX + 1 Pixeln: liegt es über CLUMP_R, gibt es einen zu breiten Lauf
		var worst := 0.0
		for c in range(0, W - CLUMP_PX):
			if rr[c] <= CLUMP_R:
				continue
			var low := 1.0
			for k in range(c, c + CLUMP_PX + 1):
				low = minf(low, rr[k])
				if low <= CLUMP_R:
					break
			worst = maxf(worst, low)
		if worst > CLUMP_R:
			fac = CLUMP_R * 0.97 / worst
		row_fac[r] = fac
		for k in range(W):
			red_rows[r * W + k] = rr[k]
	# Faktoren glätten (Minimum über ±6 Zeilen, dann Mittel, nie über dem eigenen Faktor) und anwenden.
	var smooth := PackedFloat32Array()
	smooth.resize(H)
	for r in range(H):
		var f := 1.0
		for k in range(-6, 7):
			var rk := r + k
			if track.open:
				if rk < 0 or rk >= H:
					continue
			else:
				rk = posmod(rk, H)
			f = minf(f, row_fac[rk])
		smooth[r] = f
	for r in range(H):
		var sum := 0.0
		var cnt := 0
		for k in range(-4, 5):
			var rk := r + k
			if track.open:
				if rk < 0 or rk >= H:
					continue
			else:
				rk = posmod(rk, H)
			sum += smooth[rk]
			cnt += 1
		var f := minf(sum / cnt, row_fac[r])
		for k in range(W):
			data[(r * W + k) * 4] = int(round(clampf(red_rows[r * W + k] * f, 0.0, 1.0) * 255.0))
	return Image.create_from_data(W, H, false, Image.FORMAT_RGBA8, data)
