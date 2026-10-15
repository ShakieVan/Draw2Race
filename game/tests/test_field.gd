extends SceneTree

# Feldtest (docs/dioramen/HOEHEN_PLAN.md, Regel 1.3 und Abschnitt 9): jede Rennstrecke × 3 Herausforderungen wie im Spiel über RaceField
# (Aufstellung, Wetter der Herausforderung, Ausweichen, Kontakte, Gegner-Turbo, Wippen) mit dem Spieler-Ersatz ai_route(2.0, 0).
# Für die Höhenstrecken und die Serra ist jeder ausgeschiedene Gegner ein FAIL; auf den übrigen Rennstrecken bis 15.10.2026 ein WARN mit
# Ursache, seither im Grundlauf ebenfalls ein FAIL (Maßstab der Gegnerbalance).
# Seit 03.10.2026 (Prüfung der Nachtschicht: das Grün hing an der einen Spielerlinie) fahren die Pflichtstrecken zusätzlich mit weiteren
# Spieler-Ersatzlinien: langsam auf der Außenspur, schnell auf der Gegenspur mit Turbo (ohne Sperrzonen), am Limit mittig. Diese Linien
# rechnet der Test trocken, wie ein Mensch sie ohne Rücksicht auf Nässe zeichnet; verunglückt der Spieler, zählt nur, dass die Gegner ankommen.
const MUST_FINISH := ["forest", "harbor", "quarry", "kids", "serra"]
const PLAYER_VARIANTS := [[1.2, 0.8, false], [2.6, -0.8, true], [3.0, 0.0, false]]   # Stufe, Spur, Turbo
const RACE_TRACKS := ["azure", "city", "forest", "harbor", "serra", "fair", "quarry", "kids"]
# Gegnerbalance (15.10.2026): Gegnerzeit / Zeit des Spieler-Ersatzes je Strecke, Herausforderung und Gegner im Stand bicycle-6 (Physik vor der
# Korrektur des Vorzeichenfehlers, alter 7-m/s-Erholungsschalter; dasselbe Feld wie hier). bicycle-7 macht alle Autos 7–13 % schneller, und ein
# Mensch fährt ebenso schneller: RaceField.RIVAL_SKILL hält deshalb diese RELATIVE Schwierigkeit – je Herausforderung und Gegner im Mittel über
# die Strecken höchstens BALANCE_MEAN daneben, keine Strecke mehr als BALANCE_TRACK.
# -1 = Artefakt des alten Stands, kein Maßstab (jeweils gegen die Fahrt allein bzw. die Auswertung der Takte belegt):
#   Jahrmarkt: der Spieler-Ersatz selbst hing 5–6 s im 7-m/s-Schalter (Landung neben der gekrümmten Linie über die Lücke), die Gegner 2–14 s.
#   Stadt Stufe 2 G1: Kontakt und Schalter, 1,6 s langsamer als allein. Stadt Stufe 3 G1: Stufe 3,0 im Regen überzogen, im Schalter
#   langsamer als die Gegner mit 2,3 und 2,7. Kinderzimmer Stufe 3 G2: Dreher (91° Schwimmwinkel, 11,6 s im Schalter).
const B6_RATIO := {
	"azure": [[1.0646], [1.0165, 0.9628], [0.9828, 0.9202, 1.0045]],
	"city": [[1.0534], [-1.0, 0.9730], [-1.0, 0.9429, 1.0100]],
	"forest": [[1.0259], [0.9969, 1.0114], [0.9756, 0.9766, 1.0041]],
	"harbor": [[0.9958], [0.9791, 1.0303], [0.9596, 1.0129, 0.9977]],
	"serra": [[1.0260], [0.9853, 1.0203], [0.9622, 0.9848, 0.9890]],
	"fair": [[-1.0], [-1.0, -1.0], [-1.0, -1.0, -1.0]],
	"quarry": [[1.0621], [1.0216, 0.9852], [0.9864, 0.9548, 1.0208]],
	"kids": [[1.0374], [1.0123, 0.9940], [0.9872, -1.0, 0.9951]],
}
const BALANCE_MEAN := 0.01
const BALANCE_TRACK := 0.03
# Über den Sieg (Platz 1) entscheidet der beste Gegner eines Rennens: Bezug ist der schnellste gültige Gegner aus B6_RATIO. In der Stadt
# (Stufe 2 und 3) ist G1 Artefakt, aber auch in bicycle-7 klar langsamer als G2 (1,027 bzw. 0,992 gegen 0,967 bzw. 0,946) – G2 bleibt
# dort der Maßstab. Unbestimmt und deshalb ausgenommen: Jahrmarkt (alles Artefakt) und Kinderzimmer Stufe 3 (Dreher des G2), Schlüssel
# "Strecke Stufe" mit Stufe ab 0.
const BEST_UNDEFINED := ["kids 2"]
var failures := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)
	else:
		print("PASS: ", message)

func check_balance(ratios: Dictionary) -> Array:
	# Gegnerbalance gegen B6_RATIO: je Herausforderung und Gegner das Mittel der Verhältnisse und die größte Abweichung einer Strecke,
	# dazu je Herausforderung der beste Gegner. Jede Strecke mit gültigem Bezug muss mitzählen: Ein Ausfall (Gegner oder Spieler-Ersatz)
	# fiele sonst als fehlender Summand unbemerkt aus dem Mittel.
	var lines: Array = []
	for stage in range(3):
		for k in range(stage + 1):
			var sum_now := 0.0
			var sum_ref := 0.0
			var n := 0
			var expected := 0
			var worst := 0.0
			var worst_id := "-"
			var parts: Array = []
			for id in RACE_TRACKS:
				var ref := float(B6_RATIO[id][stage][k])
				var now := float(ratios.get("%s %d %d" % [id, stage, k], -1.0))
				parts.append("%s %.3f/%s" % [id.substr(0, 4), now, ("%.3f" % ref) if ref > 0.0 else "Artefakt"])
				if ref > 0.0:
					expected += 1
				if ref <= 0.0 or now <= 0.0:
					continue
				sum_now += now
				sum_ref += ref
				n += 1
				if absf(now / ref - 1.0) > absf(worst):
					worst = now / ref - 1.0
					worst_id = id
			var mean_dev := (sum_now / sum_ref - 1.0) if n > 0 else 1.0
			var skill := RaceField.ai_skill(stage, k)
			check(n == expected and absf(mean_dev) <= BALANCE_MEAN, "Balance Stufe %d G%d (Stärke %.1f): Gegner/Spieler-Ersatz im Mittel %.4f gegen %.4f in bicycle-6 (%+.2f %%, ≤ %.0f %%; %d von %d Strecken)"
				% [stage + 1, k + 1, skill, sum_now / maxi(n, 1), sum_ref / maxi(n, 1), mean_dev * 100.0, BALANCE_MEAN * 100.0, n, expected])
			check(absf(worst) <= BALANCE_TRACK, "Balance Stufe %d G%d: keine Strecke mehr als %.0f %% neben bicycle-6 (größte Abweichung %s %+.2f %%)"
				% [stage + 1, k + 1, BALANCE_TRACK * 100.0, worst_id, worst * 100.0])
			lines.append("Stufe %d G%d %.1f: %s" % [stage + 1, k + 1, skill, " | ".join(parts)])
		# Bester Gegner: jetzt über alle Gegner (heute gibt es keine Artefakte), Bezug der schnellste gültige aus B6_RATIO.
		var best_now := 0.0
		var best_ref := 0.0
		var nb := 0
		var nb_expected := 0
		var best_worst := 0.0
		var best_worst_id := "-"
		var best_parts: Array = []
		for id in RACE_TRACKS:
			var ref := INF
			for k in range(stage + 1):
				if float(B6_RATIO[id][stage][k]) > 0.0:
					ref = minf(ref, float(B6_RATIO[id][stage][k]))
			if ref == INF or ("%s %d" % [id, stage]) in BEST_UNDEFINED:
				continue
			nb_expected += 1
			var now := INF
			for k in range(stage + 1):
				now = minf(now, float(ratios.get("%s %d %d" % [id, stage, k], INF)))
			var complete := true
			for k in range(stage + 1):
				complete = complete and ratios.has("%s %d %d" % [id, stage, k])
			best_parts.append("%s %.3f/%.3f" % [id.substr(0, 4), now, ref])
			if not complete:
				continue
			best_now += now
			best_ref += ref
			nb += 1
			if absf(now / ref - 1.0) > absf(best_worst):
				best_worst = now / ref - 1.0
				best_worst_id = id
		var best_dev := (best_now / best_ref - 1.0) if nb > 0 else 1.0
		check(nb == nb_expected and absf(best_dev) <= BALANCE_MEAN, "Balance Stufe %d, bester Gegner/Spieler-Ersatz im Mittel %.4f gegen %.4f in bicycle-6 (%+.2f %%, ≤ %.0f %%; %d von %d Strecken)"
			% [stage + 1, best_now / maxi(nb, 1), best_ref / maxi(nb, 1), best_dev * 100.0, BALANCE_MEAN * 100.0, nb, nb_expected])
		check(absf(best_worst) <= BALANCE_TRACK, "Balance Stufe %d, bester Gegner: keine Strecke mehr als %.0f %% neben bicycle-6 (größte Abweichung %s %+.2f %%)"
			% [stage + 1, BALANCE_TRACK * 100.0, best_worst_id, best_worst * 100.0])
		lines.append("Stufe %d bester Gegner: %s" % [stage + 1, " | ".join(best_parts)])
	return lines

func _init() -> void:
	var table: Array = []
	var ratios := {}   # "Strecke Stufe Gegner" -> Gegnerzeit / Zeit des Spieler-Ersatzes (Grundlauf, Wetter der Herausforderung)
	for id in RACE_TRACKS:
		for stage in range(3):
			var res := RaceField.run_field(Circuit.load_track(id), stage)
			table.append("%-7s %d %-5s %s" % [id, stage + 1, res.weather, res.text])
			for k in range(res.times.size() - 1):
				if float(res.times[0]) > 0.0 and float(res.times[k + 1]) > 0.0:
					ratios["%s %d %d" % [id, stage, k]] = float(res.times[k + 1]) / float(res.times[0])
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
					print("WARN: %s Stufe %d (%s): Gegner %d %s bei s %.3f (%.1f | %.1f)" % [id, stage + 1, res.weather, int(fl.car), fl.why, float(fl.s), float(fl.x), float(fl.z)])
				# Seit 15.10.2026 (bicycle-7, Gegnerbalance) auch hier Pflicht im Grundlauf: Er ist der Maßstab der Balance, und mit den heutigen
				# Werten kommen alle Gegner an (alle Rennstrecken × Stufen × trocken, Regen, Schnee geprüft). Die weiteren Spielerlinien bleiben
				# den Pflichtstrecken vorbehalten (Laufzeit).
				check(res.failed.is_empty(), "%s Stufe %d (%s): alle Gegner im Ziel (Grundlauf) – %s" % [id, stage + 1, res.weather, res.text])
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
	var balance := check_balance(ratios)
	print("Zeittabelle (S = Spieler-Ersatz, G = Gegner):")
	for row in table:
		print("  ", row)
	print("Gegnerbalance, Gegnerzeit / Spieler-Ersatz jetzt/bicycle-6:")
	for row in balance:
		print("  ", row)
	print("RESULT: ", checks - failures, "/", checks, " passed")
	quit(1 if failures else 0)
