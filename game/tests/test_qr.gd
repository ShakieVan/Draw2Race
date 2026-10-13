extends SceneTree
# QrCode (scripts/qr_code.gd, übernommen aus Mau-Mau Flip samt dieser Prüfung, Beta 1.0.2): Norm-Prüfwerte (Reed-Solomon nach
# ISO-Beispiel, Format- und Versionsinformation, Kapazitäten), Vergleich mit Referenzmatrizen aus libqrencode (ffmpeg qrencodesrc,
# Stufe M, reiner Byte-Modus; die Matrizen stammen aus Mau-Mau Flip) und Lesbarkeit aller Versionen 1–10 mit allen acht Masken über
# den Decoder quirc (ffmpeg-Filter „quirc“, falls ffmpeg im PATH liegt). Dazu lesen sich die beiden Codes der Einladung
# (WLAN-QR mit Sonderzeichen, Spiel-QR) mit quirc zurück.

var ok := 0
var fails := 0

# Referenzen: erzeugt am 04.10.2026 mit ffmpeg 9.0.1 (libqrencode), qrencodesrc=textfile=…:level=M:cs=1, Module 1:1 ausgelesen.
# Erste Zeile = Text, danach die Matrix ('#' dunkel).
const REF := {
	1: [
		"mau-mau flip!",
		"#######.####..#######",
		"#.....#.##.##.#.....#",
		"#.###.#.#.#.#.#.###.#",
		"#.###.#..##...#.###.#",
		"#.###.#.#####.#.###.#",
		"#.....#.......#.....#",
		"#######.#.#.#.#######",
		".........##..........",
		"#..#########.#..#.###",
		"..#..#..##..#.#...#..",
		"#...#.#....##.##..###",
		".##.##....#.##.##.##.",
		"#..#..#.##.###..#....",
		"........###...######.",
		"#######.#...###.###..",
		"#.....#.#.#.#####.###",
		"#.###.#.##.##..#.#.#.",
		"#.###.#.#.#..##......",
		"#.###.#.....###.#.###",
		"#.....#...###.##.####",
		"#######.#....##......",
	],
	5: [
		"der gastgeber legt die sitzordnung fest, jedes handy zeigt die anderen richtig.",
		"#######.##.##.#####......##.#.#######",
		"#.....#.####..##.#.##....#....#.....#",
		"#.###.#.##..####...###...###..#.###.#",
		"#.###.#..#.#.#..###.##..##..#.#.###.#",
		"#.###.#.#.....#.#.##.##...#.#.#.###.#",
		"#.....#..###...#.##..###....#.#.....#",
		"#######.#.#.#.#.#.#.#.#.#.#.#.#######",
		"..........##.#..#......####.#........",
		"#..#######.#....##..#...#.#..#..#.###",
		"#......#.#....#...##..##..##.#.#####.",
		"##....##.###.#...##.######.##.#.#...#",
		"##.##..#...#...#.##...##..##...#.##.#",
		"##...###..#.....#...#..#...##.##....#",
		"#.###...#..#.#.##.#...##.#.##...#....",
		"##.########.#..###.###..#####..#.#.##",
		"#.#..#..####..#.#.......#.#.#####.#.#",
		".#.#####..#.#..##.#.#.####.#.##..##.#",
		"###..#.##.#..#..#######....#.#.#..##.",
		".###.##.######.#...#..####.#..##....#",
		"..##......#..##...#.#..#.##..##.....#",
		"###..####.##.#####.##..##...###.##.##",
		"#.##...#.###..######.########..##.#..",
		"##.#######..#.##....#.##..##.###.#..#",
		"######....##.#...####.##..#####..##.#",
		"...#.####...#...###.#.###..##.##.#..#",
		"#...##..##..##..#.#..#.#.#####..#....",
		"##..#.#####.##..#..##....#.#..#..####",
		"#.###..##..##..#....#...#.#.....####.",
		"#.#..###.####.#....##.####.########..",
		"........###..#.##..##......##...####.",
		"#######.##.#.####..#####.#..#.#.#...#",
		"#.....#.#.##.##.####....##.##...##...",
		"#.###.#.#.#.##.#...#...##..#######...",
		"#.###.#.##.#..#.#.##...#..######....#",
		"#.###.#..#..#.###.#.#..##....#.###..#",
		"#.....#....#.##.##.#..###....#.#.####",
		"#######.#..#...#...##..##...##.###..#",
	],
	7: [
		"gib das handy nach links an lena; sie haelt den knopf gedrueckt, bis die hand erscheint. niemand sieht dabei karten!!",
		"#######..#.####.##..#.##..#...####..#.#######",
		"#.....#.##.#..#.##.#.##.#.#........#..#.....#",
		"#.###.#.#....#..#..#...#...####.##.#..#.###.#",
		"#.###.#.#.#.###.###.....#..##.####.##.#.###.#",
		"#.###.#..#####..#..#######.####.#.###.#.###.#",
		"#.....#..#....##..#.#...#####....#....#.....#",
		"#######.#.#.#.#.#.#.#.#.#.#.#.#.#.#.#.#######",
		"........#...#....##.#...###.##..#.#..........",
		"#.....#.###.#..#..#.#####......#.#...##..###.",
		"###..#..#..####.###.##...##.###########.#.#..",
		"#.##..####...#.#.#...##.#.##.....##.#.#..###.",
		"....##..#.#..#.##.####.########.#..##.###.###",
		"###.#.####.###.##.##...##...#.#.#.##..#.#...#",
		"#...#..##.#...###..##....#.#.##..#.###...##.#",
		"...#.####.##.#.####.#..#####.....##.#.##..##.",
		"#.......#.###.##.####.###.##.#............###",
		"###.###.###......##..#...##..........#.....##",
		"...###...#.###...........#..####.#.###..#.###",
		"...##.##.#.#.#.#.#...##.##.###.#.#.##..##.#.#",
		".##.#..#..#....#.###.#..##..###.##..#...#####",
		"....#####.#...#.###.#####....###.#..#####...#",
		"###.#...##..#.##...##...####.####.###...#....",
		".####.#.##.####.##..#.#.#.###....####.#.####.",
		".#.##...#.....##....#...#.#.###.#...#...###.#",
		"...######.##..#....######.#####.#.#.######...",
		"####.#..#.####.#..##..#.##....#..#...###....#",
		".#.#..#...##.....##....#..###...###.##..##.#.",
		"###..#.###.#.#.##.##.####.#......###....#.###",
		"#####.###.#.#.#..#.##..#.....##.....#..##..#.",
		".#..#...##.#.#...##...#..#.##.#..#..##.#.#..#",
		"##..#.##.#.#.###.#.#..##.#.#.#..##.##.#####.#",
		"#.#.##...#####.#........#.###.####.#.##...##.",
		".###.##..######.#.#..#.......###....##.##..#.",
		"#.##.#.#..#.....#..##..#.######.#.#.###.##...",
		"....#.##..#...#.......#...#....#.##.#..#...#.",
		".####..#..##.#.#.####.####..##..#..##.##.####",
		"#..##.##.#..#....#..#####.#.##..##########.##",
		"........#.#####..#.##...##....#..#.##...#.#.#",
		"#######...#.####...##.#.#.##...#.####.#.#..#.",
		"#.....#..#.#.#.#..###...##....#..#..#...#.###",
		"#.###.#...#.#..#.#..#####.#...##.##.#####..#.",
		"#.###.#..##.####.....#####.####..#......#.###",
		"#.###.#..#####..##..###.##.###.###..#...###.#",
		"#.....#....#.####.#.#....#..#.#######....##..",
		"#######.#.#####..#.#....#.#...##.#....##.#.#.",
	],
	10: [
		"mitspieler ohne app öffnen im browser die adresse des gastgebers, wählen einen namen und spielen mit; die karten liegen auf dem tisch, der stapel zeigt die gegenseite, wer „mau“ vergisst, zieht!",
		"#######..##.###..#.###..#.##..###.##..#...#.####..#######",
		"#.....#.#.##.#.#.##.###.#.###....##.###..#...#.#..#.....#",
		"#.###.#.#.#####..##.##..###.##.#.#..#...##..#.##..#.###.#",
		"#.###.#.###..#.###..#.#....##...#.##..########.#..#.###.#",
		"#.###.#...#.#.#..###.####.######...#.###.##.#..#..#.###.#",
		"#.....#...##.##.#.###..##.#...#...###......##.#...#.....#",
		"#######.#.#.#.#.#.#.#.#.#.#.#.#.#.#.#.#.#.#.#.#.#.#######",
		"........##.#.##..#...#..###...#.##...#..###.##.##........",
		"#.....#.#.##.#...#.#.#....######...###....##.....##..###.",
		"....#...#..#.##.#.#.#####.##..##.##..##.###..#######.#...",
		"...#..###.....#....#..#.###....#.###.##....#..#.#.##...#.",
		"#.##.#.#.....##..###..####.#....##....#.######..#...#.#..",
		"#.##.###.##..#.##...#..###.##.#.#.#.#.#.#.#.####.#####.##",
		"#......#.#####.######..#.###.##..#.###..######.##.#..#..#",
		"########...#..#..#..##....##...####...##.#...#####...###.",
		"...##..#...##..#.#....##.#.#.##...#......##..##...##..#.#",
		"..#.###...#####..#....#......###..#.#.##.###............#",
		".#.....#...##....#####..#...####..#.##....#..#.###.#.##.#",
		"#...#.###...#..#..#####.#....#..##..##.###.###.###..#.#.#",
		"###.##..#..###.##.##.#.###..##..##.#.#.##.#.##..#..######",
		"##...####..#######..#.....#......#.##....#.#.#...##..#.#.",
		"#.##.#.##.#..#..###...#.######.######.##.###.#######.#...",
		"##.####......##.####.##..#....#####.#.##.#.#.##.####.###.",
		"..#.#..#.#..#..##.##...###..#.#..#.#....#...#..#.....###.",
		"#..#..#.##.##..###....##.#..##...##.#..##.#.##...###.#..#",
		"...#...###.####.#####..##..#.##.##..#.#..##...####..#.#.#",
		"##.#########.#...#.##.#...#########.###.##..##.#########.",
		".####...##.#...###..#.##..#...#.......#...##..#.#...#####",
		"#.###.#.##.##.#.###..##...#.#.##.#.##.#..###.##.#.#.#..#.",
		"#.###...###.###.#.##.######...#..#...#...##.....#...#.#.#",
		".#.#########...##..##..##.#######...#..##..###.##########",
		"#..##..#.#...#..####....#...##..###..#..#.####.####..###.",
		".#..#.#...#.#.....##..###.#.#.##.#####.....#....#...##.#.",
		"...###.....##.#....#.##.#..##.#.#.#...#####.###..#.##.#.#",
		"..##..##.#..#.##.#.#...####.###..##...#.......####....###",
		".#.....#.........###..#.#..##...##.#.#.##.#.####..#.###..",
		".####.###.##..#.####..##.####.#.###.#.#.#########..#...##",
		".####..#....#.###...#.###.#####..#.#.#...##.##..#.##..###",
		"###...#..####.#####..#..#..##########.##...####.##.##..#.",
		"...##...##.###..#.##.####..#.....##..#.#.##..####..#..#.#",
		".#.#.###..##...####...#...######...##.....##......###....",
		"##.##..##..###.#.##...###.##.#.#.#.#...#.##..#...#.#....#",
		"..#.###.##..#.##..#..#..#...#.##.#.#.#.#.#.##..##.##..#.#",
		"#.####....##..#.##..#.######......#..#..###.#..#..#..##..",
		"###...#.#..#..##.##..##..####.#.....#.#...##.#......##.#.",
		"#..##..###...#.##.###.###.#########.#####.##.....#.####..",
		"#.#..##..#.###.##...###.##..#.#..###..#..#.##...##.#..##.",
		"#####....#..###.####.##.#..#.##.##......#.#.#..#..##.###.",
		"......####.#.#....#.#..#.##########.#..##############....",
		"........##.#.##.#.##.#..#.#...##.......####..#.##...###.#",
		"#######..#######...#.#...##.#.##.####.###..####.#.#.####.",
		"#.....#...#.###....#.##.#.#...#...##..#..##...###...#####",
		"#.###.#.....##..#..#.##.#######..#.##....#....#######...#",
		"#.###.#..######.#..#..##.##.#.#.##..##.####.#.......###..",
		"#.###.#..#...##..###.###.#..##...#.###..##.###.##....####",
		"#.....#..#.##......###.#.#.#.##.#.#...###.#.##..##...##..",
		"#######.#####.#.......##.#.....#.#.###...###.....###...#.",
	],
}


func check(cond: bool, what: String) -> void:
	if cond:
		ok += 1
	else:
		fails += 1
		print("FAIL: " + what)


func _init() -> void:
	_norm()
	_references()
	_limits()
	_quirc()
	_invite_codes()
	print("RESULT: %d ok" % ok)
	quit(0 if fails == 0 else 1)


func _norm() -> void:
	# ISO/IEC 18004 Anhang I: „01234567“ (Ziffernmodus) in 1-M → Datenwörter und die zehn Prüfwörter
	var data := PackedByteArray([16, 32, 12, 86, 97, 128, 236, 17, 236, 17, 236, 17, 236, 17, 236, 17])
	var ec := QrCode.rs_remainder(data, QrCode.rs_generator(10))
	check(ec == PackedByteArray([165, 36, 212, 193, 237, 54, 199, 135, 44, 85]), "Reed-Solomon (ISO-Beispiel): %s" % [ec])
	# Formatinformation Stufe M, Masken 0–7 (Tabelle der Norm)
	var fmt := ["101010000010010", "101000100100101", "101111001111100", "101101101001011",
		"100010111111001", "100000011001110", "100111110010111", "100101010100000"]
	for m in 8:
		check(_bin(QrCode.format_bits(m), 15) == fmt[m], "Formatbits M%d: %s" % [m, _bin(QrCode.format_bits(m), 15)])
	# Versionsinformation 7–10
	var ver := {7: "000111110010010100", 8: "001000010110111100", 9: "001001101010011001", 10: "001010010011010011"}
	for v in ver:
		check(_bin(QrCode.version_bits(v), 18) == ver[v], "Versionsbits %d" % v)
	# Byte-Kapazität Stufe M
	var cap := [14, 26, 42, 62, 84, 106, 122, 152, 180, 213]
	for v in range(1, 11):
		check(QrCode.capacity(v) == cap[v - 1], "Kapazität v%d = %d" % [v, QrCode.capacity(v)])


func _bin(value: int, bits: int) -> String:
	var s := ""
	for i in range(bits - 1, -1, -1):
		s += "1" if (value >> i) & 1 else "0"
	return s


func _references() -> void:
	for v in REF:
		var lines: Array = REF[v]
		var text: String = lines[0]
		var ref_rows: Array = lines.slice(1)
		var ref_mask := _mask_of(ref_rows)
		var auto := QrCode.encode(text)
		check(auto != null and auto.version == v, "Referenz v%d: Version %d" % [v, auto.version if auto else -1])
		var forced := QrCode.encode(text, 1, ref_mask)
		var mine := forced.to_text().split("\n")
		var diff := 0
		for y in ref_rows.size():
			for x in str(ref_rows[y]).length():
				if str(ref_rows[y])[x] != mine[y][x]:
					diff += 1
		check(diff == 0, "Referenz v%d (Maske %d): %d Module abweichend" % [v, ref_mask, diff])
		# Maskenwahl: gleiche Strafregeln → gleiche Wahl wie libqrencode
		check(auto.mask == ref_mask, "Referenz v%d: Maskenwahl %d, libqrencode %d" % [v, auto.mask, ref_mask])


# Maske aus der Formatinformation einer Matrix lesen (oberer linker Streifen)
func _mask_of(rows: Array) -> int:
	var bits := 0
	var pos := []
	for i in 6:
		pos.append(Vector2i(8, i))
	pos.append(Vector2i(8, 7))
	pos.append(Vector2i(8, 8))
	pos.append(Vector2i(7, 8))
	for i in range(9, 15):
		pos.append(Vector2i(14 - i, 8))
	for i in 15:
		var p: Vector2i = pos[i]
		if str(rows[p.y])[p.x] == "#":
			bits |= 1 << i
	for m in 8:
		if QrCode.format_bits(m) == bits:
			return m
	return -1


func _limits() -> void:
	check(QrCode.encode("x".repeat(213)) != null and QrCode.encode("x".repeat(213)).version == 10, "213 Bytes passen in v10")
	check(QrCode.encode("x".repeat(214)) == null, "214 Bytes sind zu lang")
	var e := QrCode.encode("")
	check(e != null and e.version == 1, "leerer Text")
	var q := QrCode.encode("http://192.168.178.23:24683/")
	var img := q.to_image(6, 4)
	check(img.get_width() == (q.size + 8) * 6, "Bildgröße mit Ruhezone")
	check(img.get_pixel(4 * 6 + 1, 4 * 6 + 1) == Color.BLACK and img.get_pixel(1, 1) == Color.WHITE, "Suchmuster dunkel, Rand hell")


# Lesbarkeit mit quirc: je Version zwei Bilder mit je vier Codes (Masken 0–3 und 4–7). Mehr Codes je Bild verwechselt quirc:
# Es kombiniert dann Suchmuster verschiedener Codes und stößt an seine Höchstzahl von acht Rastern.
func _quirc() -> void:
	var probe := []
	if OS.execute("ffmpeg", ["-hide_banner", "-version"], probe, true) != 0:
		print("HINWEIS: ffmpeg nicht gefunden – Lesbarkeitsprüfung übersprungen")
		return
	var dir := OS.get_user_data_dir().path_join("qr_test")
	DirAccess.make_dir_recursive_absolute(dir)
	var px := 4
	for sheet_no in 20:
		var v := 1 + sheet_no / 2
		var cell := (17 + 4 * 10 + 8) * px
		var sheet := Image.create(cell * 2, cell * 2, false, Image.FORMAT_RGBA8)
		sheet.fill(Color.WHITE)
		var texts: Array[String] = []
		for m in range((sheet_no % 2) * 4, (sheet_no % 2) * 4 + 4):
			var head := "v%d m%d äöü " % [v, m]
			var want := QrCode.capacity(v) - 3 * (m % 2)
			var text := head
			var filler := "draw2race, zeichne die linie! "
			while text.to_utf8_buffer().size() < want:
				text += filler[text.length() % filler.length()]
			while text.to_utf8_buffer().size() > want:
				text = text.substr(0, text.length() - 1)
			texts.append(text)
			var qr := QrCode.encode(text, 1, m)
			check(qr != null and qr.version == v and qr.mask == m, "Prüfcode v%d m%d gebaut" % [v, m])
			if qr == null:
				continue
			sheet.blit_rect(qr.to_image(px, 4), Rect2i(0, 0, (qr.size + 8) * px, (qr.size + 8) * px), Vector2i((m % 2) * cell, ((m / 2) % 2) * cell))
		var path := dir.path_join("qr_v%d_%d.png" % [v, sheet_no % 2])
		sheet.save_png(path)
		var out := []
		OS.execute("ffmpeg", ["-hide_banner", "-loglevel", "debug", "-i", path, "-vf", "quirc", "-f", "null", "-"], out, true)
		var log_text := "\n".join(PackedStringArray(out))
		var payloads: Array[String] = []
		for line in log_text.split("\n"):
			var at := line.find("with payload: ")
			if at >= 0:
				payloads.append(line.substr(at + 14).trim_suffix("\r"))
		# Windows liefert die Ausgabe als ANSI: UTF-8-Bytes stehen dann einzeln als Latin-1-Zeichen da
		var found := 0
		for t in texts:
			for p in payloads:
				if p == t or _latin1(p) == t.to_utf8_buffer():
					found += 1
					break
		check(found == 4, "quirc liest v%d (Bild %d): %d von 4 Codes %s" % [v, sheet_no % 2, found, payloads])


func _latin1(s: String) -> PackedByteArray:
	var out := PackedByteArray()
	for i in s.length():
		out.append(s.unicode_at(i) & 0xFF)
	return out


# Die beiden Codes der Einladung (NetInvite) so, wie InvitePanel sie zeichnet (8 px je Modul, Rand 2 Module, dunkles Petrol auf Weiß),
# müssen sich zurücklesen lassen – der WLAN-QR mit Sonderzeichen im Namen (Backslash-Schutz nach ZXing).
func _invite_codes() -> void:
	var probe := []
	if OS.execute("ffmpeg", ["-hide_banner", "-version"], probe, true) != 0:
		print("HINWEIS: ffmpeg nicht gefunden – Einladungscodes nicht zurückgelesen")
		return
	var dir := OS.get_user_data_dir().path_join("qr_test")
	DirAccess.make_dir_recursive_absolute(dir)
	var odd_ssid := "Spiel;WLAN:\\1"
	var odd_pass := "a,b\"c:d;e"
	var texts := [NetAndroid.wifi_qr_text("AndroidShare_4821", "k7m3x9q2w5r8t4z"), NetAndroid.wifi_qr_text(odd_ssid, odd_pass),
		NetAndroid.invite_url("10.94.17.1", NetApk.PORT), NetAndroid.invite_url("192.168.178.29", NetApk.PORT, 24790)]
	for i in texts.size():
		var qr := QrCode.encode(texts[i])
		check(qr != null, "Einladungscode %d gebaut" % i)
		if qr == null:
			continue
		var img := qr.to_image(8, 2, RaceHUD.INK, Color.WHITE)
		var framed := Image.create(img.get_width() + 32, img.get_height() + 32, false, Image.FORMAT_RGBA8)
		framed.fill(Color.WHITE)
		framed.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(16, 16))
		var path := dir.path_join("invite_%d.png" % i)
		framed.save_png(path)
		var out := []
		OS.execute("ffmpeg", ["-hide_banner", "-loglevel", "debug", "-i", path, "-vf", "quirc", "-f", "null", "-"], out, true)
		var got := ""
		for line in "\n".join(PackedStringArray(out)).split("\n"):
			var at := line.find("with payload: ")
			if at >= 0:
				got = line.substr(at + 14).trim_suffix("\r")
		check(got == texts[i] or _latin1(got) == str(texts[i]).to_utf8_buffer(), "quirc liest Einladungscode %d: %s" % [i, got])
	var parsed := QrJoin.parse(texts[1])
	check(parsed.kind == "wifi" and parsed.ssid == odd_ssid and parsed.password == odd_pass,
		"WLAN-QR mit Sonderzeichen: Erzeugen und Lesen passen zusammen (%s → %s)" % [texts[1], parsed])
