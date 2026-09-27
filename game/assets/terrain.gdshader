shader_type spatial;
// Gelände (Premium-Grafik): Rasen mit Farbschwankungen und trockenen Stellen, Erd-Bankett entlang der Strecke mit
// unregelmäßigem, weich in den Rasen auslaufendem Rand. Der Abstand zur Streckenmitte kommt aus dist_tex
// (beim Streckenaufbau vorberechnet, world.gd).

uniform vec4 grass_a : source_color = vec4(0.45, 0.6, 0.38, 1.0);
uniform vec4 grass_b : source_color = vec4(0.36, 0.52, 0.3, 1.0);
uniform vec4 grass_dry : source_color = vec4(0.62, 0.62, 0.4, 1.0);
uniform vec4 dirt_a : source_color = vec4(0.55, 0.45, 0.32, 1.0);
uniform vec4 dirt_b : source_color = vec4(0.42, 0.34, 0.24, 1.0);
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D dist_tex : hint_default_white, filter_linear, repeat_disable;
uniform vec2 dist_origin = vec2(0.0);
uniform vec2 dist_size = vec2(100.0);
uniform float dist_max = 24.0;
uniform float shoulder = 4.9;     // Bankettbreite ab Streckenmitte (m)
uniform bool mow_stripes = false;
uniform float snow = 0.0;
uniform float wet = 0.0;

varying vec2 world_xz;

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	// Rauschen in vier Größen: großflächig (~20 m), Flecken (~5 m), Bankettrand (~1,5 m), Körnung (~20 cm).
	float n1 = texture(noise_tex, world_xz * 0.0032).r;
	float n2 = texture(noise_tex, world_xz * 0.013 + vec2(0.3, 0.8)).r;
	float n3 = texture(noise_tex, world_xz * 0.045 + vec2(0.61, 0.17)).r;
	float n4 = texture(noise_tex, world_xz * 0.35 + vec2(0.12, 0.43)).r;
	vec3 grass = mix(grass_a.rgb, grass_b.rgb, smoothstep(0.3, 0.7, n2));
	grass = mix(grass, grass_dry.rgb, smoothstep(0.58, 0.75, n1) * 0.35);
	grass *= 0.93 + 0.12 * n4;
	if (mow_stripes) {
		grass *= 1.0 + 0.045 * sign(sin(world_xz.y * 3.14159 / 2.2));
	}
	vec2 duv = (world_xz - dist_origin) / dist_size;
	float d = texture(dist_tex, clamp(duv, vec2(0.0), vec2(1.0))).r * dist_max;
	// Abgefahrener, dunklerer Rasen nahe der Strecke.
	grass *= mix(0.78, 1.0, smoothstep(shoulder, shoulder + 3.0 + n2 * 2.0, d));
	// Bankettrand: per Rauschen verschoben und weich überblendet.
	float edge = shoulder + (n3 - 0.5) * 1.4 + (n2 - 0.5) * 0.8;
	float dirt_mask = 1.0 - smoothstep(edge - 0.5, edge + 0.45, d);
	vec3 dirt = mix(dirt_a.rgb, dirt_b.rgb, n3) * (0.85 + 0.3 * n4);
	vec3 col = mix(grass, dirt, dirt_mask);
	col = mix(col, vec3(0.9, 0.93, 0.95), snow * (0.72 + 0.28 * n2));
	col *= 1.0 - 0.28 * wet;
	ALBEDO = col;
	ROUGHNESS = mix(0.92, 0.55, wet);
	SPECULAR = 0.35;
}
