shader_type spatial;
// Boden der Dioramen mit weichen Übergängen: Rasen, Sand und Erde werden je Punkt gemischt. Die Anteile kommen aus der
// Vertexfarbe des Geländenetzes (tools/diorama.py): R = Helligkeit (Mähstreifen, Flecken), G = Sand, B = Erde/Schlamm.
// Der Übergang wird mit dem Rauschen der Texturen aufgebrochen (kein gerader Rand), nasser Sand nahe der Wasserlinie ist dunkler
// und glänzt. Laternenlicht, Nässe und Schnee wie beim übrigen Boden.

uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_n : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D sand_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_n : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_n : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D ao_tex : hint_default_white, filter_linear, repeat_disable;
uniform bool use_ao = false;
uniform vec3 grass_tint : source_color = vec3(0.9, 0.95, 0.85);
uniform vec3 sand_tint : source_color = vec3(0.96, 0.94, 0.9);
uniform vec3 dirt_tint : source_color = vec3(0.85, 0.8, 0.74);
uniform float grass_scale = 3.0;
uniform float sand_scale = 4.0;
uniform float dirt_scale = 3.0;
uniform float water_y = -1000.0;
uniform float snow = 0.0;
uniform float wet = 0.0;

#include "res://assets/lamp_light.gdshaderinc"

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 xz = world_pos.xz;
	vec3 g = texture(grass_tex, xz / grass_scale).rgb * grass_tint * COLOR.r;
	vec3 s = texture(sand_tex, xz / sand_scale).rgb * sand_tint;
	vec3 d = texture(dirt_tex, xz / dirt_scale).rgb * dirt_tint;
	// Übergang aufbrechen: die Helligkeit der Texturen verschiebt die Schwelle (Grasbüschel im Sand, Sand zwischen Halmen).
	float breakup = (dot(texture(grass_tex, xz * 0.21).rgb, vec3(0.33)) - 0.35) * 0.9;
	float ws = smoothstep(0.42, 0.58, COLOR.g + breakup * 0.6);
	float wd = smoothstep(0.42, 0.58, COLOR.b + breakup * 0.5);
	vec3 col = mix(g, s, ws);
	col = mix(col, d, wd);
	vec3 n = mix(texture(grass_n, xz / grass_scale).rgb, texture(sand_n, xz / sand_scale).rgb, ws);
	n = mix(n, texture(dirt_n, xz / dirt_scale).rgb, wd);
	// Nasser Sand nahe der Wasserlinie
	float damp = clamp((water_y + 0.32 - world_pos.y) / 0.4, 0.0, 1.0) * ws;
	col *= 1.0 - 0.34 * damp;
	float wet_all = max(wet, damp);
	col *= 1.0 - 0.25 * wet;
	col = mix(col, vec3(0.9, 0.93, 0.95), snow * (0.75 + 0.2 * breakup));
	ALBEDO = col;
	NORMAL_MAP = n;
	NORMAL_MAP_DEPTH = mix(1.0, 0.4, snow);
	ROUGHNESS = mix(0.93, 0.35, wet_all);
	SPECULAR = mix(0.3, 0.55, wet_all);
	if (use_ao) {
		AO = texture(ao_tex, UV2).r;
		AO_LIGHT_AFFECT = 0.7;
	}
	// Laternen-/Flutlicht: Albedo x Licht, entsättigt und mit weicher Helligkeitsgrenze (lamp_light.gdshaderinc), kein Neon-Rasen.
	EMISSION += lamp_lit(ALBEDO, lamp_at(xz), 2.3, 0.72, 0.28, 0.6);
}
