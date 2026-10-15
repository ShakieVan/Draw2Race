extends SceneTree
# Kontrollbilder der gezeichneten Linie am Kinderzimmer-Lineal (Wippe): Anfang (Einfahrt) und Ende (Ausfahrt), nah herangezoomt,
# beim Zeichnen (Lineal in Ruhelage, Linie auf der Ruhelage) und im Rennen (Linienstücke auf dem Deck kippen mit; Ruhelage und
# gekippt). Die Linie entsteht wie beim Zeichnen: synthetischer Finger mit 60 Hz über die Abkürzung (LineRecorder).
# Aufruf:  tools/godot_run.ps1 -Script res://tests/lineal_shots.gd -Resolution 2340x1080 -Timeout 300 -EnvPairs 'TAG=nachher'
# (LINE=deutlich: Linie im Rennen deckend statt durchscheinend, nur zur Prüfung; LANE=1.5: Finger 1,5 m statt 0,4 m neben der Pfadmitte.)
# Bilder: user://lineal_<TAG>_<name>.png; der Spielstand der Aufnahme wird am Ende gelöscht.
const STORE := "user://lineal_shots_store.json"
var app: Node
var cam := Camera3D.new()
var tag := "bild"

func _initialize() -> void:
	call_deferred("run")

func frames(n: int) -> void:
	for i in range(n):
		await process_frame

func shot(name: String) -> void:
	await frames(6)
	var path := "user://lineal_%s_%s.png" % [tag, name]
	root.get_texture().get_image().save_png(path)
	print("SHOT ", ProjectSettings.globalize_path(path))

func look(target: Vector3, from: Vector3, fov := 40.0) -> void:
	cam.fov = fov
	cam.position = from
	cam.look_at(target, Vector3.UP if absf((target - from).normalized().y) < 0.99 else Vector3(0, 0, -1))

func views(w: Seesaw, name: String, h_entry: float, h_exit: float) -> void:
	# Je Deckende: in Fahrtrichtung von hinten oben, genau von der Seite (Stufe, Lücke) und senkrecht von oben (Zoom 12 m).
	var side := Vector2(-w.u.y, w.u.x)
	for end: float in [-1.0, 1.0]:
		var e := w.world(end * w.half_len)
		var h := h_entry if end < 0.0 else h_exit
		var t := Vector3(e.x, h, e.y)
		var where := "anfang" if end < 0.0 else "ende"
		var back := -w.u * 6.0 + side * 1.5
		look(t, t + Vector3(back.x, 3.0, back.y))
		await shot("%s_%s_fahrt" % [name, where])
		look(t, t + Vector3(side.x * 6.0, 1.2, side.y * 6.0))
		await shot("%s_%s_seite" % [name, where])
		var over := Vector3(e.x, 0.0, e.y)
		look(over, over + Vector3(0.0, 12.0 * 0.5 / tan(deg_to_rad(20.0)), 0.001))
		await shot("%s_%s_oben" % [name, where])
		# Wie die Rennkamera (main.gd: Neigung 72°, hier 30 m Bildhöhe) über dem Deckende.
		look(over, over + Vector3(0.0, sin(deg_to_rad(72.0)), cos(deg_to_rad(72.0))) * (30.0 * 0.5 / tan(deg_to_rad(20.0))))
		await shot("%s_%s_spiel" % [name, where])

func boost_lines() -> void:
	# Nur Sichtprüfung (LINE=deutlich): Linie im Rennen deckend statt zu 70 % durchsichtig, sonst sind Lücken und Stufen kaum zu sehen.
	var meshes: Array = [app.world.line_mesh]
	meshes.append_array(app.world.seesaw_lines)
	for mi in meshes:
		if mi == null or (mi as MeshInstance3D).mesh == null:
			continue
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		for k in range(mesh.get_surface_count()):
			var mat := mesh.surface_get_material(k) as StandardMaterial3D
			if mat != null:
				mat.albedo_color = Color(1, 1, 1, 1)

func draw_line(t: Circuit, pen: LineRecorder, until: float) -> void:
	# Finger: Hauptstrecke, auf der Abkürzung 0,4 m (LANE) links der Pfadmitte, 26 m/s; leichtes Wackeln. Mit LANE=1.5 zeigt sich, wie
	# die Linie von weiter außen auf das Lineal einrastet (Trichter vor der Einfahrt statt Z-Knick).
	var offset := float(OS.get_environment("LANE")) if OS.get_environment("LANE") != "" else 0.4
	var k := 0
	var from := float(t.shortcuts[k].from)
	var to := float(t.shortcuts[k].to)
	var plen := t.shortcut_length(k)
	var poly := PackedVector2Array()
	var s := 0.0
	for lap in range(t.laps):
		while s < lap + from:
			poly.append(t.at(s))
			s += 0.1 / t.length
		var m := 0.0
		while m <= plen:
			var pose := t.path_pose(k, m)
			var lane := offset * smoothstep(0.0, 8.0, m) * smoothstep(plen, plen - 8.0, m)
			poly.append(Vector2(pose[0]) + Vector2(-pose[1].y, pose[1].x) * lane)
			m += 0.1
		s = lap + to
	while s <= t.laps + 0.03:
		poly.append(t.at(s))
		s += 0.1 / t.length
	var cum := 0.0
	var j := 0
	var walked := 0.0
	var tick := 0
	pen.begin(t.at(0.0), 0.0)
	while not pen.complete and pen.active and pen.progress < until and j < poly.size() - 1:
		tick += 1
		walked += 26.0 / 60.0
		while j < poly.size() - 2 and cum + poly[j].distance_to(poly[j + 1]) < walked:
			cum += poly[j].distance_to(poly[j + 1])
			j += 1
		var f := clampf((walked - cum) / maxf(1e-6, poly[j].distance_to(poly[j + 1])), 0.0, 1.0)
		var dir := (poly[j + 1] - poly[j]).normalized()
		pen.sample(poly[j].lerp(poly[j + 1], f) + Vector2(-dir.y, dir.x) * 0.15 * sin(tick * 0.09), tick / 60.0)

func run() -> void:
	tag = OS.get_environment("TAG") if OS.get_environment("TAG") != "" else "bild"
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await frames(2)
	app.store = ProgressStore.new(STORE)
	app.store.data["ghost"] = false
	app.select_track("kids")
	app.start_drawing()
	await frames(5)
	root.add_child(cam)
	cam.far = 2000.0
	cam.make_current()
	var t: Circuit = app.track
	var w: Seesaw = t.rest_seesaws()[0]
	var pen: LineRecorder = app.recorder
	# Zeichnen: Linie bis hinter die Abkürzung der ersten Runde, Lineal in Ruhelage (Einfahrt unten, Ausfahrt oben).
	draw_line(t, pen, float(t.shortcuts[0].to) + 0.05)
	pen.end()
	app.refresh_line()
	await frames(10)
	app.hud.visible = false
	await views(w, "zeichnen", w.rest_y(-w.half_len), w.rest_y(w.half_len))
	# Rennen: Linie fertig zeichnen; Simulation anhalten, Lineal von Hand in Ruhelage bzw. gekippt zeigen (nur Darstellung).
	pen.begin(pen.last_pos, 1000.0, 3.0)
	draw_line_rest(t, pen)
	app.line_complete()
	app.set_physics_process(false)
	app.hud.visible = false
	if OS.get_environment("LINE") == "deutlich":
		boost_lines()
	await frames(10)
	print("PHASE ", app.phase, " complete=", pen.complete, " punkte=", pen.route.size())
	var sim: Seesaw = app.field.seesaws[0]
	await views(w, "rennen_ruhe", 0.0, 2.2)
	sim.phi = -sim.theta
	sim.prev_phi = -sim.theta
	await frames(4)
	await views(w, "rennen_gekippt", 2.2, 0.0)
	sim.phi = 0.0
	sim.prev_phi = 0.0
	await frames(4)
	await views(w, "rennen_waagrecht", 1.1, 1.1)
	app.show_menu()
	cam.queue_free()
	await frames(3)
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(STORE + suffix):
			DirAccess.remove_absolute(STORE + suffix)
	quit()

func draw_line_rest(t: Circuit, pen: LineRecorder) -> void:
	# Rest der Linie bis ins Ziel: weiter auf der Hauptstrecke bzw. über die Abkürzung der zweiten Runde.
	var k := 0
	var from := float(t.shortcuts[k].from)
	var to := float(t.shortcuts[k].to)
	var plen := t.shortcut_length(k)
	var tick := 0
	var clock := 1000.0
	var s := pen.progress
	while not pen.complete and pen.active and tick < 20000:
		tick += 1
		clock += 1.0 / 60.0
		s += 26.0 / 60.0 / t.length
		var u := fposmod(s, 1.0)
		var p: Vector2
		if u > from and u < to and s > 1.0:
			var m := (u - from) / (to - from) * plen
			p = t.path_pose(k, m)[0]
		else:
			p = t.at(s)
		pen.sample(p, clock)
