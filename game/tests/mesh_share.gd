extends SceneTree
# Prüft, wie viele verschiedene Netze die Prop_-Bäume des Dioramas haben (für das Zusammenfassen zu MultiMeshes).
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var id := OS.get_environment("TRACK") if OS.get_environment("TRACK") != "" else "city"
	var scene: Node = load("res://dioramas/%s.glb" % id).instantiate()
	root.add_child(scene)
	var meshes := {}
	var layers := {}
	for node in scene.find_children("Prop_*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		meshes[mi.mesh.get_instance_id()] = meshes.get(mi.mesh.get_instance_id(), 0) + 1
	print("PROP Knoten=", scene.find_children("Prop_*", "MeshInstance3D", true, false).size(), " verschiedene Netze=", meshes.size(), " ", meshes.values())
	quit()
