shader_type spatial;
// Wasser (Premium-Grafik): zwei gegeneinander treibende Wellennormalen, glitzernde Sonnenreflexe, leichte
// Farbschwankung. Nur Darstellung.

uniform vec4 shallow : source_color = vec4(0.27, 0.62, 0.62, 1.0);
uniform vec4 deep : source_color = vec4(0.12, 0.38, 0.45, 1.0);
uniform sampler2D wave_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D wave_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D tint_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float wave_scale = 0.08;
uniform float speed = 0.02;
uniform float choppy = 0.55;   // Regen/Wind: stärkere Wellen
// Küste: Wassertiefe in der Vertexfarbe (Rot: 0 = Ufer, 1 = 1,6 m und tiefer), daraus Farbe und Brandung.
uniform bool use_depth = false;
uniform vec4 lagoon_col : source_color = vec4(0.36, 0.80, 0.74, 1.0);
uniform vec4 open_col : source_color = vec4(0.05, 0.30, 0.44, 1.0);
uniform vec4 foam_col : source_color = vec4(0.93, 0.96, 0.96, 1.0);

#include "res://assets/lamp_light.gdshaderinc"

varying vec2 world_xz;

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 uv1 = world_xz * wave_scale + vec2(TIME * speed, TIME * speed * 0.6);
	vec2 uv2 = world_xz * wave_scale * 1.7 - vec2(TIME * speed * 0.8, -TIME * speed * 0.45);
	vec3 n1 = texture(wave_a, uv1).rgb;
	vec3 n2 = texture(wave_b, uv2).rgb;
	NORMAL_MAP = normalize(mix(vec3(0.5, 0.5, 1.0), (n1 + n2) * 0.5, choppy));
	float t = texture(tint_noise, world_xz * 0.01 + vec2(TIME * 0.002)).r;
	ALBEDO = mix(shallow.rgb, deep.rgb, smoothstep(0.3, 0.75, t));
	ROUGHNESS = 0.08;
	if (use_depth) {
		float d = COLOR.r;
		vec3 water = mix(lagoon_col.rgb, open_col.rgb, smoothstep(0.04, 0.85, d));
		ALBEDO = water * (0.92 + 0.16 * t);
		// Brandung: Schaumsaum an der Wasserlinie und auflaufende Schaumstreifen im Flachen.
		float edge = 1.0 - smoothstep(0.0, 0.035, d);
		float wave = smoothstep(0.82, 1.0, sin(d * 70.0 - TIME * 1.6 + n1.r * 3.0) * 0.5 + 0.5) * (1.0 - smoothstep(0.02, 0.16, d));
		float foam = clamp(edge + wave * 0.7, 0.0, 1.0) * (0.75 + 0.25 * n2.g);
		ALBEDO = mix(ALBEDO, foam_col.rgb, foam);
		ROUGHNESS = mix(0.06, 0.6, foam);
	}
	METALLIC = 0.0;
	SPECULAR = 0.75;
	// Laternen-/Flutlicht (Lichtkarte): Das dunkle Wasser streut wenig, nimmt aber Lichtfarbe und Stärke der Lampen auf; helle Schaumsäume etwas mehr.
	// Eigener Durchgang mit Vertexfarbe (lit_overlay) entfällt: Die Tiefe steckt in COLOR.r und färbte das Licht rot.
	EMISSION += lamp_lit(ALBEDO, lamp_at(world_xz), 0.55, 0.85, 0.06, 0.16);
}
