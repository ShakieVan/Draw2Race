shader_type spatial;
render_mode cull_disabled;
// Fahrbahn (Premium-Grafik): Körnung, Nässe, Pfützen und echte Spiegelungen.
// Die Spiegelung rendert eine an der Fahrbahnebene gespiegelte Kamera (atmosphere.gd) in reflection_tex.
// Pfützen liegen an festen Weltkoordinaten (Rauschtextur), Regen lässt die Spiegelung leicht wabern.

uniform vec4 base_color : source_color = vec4(0.22, 0.29, 0.31, 1.0);
uniform sampler2D grain_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D puddle_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform sampler2D reflection_tex : source_color, filter_linear, repeat_disable;
uniform bool use_reflection = false;
uniform bool flip_x = true;
uniform float grain_strength = 0.35;
uniform float wetness = 0.0;     // 0 trocken, 1 nasser Film
uniform float puddles = 0.0;     // 0 keine, 1 Pfützen sichtbar
uniform float snow = 0.0;        // 0 kein Schnee, 1 Schneeschleier
uniform float rain = 0.0;        // Regenstärke für die Wellen in der Spiegelung
uniform float puddle_cover = 0.56; // Schwelle der Pfützen-Rauschtextur (kleiner = mehr Pfützen)
// Diorama: Fototextur (Weltkoordinaten, Kachelgröße albedo_scale) und gebackene Umgebungsverdeckung (zweite UV-Ebene).
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool use_albedo = false;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform float albedo_scale = 6.0;
uniform sampler2D ao_tex : hint_default_white, filter_linear, repeat_disable;
uniform bool use_ao = false;

#include "res://assets/lamp_light.gdshaderinc"

varying vec2 world_xz;

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	float g1 = texture(grain_tex, world_xz * 0.45).r;
	float g2 = texture(grain_tex, world_xz * 2.1 + vec2(0.37, 0.71)).r;
	vec3 base = base_color.rgb;
	if (use_albedo) {
		base = texture(albedo_tex, world_xz / albedo_scale).rgb * albedo_tint.rgb;
	}
	vec3 col = base * (1.0 - grain_strength * 0.5 + grain_strength * (0.6 * g1 + 0.4 * g2));
	float puddle = smoothstep(puddle_cover, puddle_cover + 0.08, texture(puddle_tex, world_xz * 0.035).r) * puddles;
	float wet = clamp(max(wetness * 0.65, puddle), 0.0, 1.0);
	col *= mix(1.0, 0.5, wet);
	// Aufschlagringe der Regentropfen: je 0,45-m-Zelle ein Tropfen mit eigener Phase und Lage, zwei Lagen.
	float rings = 0.0;
	if (rain > 0.01) {
		for (int layer = 0; layer < 2; layer++) {
			vec2 cell_uv = world_xz / 0.45 + float(layer) * vec2(0.37, 0.61);
			vec2 cell = floor(cell_uv);
			vec2 local = fract(cell_uv) - 0.5;
			float h1 = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
			float h2 = fract(sin(dot(cell, vec2(39.3467, 11.135))) * 24634.6345);
			vec2 center = (vec2(h1, h2) - 0.5) * 0.5;
			float age = fract(TIME * (1.1 + h1 * 0.6) + h2);
			float radius = age * 0.42;
			float dist = length(local - center);
			rings += (1.0 - smoothstep(0.0, 0.035, abs(dist - radius))) * (1.0 - age) * (1.0 - age);
		}
		rings *= rain * mix(0.35, 1.0, puddle);
	}
	col = mix(col, vec3(0.86, 0.9, 0.93), snow * (0.45 + 0.25 * g2));
	ALBEDO = col;
	if (use_ao) {
		AO = texture(ao_tex, UV2).r;
		AO_LIGHT_AFFECT = 0.85;
	}
	ROUGHNESS = mix(0.88, 0.06, wet);
	SPECULAR = mix(0.4, 0.6, wet);
	if (use_reflection && wet > 0.01) {
		vec2 ripple = (vec2(texture(grain_tex, world_xz * 0.9 + vec2(TIME * 0.21, TIME * 0.13)).r,
				texture(grain_tex, world_xz * 0.9 - vec2(TIME * 0.17, TIME * 0.19)).r) - 0.5) * 0.012 * rain;
		vec2 uv = SCREEN_UV + ripple + vec2(rings * 0.006);
		if (flip_x) {
			uv.x = 1.0 - uv.x;
		}
		vec3 refl = texture(reflection_tex, clamp(uv, vec2(0.001), vec2(0.999))).rgb;
		// Pfützen spiegeln fast wie ein Spiegel, der nasse Film nur schwach.
		float strength = mix(wetness * 0.22, 0.75, puddle);
		EMISSION = refl * strength;
		ALBEDO *= 1.0 - strength * 0.6;
	}
	// Ringe hellen die Oberfläche kurz auf (spiegeln das Himmelslicht).
	EMISSION += vec3(0.55, 0.62, 0.7) * rings * 0.35;
	// Laternenlicht (vorberechnet, mit weichen Gebäudeschatten) als beleuchtete Albedo.
	// Diffus (Farbe x Licht) plus Glanzanteil: Asphalt – vor allem nasser – wirft Laternenlicht auch als Schimmer zurück.
	EMISSION += lamp_at(world_xz) * (ALBEDO * 2.6 + vec3(0.07 + 0.16 * wetness + 0.25 * puddle));
}
