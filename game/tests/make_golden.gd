extends SceneTree

# Werkzeug (keine Suite): nimmt die Messanker des Höhen-Pakets auf (docs/dioramen/HOEHEN_PLAN.md, A0).
#   WRITE=1  schreibt game/tests/golden_times.json (Solo ai_route(2.3, 0), trocken, ohne Turbo, alle Strecken, 6 Nachkommastellen)
#   FIELD=1  druckt zusätzlich den Feldstatus (jede Strecke × 3 Herausforderungen wie im Spiel, Spieler-Ersatz ai_route(2.0, 0))
# Aufruf: tools/godot_run.ps1 -Script res://tests/make_golden.gd -Headless -EnvPairs 'WRITE=1','FIELD=1'
const TRACKS := ["azure", "city", "forest", "harbor", "serra", "fair", "quarry", "kids", "arena"]
const DT := 1.0 / 60.0

static func solo_time(id: String) -> Dictionary:
	RaceVehicle.weather_grip = 1.0
	var track := Circuit.load_track(id)
	var v := RaceVehicle.new(track, track.ai_route(2.3, 0.0))
	for tick in range(60 * 300):
		v.step(DT, false, float(tick + 1) * DT)
		if v.finish_time >= 0.0 or v.crashed:
			break
	return {"time": snappedf(v.finish_time, 0.000001), "crashed": v.crashed, "s": snappedf(v.progress, 0.0001)}

func _init() -> void:
	var golden := {}
	for id in TRACKS:
		golden[id] = solo_time(id)
		print("SOLO %-7s %s" % [id, JSON.stringify(golden[id])])
	if OS.get_environment("WRITE") == "1":
		var f := FileAccess.open("res://tests/golden_times.json", FileAccess.WRITE)
		f.store_string(JSON.stringify({"note": "Solo ai_route(2.3, 0), trocken, ohne Turbo (tests/make_golden.gd)", "physics": RaceVehicle.VERSION, "times": golden}, "\t") + "\n")
		f.close()
		print("geschrieben: res://tests/golden_times.json")
	if OS.get_environment("FIELD") == "1":
		for id in TRACKS:
			var track := Circuit.load_track(id)
			for stage in range(3):
				var res := RaceField.run_field(track, stage)
				print("FIELD %-7s %d %-5s %s" % [id, stage + 1, res.weather, res.text])
	quit()
