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

func bake() -> void:
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
	var c := track.bounds.get_center()
	var half := track.bounds.size*0.5 + Vector2(Circuit.HALF_WIDTH+9.0, Circuit.HALF_WIDTH+9.0)
	shape("box", Vector3(c.x,-2.5,c.y), Vector3(half.x*2+160,0.4,half.y*2+160), Color(theme.sea))
	if theme.island:
		# Insel: Sandsockel, Strand, Wiese mit Mähstreifen.
		shape("disc", Vector3(c.x,-1.2,c.y), Vector3(half.x*2.35,2.0,half.y*2.35), Color(theme.rim))
		shape("disc", Vector3(c.x,-0.18,c.y), Vector3(half.x*2.3,0.35,half.y*2.3), Color(theme.rim2))
		shape("disc", Vector3(c.x,0.01,c.y), Vector3(half.x*2.15,0.15,half.y*2.15), Color(theme.ground))
		for strip in range(-12,13):
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
		shape("box", Vector3(c.x,0.02,c.y), Vector3(half.x*2+66,0.12,half.y*2+56), Color(theme.ground))
		if track.theme == "city":
			for gx in range(-8,9):
				shape("box",Vector3(c.x+gx*9.0,0.09,c.y),Vector3(0.12,0.01,half.y*2+50),Color(theme.stripe))
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
	bake()
	for key in ["ground","stripe","shoulder","rim2"]:
		atmosphere.register_tint(material(Color(theme[key])))
	var road_color := Color("8b6f4e") if track.road == "gravel" else Color("394950")
	atmosphere.road_material = material(road_color)
	atmosphere.road_color = road_color
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

func build_asphalt_road() -> void:
	road_strip(-3.5, 3.5, 0.17, Color("394950"), 0.0, 1.0, true)
	road_strip(-3.37, -3.29, 0.185, Color("e8dfc8"), 0.0, 1.0, true, true)
	road_strip(3.29, 3.37, 0.185, Color("e8dfc8"), 0.0, 1.0, true, true)
	var curb_count := int(track.length/0.86)
	for i in range(curb_count):
		var s := float(i) / curb_count
		for edge in [-1.0, 1.0]:
			var p := track.at(s, edge * 3.75)
			# An der Kreuzung (Acht) keine Randsteine quer über die andere Fahrbahn.
			if track.other_branch_distance(p, s) > Circuit.HALF_WIDTH + 0.6:
				shape("box", Vector3(p.x,0.21,p.y), Vector3(0.86,0.15,0.58), CORAL if i % 4 < 2 else CREAM, -track.tangent(s).angle())
		if i % 4 == 0:
			var p := track.at(s)
			if track.other_branch_distance(p, s) > Circuit.HALF_WIDTH + 0.2:
				shape("box", Vector3(p.x,0.182+s*0.004,p.y), Vector3(0.8,0.016,0.06), Color("8b9390"), -track.tangent(s).angle())

func build_gravel_road() -> void:
	# Schotterpiste: braune Fahrbahn mit Körnung, keine Randlinien; Holzpfosten und Feldsteine statt Randsteinen.
	road_strip(-3.5, 3.5, 0.17, Color("8b6f4e"), 0.0, 1.0, true)
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
	pool.position = Vector3(head.x, 0.24, head.z)
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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

func build_prop(prop: Dictionary) -> void:
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

func road_strip(inner: float, outer: float, y: float, color: Color, start_s := 0.0, end_s := 1.0, stagger := false, skip_crossing := false) -> void:
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

static func line_half_width(speed: float) -> float:
	# Langsam = 3x so breit wie früher (0,32 m), damit langsam und schnell klar unterscheidbar sind.
	return lerpf(0.96,0.10,clampf((speed-5.0)/24.0,0.0,1.0))

static func line_color(speed: float) -> Color:
	return Color("fff1b8").lerp(Color("ed3c32"),clampf((speed-5.0)/24.0,0.0,1.0))

func draw_route(route: Array[Dictionary], subdued := false, open_from := -1, ghost: Array[Dictionary] = []) -> void:
	# open_from: Routenindex, ab dem die Linie offen ist (schimmert); ghost: alter Rest während einer Probe.
	var split := route.size() if open_from < 0 else clampi(open_from, 0, route.size())
	line_mesh.mesh = route_mesh(route, 0, split, subdued, line_material(false))
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

func car_model(color: Color, player := false, style := "coupe") -> Node3D:
	var st: Dictionary = CAR_STYLES.get(style, CAR_STYLES.coupe)
	var L: float = st.len
	var W: float = st.wid
	var Y: float = st.y
	var car := Node3D.new()
	add_child(car)
	var body := shape("box",Vector3(0,Y,0),Vector3(L,st.h,W),color,0,car)
	if player:
		# Eigenes Auto: leicht selbstleuchtende Karosserie und pulsierender Lichtkranz am Boden.
		var glow := StandardMaterial3D.new()
		glow.albedo_color = color.lightened(0.12)
		glow.roughness = 0.5
		glow.emission_enabled = true
		glow.emission = color
		glow.emission_energy_multiplier = 0.35
		body.material_override = glow
		body.name = "Body"
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
		halo.position = Vector3(0, 0.05, 0)
		car.add_child(halo)
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
