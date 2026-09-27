class_name Diorama
extends Node3D

const CREAM := Color("f2e9d5")
const TEAL := Color("227c77")
const CORAL := Color("f16c4c")
const DARK := Color("203940")
var batches: Dictionary = {}
var materials: Dictionary = {}
var track: Circuit
var marker: Node3D
var line_mesh: MeshInstance3D
var open_mesh: MeshInstance3D      # offener (noch änderbarer) Linienteil, schimmert
var ghost_mesh: MeshInstance3D     # alter Linienrest während einer Probe
var open_material: StandardMaterial3D
var skid_mesh: MeshInstance3D
var tyre_tracks := TyreTracks.new()
var atmosphere: Atmosphere

func material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not materials.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.86
		materials[key] = mat
	return materials[key]

func shape(kind: String, p: Vector3, size: Vector3, color: Color, turn := 0.0, parent: Node3D = null) -> MeshInstance3D:
	var key := kind + color.to_html()
	var mesh: Mesh
	if batches.has(key):
		mesh = batches[key].mesh
	else:
		if kind == "box":
			mesh = BoxMesh.new()
		elif kind == "cone":
			mesh = CylinderMesh.new()
			mesh.top_radius = 0.0
			mesh.bottom_radius = 0.5
			mesh.height = 1.0
			mesh.radial_segments = 7
		else:
			mesh = CylinderMesh.new()
			mesh.top_radius = 0.5
			mesh.bottom_radius = 0.5
			mesh.height = 1.0
			mesh.radial_segments = 32 if kind == "disc" else 9
		mesh.material = material(color)
		batches[key] = {"mesh": mesh, "transforms": []}
	var transform := Transform3D(Basis(Vector3.UP, turn).scaled_local(size), p)
	if parent != null:
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.transform = transform
		parent.add_child(instance)
		return instance
	batches[key].transforms.append(transform)
	return null

func shape_transform(kind: String, transform: Transform3D, color: Color) -> void:
	# Wie shape(), aber mit beliebiger Transformation (z. B. gekippte Objekte).
	shape(kind, Vector3.ZERO, Vector3.ONE, color)
	batches[kind + color.to_html()].transforms[-1] = transform

const WATER_SHADER := preload("res://assets/water.gdshader")
const WATER_COLORS := ["39959c", "4aa6a5", "53b3ac", "3f7f80"]
var water_material: ShaderMaterial

func premium_water() -> ShaderMaterial:
	if water_material == null:
		water_material = ShaderMaterial.new()
		water_material.shader = WATER_SHADER
		for key in ["wave_a", "wave_b"]:
			var tex := noise_texture(0.02 if key == "wave_a" else 0.035, 3 if key == "wave_a" else 9, 256)
			tex.as_normal_map = true
			tex.bump_strength = 6.0
			water_material.set_shader_parameter(key, tex)
		water_material.set_shader_parameter("tint_noise", noise_texture(0.02, 13, 128))
	return water_material

func bake() -> void:
	for key in batches:
		# Premium: Wasserflächen (Meer, Lagune, Teich, Brunnen) mit bewegtem Wasser-Shader.
		if premium_rendering() and WATER_COLORS.any(func(c): return key.contains(c)):
			batches[key].mesh.material = premium_water()
	for batch in batches.values():
		if batch.transforms.is_empty():
			continue
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = batch.mesh
		multi.instance_count = batch.transforms.size()
		for i in range(batch.transforms.size()):
			multi.set_instance_transform(i, batch.transforms[i])
		var node := MultiMeshInstance3D.new()
		node.multimesh = multi
		var mat := batch.mesh.material as StandardMaterial3D
		if mat != null:
			node.material_overlay = lit_overlay_color(mat.albedo_color)
		add_child(node)

const THEMES := {
	"coast": {"sky":"327d88","sea":"39959c","ground":"8eae85","stripe":"89a981","rim":"c7b79a","rim2":"f2e9d5","shoulder":"b69c73","mud":"896c4d","island":true},
	"city": {"sky":"283440","sea":"30383f","ground":"7c8784","stripe":"86918e","rim":"5d6569","rim2":"a3aaa9","shoulder":"9ba39f","mud":"6d665a","island":false},
	"forest": {"sky":"36614d","sea":"2c4a38","ground":"4f7b49","stripe":"4a7444","rim":"5f4f39","rim2":"76654a","shoulder":"5f5a34","mud":"4a3524","island":false},
}
const NAMED := {"coral":"f16c4c","cream":"f2e9d5","teal":"227c77","sand":"d8c39a","slate":"5f6f78","gold":"f3c374"}

func named(value, fallback := "f2e9d5") -> Color:
	var key := str(value) if value != null else ""
	return Color(NAMED.get(key, key if key.is_valid_html_color() else fallback))

func build(circuit: Circuit) -> void:
	track = circuit
	var theme: Dictionary = THEMES.get(track.theme, THEMES.coast)
	atmosphere = Atmosphere.new()
	add_child(atmosphere)
	atmosphere.setup(self, Color(theme.sky), track.bounds)
	atmosphere.premium = premium_rendering()
	var c := track.bounds.get_center()
	var half := track.bounds.size*0.5 + Vector2(Circuit.HALF_WIDTH+9.0, Circuit.HALF_WIDTH+9.0)
	shape("box", Vector3(c.x,-2.5,c.y), Vector3(half.x*2+160,0.4,half.y*2+160), Color(theme.sea))
	var fancy_ground := premium_rendering()
	if theme.island:
		# Insel: Sandsockel, Strand, Wiese mit Mähstreifen.
		shape("disc", Vector3(c.x,-1.2,c.y), Vector3(half.x*2.35,2.0,half.y*2.35), Color(theme.rim))
		shape("disc", Vector3(c.x,-0.18,c.y), Vector3(half.x*2.3,0.35,half.y*2.3), Color(theme.rim2))
		if fancy_ground:
			premium_ground(theme, Vector3(c.x,0.01,c.y), Vector3(half.x*2.15,0.15,half.y*2.15), true)
		else:
			shape("disc", Vector3(c.x,0.01,c.y), Vector3(half.x*2.15,0.15,half.y*2.15), Color(theme.ground))
		for strip in range(-12 if not fancy_ground else 0,13 if not fancy_ground else 0):
			var z := strip*2.2
			var width := half.x*2.1*sqrt(maxf(0,1.0-pow(z/(half.y*1.05),2)))
			if width > 1.0:
				shape("box",Vector3(c.x,0.09,c.y+z),Vector3(width,0.008,1.1),Color(theme.stripe))
		for i in range(40):
			var x := sin(i*17.2)*(half.x*2.0)
			var z := cos(i*8.1)*(half.y*1.9)
			if Vector2(x/(half.x*1.2),z/(half.y*1.2)).length() > 1.0:
				shape("box", Vector3(c.x+x,-2.27,c.y+z),Vector3(1.4+fposmod(i,3),0.015,0.08), Color("68b4b7"))
	else:
		# Stadt/Wald: großflächiger Boden bis zum Horizont mit Randsockel.
		shape("box", Vector3(c.x,-0.6,c.y), Vector3(half.x*2+70,1.2,half.y*2+60), Color(theme.rim))
		if fancy_ground:
			premium_ground(theme, Vector3(c.x,0.02,c.y), Vector3(half.x*2+66,0.12,half.y*2+56), false)
		else:
			shape("box", Vector3(c.x,0.02,c.y), Vector3(half.x*2+66,0.12,half.y*2+56), Color(theme.ground))
		if track.theme == "city":
			for gx in range(-8,9):
				shape("box",Vector3(c.x+gx*9.0,0.09,c.y),Vector3(0.12,0.01,half.y*2+50),Color(theme.stripe))
	if not fancy_ground:
		road_strip(-4.9, 4.9, 0.12, Color(theme.shoulder))
	for zone in track.surfaces:
		var sides: Array = [[4.05,4.9]] if zone.side=="outer" else ([[-4.9,-4.05]] if zone.side=="inner" else [[4.05,4.9],[-4.9,-4.05]])
		for band in sides:
			road_strip(band[0],band[1],0.13,Color(theme.mud),float(zone.from),float(zone.to))
	if track.road == "gravel":
		build_gravel_road()
	else:
		build_asphalt_road()
	# Start/Ziel-Karo quer über die Fahrbahn und Startplätze dahinter.
	var t0 := track.tangent(0.0)
	var n0 := Vector2(-t0.y, t0.x)
	for row in range(2):
		for k in range(10):
			var lateral := -3.15 + k*0.7
			var p := track.at(0.0, lateral) + t0*(row*0.36 - 0.18)
			shape("box", Vector3(p.x,0.205,p.y), Vector3(0.36,0.018,0.7), CREAM if (row+k)%2==0 else DARK, -t0.angle())
	if track.road == "asphalt":
		for k in range(4):
			var p := track.at(-(2.0+k*2.1)/track.length, (1.5 if k%2 else -1.5))
			shape("box", Vector3(p.x,0.20,p.y), Vector3(1.3,0.018,0.06), CREAM, -t0.angle())
	for s in [0.04,0.25,0.50,0.75]:
		var p := track.at(s)
		if track.other_branch_distance(p, s) < Circuit.HALF_WIDTH + 1.0:
			continue
		# Fahrtrichtungspfeil ">": Schenkel laufen nach vorn zur Spitze zusammen.
		var angle := -track.tangent(s).angle()
		var arrow_color := Color("d9d1bd") if track.road == "gravel" else Color("b8bfb1")
		for sign_value in [-1.0,1.0]:
			var center: Vector2 = p-track.tangent(s)*0.34+track.tangent(s).orthogonal()*sign_value*0.22
			shape("box", Vector3(center.x,0.20+s*0.004,center.y), Vector3(0.85,0.02,0.16), arrow_color, angle-sign_value*0.55)
	for prop in track.props:
		build_prop(prop)
	flush_ai_props()
	atmosphere.bake_rain_lights(track.bounds.grow(Circuit.HALF_WIDTH + 12.0))
	bake()
	for key in ["ground","stripe","shoulder","rim2"]:
		atmosphere.register_tint(material(Color(theme[key])))
	var road_color := Color("8b6f4e") if track.road == "gravel" else Color("394950")
	atmosphere.road_material = material(road_color)
	atmosphere.road_color = road_color
	if premium_rendering() and road_mesh != null:
		# Premium: Asphalt-/Schotter-Shader mit Nässe, Pfützen und Spiegelung statt Einfarbfläche.
		atmosphere.road_shader = premium_road(road_color)
		road_mesh.material_override = atmosphere.road_shader
	build_puddles()
	marker = Node3D.new()
	add_child(marker)
	shape("disc",Vector3.ZERO,Vector3(1.6,0.08,1.6),Color("ffd38b"),0,marker)
	shape("disc",Vector3(0,0.06,0),Vector3(0.9,0.10,0.9),CORAL,0,marker)
	var start := track.at(0.0)
	marker.position = Vector3(start.x,0.31,start.y)
	line_mesh = MeshInstance3D.new()
	add_child(line_mesh)
	open_mesh = MeshInstance3D.new()
	add_child(open_mesh)
	ghost_mesh = MeshInstance3D.new()
	add_child(ghost_mesh)
	skid_mesh = MeshInstance3D.new()
	skid_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(skid_mesh)
	sort_layers(self)
	for flat in [line_mesh, open_mesh, ghost_mesh, skid_mesh]:
		flat.layers = LAYER_FLAT

func build_asphalt_road() -> void:
	road_mesh = road_strip(-3.5, 3.5, 0.17, Color("394950"), 0.0, 1.0, true)
	road_strip(-3.37, -3.29, 0.185, Color("e8dfc8"), 0.0, 1.0, true, true)
	road_strip(3.29, 3.37, 0.185, Color("e8dfc8"), 0.0, 1.0, true, true)
	# Randsteine als durchgehendes Band je Seite: Segmentgrenzen quer zur Strecke, daher innen kürzer und außen
	# länger – keine Überlappung (Flackern) in der Innenkurve, keine Lücken außen.
	for edge in [-1.0, 1.0]:
		curb_band(edge * 3.46, edge * 4.04)
	var curb_count := int(track.length/0.86)
	for i in range(curb_count):
		var s := float(i) / curb_count
		if i % 4 == 0:
			var p := track.at(s)
			if track.other_branch_distance(p, s) > Circuit.HALF_WIDTH + 0.2:
				shape("box", Vector3(p.x,0.182+s*0.004,p.y), Vector3(0.8,0.016,0.06), Color("8b9390"), -track.tangent(s).angle())

func curb_band(inner: float, outer: float) -> void:
	# Je Farbe ein Netz (gleiches Material wie die übrigen Bauteile, daher gleiche Helligkeit).
	var tools := {CORAL: SurfaceTool.new(), CREAM: SurfaceTool.new()}
	for st in tools.values():
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var blocks := int(track.length / 0.86)
	var steps := 3          # Unterteilung je Block, damit Kurven rund bleiben
	var top := 0.285
	var bottom := 0.14
	var lo := minf(inner, outer)
	var hi := maxf(inner, outer)
	for b in range(blocks):
		var st: SurfaceTool = tools[CORAL if b % 4 < 2 else CREAM]
		for k in range(steps):
			var s0 := (b + float(k) / steps) / blocks
			var s1 := (b + float(k + 1) / steps) / blocks
			var mid := track.at((s0 + s1) * 0.5, (lo + hi) * 0.5)
			# An der Kreuzung (Acht) keine Randsteine quer über die andere Fahrbahn.
			if track.other_branch_distance(mid, (s0 + s1) * 0.5) < Circuit.HALF_WIDTH + 0.6:
				continue
			var a0 := track.at(s0, lo)
			var a1 := track.at(s0, hi)
			var b0 := track.at(s1, lo)
			var b1 := track.at(s1, hi)
			var quads := [
				[Vector3(a0.x, top, a0.y), Vector3(a1.x, top, a1.y), Vector3(b1.x, top, b1.y), Vector3(b0.x, top, b0.y)],
				[Vector3(a1.x, bottom, a1.y), Vector3(b1.x, bottom, b1.y), Vector3(b1.x, top, b1.y), Vector3(a1.x, top, a1.y)],
				[Vector3(b0.x, bottom, b0.y), Vector3(a0.x, bottom, a0.y), Vector3(a0.x, top, a0.y), Vector3(b0.x, top, b0.y)],
			]
			for qi in range(quads.size()):
				var q: Array = quads[qi]
				var e1: Vector3 = q[1] - q[0]
				var e2: Vector3 = q[3] - q[0]
				var n: Vector3 = Vector3.UP if qi == 0 else e1.cross(e2).normalized()
				for idx in [0, 2, 1, 0, 3, 2]:
					st.set_normal(n)
					st.add_vertex(q[idx])
	for color in tools:
		var mesh := MeshInstance3D.new()
		mesh.mesh = tools[color].commit()
		var mat := material(color)
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh.material_override = mat
		mesh.material_overlay = lit_overlay_color(color)
		add_child(mesh)

func build_gravel_road() -> void:
	# Schotterpiste: braune Fahrbahn mit Körnung, keine Randlinien; Holzpfosten und Feldsteine statt Randsteinen.
	road_mesh = road_strip(-3.5, 3.5, 0.17, Color("8b6f4e"), 0.0, 1.0, true)
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	for i in range(int(track.length*7.0)):
		var s := rng.randf()
		var p := track.at(s, rng.randf_range(-3.3,3.3))
		if track.other_branch_distance(p, s) < Circuit.HALF_WIDTH + 0.2:
			continue
		var tone := Color("a88c65") if rng.randf() < 0.6 else Color("6e5639")
		shape("box", Vector3(p.x,0.176+s*0.004,p.y), Vector3(rng.randf_range(0.08,0.2),0.012,rng.randf_range(0.08,0.2)), tone, rng.randf()*TAU)
	var post_count := int(track.length/3.2)
	for i in range(post_count):
		var s := float(i) / post_count
		for edge in [-1.0, 1.0]:
			var p := track.at(s, edge * 4.3)
			if track.other_branch_distance(p, s) < Circuit.HALF_WIDTH + 1.0:
				continue
			if i % 5 == 2:
				shape("cone", Vector3(p.x,0.3,p.y), Vector3(0.8,0.6,0.7), Color("8a8f8c"), s*40.0)
			else:
				shape("box", Vector3(p.x,0.55,p.y), Vector3(0.16,1.0,0.16), Color("6b4a32"))
				shape("box", Vector3(p.x,0.98,p.y), Vector3(0.2,0.06,0.2), Color("f1dfb7"))

func light_pool(head: Vector3, reach: float, color: Color) -> void:
	# Lichtkegel am Boden (nur abends/nachts sichtbar) plus leuchtender Kopf; ohne echte Lichtquelle, mobil-tauglich.
	var node := Node3D.new()
	add_child(node)
	var pool := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(reach*2.0, reach*2.0)
	quad.orientation = PlaneMesh.FACE_Y
	pool.mesh = quad
	pool.material_override = Atmosphere.soft_material(color, true)
	# Über den Randsteinen (0,285 m), damit auch sie im Lichtkegel liegen; unter Linie und Autos kaum sichtbar.
	pool.position = Vector3(head.x, 0.30, head.z)
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Premium: Boden und Fahrbahn lesen das vorberechnete Laternenlicht (mit Schatten), keine Lichtscheibe.
	pool.visible = not premium_rendering()
	node.add_child(pool)
	var glow := MeshInstance3D.new()
	var gq := QuadMesh.new()
	gq.size = Vector2(1.6,1.6)
	glow.mesh = gq
	var gm := Atmosphere.soft_material(Color(1.0,0.92,0.7,0.9), true)
	gm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	glow.material_override = gm
	glow.position = head
	node.add_child(glow)
	node.visible = false
	atmosphere.night_lights.append(node)
	atmosphere.lamps.append([head, reach, Color(color.r, color.g, color.b)])

func build_puddles() -> void:
	# Glänzende Pfützen auf Asphalt, nur bei Regen sichtbar.
	if track.road != "asphalt":
		return
	var glossy := StandardMaterial3D.new()
	glossy.albedo_color = Color("1c2830")
	glossy.roughness = 0.03
	glossy.metallic_specular = 1.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	for i in range(18):
		var s := rng.randf()
		var p := track.at(s, rng.randf_range(-2.6,2.6))
		var puddle := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 0.5
		disc.bottom_radius = 0.5
		disc.height = 0.01
		disc.radial_segments = 20
		puddle.mesh = disc
		puddle.material_override = glossy
		puddle.scale = Vector3(rng.randf_range(1.4,3.2),1,rng.randf_range(0.8,1.8))
		puddle.rotation.y = rng.randf()*TAU
		puddle.position = Vector3(p.x,0.176+s*0.004+0.003,p.y)
		puddle.visible = false
		add_child(puddle)
		atmosphere.puddles.append(puddle)

# --- Premium-Kulisse: KI-Modelle (tools/build_props.ps1) statt Klötzchen, gleiche Modelle gebündelt ---
const AI_PROP_PATH := "res://assets/props/%s.glb"
# Drehung je Modell (Grad), damit die Schauseite zur Strecke bzw. in +z zeigt (TRELLIS-Grundausrichtung).
const AI_PROP_YAW := {}
var ai_prop_meshes := {}
var ai_prop_batches := {}

func ai_prop_mesh(name: String) -> Mesh:
	if not ai_prop_meshes.has(name):
		var mesh: Mesh = null
		if ResourceLoader.exists(AI_PROP_PATH % name):
			var scene: Node = load(AI_PROP_PATH % name).instantiate()
			var found := scene.find_children("*", "MeshInstance3D", true, false)
			if not found.is_empty():
				mesh = (found[0] as MeshInstance3D).mesh
			scene.free()
		ai_prop_meshes[name] = mesh
	return ai_prop_meshes[name]

var ai_arms := {}

func ai_arm(name: String) -> Array:
	# Richtung (Winkel in der x/z-Ebene) und Länge des Auslegers relativ zur Höhe: Mittel der obersten 8 %
	# der Punkte (Leuchtenkopf) gegenüber den untersten 8 % (Mastfuß).
	if ai_arms.has(name):
		return ai_arms[name]
	var result := [0.0, 0.0]
	var mesh := ai_prop_mesh(name)
	if mesh != null:
		var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var box := mesh.get_aabb()
		var top := Vector2.ZERO
		var bottom := Vector2.ZERO
		var nt := 0
		var nb := 0
		for v in verts:
			if v.y > box.end.y - box.size.y * 0.08:
				top += Vector2(v.x, v.z)
				nt += 1
			elif v.y < box.position.y + box.size.y * 0.08:
				bottom += Vector2(v.x, v.z)
				nb += 1
		if nt > 0 and nb > 0:
			var arm := top / nt - bottom / nb
			result = [atan2(arm.y, arm.x), arm.length() / maxf(box.size.y, 0.001)]
	ai_arms[name] = result
	return result

func place_ai(name: String, x: float, z: float, yaw: float, height: float, footprint := Vector2.ZERO, stretch := false, base_y := 0.0) -> bool:
	# Modell auf Höhe/Grundfläche bringen und zum Bündel hinzufügen. false = Modell fehlt (Klötzchen bauen).
	var mesh := ai_prop_mesh(name)
	if mesh == null:
		return false
	var box := mesh.get_aabb()
	var scale3: Vector3
	if footprint != Vector2.ZERO:
		var sx := footprint.x / maxf(box.size.x, 0.001)
		var sz := footprint.y / maxf(box.size.z, 0.001)
		if stretch:
			scale3 = Vector3(sx, height / maxf(box.size.y, 0.001) if height > 0.0 else (sx + sz) * 0.5, sz)
		else:
			var u := minf(sx, sz)
			scale3 = Vector3(u, u, u)
	else:
		var u := height / maxf(box.size.y, 0.001)
		scale3 = Vector3(u, u, u)
	var basis := Basis(Vector3.UP, yaw + deg_to_rad(float(AI_PROP_YAW.get(name, 0.0)))) * Basis.from_scale(scale3)
	if footprint != Vector2.ZERO and box.size.y * scale3.y > 2.5:
		# Größere Bauten werfen Laternenschatten (vorberechnet in Atmosphere.bake_rain_lights).
		atmosphere.occluders.append([Vector2(x, z), Vector2(box.size.x * scale3.x, box.size.z * scale3.z) * 0.5, -yaw])
	var anchor := Vector3(box.get_center().x, box.position.y, box.get_center().z)
	var origin := Vector3(x, base_y, z) - basis * anchor
	if not ai_prop_batches.has(name):
		ai_prop_batches[name] = []
	ai_prop_batches[name].append(Transform3D(basis, origin))
	return true

func flush_ai_props() -> void:
	# Ein MultiMesh je Modell: wenige Zeichenaufrufe auch bei ~270 Waldbäumen.
	for name in ai_prop_batches:
		var list: Array = ai_prop_batches[name]
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = ai_prop_mesh(name)
		multi.instance_count = list.size()
		for i in range(list.size()):
			multi.set_instance_transform(i, list[i])
		var node := MultiMeshInstance3D.new()
		node.name = "KI_" + name
		node.multimesh = multi
		node.material_overlay = lit_overlay(multi.mesh)
		add_child(node)
	ai_prop_batches.clear()

const LIT_OVERLAY := preload("res://assets/lit_overlay.gdshader")

func lit_overlay(mesh: Mesh) -> ShaderMaterial:
	# Laternenlicht direkt + indirekt als Zusatzdurchgang; nutzt die Farbtextur des Modells.
	var mat := ShaderMaterial.new()
	mat.shader = LIT_OVERLAY
	var base := mesh.surface_get_material(0) as StandardMaterial3D if mesh.get_surface_count() > 0 else null
	if base != null:
		if base.albedo_texture != null:
			mat.set_shader_parameter("albedo_tex", base.albedo_texture)
		mat.set_shader_parameter("tint", base.albedo_color)
	return mat

func lit_overlay_color(color: Color) -> ShaderMaterial:
	# Wie lit_overlay, aber für einfarbige Bauteile (Randsteine, Markierungen, Klötzchen-Deko).
	if not premium_rendering():
		return null
	var mat := ShaderMaterial.new()
	mat.shader = LIT_OVERLAY
	mat.set_shader_parameter("tint", color)
	return mat

func premium_prop(prop: Dictionary) -> bool:
	# true = als KI-Modell gebaut (samt Licht/Schrift), false = Klötzchen-Fassung verwenden.
	if not premium_rendering():
		return false
	var x := float(prop.get("x",0.0))
	var z := float(prop.get("z",0.0))
	var rot := -deg_to_rad(float(prop.get("rot",0.0)))
	var w := float(prop.get("w",2.0))
	var d := float(prop.get("d",2.0))
	var sc := float(prop.get("scale",1.0))
	# Zufällige, aber feste Drehung für ungerichtete Objekte (Bäume, Felsen).
	var spin := fposmod(x * 12.9898 + z * 78.233, TAU)
	match str(prop.get("type","")):
		"palm":
			return place_ai("kueste_palme", x, z, spin, float(prop.get("h",3.5)) * 1.35)
		"parasol":
			return place_ai("kueste_sonnenschirm", x, z, spin, 2.5)
		"planter":
			return place_ai("kueste_pflanzkuebel", x, z, rot, 0.0, Vector2(w, d), true)
		"pine":
			return place_ai("wald_kiefer", x, z, spin, 5.6 * sc)
		"oak":
			return place_ai("wald_eiche", x, z, spin, 4.6 * sc)
		"rock":
			return place_ai("wald_felsen" if track.theme == "forest" else "kueste_felsen", x, z, spin, 1.0 * sc)
		"log":
			return place_ai("wald_baumstamm", x, z, rot, 0.0, Vector2(3.2, 0.7), true)
		"street_tree":
			return place_ai("stadt_baum", x, z, spin, 4.6)
		"fountain":
			return place_ai("stadt_brunnen", x, z, spin, 0.0, Vector2(5.0, 5.0))
		"boathouse":
			return place_ai("kueste_bootshaus", x, z, rot, 0.0, Vector2(4.5, 5.0), false, -0.5)
		"cabin":
			return place_ai("wald_huette", x, z, rot, 0.0, Vector2(5.0, 4.0))
		"stand":
			return place_ai("kueste_tribuene", x, z, rot, 0.0, Vector2(w, d + 2.0), true)
		"tower":
			return place_ai("kueste_zeitnahme", x, z, rot, 5.5)
		"pavilion":
			if place_ai("kueste_clubhaus", x, z, rot, 0.0, Vector2(w + 1.0, d + 1.0)):
				label3d(str(prop.get("text","")), Vector3(x, 3.4, z + d * 0.62), 62, CREAM)
				return true
			return false
		"building":
			var kinds := ["stadt_altbau", "stadt_eckladen", "stadt_wohnblock", "stadt_buero"]
			var pick: String = kinds[int(absf(x * 3.0 + z * 7.0)) % kinds.size()]
			# Gleichmäßig skalieren (nicht strecken): KI-Häuser behalten ihre Proportionen.
			return place_ai(pick, x, z, rot, 0.0, Vector2(w, d))
		"lamp":
			# Ausleger zur Fahrbahn drehen; das Licht sitzt am Leuchtenkopf über der Straße.
			var model := "stadt_laterne" if track.theme == "city" else "kueste_laterne"
			var arm := ai_arm(model)
			var here := Vector2(x, z)
			var to_road := track.at(track.phase(here)) - here
			var yaw := float(arm[0]) - atan2(to_road.y, to_road.x) if to_road.length() > 0.1 else spin
			if place_ai(model, x, z, yaw, 4.2):
				var head := here + to_road.normalized() * float(arm[1]) * 4.2
				light_pool(Vector3(head.x,3.9,head.y), 4.0, Color(1.0,0.82,0.5,0.5))
				return true
			return false
		"floodlight":
			if place_ai("kueste_flutlicht", x, z, rot, 9.0):
				light_pool(Vector3(x,8.6,z), float(prop.get("reach",11.0)), Color(0.95,0.95,1.0,0.42))
				return true
			return false
		"lantern":
			if place_ai("wald_laterne", x, z, spin, 1.7):
				light_pool(Vector3(x,1.55,z), 3.2, Color(1.0,0.75,0.4,0.55))
				return true
			return false
	return false

func build_prop(prop: Dictionary) -> void:
	if premium_prop(prop):
		return
	var x := float(prop.get("x",0.0))
	var z := float(prop.get("z",0.0))
	var rot := -deg_to_rad(float(prop.get("rot",0.0)))
	var w := float(prop.get("w",2.0))
	var d := float(prop.get("d",2.0))
	var sc := float(prop.get("scale",1.0))
	var text := str(prop.get("text",""))
	match str(prop.get("type","")):
		"palm":
			palm(Vector2(x,z), float(prop.get("h",3.5)))
		"parasol":
			var p := Vector3(x,1.3,z)
			shape("cylinder", p-Vector3(0,0.7,0),Vector3(0.1,1.8,0.1), DARK)
			shape("cone", p+Vector3(0,0.6,0),Vector3(2.4,0.7,2.4), named(prop.get("color")))
			shape("box", p-Vector3(0,0.95,-1.2),Vector3(1.8,0.20,0.65), CREAM)
		"planter":
			shape("box",Vector3(x,0.48,z),Vector3(w,0.7,d),CREAM,rot)
			shape("box",Vector3(x,0.92,z),Vector3(w*0.9,0.4,d+0.1),Color("56876c"),rot)
		"flower":
			shape("cone",Vector3(x,0.42,z),Vector3(0.7,0.7,0.7),Color("668969"))
			shape("disc",Vector3(x,0.8,z),Vector3(0.3,0.15,0.3),named(prop.get("color"),"f3c374"))
		"lagoon":
			shape("disc", Vector3(x,0.10,z), Vector3(w,0.18,d), Color("d8ceaf"))
			shape("disc", Vector3(x,0.22,z), Vector3(w-1.5,0.12,d-1.5), Color("4aa6a5"))
			shape("disc", Vector3(x,0.29,z), Vector3(w-4.5,0.02,d-4.5), Color("53b3ac"))
		"pond":
			shape("disc", Vector3(x,0.08,z), Vector3(w,0.16,d), Color("6b5a40"))
			shape("disc", Vector3(x,0.16,z), Vector3(w-1.2,0.10,d-1.2), Color("3f7f80"))
		"walkway":
			var planks := int(w/0.6)
			for i in range(planks):
				shape("box", Vector3(x-w*0.5+i*0.6,0.48,z), Vector3(0.5,0.20,d), Color("b29268"))
			for i in range(int(w/2.2)+1):
				shape("box", Vector3(x-w*0.5+i*2.2,0.65,z+d*0.45), Vector3(0.12,1.2,0.12), CREAM)
		"pavilion":
			shape("box", Vector3(x,1.1,z), Vector3(w,2.2,d), CREAM)
			shape("box", Vector3(x,0.5,z+d*0.62), Vector3(w+1.0,1.0,1.2), Color("c9baa0"))
			shape("box", Vector3(x,2.35,z), Vector3(w+1.3,0.3,d+1.2), CORAL)
			shape("box", Vector3(x,1.4,z+d*0.506), Vector3(w-1.4,0.95,0.04), Color("28535b"))
			for i in range(5):
				shape("box", Vector3(x-w*0.37+i*w*0.185,2.56,z), Vector3(w*0.15,0.10,d*0.74), Color("345866"))
			label3d(text, Vector3(x,2.8,z+d*0.56), 62, CREAM)
		"label":
			label3d(text, Vector3(x,0.25,z), 64, Color("e9dfbf"), bool(prop.get("flat",false)))
		"tower":
			shape("box",Vector3(x,2.1,z),Vector3(0.3,4.2,0.3),DARK)
			shape("box",Vector3(x,4.2,z),Vector3(4.1,1.7,0.4),DARK)
			label3d(text,Vector3(x,4.25,z+0.23),48,CREAM)
		"boathouse":
			for i in range(5):
				shape("box", Vector3(x-2+i*1.1,-0.4,z-2), Vector3(1.0,0.2,4.0), Color("b29873"))
			shape("box",Vector3(x+1,-1.4,z+3),Vector3(1.7,0.8,4.2),CREAM,0.3)
			shape("box",Vector3(x+1,-0.7,z+3),Vector3(1.1,0.7,1.4),CORAL,0.3)
		"stand":
			for tier in range(4):
				shape("box", Vector3(x,0.4+tier*0.35,z+1.1-tier*0.8), Vector3(w,0.75+tier*0.65,0.85), CREAM)
				for seat in range(int(w/0.6)):
					shape("box", Vector3(x-w*0.45+seat*0.6,0.9+tier*0.7,z+1.1-tier*0.8), Vector3(0.36,0.25,0.36), CORAL if (seat+tier)%3 else TEAL)
			shape("box", Vector3(x,4.3,z), Vector3(w+1.4,0.22,d+1.5), Color("f1dfb7"))
			for side in [-0.48,0.48]:
				shape("box", Vector3(x+w*side,2.1,z-1.5), Vector3(0.16,4.3,0.16), DARK)
		"building":
			var h := float(prop.get("h",8.0))
			var col := named(prop.get("color"),"a3aaa9")
			shape("box", Vector3(x,h*0.5,z), Vector3(w,h,d), col, rot)
			shape("box", Vector3(x,h+0.15,z), Vector3(w+0.3,0.3,d+0.3), col.darkened(0.25), rot)
			for floor_i in range(1,int(h/2.4)+1):
				shape("box", Vector3(x,floor_i*2.4-0.7,z), Vector3(w+0.06,0.7,d+0.06), Color("2c4a55"), rot)
		"lamp":
			shape("cylinder", Vector3(x,1.6,z), Vector3(0.12,3.2,0.12), DARK)
			shape("box", Vector3(x,3.25,z), Vector3(0.5,0.18,0.5), Color("fff1b6"))
			light_pool(Vector3(x,3.25,z), 4.0, Color(1.0,0.82,0.5,0.5))
		"floodlight":
			shape("cylinder", Vector3(x,4.0,z), Vector3(0.22,8.0,0.22), DARK)
			shape("box", Vector3(x,8.1,z), Vector3(1.6,0.5,0.5), Color("fff1b6"), rot)
			light_pool(Vector3(x,8.1,z), float(prop.get("reach",11.0)), Color(0.95,0.95,1.0,0.42))
		"lantern":
			shape("cylinder", Vector3(x,0.9,z), Vector3(0.12,1.8,0.12), Color("6b4a32"))
			shape("box", Vector3(x,1.9,z), Vector3(0.3,0.35,0.3), Color("ffcf7a"))
			light_pool(Vector3(x,1.9,z), 3.2, Color(1.0,0.75,0.4,0.55))
		"street_tree":
			shape("cylinder", Vector3(x,0.9,z), Vector3(0.22,1.8,0.22), Color("7a5c40"))
			shape("disc", Vector3(x,2.3,z), Vector3(2.0,1.6,2.0), Color("5f9a5f"))
			shape("box", Vector3(x,0.12,z), Vector3(1.6,0.12,1.6), Color("6d7672"))
		"billboard":
			shape("box", Vector3(x,1.6,z), Vector3(0.2,3.2,0.2), DARK, rot)
			shape("box", Vector3(x,3.6,z), Vector3(6.0,2.0,0.3), CORAL, rot)
			var label := Label3D.new()
			label.text = text
			label.font_size = 70
			label.pixel_size = 0.013
			label.modulate = CREAM
			label.position = Vector3(x,3.6,z) + Vector3(0,0,0.2).rotated(Vector3.UP, rot)
			label.rotation.y = rot
			add_child(label)
		"fountain":
			shape("disc", Vector3(x,0.25,z), Vector3(5,0.5,5), Color("a3aaa9"))
			shape("disc", Vector3(x,0.45,z), Vector3(4.2,0.1,4.2), Color("4aa6a5"))
			shape("cylinder", Vector3(x,1.0,z), Vector3(0.5,1.6,0.5), Color("a3aaa9"))
		"pine":
			shape("cylinder", Vector3(x,0.6*sc,z), Vector3(0.28*sc,1.2*sc,0.28*sc), Color("6b4a32"))
			shape("cone", Vector3(x,2.0*sc,z), Vector3(2.6*sc,2.4*sc,2.6*sc), Color("2f6b45"))
			shape("cone", Vector3(x,3.2*sc,z), Vector3(1.9*sc,2.0*sc,1.9*sc), Color("367a4e"))
		"oak":
			shape("cylinder", Vector3(x,0.9*sc,z), Vector3(0.35*sc,1.8*sc,0.35*sc), Color("6b4a32"))
			shape("disc", Vector3(x,2.6*sc,z), Vector3(3.2*sc,2.2*sc,3.2*sc), Color("4f8a45"))
		"rock":
			shape("cone", Vector3(x,0.35*sc,z), Vector3(1.6*sc,0.9*sc,1.3*sc), Color("8a8f8c"), rot)
		"log":
			# Liegender Stamm: Zylinder um 90° gekippt, dann in Streckenrichtung gedreht.
			var t := Transform3D(Basis(Vector3.UP, rot) * Basis(Vector3.FORWARD, PI*0.5), Vector3(x,0.35,z))
			shape_transform("cylinder", t.scaled_local(Vector3(0.6,3.2,0.6)), Color("7a5c40"))
		"cabin":
			shape("box", Vector3(x,1.2,z), Vector3(5,2.4,4), Color("8a6a48"), rot)
			shape("box", Vector3(x,2.7,z), Vector3(5.6,0.6,4.6), Color("5b442f"), rot)
			shape("box", Vector3(x,1.1,z), Vector3(1.0,2.0,4.06), Color("3e2e20"), rot)

func palm(p: Vector2, height: float) -> void:
	shape("cylinder",Vector3(p.x,height*0.5,p.y),Vector3(0.32,height,0.32),Color("9d8060"))
	for i in range(6):
		var a := i * TAU / 6.0
		shape("cone",Vector3(p.x+cos(a)*0.65,height,p.y+sin(a)*0.65),Vector3(2.4,0.48,1.1),Color("427f65") if i%2 else Color("57946d"),-a)
	shape("cone",Vector3(p.x,height+0.4,p.y),Vector3(1.7,1.0,1.7),Color("659d70"))

func label3d(text: String, pos: Vector3, font_size: int, color: Color, flat := false) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = 0.013
	label.modulate = color
	label.outline_size = 0
	label.no_depth_test = false
	label.position = pos
	if flat:
		label.rotation_degrees.x = -90
	add_child(label)

func road_strip(inner: float, outer: float, y: float, color: Color, start_s := 0.0, end_s := 1.0, stagger := false, skip_crossing := false) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := maxi(1,ceili(track.length/0.5*(end_s-start_s)))
	for i in range(count):
		var a := lerpf(start_s,end_s,float(i)/count)
		var b := lerpf(start_s,end_s,float(i+1)/count)
		# Staffelung: späterer Streckenverlauf liegt minimal höher (Acht-Kreuzung ohne Z-Flimmern).
		var ya := y + (a*0.004 if stagger else 0.0)
		var yb := y + (b*0.004 if stagger else 0.0)
		var points := [track.at(a,inner),track.at(a,outer),track.at(b,outer),track.at(b,inner)]
		if skip_crossing and track.other_branch_distance(points[0], a) < Circuit.HALF_WIDTH + 0.3:
			continue
		var heights := [ya,ya,yb,yb]
		for j in [0,2,1,0,3,2]:
			surface.set_normal(Vector3.UP)
			surface.add_vertex(Vector3(points[j].x,heights[j],points[j].y))
	var mesh := MeshInstance3D.new()
	mesh.mesh = surface.commit()
	var mat := material(color)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = mat
	add_child(mesh)
	return mesh

static func line_half_width(speed: float) -> float:
	# Halbe Breite gegenüber vorher (langsam 0,48 m, schnell 0,05 m) und nicht linear: Die Breite fällt schon bei
	# mittlerem Tempo deutlich ab, richtig breit wird die Linie nur bei langsamem Tempo.
	var t := clampf((speed-5.0)/24.0,0.0,1.0)
	return lerpf(0.48,0.05,pow(t,0.4))

static func line_color(speed: float) -> Color:
	return Color("fff1b8").lerp(Color("ed3c32"),clampf((speed-5.0)/24.0,0.0,1.0))

func draw_route(route: Array[Dictionary], subdued := false, open_from := -1, ghost: Array[Dictionary] = []) -> void:
	# open_from: Routenindex, ab dem die Linie offen ist (schimmert); ghost: alter Rest während einer Probe.
	var split := route.size() if open_from < 0 else clampi(open_from, 0, route.size())
	var line_mat := line_material(subdued)
	if subdued:
		# Im Rennen: Linie zu 70 % durchsichtig, damit Fahrbahn, Pfützen und Autos darunter sichtbar bleiben.
		line_mat.albedo_color = Color(1, 1, 1, 0.3)
		# Wie Fahrbahnmarkierung beleuchtet (Tag hell, Nacht dunkel, unter Laternen hell) statt selbstleuchtend.
		line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		line_mat.roughness = 0.9
		# Ganz dezentes Eigenleuchten, damit die Linie auch nachts noch zu ahnen ist.
		line_mat.emission_enabled = true
		line_mat.emission = Color(1.0, 0.9, 0.78)
		line_mat.emission_energy_multiplier = 0.16
	line_mesh.mesh = route_mesh(route, 0, split, subdued, line_mat)
	open_mesh.mesh = route_mesh(route, maxi(split, 1) - 1, route.size(), false, open_line_material()) if split < route.size() else null
	# Deckend, damit sich überlappende Segmente nicht streifig addieren; der Altrest wirkt wie ein Schatten.
	var ghost_mat := line_material(false)
	ghost_mat.albedo_color = Color(0.5, 0.5, 0.5)
	ghost_mesh.mesh = route_mesh(ghost, 0, ghost.size(), true, ghost_mat)

func line_material(transparent: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if transparent:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat

func open_line_material() -> StandardMaterial3D:
	if open_material == null:
		open_material = line_material(false)
	return open_material

func route_mesh(route: Array[Dictionary], from: int, to: int, subdued: bool, mat: StandardMaterial3D) -> Mesh:
	if to - from < 2:
		return null
	# Durchgehendes Band: Normale je Punkt aus den Nachbarpunkten gemittelt -> keine Zacken in Kurven.
	var normals: Array[Vector2] = []
	for j in range(from, to):
		var prev: Vector2 = route[maxi(j - 1, 0)].p
		var next: Vector2 = route[mini(j + 1, route.size() - 1)].p
		var dir := next - prev
		normals.append(dir.normalized().orthogonal() if dir.length() > 0.0001 else (normals[-1] if not normals.is_empty() else Vector2.UP))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(from + 1, to):
		var a: Vector2 = route[i-1].p
		var b: Vector2 = route[i].p
		if a.is_equal_approx(b):
			continue
		var side_a := normals[i-1-from]*line_half_width(float(route[i-1].speed))
		var side_b := normals[i-from]*line_half_width(float(route[i].speed))
		var color_a := line_color(float(route[i-1].speed))
		var color_b := line_color(float(route[i].speed))
		if (float(route[-1].s)>1.02 and float(route[i].s)<1.0) or subdued:
			color_a = color_a.darkened(0.30)
			color_b = color_b.darkened(0.30)
		var corners := [a-side_a,b+side_b,a+side_a,a-side_a,b-side_b,b+side_b]
		for vertex in range(6):
			var at_end := vertex in [1,4,5]
			var p: Vector2 = corners[vertex]
			st.set_color(color_b if at_end else color_a)
			st.set_normal(Vector3.UP)
			var s: float = route[i].s if at_end else route[i-1].s
			st.add_vertex(Vector3(p.x,0.27+s*0.006,p.y))
	st.set_material(mat)
	return st.commit()

func _process(_dt: float) -> void:
	# Schimmern des offenen Linienteils (nur Darstellung).
	if open_material != null and open_mesh.mesh != null:
		var pulse := 0.5 + 0.5*sin(Time.get_ticks_msec()*0.008)
		var k := 0.72+0.6*pulse
		open_material.albedo_color = Color(k, k, k)

# Proportionen je Fahrzeugtyp: Länge, Breite, Karosseriehöhe/-lage, Kabine, Radgröße.
const CAR_STYLES := {
	"coupe": {"len":1.95,"wid":0.94,"y":0.45,"h":0.36,"cab_x":-0.1,"cab_len":0.95,"cab_h":0.35,"wheel":0.44},
	"hatch": {"len":1.75,"wid":0.94,"y":0.47,"h":0.40,"cab_x":-0.2,"cab_len":1.05,"cab_h":0.46,"wheel":0.44},
	"rally": {"len":1.9,"wid":0.96,"y":0.55,"h":0.38,"cab_x":-0.1,"cab_len":0.95,"cab_h":0.38,"wheel":0.56},
	"muscle": {"len":2.2,"wid":1.04,"y":0.44,"h":0.36,"cab_x":-0.35,"cab_len":0.85,"cab_h":0.32,"wheel":0.48},
	"gt": {"len":2.1,"wid":1.0,"y":0.38,"h":0.28,"cab_x":-0.2,"cab_len":0.9,"cab_h":0.28,"wheel":0.40},
}

# Premium-Autos: frei entworfene Modelle aus tools/make_car.py (Blender). Nur mit Vulkan-Renderer;
# auf OpenGL-Geräten (und per Entwickler-Schalter) bleibt die einfache Klötzchen-Grafik.
var premium := true
var road_mesh: MeshInstance3D
const ROAD_SHADER := preload("res://assets/road.gdshader")
# Sichtbarkeitsebenen: 1 = aufragend (wird gespiegelt), 2 = flach am Boden (Spiegelkamera lässt es aus).
const LAYER_TALL := 1
const LAYER_FLAT := 2

func premium_rendering() -> bool:
	return premium and RenderingServer.get_current_rendering_method() != "gl_compatibility"

func noise_texture(frequency: float, seed_value: int, size := 512) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = frequency
	noise.fractal_octaves = 4
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.seamless = true
	tex.width = size
	tex.height = size
	return tex

func premium_road(color: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = ROAD_SHADER
	mat.set_shader_parameter("base_color", color)
	mat.set_shader_parameter("grain_tex", noise_texture(0.06, 7))
	mat.set_shader_parameter("puddle_tex", noise_texture(0.012, 41, 256))
	mat.set_shader_parameter("grain_strength", 0.5 if track.road == "gravel" else 0.35)
	return mat

var spark_pool: Array[CPUParticles3D] = []
var spark_next := 0

func sparks(at: Vector3, side: Vector3, strength: float) -> void:
	# Funkenregen bei Kollisionen: kleiner Vorrat an Einmal-Emittern, reihum wiederverwendet.
	if atmosphere != null and atmosphere.quality == 0:
		return
	if spark_pool.is_empty():
		var streak := BoxMesh.new()
		streak.size = Vector3(0.03, 0.03, 0.24)
		var hot := StandardMaterial3D.new()
		hot.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		hot.vertex_color_use_as_albedo = true
		streak.material = hot
		# Weißglut -> Gelb -> Orange -> glimmendes Rot (Farbe über die Lebensdauer).
		var ramp := Gradient.new()
		ramp.offsets = PackedFloat32Array([0.0, 0.25, 0.65, 1.0])
		ramp.colors = PackedColorArray([Color(1.0, 0.97, 0.75), Color(1.0, 0.8, 0.25), Color(1.0, 0.45, 0.08), Color(0.6, 0.12, 0.02)])
		for i in range(4):
			var p := CPUParticles3D.new()
			p.one_shot = true
			p.emitting = false
			p.explosiveness = 0.9
			p.lifetime = 0.5
			p.mesh = streak
			p.local_coords = false
			p.particle_flag_align_y = true
			p.spread = 55.0
			p.gravity = Vector3(0, -9.8, 0)
			p.initial_velocity_min = 3.0
			p.initial_velocity_max = 8.0
			p.scale_amount_min = 0.6
			p.scale_amount_max = 1.3
			p.color_ramp = ramp
			p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(p)
			spark_pool.append(p)
	var emitter := spark_pool[spark_next]
	spark_next = (spark_next + 1) % spark_pool.size()
	if emitter.emitting:
		return
	emitter.global_position = at
	emitter.direction = (side + Vector3(0, 0.9, 0)).normalized()
	emitter.amount = int(lerpf(12.0, 48.0, strength))
	emitter.restart()

const TERRAIN_SHADER := preload("res://assets/terrain.gdshader")

func distance_texture(margin: float, cells: int) -> Dictionary:
	# Abstand zur Streckenmitte auf einem groben Raster (für weiche Bankett-Übergänge im Gelände-Shader).
	var area := track.bounds.grow(margin)
	var img := Image.create(cells, cells, false, Image.FORMAT_RF)
	var max_d := 24.0
	for iy in range(cells):
		for ix in range(cells):
			var p := area.position + Vector2((ix + 0.5) / cells * area.size.x, (iy + 0.5) / cells * area.size.y)
			img.set_pixel(ix, iy, Color(minf(track.center_distance(p), max_d) / max_d, 0, 0))
	return {"tex": ImageTexture.create_from_image(img), "origin": area.position, "size": area.size, "max": max_d}

func premium_ground(theme: Dictionary, pos: Vector3, size: Vector3, disc: bool) -> void:
	var node := MeshInstance3D.new()
	if disc:
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.5
		cyl.bottom_radius = 0.5
		cyl.height = 1.0
		cyl.radial_segments = 64
		node.mesh = cyl
	else:
		node.mesh = BoxMesh.new()
	node.scale = size
	node.position = pos
	var mat := ShaderMaterial.new()
	mat.shader = TERRAIN_SHADER
	var base := Color(theme.ground)
	var dirt := Color(theme.shoulder)
	mat.set_shader_parameter("grass_a", base.lightened(0.04))
	mat.set_shader_parameter("grass_b", base.darkened(0.08))
	mat.set_shader_parameter("grass_dry", base.lerp(Color("c9b98a"), 0.55))
	mat.set_shader_parameter("dirt_a", dirt)
	mat.set_shader_parameter("dirt_b", dirt.darkened(0.25))
	mat.set_shader_parameter("noise_tex", noise_texture(0.03, 19))
	mat.set_shader_parameter("mow_stripes", theme.island)
	var field := distance_texture(26.0, 192)
	mat.set_shader_parameter("dist_tex", field.tex)
	mat.set_shader_parameter("dist_origin", field.origin)
	mat.set_shader_parameter("dist_size", field.size)
	mat.set_shader_parameter("dist_max", field.max)
	node.material_override = mat
	add_child(node)
	if atmosphere != null:
		atmosphere.terrain_shader = mat

func sort_layers(root: Node) -> void:
	# Flaches (Boden, Fahrbahn, Linien, Lichtflecken) auf Ebene 2, alles Aufragende auf Ebene 1.
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		var geo := node as GeometryInstance3D
		if geo.has_meta("keep_layer"):
			continue
		var box := geo.global_transform * geo.get_aabb()
		geo.layers = LAYER_FLAT if box.end.y < 0.45 else LAYER_TALL
const CAR_PAINT := preload("res://assets/cars/car_paint.gdshader")
# Lacksättigung je Stil, wenn die KI den Lack farbstichig gebacken hat (siehe tools/ai_cars.json).
const PAINT_SAT := {"muscle": 0.34}

func premium_car_path(style: String) -> String:
	return "res://assets/cars/%s.glb" % style

func uses_premium(style: String) -> bool:
	return premium and RenderingServer.get_current_rendering_method() != "gl_compatibility" \
		and ResourceLoader.exists(premium_car_path(style))

func premium_car(car: Node3D, color: Color, style: String) -> StandardMaterial3D:
	var model: Node3D = load(premium_car_path(style)).instantiate()
	model.name = "Model"
	car.add_child(model)
	# Lack je Auto: das Material "Paint" aller Teile durch eine eigene Kopie in der Wagenfarbe ersetzen.
	var paint: StandardMaterial3D = null
	var wheels: Array[Node3D] = []
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.name.begins_with("Wheel_"):
			wheels.append(mesh_node)
		for i in range(mesh_node.mesh.get_surface_count()):
			var mat := mesh_node.mesh.surface_get_material(i) as StandardMaterial3D
			if mat != null and mat.resource_name.begins_with("AIBody"):
				# KI-Karosserie: Lack-Shader tönt den eingebackenen hellgrauen Lack in der Wagenfarbe.
				var shaded := ShaderMaterial.new()
				shaded.shader = CAR_PAINT
				shaded.set_shader_parameter("albedo_tex", mat.albedo_texture)
				shaded.set_shader_parameter("paint_color", color)
				shaded.set_shader_parameter("paint_max_sat", float(PAINT_SAT.get(style, 0.16)))
				if mat.roughness_texture != null:
					shaded.set_shader_parameter("orm_tex", mat.roughness_texture)
					shaded.set_shader_parameter("has_orm", true)
				mesh_node.set_surface_override_material(i, shaded)
				car.set_meta("paint_shader", shaded)
				continue
			if mat != null and mat.resource_name == "Paint":
				if paint == null:
					paint = mat.duplicate()
					paint.albedo_color = color
					paint.clearcoat_enabled = true
					paint.clearcoat = 1.0
					paint.clearcoat_roughness = 0.05
				mesh_node.set_surface_override_material(i, paint)
	car.set_meta("wheels", wheels)
	car.set_meta("body", model.find_child("Body", true, false))
	return paint

func classic_body(car: Node3D, color: Color, player: bool, style: String) -> void:
	# Einfache Klötzchen-Grafik (schwache Geräte / OpenGL).
	var st: Dictionary = CAR_STYLES.get(style, CAR_STYLES.coupe)
	var L: float = st.len
	var W: float = st.wid
	var Y: float = st.y
	var body := shape("box",Vector3(0,Y,0),Vector3(L,st.h,W),color,0,car)
	if player:
		# Eigenes Auto: leicht selbstleuchtende Karosserie (Puls in main.gd).
		var glow := StandardMaterial3D.new()
		glow.albedo_color = color.lightened(0.12)
		glow.roughness = 0.5
		glow.emission_enabled = true
		glow.emission = color
		glow.emission_energy_multiplier = 0.35
		body.material_override = glow
		car.set_meta("paint", glow)
	var cab_y: float = Y + st.h*0.5 + st.cab_h*0.5 - 0.02
	shape("box",Vector3(st.cab_x,cab_y,0),Vector3(st.cab_len,st.cab_h,W*0.83),Color("23404a"),0,car)
	shape("box",Vector3(st.cab_x-0.02,cab_y+st.cab_h*0.5+0.03,0),Vector3(st.cab_len*0.74,0.07,W*0.84),color,0,car)
	shape("box",Vector3(L*0.33,Y+st.h*0.5+0.02,0),Vector3(L*0.28,0.05,0.18),CREAM,0,car)
	for x in [-L*0.32,L*0.32]:
		for z in [-W*0.53,W*0.53]:
			shape("box",Vector3(x,st.wheel*0.7,z),Vector3(st.wheel*1.09,st.wheel,0.23),Color("15262f"),0,car)
	for z in [-W*0.33,W*0.33]:
		shape("box",Vector3(L*0.505,Y+0.02,z),Vector3(0.03,0.12,0.19),Color("fff1b6"),0,car)
		shape("box",Vector3(-L*0.505,Y+0.03,z),Vector3(0.03,0.12,0.19),CORAL,0,car)
	match style:
		"coupe":
			shape("box",Vector3(-L*0.45,Y+0.35,0),Vector3(0.17,0.12,W*1.27),DARK,0,car)
		"rally":
			for z in [-0.3,-0.1,0.1,0.3]:
				shape("box",Vector3(st.cab_x+st.cab_len*0.35,cab_y+st.cab_h*0.5+0.1,z),Vector3(0.1,0.1,0.14),Color("fff1b6"),0,car)
			for z in [-W*0.53,W*0.53]:
				shape("box",Vector3(-L*0.44,st.wheel*0.55,z),Vector3(0.04,0.3,0.24),DARK,0,car)
		"muscle":
			for z in [-0.12,0.12]:
				shape("box",Vector3(0.1,Y+st.h*0.5+0.01,z),Vector3(L*0.95,0.03,0.12),CREAM,0,car)
			shape("box",Vector3(L*0.2,Y+st.h*0.5+0.07,0),Vector3(0.45,0.12,0.36),DARK,0,car)
		"gt":
			for z in [-W*0.35,W*0.35]:
				shape("box",Vector3(-L*0.44,Y+0.3,z),Vector3(0.08,0.3,0.08),DARK,0,car)
			shape("box",Vector3(-L*0.46,Y+0.47,0),Vector3(0.35,0.05,W*1.2),DARK,0,car)

func car_model(color: Color, player := false, style := "coupe") -> Node3D:
	var st: Dictionary = CAR_STYLES.get(style, CAR_STYLES.coupe)
	var L: float = st.len
	var W: float = st.wid
	var Y: float = st.y
	var car := Node3D.new()
	add_child(car)
	if uses_premium(style):
		var paint := premium_car(car, color, style)
		if player and car.has_meta("paint_shader"):
			car.get_meta("paint_shader").set_shader_parameter("glow", 0.25)
		if player and paint != null:
			# Eigenes Auto: leicht leuchtender Lack (Puls in main.gd).
			paint.emission_enabled = true
			paint.emission = color
			paint.emission_energy_multiplier = 0.25
			car.set_meta("paint", paint)
	else:
		classic_body(car, color, player, style)
	if player:
		var halo := MeshInstance3D.new()
		halo.name = "Halo"
		var disc := CylinderMesh.new()
		disc.top_radius = 1.55
		disc.bottom_radius = 1.55
		disc.height = 0.02
		disc.radial_segments = 32
		halo.mesh = disc
		var halo_mat := StandardMaterial3D.new()
		halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		halo_mat.albedo_color = Color(1.0, 0.86, 0.45, 0.38)
		halo.material_override = halo_mat
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Über den Randsteinen (Auto bei y 0,2 + 0,1 = 0,3 > 0,285), sonst verdecken sie den Lichtkranz.
		halo.position = Vector3(0, 0.1, 0)
		car.add_child(halo)
	var exhaust := Node3D.new()
	exhaust.name = "Turbo"
	car.add_child(exhaust)
	for z in [-0.28,0.28]:
		var flame := shape("cone",Vector3(-1.5,0.38,z),Vector3(0.32,1.25,0.32),Color("89ecf0"),0,exhaust)
		flame.rotation.z = PI/2
	exhaust.visible = false
	# Scheinwerferkegel und Rücklicht-Glühen (nur bei Dunkelheit sichtbar, schaltet main.gd).
	var lights := Node3D.new()
	lights.name = "Lights"
	car.add_child(lights)
	var beam := MeshInstance3D.new()
	var bq := QuadMesh.new()
	bq.size = Vector2(7.0,3.4)
	bq.orientation = PlaneMesh.FACE_Y
	beam.mesh = bq
	beam.material_override = Atmosphere.soft_material(Color(1.0,0.93,0.72,0.55), true)
	beam.position = Vector3(L*0.5+3.2,0.06,0)
	lights.add_child(beam)
	for z in [-W*0.33,W*0.33]:
		var tail := MeshInstance3D.new()
		var tq := QuadMesh.new()
		tq.size = Vector2(0.9,0.9)
		tail.mesh = tq
		var tm := Atmosphere.soft_material(Color(1.0,0.2,0.15,0.8), true)
		tm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		tail.material_override = tm
		tail.position = Vector3(-L*0.52,Y+0.03,z)
		lights.add_child(tail)
	lights.visible = false
	# Staubwolke hinter dem Auto auf losem Untergrund (steuert main.gd je nach Belag und Tempo).
	var dust := CPUParticles3D.new()
	dust.name = "Dust"
	dust.emitting = false
	dust.amount = 36
	dust.lifetime = 1.1
	dust.local_coords = false
	dust.position = Vector3(-L*0.5,0.3,0)
	dust.direction = Vector3(-1,0.6,0)
	dust.spread = 35.0
	dust.gravity = Vector3(0,0.4,0)
	dust.initial_velocity_min = 1.0
	dust.initial_velocity_max = 2.6
	dust.scale_amount_min = 0.6
	dust.scale_amount_max = 1.6
	var puff := QuadMesh.new()
	puff.size = Vector2(1.1,1.1)
	var dm := Atmosphere.soft_material(Color(0.78,0.68,0.52,0.35))
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	puff.material = dm
	dust.mesh = puff
	car.add_child(dust)
	return car

func update_tracks(time: float) -> void:
	tyre_tracks.prune(time)
	if tyre_tracks.segments.is_empty():
		skid_mesh.mesh = null
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment in tyre_tracks.segments:
		var a: Vector2 = segment.a
		var b: Vector2 = segment.b
		if segment.kind=="soil":
			# Small gaps suggest a tyre tread instead of a painted brown line.
			b = a.lerp(b,0.80)
		var side := (b-a).normalized().orthogonal()*float(segment.width)*0.5
		var color: Color = segment.color
		color.a *= clampf((TyreTracks.LIFETIME-(time-float(segment.time)))/12.0,0,1)
		var points := [a-side,b+side,a+side,a-side,b-side,b+side]
		for i in range(6):
			var p: Vector2 = points[i]
			st.set_color(color)
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(p.x,float(segment.height_b) if i in [1,4,5] else float(segment.height_a),p.y))
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	st.set_material(mat)
	skid_mesh.mesh = st.commit()
