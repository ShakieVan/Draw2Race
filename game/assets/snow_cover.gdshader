shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;
// Schneedecke als Zusatzschicht über beliebigen Netzen (material_overlay): Der Schnee liegt auf nach oben zeigenden Flächen,
// unregelmäßig am Rand; Wände bleiben frei. Er wird wie alles beleuchtet (Sonne/Mond, Umgebung) und erhält das
// Laternenlicht aus der Lichtkarte; ein paar Zentimeter Dicke trennen die Schicht vom Untergrund (kein Z-Kampf, weiche Kanten).
#include "res://assets/lamp_light.gdshaderinc"

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float min_up = 0.45;       // ab dieser Aufwärtsneigung (Normale y) bleibt Schnee liegen
uniform float strength = 0.96;     // größte Deckkraft (kleinere Werte lassen Markierungen durchscheinen)
uniform float lift = 0.012;        // Schneehöhe in Metern

varying vec3 wpos;
varying float up_amount;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	up_amount = clamp(wn.y, 0.0, 1.0);
	VERTEX += NORMAL * lift * smoothstep(min_up, min_up + 0.3, up_amount);
}

void fragment() {
	float n1 = texture(noise_tex, wpos.xz * 0.11).r;
	float n2 = texture(noise_tex, wpos.xz * 0.47 + vec2(0.3, 0.7)).r;
	float edge = smoothstep(min_up, min_up + 0.25, up_amount + (n1 - 0.5) * 0.3);
	float cover = edge * (0.92 + 0.16 * (n2 - 0.5));
	ALBEDO = vec3(0.92, 0.94, 0.97) * (0.96 + 0.08 * n2);
	ROUGHNESS = 0.8;
	SPECULAR = 0.25;
	ALPHA = clamp(cover * strength, 0.0, 1.0);
	// Laternenlicht liegt am Boden: Dächer und hohe Flächen bekommen es nicht.
	float near_ground = 1.0 - smoothstep(1.0, 5.0, wpos.y);
	EMISSION = lamp_at(wpos.xz) * ALBEDO * 0.75 * near_ground;
}
