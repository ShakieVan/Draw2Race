shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// Schneeflocken ohne Eigenleuchten: Sie sind so hell wie das Licht an ihrer Stelle (wie rain.gdshader):
// Tageslicht relativ zum Tag (day_light), Laternen aus der Lichtkarte, Scheinwerfer und Rücklichter der Autos.
uniform vec3 day_light = vec3(1.0);
#include "res://assets/lamp_light.gdshaderinc"
uniform int car_count = 0;
uniform vec4 car_pos[8];                     // xyz = Position, w = Fahrtrichtung (Winkel)
uniform float cars_lit = 0.0;                // 1 = Scheinwerfer an (Dämmerung/Nacht)

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 xz = world_pos.xz;
	vec3 light = day_light + lamp_at(xz) * 1.6;
	for (int i = 0; i < car_count; i++) {
		vec2 d = xz - car_pos[i].xz;
		vec2 fwd = vec2(cos(car_pos[i].w), sin(car_pos[i].w));
		float ahead = dot(d, fwd);
		float side = abs(dot(d, vec2(-fwd.y, fwd.x)));
		float cone = step(0.6, ahead) * (1.0 - smoothstep(4.0, 9.0, ahead)) * (1.0 - smoothstep(0.5 + ahead * 0.35, 0.9 + ahead * 0.45, side));
		light += vec3(1.0, 0.92, 0.72) * cone * 1.4 * cars_lit;
		float tail = step(ahead, -0.7) * (1.0 - smoothstep(0.3, 2.2, length(d + fwd * 1.1)));
		light += vec3(1.0, 0.12, 0.08) * tail * 1.2 * cars_lit;
	}
	// Kugel weich: Mitte hell, Rand dunkler (UV.y läuft über die Höhe der Kugel).
	float shade = 0.75 + 0.25 * sin(UV.y * 3.14159);
	ALBEDO = clamp(light * shade, vec3(0.0), vec3(1.0));
	ALPHA = 0.9;
}
