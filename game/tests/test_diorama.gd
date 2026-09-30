extends SceneTree

# Prüft das Diorama der Stadt nach dem Laden: Bäume als MultiMesh, Rennausstattung, parkende Autos, Bänke, Materialien ohne Platzhalter.
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
		check(placeholders == 0, "kein E_/K_-Platzhalter ohne Spielmaterial (%d)" % placeholders)
	print("RESULT: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures > 0 else 0)
