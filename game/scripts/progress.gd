class_name ProgressStore
extends RefCounted

# Version 2: Gold als eindeutige Einträge "strecke/stufe" (Version 1 speicherte Zahlen; nach dem Laden aus
# JSON waren das Kommazahlen, "0 in [0.0]" ist in GDScript falsch -> Gold wurde doppelt gezählt).
var data := {"version": 2, "gold": [], "best": {}, "sound": true, "music": true, "music_style": "energie",
	"camera": true, "camera_zoom": 0.4, "track": "azure", "music_volume": 0.8, "sfx_volume": 1.0, "times": {},
	"name": "", "show_names": true, "bubbles": true}
var path := "user://progress.json"

func _init(save_path := "user://progress.json") -> void:
	path = save_path
	for candidate in [path, path + ".bak"]:
		if not FileAccess.file_exists(candidate):
			continue
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(candidate)) != OK:
			continue
		var parsed = json.data
		if parsed is Dictionary and parsed.get("version") in [1, 1.0, 2, 2.0] and parsed.get("gold") is Array and parsed.get("best") is Dictionary:
			data.merge(parsed, true)
			migrate()
			break

func migrate() -> void:
	var unique: Array = []
	for entry in data.gold:
		var key := "azure/%d" % int(entry) if (entry is float or entry is int) else str(entry)
		if not key in unique:
			unique.append(key)
	data.gold = unique
	data.version = 2

# Bestzeit und Bestenliste gelten je Fassung der Strecke ("rev" der Streckendatei; Fassung 1 = bisheriger Schlüssel). Gold bleibt
# über Fassungen hinweg erhalten (Schlüssel ohne Fassung).
static var rev_cache := {}

static func track_rev(track_id: String) -> int:
	if not rev_cache.has(track_id):
		var path := "res://tracks/%s.json" % track_id
		var data = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		rev_cache[track_id] = int(data.get("rev", 1)) if data is Dictionary else 1
	return rev_cache[track_id]

static func board_key(track_id: String) -> String:
	var r := track_rev(track_id)
	return track_id if r <= 1 else "%s@r%d" % [track_id, r]

# ---------- Spielername (M1, docs/MULTIPLAYER_RECHERCHE.md 6) ----------
# Höchstens 12 Zeichen (wie NetProtocol.MAX_NAME): Buchstaben samt Umlauten und ß, Ziffern, Leerzeichen und - _ . ' ! ?
# Leer = Vorschlag „Fahrer NN“ (einmal zufällig gewählt und im Spielstand gemerkt, damit er gleich bleibt).
const NAME_MAX := 12
const NAME_MARKS := " -_.'!?"

static func name_char_ok(c: int) -> bool:
	return (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) \
		or (c >= 0xC0 and c <= 0x17F and c != 0xD7 and c != 0xF7) or NAME_MARKS.contains(char(c))

static func name_chars(text: String) -> String:
	var out := ""
	for i in range(text.length()):
		if name_char_ok(text.unicode_at(i)):
			out += text[i]
	return out

static func filter_name(text: String) -> String:
	# Beim Tippen: unerlaubte Zeichen weglassen, Länge begrenzen (Leerzeichen am Ende bleiben, man tippt ja weiter).
	return name_chars(text).left(NAME_MAX)

static func clean_name(text: String) -> String:
	# Zum Speichern: gefiltert, ohne Rand- und doppelte Leerzeichen, höchstens NAME_MAX Zeichen.
	var out := name_chars(text).strip_edges()
	while out.contains("  "):
		out = out.replace("  ", " ")
	return out.left(NAME_MAX).strip_edges()

func default_name() -> String:
	var hint := str(data.get("name_hint", ""))
	if clean_name(hint) == "" or hint != clean_name(hint):
		hint = "Fahrer %d" % randi_range(10, 99)
		data["name_hint"] = hint
	return hint

func player_name() -> String:
	var own := clean_name(str(data.get("name", "")))
	return own if own != "" else default_name()

func set_player_name(text: String) -> void:
	data["name"] = clean_name(text)
	save()

func has_gold(track_id: String, stage: int) -> bool:
	return "%s/%d" % [track_id, stage] in data.gold

func gold_count(track_id: String) -> int:
	return data.gold.filter(func(g): return str(g).begins_with(track_id + "/")).size()

func save() -> bool:
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data))
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.copy_absolute(path, path + ".bak")
	return DirAccess.rename_absolute(path + ".tmp", path) == OK

func result(track_id: String, stage: int, car: int, time: float, won: bool) -> bool:
	var key := "%s/%s/%d/%d" % [board_key(track_id), RaceVehicle.VERSION, stage, car]
	var record: bool = not data.best.has(key) or time < float(data.best[key])
	if record:
		data.best[key] = time
	var gold := "%s/%d" % [track_id, stage]
	if won and not gold in data.gold:
		data.gold.append(gold)
	last_place = add_time(track_id, stage, car, time)
	save()
	return record

func result_drift(track_id: String, stage: int, car: int, score: int, won: bool) -> bool:
	# Drift-Modus: Bestenliste nach Punkten (absteigend).
	var gold := "%s/%d" % [track_id, stage]
	if won and not gold in data.gold:
		data.gold.append(gold)
	if not data.has("times") or not data.times is Dictionary:
		data.times = {}
	var key := "%s/%d" % [board_key(track_id), stage]
	var list: Array = data.times.get(key, [])
	var best := 0 if list.is_empty() else int(list[0].get("score", 0))
	var entry := {"score": score, "time": 0.0, "car": car, "date": Time.get_date_string_from_system(), "physics": RaceVehicle.VERSION}
	list.append(entry)
	list.sort_custom(func(a, b): return int(a.get("score", 0)) > int(b.get("score", 0)))
	var place := list.find(entry) + 1
	data.times[key] = list.slice(0, BOARD_SIZE)
	last_place = place if place <= BOARD_SIZE else 0
	save()
	return score > best

# Persönliche Bestenliste je Strecke und Herausforderung: die 10 schnellsten Fahrten (Zeit, Auto, Datum).
const BOARD_SIZE := 10
var last_place := 0

func board(track_id: String, stage: int) -> Array:
	return data.get("times", {}).get("%s/%d" % [board_key(track_id), stage], [])

func add_time(track_id: String, stage: int, car: int, time: float) -> int:
	if not data.has("times") or not data.times is Dictionary:
		data.times = {}
	var key := "%s/%d" % [board_key(track_id), stage]
	var list: Array = data.times.get(key, [])
	var entry := {"time": snappedf(time, 0.001), "car": car, "date": Time.get_date_string_from_system(), "physics": RaceVehicle.VERSION}
	list.append(entry)
	list.sort_custom(func(a, b): return float(a.time) < float(b.time))
	var place := list.find(entry) + 1
	data.times[key] = list.slice(0, BOARD_SIZE)
	return place if place <= BOARD_SIZE else 0

func best_time(track_id: String, stage := -1) -> Dictionary:
	# Beste Fahrt einer Herausforderung oder (stage -1) der ganzen Strecke.
	var best := {}
	for st in ([stage] if stage >= 0 else [0, 1, 2]):
		var list := board(track_id, st)
		if not list.is_empty() and (best.is_empty() or float(list[0].time) < float(best.time)):
			best = list[0]
	return best
