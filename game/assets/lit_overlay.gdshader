shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;
// Zusatzlicht für Gebäude und Kulisse (als material_overlay über dem normalen Material):
// - direkt: Flächen, die einer von Laternen beleuchteten Stelle zugewandt sind, werden angestrahlt;
// - indirekt: beleuchteter (bei Nässe stärker spiegelnder) Boden hellt die unteren Wandbereiche farbig auf.
#include "res://assets/lamp_light.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform vec4 tint : source_color = vec4(1.0);
uniform float light_gain = 1.0;          // Stärke des Zusatzlichts
uniform bool soft_clip = false;          // helle Stellen weich abfangen (helle Bausatz-Wände würden sonst weiß ausbrennen)
uniform bool use_vertex_color = false;   // Bausatz-Häuser: Putzton und Verschattung stecken in der Vertexfarbe

varying vec3 world_pos;
varying vec3 world_normal;
varying vec3 vcol;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vcol = COLOR.rgb;
}

void fragment() {
	if (lamp_strength <= 0.001) {
		discard;
	}
	vec3 base = texture(albedo_tex, UV).rgb * tint.rgb;
	if (use_vertex_color) {
		base *= vcol;
	}
	vec2 n = world_normal.xz;
	float up = clamp(world_normal.y, 0.0, 1.0);
	// Licht vor der Fläche (in Blickrichtung der Normalen) gegenüber dahinter: zugewandte Seiten werden hell.
	vec3 front = lamp_at(world_pos.xz + n * 1.2);
	vec3 here = lamp_at(world_pos.xz);
	float height = world_pos.y;
	// Laternenköpfe hängen bei ~4 m: darüber nimmt das Licht auf Wänden rasch ab.
	float reach = 1.0 - smoothstep(3.0, 9.0, height);
	vec3 direct = front * length(n) * reach * 1.8 + here * up * 0.75 * reach;
	// Indirekt: vom Boden zurückgeworfen, nur nahe am Boden, nasser Boden reflektiert mehr.
	vec3 bounce = front * (1.0 - smoothstep(0.0, 3.5, height)) * (0.25 + 0.35 * street_wet);
	vec3 lit = (direct + bounce) * light_gain;
	if (soft_clip) {
		lit = lit / (1.0 + 0.8 * lit);
	}
	ALBEDO = base * lit;
}
