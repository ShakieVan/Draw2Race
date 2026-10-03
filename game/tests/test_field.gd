extends SceneTree

# Feldtest (docs/dioramen/HOEHEN_PLAN.md, Regel 1.3 und Abschnitt 9): jede Rennstrecke × 3 Herausforderungen wie im Spiel über RaceField
# (Aufstellung, Wetter der Herausforderung, Ausweichen, Kontakte, Gegner-Turbo, Wippen) mit dem Spieler-Ersatz ai_route(2.0, 0).
# Für die Höhenstrecken und die Serra ist jeder ausgeschiedene Gegner ein FAIL; auf den unveränderten Strecken ein WARN mit Ursache.
# Seit 03.10.2026 (Prüfung der Nachtschicht: das Grün hing an der einen Spielerlinie) fahren die Pflichtstrecken zusätzlich mit weiteren
# Spieler-Ersatzlinien: langsam auf der Außenspur, schnell auf der Gegenspur mit Turbo (ohne Sperrzonen), am Limit mittig. Diese Linien
# rechnet der Test trocken, wie ein Mensch sie ohne Rücksicht auf Nässe zeichnet; verunglückt der Spieler, zählt nur, dass die Gegner ankommen.
const MUST_FINISH := ["forest", "harbor", "quarry", "kids", "serra"]
const PLAYER_VARIANTS := [[1.2, 0.8, false], [2.6, -0.8, true], [3.0, 0.0, false]]   # Stufe, Spur, Turbo
const RACE_TRACKS := ["azure", "city", "forest", "harbor", "serra", "fair", "quarry", "kids"]
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
	var table: Array = []
	for id in RACE_TRACKS:
		for stage in range(3):
			var res := RaceField.run_field(Circuit.load_track(id), stage)
			table.append("%-7s %d %-5s %s" % [id, stage + 1, res.weather, res.text])
			if id in MUST_FINISH:
				check(res.failed.is_empty(), "%s Stufe %d (%s): alle Gegner im Ziel – %s" % [id, stage + 1, res.weather, res.text])
				for pv in PLAYER_VARIANTS:
					var tr := Circuit.load_track(id)
					var line := tr.ai_route(float(pv[0]), float(pv[1]))
					var rv := RaceField.run_field(tr, stage, line, 300.0, bool(pv[2]))
					var tag := "P%.1f/%.1f%s" % [float(pv[0]), float(pv[1]), "T" if pv[2] else ""]
					table.append("%-7s %d %-5s %-10s %s" % [id, stage + 1, rv.weather, tag, rv.text])
					check(rv.failed.is_empty(), "%s Stufe %d (%s), Spieler %s: alle Gegner im Ziel – %s" % [id, stage + 1, rv.weather, tag, rv.text])
			else:
				for fl in res.failed:
					print("WARN: %s Stufe %d (%s): Gegner %d %s bei s %.3f (%.1f | %.1f) – Bestandsfehler der unveränderten Strecke" % [id, stage + 1, res.weather, int(fl.car), fl.why, float(fl.s), float(fl.x), float(fl.z)])
				check(res.times[0] > 0.0, "%s Stufe %d: Spieler-Ersatz im Ziel (%.2f s)" % [id, stage + 1, float(res.times[0])])
	# Kinderzimmer: zusätzlich mit dem Spieler-Ersatz auf dem Lineal (sobald die Strecke eine Wippe hat); Stufe 3 zweimal identisch.
	var kids := Circuit.load_track("kids")
	if not kids.seesaws.is_empty():
		for stage in range(3):
			var on_ruler := RaceField.run_field(Circuit.load_track("kids"), stage, kids.ai_route(2.0, 0.0, int(kids.seesaws[0].get("shortcut", 0))))
			table.append("kids*   %d %-5s %s" % [stage + 1, on_ruler.weather, on_ruler.text])
			check(on_ruler.failed.is_empty(), "kids Stufe %d, Spieler auf dem Lineal: alle Gegner im Ziel – %s" % [stage + 1, on_ruler.text])
			var fast := RaceField.run_field(Circuit.load_track("kids"), stage, kids.ai_route(2.8, 0.0, int(kids.seesaws[0].get("shortcut", 0))), 300.0, true)
			table.append("kids*T  %d %-5s %s" % [stage + 1, fast.weather, fast.text])
			check(fast.failed.is_empty(), "kids Stufe %d, Spieler 2,8 mit Turbo auf dem Lineal: alle Gegner im Ziel – %s" % [stage + 1, fast.text])
	else:
		print("INFO: kids ohne Wippe (Streckendaten folgen), Lauf auf dem Lineal entfällt")
	var once := RaceField.run_field(Circuit.load_track("kids"), 2)
	var twice := RaceField.run_field(Circuit.load_track("kids"), 2)
	check(str(once.times) == str(twice.times), "kids Stufe 3 zweimal gerechnet: identische Zeiten %s" % str(once.times))
	# Drift-Arena: der Zeitlimit-Bot (ai_route 1.0) kommt ins Ziel.
	var arena := Circuit.load_track("arena")
	var bot := RaceVehicle.new(arena, arena.ai_route(1.0))
	for tick in range(60 * 240):
		bot.step(1.0 / 60.0, false, float(tick + 1) / 60.0)
		if bot.finish_time >= 0.0 or bot.crashed:
			break
	check(bot.finish_time > 0.0 and not bot.crashed, "Drift-Arena: Zeitlimit-Bot im Ziel (%.2f s)" % bot.finish_time)
	print("Zeittabelle (S = Spieler-Ersatz, G = Gegner):")
	for row in table:
		print("  ", row)
	print("RESULT: ", checks - failures, "/", checks, " passed")
	quit(1 if failures else 0)
