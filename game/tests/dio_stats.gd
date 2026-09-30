extends SceneTree
# Zählt Dreiecke je Knoten des Dioramas (Ausgabe: nach Dreiecken sortiert), Gruppen nach Namenspräfix.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var id := OS.get_environment("TRACK") if OS.get_environment("TRACK") != "" else "city"
	var scene: Node = load("res://dioramas/%s.glb" % id).instantiate()
	root.add_child(scene)
	var rows := []
	var groups := {}
	var total := 0
	var box := AABB()
	var first := true
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var tris := 0
		for i in range(mi.mesh.get_surface_count()):
			var arr := mi.mesh.surface_get_arrays(i)
			var idx = arr[Mesh.ARRAY_INDEX]
			tris += (idx.size() / 3) if idx != null and idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX].size() / 3)
		total += tris
		var wb := mi.global_transform * mi.get_aabb()
		box = wb if first else box.merge(wb)
		first = false
		var key := String(mi.name)
		var digits := key.length()
		while digits > 0 and (key[digits - 1] >= "0" and key[digits - 1] <= "9" or key[digits - 1] == "_" and false):
			digits -= 1
		key = key.substr(0, digits)
		if not groups.has(key):
			groups[key] = [0, 0]
		groups[key][0] += 1
		groups[key][1] += tris
		rows.append([tris, mi.name, mi.mesh.get_surface_count()])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	for r in rows.slice(0, 12):
		print("NODE %s tris=%d flaechen=%d" % [r[1], r[0], r[2]])
	for k in groups:
		print("GROUP %s n=%d tris=%d" % [k, groups[k][0], groups[k][1]])
	print("TOTAL tris=%d nodes=%d aabb=%s" % [total, rows.size(), box])
	quit()
