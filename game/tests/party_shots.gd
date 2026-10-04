extends SceneTree
# Kontrollbilder für den Mehrspieler „Weitergeben“ (M2b) im Handyformat: Menü, Auswahl, Einstellungen (alle drei im selben Auto),
# Garage (Autowahl mit Spielerfarbe), Übergabekarte, Zeichnen, fertige Linie, Enthüllung, Rennen bei Tag (Küste, Stufe 1) und bei
# Nacht (Stadt, Stufe 2) mit 3 Spielern im selben Auto in ihren Farben, Turboknöpfen (zwei gehalten), Namensschildern und
# Sprechblasen, dazu die Wertung. Schildgrößen wie auf dem Handy (NameTags.phone).
# Aufruf (20:9):  tools/godot_run.ps1 -Script res://tests/party_shots.gd -Resolution 2400x1080 -Timeout 240
# Bilder: user://party_<name>.png; der Spielstand der Aufnahme wird am Ende gelöscht.
const STORE := "user://party_shots_store.json"
var app: Node

func _initialize() -> void:
	call_deferred("run")

func frames(n: int) -> void:
	for i in range(n):
		await process_frame

func physics(n: int) -> void:
	for i in range(n):
		if app.paused:
			app.resume_game()   # Fokusverlust des Aufnahmefensters hält das Spiel sonst an
		await physics_frame

func shot(name: String) -> void:
	if app.paused:
		app.resume_game()
	await frames(3)
	var path := "user://party_%s.png" % name
	root.get_texture().get_image().save_png(path)
	var tags := ""
	for d in app.hud.tags.drawn:
		tags += " %s%d„%s“%s" % [d.kind[0], d.car, d.text, " (nur Schrift)" if d.get("faded", false) else ""]
	print("SHOT ", ProjectSettings.globalize_path(path), tags)

func touch(index: int, pos: Vector2, down: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = pos
	ev.pressed = down
	app._input(ev)

func draw_all(pt: PassParty, keep: int, shots: bool) -> void:
	for k in range(pt.count()):
		if shots and k == keep:
			await shot("uebergabe")
		app.party_draw()
		var route: Array[Dictionary] = app.track.ai_route(1.7 + 0.25 * k, [0.0, 0.9, -0.9][k])
		if shots and k == keep:
			app.recorder.route = route.slice(0, route.size() / 2)
			app.refresh_line()
			await shot("zeichnen")
		app.recorder.route = route
		app.recorder.complete = true
		app.line_complete()
		if shots and k == keep:
			await shot("linie_fertig")
		app.party_pass()

func race_shot(name: String, wait: int) -> void:
	# Ampel und ein Stück Rennen in Echtzeit; Spieler 1 und 2 halten ihren Turboknopf; eine Blase, falls gerade keine zu sehen ist.
	await physics(200)
	var pads: TurboPads = app.hud.pads
	touch(3, pads.rects[0].get_center(), true)
	touch(4, pads.rects[1].get_center(), true)
	await physics(wait)
	var bubble := false
	for d in app.hud.tags.drawn:
		bubble = bubble or d.kind == "bubble"
	if not bubble:
		for d in app.hud.tags.drawn:
			if d.kind == "tag" and not d.pinned and not app.field.is_human(int(d.car)):
				app.chatter.say(int(d.car), "overtake", app.race_time, "", int(d.car))
				break
		await physics(18)
	await shot(name)
	touch(3, Vector2.ZERO, false)
	touch(4, Vector2.ZERO, false)

func to_result() -> void:
	# Rest des Rennens ohne Warten (gleicher 60-Hz-Takt, nur schneller als Echtzeit).
	app.set_physics_process(false)
	for tick in range(60 * 240):
		app._physics_process(1.0 / 60.0)
		if app.phase == "result":
			break
	for tick in range(60 * 30):
		if app.field.done():
			break
		app._physics_process(1.0 / 60.0)
	app.set_physics_process(true)

func run() -> void:
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await frames(2)
	app.store = ProgressStore.new(STORE)
	app.store.data["ghost"] = false
	app.store.set_player_name("Shakie")
	NameTags.phone = true
	app.select_track("azure")
	app.show_menu()
	await frames(4)
	await shot("menue")
	app.hud.party_ui.mode_dialog()
	await shot("auswahl")
	app.hud.close_overlays()
	app.open_party()
	var pt: PassParty = app.party
	pt.add_player()
	pt.set_name(1, "Anna")
	pt.set_name(2, "Ben")
	for k in range(pt.count()):
		pt.set_car(k, 3)          # Autowahl: alle im Thunder V8, jeder in seiner Farbe
	pt.set_track("azure")
	pt.set_stage(0)
	pt.ai = 1
	app.hud.party_ui.setup_screen()
	await shot("einstellungen")
	app.party_garage(1)
	await frames(20)              # Schaufenster: Auto dreht sich ein Stück
	await shot("garage")
	app.close_garage()
	app.party_start()
	await draw_all(pt, 1, true)
	await physics(50)
	await shot("enthuellung")
	app.party_begin_race()
	await race_shot("rennen_tag", 160)
	to_result()
	await shot("wertung")
	# Nacht: Stadt, Stufe 2 (Nacht, trocken).
	app.open_party()
	pt.set_track("city")
	pt.set_stage(1)
	app.party_start()
	await draw_all(pt, -1, false)
	await physics(40)
	await shot("enthuellung_nacht")
	app.party_begin_race()
	await physics(60)
	await shot("ampel_nacht")   # Startaufstellung: Schilder dicht an dicht, fremde über eigenen Autos nur als Schrift
	await race_shot("rennen_nacht", 140)
	app.show_menu()
	await frames(2)
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(STORE + suffix):
			DirAccess.remove_absolute(STORE + suffix)
	quit()
