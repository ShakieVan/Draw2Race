class_name QrCode
extends RefCounted
# QR-Code-Erzeuger, eigene Umsetzung nach ISO/IEC 18004 (keine fremde Bibliothek): Byte-Modus (UTF-8), Fehlerkorrektur M,
# Versionen 1–10 (bis 213 Bytes), Maskenwahl nach den vier Strafregeln N1–N4.
# Ablauf: Bitstrom (Modus 0100, Längenfeld, Daten, Abschluss, Füllbytes EC/11) → Blöcke mit Reed-Solomon-Prüfwörtern über
# GF(256) (Polynom 0x11D) → verschränken → Funktionsmuster, Daten im Zickzack, Maske, Format- und Versionsinformation.
# Verwendung: QrCode.encode("http://192.168.1.5:24683/").to_texture(8)
# Übernommen aus Mau-Mau Flip (Beta 1.0.1, dort geprüft mit Referenzmatrizen aus libqrencode und quirc); in Draw2Race prüft
# tests/test_invite.gd Kennwerte, Reed-Solomon und das Dekodieren der Muster (Format, Daten) aller Versionen und Masken.
# Genutzt für die Einladung im WLAN-Mehrspieler (InvitePanel: WLAN-QR und Spiel-QR, Beta 1.0.2).

const MAX_VERSION := 10
const FORMAT_MASK := 0x5412          # XOR-Maske der Formatinformation
const FORMAT_GEN := 0x537            # BCH(15,5)
const VERSION_GEN := 0x1F25          # BCH(18,6)
const EC_BITS_M := 0                 # Kennbits der Stufe M (L=01, M=00, Q=11, H=10)

# Stufe M je Version: [Codewörter gesamt, Prüfwörter je Block, Blöcke Gruppe 1, Daten je Block G1, Blöcke G2, Daten je Block G2]
const EC_M := [
	[],
	[26, 10, 1, 16, 0, 0],
	[44, 16, 1, 28, 0, 0],
	[70, 26, 1, 44, 0, 0],
	[100, 18, 2, 32, 0, 0],
	[134, 24, 2, 43, 0, 0],
	[172, 16, 4, 27, 0, 0],
	[196, 18, 4, 31, 0, 0],
	[242, 22, 2, 38, 2, 39],
	[292, 22, 3, 36, 2, 37],
	[346, 26, 4, 43, 1, 44],
]
# Mittelpunkte der Ausrichtungsmuster je Version
const ALIGN := [[], [], [6, 18], [6, 22], [6, 26], [6, 30], [6, 34], [6, 22, 38], [6, 24, 42], [6, 26, 46], [6, 28, 50]]

static var _exp := PackedInt32Array()
static var _log := PackedInt32Array()

var version := 0
var mask := -1
var size := 0
var modules := PackedByteArray()     # size*size, 1 = dunkel
var _func := PackedByteArray()       # 1 = Funktionsmodul (nicht maskieren, keine Daten)
var codewords := PackedByteArray()   # verschränkte Code-Wörter (für Tests)


# Erzeugt den Code oder null, wenn der Text zu lang ist. force_mask 0–7 erzwingt eine Maske (Tests), min_version eine Mindestgröße.
static func encode(text: String, min_version := 1, force_mask := -1) -> QrCode:
	var data := text.to_utf8_buffer()
	var v := maxi(min_version, 1)
	while v <= MAX_VERSION and data.size() > capacity(v):
		v += 1
	if v > MAX_VERSION:
		return null
	var qr := QrCode.new()
	qr._build(data, v, force_mask)
	return qr


# Höchstzahl Bytes im Byte-Modus bei Stufe M
static func capacity(v: int) -> int:
	var bits := data_codewords(v) * 8 - 4 - count_bits(v)
	return bits / 8


static func count_bits(v: int) -> int:
	return 8 if v <= 9 else 16


static func data_codewords(v: int) -> int:
	var e: Array = EC_M[v]
	return int(e[2]) * int(e[3]) + int(e[4]) * int(e[5])


func is_dark(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < size and y < size and modules[y * size + x] == 1


# Bild mit Ruhezone (border Module) – Module als scharfe Quadrate
func to_image(module_px := 8, border := 4, dark := Color.BLACK, light := Color.WHITE) -> Image:
	var w := (size + 2 * border) * module_px
	var img := Image.create(w, w, false, Image.FORMAT_RGBA8)
	img.fill(light)
	for y in size:
		for x in size:
			if modules[y * size + x] == 1:
				img.fill_rect(Rect2i((x + border) * module_px, (y + border) * module_px, module_px, module_px), dark)
	return img


func to_texture(module_px := 8, border := 4, dark := Color.BLACK, light := Color.WHITE) -> ImageTexture:
	return ImageTexture.create_from_image(to_image(module_px, border, dark, light))


# Textform für Tests: Zeilen aus '#' (dunkel) und '.' (hell)
func to_text() -> String:
	var rows: PackedStringArray = []
	for y in size:
		var row := ""
		for x in size:
			row += "#" if modules[y * size + x] == 1 else "."
		rows.append(row)
	return "\n".join(rows)


# ---------------------------------------------------------------- Aufbau

func _build(data: PackedByteArray, v: int, force_mask: int) -> void:
	version = v
	size = 17 + 4 * v
	codewords = _interleave(_data_codewords(data, v), v)
	modules = PackedByteArray()
	modules.resize(size * size)
	_func = PackedByteArray()
	_func.resize(size * size)
	_draw_function_patterns()
	_place_data(codewords)
	if force_mask >= 0 and force_mask <= 7:
		mask = force_mask
	else:
		var best := -1
		var best_score := 1 << 30
		for m in 8:
			_apply_mask(m)
			_draw_format(m)
			var score := penalty()
			if score < best_score:
				best_score = score
				best = m
			_apply_mask(m)   # XOR macht die Maske wieder rückgängig
		mask = best
	_apply_mask(mask)
	_draw_format(mask)


# Bitstrom → Datencodewörter mit Abschluss und Füllbytes
static func _data_codewords(data: PackedByteArray, v: int) -> PackedByteArray:
	var bits: Array[int] = []
	_push_bits(bits, 0b0100, 4)
	_push_bits(bits, data.size(), count_bits(v))
	for b in data:
		_push_bits(bits, b, 8)
	var cap := data_codewords(v) * 8
	_push_bits(bits, 0, mini(4, cap - bits.size()))
	while bits.size() % 8 != 0:
		bits.append(0)
	var out := PackedByteArray()
	for i in range(0, bits.size(), 8):
		var val := 0
		for k in 8:
			val = (val << 1) | bits[i + k]
		out.append(val)
	var pad := [0xEC, 0x11]
	var p := 0
	while out.size() < data_codewords(v):
		out.append(pad[p % 2])
		p += 1
	return out


static func _push_bits(bits: Array[int], value: int, count: int) -> void:
	for i in range(count - 1, -1, -1):
		bits.append((value >> i) & 1)


# Blöcke bilden, Prüfwörter anhängen, spaltenweise verschränken
static func _interleave(data: PackedByteArray, v: int) -> PackedByteArray:
	var e: Array = EC_M[v]
	var ec_len := int(e[1])
	var blocks: Array[PackedByteArray] = []
	var ecs: Array[PackedByteArray] = []
	var gen := rs_generator(ec_len)
	var pos := 0
	for g in 2:
		var count := int(e[2 + g * 2])
		var blen := int(e[3 + g * 2])
		for b in count:
			var block := data.slice(pos, pos + blen)
			pos += blen
			blocks.append(block)
			ecs.append(rs_remainder(block, gen))
	var out := PackedByteArray()
	var max_len := 0
	for blk in blocks:
		max_len = maxi(max_len, blk.size())
	for i in max_len:
		for blk in blocks:
			if i < blk.size():
				out.append(blk[i])
	for i in ec_len:
		for ec in ecs:
			out.append(ec[i])
	return out


# ---------------------------------------------------------------- Reed-Solomon über GF(256)

static func _gf_init() -> void:
	if _exp.size() > 0:
		return
	_exp.resize(512)
	_log.resize(256)
	var x := 1
	for i in 255:
		_exp[i] = x
		_log[x] = i
		x <<= 1
		if x & 0x100:
			x ^= 0x11D
	for i in range(255, 512):
		_exp[i] = _exp[i - 255]


static func gf_mul(a: int, b: int) -> int:
	if a == 0 or b == 0:
		return 0
	_gf_init()
	return _exp[_log[a] + _log[b]]


# Erzeugerpolynom g(x) = Π (x − α^i), i = 0 … degree−1; Koeffizienten vom höchsten Grad abwärts (g[0] = 1)
static func rs_generator(degree: int) -> PackedInt32Array:
	_gf_init()
	var g := PackedInt32Array([1])
	for i in degree:
		var nxt := PackedInt32Array()
		nxt.resize(g.size() + 1)
		for j in g.size():
			nxt[j] ^= g[j]
			nxt[j + 1] ^= gf_mul(g[j], _exp[i])
		g = nxt
	return g


# Rest der Division data(x)·x^n durch g(x) = Prüfwörter
static func rs_remainder(data: PackedByteArray, gen: PackedInt32Array) -> PackedByteArray:
	var n := gen.size() - 1
	var rem := PackedInt32Array()
	rem.resize(n)
	for b in data:
		var factor := b ^ rem[0]
		for k in range(n - 1):
			rem[k] = rem[k + 1]
		rem[n - 1] = 0
		for k in n:
			rem[k] ^= gf_mul(gen[k + 1], factor)
	var out := PackedByteArray()
	for r in rem:
		out.append(r)
	return out


# ---------------------------------------------------------------- Funktionsmuster

func _set_func(x: int, y: int, dark: bool) -> void:
	modules[y * size + x] = 1 if dark else 0
	_func[y * size + x] = 1


func _draw_function_patterns() -> void:
	# Zeitmuster
	for i in size:
		_set_func(6, i, i % 2 == 0)
		_set_func(i, 6, i % 2 == 0)
	# Suchmuster samt hellem Trennstreifen
	for c in [Vector2i(3, 3), Vector2i(size - 4, 3), Vector2i(3, size - 4)]:
		for dy in range(-4, 5):
			for dx in range(-4, 5):
				var x: int = c.x + dx
				var y: int = c.y + dy
				if x < 0 or y < 0 or x >= size or y >= size:
					continue
				var d := maxi(absi(dx), absi(dy))
				_set_func(x, y, d != 2 and d != 4)
	# Ausrichtungsmuster (nicht auf den Suchmustern)
	var pos: Array = ALIGN[version]
	var last := pos.size() - 1
	for i in pos.size():
		for j in pos.size():
			if (i == 0 and j == 0) or (i == 0 and j == last) or (i == last and j == 0):
				continue
			var cx := int(pos[i])
			var cy := int(pos[j])
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					_set_func(cx + dx, cy + dy, maxi(absi(dx), absi(dy)) != 1)
	# Formatbereiche reservieren (Inhalt folgt mit der Maske), dunkles Modul
	_draw_format(0)
	# Versionsinformation ab Version 7
	if version >= 7:
		var rem := version
		for i in 12:
			rem = (rem << 1) ^ ((rem >> 11) * VERSION_GEN)
		var bits := (version << 12) | rem
		for i in 18:
			var bit := ((bits >> i) & 1) == 1
			var a := size - 11 + i % 3
			var b := i / 3
			_set_func(a, b, bit)
			_set_func(b, a, bit)


static func format_bits(m: int) -> int:
	var data := (EC_BITS_M << 3) | m
	var rem := data
	for i in 10:
		rem = (rem << 1) ^ ((rem >> 9) * FORMAT_GEN)
	return ((data << 10) | rem) ^ FORMAT_MASK


static func version_bits(v: int) -> int:
	var rem := v
	for i in 12:
		rem = (rem << 1) ^ ((rem >> 11) * VERSION_GEN)
	return (v << 12) | rem


# Formatinformation zweifach: um das Suchmuster oben links sowie geteilt unten links/oben rechts (x = Spalte, y = Zeile)
func _draw_format(m: int) -> void:
	var bits := format_bits(m)
	for i in 6:
		_set_func(8, i, _bit(bits, i))
	_set_func(8, 7, _bit(bits, 6))
	_set_func(8, 8, _bit(bits, 7))
	_set_func(7, 8, _bit(bits, 8))
	for i in range(9, 15):
		_set_func(14 - i, 8, _bit(bits, i))
	for i in 8:
		_set_func(size - 1 - i, 8, _bit(bits, i))
	for i in range(8, 15):
		_set_func(8, size - 15 + i, _bit(bits, i))
	_set_func(8, size - 8, true)


static func _bit(value: int, i: int) -> bool:
	return ((value >> i) & 1) == 1


# Daten im Zickzack: Spaltenpaare von rechts, abwechselnd aufwärts und abwärts, Spalte 6 (Zeitmuster) wird übersprungen
func _place_data(words: PackedByteArray) -> void:
	var total := words.size() * 8
	var idx := 0
	var right := size - 1
	var upward := true
	while right >= 1:
		if right == 6:
			right = 5
		for k in size:
			var y := size - 1 - k if upward else k
			for dx in 2:
				var x := right - dx
				if _func[y * size + x] == 1:
					continue
				var dark := 0
				if idx < total:
					dark = (words[idx >> 3] >> (7 - (idx & 7))) & 1
				modules[y * size + x] = dark
				idx += 1
		upward = not upward
		right -= 2


static func mask_hit(m: int, x: int, y: int) -> bool:
	match m:
		0: return (y + x) % 2 == 0
		1: return y % 2 == 0
		2: return x % 3 == 0
		3: return (y + x) % 3 == 0
		4: return (y / 2 + x / 3) % 2 == 0
		5: return (y * x) % 2 + (y * x) % 3 == 0
		6: return ((y * x) % 2 + (y * x) % 3) % 2 == 0
		7: return ((y + x) % 2 + (y * x) % 3) % 2 == 0
	return false


func _apply_mask(m: int) -> void:
	for y in size:
		for x in size:
			var i := y * size + x
			if _func[i] == 0 and mask_hit(m, x, y):
				modules[i] ^= 1


# ---------------------------------------------------------------- Strafpunkte (Maskenwahl)

func penalty() -> int:
	var score := 0
	for horizontal in [true, false]:
		for a in size:
			var line := PackedByteArray()
			line.resize(size)
			for b in size:
				line[b] = modules[a * size + b] if horizontal else modules[b * size + a]
			score += _line_penalty(line)
	# N2: 2×2-Blöcke gleicher Farbe
	for y in size - 1:
		for x in size - 1:
			var c := modules[y * size + x]
			if c == modules[y * size + x + 1] and c == modules[(y + 1) * size + x] and c == modules[(y + 1) * size + x + 1]:
				score += 3
	# N4: Anteil dunkler Module, je volle 5 % Abweichung von 50 % zehn Punkte
	var dark := 0
	for v in modules:
		dark += v
	var total := size * size
	score += 10 * (absi(dark * 100 - total * 50) / (total * 5))
	return score


# N1 (Läufe ≥ 5: 3 + Überlänge) und N3 (1:1:3:1:1 mit vier hellen Modulen davor oder danach; außerhalb gilt als hell)
static func _line_penalty(line: PackedByteArray) -> int:
	var score := 0
	var runs: Array[Vector2i] = []   # (Farbe, Länge)
	var start := 0
	for i in range(1, line.size() + 1):
		if i == line.size() or line[i] != line[start]:
			var run_len := i - start
			runs.append(Vector2i(line[start], run_len))
			if run_len >= 5:
				score += 3 + (run_len - 5)
			start = i
	for k in range(2, runs.size() - 2):
		var c := runs[k]
		if c.x != 1 or c.y % 3 != 0:
			continue
		var n := c.y / 3
		if runs[k - 1] != Vector2i(0, n) or runs[k + 1] != Vector2i(0, n) or runs[k - 2] != Vector2i(1, n) or runs[k + 2] != Vector2i(1, n):
			continue
		var before := 1 << 20 if k - 3 < 0 else (runs[k - 3].y if runs[k - 3].x == 0 else 0)
		var after := 1 << 20 if k + 3 >= runs.size() else (runs[k + 3].y if runs[k + 3].x == 0 else 0)
		if before >= 4 * n or after >= 4 * n:
			score += 40
	return score
