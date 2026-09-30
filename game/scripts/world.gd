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
const WATER_COLORS := ["39959c", "4aa6a5", "53b3ac", "3f7f80", "2f6f7a", "2d7fa1"]
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
			add_overlay(node, lit_overlay_color(mat.albedo_color))
		add_child(node)

const THEMES := {
	"coast": {"sky":"327d88","sea":"39959c","ground":"8eae85","stripe":"89a981","rim":"c7b79a","rim2":"f2e9d5","shoulder":"b69c73","mud":"896c4d","island":true},
	"city": {"sky":"283440","sea":"30383f","ground":"7c8784","stripe":"86918e","rim":"5d6569","rim2":"a3aaa9","shoulder":"9ba39f","mud":"6d665a","island":false},
	"forest": {"sky":"36614d","sea":"2c4a38","ground":"4f7b49","stripe":"4a7444","rim":"5f4f39","rim2":"76654a","shoulder":"5f5a34","mud":"4a3524","island":false},
	"harbor": {"sky":"4d6f80","sea":"2f6f7a","ground":"8a8f8c","stripe":"7f8583","rim":"5d6569","rim2":"a3aaa9","shoulder":"6f7472","mud":"5a554a","island":false},
	"fair": {"sky":"1d2240","sea":"1f2a3a","ground":"7a6f5a","stripe":"72684f","rim":"4d4436","rim2":"8a7d63","shoulder":"8d7f63","mud":"5a4a36","island":false},
	"quarry": {"sky":"8aa3b0","sea":"3f4f55","ground":"9a948a","stripe":"918b80","rim":"6f6a61","rim2":"a8a296","shoulder":"8a7e6a","mud":"6a5a44","island":false,"rock":"8d8a83"},
	"kids": {"sky":"d9cbb4","sea":"8a6a4a","ground":"b98a5a","stripe":"a87a4c","rim":"e0e0e0","rim2":"d64541","shoulder":"c49a6c","mud":"b0413e","island":false,"road":"e8742a","planks":true},
	"mountain": {"sky":"6fa7c9","sea":"2d7fa1","ground":"8a9a5b","stripe":"84935a","rim":"8f836d","rim2":"b8ab8f","shoulder":"b09a74","mud":"7a6448","island":false,"rock":"b3a891"},
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
	diorama = premium_rendering() and ResourceLoader.exists(DIORAMA_PATH % track.id)
	if diorama:
		# Gebackenes Diorama (Blender, tools/diorama.py): Boden, Straße, Häuser, Bäume, Umgebungsverdeckung.
		build_diorama()
	elif not track.terrain.is_empty():
		# Gelände mit Höhenrelief (Berg, Steilküste): Netz aus dem Höhenraster der Strecke.
		build_terrain(theme, fancy_ground)
	elif theme.island:
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
		# Stadt/Wald: großflächiger Boden bis zum Horizont mit Randsockel. Mit Kaikante (quay_z) endet das Land dort an
		# einer Kaimauer; dahinter liegt das Meer (Wasserfläche des Themas, tiefer als der Kai) bis zum Horizont.
		var rim_z := Vector2(c.y - (half.y*2+60)*0.5, c.y + (half.y*2+60)*0.5)
		var ground_z := Vector2(c.y - (half.y*2+56)*0.5, c.y + (half.y*2+56)*0.5)
		var quay := track.quay_z < 1e8
		if quay and track.quay_dir > 0.0:
			rim_z.y = minf(rim_z.y, track.quay_z)
			ground_z.y = minf(ground_z.y, track.quay_z)
		elif quay:
			rim_z.x = maxf(rim_z.x, track.quay_z)
			ground_z.x = maxf(ground_z.x, track.quay_z)
		var gz := (ground_z.x + ground_z.y)*0.5
		var gd := ground_z.y - ground_z.x
		shape("box", Vector3(c.x,-0.6,(rim_z.x + rim_z.y)*0.5), Vector3(half.x*2+70,1.2,rim_z.y - rim_z.x), Color(theme.rim))
		if quay:
			# Kaimauer und heller Kantenstein auf der Landseite der Kante.
			shape("box", Vector3(c.x,-1.25,track.quay_z-0.45*track.quay_dir), Vector3(half.x*2+70,2.5,0.9), Color("767b7d"))
			shape("box", Vector3(c.x,0.1,track.quay_z-0.35*track.quay_dir), Vector3(half.x*2+70,0.2,0.7), Color("b9b8b0"))
		if theme.get("planks", false):
			# Kinderzimmer: Parkett aus 2,4 m breiten Dielen in zwei Holztönen mit Fugen, Spielzeugbahn liegt direkt darauf.
			var width := half.x*2+66
			var count := int(width / 2.4)
			for k in range(count):
				var x := c.x - width*0.5 + (k + 0.5)*2.4
				var tone := Color(theme.ground).lerp(Color(theme.stripe), 0.5 + 0.5*sin(k*2.3))
				shape("box", Vector3(x,0.02,gz), Vector3(2.36,0.12,gd), tone)
		elif fancy_ground:
			premium_ground(theme, Vector3(c.x,0.02,gz), Vector3(half.x*2+66,0.12,gd), false)
		else:
			shape("box", Vector3(c.x,0.02,gz), Vector3(half.x*2+66,0.12,gd), Color(theme.ground))
		if track.theme == "city":
			for gx in range(-8,9):
				shape("box",Vector3(c.x+gx*9.0,0.09,c.y),Vector3(0.12,0.01,half.y*2+50),Color(theme.stripe))
	if not fancy_ground and not theme.get("planks", false):
		road_strip(-4.9, 4.9, 0.12, Color(theme.shoulder))
	for zone in track.surfaces:
		var sides: Array = [[4.05,4.9]] if zone.side=="outer" else ([[-4.9,-4.05]] if zone.side=="inner" else [[4.05,4.9],[-4.9,-4.05]])
		for band in sides:
			road_strip(band[0],band[1],0.13,Color(theme.mud),float(zone.from),float(zone.to))
	if diorama:
		pass
	elif track.road == "gravel":
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
	build_stunts()
	build_shortcuts()
	for prop in track.props:
		if diorama and (str(prop.get("type", "")) in DIORAMA_BAKED or diorama_blocks(prop)):
			continue   # im Diorama enthalten bzw. läge auf einer Diorama-Straße
		build_prop(prop)
	for lamp in diorama_lamps:
		build_prop({"type": "lamp", "x": lamp.x, "z": lamp.z, "toward": lamp.toward})
	flush_ai_props()
	flush_cards()
	atmosphere.bake_rain_lights(track.bounds.grow(Circuit.HALF_WIDTH + 12.0))
	bake()
	for key in ["ground","stripe","shoulder","rim2"]:
		atmosphere.register_tint(material(Color(theme[key])))
	var road_color := Color(theme.get("road", "8b6f4e" if track.road == "gravel" else "394950"))
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
	marker.position = Vector3(start.x,0.31 + track.surface_z(0.0),start.y)
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

func build_terrain(theme: Dictionary, fancy: bool) -> void:
	var tr: Dictionary = track.terrain
	var w := int(tr.w)
	var h := int(tr.h)
	var cell := float(tr.cell)
	var ox := float(tr.origin[0])
	var oz := float(tr.origin[1])
	var hs: Array = tr.heights
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vtx := func(ix: int, iz: int) -> Vector3:
		return Vector3(ox + ix * cell, float(hs[iz * w + ix]) + 0.02, oz + iz * cell)
	for iz in range(h - 1):
		for ix in range(w - 1):
			var a: Vector3 = vtx.call(ix, iz)
			var b: Vector3 = vtx.call(ix + 1, iz)
			var c: Vector3 = vtx.call(ix + 1, iz + 1)
			var d: Vector3 = vtx.call(ix, iz + 1)
			for tri in [[a, b, c], [a, c, d]]:
				var n: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
				if n.y < 0.0:
					n = -n
				for p in tri:
					st.set_normal(n)
					st.add_vertex(p)
	var node := MeshInstance3D.new()
	node.mesh = st.commit()
	if fancy:
		# Gleicher Gelände-Shader wie auf ebenen Strecken (Rasen/Fels, weicher Bankett-Übergang).
		premium_ground(theme, Vector3.ZERO, Vector3.ONE, false)
		var flat_ground: MeshInstance3D = get_child(get_child_count() - 1)
		node.material_override = flat_ground.material_override
		flat_ground.queue_free()
	else:
		node.material_override = material(Color(theme.ground))
	add_child(node)
	# Steilwände: Flächen mit starker Neigung felsgrau statt Rasen (nur optisch, eigener Durchgang).
	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color(theme.get("rock", "9a9486"))
	rock.roughness = 0.95
	var cliff := SurfaceTool.new()
	cliff.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for iz in range(h - 1):
		for ix in range(w - 1):
			var a: Vector3 = vtx.call(ix, iz)
			var b: Vector3 = vtx.call(ix + 1, iz)
			var c: Vector3 = vtx.call(ix + 1, iz + 1)
			var d: Vector3 = vtx.call(ix, iz + 1)
			var slope := maxf(absf(a.y - c.y), absf(b.y - d.y)) / (cell * 1.414)
			if slope < 0.9:
				continue
			any = true
			for tri in [[a, b, c], [a, c, d]]:
				var n: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
				if n.y < 0.0:
					n = -n
				for p in tri:
					cliff.set_normal(n)
					cliff.add_vertex(p + Vector3(0, 0.03, 0))
	if any:
		var rocks := MeshInstance3D.new()
		rocks.mesh = cliff.commit()
		rocks.material_override = rock
		add_child(rocks)

func build_shortcuts() -> void:
	# Fahrbahn der Abkürzungen (schmaler, eigener Belag) entlang ihres Pfads.
	for sc in track.shortcuts:
		var trail: Array = sc.path
		var half := float(sc.width) * 0.5
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in range(trail.size() - 1):
			var a: Vector2 = trail[i]
			var b: Vector2 = trail[i + 1]
			var nrm := (b - a).normalized().orthogonal() * half
			var ya := 0.165 + track.terrain_height(a)
			var yb := 0.165 + track.terrain_height(b)
			var q := [Vector3(a.x - nrm.x, ya, a.y - nrm.y), Vector3(a.x + nrm.x, ya, a.y + nrm.y), Vector3(b.x + nrm.x, yb, b.y + nrm.y), Vector3(b.x - nrm.x, yb, b.y - nrm.y)]
			for j in [0, 2, 1, 0, 3, 2]:
				st.set_normal(Vector3.UP)
				st.add_vertex(q[j])
		var node := MeshInstance3D.new()
		node.mesh = st.commit()
		var color := Color("8b6f4e") if str(sc.surface) == "gravel" else Color("3f4c52")
		node.material_override = premium_road(color) if premium_rendering() else material(color)
		add_child(node)

func build_stunts() -> void:
	# 2,5D-Bauteile: Stützpfeiler unter erhöhter Fahrbahn, Holzschanzen, Looping-Ring.
	var pillar := Color("7d8386")
	var steps := int(track.length / 6.0)
	for i in range(steps):
		var s := float(i) / steps
		var h := track.base_height(s)
		if h > 1.2 and not track.in_gap(s):
			for side in [-1.0, 1.0]:
				var p := track.at(s, side * (Circuit.HALF_WIDTH - 0.6))
				# Pfeiler nur, wo die Fahrbahn wirklich über dem Gelände liegt (Brücke), nicht am Berg.
				var ground := track.terrain_height(p)
				if h - ground > 1.2:
					shape("box", Vector3(p.x, (h + ground) * 0.5, p.y), Vector3(0.6, h - ground, 0.6), pillar)
	var wood := Color("a0764a")
	var dark_wood := Color("6e4d2e")
	for r in track.ramps:
		var s0 := float(r.s)
		var len_m := float(r.length)
		var height := float(r.height)
		var n := maxi(4, int(len_m / 0.5))
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for k in range(n):
			var sa := s0 + len_m * k / n / track.length
			var sb := s0 + len_m * (k + 1) / n / track.length
			var ha := track.base_height(sa) + height * k / n + 0.2
			var hb := track.base_height(sb) + height * (k + 1) / n + 0.2
			var w := Circuit.HALF_WIDTH - 0.3
			var q := [track.at(sa, -w), track.at(sa, w), track.at(sb, w), track.at(sb, -w)]
			var hs := [ha, ha, hb, hb]
			for j in [0, 2, 1, 0, 3, 2]:
				st.set_normal(Vector3.UP)
				st.add_vertex(Vector3(q[j].x, hs[j], q[j].y))
			# Seitenwangen
			for side in [-w, w]:
				var p0 := track.at(sa, side)
				var p1 := track.at(sb, side)
				var base := track.base_height(sa) + 0.18
				var quad := [Vector3(p0.x, base, p0.y), Vector3(p1.x, base, p1.y), Vector3(p1.x, hb, p1.y), Vector3(p0.x, ha, p0.y)]
				for j in [0, 1, 2, 0, 2, 3]:
					st.set_normal(Vector3(0, 0, 1))
					st.add_vertex(quad[j])
		# Stirnseite an der Absprungkante
		var se := s0 + len_m / track.length
		var e0 := track.at(se, -Circuit.HALF_WIDTH + 0.3)
		var e1 := track.at(se, Circuit.HALF_WIDTH - 0.3)
		var top := track.base_height(se) + height + 0.2
		var low := track.base_height(se) + 0.18
		var face := [Vector3(e0.x, low, e0.y), Vector3(e1.x, low, e1.y), Vector3(e1.x, top, e1.y), Vector3(e0.x, top, e0.y)]
		for j in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3(0, 0, 1))
			st.add_vertex(face[j])
		var node := MeshInstance3D.new()
		node.mesh = st.commit()
		var mat := material(wood)
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		node.material_override = mat
		add_child(node)
		# Bohlenfugen quer über die Schanze
		for k in range(1, n):
			var sk := s0 + len_m * k / n / track.length
			var pk := track.at(sk)
			shape("box", Vector3(pk.x, track.base_height(sk) + height * k / n + 0.21, pk.y), Vector3(0.04, 0.01, (Circuit.HALF_WIDTH - 0.3) * 2.0), dark_wood, -track.tangent(sk).angle())
	for l in track.loops:
		build_loop(float(l.s), float(l.radius))

func build_loop(s: float, radius: float) -> void:
	# Looping wie eine Spielzeugbahn: schmales Band (eine Spur) mit Seitenborden. Es steigt auf der rechten
	# Fahrbahnhälfte auf, versetzt sich beim Überschlag seitlich (Spiralstück) und landet links daneben.
	var origin := track.at(s)
	var fwd := track.tangent(s)
	var side := Vector2(-fwd.y, fwd.x)
	var base := track.base_height(s) + 0.2
	var n := 72
	var w := Circuit.LOOP_BAND
	var toy := track.theme == "kids"
	var band := SurfaceTool.new()
	band.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rails := SurfaceTool.new()
	rails.begin(Mesh.PRIMITIVE_TRIANGLES)
	var point := func(th: float, lateral: float, lift: float) -> Vector3:
		# Punkt auf dem Band: lift > 0 = zur Ringmitte hin (Innenseite, auf der das Auto fährt).
		var c: Vector2 = origin + fwd * (radius - lift) * sin(th) + side * (track.loop_lateral(th) + lateral)
		return Vector3(c.x, base + radius - (radius - lift) * cos(th), c.y)
	for k in range(n):
		var t0: float = TAU * k / n
		var t1: float = TAU * (k + 1) / n
		var inward := Vector3(-fwd.x * sin(t0), cos(t0), -fwd.y * sin(t0))
		var quad := [point.call(t0, -w, 0.0), point.call(t0, w, 0.0), point.call(t1, w, 0.0), point.call(t1, -w, 0.0)]
		for j in [0, 1, 2, 0, 2, 3]:
			band.set_normal(inward)
			band.add_vertex(quad[j])
		# Borde: senkrechte Streifen an beiden Bandkanten, 0,3 m zur Ringmitte hin.
		for edge in [-w, w]:
			var r := [point.call(t0, edge, 0.0), point.call(t0, edge, 0.3), point.call(t1, edge, 0.3), point.call(t1, edge, 0.0)]
			var out := Vector3(side.x, 0.0, side.y) * signf(edge)
			for j in [0, 1, 2, 0, 2, 3]:
				rails.set_normal(out)
				rails.add_vertex(r[j])
	var band_node := MeshInstance3D.new()
	band_node.mesh = band.commit()
	# Halbtransparent, damit das Auto innen (oben kopfüber) aus der Draufsicht sichtbar bleibt.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.45, 0.12, 0.7) if toy else Color(0.72, 0.77, 0.82, 0.65)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.metallic = 0.0 if toy else 0.5
	mat.roughness = 0.35
	band_node.material_override = mat
	band_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(band_node)
	var rail_node := MeshInstance3D.new()
	rail_node.mesh = rails.commit()
	var rail_mat := StandardMaterial3D.new()
	rail_mat.albedo_color = Color("e8611a") if toy else Color("4f565c")
	rail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	rail_mat.metallic = 0.0 if toy else 0.6
	rail_mat.roughness = 0.4
	rail_node.material_override = rail_mat
	add_child(rail_node)
	# Stützen: je eine schlanke Säule außen an der vorderen und hinteren Ringseite (Höhe = Radius).
	for th in [PI * 0.5, PI * 1.5]:
		var lateral := track.loop_lateral(th)
		var p: Vector2 = origin + fwd * radius * sin(th) + side * (lateral + signf(lateral) * (w + 0.25))
		var y := base + radius
		shape("box", Vector3(p.x, y * 0.5, p.y), Vector3(0.22, y, 0.22), Color("e8611a") if toy else Color("5d6368"))

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
			if track.in_gap((s0 + s1) * 0.5):
				continue
			var a0 := track.at(s0, track.edge_offset(s0, lo))
			var a1 := track.at(s0, track.edge_offset(s0, hi))
			var b0 := track.at(s1, track.edge_offset(s1, lo))
			var b1 := track.at(s1, track.edge_offset(s1, hi))
			var ha := track.base_height(s0)
			var hb := track.base_height(s1)
			var quads := [
				[Vector3(a0.x, top + ha, a0.y), Vector3(a1.x, top + ha, a1.y), Vector3(b1.x, top + hb, b1.y), Vector3(b0.x, top + hb, b0.y)],
				[Vector3(a1.x, bottom + ha, a1.y), Vector3(b1.x, bottom + hb, b1.y), Vector3(b1.x, top + hb, b1.y), Vector3(a1.x, top + ha, a1.y)],
				[Vector3(b0.x, bottom + hb, b0.y), Vector3(a0.x, bottom + ha, a0.y), Vector3(a0.x, top + ha, a0.y), Vector3(b0.x, top + hb, b0.y)],
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
		add_overlay(mesh, lit_overlay_color(color))
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
# Modelle, deren Längsachse in der KI-Ausgabe entlang z liegt; das Streckenformat erwartet w (Breite) entlang x.
const AI_PROP_YAW := {"hafen_lagerhalle": 90.0, "hafen_frachtschiff": 90.0, "hafen_frachtschiff_einfach": 90.0, "hafen_container": 90.0,
	"hafen_kran": -90.0, "drift_betonblock": 90.0, "serra_leitplanke": 90.0, "drift_parkhaus": 90.0, "drift_reifenwand": 90.0}
var ai_prop_meshes := {}
var ai_prop_batches := {}

# Laternen aus dem Bausatz (tools/make_lamp.py): Mast im Ursprung, Ausleger in +x; Kopf (Reichweite, Höhe) in Modellmetern.
const POLE_MODELS := ["stadt_laterne_kit"]
const LAMP_HEAD := {"stadt_laterne_kit": Vector2(1.2, 4.1)}
const METAL_SCALE := {"hafen_kran": 0.15}

func ai_prop_mesh(name: String) -> Mesh:
	if not ai_prop_meshes.has(name):
		var mesh: Mesh = null
		if ResourceLoader.exists(AI_PROP_PATH % name):
			var scene: Node = load(AI_PROP_PATH % name).instantiate()
			var found := scene.find_children("*", "MeshInstance3D", true, false)
			if not found.is_empty():
				mesh = (found[0] as MeshInstance3D).mesh
				for i in range(mesh.get_surface_count()):
					var kit_mat := mesh.surface_get_material(i)
					if kit_mat != null and kit_mat.resource_name.begins_with("K_"):
						mesh.surface_set_material(i, kit_material(kit_mat.resource_name.substr(2)))
				if METAL_SCALE.has(name.trim_suffix("_lo")):
					# Lack statt blankem Metall: die KI hält glänzende weiße Farbe teils für Metall (wirkt silbrig).
					for i in range(mesh.get_surface_count()):
						var mat := mesh.surface_get_material(i) as StandardMaterial3D
						if mat != null:
							mat = mat.duplicate()
							mat.metallic = float(METAL_SCALE[name.trim_suffix("_lo")])
							mesh.surface_set_material(i, mat)
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
		if absf(float(AI_PROP_YAW.get(name, 0.0))) == 90.0:
			footprint = Vector2(footprint.y, footprint.x)   # Grundfläche in Modellachsen (vor der Drehung)
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
	if POLE_MODELS.has(name):
		anchor = Vector3.ZERO        # Mast im Ursprung des Modells: er steht genau auf (x, z), der Ausleger ragt hinaus
	var origin := Vector3(x, base_y + track.terrain_height(Vector2(x, z)), z) - basis * anchor
	if not ai_prop_batches.has(name):
		ai_prop_batches[name] = []
	ai_prop_batches[name].append(Transform3D(basis, origin))
	return true

const CHUNK := 24.0            # Kachelgröße (m): Kacheln außerhalb des Bildes zeichnet die GPU nicht
var detail_hi: Array[GeometryInstance3D] = []
var detail_lo: Array[GeometryInstance3D] = []
var overlay_nodes: Array = []  # [Knoten, Zusatzlicht-Material] – nur bei Dunkelheit eingehängt
var detail_high := true

func add_overlay(node: GeometryInstance3D, mat: Material) -> void:
	if mat != null:
		overlay_nodes.append([node, mat])

func set_overlays(on: bool) -> void:
	# Zusatzlicht (Laternen) kostet einen weiteren Durchgang; am Tag trägt es nichts bei.
	for entry in overlay_nodes:
		if is_instance_valid(entry[0]):
			entry[0].material_overlay = entry[1] if on else null

func set_detail(high: bool) -> void:
	# Volle Modelle nur nah; in der Übersicht die vereinfachte Fassung. Schatten immer von der einfachen.
	if high == detail_high:
		return
	detail_high = high
	for node in detail_hi:
		node.visible = high
	for node in detail_lo:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if high else GeometryInstance3D.SHADOW_CASTING_SETTING_ON

func multimesh_node(mesh: Mesh, list: Array, label: String) -> MultiMeshInstance3D:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = list.size()
	for i in range(list.size()):
		multi.set_instance_transform(i, list[i])
	var node := MultiMeshInstance3D.new()
	node.name = label
	node.multimesh = multi
	add_child(node)
	return node

# --- Baumkarten (Billboards): ein Bild pro Baum statt eines 3D-Modells ---
const CARD_SHADER := preload("res://assets/cards/tree_card.gdshader")
const CARD_PATH := "res://assets/cards/%s.png"
const CARD_TREES := ["serra_olivenbaum", "serra_pinie"]
var card_batches := {}

func place_card(name: String, x: float, z: float, height: float) -> bool:
	if not ResourceLoader.exists(CARD_PATH % name):
		return false
	# Feste Zufallswerte je Position: Größe ±15 %, Spiegelung.
	var h := fposmod(x * 12.9898 + z * 78.233, 1.0)
	var size := height * (0.85 + 0.3 * h)
	var flip := -1.0 if fposmod(x * 3.7 + z * 1.3, 2.0) < 1.0 else 1.0
	if not card_batches.has(name):
		card_batches[name] = []
	card_batches[name].append(Transform3D(Basis.from_scale(Vector3(size * flip, size, size)), Vector3(x, 0.1 + track.terrain_height(Vector2(x, z)), z)))
	return true

func flush_cards() -> void:
	for name in card_batches:
		var tex: Texture2D = load(CARD_PATH % name)
		var quad := QuadMesh.new()
		quad.size = Vector2(float(tex.get_width()) / tex.get_height(), 1.0)
		quad.center_offset = Vector3(0, 0.5, 0)
		var mat := ShaderMaterial.new()
		mat.shader = CARD_SHADER
		mat.set_shader_parameter("card", tex)
		quad.material = mat
		var chunks := {}
		for t in card_batches[name]:
			var key := Vector2i(floori(t.origin.x / CHUNK), floori(t.origin.z / CHUNK))
			if not chunks.has(key):
				chunks[key] = []
			chunks[key].append(t)
		for key in chunks:
			var node := multimesh_node(quad, chunks[key], "Karte_%s_%d_%d" % [name, key.x, key.y])
			# Kulling-Box: Karten sind im Schattendurchgang zur Kamera gedreht, großzügig bemessen.
			node.extra_cull_margin = 8.0
	card_batches.clear()

const ALWAYS_FULL := ["hafen_kran", "hafen_frachtschiff", "hafen_frachtschiff_einfach"]
const MASS_COUNT := 6   # ab so vielen Exemplaren je Strecke gilt ein Modell als Massenware

func flush_ai_props() -> void:
	# Je Modell und Kachel ein MultiMesh (Aussortieren außerhalb des Bildes), dazu eine vereinfachte Fassung
	# (<name>_lo) für Schatten und Übersicht.
	for name in ai_prop_batches:
		var chunks := {}
		for t in ai_prop_batches[name]:
			var key := Vector2i(floori(t.origin.x / CHUNK), floori(t.origin.z / CHUNK))
			if not chunks.has(key):
				chunks[key] = []
			chunks[key].append(t)
		var hi := ai_prop_mesh(name)
		# Vereinfachte Fassung nur für Massenware (Bäume, Laternen, Zäune …): dort spart sie viel und fällt nicht auf.
		# Einzelne Bauten und Blickfänge bleiben immer voll – vereinfacht zerfallen ihre Formen sichtbar.
		var mass: bool = ai_prop_batches[name].size() >= MASS_COUNT and not name in ALWAYS_FULL
		var lo: Mesh = ai_prop_mesh(name + "_lo") if mass else null
		for key in chunks:
			var node := multimesh_node(hi, chunks[key], "KI_%s_%d_%d" % [name, key.x, key.y])
			add_overlay(node, lit_overlay(hi))
			if lo != null:
				node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				var simple := multimesh_node(lo, chunks[key], "KI_%s_lo_%d_%d" % [name, key.x, key.y])
				simple.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
				add_overlay(simple, lit_overlay(lo))
				detail_hi.append(node)
				detail_lo.append(simple)
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
		mat.set_shader_parameter("use_vertex_color", base.vertex_color_use_as_albedo)
	return mat

func lit_overlay_color(color: Color) -> ShaderMaterial:
	# Wie lit_overlay, aber für einfarbige Bauteile (Randsteine, Markierungen, Klötzchen-Deko).
	if not premium_rendering():
		return null
	var mat := ShaderMaterial.new()
	mat.shader = LIT_OVERLAY
	mat.set_shader_parameter("tint", color)
	return mat

func generic_prop(prop: Dictionary) -> bool:
	# Streckenformat-Typen, die in beiden Grafikstufen gelten: "water" und "ai" (KI-Modell mit Klötzchen-Ersatz).
	var x := float(prop.get("x",0.0))
	var z := float(prop.get("z",0.0))
	var rot := -deg_to_rad(float(prop.get("rot",0.0)))
	match str(prop.get("type","")):
		"crane":
			build_crane(x, z, rot, float(prop.get("h", 16.0)))
			return true
		"ship":
			build_ship(x, z, rot, float(prop.get("length", 34.0)))
			return true
		"water":
			# Wasserfläche knapp über dem Boden, unter der Fahrbahn (Wasser-Shader über die Farbe).
			shape("box", Vector3(x, 0.06 + track.terrain_height(Vector2(x, z)), z), Vector3(float(prop.get("w",4.0)), 0.12, float(prop.get("d",4.0))), Color("3f7f80"), rot)
			return true
		"ai":
			var model := str(prop.get("model",""))
			if low_detail and LOW_VARIANTS.has(model) and ResourceLoader.exists(AI_PROP_PATH % LOW_VARIANTS[model]):
				model = LOW_VARIANTS[model]
			var h := float(prop.get("h", 0.0))
			var fp := Vector2(float(prop.get("w", 0.0)), float(prop.get("d", 0.0)))
			# Bäume als Bildkarten (billig, weiche Kronen), sonst KI-Modell.
			if premium_rendering() and model in CARD_TREES and place_card(model, x, z, h if h > 0.0 else 5.0):
				return true
			# "y": Fußpunkt über/unter dem Gelände (z. B. Schiffsrumpf unter der Wasserlinie).
			if premium_rendering() and place_ai(model, x, z, rot, h, fp, false, float(prop.get("y", 0.0))):
				return true
			if model == "hafen_kran" and prop.has("feet"):
				build_crane(float(prop.feet[0]), float(prop.feet[1]), rot, 16.0)   # einfache Grafik: Grundformen
				return true
			if model.begins_with("hafen_frachtschiff"):
				build_ship(x, z, rot, fp.x)   # einfache Grafik: Frachter aus Grundformen statt Klotz
				return true
			# Ersatz, solange das Modell fehlt (oder einfache Grafik): Klotz in Grundfarbe.
			var size := Vector3(fp.x if fp.x > 0.0 else maxf(h * 0.5, 0.8), h if h > 0.0 else 2.0, fp.y if fp.y > 0.0 else maxf(h * 0.5, 0.8))
			var base := track.terrain_height(Vector2(x, z))
			shape("box", Vector3(x, base + size.y * 0.5, z), size, Color(str(prop.get("color","a3aaa9"))), rot)
			return true
	return false

func beam(frame: Transform3D, a: Vector3, b: Vector3, thick: float, color: Color) -> void:
	# Stab von a nach b (lokale Koordinaten des Rahmens), quadratischer Querschnitt.
	var d := b - a
	var up := d.normalized()
	var axis := Vector3.UP.cross(up)
	var rot := Basis() if axis.length() < 1e-4 else Basis(axis.normalized(), Vector3.UP.angle_to(up))
	shape_transform("box", frame * Transform3D(rot * Basis.from_scale(Vector3(thick, d.length(), thick)), (a + b) * 0.5), color)

func block(frame: Transform3D, center: Vector3, size: Vector3, color: Color) -> void:
	shape_transform("box", frame * Transform3D(Basis.from_scale(size), center), color)

func build_crane(x: float, z: float, rot: float, h: float) -> void:
	# Containerbrücke aus Grundformen: Portal mit vier Beinen auf der Kaifläche, Ausleger über das Wasser
	# (lokal +z), Maschinenhaus, Führerhaus, A-Rahmen mit Abspannung, Laufkatze mit Spreader.
	var f := Transform3D(Basis(Vector3.UP, rot), Vector3(x, track.terrain_height(Vector2(x, z)), z))
	var red := Color("b8392b")
	var white := Color("e9e6df")
	var steel := Color("4a4f54")
	for lx in [-5.0, 5.0]:
		block(f, Vector3(lx, 0.45, 0.0), Vector3(1.1, 0.9, 7.0), steel)
		for lz in [-2.5, 2.5]:
			beam(f, Vector3(lx, 0.9, lz), Vector3(lx, h, lz), 0.75, red)
		block(f, Vector3(lx, h - 0.45, 0.0), Vector3(0.85, 0.9, 5.8), red)
		beam(f, Vector3(lx, 1.5, -2.5), Vector3(lx, h - 1.0, 2.5), 0.3, red)
	for lz in [-2.5, 2.5]:
		block(f, Vector3(0.0, h - 0.45, lz), Vector3(10.8, 0.9, 0.85), red)
		block(f, Vector3(0.0, 5.0, lz), Vector3(10.4, 0.5, 0.5), red)
	var back := -8.0
	var tip := 24.0
	for gx in [-1.7, 1.7]:
		block(f, Vector3(gx, h + 0.55, (back + tip) * 0.5), Vector3(0.65, 1.1, tip - back), white)
		beam(f, Vector3(gx, h + 1.1, -1.5), Vector3(gx, h + 9.0, 0.0), 0.55, red)
		beam(f, Vector3(gx, h + 1.1, 2.0), Vector3(gx, h + 9.0, 0.0), 0.45, red)
		beam(f, Vector3(gx, h + 9.0, 0.0), Vector3(gx, h + 1.1, tip - 1.0), 0.15, steel)
		beam(f, Vector3(gx, h + 9.0, 0.0), Vector3(gx, h + 1.1, back + 1.0), 0.15, steel)
	block(f, Vector3(0.0, h + 9.1, 0.0), Vector3(4.0, 0.4, 0.6), red)
	block(f, Vector3(0.0, h + 2.3, back + 3.0), Vector3(5.0, 2.4, 4.5), white)
	block(f, Vector3(0.0, h - 1.0, 6.5), Vector3(1.8, 1.6, 2.2), white)
	block(f, Vector3(0.0, h - 1.0, 7.6), Vector3(1.6, 0.9, 0.1), Color("24313a"))
	var trolley_z := 15.0
	block(f, Vector3(0.0, h + 1.3, trolley_z), Vector3(4.2, 0.9, 2.6), steel)
	var low := h - 10.0
	for cx in [-1.2, 1.2]:
		for cz in [-0.6, 0.6]:
			beam(f, Vector3(cx, h + 0.8, trolley_z + cz), Vector3(cx, low + 0.3, trolley_z + cz), 0.06, Color("222222"))
	block(f, Vector3(0.0, low, trolley_z), Vector3(6.2, 0.45, 2.5), Color("e2b31d"))

func build_ship(x: float, z: float, rot: float, length: float) -> void:
	# Containerfrachter aus Grundformen, liegt im Meer vor der Kaimauer (Wasserlinie = Meeresfläche).
	var wl := -2.3
	var f := Transform3D(Basis(Vector3.UP, rot), Vector3(x, wl, z))
	var width := 9.0
	var hull := Color("1f3550")
	# Rumpf, Bug als übereck gestellter Block (Spitze in +x), rote Wasserlinie, Deckfläche.
	block(f, Vector3(0.0, 1.0, 0.0), Vector3(length, 4.2, width), hull)
	shape_transform("box", f * Transform3D(Basis(Vector3.UP, PI * 0.25) * Basis.from_scale(Vector3(width * 0.707, 4.2, width * 0.707)), Vector3(length * 0.5, 1.0, 0.0)), hull)
	block(f, Vector3(0.0, 0.05, 0.0), Vector3(length + 0.1, 0.4, width + 0.1), Color("9c3326"))
	block(f, Vector3(0.0, 3.15, 0.0), Vector3(length - 0.4, 0.1, width - 0.6), Color("5c6468"))
	# Brücke und Schornstein am Heck (−x).
	var stern := -length * 0.5
	block(f, Vector3(stern + 3.0, 6.6, 0.0), Vector3(4.2, 7.0, width - 1.0), Color("ecebe6"))
	block(f, Vector3(stern + 3.0, 9.3, 0.0), Vector3(4.3, 0.7, width - 0.9), Color("26323a"))
	block(f, Vector3(stern + 3.0, 10.2, 0.0), Vector3(4.6, 0.3, width + 1.4), Color("ecebe6"))
	block(f, Vector3(stern + 0.8, 8.0, 0.0), Vector3(1.8, 4.0, 1.8), Color("b8392b"))
	block(f, Vector3(stern + 0.8, 10.2, 0.0), Vector3(1.9, 0.5, 1.9), Color("1b1b1b"))
	# Containerstapel: Buchten zu 6,1 m, drei Reihen quer, ein bis drei Lagen.
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(x) * 31.0 + absf(z) * 7.0) + 5
	var colors := ["8e3b2e", "3d5a6b", "4a6b3d", "c07a2c", "6b6f73", "2c4f8a", "a8a39a"]
	var bay := stern + 7.2
	while bay + 3.05 < length * 0.5 - 3.0:
		for row in [-2.55, 0.0, 2.55]:
			var layers := rng.randi_range(1, 3)
			for k in range(layers):
				block(f, Vector3(bay, 3.2 + 1.3 + k * 2.6, row), Vector3(6.0, 2.5, 2.4), Color(colors[rng.randi() % colors.size()]))
		bay += 6.3

const DIORAMA_PATH := "res://dioramas/%s.glb"
# Bausteine, die das Diorama selbst enthält (Laternen, Schilder usw. bleiben Laufzeit-Bauteile).
const DIORAMA_BAKED := ["building", "street_tree", "fountain"]
# Farbtöne der Diorama-Materialien (Fototexturen angleichen).
const DIORAMA_TINT := {"D_Asphalt": Color(0.42, 0.44, 0.46), "D_Randstein": Color(0.8, 0.8, 0.78),
	"D_Gehweg": Color(0.78, 0.76, 0.72), "D_Pflaster": Color(0.86, 0.84, 0.8), "D_Gras": Color(0.9, 0.95, 0.85),
	"D_Stein": Color(0.9, 0.88, 0.84), "D_Weite": Color(0.62, 0.62, 0.6), "D_Beton": Color(0.75, 0.75, 0.73),
	"D_Asphalt_Strasse": Color(0.9, 0.9, 0.88)}
# Der Fahrbahn-Shader nimmt diese Töne als Multiplikator der Fototextur.
var diorama := false
var diorama_blocked: Array = []   # Straßenflächen des Dioramas: [ox, oz, ux, uz, vx, vz, a0, a1, b0, b1] (Begleitdatei)
var diorama_lamps: Array = []     # zusätzliche Laternen für Kreuzungen/Nebenstraßen: {x, z, toward}

func diorama_blocks(prop: Dictionary) -> bool:
	# Liegt ein Laufzeit-Bauteil (Laterne, Tafel …) auf einer Diorama-Straße? Dann entfällt es.
	var x := float(prop.get("x", 0.0))
	var z := float(prop.get("z", 0.0))
	for r in diorama_blocked:
		var rx: float = x - float(r[0])
		var rz: float = z - float(r[1])
		var a: float = rx * float(r[2]) + rz * float(r[3])
		var b: float = rx * float(r[4]) + rz * float(r[5])
		if a >= float(r[6]) and a <= float(r[7]) and b >= float(r[8]) and b <= float(r[9]):
			return true
	return false

var kit_materials := {}        # Oberflächen der Bausatz-Häuser (Schlüssel wie in tools/kit_house.py)
var window_materials: Array = []   # davon: mit leuchtenden Fenstern (Stärke nach Tageszeit)
var blink_materials: Array = []    # rote Warnleuchten der Absperrschranken (blinken bei Dunkelheit)
var blink_level := 0.0

func kit_material(key: String) -> StandardMaterial3D:
	# Bausatz-Oberfläche aus den prozeduralen Texturen (Albedo, Normalkarte, Fensterlicht); Vertexfarbe = Putzton und Verschattung.
	if kit_materials.has(key):
		return kit_materials[key]
	var mat := StandardMaterial3D.new()
	mat.resource_name = "K_" + key
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.85
	mat.metallic_specular = 0.3
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if key == "lampe_rot":
		# Rote Warnleuchte der Absperrschranken: blinkt bei Dämmerung und Nacht (_process).
		mat.albedo_color = Color(0.85, 0.05, 0.03)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.1, 0.04)
		mat.emission_energy_multiplier = 0.0
		blink_materials.append(mat)
	elif key == "lampe":
		# Leuchtfläche unter dem Laternenkopf: nachts warmweiß, am Tag aus (gleiche Stärke wie das Fensterlicht).
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.86, 0.62)
		mat.emission_energy_multiplier = 0.0
		window_materials.append(mat)
	elif key != "farbe":
		mat.albedo_texture = load(KIT_PATH % key)
		if ResourceLoader.exists(KIT_PATH % (key + "_n")):
			mat.normal_enabled = true
			mat.normal_texture = load(KIT_PATH % (key + "_n"))
		if ResourceLoader.exists(KIT_PATH % (key + "_e")):
			mat.emission_enabled = true
			mat.emission = Color.WHITE
			mat.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY   # Standard "Addieren" würde die ganze Fläche leuchten lassen
			mat.emission_texture = load(KIT_PATH % (key + "_e"))
			mat.emission_energy_multiplier = 0.0
			window_materials.append(mat)
	kit_materials[key] = mat
	return mat

func set_windows(level: float) -> void:
	# Fensterlicht der Bausatz-Häuser: 0 am Tag, in der Dämmerung schwach, nachts voll.
	for mat in window_materials:
		mat.emission_energy_multiplier = level * 0.9   # unter der Glühschwelle (1,15), sonst verschmieren die Fenster zu weißen Wänden
	blink_level = level
	if level <= 0.0:
		for mat in blink_materials:
			mat.emission_energy_multiplier = 0.0

func build_diorama() -> void:
	var scene: Node3D = load(DIORAMA_PATH % track.id).instantiate()
	scene.name = "Diorama"
	var layout_path: String = (DIORAMA_PATH % track.id).replace(".glb", "_layout.json")
	diorama_blocked = []
	if FileAccess.file_exists(layout_path):
		var layout = JSON.parse_string(FileAccess.get_file_as_string(layout_path))
		if layout is Dictionary:
			diorama_blocked = layout.get("blocked", [])
			diorama_lamps = layout.get("lamps", [])
	add_child(scene)
	var ao_path: String = (DIORAMA_PATH % track.id).replace(".glb", "_ao.jpg")
	var ao: Texture2D = load(ao_path) if ResourceLoader.exists(ao_path) else null
	var road_shaders := {}
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var lit := true
		var node_name := String(mi.name)
		var kit_albedo: Texture2D = null
		# Regen-Spiegelung: nur Aufragendes nahe der Strecke gelangt in die Spiegelkamera (Ebene 1); alles
		# Weitere erscheint nur im Hauptbild und spart im Zusatzdurchgang den Großteil der Dreiecke.
		if node_name.begins_with("Prop_"):
			var at := mi.global_position
			mi.set_meta("keep_layer", true)
			mi.layers = LAYER_TALL if track.center_distance(Vector2(at.x, at.z)) < REFLECT_NEAR else LAYER_FLAT
		elif node_name.begins_with("Haus_"):
			mi.set_meta("keep_layer", true)
			mi.layers = LAYER_TALL if node_name.begins_with("Haus_nah") else LAYER_FLAT
		for i in range(mi.mesh.get_surface_count()):
			var mat := mi.mesh.surface_get_material(i) as StandardMaterial3D
			if mat == null:
				continue
			var mname := mat.resource_name
			if mname == "D_Asphalt" or mname == "D_Asphalt_Strasse":
				# Fahrbahn: Nässe, Pfützen, Spiegelung und Laternenlicht kommen aus dem Fahrbahn-Shader.
				if not road_shaders.has(mname):
					var tint: Color = DIORAMA_TINT.get(mname, Color.WHITE)
					var sm := premium_road(tint)
					sm.set_shader_parameter("albedo_tex", mat.albedo_texture)
					sm.set_shader_parameter("use_albedo", true)
					sm.set_shader_parameter("albedo_tint", tint)
					sm.set_shader_parameter("grain_strength", 0.12)
					sm.set_shader_parameter("wear", 1.0)
					if ao != null:
						sm.set_shader_parameter("ao_tex", ao)
						sm.set_shader_parameter("use_ao", true)
					road_shaders[mname] = sm
					if mname == "D_Asphalt":
						atmosphere.road_shader = sm
					else:
						atmosphere.road_shaders_extra.append(sm)
				mi.set_surface_override_material(i, road_shaders[mname])
				lit = false
				continue
			if mname == "D_Wasser":
				mi.set_surface_override_material(i, premium_water())
				continue
			if mname.begins_with("K_"):
				var kit := kit_material(mname.substr(2))
				mi.set_surface_override_material(i, kit)
				kit_albedo = kit.albedo_texture
				continue
			if mname.begins_with("D_"):
				if DIORAMA_TINT.has(mname):
					mat.albedo_color = DIORAMA_TINT[mname]
				# Gebackene Umgebungsverdeckung (zweite UV-Ebene); dunkelt auch direktes Licht ab (Kontaktschatten).
				if ao != null and mi.mesh.surface_get_format(i) & Mesh.ARRAY_FORMAT_TEX_UV2:
					mat.ao_enabled = true
					mat.ao_texture = ao
					mat.ao_on_uv2 = true
					mat.ao_light_affect = 0.85
					mat.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		if lit and node_name.begins_with("Haus_"):
			# Laternenlicht nur auf die Häuser nahe der Strecke (der Zusatzdurchgang kostet die Dreiecke ein zweites Mal).
			if node_name.begins_with("Haus_nah"):
				var glow := lit_overlay_color(Color(0.6, 0.6, 0.6))
				if glow != null:
					glow.set_shader_parameter("albedo_tex", kit_albedo)
					glow.set_shader_parameter("use_vertex_color", true)
					glow.set_shader_parameter("soft_clip", true)
					glow.set_shader_parameter("light_gain", 0.7)
					add_overlay(mi, glow)
		elif lit:
			add_overlay(mi, lit_overlay(mi.mesh))

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
			return place_card("kueste_palme", x, z, float(prop.get("h",3.5)) * 1.35) or place_ai("kueste_palme", x, z, spin, float(prop.get("h",3.5)) * 1.35)
		"parasol":
			return place_ai("kueste_sonnenschirm", x, z, spin, 2.5)
		"planter":
			return place_ai("kueste_pflanzkuebel", x, z, rot, 0.0, Vector2(w, d), true)
		"pine":
			return place_card("wald_kiefer", x, z, 5.6 * sc) or place_ai("wald_kiefer", x, z, spin, 5.6 * sc)
		"oak":
			return place_card("wald_eiche", x, z, 4.6 * sc) or place_ai("wald_eiche", x, z, spin, 4.6 * sc)
		"rock":
			return place_ai("wald_felsen" if track.theme == "forest" else "kueste_felsen", x, z, spin, 1.0 * sc)
		"log":
			return place_ai("wald_baumstamm", x, z, rot, 0.0, Vector2(3.2, 0.7), true)
		"street_tree":
			return place_card("stadt_baum", x, z, 4.6) or place_ai("stadt_baum", x, z, spin, 4.6)
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
			var model := str(prop.get("model", ("stadt_laterne_kit" if diorama else "stadt_laterne") if track.theme == "city" else "kueste_laterne"))
			var arm := ai_arm(model)
			var here := Vector2(x, z)
			var to_road := track.at(track.phase(here)) - here
			if prop.has("toward"):
				to_road = Vector2(float(prop.toward[0]), float(prop.toward[1])) - here   # Diorama-Straße: Blickpunkt vorgegeben
			var yaw := float(arm[0]) - atan2(to_road.y, to_road.x) if to_road.length() > 0.1 else spin
			if place_ai(model, x, z, yaw, 4.2):
				var reach := float(arm[1]) * 4.2
				var head_y := 3.9
				if LAMP_HEAD.has(model):
					var lamp_scale := 4.2 / maxf(ai_prop_mesh(model).get_aabb().size.y, 0.001)
					reach = LAMP_HEAD[model].x * lamp_scale
					head_y = LAMP_HEAD[model].y * lamp_scale
				var head := here + to_road.normalized() * reach
				light_pool(Vector3(head.x,head_y,head.y), 4.0, Color(1.0,0.82,0.5,0.5))
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
	if generic_prop(prop) or premium_prop(prop):
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
		var points := [track.at(a,track.edge_offset(a,inner)),track.at(a,track.edge_offset(a,outer)),track.at(b,track.edge_offset(b,outer)),track.at(b,track.edge_offset(b,inner))]
		if skip_crossing and track.other_branch_distance(points[0], a) < Circuit.HALF_WIDTH + 0.3:
			continue
		# 2,5D: Fahrbahn folgt dem Höhenprofil; in Lücken (Sprung über eine andere Straße) keine Fahrbahn.
		if track.in_gap((a + b) * 0.5):
			continue
		ya += track.base_height(a)
		yb += track.base_height(b)
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
			st.add_vertex(Vector3(p.x,0.27+s*0.006+track.surface_z(s),p.y))
	st.set_material(mat)
	return st.commit()

func _process(_dt: float) -> void:
	# Warnleuchten der Absperrschranken blinken (nur Darstellung), etwa einmal pro Sekunde.
	if blink_level > 0.0 and not blink_materials.is_empty():
		var on := fmod(Time.get_ticks_msec() * 0.001, 1.1) < 0.45
		for mat in blink_materials:
			mat.emission_energy_multiplier = blink_level * (1.0 if on else 0.06)
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
var low_detail := false   # Grafikqualität „Niedrig“: einfachere KI-Modelle, wo vorhanden (LOW_VARIANTS)
# Einfachere Fassung einzelner KI-Modelle für die Qualitätsstufe „Niedrig“ (ruhigere Form, weniger Dreiecke).
const LOW_VARIANTS := {"hafen_frachtschiff": "hafen_frachtschiff_einfach"}
var road_mesh: MeshInstance3D
const ROAD_SHADER := preload("res://assets/road.gdshader")
# Sichtbarkeitsebenen: 1 = aufragend (wird gespiegelt), 2 = flach am Boden (Spiegelkamera lässt es aus).
const LAYER_TALL := 1
const LAYER_FLAT := 2
const KIT_PATH := "res://assets/kit/%s.png"       # Bausatz-Texturen der Diorama-Häuser (tools/make_kit_textures.py)
const REFLECT_NEAR := 24.0   # Diorama: nur Bauten bis zu diesem Abstand zur Strecke spiegeln sich in der nassen Fahrbahn

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
const PAINT_SAT := {"muscle": 0.34, "roadster": 0.32}
# Dunkel gebackener Lack (Pickup): Lackschwelle und Bezugshelligkeit (sRGB) je Stil.
const PAINT_LIGHT := {"pickup": [0.13, 0.22], "roadster": [0.36, 0.86]}

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
				if PAINT_LIGHT.has(style):
					shaded.set_shader_parameter("paint_min_light", float(PAINT_LIGHT[style][0]))
					shaded.set_shader_parameter("paint_reference", float(PAINT_LIGHT[style][1]))
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

const TRACK_SHADER := preload("res://assets/tyre_track.gdshader")
var track_multi: MultiMesh
var track_material: ShaderMaterial
var track_head := 0
var track_seen := 0

func setup_track_ring() -> void:
	# Ringpuffer: ein neues Spurstück überschreibt genau eine Instanz, statt das ganze Netz neu zu bauen
	# (vorher alle 8 Takte bis zu ~25.000 Eckpunkte -> spürbares Ruckeln auf Schotter).
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	quad.orientation = PlaneMesh.FACE_Y
	quad.center_offset = Vector3(0.5, 0, 0)
	track_material = ShaderMaterial.new()
	track_material.shader = TRACK_SHADER
	track_material.set_shader_parameter("lifetime", TyreTracks.LIFETIME)
	quad.material = track_material
	track_multi = MultiMesh.new()
	track_multi.transform_format = MultiMesh.TRANSFORM_3D
	track_multi.use_colors = true
	track_multi.use_custom_data = true
	track_multi.mesh = quad
	track_multi.instance_count = TyreTracks.MAX_SEGMENTS
	track_multi.visible_instance_count = 0
	var node := MultiMeshInstance3D.new()
	node.multimesh = track_multi
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.layers = LAYER_FLAT
	node.extra_cull_margin = 200.0
	add_child(node)

func update_tracks(time: float) -> void:
	if track_multi == null:
		setup_track_ring()
	if tyre_tracks.total < track_seen:
		# Spuren gelöscht (Neustart): Ring leeren.
		track_seen = 0
		track_head = 0
		track_multi.visible_instance_count = 0
	var fresh := mini(tyre_tracks.total - track_seen, tyre_tracks.segments.size())
	for k in range(tyre_tracks.segments.size() - fresh, tyre_tracks.segments.size()):
		var segment: Dictionary = tyre_tracks.segments[k]
		var a: Vector2 = segment.a
		var b: Vector2 = segment.b
		if segment.kind=="soil":
			# Kleine Lücken wirken wie Reifenprofil statt wie ein gemalter Strich.
			b = a.lerp(b,0.80)
		var along := Vector3(b.x - a.x, float(segment.height_b) - float(segment.height_a), b.y - a.y)
		var side := Vector3(-(b.y - a.y), 0, b.x - a.x).normalized() * float(segment.width)
		track_multi.set_instance_transform(track_head, Transform3D(Basis(along, Vector3.UP * 0.001, side), Vector3(a.x, float(segment.height_a), a.y)))
		track_multi.set_instance_color(track_head, segment.color)
		track_multi.set_instance_custom_data(track_head, Color(float(segment.time), 0, 0, 0))
		track_head = (track_head + 1) % TyreTracks.MAX_SEGMENTS
		track_multi.visible_instance_count = maxi(track_multi.visible_instance_count, track_head if track_multi.visible_instance_count < TyreTracks.MAX_SEGMENTS and track_head > 0 else TyreTracks.MAX_SEGMENTS)
	track_seen = tyre_tracks.total
	track_material.set_shader_parameter("now", time)
	tyre_tracks.prune(time)
