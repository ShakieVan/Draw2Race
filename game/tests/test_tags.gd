extends SceneTree

# M1 „Namen und Sprechblasen“ (docs/MULTIPLAYER_RECHERCHE.md 6): Spielername im Spielstand, KI-Namen, Ereignisblasen mit
# Ratenbegrenzung, Namensschilder im Rennen (auch am Bildrand) – und vor allem: nichts davon ändert die Simulation.
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

func run() -> void:
	test_names()
	test_chatter()
	await test_race()
	print("RESULT: ", checks - failures, "/", checks, " passed")
	quit(1 if failures else 0)

func test_names() -> void:
	check(ProgressStore.clean_name("  Jörg   Müßig-Überflieger ") == "Jörg Müßig-Ü", "Name: Umlaute/ß erlaubt, Leerzeichen gekürzt, höchstens 12 Zeichen")
	check(ProgressStore.clean_name("<b>Ann</b>\n\t😀") == "bAnnb", "Name: Sonderzeichen, Steuerzeichen und Emoji fallen weg")
	check(ProgressStore.filter_name("Max ") == "Max " and ProgressStore.filter_name("ABCDEFGHIJKLMNOP").length() == 12, "Tippen: Leerzeichen am Ende bleibt, Länge begrenzt")
	var path := "user://test_tags_%s.json" % Time.get_ticks_usec()
	var store := ProgressStore.new(path)
	check(bool(store.data.show_names) and bool(store.data.bubbles), "Namen und Sprechblasen sind anfangs an")
	var hint := store.player_name()
	check(hint.begins_with("Fahrer ") and hint.length() == 9 and store.player_name() == hint, "Vorschlag „Fahrer NN“ bleibt gleich")
	store.set_player_name("  Rennsemmel ")
	store.data["bubbles"] = false
	store.save()
	var again := ProgressStore.new(path)
	check(again.player_name() == "Rennsemmel" and not bool(again.data.bubbles) and bool(again.data.show_names), "Name und Schalter werden gespeichert")
	again.set_player_name("   ")
	check(again.player_name() == hint, "Leerer Name = gemerkter Vorschlag")
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	# Anzeigenamen: KI je Karosserie, Menschen zuerst, Doppelte mit Ziffer.
	var entries := [RaceField.human_entry([], 0), RaceField.ai_entry(2.0, 1.0), RaceField.ai_entry(2.0, -1.0)]
	var names := NameTags.names_for(entries, [0, 4, 6], 0, "Anna")
	check(Array(names) == ["Anna", "Ada Apex", "Kalle Kipper"], "Ich, dann KI-Namen nach Karosserie")
	names = NameTags.names_for(entries, [0, 4, 6], 0, "Ada Apex")
	check(names[0] == "Ada Apex" and names[1] == "Ada Apex 2", "Gleicher Name: die KI bekommt die Ziffer")
	var two := [RaceField.human_entry([], 0, "Kalle Kipper"), RaceField.human_entry([], 1), RaceField.ai_entry(2.0, 1.0)]
	names = NameTags.names_for(two, [0, 1, 6], 1, "")
	check(names[0] == "Kalle Kipper" and names[1] == "Spieler 2" and names[2] == "Kalle Kipp 2", "Mehrere Menschen: Namen aus der Liste, sonst „Spieler n“")
	check(NameTags.unique_name("Abcdefghijkl", ["Abcdefghijkl"]) == "Abcdefghij 2", "Ziffer passt in 12 Zeichen")

var route: Array[Dictionary] = []

func cars_at(track: Circuit, meters: Array) -> Array:
	# Synthetische Autos (nur Zustände setzen, kein Simulationstakt): Fortschritt aus Metern, nebeneinander.
	if route.is_empty():
		route = track.ai_route(2.0, 0.0)
	var cars: Array = []
	for i in range(meters.size()):
		var v := RaceVehicle.new(track, route)
		v.progress = float(meters[i]) / track.length
		v.pos = Vector2(i, 0)
		cars.append(v)
	return cars

func put(v: RaceVehicle, meters: float) -> void:
	v.progress = meters / v.track.length

func test_chatter() -> void:
	var track := Circuit.load_track("azure")
	# A: Gedränge am Start, Überholen, Führung.
	var cars := cars_at(track, [100, 97, 94])
	var ch := RaceChatter.new()
	ch.observe(cars, [], 0.5)
	put(cars[1], 110)
	ch.observe(cars, [], 1.0)
	check(ch.active_count(1.0) == 0, "Am Start (Gedränge) keine Überhol-Blasen")
	put(cars[1], 97)
	ch.observe(cars, [], 1.5)
	put(cars[2], 98.5)
	ch.observe(cars, [], 3.0)
	var b := ch.active(2, 3.0)
	check(not b.is_empty() and b.kind == "overtake" and str(b.text) in RaceChatter.TEXTS.overtake, "Überholen erzeugt eine Blase beim Überholer")
	check(ch.active(1, 3.0).is_empty(), "Der Überholte schweigt")
	put(cars[1], 105)
	ch.observe(cars, [], 3.1)
	check(ch.active(1, 3.1).get("kind", "") == "lead", "Neue Führung: „Führung!“ verdrängt „Überholt!“")
	check(ch.active_count(3.1) == 2, "Je Auto höchstens eine Blase")
	# B: Ratenbegrenzung (Auto 2 führt weit vorn, Auto 1 und 0 tauschen immer wieder).
	cars = cars_at(track, [100, 97, 200])
	ch = RaceChatter.new()
	ch.observe(cars, [], 3.0)
	put(cars[1], 102)
	ch.observe(cars, [], 4.0)
	check(ch.active(1, 4.0).get("kind", "") == "overtake", "Überholen nach dem Start")
	put(cars[1], 98.5)
	ch.observe(cars, [], 4.5)
	put(cars[1], 102)
	ch.observe(cars, [], 5.0)
	check(float(ch.active(1, 5.0).get("born", 0.0)) == 4.0, "Laufende gleichwertige Blase wird nicht ersetzt")
	put(cars[1], 98.5)
	ch.observe(cars, [], 6.2)
	put(cars[1], 102)
	ch.observe(cars, [], 6.5)
	check(ch.active(1, 6.5).is_empty(), "Nach einer Blase schweigt das Auto bis CAR_GAP")
	put(cars[1], 98.5)
	ch.observe(cars, [], 7.2)
	put(cars[1], 102)
	ch.observe(cars, [], 7.5)
	check(float(ch.active(1, 7.5).get("born", 0.0)) == 7.5, "Nach CAR_GAP darf es wieder")
	check(not ch.active(1, 7.5 + RaceChatter.LIFE - 0.01).is_empty() and ch.active(1, 7.5 + RaceChatter.LIFE + 0.01).is_empty(), "Blase lebt LIFE Sekunden")
	# C: Wichtiger verdrängt unwichtiger; Ziel mit Platz.
	cars = cars_at(track, [100, 80, 60, 40])
	ch = RaceChatter.new()
	ch.observe(cars, [], 3.0)
	cars[0].velocity = Vector2(-10, 0)
	cars[0].heading = 0.0
	ch.observe(cars, [[0, 3, 4.0]], 4.0)
	check(ch.active(0, 4.0).get("kind", "") == "spin", "Dreher (Fahrt gegen die Blickrichtung) schlägt den gleichzeitigen Rempler")
	cars[0].crashed = true
	cars[0].wrecked = true
	ch.observe(cars, [], 4.2)
	check(ch.active(0, 4.2).get("kind", "") == "wreck" and str(ch.active(0, 4.2).text) in RaceChatter.TEXTS.wreck, "Totalschaden verdrängt den Dreher")
	ch.observe(cars, [[1, 2, 6.0]], 8.0)
	check(ch.active(1, 8.0).get("kind", "") == "contact", "Rempler: der Vordere beschwert sich")
	cars[1].finish_time = 30.0
	cars[3].finish_time = 31.0
	ch.observe(cars, [], 31.0)
	check(str(ch.active(1, 31.0).get("text", "")) == "Ziel – Platz 1" and str(ch.active(3, 31.0).get("text", "")) == "Ziel – Platz 2", "Zieleinlauf mit Platz")
	check(ch.active(1, 31.0 + RaceChatter.LIFE_LONG + 0.01).is_empty(), "Blasen verschwinden nach ihrer Lebensdauer")
	# D: höchstens MAX_ACTIVE gleichzeitig, mein Auto immer.
	var ch2 := RaceChatter.new()
	ch2.reset(5)
	for i in range(5):
		ch2.say(i, "jump", 10.0, "", 4)
	check(ch2.active_count(10.0) == RaceChatter.MAX_ACTIVE + 1 and not ch2.active(4, 10.0).is_empty() and ch2.active(3, 10.0).is_empty(),
		"Höchstens %d Blasen gleichzeitig, mein Auto immer" % RaceChatter.MAX_ACTIVE)
	# E: Turbo nur bei Menschen, Sprung nach JUMP_TIME in der Luft.
	var crowd := cars_at(track, [100, 80, 60])
	var humans := [true, false, false]
	var ch3 := RaceChatter.new()
	ch3.observe(crowd, [], 5.0, humans, 0)
	crowd[0].boosting = true
	crowd[1].boosting = true
	crowd[2].airborne = true
	ch3.observe(crowd, [], 5.1, humans, 0)
	check(ch3.active(0, 5.1).get("kind", "") == "turbo" and ch3.active(1, 5.1).is_empty(), "„Turbo!“ nur bei Menschen")
	check(ch3.active(2, 5.1).is_empty(), "Kurzer Hüpfer: keine Blase")
	ch3.observe(crowd, [], 5.1 + RaceChatter.JUMP_TIME + 0.02, humans, 0)
	check(ch3.active(2, 5.7).get("kind", "") == "jump", "Langer Sprung: Blase")

func race_run(names_on: bool, bubbles_on: bool) -> Dictionary:
	# Vorführfahrt (keine Bestenliste, kein Geist) mit 3 Gegnern, Spieler-Ersatz ai_route(2.0); Takt und Darstellung von Hand.
	app.store.data["show_names"] = names_on
	app.store.data["bubbles"] = bubbles_on
	app.store.data["ghost"] = false
	app.stage = 2
	app.start_drawing()
	app.demonstration = true
	app.recorder.route = app.track.ai_route(2.0, 0.0)
	app.recorder.complete = true
	app.begin_race()
	var dt := 1.0 / 60.0
	var seen := {"tags": 0, "own": false, "pinned": 0, "pinned_inside": true, "bubbles": 0}
	var screen: Rect2 = root.get_visible_rect()
	for tick in range(60 * 150):
		app._physics_process(dt)
		app._process(dt)
		if tick % 500 == 300:
			# Einmal ganz normal zeichnen, einmal mit weggedrehter Kamera (Autos außerhalb -> Schilder am Rand).
			var offset := Vector3(0, 0, 0) if tick % 1000 == 300 else Vector3(140, 0, 0)
			app.camera.position += offset
			await process_frame
			await process_frame
			app.camera.position -= offset
			for d in app.hud.tags.drawn:
				if d.kind == "tag":
					seen.tags += 1
					if d.car == app.me and d.text == app.store.player_name():
						seen.own = true
					if d.pinned:
						seen.pinned += 1
						if not screen.encloses(d.rect):
							seen.pinned_inside = false
				else:
					seen.bubbles += 1
		if app.phase == "result" and app.field.done():
			break
	var times: Array = []
	var poses: Array = []
	for v in app.vehicles:
		times.append(v.finish_time)
		poses.append(v.pos)
	return {"times": times, "poses": poses, "history": app.chatter.history.duplicate(), "names": app.car_names.duplicate(),
		"seen": seen, "phase": app.phase}

func test_race() -> void:
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	await process_frame
	var test_path := "user://test_tags_race_%s.json" % Time.get_ticks_usec()
	app.store = ProgressStore.new(test_path)
	app.run_record_path = test_path + ".run"
	app.store.set_player_name("Testfahrer")
	var on := await race_run(true, true)
	var off := await race_run(false, false)
	check(on.phase == "result" and off.phase == "result", "Beide Rennen zu Ende gefahren")
	check(on.times.size() == 4, "Rennen mit 3 Gegnern")
	check(on.times == off.times and on.poses == off.poses, "Namen und Sprechblasen ändern das Rennen nicht (Zeiten und Endpositionen bitgleich)")
	print("Zeiten: ", on.times)
	check(on.names[0] == "Testfahrer" and on.names.size() == 4 and not ("" in on.names), "Jedes Auto hat einen Namen, meins aus dem Spielstand")
	var finish := 0
	var kinds := {}
	for e in on.history:
		kinds[e.kind] = true
		if e.kind == "finish":
			finish += 1
	print("Blasen: ", on.history.size(), " ", kinds.keys())
	check(finish >= 1 and on.history.size() >= 2, "Im Rennen entstehen Ereignisblasen (mindestens der Zieleinlauf)")
	check(off.history.is_empty() and off.seen.tags == 0 and off.seen.bubbles == 0, "Ausgeschaltet: keine Schilder, keine Blasen")
	check(on.seen.tags >= 8 and on.seen.own, "Schilder über den Autos, meines mit meinem Namen")
	check(on.seen.pinned >= 1 and on.seen.pinned_inside, "Autos außerhalb: Schild am Bildrand, ganz im Bild")
	var rows: Array = app.sorted_results()
	check(app.hud.driver_name(app.me) == "Testfahrer" and app.hud.driver_name(1) == str(app.car_names[1]), "Ergebnisliste zeigt Namen statt DU/RIVALE")
	check(rows.size() == 4, "Ergebniszeilen für alle Autos")
	for suffix in ["", ".bak", ".tmp", ".run"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path + suffix))
