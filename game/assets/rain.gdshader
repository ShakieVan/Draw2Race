shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
// Regentropfen ohne Eigenfarbe: Sie werfen nur Licht zurück, das an ihrer Position ankommt.
// - Tageslicht (Sonne/Himmel) gleichmäßig über day_light,
// - Laternen/Flutlicht/Wegleuchten über eine beim Streckenaufbau berechnete Lichtkarte (Farbe + Stärke),
// - Scheinwerfer (Kegel nach vorn) und Rücklichter (rot) der Autos, live aus main.gd.
// Zum Boden hin heller (Tiefenhinweis in der steilen Draufsicht), oben fast unsichtbar.

uniform vec3 day_light = vec3(0.0);
#include "res://assets/lamp_light.gdshaderinc"
uniform int car_count = 0;
uniform vec4 car_pos[8];                     // xyz = Position, w = Fahrtrichtung (Winkel)
uniform float cars_lit = 0.0;                // 1 = Scheinwerfer an (Dämmerung/Nacht)
uniform float spawn_height = 9.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 xz = world_pos.xz;
	vec3 light = day_light;
	light += lamp_at(xz) * 1.4;
	for (int i = 0; i < car_count; i++) {
		vec2 d = xz - car_pos[i].xz;
		vec2 fwd = vec2(cos(car_pos[i].w), sin(car_pos[i].w));
		float ahead = dot(d, fwd);
		float side = abs(dot(d, vec2(-fwd.y, fwd.x)));
		// Scheinwerferkegel: 1–9 m vor dem Auto, öffnet sich nach vorn.
		float cone = step(0.6, ahead) * (1.0 - smoothstep(4.0, 9.0, ahead)) * (1.0 - smoothstep(0.5 + ahead * 0.35, 0.9 + ahead * 0.45, side));
		light += vec3(1.0, 0.92, 0.72) * cone * 1.4 * cars_lit;
		// Rücklichter: kleiner roter Schein hinter dem Auto.
		float tail = step(ahead, -0.7) * (1.0 - smoothstep(0.3, 2.2, length(d + fwd * 1.1)));
		light += vec3(1.0, 0.12, 0.08) * tail * 1.2 * cars_lit;
	}
	float h = clamp(world_pos.y / spawn_height, 0.0, 1.0);
	float near_ground = mix(1.0, 0.08, smoothstep(0.1, 0.9, h));
	// Streifen weich auslaufend (UV.y entlang des Tropfens).
	float streak = sin(UV.y * 3.14159);
	ALBEDO = light * near_ground * streak * 0.55;
}
