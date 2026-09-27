class_name Atmosphere
extends Node3D

# Tageszeit, Wetter und Nebel samt Grafikqualität. Nur Darstellung; die Haftung bei Nässe/Schnee
# liefert grip_factor() an die Fahrphysik (Leitplanke 3/4: Darstellung ändert die Simulation nicht,
# die Wetterbedingung selbst ist aber Teil der Herausforderung).
const TIMES := {
	"day": {"sun":"fff0ce","sun_energy":0.8,"sun_angle":-52.0,"ambient":"c8e4ed","ambient_energy":0.35,"sky_mix":0.0,"sky":"327d88"},
	"dusk": {"sun":"ffb070","sun_energy":0.6,"sun_angle":-20.0,"ambient":"ffc9a0","ambient_energy":0.32,"sky_mix":0.75,"sky":"8a5a6a"},
	"night": {"sun":"8fa8ff","sun_energy":0.12,"sun_angle":-62.0,"ambient":"3a4a78","ambient_energy":0.28,"sky_mix":0.95,"sky":"0b1626"},
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
var snow := CPUParticles3D.new()
var fog_banks: Array[MeshInstance3D] = []
var puddles: Array[MeshInstance3D] = []
var night_lights: Array[Node3D] = []
var tinted: Dictionary = {}
var road_material: StandardMaterial3D
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
	sun.directional_shadow_max_distance = 150
	add_child(sun)
	var c := bounds.get_center()
	var half := bounds.size*0.5 + Vector2(14,14)
	for p in [rain, snow]:
		p.emitting = false
		p.local_coords = false
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.emission_box_extents = Vector3(half.x, 1.0, half.y)
		p.position = Vector3(c.x, 22.0, c.y)
		add_child(p)
	var drop := BoxMesh.new()
	drop.size = Vector3(0.04, 0.9, 0.04)
	drop.material = unshaded(Color(0.78, 0.86, 0.95, 0.55))
	rain.mesh = drop
	rain.direction = Vector3(0.12, -1, 0.05)
	rain.spread = 3.0
	rain.gravity = Vector3.ZERO
	rain.initial_velocity_min = 34.0
	rain.initial_velocity_max = 40.0
	rain.lifetime = 0.7
	var flake := SphereMesh.new()
	flake.radius = 0.08
	flake.height = 0.16
	flake.radial_segments = 6
	flake.rings = 3
	flake.material = unshaded(Color(1, 1, 1, 0.9))
	snow.mesh = flake
	snow.direction = Vector3(0.2, -1, 0.1)
	snow.spread = 25.0
	snow.gravity = Vector3.ZERO
	snow.initial_velocity_min = 2.5
	snow.initial_velocity_max = 4.0
	snow.lifetime = 7.0
	# Nebelbänke: flache, weich auslaufende Schwaden knapp über dem Boden, die langsam treiben.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in range(14):
		var bank := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(rng.randf_range(14, 24), rng.randf_range(7, 12))
		quad.orientation = PlaneMesh.FACE_Y
		bank.mesh = quad
		bank.material_override = soft_material(Color(0.9, 0.93, 0.95, 0.5))
		bank.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bank.position = Vector3(c.x + rng.randf_range(-half.x, half.x), rng.randf_range(0.8, 2.4), c.y + rng.randf_range(-half.y, half.y))
		bank.set_meta("drift", Vector2(rng.randf_range(0.3, 0.9), rng.randf_range(-0.2, 0.2)))
		bank.set_meta("area", Rect2(c - half, half*2))
		bank.visible = false
		add_child(bank)
		fog_banks.append(bank)

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
	env.ambient_light_color = Color(t.ambient)
	env.ambient_light_energy = float(t.ambient_energy) + (0.12 if weather == "snow" else 0.0)
	sun.light_color = Color(t.sun)
	sun.light_energy = sun_energy
	sun.rotation_degrees = Vector3(float(t.sun_angle), -32, 0)
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
	for i in range(fog_banks.size()):
		fog_banks[i].visible = i < banks
		var m: StandardMaterial3D = fog_banks[i].material_override
		m.albedo_color = (Color(0.9, 0.93, 0.95) if not is_dark() else Color(0.55, 0.6, 0.7)) * Color(1, 1, 1, 0.55 if fog == 1 else 0.75)
	env.fog_enabled = fog >= 1
	env.fog_light_color = sky.lerp(Color.WHITE, 0.4)
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
		puddle.visible = weather == "rain"
	for node in night_lights:
		node.visible = is_dark()

func _process(dt: float) -> void:
	clock += dt
	for bank in fog_banks:
		if not bank.visible:
			continue
		var drift: Vector2 = bank.get_meta("drift")
		var area: Rect2 = bank.get_meta("area")
		bank.position.x += drift.x * dt
		bank.position.z += drift.y * dt
		if bank.position.x > area.end.x + 10.0:
			bank.position.x = area.position.x - 10.0
