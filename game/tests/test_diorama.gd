extends SceneTree

# Prüft die Dioramen: zuerst das der Stadt im Einzelnen (Bäume als MultiMesh, Rennausstattung, parkende Autos, Bänke, Materialien ohne
# Platzhalter), danach für JEDE Strecke mit game/dioramas/<id>.glb dieselben Grundprüfungen und die Spielebene: Hindernisse der
# Begleitdatei halten den Fahrschlauch, Rampen-/Lücken-/Looping-Zonen und Abkürzungen frei, die KI fährt mit allen Hindernissen
# ohne Zusammenstoß ins Ziel.
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

func diorama_ids() -> Array:
	# Strecken mit gebautem Diorama (game/dioramas/<id>.glb); .remap kommt in exportierten Fassungen vor.
	var ids: Array = []
	for file in DirAccess.get_files_at("res://dioramas"):
		var name_ := String(file).trim_suffix(".remap")
		if name_.ends_with(".glb"):
			ids.append(name_.trim_suffix(".glb"))
	ids.sort()
	return ids

func count_placeholders(scene: Node) -> int:
	# E_-/K_-Oberflächen ohne Spielmaterial (world.gd ersetzt sie): solche Platzhalter wären im Spiel weiß bzw. einfarbig.
	var placeholders := 0
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in range(mi.mesh.get_surface_count()):
			var overridden := mi.get_surface_override_material(i)
			var base := mi.mesh.surface_get_material(i)
			var name_ := String(base.resource_name) if base != null else ""
			if overridden == null and (name_.begins_with("E_") or name_.begins_with("K_")):
				placeholders += 1
	return placeholders

func run() -> void:
	var app: Node = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.store = ProgressStore.new("user://test_diorama_%s.json" % Time.get_ticks_usec())
	app.select_track("city")
	app.start_drawing()
	for i in range(5):
		await process_frame
	var world: Node3D = app.world
	check(world.diorama, "Diorama der Stadt wird geladen")
	var scene: Node = world.get_node_or_null("Diorama")
	check(scene != null, "Diorama-Knoten vorhanden")
	if scene != null:
		var multis := scene.find_children("Baeume_*", "MultiMeshInstance3D", true, false)
		check(multis.size() >= 3 and multis.size() <= 12, "Bäume zu MultiMeshes zusammengefasst (%d)" % multis.size())
		var trees := 0
		for m in multis:
			trees += (m as MultiMeshInstance3D).multimesh.instance_count
		check(trees >= 30, "MultiMeshes tragen alle Bäume (%d)" % trees)
		var singles := scene.find_children("Prop_*", "MeshInstance3D", true, false).size()
		check(singles <= 8, "höchstens wenige Einzelbäume übrig (%d)" % singles)
		for prefix in ["Ausstattung_e_menge", "Ausstattung_e_banner", "Ausstattung_e_portal", "Ausstattung_e_flagge", "Ausstattung_stahl", "Auto_k_farbe", "Bank_holz"]:
			check(not scene.find_children(prefix + "*", "MeshInstance3D", true, false).is_empty(), "Objekt %s vorhanden" % prefix)
		var placeholders := count_placeholders(scene)
		check(placeholders == 0, "kein E_/K_-Platzhalter ohne Spielmaterial (%d)" % placeholders)
		check_crowd_material(world, scene)
	# --- Kernfunktionen der Pipeline (Lichtkarte, Bodenhöhen, unsichtbare Hindernisse), unabhängig von einem bestimmten Diorama
	check_core_features()
	check_light_shaders()
	# --- alle Strecken mit Diorama
	var ids := diorama_ids()
	check(ids.has("city"), "Dioramen gefunden: %s" % ", ".join(PackedStringArray(ids)))
	for id in ids:
		await check_track(app, str(id))
	print("RESULT: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures > 0 else 0)

func check_track(app: Node, id: String) -> void:
	app.select_track(id)
	app.start_drawing()
	for i in range(5):
		await process_frame
	var world: Node3D = app.world
	var track: Circuit = app.track
	check(track.id == id, "%s: Strecke geladen" % id)
	check(world.diorama, "%s: Diorama wird geladen" % id)
	var scene: Node = world.get_node_or_null("Diorama")
	check(scene != null, "%s: Diorama-Knoten vorhanden" % id)
	if scene != null:
		var placeholders := count_placeholders(scene)
		check(placeholders == 0, "%s: kein E_/K_-Platzhalter ohne Spielmaterial (%d)" % [id, placeholders])
	var layout = JSON.parse_string(FileAccess.get_file_as_string("res://dioramas/%s_layout.json" % id))
	check(layout is Dictionary and layout.get("extent", []).size() == 4 and layout.get("obstacles") is Array and layout.get("baked") is Array,
		"%s: Begleitdatei vollständig (extent, obstacles, baked)" % id)
	if not layout is Dictionary or layout.get("extent", []).size() != 4:
		return
	var ext: Array = layout.extent
	check(float(ext[0]) <= track.bounds.position.x and float(ext[1]) <= track.bounds.position.y and float(ext[2]) >= track.bounds.end.x
		and float(ext[3]) >= track.bounds.end.y, "%s: Diorama-Fläche deckt die Strecke ab" % id)
	check(track.obstacle_source == "layout", "%s: Hindernisse aus der Begleitdatei (%d)" % [id, track.obstacles.size()])
	check_layout_extras(world, track, layout, id)
	check_lighting(world, scene, track, id)
	# Straßenart: Laufzeit-Fahrbahn hybrid (Spiel baut die Straße) oder gebackene Fahrbahn (keine zweite darüber)
	var runtime_road := bool(layout.get("runtime_road", false))
	check(world.diorama_runtime_road == runtime_road, "%s: runtime_road der Begleitdatei wirkt" % id)
	if runtime_road:
		check(world.road_mesh != null, "%s: Laufzeit-Fahrbahn gebaut" % id)
		check(layout.get("blocked", []).is_empty(), "%s: Laufzeit-Fahrbahn ohne gebackene Straßenflächen" % id)
	else:
		check(world.road_mesh == null, "%s: gebackene Fahrbahn, keine zweite zur Laufzeit" % id)
	check(world.diorama_runtime_terrain == bool(layout.get("runtime_terrain", false)), "%s: runtime_terrain der Begleitdatei wirkt" % id)
	if bool(layout.get("runtime_terrain", false)):
		check(not track.terrain.is_empty(), "%s: runtime_terrain nur mit Geländerelief in der Strecke" % id)
	# Spielebene: Fahrschlauch frei von Hindernissen. Die ersten Einträge von track.obstacles stammen aus der Begleitdatei (obstacles,
	# lamps): dafür ist das Diorama verantwortlich. Danach folgen die Bausteine der Streckendatei, die das Diorama nicht selbst enthält
	# (baked); sie sind nicht Sache des Themas (nur über "baked" und eigene "lamps" beeinflussbar) und werden nur gemeldet.
	var n_layout: int = layout.obstacles.size() + layout.get("lamps", []).size()
	var bad := corridor_offenders(track)
	var own: Array = []
	var foreign: Array = []
	for index in bad:
		var o: Dictionary = track.obstacles[int(index)]
		(own if int(index) < n_layout else foreign).append("%s@(%.1f|%.1f) %.2f m" % [o.k, o.c.x, o.c.y, bad[index]])
	check(own.is_empty(), "%s: Hindernisse des Dioramas halten den Fahrschlauch frei (%d Verstöße) %s" % [id, own.size(), ", ".join(PackedStringArray(own.slice(0, 4)))])
	if not foreign.is_empty():
		print("WARN: %s: %d Bausteine der Streckendatei stehen im Fahrschlauch: %s" % [id, foreign.size(), ", ".join(PackedStringArray(foreign.slice(0, 4)))])
	# KI fährt die Strecke mit allen Hindernissen ohne Zusammenstoß zu Ende
	var bot := RaceVehicle.new(track, track.ai_route(1.6))
	var hits := 0
	for tick in range(60 * 150):
		bot.step(1.0 / 60.0, false, float(tick + 1) / 60.0)
		if bot.obstacle_hit > 1.0:
			hits += 1
		bot.obstacle_hit = 0.0
		if bot.finish_time >= 0.0 or bot.crashed:
			break
	check(bot.finish_time > 0.0 and not bot.crashed and hits == 0, "%s: KI im Ziel ohne Zusammenstoß (%.1f s, %d Stöße)" % [id, bot.finish_time, hits])

func check_light_shaders() -> void:
	# Lichtmodell der Nacht (lamp_light.gdshaderinc, lamp_lit): Boden, Gelände und Zusatzlicht begrenzen und entsättigen die Lampenhelligkeit
	# (kein Neon-Rasen unter Flutlicht); Wasser und Fahnen lesen die Lichtkarte selbst.
	var inc := FileAccess.get_file_as_string("res://assets/lamp_light.gdshaderinc")
	check(inc.contains("vec3 lamp_lit(") and inc.contains("vec3 lamp_limit("), "Lichtmodell: lamp_lit und lamp_limit vorhanden")
	for name in ["ground_blend", "terrain", "lit_overlay", "water", "flag"]:
		var shader := load("res://assets/%s.gdshader" % name) as Shader
		# Das Zusatzlicht steht seit 02.10.2026 in lit_overlay.gdshaderinc (ein- und beidseitige Fassung teilen es)
		var code := FileAccess.get_file_as_string("res://assets/lit_overlay.gdshaderinc") if name == "lit_overlay" else (shader.code if shader != null else "")
		check(shader != null and code.contains("lamp_lit("), "Lichtmodell: %s.gdshader nutzt lamp_lit" % name)
	for name in ["ground_blend", "terrain"]:
		var code := (load("res://assets/%s.gdshader" % name) as Shader).code
		check(not code.contains("ALBEDO * lamp_at("), "Lichtmodell: %s.gdshader addiert Lampenlicht nicht mehr ungebremst" % name)
	# Grenzwert: auch ein sehr helles, gesättigtes Gras-Licht bleibt unter dem Maximum (gleiche Formel wie im Shader, Knie 0,28, Grenze 0,6).
	var e := Vector3(0.9, 2.4, 0.3)
	var luma := Vector3(0.299, 0.587, 0.114)
	var le := e.dot(luma)
	var room := 0.6 - 0.28
	var limited := 0.28 + room * (1.0 - exp(-(le - 0.28) / room))
	check(limited < 0.6 and limited > 0.28, "Lichtmodell: Helligkeitsgrenze hält (%.2f -> %.2f)" % [le, limited])
	# Tageslicht-Grenze: das wirksame Licht (Karte x gain) läuft weich auf LAMP_DAY (1,0, Knie 0,6), keine Fläche wird nachts heller als ihre Albedo;
	# Fahrbahn und Zuschauer nutzen sie ebenso, Laufzeit-Bauteile bekommen die Grundhelligkeit der Nacht (lamp_floor).
	check(inc.contains("vec3 lamp_day(") and inc.contains("const float LAMP_DAY = 1.0") and inc.contains("vec3 lamp_floor("), "Lichtmodell: lamp_day und lamp_floor vorhanden")
	for name in ["road", "crowd"]:
		var code := (load("res://assets/%s.gdshader" % name) as Shader).code
		check(code.contains("lamp_day(") or code.contains("lamp_lit("), "Lichtmodell: %s.gdshader begrenzt Lampenlicht auf Tageslicht" % name)
	var overlay_code := FileAccess.get_file_as_string("res://assets/lit_overlay.gdshaderinc")
	var one_sided := (load("res://assets/lit_overlay.gdshader") as Shader).code
	var two_sided := (load("res://assets/lit_overlay_two_sided.gdshader") as Shader).code
	check(overlay_code.contains("ambient_floor") and overlay_code.contains("#ifdef TWO_SIDED") and overlay_code.contains("lamp_floor("), "Lichtmodell: Zusatzlicht mit Grundhelligkeit und Rückseiten")
	check(one_sided.contains("cull_back") and two_sided.contains("cull_disabled") and two_sided.contains("#define TWO_SIDED"),
		"Lichtmodell: Zusatzlicht einseitig (cull_back) und beidseitig (cull_disabled) getrennt")
	# Zuschauer (Befund 02.10.2026: nachts blass und durchsichtig wie Geister, weil das additive Zusatzlicht der Tribünenstufen über die
	# halbtransparente Menge gezeichnet wurde): undurchsichtiger Ausschnitt im Hauptdurchgang, weiche Teile als eigener Durchgang (CROWD_SOFT),
	# Alpha nur aus der Textur, Licht = Albedo x (Lichtkarte über lamp_lit + Grundhelligkeit), kein Eigenleuchten.
	var crowd_code := (load("res://assets/crowd.gdshader") as Shader).code
	check(crowd_code.contains("ALPHA_SCISSOR_THRESHOLD") and crowd_code.contains("#ifdef CROWD_SOFT") and crowd_code.contains("discard"),
		"Zuschauer: undurchsichtiger Ausschnitt plus Weichteil-Durchgang (CROWD_SOFT)")
	var alpha_ok := true
	var emission_ok := false
	for line in crowd_code.split("\n"):
		var code_part := line.split("//")[0]
		if code_part.contains("ALPHA =") and code_part.strip_edges() != "ALPHA = c.a;":
			alpha_ok = false
		if code_part.contains("EMISSION") and code_part.contains("lamp_lit(c.rgb") and code_part.contains("c.rgb * lamp_floor("):
			emission_ok = true
	check(alpha_ok, "Zuschauer: Alpha nur aus dem Ausschnitt der Textur (nie vom Licht)")
	check(emission_ok and not crowd_code.contains("blend_add") and not crowd_code.contains("unshaded"),
		"Zuschauer: Licht = Albedo x (lamp_lit + lamp_floor), kein additives Leuchten")
	var strong := 5.0
	var room_day := 1.0 - 0.6
	var day_limited := 0.6 + room_day * (1.0 - exp(-(strong - 0.6) / room_day))
	check(day_limited <= 1.0 and day_limited > 0.95, "Lichtmodell: Tageslicht-Grenze hält (Licht %.1f -> %.3f)" % [strong, day_limited])

func check_lighting(world: Diorama, scene: Node, track: Circuit, id: String) -> void:
	# Nachtlicht (Stand 02.10.2026): Wasser ohne Zusatzlicht-Durchgang (der multiplizierte die Tiefe aus der Vertexfarbe und färbte es rot),
	# Schanzen mit Zusatzlicht, Erdflecken der Schotterpiste nie über Lücken.
	if scene != null:
		var water := 0
		var overlaid := 0
		for node in scene.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if mi.mesh == null:
				continue
			var is_water := false
			for i in range(mi.mesh.get_surface_count()):
				var base := mi.mesh.surface_get_material(i)
				if base != null and String(base.resource_name) == "D_Wasser":
					is_water = true
			if not is_water:
				continue
			water += 1
			if world.overlay_nodes.any(func(entry: Array) -> bool: return entry[0] == mi and entry[1] != null):
				overlaid += 1
		check(overlaid == 0, "%s: Wasser (%d Flächen) ohne Laternen-Zusatzlicht" % [id, water])
	if not track.ramps.is_empty():
		var wood := Color("a0764a")
		var ramp_nodes := world.overlay_nodes.filter(func(entry: Array) -> bool:
			var n = entry[0]
			return is_instance_valid(n) and n is MeshInstance3D and n.material_override is StandardMaterial3D and n.material_override.albedo_color == wood and entry[1] != null)
		check(ramp_nodes.size() >= track.ramps.size(), "%s: Schanzen (%d) haben Laternen-Zusatzlicht (%d)" % [id, track.ramps.size(), ramp_nodes.size()])
	# Laufzeit-Bauteile (Seitenstreifen, Schlammbänder, Randlinien, Looping): Zusatzlicht mit Grundhelligkeit der Nacht, Looping beidseitig und unabhängig von der Normale
	var floor_entries := world.overlay_nodes.filter(func(entry: Array) -> bool:
		return entry[1] is ShaderMaterial and param(entry[1], "ambient_floor") > 0.0)
	if not track.loops.is_empty():
		var loops := floor_entries.filter(func(entry: Array) -> bool:
			return entry[1].shader == Diorama.LIT_OVERLAY_TWO_SIDED and param(entry[1], "omni") > 0.0)
		check(loops.size() >= track.loops.size() * 2, "%s: Looping (Band und Borde) mit Nachtlicht beidseitig (%d)" % [id, loops.size()])
	if world.diorama_runtime_road and not track.surfaces.is_empty():
		var strips := floor_entries.filter(func(entry: Array) -> bool:
			return is_equal_approx(param(entry[1], "light_gain"), Diorama.STRIP_LIGHT_GAIN))
		check(strips.size() >= track.surfaces.size(), "%s: Schlammbänder/Seitenstreifen mit Laternenlicht (%d)" % [id, strips.size()])
	if world.road_mesh != null:
		check(not world.overlay_nodes.any(func(entry: Array) -> bool: return entry[0] == world.road_mesh and entry[1] != null),
			"%s: Fahrbahn ohne zweites Zusatzlicht (das Licht steckt im Fahrbahn-Shader)" % id)
	if track.road == "gravel" and world.diorama_runtime_road and not track.gaps.is_empty():
		var in_gap := 0
		var spots := 0
		for tone in ["a88c65", "6e5639"]:
			var key := "box" + Color(tone).to_html()
			if not world.batches.has(key):
				continue
			for t in world.batches[key].transforms:
				var at := Vector2(t.origin.x, t.origin.z)
				if track.center_distance(at) > Circuit.HALF_WIDTH:
					continue          # Pfosten- und Randteile in gleicher Farbe zählen nicht
				spots += 1
				if track.in_gap(track.phase(at)):
					in_gap += 1
		check(spots > 0 and in_gap == 0, "%s: Erdflecken der Schotterpiste nicht über Lücken (%d Flecken, %d in Lücken)" % [id, spots, in_gap])

func check_crowd_material(world: Diorama, scene: Node) -> void:
	# Spielmaterial der Zuschauer (world.gd, event_material "menge"): Hauptdurchgang undurchsichtig (crowd.gdshader), next_pass mit
	# CROWD_SOFT nach dem Zusatzlicht der Tribünen (render_priority 1); die Mengen-Knoten werfen keinen Schatten (4 mm über den Stufen).
	var crowd = world.event_materials.get("menge")
	var soft = crowd.next_pass if crowd is ShaderMaterial else null
	check(crowd is ShaderMaterial and crowd.shader == Diorama.CROWD_SHADER and soft is ShaderMaterial and soft.shader != null
		and soft.shader.code.contains("#define CROWD_SOFT") and soft.render_priority > crowd.render_priority,
		"Zuschauer: Hauptdurchgang undurchsichtig, Weichteile als next_pass nach dem Zusatzlicht")
	var nodes := 0
	var casting := 0
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh != null and mi.mesh.get_surface_count() == 1 and mi.get_surface_override_material(0) == crowd:
			nodes += 1
			if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				casting += 1
	check(nodes > 0 and casting == 0, "Zuschauer: %d Mengen-Knoten ohne Schattenwurf (%d werfen)" % [nodes, casting])

func param(mat: ShaderMaterial, name: String) -> float:
	# Gesetzter Shaderwert als Zahl (nicht gesetzt: 0; bool: 0/1)
	var v = mat.get_shader_parameter(name)
	return 0.0 if v == null else float(v)

func light_at(atm: Atmosphere, p: Vector2) -> float:
	# Grünanteil der gebackenen Lichtkarte an einem Weltpunkt (Atmosphere.keep_map)
	var uv := (p - atm.light_area.position) / atm.light_area.size
	return atm.light_map.get_pixelv(Vector2i(int(uv.x * atm.light_map.get_width()), int(uv.y * atm.light_map.get_height()))).g

func mesh_up(mi: MeshInstance3D) -> float:
	# Summe der nach oben zeigenden Anteile aller Dreiecke (gleiche Umlaufrichtung wie die Hauptstraße = gleiches Vorzeichen)
	var v: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var sum := 0.0
	for i in range(0, v.size() - 2, 3):
		sum += (v[i + 1] - v[i]).cross(v[i + 2] - v[i]).y
	return sum

func check_core_features() -> void:
	# Lichtkarte: ein Licht in 3 m Höhe bei (0|0), Lichtradius am Boden 10,8 m. Hohe Wand (8 m) östlich, niedrige Mauer (0,4 m) westlich,
	# Haus (Rechteck) nördlich.
	var atm := Atmosphere.new()
	atm.keep_map = true
	atm.lamps.append([Vector3(0.0, 3.0, 0.0), 6.0, Color(1, 1, 1)])
	atm.occluder_polys.append([PackedVector2Array([Vector2(2.5, -4.0), Vector2(3.0, -4.0), Vector2(3.0, 4.0), Vector2(2.5, 4.0)]), 8.0])
	atm.occluder_polys.append([PackedVector2Array([Vector2(-3.0, -4.0), Vector2(-2.5, -4.0), Vector2(-2.5, 4.0), Vector2(-3.0, 4.0)]), 0.4])
	atm.occluders.append([Vector2(0.0, -3.5), Vector2(2.0, 0.6), 0.0])
	atm.bake_rain_lights(Rect2(-20.0, -20.0, 40.0, 40.0), 256)
	var open := light_at(atm, Vector2(0.0, 6.0))
	var behind_tall := light_at(atm, Vector2(5.0, 0.0))
	var behind_low := light_at(atm, Vector2(-5.0, 0.0))
	var behind_house := light_at(atm, Vector2(0.0, -6.0))
	check(open > 0.2, "Lichtkarte: freie Fläche ist beleuchtet (%.2f)" % open)
	check(behind_tall < 0.1 * open, "Lichtkarte: hoher Lichtblocker (Polygon) wirft Schatten (%.3f gegen %.2f)" % [behind_tall, open])
	check(behind_low > 0.8 * open, "Lichtkarte: Licht aus 3 m Höhe geht über eine 0,4-m-Mauer hinweg (%.2f)" % behind_low)
	check(behind_house < 0.1 * open, "Lichtkarte: Gebäude (Rechteck) wirft weiter Schatten (%.3f)" % behind_house)
	atm.rain.free()                      # Atmosphere legt Regen, Schnee und Sonne schon bei new() an; sie hängen erst nach setup() im Baum
	atm.snow.free()
	atm.sun.free()
	atm.free()
	# Bodenhöhe (prop_y): Eintrag gilt in 6 cm Umgebung, sonst 0
	var probe := Diorama.new()
	probe.set_prop_height(10.0, 20.0, 1.5)
	check(is_equal_approx(probe.diorama_ground_y(10.02, 20.0), 1.5) and probe.diorama_ground_y(12.0, 20.0) == 0.0, "Bodenhöhe (prop_y) gilt am Standort des Bausteins, sonst 0")
	probe.free()
	# Einfache Grafikstufe: unsichtbare Hindernisse ("v": false) werden nicht als Klotz gezeichnet, kollidieren aber
	var tr := Circuit.new()
	tr.obstacles.clear()                 # Circuit.new() bringt die Hindernisse der Standardstrecke mit
	tr.add_circle(Vector2.ZERO, 1.0, 2.0, "mauer")
	tr.add_rect(Vector2(10.0, 0.0), Vector2.RIGHT, Vector2(1.0, 1.0), 2.0, "mauer")
	tr.add_circle(Vector2(20.0, 0.0), 1.0, 2.0, "mauer")
	tr.obstacles[2]["v"] = false
	var blocks := Diorama.new()
	blocks.track = tr
	blocks.build_obstacle_blocks()
	var drawn := 0
	for key in blocks.batches:
		drawn += blocks.batches[key].transforms.size()
	check(drawn == 2, "einfache Grafikstufe: unsichtbares Hindernis wird nicht gezeichnet (%d von 3 Körpern)" % drawn)
	check(tr.obstacle_contact(tr.obstacles[2], Vector2(20.5, 0.0), 0.3).z > 0.0, "unsichtbares Hindernis kollidiert weiterhin")
	blocks.free()

func check_layout_extras(world: Diorama, track: Circuit, layout: Dictionary, id: String) -> void:
	# Optionale Schlüssel der Begleitdatei: Punktlichter, Lichtblocker, Bodenhöhen, unsichtbare Hindernisse, Laternenmodelle, Abkürzungsbelag.
	var ext: Array = layout.extent
	var area := Rect2(Vector2(float(ext[0]), float(ext[1])), Vector2(float(ext[2]) - float(ext[0]), float(ext[3]) - float(ext[1])))
	var lights: Array = layout.get("lights", [])
	var lights_ok := true
	for l in lights:
		var plausible: bool = l is Dictionary and l.has("x") and l.has("z") and float(l.get("range", 0.0)) > 0.0 and float(l.get("energy", 1.0)) >= 0.0 			and l.get("color", []).size() == 3 and float(l.get("y", 0.0)) >= 0.0
		if not plausible or not area.has_point(Vector2(float(l.x), float(l.z))):
			lights_ok = false
	check(lights_ok, "%s: Punktlichter (%d) liegen in der Diorama-Fläche und haben Reichweite, Farbe und Stärke" % [id, lights.size()])
	check(world.diorama_lights.size() == lights.size() and world.atmosphere.lamps.size() >= lights.size(), "%s: Punktlichter gehen in die Lichtkarte" % id)
	# Lichtstärke der Laufzeit-Lichter je Bausteintyp ("prop_light", z. B. Azure-Flutlichter gedimmt): Lichtkarte trägt die skalierten Werte, keine ungedimmten
	var base_colors := {"floodlight": Color(0.95, 0.95, 1.0), "lamp": Color(1.0, 0.82, 0.5), "lantern": Color(1.0, 0.75, 0.4)}
	var prop_light = layout.get("prop_light", {})
	var prop_scales: Dictionary = prop_light if prop_light is Dictionary else {}
	for kind in prop_scales:
		var v = prop_light[kind]
		var energy := float(v.get("energy", 1.0)) if v is Dictionary else float(v)
		if not base_colors.has(kind) or is_equal_approx(energy, 1.0):
			continue
		var b: Color = base_colors[kind]
		var want := Color(b.r * energy, b.g * energy, b.b * energy)     # Farbe x Stärke, Alpha 1 wie in World.light_pool
		var scaled := 0
		var unscaled := 0
		for lamp in world.atmosphere.lamps:
			var c: Color = lamp[2]
			if c.is_equal_approx(want):
				scaled += 1
			elif c.is_equal_approx(b):
				unscaled += 1
		check(scaled > 0 and unscaled == 0, "%s: prop_light %s wirkt (%d gedimmt, %d ungedimmt)" % [id, kind, scaled, unscaled])
	var polys: Array = layout.get("occluder_polys", [])
	var polys_ok := true
	for p in polys:
		if not (p is Array and p.size() == 2 and p[0] is Array and p[0].size() >= 3 and float(p[1]) > 0.0):
			polys_ok = false
	check(polys_ok and world.atmosphere.occluder_polys.size() == polys.size(), "%s: Lichtblocker-Polygone (%d) gültig und übernommen" % [id, polys.size()])
	var heights: Array = layout.get("prop_y", [])
	var known: Array[Vector2] = []
	for p in track.props:
		known.append(Vector2(float(p.get("x", 0.0)), float(p.get("z", 0.0))))
	for lamp in layout.get("lamps", []):
		known.append(Vector2(float(lamp.x), float(lamp.z)))
	var orphans := 0
	var mismatched := 0
	for e in heights:
		var at := Vector2(float(e[0]), float(e[1]))
		if not known.any(func(k: Vector2) -> bool: return k.distance_to(at) < 0.05):
			orphans += 1
		if absf(world.diorama_ground_y(at.x, at.y) - float(e[2])) > 0.002:
			mismatched += 1
	check(heights.size() <= known.size() and orphans == 0, "%s: Bodenhöhen (prop_y, %d) nur an Orten von Bausteinen/Laternen (%d ohne)" % [id, heights.size(), orphans])
	check(mismatched == 0, "%s: Bodenhöhen wirken im Spiel (diorama_ground_y)" % id)
	var invisible := 0
	var kept := true
	for i in range(layout.obstacles.size()):
		var o: Dictionary = layout.obstacles[i]
		if o.has("v") and not bool(o.v):
			invisible += 1
			var t: Dictionary = track.obstacles[i]
			if bool(t.get("v", true)) or track.obstacle_contact(t, t.c, 0.05).z <= 0.0:
				kept = false
	check(kept, "%s: unsichtbare Hindernisse (%d) behalten Flag und Kollision" % [id, invisible])
	var models := {}
	for lamp in layout.get("lamps", []):
		if lamp.has("model"):
			models[str(lamp.model)] = true
	for model in models:
		check(ResourceLoader.exists("res://assets/props/%s.glb" % model), "%s: Laternenmodell %s vorhanden" % [id, model])
		check(not world.find_children("KI_%s_*" % model, "MultiMeshInstance3D", true, false).is_empty(), "%s: Diorama-Laternen mit Modell %s gebaut" % [id, model])
	if world.road_mesh != null and not track.shortcuts.is_empty():
		var shortcut_nodes := 0
		var same_side := true
		for node in world.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if mi != world.road_mesh and mi.material_override != null and world.atmosphere.road_shaders_extra.has(mi.material_override):
				shortcut_nodes += 1
				if signf(mesh_up(mi)) != signf(mesh_up(world.road_mesh)):
					same_side = false
		check(shortcut_nodes == track.shortcuts.size(), "%s: Abkürzungen mit Fahrbahn-Shader gebaut (%d)" % [id, shortcut_nodes])
		check(same_side, "%s: Abkürzungsfläche blickt wie die Hauptfahrbahn nach oben (nicht schwarz)" % id)

func in_zone(s: float, zone: Array) -> bool:
	# Zone [von, bis] in Streckenanteilen (zyklisch)
	return fposmod(s - float(zone[0]), 1.0) <= fposmod(float(zone[1]) - float(zone[0]), 1.0)

func air_zones(track: Circuit) -> Array:
	# Bereiche, in denen das Auto nicht der Mittellinie folgt oder seitlich abdriften darf: [von, bis, Zusatzbreite]
	var zones: Array = []
	var meter := 1.0 / track.length
	for r in track.ramps:
		zones.append([float(r.s), float(r.s) + float(r.length) * meter + 3.0 * meter, 1.0])
	for g in track.gaps:
		# Absprung davor und Landung dahinter (das Auto setzt dort mit dem Schwung auf, bevor der Grip einsetzt)
		zones.append([float(g.from) - 6.0 * meter, float(g.to) + 25.0 * meter, 1.0])
	for l in track.loops:
		zones.append([float(l.s) - 20.0 * meter, float(l.s) + 40.0 * meter, 0.5])
	return zones

func clearance(o: Dictionary) -> float:
	# Abstand, den ein Hindernis zum Rand der Fahrbahn (bzw. Abkürzung) mindestens halten muss: feste Hindernisse (Mauer, Baum, Mast,
	# Auto ...) 0,4 m; weiche (Absperrung, Gitter, Bank, Reifen) dürfen unmittelbar am Rand stehen (die Eckmarkierungen der Stadt
	# stehen 0,12 m daneben), aber nicht auf der Fahrbahn.
	return 0.05 if Circuit.SOFT_OBSTACLES.has(str(o.k)) else 0.4

func corridor_offenders(track: Circuit) -> Dictionary:
	# Hindernis-Index -> größte Eindringtiefe in den Fahrschlauch (Halbbreite + clearance(), in Flug-/Looping-Zonen mehr) und in
	# Abkürzungen (Breite/2 + clearance()). Abgetastet wird die Mittellinie im Meterabstand.
	var bad := {}
	var zones := air_zones(track)
	for i in range(0, track.span(), 2):
		var s := track.index_s(i)
		var p: Vector2 = track.points[i]
		var radius := track.hw(s)
		for z in zones:
			if in_zone(s, z):
				radius += float(z[2])
				break
		for k in range(track.obstacles.size()):
			var depth: float = track.obstacle_contact(track.obstacles[k], p, radius + clearance(track.obstacles[k])).z
			if depth > 0.0:
				bad[k] = maxf(float(bad.get(k, 0.0)), depth)
	for sc in track.shortcuts:
		var path: Array = sc.path
		var half := float(sc.width) * 0.5
		for i in range(path.size() - 1):
			var a: Vector2 = path[i]
			var b: Vector2 = path[i + 1]
			var steps := maxi(1, ceili(a.distance_to(b)))
			for j in range(steps + 1):
				var p := a.lerp(b, float(j) / steps)
				for k in range(track.obstacles.size()):
					var depth: float = track.obstacle_contact(track.obstacles[k], p, half + clearance(track.obstacles[k])).z
					if depth > 0.0:
						bad[k] = maxf(float(bad.get(k, 0.0)), depth)
	return bad
