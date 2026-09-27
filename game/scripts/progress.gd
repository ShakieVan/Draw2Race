class_name ProgressStore
extends RefCounted

# Version 2: Gold als eindeutige Einträge "strecke/stufe" (Version 1 speicherte Zahlen; nach dem Laden aus
# JSON waren das Kommazahlen, "0 in [0.0]" ist in GDScript falsch -> Gold wurde doppelt gezählt).
var data := {"version": 2, "gold": [], "best": {}, "sound": true, "music": true, "music_style": "energie",
	"camera": true, "camera_zoom": 0.4, "track": "azure", "music_volume": 0.8, "sfx_volume": 1.0, "times": {}}
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
	var key := "%s/%s/%d/%d" % [track_id, RaceVehicle.VERSION, stage, car]
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
	var key := "%s/%d" % [track_id, stage]
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
	return data.get("times", {}).get("%s/%d" % [track_id, stage], [])

func add_time(track_id: String, stage: int, car: int, time: float) -> int:
	if not data.has("times") or not data.times is Dictionary:
		data.times = {}
	var key := "%s/%d" % [track_id, stage]
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
