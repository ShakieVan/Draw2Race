extends SceneTree

# Mehrspieler „Weitergeben“ (M2b): 2, 3 und 4 Spieler auf einem Handy, über die echte Oberfläche bedient.
#   Menü → Mehrspieler → Auf einem Handy → Einstellungen → Garage je Spieler (alle dasselbe Auto, jeder seine Farbe) → je Spieler
#   Übergabekarte (verdeckt alles) → Zeichnen → Linie fertig → Enthüllung (alle Linien in Spielerfarben) → Rennen mit Turboknöpfen
#   (mehrere Finger) → Wertung → Revanche → Menü. Spielerfarben: Lack, Schild, Lichtkranz, Turboknopf, Linie; KI-Farben heben sich ab.
# Geprüft wird außerdem: Der Spielstand (Datei) ist danach Byte für Byte unverändert, es entstehen weder Geist noch letzte Fahrt;
# das Rennen ist deterministisch (Nachrechnen ohne Darstellung aus Teilnehmerliste und Turbo-Protokoll ergibt dieselben Zeiten);
# ein Einzelspieler-Rennen danach ist bitgleich mit demselben Rennen davor; die Zurück-Taste führt in jedem Schritt sinnvoll weiter.
const DT := 1.0 / 60.0
var failures := 0
var checks := 0
var app: Node

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)
	else:
		print("PASS: ", message)

func _initialize() -> void:
	call_deferred("run")

func ghost_listing() -> String:
	# Geisterdateien samt Inhalt (Prüfsumme): unverändert = nichts geschrieben.
	var out := ""
	if DirAccess.dir_exists_absolute("user://ghosts"):
		for f in DirAccess.get_files_at("user://ghosts"):
			out += "%s:%s " % [f, FileAccess.get_md5("user://ghosts/" + f)]
	return out

func buttons(prefix: String) -> Array:
	var out: Array = []
	for b in app.hud.content.find_children("*", "Button", true, false):
		if b.is_inside_tree() and not b.is_queued_for_deletion() and (b as Button).text.begins_with(prefix):
			out.append(b)
	return out

func named(node_name: String) -> Node:
	var found: Array = app.hud.content.find_children(node_name, "", true, false)
	for n in found:
		if not n.is_queued_for_deletion():
			return n
	return null

func press(prefix: String) -> bool:
	var list := buttons(prefix)
	if list.size() != 1 or (list[0] as Button).disabled:
		printerr("Knopf „%s“: %d gefunden" % [prefix, list.size()])
		return false
	(list[0] as Button).pressed.emit()
	return true

func press_named(node_name: String) -> bool:
	var b := named(node_name) as Button
	if b == null:
		printerr("Knopf %s fehlt" % node_name)
		return false
	b.pressed.emit()
	return true

func texts() -> Array:
	var out: Array = []
	for l in app.hud.content.find_children("*", "Label", true, false):
		if not l.is_queued_for_deletion():
			out.append((l as Label).text)
	return out

func any_text(fragment: String) -> bool:
	for t in texts():
		if str(t).contains(fragment):
			return true
	return false

func painted(model: Node3D, c: Color) -> bool:
	# Lack des Modells in Farbe c: Lack-Shader (Premium) bzw. leuchtender Lack der Menschen (Premium und Klötzchen-Grafik).
	if model.has_meta("paint_shader"):
		return (model.get_meta("paint_shader") as ShaderMaterial).get_shader_parameter("paint_color") == c
	if model.has_meta("paint"):
		return (model.get_meta("paint") as StandardMaterial3D).emission == c
	return false

func garage_pick(pt: PassParty, k: int, car: int, colour: int) -> void:
	# Garage von Spieler k über die Oberfläche: Auto mit den Pfeilen auf car stellen, Farbe colour wählen (−1 = behalten), Fertig.
	check(press_named("PlayerCar%d" % (k + 1)) and app.phase == "party_garage" and named("GarageCard") != null, "Garage für Spieler %d geöffnet" % (k + 1))
	var who := named("GarageWho") as Label
	check(who != null and who.text == pt.names()[k] and is_instance_valid(app.hud.showcase_car), "Garage zeigt Spieler %d und das drehende Auto" % (k + 1))
	if app.hud.showcase_car.has_meta("paint_shader"):
		check(painted(app.hud.showcase_car, pt.color(k)), "Auto in der Garage in der Spielerfarbe lackiert")
	var steps := 0
	while int(pt.players[k].car) != car and steps < RaceVehicle.CARS.size():
		press_named("CarNext")
		steps += 1
	check(int(pt.players[k].car) == car and (named("CarName") as Label).text == str(RaceVehicle.CARS[car].name) and app.phase == "party_garage",
		"Spieler %d wählt %s (auch wenn es ein anderer fährt)" % [k + 1, RaceVehicle.CARS[car].name])
	for j in range(pt.count()):
		if j != k:
			var other := named("Swatch%d" % pt.color_index(j)) as Button
			check(other != null and other.disabled, "Farbe von Spieler %d ist in der Garage von Spieler %d gesperrt" % [j + 1, k + 1])
	if colour >= 0:
		check(press_named("Swatch%d" % colour) and pt.color_index(k) == colour and (named("ColorName") as Label).text.begins_with(PlayerColors.color_name(colour)),
			"Spieler %d wählt die Farbe %s" % [k + 1, PlayerColors.color_name(colour)])
	if k == 0:
		app.go_back()
		check(app.phase == "party_setup" and named("PlayerCar1") != null, "Zurück-Taste in der Garage: Einstellungen, Wahl bleibt")
	else:
		check(press_named("GarageDone") and app.phase == "party_setup", "Fertig: zurück zu den Einstellungen")
	var button := named("PlayerCar%d" % (k + 1)) as Button
	check(button != null and button.text.begins_with(str(RaceVehicle.CARS[car].name)), "Einstellungen zeigen das gewählte Auto")

func lines_shown() -> int:
	var n := 1 if app.world.line_mesh.mesh != null else 0
	for node in app.world.extra_lines:
		if is_instance_valid(node) and node.mesh != null:
			n += 1
	return n

func solo_race() -> Array:
	# Einzelspieler-Rennen wie im Spiel (Herausforderung 3, drei Rivalen), als Vorführfahrt: schreibt nichts in den Spielstand.
	app.stage = 2
	app.start_drawing()
	app.demonstration = true
	app.recorder.route = app.track.ai_route(1.8)
	app.recorder.complete = true
	app.line_complete()
	for tick in range(12000):
		app._physics_process(DT)
		if app.phase == "result" and app.field.done():
			break
	var out: Array = []
	for v in app.vehicles:
		out.append([v.finish_time, v.pos, v.heading])
	return out

func replay(entries: Array, contacts: bool, logs: Array, drift: bool, limit: float) -> Array:
	# Dasselbe Rennen ohne Darstellung: Teilnehmerliste, Berührungen und Turbo-Protokoll; Ergebnisphase wie main.gd (alle Menschen im
	# Ziel oder ausgeschieden, nach dem Absturz 1,6 s bzw. aus dem Looping 2,4 s; Drift: Zeitlimit).
	var f := RaceField.new(Circuit.load_track(app.track_id))
	f.setup_entries(entries)
	f.contacts = contacts
	var inputs: Array[bool] = []
	inputs.resize(f.cars.size())
	var wait: Array[float] = []
	wait.resize(f.cars.size())
	var time := 0.0
	var phase := "race"
	for tick in range(60 * 300):
		time += DT
		if phase == "race":
			for i in range(f.cars.size()):
				inputs[i] = f.is_human(i) and RaceField.replay_turbo(logs[i], time)
			f.step_inputs(DT, time, inputs, "race")
			var done := true
			for i in f.human_indices():
				var v := f.cars[i]
				if v.crashed:
					wait[i] += DT
				if not (v.finish_time >= 0.0 or wait[i] > (2.4 if v.loop_fall else 1.6)):
					done = false
			if done or (drift and time > limit):
				phase = "result"
		else:
			f.step(DT, time, false, "result")
		if f.done() or (phase == "result" and drift):
			break
	var out: Array = []
	for v in f.cars:
		out.append(v.finish_time)
	return out

func draw_turns(pt: PassParty, names: Array, redraw_turn: int) -> void:
	# Alle Spieler nacheinander: Übergabekarte prüfen, antippen, Linie „zeichnen“, weitergeben.
	for k in range(pt.count()):
		check(app.phase == "handover" and pt.turn == k, "Übergabekarte vor Linie %d" % (k + 1))
		var title := named("HandoverTitle") as Label
		var hint := named("HandoverHint") as Label
		var want_hint := "Handy nehmen, dann tippen" if k == 0 else "Handy weitergeben, dann tippen"
		check(title != null and title.text == "Spieler %d: %s" % [k + 1, names[k]] and hint != null and hint.text == want_hint,
			"Karte: „%s – %s“" % [title.text if title else "?", hint.text if hint else "?"])
		check(lines_shown() == 0 and not app.world.visible, "Karte verdeckt alle Linien (keine Linie, Strecke ausgeblendet)")
		app.hud.party_ui.card_shown_at = Time.get_ticks_msec()
		press_named("HandoverTap")
		check(app.phase == "handover", "Tipp gleich nach dem Erscheinen zählt nicht (Finger des Vorgängers)")
		app.hud.party_ui.card_shown_at = -100000
		press_named("HandoverTap")
		check(app.phase == "draw" and app.recorder.route.is_empty() and lines_shown() == 0, "Spieler %d zeichnet auf leerer Strecke" % (k + 1))
		var chip := named("DrawChip")
		check(chip != null and any_text("Spieler %d: %s" % [k + 1, names[k]]), "Zeichenansicht zeigt, wer zeichnet")
		var route: Array[Dictionary] = app.track.ai_route(1.5 + 0.3 * k, [0.0, 0.8, -0.8, 0.4][k])
		if k == redraw_turn:
			# Neu zeichnen (Fußleiste) beginnt die eigene Linie von vorn, der Zug bleibt.
			app.recorder.route = route.slice(0, 30)
			press("Neu zeichnen")
			check(app.phase == "draw" and app.recorder.route.is_empty() and pt.turn == k, "Neu zeichnen: leere Linie, derselbe Spieler")
		app.recorder.route = route
		app.recorder.complete = true
		app.line_complete()
		check(app.phase == "drawn" and lines_shown() == 1 and (pt.routes[k] as Array).size() == route.size(), "Linie %d fertig, nur die eigene zu sehen" % (k + 1))
		if k == 0:
			app.go_back()
			check(app.paused and app.hud.overlay_open(), "Zurück bei fertiger Linie: Pause")
			app.go_back()
			check(not app.paused and app.phase == "drawn" and named("PassButton") != null, "Zurück in der Pause: weiter, Linie bleibt")
		press_named("PassButton")

func party_round(n: int, track_id: String, stage: int, ai: int, contacts: bool, names: Array, fresh: bool) -> void:
	var solo_track: String = app.track_id
	var solo_stage: int = app.stage
	app.show_menu()
	check(press("Mehrspieler"), "Menü hat „Mehrspieler“")
	var wlan := buttons("Im WLAN")
	check(wlan.size() == 1 and not (wlan[0] as Button).disabled, "„Im WLAN“ ist wählbar (M3)")
	app.go_back()
	await process_frame
	check(app.phase == "menu" and not app.hud.overlay_open(), "Zurück schließt die Auswahl")
	press("Mehrspieler")
	check(press("Auf einem Handy"), "Auswahl „Auf einem Handy (Weitergeben)“")
	check(app.phase == "party_setup" and app.party != null, "Einstellungen geöffnet")
	var pt: PassParty = app.party
	while pt.count() > 2:
		pt.remove_player(pt.count() - 1)
	app.hud.party_ui.setup_screen()
	if fresh:
		check(pt.count() == 2 and str(pt.players[0].name) == app.store.player_name() and pt.names()[1] == "Spieler 2" and int(pt.players[0].car) == app.car_choice,
			"Vorbelegt: eigener Name und Auto, „Spieler 2“")
	while pt.count() < n:
		press("+  Spieler")
	check(pt.count() == n and buttons("+  Spieler").size() == (0 if n == 4 else 1), "%d Spieler" % n)
	for k in range(n):
		var edit := named("PlayerName%d" % (k + 1)) as LineEdit
		edit.text = str(names[k])
		edit.text_changed.emit(edit.text)
		edit.text_submitted.emit(edit.text)
	# Autowahl: alle dasselbe Auto (je Runde ein anderes), jeder seine Farbe; Spieler 2 nimmt Orange statt der Vorgabe.
	var same_car: int = {2: 3, 3: 6, 4: 5}[n]
	if fresh:
		check(int(pt.players[1].car) == int(pt.players[0].car), "Neuer Spieler fährt vorbelegt dasselbe Auto")
	for k in range(n):
		garage_pick(pt, k, same_car, 4 if k == 1 and n == 2 else -1)
	var cars := {}
	var colours := {}
	for k in range(n):
		cars[int(pt.players[k].car)] = true
		colours[pt.color_index(k)] = true
	check(cars.size() == 1 and colours.size() == n, "Alle %d Spieler im selben Auto (%s), jeder in eigener Farbe %s" % [n, RaceVehicle.CARS[same_car].name,
		str(range(n).map(func(k): return PlayerColors.color_name(pt.color_index(k))))])
	# Belegte Farbe gewünscht (die von Spieler 1): der Letzte bekommt die nächste freie in Palettenfolge.
	var expect := pt.color_index(0)
	while expect in pt.taken_colors(n - 1):
		expect = (expect + 1) % PlayerColors.count()
	pt.set_color(n - 1, pt.color_index(0))
	check(pt.color_index(n - 1) == expect and expect != pt.color_index(0), "Belegte Farbe gewünscht → nächste freie (%s)" % PlayerColors.color_name(expect))
	var unique_after := {}
	for k in range(n):
		unique_after[pt.color_index(k)] = true
	check(unique_after.size() == n, "Farben bleiben eindeutig")
	press(RaceHUD.SHORT_NAMES[track_id])
	press("Stufe %d" % (stage + 1))
	if not pt.is_drift():
		press("%d" % ai)
		var toggles: Array = app.hud.content.find_children("*", "CheckButton", true, false)
		for t in toggles:
			if (t as CheckButton).text.begins_with("Berührungen"):
				(t as CheckButton).button_pressed = contacts
	check(pt.track_id == track_id and pt.stage == stage and pt.ai == (0 if pt.is_drift() else ai) and (pt.is_drift() or pt.contacts == contacts), "Strecke, Stufe, KI und Berührungen eingestellt")
	var shown := pt.names()
	if n == 3:
		check(shown[1] == "Anna" and shown[2] == "Anna 2", "Gleiche Namen bekommen eine Ziffer %s" % str(shown))
	check(press("Los"), "Start")
	check(app.track_id == track_id and app.stage == stage, "Strecke und Herausforderung der Runde geladen")
	draw_turns(pt, shown, 1)
	check(app.phase == "reveal" and lines_shown() == n and app.world.visible, "Enthüllung: alle %d Linien zugleich" % n)
	if n == 3:
		press_named("RevealTap")
	else:
		for tick in range(int(PassParty.REVEAL_TIME * 60.0) + 2):
			app._physics_process(DT)
	check(app.phase == "countdown", "Nach der Enthüllung: Ampel")
	var field: RaceField = app.field
	var total := n + (0 if pt.is_drift() else ai)
	check(field.human_count() == n and app.vehicles.size() == total and field.contacts == (contacts and not pt.is_drift()), "%d Menschen + %d KI, Berührungen %s" % [n, total - n, "an" if field.contacts else "aus"])
	var names_ok := true
	for k in range(n):
		names_ok = names_ok and app.car_names[pt.slot_of(k)] == shown[k] and field.is_human(pt.slot_of(k))
	check(names_ok and app.me == pt.slot_of(0), "Namen je Startplatz, mein Auto = Spieler 1")
	check(app.models[pt.slot_of(n - 1)].has_node("Halo"), "Jeder Mensch mit Lichtkranz")
	# Spielerfarben im Rennen: Lack, Schild, Lichtkranz je Mensch; die KI behält ihre Autofarbe, die sich von allen abhebt.
	var paint_ok := true
	for k in range(n):
		var model: Node3D = app.models[pt.slot_of(k)]
		var halo := (model.get_node("Halo") as MeshInstance3D).material_override as StandardMaterial3D
		paint_ok = paint_ok and int(app.field.entries[pt.slot_of(k)].car) == same_car and painted(model, pt.color(k)) and model.get_meta("tag_color") == pt.color(k) \
			and Color(halo.albedo_color, 1.0).is_equal_approx(pt.color(k).lightened(0.25))   # Deckkraft pulsiert
	check(paint_ok, "Gleiches Auto, je Mensch Lack, Schild und Lichtkranz in seiner Farbe")
	var looks: Array = app.car_looks()
	var ai_ok := true
	var ai_seen := {}
	for i in range(app.vehicles.size()):
		if field.is_human(i):
			continue
		ai_seen[int(looks[i])] = true
		var ai_color := Color(RaceVehicle.CARS[int(looks[i])].color)
		ai_ok = ai_ok and app.models[i].get_meta("tag_color") == ai_color
		for k in range(n):
			ai_ok = ai_ok and PlayerColors.distance(ai_color, pt.color(k)) >= PlayerColors.CLASH
	check(ai_ok and ai_seen.size() == total - n, "KI in Autofarben, deutlich anders als alle Spielerfarben %s" % str(looks))
	check(lines_shown() == n, "Im Rennen alle Linien der Menschen sichtbar")
	var pads: TurboPads = app.hud.pads
	var screen: Rect2 = root.get_visible_rect()
	var pads_ok: bool = pads.visible and pads.rects.size() == n
	for a in range(pads.rects.size()):
		pads_ok = pads_ok and screen.encloses(pads.rects[a])
		for b in range(a + 1, pads.rects.size()):
			pads_ok = pads_ok and not pads.rects[a].intersects(pads.rects[b])
	check(pads_ok, "%d Turboknöpfe, getrennt, ganz im Bild" % n)
	var pad_colours_ok: bool = pads.colors.size() == n
	for k in range(mini(n, pads.colors.size())):
		pad_colours_ok = pad_colours_ok and pads.colors[k] == pt.color(k)
	check(pad_colours_ok, "Turboknöpfe in den Spielerfarben")
	for tick in range(185):
		app._physics_process(DT)
	check(app.phase == "race", "Rennen läuft")
	# Zwei Finger zugleich: Spieler 2 und Spieler 1 halten ihren Knopf; Spieler 3 (falls da) nicht.
	var p2 := pt.slot_of(1)
	var p1 := pt.slot_of(0)
	var t1 := InputEventScreenTouch.new()
	t1.index = 3
	t1.pressed = true
	t1.position = pads.rects[1].get_center()
	app._input(t1)
	var t2 := InputEventScreenTouch.new()
	t2.index = 4
	t2.pressed = true
	t2.position = pads.rects[0].get_center()
	app._input(t2)
	check(app.pad_held.get(p2, false) and app.pad_held.get(p1, false) and app.pad_held.size() == 2, "Zwei Finger halten zwei Turboknöpfe")
	for tick in range(90):
		app._physics_process(DT)
	var up := t1.duplicate() as InputEventScreenTouch
	up.pressed = false
	app._input(up)
	check(not app.pad_held.get(p2, false) and app.pad_held.get(p1, false), "Loslassen gibt nur den eigenen Knopf frei")
	up = t2.duplicate() as InputEventScreenTouch
	up.pressed = false
	app._input(up)
	var logs_ok: bool = not (field.turbo_log[p1] as Array).is_empty() and not (field.turbo_log[p2] as Array).is_empty()
	if n >= 3:
		logs_ok = logs_ok and (field.turbo_log[pt.slot_of(2)] as Array).is_empty()
	check(logs_ok, "Turbo wirkt je Spieler auf sein Auto")
	# Kurz zeichnen lassen: Schilder der Menschen als eigene, kein Schild unter einem Turboknopf.
	await process_frame
	await process_frame
	var tags_ok := true
	var own_tags := 0
	for d in app.hud.tags.drawn:
		if d.kind == "tag" and field.is_human(int(d.car)):
			own_tags += 1
		for r in pads.rects:
			if d.kind == "tag" and (d.rect as Rect2).intersects(r):
				tags_ok = false
	print("INFO: Schilder ", app.hud.tags.drawn.size(), ", davon Menschen ", own_tags)
	check(tags_ok, "Schilder weichen den Turboknöpfen aus")
	for tick in range(10800):
		app._physics_process(DT)
		if app.phase == "result":
			break
	check(app.phase == "result", "Wertung, wenn alle Menschen fertig sind")
	var all_text := " ".join(texts())
	check(not all_text.contains("Gold") and not all_text.contains("Bestenliste") and not all_text.contains("BESTZEIT"), "Wertung ohne Gold und Bestenliste")
	var rows_ok := true
	for k in range(n):
		rows_ok = rows_ok and any_text(shown[k])
	check(rows_ok and named("RematchButton") != null and named("MenuButton") != null and named("ResultTitle") != null, "Wertung mit allen Namen, Revanche und Zurück zum Menü")
	# Determinismus: dasselbe Rennen ohne Darstellung nachgerechnet.
	var entries: Array = field.entries.duplicate(true)
	var logs: Array = field.turbo_log.duplicate(true)
	var drift: bool = pt.is_drift()
	var limit: float = app.drift_limit() if drift else 0.0
	for tick in range(6000):
		if field.done() or drift:
			break
		app._physics_process(DT)
	var live: Array = []
	for v in app.vehicles:
		live.append(v.finish_time)
	var again := replay(entries, field.contacts, logs, drift, limit)
	check(str(live) == str(again), "Deterministisch: nachgerechnet gleich %s" % str(live))
	# Spielerfarben sind reine Darstellung: ohne "paint" in der Teilnehmerliste dasselbe Rennen.
	var plain: Array = []
	for e in entries:
		var c: Dictionary = (e as Dictionary).duplicate()
		c.erase("paint")
		plain.append(c)
	check(entries.any(func(e): return e.has("paint")) and str(replay(plain, field.contacts, logs, drift, limit)) == str(live), "Spielerfarben ändern das Rennen nicht")
	if drift:
		var scores_ok := true
		var rows: Array = app.party_rows()
		for i in range(1, rows.size()):
			scores_ok = scores_ok and (not rows[i].in_time or rows[i - 1].in_time) and (rows[i].in_time != rows[i - 1].in_time or rows[i].score <= rows[i - 1].score)
		check(scores_ok and any_text("DRIFT-WERTUNG") and rows.size() == n, "Drift: alle gleichzeitig, nach Punkten gewertet")
	# Revanche: gleiche Einstellungen, neue Linien, Sieger startet hinten.
	var last: Array = pt.last_ranking.duplicate()
	check(press_named("RematchButton"), "Revanche")
	var reversed_ok := pt.grid.size() == n
	for k in range(n):
		reversed_ok = reversed_ok and pt.grid[k] == last[n - 1 - k]
	check(app.phase == "handover" and pt.turn == 0 and pt.routes.all(func(r): return (r as Array).is_empty()) and reversed_ok and pt.track_id == track_id,
		"Revanche: neu zeichnen, Aufstellung umgekehrt %s → %s" % [str(last), str(pt.grid)])
	app.go_back()
	check(app.paused and app.phase == "handover", "Zurück auf der Übergabekarte: Pause")
	app.go_back()
	check(not app.paused and named("HandoverTitle") != null, "Zurück in der Pause: Karte wieder da")
	if n == 2:
		# Zweites Rennen ganz durchfahren.
		draw_turns(pt, shown, -1)
		for tick in range(int(PassParty.REVEAL_TIME * 60.0) + 2):
			app._physics_process(DT)
		for tick in range(12000):
			app._physics_process(DT)
			if app.phase == "result":
				break
		check(app.phase == "result" and pt.races == 2 and app.me == pt.slot_of(0), "Revanche gefahren (Rennen %d)" % pt.races)
		app.go_back()
		check(app.phase == "party_setup" and app.party == pt and pt.count() == n, "Zurück in der Wertung: Einstellungen (bleiben erhalten)")
		app.go_back()
		check(app.phase == "menu" and app.party == null, "Zurück in den Einstellungen: Menü")
	else:
		app.show_menu()
	check(app.track_id == solo_track and app.stage == solo_stage, "Danach gelten wieder Strecke und Herausforderung des Einzelspielers")

func run() -> void:
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	await process_frame
	var test_path := "user://test_party_%s.json" % Time.get_ticks_usec()
	app.store = ProgressStore.new(test_path)
	app.run_record_path = test_path + ".run"
	app.store.set_player_name("Shakie")
	app.store.data["ghost"] = false
	app.store.result("azure", 0, 0, 25.5, true)   # etwas Fortschritt im Spielstand
	app.store.save()
	app.select_track("azure")
	app.stage = 0
	var car_before: int = app.car_choice
	var md5 := FileAccess.get_md5(test_path)
	var bak := FileAccess.get_md5(test_path + ".bak")
	var run_md5 := FileAccess.get_md5(test_path + ".run")
	var gold: Array = app.store.data.gold.duplicate()
	var best: Dictionary = app.store.data.best.duplicate(true)
	var times: Dictionary = app.store.data.times.duplicate(true)
	var ghost_dir := ProjectSettings.globalize_path("user://ghosts")
	var ghosts_before := ghost_listing()
	var before := solo_race()
	app.show_menu()
	app.stage = 0
	await party_round(2, "city", 1, 2, false, ["Anna", "Ben"], true)
	await party_round(3, "kids", 2, 1, true, ["Shakie", "Anna", "Anna"], false)
	await party_round(4, "arena", 0, 0, false, ["Ada", "Bo", "Cem", "Dana"], false)
	check(md5 != "" and FileAccess.get_md5(test_path) == md5 and FileAccess.get_md5(test_path + ".bak") == bak, "Spielstand-Datei (und Sicherung) Byte für Byte unverändert")
	check(app.store.data.gold == gold and app.store.data.best == best and app.store.data.times == times, "Kein Gold, keine Bestzeit, keine Bestenliste aus dem Mehrspieler")
	check(ghost_listing() == ghosts_before and FileAccess.get_md5(test_path + ".run") == run_md5, "Kein Geist und keine letzte Fahrt aus dem Mehrspieler (%s)" % ghost_dir)
	check(app.car_choice == car_before and app.party == null and app.solo() and app.track_id == "azure", "Einzelspieler-Auswahl unverändert")
	var after := solo_race()
	check(str(before) == str(after) and before.size() == 4, "Einzelspieler nach dem Mehrspieler bitgleich wie davor %s" % str(before.map(func(r): return r[0])))
	check(FileAccess.get_md5(test_path) == md5 and ghost_listing() == ghosts_before, "Vorführfahrten schreiben ebenfalls nichts")
	for suffix in ["", ".bak", ".tmp", ".run"]:
		if FileAccess.file_exists(test_path + suffix):
			DirAccess.remove_absolute(test_path + suffix)
	app.queue_free()
	await process_frame
	print("RESULT: ", checks - failures, "/", checks, " passed")
	quit(1 if failures else 0)
