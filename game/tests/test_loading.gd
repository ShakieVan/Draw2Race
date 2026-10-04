extends SceneTree
# Laden im Hintergrund (04.10.2026): Lichtkarte (LightBake) bitgleich zur Rechnung am Stück, Rauschtexturen gleich NoiseTexture2D,
# Welt aus build_async gleich der aus build(), Ablauf in main.gd (Knöpfe „Strecke lädt …“, neue Wahl während des Ladens, Zurück zur
# gezeigten Welt, Zeichnen/Vorführfahrt erst mit fertiger Welt, Programmende mitten im Laden).

var failures := 0
var checks := 0

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
	var only := OS.get_environment("PART")      # nur zur Fehlersuche: light, noise, world, main
	if only in ["", "light"]:
		test_light_bake()
		await test_light_abandon()
	if only in ["", "noise"]:
		await test_noise()
	if only in ["", "world"]:
		await test_async_world()
	if only in ["", "main"]:
		await test_main_flow()
	print("INFO: Bilder bis zum Ende: %d (build.ps1: höchstens 180)" % Engine.get_process_frames())
	print("RESULT: ", checks - failures, "/", checks, " passed")
	quit(1 if failures > 0 else 0)

func pump(done: Callable, app: Node = null, w: Diorama = null, timeout_ms := 30000) -> bool:
	# Laden ohne Bildtakt vorantreiben (build.ps1: höchstens 180 Bilder je Testreihe): Lader bzw. Bau wie je Bild anstoßen, höchstens alle
	# 100 ms ein echtes Bild.
	var end := Time.get_ticks_msec() + timeout_ms
	var next_frame := Time.get_ticks_msec() + 100
	while Time.get_ticks_msec() < end:
		if done.call():
			return true
		if app != null and is_instance_valid(app):
			app._load_tick()
		if w != null:
			Diorama.reap()
			w.resume.emit()
		OS.delay_msec(1)
		if Time.get_ticks_msec() >= next_frame:
			await process_frame
			next_frame = Time.get_ticks_msec() + 100
	return done.call()

# ---------- Lichtkarte ----------
func bake(occ: Array, polys: Array, lamps: Array, area: Rect2, cells: int, use_cull: bool, threads: int) -> PackedByteArray:
	LightBake.forget()
	LightBake.cull = use_cull
	LightBake.threads = threads
	var job := LightBake.new(occ, polys, lamps, area, cells)
	job.wait()
	LightBake.cull = true
	LightBake.threads = 0
	return job.image.get_data()

func test_light_bake() -> void:
	# Kunstszene: Gebäude (gedreht), Lichtblocker mit Höhe, Lampen nah an Hindernissen, am Rand und außerhalb der Fläche.
	var area := Rect2(-40.0, -30.0, 80.0, 60.0)
	var occ := [[Vector2(0, 0), Vector2(4, 2), 0.4], [Vector2(-18, 10), Vector2(3, 3), 0.0], [Vector2(25, -12), Vector2(6, 1), 1.1]]
	var polys := [[PackedVector2Array([Vector2(8, 8), Vector2(16, 9), Vector2(15, 14), Vector2(9, 13)]), 2.5]]
	var lamps := []
	for i in range(14):
		var p := Vector3(-38.0 + i * 6.1, 3.0 + (i % 4) * 2.0, -26.0 + fmod(i * 17.3, 52.0))
		lamps.append([p, 2.0 + (i % 5) * 1.7, Color(1.0, 0.8 - i * 0.02, 0.5, 1.0)])
	lamps.append([Vector3(-45.0, 6.0, 0.0), 9.0, Color(0.9, 0.9, 1.0)])     # außerhalb der Fläche
	var reference := bake(occ, polys, lamps, area, 128, false, 1)
	check(bake(occ, polys, lamps, area, 128, true, 1) == reference, "Lichtkarte: Grobraster ändert kein Byte (Kunstszene, 128 Zellen)")
	check(bake(occ, polys, lamps, area, 128, true, 0) == reference, "Lichtkarte: Streifen auf mehreren Fäden bitgleich zur Rechnung am Stück")
	check(bake(occ, polys, lamps, area, 96, true, 0) == bake(occ, polys, lamps, area, 96, false, 1), "Lichtkarte: auch bei ungerader Streifenteilung (96 Zellen)")
	# Echte Strecke (Stadt: 55 Häuser, 104 Lampen) in kleinerer Auflösung.
	var w := Diorama.new()
	root.add_child(w)
	w.build(Circuit.load_track("city"))
	var a: Atmosphere = w.atmosphere
	var city_area: Rect2 = w.diorama_extent if w.diorama_extent.has_area() else w.track.bounds
	check(bake(a.occluders, a.occluder_polys, a.lamps, city_area, 160, true, 0) == bake(a.occluders, a.occluder_polys, a.lamps, city_area, 160, false, 1),
		"Lichtkarte Stadt: parallel mit Grobraster bitgleich (%d Lampen, %d Häuser)" % [a.lamps.size(), a.occluders.size()])
	# Merkspeicher: dieselben Eingaben → dasselbe Bild ohne Rechnung.
	LightBake.forget()
	var first := LightBake.new(a.occluders, a.occluder_polys, a.lamps, city_area, 64)
	first.wait()
	var again := LightBake.new(a.occluders, a.occluder_polys, a.lamps, city_area, 64)
	again.start()
	check(again.done() and again.from_memory and again.image == first.image, "Lichtkarte: Rückkehr zu einer Strecke kommt aus dem Merkspeicher")
	var moved := a.lamps.duplicate(true)
	moved[0][0] += Vector3(0.5, 0, 0)
	var other := LightBake.new(a.occluders, a.occluder_polys, moved, city_area, 64)
	other.start()
	check(not other.from_memory, "Lichtkarte: andere Lampen → neuer Schlüssel, neu gerechnet")
	other.wait()
	w.free()

func test_light_abandon() -> void:
	# Abbruch mitten in der Rechnung (andere Strecke gewählt): Fäden enden, reap() räumt auf, nichts landet im Merkspeicher.
	LightBake.forget()
	var lamps := []
	for i in range(40):
		lamps.append([Vector3(i * 2.0 - 40.0, 8.0, 0.0), 20.0, Color(1, 1, 1)])
	var job := LightBake.new([[Vector2(0, 5), Vector2(3, 3), 0.0]], [], lamps, Rect2(-60, -60, 120, 120), 256)
	job.start()
	job.poll()
	OS.delay_msec(20)
	job.poll()
	job.abandon()
	var t0 := Time.get_ticks_msec()
	var ok: bool = await pump(func():
		LightBake.reap()
		return LightBake._orphans.is_empty())
	check(ok and LightBake._memory.is_empty(), "Lichtkarte: abgebrochener Auftrag nach %d ms eingesammelt, nichts gemerkt" % (Time.get_ticks_msec() - t0))

# ---------- Rauschtexturen ----------
func test_noise() -> void:
	# Dasselbe Bild wie die frühere NoiseTexture2D (nahtlos, normalisiert, Mipmaps; Wasser als Normalenkarte).
	var same := 0
	var compared := 0
	for n in Diorama.NOISE_SET:
		var fn := FastNoiseLite.new()
		fn.seed = n[1]
		fn.frequency = n[0]
		fn.fractal_octaves = 4
		var tex := NoiseTexture2D.new()
		tex.noise = fn
		tex.seamless = true
		tex.width = n[2]
		tex.height = n[2]
		if float(n[3]) > 0.0:
			tex.as_normal_map = true
			tex.bump_strength = n[3]
		await tex.changed
		var old_img := tex.get_image()
		if old_img == null:
			continue
		compared += 1
		if old_img.get_data() == Diorama.noise_image(n[0], n[1], n[2], n[3]).get_data() and old_img.has_mipmaps():
			same += 1
	check(compared == Diorama.NOISE_SET.size() and same == compared, "Rauschtexturen: %d von %d bytegleich zur NoiseTexture2D" % [same, compared])

# ---------- Welt im Hintergrund ----------
func fingerprint(w: Node) -> PackedStringArray:
	# Aufbau der Welt: Klasse, Lage, Sichtbarkeit, Ebenen, Netze, Materialien, MultiMesh-Lagen – in Baumreihenfolge.
	var out := PackedStringArray()
	for n in w.find_children("*", "", true, false):
		if n.is_queued_for_deletion():
			continue
		var line := n.get_class()
		if n is Node3D:
			line += " %s %s" % [(n as Node3D).transform, (n as Node3D).visible]
		if n is GeometryInstance3D:
			var g := n as GeometryInstance3D
			line += " L%d S%d T%s %s %s" % [g.layers, g.cast_shadow, g.transparency, material_tag(g.material_override), material_tag(g.material_overlay)]
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			line += " M%d %s" % [mi.mesh.get_surface_count(), mi.mesh.get_aabb()]
			for i in range(mi.mesh.get_surface_count()):
				line += " " + material_tag(mi.get_surface_override_material(i))
		if n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null:
			var mm := (n as MultiMeshInstance3D).multimesh
			line += " MM%d" % mm.instance_count
			for i in range(mm.instance_count):
				line += " %s" % mm.get_instance_transform(i)
		out.append(line)
	return out

func material_tag(m: Material) -> String:
	if m == null:
		return "-"
	if m is ShaderMaterial:
		return "S:" + (m as ShaderMaterial).shader.resource_path.get_file()
	if m is StandardMaterial3D:
		var s := m as StandardMaterial3D
		return "M:%s/%s/%s/%s" % [s.albedo_color.to_html(), s.ao_enabled, s.cull_mode, s.albedo_texture != null]
	return m.get_class()

func test_async_world() -> void:
	# Gleiche Welt aus build_async (Zeitscheiben, Modell im Arbeitsfaden, Lichtkarte parallel) wie aus build() am Stück.
	for id in ["harbor", "serra", "kids"]:
		var sync := Diorama.new()
		root.add_child(sync)
		sync.build(Circuit.load_track(id))
		await process_frame
		var expected := fingerprint(sync)
		sync.free()
		var w := Diorama.new()
		w.slice_usec = 4000
		root.add_child(w)
		var started := Time.get_ticks_msec()
		var pauses := [0]
		w.resume.connect(func(): pauses[0] += 1)
		w.build_async(Circuit.load_track(id))
		await pump(func(): return not w.building, null, w)
		await process_frame
		var got := fingerprint(w)
		check(w.built and pauses[0] > 3 and got == expected, "Welt %s im Hintergrund: %d Pausen, %d Knoten wie am Stück (%d ms)" % [id, pauses[0], got.size(), Time.get_ticks_msec() - started])
		w.free()
	# Abbruch an vielen Stellen des Baus (Modell laden, Netze, Bäume zusammenfassen, Straße, Bausteine, Lichtkarte): Der Bau endet sofort im
	# Aufruf von abort() und wartet danach nie mehr (früher hing er in merge_props für immer, die halbe Welt blieb bis zum Programmende).
	var stuck := []
	for k in [0, 2, 5, 9, 14, 22, 35, 55, 80, 120, 170, 240]:
		var cut := Diorama.new()
		cut.slice_usec = 400
		root.add_child(cut)
		var ended := []
		cut.finished.connect(func(): ended.append(true))
		cut.build_async(Circuit.load_track("forest" if k % 2 == 0 else "harbor"))
		for i in range(k):
			if not cut.building:
				break
			OS.delay_msec(1)
			Diorama.reap()
			cut.resume.emit()
		var was_building := cut.building
		cut.abort()
		if was_building and (ended.size() != 1 or cut.building or cut.built):
			stuck.append(k)
		cut.free()
	check(stuck.is_empty(), "Abbruch an 12 Stellen: Bau endet jeweils sofort, nichts hängt (hängend nach %s Pausen)" % str(stuck))
	var gone: bool = await pump(func():
		Diorama.reap()
		return Diorama._unclaimed.is_empty())
	check(gone, "Abbruch: offene Ladeaufträge sind abgeholt")

# ---------- Ablauf im Spiel ----------
func node(app: Node, node_name: String) -> Node:
	return app.hud.root.find_child(node_name, true, false)

func test_main_flow() -> void:
	var app: Node = load("res://main.tscn").instantiate()
	root.add_child(app)
	var test_path := "user://test_loading_%s.json" % Time.get_ticks_usec()
	app.store = ProgressStore.new(test_path)
	check(not app.track_ready() and app.next_world != null and not app.world.built, "Start: Menü sofort, die erste Welt entsteht im Hintergrund")
	var ok: bool = await pump(func(): return app.track_ready(), app)
	check(ok and app.world.built and app.world.track.id == app.track_id, "Start: Welt fertig und eingesetzt (%s)" % app.track_id)
	if app.track_id != "azure":
		app.select_track("azure")     # gespeicherte Strecke des Rechners: auf die Küste festlegen (am Stück)
	var first: String = app.track_id
	app.show_menu()
	var draw_text: String = (node(app, "DrawButton") as Button).text
	app.pick_track("harbor")
	app.stage = 0
	app.hud.menu()
	var draw := node(app, "DrawButton") as Button
	var demo := node(app, "DemoButton") as Button
	check(app.track_id == "harbor" and app.track.id == "harbor" and app.world.track.id == first, "Wahl: Streckendaten sofort, die alte Welt bleibt, bis die neue steht")
	check(draw.disabled and draw.text == "Strecke lädt …" and demo.disabled and demo.text == "Strecke lädt …", "Laden: „Linie zeichnen“ und „Vorführfahrt“ gesperrt mit „Strecke lädt …“")
	app._load_tick()
	app._load_tick()
	var aborted: Diorama = app.next_world
	app.pick_track("forest")
	app.hud.menu()
	check(aborted.aborted and app.next_world != aborted and app.next_world != null and app.track.id == "forest", "Neue Wahl während des Ladens: Bau abgebrochen, neuer Bau für den Wald")
	app.pick_track(first)
	app.hud.menu()
	check(app.track_ready() and app.world.track.id == first and not (node(app, "DrawButton") as Button).disabled, "Zurück zur gezeigten Strecke: sofort bereit, kein Bau")
	app.pick_track("kids")
	app.hud.menu()
	draw = node(app, "DrawButton") as Button
	ok = await pump(func(): return app.track_ready(), app)
	check(ok and app.world.track.id == "kids" and not draw.disabled and draw.text == draw_text, "Geladen: Knopf wieder „%s“ und frei" % draw_text.strip_edges())
	ok = await pump(func(): return app.wreck.is_empty(), app)
	check(ok and app.get_children().filter(func(c): return c is Diorama).size() == 1, "Alte Welten Stück für Stück abgerissen, nur eine Welt übrig")
	# Sicherheitsnetz: Zeichnen bzw. Vorführfahrt mitten im Laden stellen die Welt sofort fertig.
	app.pick_track("quarry")
	check(not app.track_ready(), "Steinbruch lädt")
	app.start_drawing()
	check(app.track_ready() and app.world.track.id == "quarry" and app.phase == "draw" and app.world.visible, "Linie zeichnen mitten im Laden: Welt sofort fertig, Zeichenansicht")
	app.show_menu()
	app.pick_track("serra")
	app.demo()
	check(app.track_ready() and app.world.track.id == "serra" and app.phase in ["countdown", "race"] and app.vehicles.size() > 0, "Vorführfahrt mitten im Laden: Welt fertig, Rennen läuft")
	# Weitergeben: Übergabekarte wartet auf die Welt.
	app.show_menu()
	app.open_party()
	app.party.set_track("fair")
	app.party_start()
	var tap := node(app, "HandoverTap") as Button
	var hint := node(app, "HandoverGo") as Label
	check(not app.track_ready() and tap.disabled and hint.text == "Strecke lädt …", "Übergabekarte: Tippen gesperrt, Hinweis „Strecke lädt …“")
	ok = await pump(func(): return app.track_ready(), app)
	check(ok and not tap.disabled and hint.text != "Strecke lädt …" and not app.world.visible, "Übergabekarte nach dem Laden frei, Strecke weiter verdeckt")
	app.show_menu()
	# Programmende mitten im Laden: Bau abbrechen, Fäden abwarten (Absturz/Lecks beim Beenden, gefunden 04.10.2026).
	app.pick_track("arena")
	app._load_tick()
	app.queue_free()
	await process_frame
	await process_frame
	check(Diorama._unclaimed.is_empty() and LightBake._orphans.is_empty(), "Ende mitten im Laden: Ladeaufträge und Fäden abgeschlossen")
	for f in [test_path, test_path + ".bak"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
