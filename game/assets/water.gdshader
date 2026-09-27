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
	METALLIC = 0.0;
	SPECULAR = 0.75;
}
