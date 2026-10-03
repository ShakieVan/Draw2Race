extends SceneTree

# Nutzungsspuren (docs/dioramen/HOEHEN_PLAN.md 2.3 und 8; docs/dioramen/README.md „Nutzungsspuren“): je Strecke mit Laufzeit-Fahrbahn
# eine Spurenkarte game/assets/wear/<id>.png + .json (Erzeuger tests/make_wear.gd). Geprüft: vorhanden, Maße passen zu Länge/Breite,
# Hash aktuell, keine Spuren in Lücken/Looping-Zone/Schanzen/an der Startlinie und neben der Fahrbahn, keine geschlossene
# Gummifläche, Rinnen nur auf Schotter, verlustfreier Import mit Mipmaps, und die Simulation liest keine Karte.
const TRACKS := ["forest", "quarry", "harbor", "fair", "serra", "arena", "kids"]
const SIM_SCRIPTS := ["res://scripts/track.gd", "res://scripts/vehicle.gd", "res://scripts/race_field.gd", "res://scripts/seesaw.gd"]
const CLOSED_R := 0.45 * 255.0 + 3.0     # R über diesem Wert gilt als dunkle Gummifläche …
const CLOSED_PX := 25                     # … die quer höchstens 1,6 m (25 × 0,0625 m) zusammenhängen darf
var failures := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)
	else:
		print("PASS: ", message)

func _init() -> void:
	for id in TRACKS:
		test_track(str(id))
	for path in SIM_SCRIPTS:
		var text := FileAccess.get_file_as_string(path)
		check(text != "" and not ("wear_map" in text or "assets/wear" in text or "make_wear" in text), "%s liest keine Spurenkarte" % path.get_file())
	print("RESULT: ", checks - failures, "/", checks, " passed")
	quit(1 if failures else 0)

func test_track(id: String) -> void:
	var track := Circuit.load_track(id)
	var base := "res://assets/wear/%s" % id
	var has_files := FileAccess.file_exists(base + ".json") and FileAccess.file_exists(base + ".png")
	check(has_files, "%s: Spurenkarte vorhanden" % id)
	if not has_files:
		return
	var meta = JSON.parse_string(FileAccess.get_file_as_string(base + ".json"))
	check(meta is Dictionary and int(meta.get("version", 0)) == 1, "%s: Begleitdatei lesbar (version 1)" % id)
	if not meta is Dictionary:
		return
	check(str(meta.get("hash", "")) == track.file_hash, "%s: Hash passt zur Streckendatei (sonst make_wear neu erzeugen)" % id)
	var img := Image.load_from_file(ProjectSettings.globalize_path(base + ".png"))
	var lat := float(meta.lat)
	var px := float(meta.px_lat)
	var step := float(meta.step)
	var rows := img.get_height()
	var cols := img.get_width()
	check(is_equal_approx(px, 0.0625) and cols == int(round(2.0 * lat / px)) and lat >= track.max_half_width,
		"%s: Breite %d px = ±%.2f m (Fahrbahn bis %.2f m)" % [id, cols, lat, track.max_half_width])
	check(absf(rows * step - track.length) < 0.01 and absf(float(meta.length) - track.length) < 0.01 and step <= 0.25 + 1e-6 and step > 0.24,
		"%s: Länge %d Zeilen × %.4f m = %.1f m (Strecke %.1f m)" % [id, rows, step, rows * step, track.length])
	check(rows <= 4096, "%s: Texturhöhe %d ≤ 4096" % [id, rows])
	# Ausgesparte Zeilen (Kernbereiche, ohne Rand der Erzeugung): Start-/Ziellinie ±1 m, Lücken, Looping-Zone, Schanzen.
	var zones: Array = [[-1.0, 1.0]]
	if track.open:
		zones.append([track.length - 1.0, track.length + 1.0])
	for g in track.gaps:
		zones.append([float(g.from) * track.length, float(g.to) * track.length])
	for l in track.loops:
		zones.append([float(l.s) * track.length - float(l.radius), float(l.s) * track.length + float(l.radius)])
	for r in track.ramps:
		zones.append([float(r.s) * track.length, float(r.s) * track.length + float(r.length)])
	var spared_hits := 0
	var outside_hits := 0
	var worst_run := 0
	var worst_at := 0.0
	var sum_r := 0.0
	var sum_g := 0.0
	var max_b := 0.0
	var road_px := 0
	for y in range(rows):
		var m := (y + 0.5) * step
		var spare := false
		for z in zones:
			var dm := m - float(z[0])
			if not track.open:
				dm = fposmod(dm + 1.0, track.length) - 1.0
			if dm >= 0.0 and dm <= float(z[1]) - float(z[0]):
				spare = true
		var half := track.hw(m / track.length)
		var run := 0
		for x in range(cols):
			var c := img.get_pixel(x, y)
			var o := -lat + (x + 0.5) * px
			var any := c.r8 > 0 or c.g8 > 0 or c.b8 > 0
			if spare and any:
				spared_hits += 1
			if absf(o) > half + 0.1 and any:
				outside_hits += 1
			if absf(o) <= half:
				road_px += 1
				sum_r += c.r
				sum_g += c.g
			max_b = maxf(max_b, c.b)
			run = run + 1 if c.r8 > CLOSED_R else 0
			if run > worst_run:
				worst_run = run
				worst_at = m
	check(spared_hits == 0, "%s: keine Spuren an Startlinie, in Lücken, Looping-Zone, Schanzen (%d Pixel)" % [id, spared_hits])
	check(outside_hits == 0, "%s: keine Spuren neben der Fahrbahn (%d Pixel)" % [id, outside_hits])
	check(worst_run <= CLOSED_PX, "%s: keine geschlossene Gummifläche (längster dunkler Querlauf %.2f m bei %.1f m)" % [id, worst_run * px, worst_at])
	var mean_r := sum_r / maxi(road_px, 1)
	var mean_g := sum_g / maxi(road_px, 1)
	check(mean_r > 0.005 and mean_r < 0.15 and mean_g > 0.05 and mean_g < 0.6, "%s: Mittelwerte Gummi %.3f, Politur %.3f im Rahmen" % [id, mean_r, mean_g])
	if track.road == "gravel":
		check(max_b > 0.5, "%s: Schotter hat Spurrinnen (B max %.2f)" % [id, max_b])
	else:
		check(max_b == 0.0, "%s: Asphalt ohne Spurrinnen (B max %.2f)" % [id, max_b])
	# Import: verlustfrei, mit Mipmaps, keine Grafikkartenkompression (HOEHEN_PLAN 8).
	var imp := FileAccess.get_file_as_string(base + ".png.import")
	check(imp.contains("compress/mode=0") and imp.contains("mipmaps/generate=true") and imp.contains("detect_3d/compress_to=0"),
		"%s: Import verlustfrei mit Mipmaps" % id)
	var tex = load(base + ".png") if ResourceLoader.exists(base + ".png") else null
	check(tex is Texture2D and tex.get_width() == cols and tex.get_height() == rows, "%s: importierte Textur ladbar (%d × %d)" % [id, cols, rows])
