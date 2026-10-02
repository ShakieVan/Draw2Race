class_name Atmosphere
extends Node3D

# Tageszeit, Wetter und Nebel samt Grafikqualität. Nur Darstellung; die Haftung bei Nässe/Schnee
# liefert grip_factor() an die Fahrphysik (Leitplanke 3/4: Darstellung ändert die Simulation nicht,
# die Wetterbedingung selbst ist aber Teil der Herausforderung).
const TIMES := {
	"day": {"sun":"fff0ce","sun_energy":0.95,"sun_angle":-52.0,"ambient":"c8e4ed","ambient_energy":0.35,"sky_mix":0.0,"sky":"327d88"},
	"dusk": {"sun":"ffb070","sun_energy":0.6,"sun_angle":-20.0,"ambient":"ffc9a0","ambient_energy":0.32,"sky_mix":0.75,"sky":"8a5a6a"},
	"night": {"sun":"8fa8ff","sun_energy":0.12,"sun_angle":-62.0,"ambient":"3a4a78","ambient_energy":0.28,"sky_mix":0.95,"sky":"0b1626"},
}
# Hemisphärisches Umgebungslicht (Premium): oben die Himmelsfarbe, an Wänden der Horizont, unten die Bodenrückstrahlung. So liegen
# Schatten kühler als besonnte Flächen, Wände dunkler als Dächer, Kronen oben heller (vorher eine einzige Umgebungsfarbe).
const SKY_LIGHT := {
	"day": {"top": "adbfdb", "horizon": "e0ded6", "ground_horizon": "b8a68c", "ground": "756654", "energy": 0.85},
	"dusk": {"top": "b79aa8", "horizon": "ffa070", "ground_horizon": "a6684f", "ground": "5a4038", "energy": 0.38},
	"night": {"top": "243060", "horizon": "34406e", "ground_horizon": "141726", "ground": "0f1219", "energy": 0.5},
}
# Bedeckter Himmel (Regen, Schnee): neutral grau, bei Schnee mit heller Rückstrahlung des Bodens.
const OVERCAST_LIGHT := {
	"rain": {"top": "a9b3bb", "horizon": "b4b9bc", "ground_horizon": "8f8f8c", "ground": "6a6a67"},
	"snow": {"top": "b9c2cb", "horizon": "c8cfd4", "ground_horizon": "b2b8bd", "ground": "989ea3"},
}
const WEATHER_GRIP := {"dry": 1.0, "rain": 0.85, "snow": 0.7}
const QUALITY_NAMES := ["Niedrig", "Mittel", "Hoch"]
const TIME_NAMES := {"day": "Tag", "dusk": "Dämmerung", "night": "Nacht"}
const WEATHER_NAMES := {"dry": "Trocken", "rain": "Regen", "snow": "Schnee"}
const FOG_NAMES := ["Kein Nebel", "Nebelschwaden", "Dichter Nebel"]

static func describe(c: Dictionary) -> String:
	var parts := [str(TIME_NAMES.get(c.get("time","day"),"Tag"))]
	if str(c.get("weather","dry")) != "dry":
		parts.append(str(WEATHER_NAMES.get(c.weather,"")))
	if int(c.get("fog",0)) > 0:
		parts.append(FOG_NAMES[clampi(int(c.fog),0,2)])
	return " · ".join(parts)

var world: Node3D
var env := Environment.new()
var sun := DirectionalLight3D.new()
var conditions := {"time": "day", "weather": "dry", "fog": 0}
var quality := 2
var base_sky := Color("327d88")
var rain := CPUParticles3D.new()
var rain_material: ShaderMaterial
var snow_material: ShaderMaterial
var fog_texture: Texture2D
var lamps: Array = []          # [Position, Reichweite, Farbe] aller Straßenlichter (für die Regen-Lichtkarte)
var snow := CPUParticles3D.new()
var fog_banks: Array[MeshInstance3D] = []
var puddles: Array[MeshInstance3D] = []
var night_lights: Array[Node3D] = []
var tinted: Dictionary = {}
var road_material: StandardMaterial3D
var sky_material := ProceduralSkyMaterial.new()
var road_shader: ShaderMaterial            # Premium-Fahrbahn (world.gd), sonst null
var road_shaders_extra: Array = []         # weitere Fahrbahn-Shader (Diorama: Nebenstraßen mit eigener Textur)

func all_road_shaders() -> Array:
	var list: Array = []
	if road_shader != null:
		list.append(road_shader)
	list.append_array(road_shaders_extra)
	return list
var terrain_shader: ShaderMaterial         # Premium-Gelände (world.gd), sonst null
var premium := false                      # Premium-Grafik aktiv (setzt world.gd)
var reflection_view: SubViewport
var reflection_cam: Camera3D
var reflecting := false
var reflect_wanted := false   # Wetter und Qualität verlangen Spiegelung
var reflect_far := false      # Kamera zu weit weg oder zu steil: Spiegelung ausgesetzt
const REFLECT_PLANE := 0.19                 # Höhe der Fahrbahnebene (Spiegelachse)
var road_color := Color("394950")
var clock := 0.0

func setup(owner_world: Node3D, sky: Color, bounds: Rect2) -> void:
	world = owner_world
	base_sky = sky
	var holder := WorldEnvironment.new()
	env.background_mode = Environment.BG_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	holder.environment = env
	add_child(holder)
	sun.shadow_enabled = true
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	sun.directional_shadow_max_distance = 150
	# Halbschatten wie bei echter Sonne (Winkelgröße), dazu leicht weichgezeichnete Schattenkanten.
	sun.light_angular_distance = 1.2
	sun.shadow_blur = 1.5
	add_child(sun)
	var c := bounds.get_center()
	var half := bounds.size*0.5 + Vector2(14,14)
	for p in [rain, snow]:
		p.emitting = false
		p.local_coords = false
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.emission_box_extents = Vector3(half.x, 1.0, half.y)
		p.position = Vector3(c.x, 22.0, c.y)
		# Niederschlag nicht spiegeln (Ebene 2): gespiegelte Tropfen „fallen“ in der Pfütze nach oben und irritieren.
		p.layers = 2
		p.set_meta("keep_layer", true)
		add_child(p)
	# Regen: Tropfen starten 9 m über dem Boden und enden genau am Boden (dort setzen die Aufschlagringe
	# im Fahrbahn-Shader an); leicht schräg durch Wind, unterschiedlich schnell.
	rain.position = Vector3(c.x, 9.0, c.y)
	var drop := BoxMesh.new()
	drop.size = Vector3(0.03, 0.75, 0.03)
	# Tropfen reflektieren nur ankommendes Licht (Sonne, Laternen, Scheinwerfer, Rücklichter), siehe rain.gdshader.
	rain_material = ShaderMaterial.new()
	rain_material.shader = preload("res://assets/rain.gdshader")
	rain_material.set_shader_parameter("spawn_height", 9.0)
	drop.material = rain_material
	rain.mesh = drop
	rain.particle_flag_align_y = true
	rain.direction = Vector3(0.22, -1, 0.1)
	rain.spread = 2.0
	rain.gravity = Vector3.ZERO
	rain.initial_velocity_min = 26.0
	rain.initial_velocity_max = 30.0
	rain.lifetime = 0.33
	rain.scale_amount_min = 0.7
	rain.scale_amount_max = 1.2
	var flake := SphereMesh.new()
	flake.radius = 0.08
	flake.height = 0.16
	flake.radial_segments = 6
	flake.rings = 3
	# Flocken haben keine Eigenfarbe: Sie sind so hell wie das Licht an ihrer Stelle (snow.gdshader).
	snow_material = ShaderMaterial.new()
	snow_material.shader = preload("res://assets/snow.gdshader")
	flake.material = snow_material
	snow.mesh = flake
	snow.direction = Vector3(0.2, -1, 0.1)
	snow.spread = 25.0
	snow.gravity = Vector3.ZERO
	snow.initial_velocity_min = 2.5
	snow.initial_velocity_max = 4.0
	snow.lifetime = 9.0           # 22 m Starthöhe bei mindestens 2,5 m/s: die Flocken erreichen den Boden
	# Nebelbänke: flache, weich auslaufende Schwaden knapp über dem Boden, die langsam treiben.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in range(14):
		var bank := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(rng.randf_range(14, 24), rng.randf_range(7, 12))
		quad.orientation = PlaneMesh.FACE_Y
		bank.mesh = quad
		bank.material_override = fog_material()
		bank.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bank.position = Vector3(c.x + rng.randf_range(-half.x, half.x), rng.randf_range(0.8, 2.4), c.y + rng.randf_range(-half.y, half.y))
		bank.set_meta("drift", Vector2(rng.randf_range(0.3, 0.9), rng.randf_range(-0.2, 0.2)))
		bank.set_meta("area", Rect2(c - half, half*2))
		bank.visible = false
		add_child(bank)
		fog_banks.append(bank)

func fog_material() -> ShaderMaterial:
	# Nebelbank ohne Eigenleuchten (fog_bank.gdshader): Farbe x Umgebungs-/Sonnenlicht + Laternenlicht.
	if fog_texture == null:
		fog_texture = soft_texture()
	var m := ShaderMaterial.new()
	m.shader = preload("res://assets/fog_bank.gdshader")
	m.set_shader_parameter("soft_tex", fog_texture)
	return m

func apply_sky_light(time_name: String, weather: String) -> void:
	# Der Himmel wird nicht gezeichnet (Hintergrund bleibt eine Farbe); er liefert nur das Umgebungs- und Spiegellicht.
	var sl: Dictionary = SKY_LIGHT.get(time_name, SKY_LIGHT.day)
	var colors: Dictionary = sl
	var energy := float(sl.energy)
	if weather != "dry" and time_name == "day":
		colors = OVERCAST_LIGHT[weather]
		energy *= 0.92 if weather == "rain" else 0.72
	elif weather == "snow":
		energy += 0.1
	sky_material.sky_top_color = Color(colors.top)
	sky_material.sky_horizon_color = Color(colors.horizon)
	sky_material.ground_horizon_color = Color(colors.ground_horizon)
	sky_material.ground_bottom_color = Color(colors.ground)
	sky_material.sky_curve = 0.25
	sky_material.ground_curve = 0.08
	if env.sky == null:
		var sky_res := Sky.new()
		sky_res.sky_material = sky_material
		env.sky = sky_res
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = energy

func light_rel(t: Dictionary, sun_energy: float) -> Color:
	# Streulicht aus Umgebung und Sonne/Mond relativ zu einem trockenen Tag: 1 am Tag, nachts klein. Nebel und Schnee haben
	# kein Eigenlicht; sie sind nur so hell wie dieses Licht (die Laternen kommen im Shader aus der Lichtkarte dazu).
	var d: Dictionary = TIMES.day
	var day := Color(d.ambient) * float(d.ambient_energy) * 1.6 + Color(d.sun) * float(d.sun_energy) * 0.55
	var now := Color(t.ambient) * float(t.ambient_energy) * 1.6 + Color(t.sun) * sun_energy * 0.55
	return Color(clampf(now.r / day.r, 0.03, 1.0), clampf(now.g / day.g, 0.03, 1.0), clampf(now.b / day.b, 0.03, 1.0))

func unshaded(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	return m

static func soft_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	return t

static func soft_material(color: Color, additive := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = soft_texture()
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m

func register_tint(material: StandardMaterial3D) -> void:
	# Bodenmaterialien, die bei Schnee weiß überzogen werden.
	tinted[material] = material.albedo_color

func grip_factor() -> float:
	return float(WEATHER_GRIP.get(conditions.weather, 1.0))

func is_dark() -> bool:
	return conditions.time in ["dusk", "night"]

func apply(new_conditions: Dictionary, new_quality: int) -> void:
	conditions = new_conditions.duplicate()
	quality = clampi(new_quality, 0, 2)
	var t: Dictionary = TIMES.get(conditions.time, TIMES.day)
	var weather := str(conditions.weather)
	var sky := base_sky.lerp(Color(t.sky), float(t.sky_mix))
	var sun_energy := float(t.sun_energy)
	if weather != "dry":
		sky = sky.lerp(Color("6f7a80") if weather == "rain" else Color("c9d3d8"), 0.45 if conditions.time == "day" else 0.2)
		sun_energy *= 0.55
	env.background_color = sky
	if premium:
		apply_sky_light(str(conditions.time), weather)
	else:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.reflected_light_source = Environment.REFLECTION_SOURCE_BG
		env.ambient_light_color = Color(t.ambient)
		env.ambient_light_energy = float(t.ambient_energy) + (0.12 if weather == "snow" else 0.0)
	sun.light_color = Color(t.sun)
	sun.light_energy = sun_energy
	sun.rotation_degrees = Vector3(float(t.sun_angle), -32, 0)
	# Premium: dezentes Leuchten sehr heller Lichter (Scheinwerfer, Rückleuchten, Funken), nicht des Lacks.
	env.glow_enabled = premium and quality >= 1
	env.glow_intensity = 0.55
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.15
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	# Qualität: Schatten, Kantenglättung, Partikelmengen.
	sun.shadow_enabled = quality >= 1
	RenderingServer.directional_shadow_atlas_set_size([1024, 2048, 4096][quality], true)
	get_viewport().msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][quality]
	var density: float = [0.3, 0.65, 1.0][quality]
	rain.amount = int(2600 * density)
	snow.amount = int(1500 * density)
	rain.emitting = weather == "rain"
	snow.emitting = weather == "snow"
	rain.visible = rain.emitting
	snow.visible = snow.emitting
	# Nebel: partiell = treibende Bänke, dicht = zusätzlich Dunst über allem.
	var fog := int(conditions.fog)
	var banks: int = [0, 7, 14][quality] if fog >= 1 else 0
	if fog >= 1 and quality == 0:
		banks = 3
	var lit := light_rel(t, sun_energy)
	var lit_v := Vector3(lit.r, lit.g, lit.b)
	# Nebel streut alle Wellenlängen: das warme Abendlicht färbt ihn nur zu 60 %.
	var luma := lit.r * 0.3 + lit.g * 0.59 + lit.b * 0.11
	var fog_lit := Color(lerpf(luma, lit.r, 0.6), lerpf(luma, lit.g, 0.6), lerpf(luma, lit.b, 0.6))
	var fog_lit_v := Vector3(fog_lit.r, fog_lit.g, fog_lit.b)
	for i in range(fog_banks.size()):
		fog_banks[i].visible = i < banks
		var m := fog_banks[i].material_override as ShaderMaterial
		m.set_shader_parameter("fog_color", Color(0.9, 0.93, 0.95, (0.55 if fog == 1 else 0.75) * (0.85 if is_dark() else 1.0)))
		m.set_shader_parameter("ambient_light", fog_lit_v)
	snow_material.set_shader_parameter("day_light", lit_v)
	snow_material.set_shader_parameter("cars_lit", 1.0 if is_dark() else 0.0)
	env.fog_enabled = fog >= 1
	# Der Tiefennebel hat kein Eigenlicht: nachts dunkel, tagsüber wie bisher.
	env.fog_light_color = sky.lerp(Color.WHITE, 0.4) * fog_lit
	env.fog_density = 0.004 if fog == 1 else 0.012
	# Oberflächen: nass glänzend und dunkler, Schnee hellt Boden und Fahrbahn auf.
	if road_material != null:
		road_material.albedo_color = road_color.darkened(0.18) if weather == "rain" else (road_color.lerp(Color("e4e9eb"), 0.55) if weather == "snow" else road_color)
		road_material.roughness = 0.12 if weather == "rain" else 0.86
		road_material.metallic_specular = 0.9 if weather == "rain" else 0.5
	for material in tinted:
		var original: Color = tinted[material]
		material.albedo_color = original.lerp(Color("eef3f5"), 0.78) if weather == "snow" else original
	for puddle in puddles:
		puddle.visible = weather == "rain" and road_shader == null
	if road_shader != null:
		# Premium-Fahrbahn: Nässe, Pfützen und echte Spiegelung (ab Qualität „Mittel“) statt Farbwechsel.
		var wet := weather == "rain"
		for rs in all_road_shaders():
			rs.set_shader_parameter("wetness", 1.0 if wet else 0.0)
			rs.set_shader_parameter("puddles", 1.0 if wet else 0.0)
			rs.set_shader_parameter("rain", 1.0 if wet else 0.0)
			rs.set_shader_parameter("snow", 1.0 if weather == "snow" else 0.0)
		set_reflection(wet and quality >= 1)
	if rain_material != null:
		var tod := str(conditions.time)
		var sky_light := Color(t.ambient) * float(t.ambient_energy) + Color(t.sun) * sun_energy * 0.35
		rain_material.set_shader_parameter("day_light", Vector3(sky_light.r, sky_light.g, sky_light.b) * (0.9 if tod == "day" else 0.35))
		rain_material.set_shader_parameter("cars_lit", 1.0 if is_dark() else 0.0)
	RenderingServer.global_shader_parameter_set("lamp_strength", (1.0 if conditions.time == "night" else 0.6) if is_dark() else 0.0)
	RenderingServer.global_shader_parameter_set("street_wet", 1.0 if weather == "rain" else 0.0)
	if terrain_shader != null:
		terrain_shader.set_shader_parameter("snow", 1.0 if weather == "snow" else 0.0)
		terrain_shader.set_shader_parameter("wet", 1.0 if weather == "rain" else 0.0)
	for node in night_lights:
		node.visible = is_dark()
	if world != null and world.has_method("set_overlays"):
		world.set_overlays(is_dark())
	if world != null and world.has_method("set_snow"):
		world.set_snow(weather == "snow")
	if world != null and world.has_method("set_windows"):
		world.set_windows(1.0 if conditions.time == "night" else (0.55 if conditions.time == "dusk" else 0.0))

var occluders: Array = []      # [Mitte Vector2, halbe Größe Vector2, Drehung] von Gebäuden (werfen Laternenschatten)
var occluder_polys: Array = []  # [Ecken PackedVector2Array, Höhe] beliebiger Lichtblocker (Begleitdatei "occluder_polys", z. B. gekrümmte Tribünen)
const LAMP_REACH := 1.8        # Lichtradius am Boden = Reichweite des Eintrags in lamps x LAMP_REACH
const SOLID_HIGH := 1.0e9      # Höhe der Gebäude (Rechtecke): blockieren jeden Strahl
var keep_map := false          # nur für Tests: die gebackene Lichtkarte (RGB-Float) samt Fläche behalten
var light_map: Image
var light_area := Rect2()

static func inside_poly(p: Vector2, poly: PackedVector2Array) -> bool:
	# Punkt im Polygon (gerade-ungerade-Regel, unabhängig vom Umlaufsinn).
	var inside := false
	var n := poly.size()
	var j := n - 1
	for i in range(n):
		var a := poly[i]
		var b := poly[j]
		if (a.y > p.y) != (b.y > p.y) and p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x:
			inside = not inside
		j = i
	return inside

func bake_rain_lights(area: Rect2, cells := 256) -> void:
	# Vorberechnetes Laternenlicht (Draufsicht): Farbe x Stärke je Zelle, Gebäude und Lichtblocker werfen Schatten; danach
	# weichgezeichnet (unscharfe Schattenkanten). Wird als globaler Shaderwert von Fahrbahn, Gelände, Kulisse,
	# Autos, Nebel und Niederschlag gelesen. Hindernisse stehen als Höhenmaske (eine Zahl je Zelle) bereit: Licht gelangt
	# weder hinein noch hindurch; die Sichtprüfung je Zelle ist damit ein Feldzugriff je Schritt. Gebäude zählen als unendlich
	# hoch, Polygone (occluder_polys) blockieren nur Strahlen, die auf ihrer Höhe noch unter der Oberkante liegen.
	var data := PackedFloat32Array()
	data.resize(cells * cells * 3)
	var cell := area.size / cells
	var solid := PackedFloat32Array()
	solid.resize(cells * cells)
	for o in occluders:
		var oc: Vector2 = o[0]
		var oh: Vector2 = o[1]
		var rot := float(o[2])
		var rad := oh.length()
		var bx0 := maxi(0, int((oc.x - rad - area.position.x) / cell.x))
		var bx1 := mini(cells - 1, int((oc.x + rad - area.position.x) / cell.x))
		var by0 := maxi(0, int((oc.y - rad - area.position.y) / cell.y))
		var by1 := mini(cells - 1, int((oc.y + rad - area.position.y) / cell.y))
		for iy in range(by0, by1 + 1):
			for ix in range(bx0, bx1 + 1):
				var local := (area.position + Vector2((ix + 0.5) * cell.x, (iy + 0.5) * cell.y) - oc).rotated(-rot)
				if absf(local.x) < oh.x and absf(local.y) < oh.y:
					solid[iy * cells + ix] = SOLID_HIGH
	for pol in occluder_polys:
		var pts: PackedVector2Array = pol[0]
		var ph := float(pol[1])
		if pts.size() < 3:
			continue
		var lo := pts[0]
		var hi := pts[0]
		for q in pts:
			lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
			hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
		var px0 := maxi(0, int((lo.x - area.position.x) / cell.x) - 1)
		var px1 := mini(cells - 1, int((hi.x - area.position.x) / cell.x) + 1)
		var py0 := maxi(0, int((lo.y - area.position.y) / cell.y) - 1)
		var py1 := mini(cells - 1, int((hi.y - area.position.y) / cell.y) + 1)
		for iy in range(py0, py1 + 1):
			for ix in range(px0, px1 + 1):
				var c0 := area.position + Vector2((ix + 0.5) * cell.x, (iy + 0.5) * cell.y)
				# Mitte und vier Punkte nahe den Zellecken: auch Streifen, die schmaler als eine Zelle sind, schließen lückenlos
				var hit := inside_poly(c0, pts)
				if not hit:
					for off: Vector2 in [Vector2(-0.3, -0.3), Vector2(0.3, -0.3), Vector2(0.3, 0.3), Vector2(-0.3, 0.3)]:
						if inside_poly(c0 + off * cell, pts):
							hit = true
							break
				if hit:
					var k0 := iy * cells + ix
					solid[k0] = maxf(solid[k0], ph)
	var step_len := minf(cell.x, cell.y)
	for lamp in lamps:
		var p: Vector3 = lamp[0]
		# Lichtradius am Boden: höher hängende Köpfe leuchten weiter als die frühere Lichtscheibe.
		var reach: float = lamp[1] * LAMP_REACH
		var col: Color = lamp[2]
		var head := Vector2(p.x, p.z)
		var x0 := maxi(0, int((p.x - reach - area.position.x) / cell.x))
		var x1 := mini(cells - 1, int((p.x + reach - area.position.x) / cell.x))
		var y0 := maxi(0, int((p.z - reach - area.position.y) / cell.y))
		var y1 := mini(cells - 1, int((p.z + reach - area.position.y) / cell.y))
		for iy in range(y0, y1 + 1):
			for ix in range(x0, x1 + 1):
				if solid[iy * cells + ix] > 0.0:
					continue
				var q := area.position + Vector2((ix + 0.5) * cell.x, (iy + 0.5) * cell.y)
				var d := q.distance_to(head)
				if d >= reach:
					continue
				# Sichtlinie Laterne -> Zelle durch die Gebäudemaske (die ersten 1,2 m am Mast zählen nicht).
				var steps := int(d / step_len)
				var hidden := false
				for k in range(1, steps):
					var t := float(k) / steps
					if d * t < 1.2:
						continue
					var sx := int((lerpf(head.x, q.x, t) - area.position.x) / cell.x)
					var sy := int((lerpf(head.y, q.y, t) - area.position.y) / cell.y)
					# Der Strahl vom Lichtkopf (Höhe p.y) zum Boden hat auf halbem Weg nur noch die halbe Höhe.
					if sx >= 0 and sy >= 0 and sx < cells and sy < cells and solid[sy * cells + sx] > p.y * (1.0 - t):
						hidden = true
						break
				if hidden:
					continue
				var f := 1.0 - smoothstep(0.0, reach, d)
				f = f * f * 1.6
				var k2 := (iy * cells + ix) * 3
				data[k2] += col.r * f
				data[k2 + 1] += col.g * f
				data[k2 + 2] += col.b * f
	var img := Image.create_from_data(cells, cells, false, Image.FORMAT_RGBF, data.to_byte_array())
	# Weiche Schatten: verkleinern und wieder vergrößern (bilinear) wirkt wie eine Unschärfe von ~1 m.
	img.resize(cells / 3, cells / 3, Image.INTERPOLATE_BILINEAR)
	img.resize(cells, cells, Image.INTERPOLATE_CUBIC)
	if keep_map:
		light_map = img
		light_area = area
	var tex := ImageTexture.create_from_image(img)
	RenderingServer.global_shader_parameter_set("lamp_light", tex)
	RenderingServer.global_shader_parameter_set("lamp_origin", area.position)
	RenderingServer.global_shader_parameter_set("lamp_size", area.size)

func update_rain_cars(cars: Array) -> void:
	# cars: [Vector3 Position, Fahrtrichtung] je Auto; höchstens 8.
	if rain_material == null or not (rain.emitting or snow.emitting):
		return
	var data := PackedVector4Array()
	for c in cars.slice(0, 8):
		var p: Vector3 = c[0]
		data.append(Vector4(p.x, p.y, p.z, float(c[1])))
	while data.size() < 8:
		data.append(Vector4.ZERO)
	for m in [rain_material, snow_material]:
		m.set_shader_parameter("car_pos", data)
		m.set_shader_parameter("car_count", mini(cars.size(), 8))

func follow_view(focus: Vector3, zoom: float, aspect: float, pitch: float) -> void:
	# Regen und Schnee folgen dem Bild: Die Emissionsbox deckt stets den sichtbaren Bereich samt Rand ab (Perspektive:
	# die Tiefe des Bildes wächst mit der Neigung), so gibt es beim Zoomen und Fahren keine sichtbare Grenze.
	var hx := zoom * aspect * 0.5 * 1.45 + 8.0
	var hz := zoom / maxf(0.45, sin(pitch)) * 0.5 * 1.6 + 10.0
	for p in [rain, snow]:
		if p.emitting:
			p.emission_box_extents = Vector3(hx, 1.0, hz)
			p.position.x = focus.x
			p.position.z = focus.z

func set_area(area: Rect2) -> void:
	# Nebelbänke treiben über die ganze Fläche (Diorama: Stadt), nicht nur über die Rennstrecke.
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 5
	for bank in fog_banks:
		bank.set_meta("area", area)
		bank.position = Vector3(rng2.randf_range(area.position.x, area.end.x), rng2.randf_range(0.8, 2.4), rng2.randf_range(area.position.y, area.end.y))

func fit_shadow(distance: float) -> void:
	# Die schräge Draufsicht hat nur einen schmalen Tiefenbereich: eine einzige orthogonale Schattenkarte, deren Reichweite
	# der Kamera folgt, spart die vier Teilbereiche (jeder zeichnet alle Schattenwerfer neu) und gewinnt Auflösung.
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = clampf(distance * 1.3 + 22.0, 40.0, 150.0)

func set_reflection(on: bool) -> void:
	reflect_wanted = on
	apply_reflection()

func limit_reflection(zoom_ratio: float, pitch: float) -> void:
	# Die Spiegelbilder sieht man nur bei nahem, geneigtem Blick; in der senkrechten Übersicht kostet der Zusatzdurchgang
	# (ganze Stadt ein zweites Mal) viel und bringt nichts. Mit Hysterese, damit es nicht flackert.
	var far := reflect_far
	if zoom_ratio > 0.66 or pitch > deg_to_rad(82.0):
		far = true
	elif zoom_ratio < 0.56 and pitch < deg_to_rad(78.0):
		far = false
	if far != reflect_far:
		reflect_far = far
		apply_reflection()

func apply_reflection() -> void:
	var on := reflect_wanted and not reflect_far
	# Spiegelkamera: rendert nur Aufragendes (Ebene 1) von unterhalb der Fahrbahnebene, halbe Auflösung.
	if on and reflection_view == null:
		reflection_view = SubViewport.new()
		reflection_view.msaa_3d = Viewport.MSAA_DISABLED
		add_child(reflection_view)
		reflection_view.world_3d = get_viewport().find_world_3d()
		reflection_cam = Camera3D.new()
		reflection_cam.cull_mask = 1
		reflection_view.add_child(reflection_cam)
		reflection_cam.current = true
		for rs in all_road_shaders():
			rs.set_shader_parameter("reflection_tex", reflection_view.get_texture())
	reflecting = on
	if reflection_view != null:
		reflection_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	for rs in all_road_shaders():
		rs.set_shader_parameter("use_reflection", on)

func update_reflection() -> void:
	var main := get_viewport().get_camera_3d()
	if main == null or main == reflection_cam:
		return
	var size := Vector2i(get_viewport().get_visible_rect().size * 0.5)
	if reflection_view.size != size:
		reflection_view.size = size
	reflection_cam.projection = main.projection
	reflection_cam.size = main.size
	reflection_cam.fov = main.fov
	reflection_cam.near = main.near
	reflection_cam.far = main.far
	reflection_cam.keep_aspect = main.keep_aspect
	var t := main.global_transform
	var o := t.origin
	var forward := -t.basis.z
	var up := t.basis.y
	var mirrored := Vector3(o.x, 2.0*REFLECT_PLANE - o.y, o.z)
	reflection_cam.look_at_from_position(mirrored, mirrored + Vector3(forward.x, -forward.y, forward.z), Vector3(up.x, -up.y, up.z))

func _process(dt: float) -> void:
	clock += dt
	if reflecting:
		update_reflection()
	for bank in fog_banks:
		if not bank.visible:
			continue
		var drift: Vector2 = bank.get_meta("drift")
		var area: Rect2 = bank.get_meta("area")
		bank.position.x += drift.x * dt
		bank.position.z += drift.y * dt
		if bank.position.x > area.end.x + 10.0:
			bank.position.x = area.position.x - 10.0
