shader_type spatial;
render_mode blend_mix, cull_disabled, specular_disabled;

// Zuschauerstreifen (Rennausstattung, tools/make_event_textures.py): Draufsicht auf Menschen; die Menge wiegt und hüpft leicht.
// UV.x läuft mit der Streckenlänge (6 m je Bildbreite), UV.y quer zur Reihe (0 = hinten, 1 = am Gitter).
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float sway = 1.0;

void fragment() {
	vec2 uv = UV;
	float t = TIME;
	uv.y += (sin(t * 2.3 + UV.x * 38.0) * 0.034 + sin(t * 3.7 + UV.x * 71.0) * 0.022) * sway;
	uv.x += sin(t * 1.9 + UV.y * 17.0 + UV.x * 23.0) * 0.004 * sway;
	vec4 c = texture(albedo_tex, uv);
	ALBEDO = c.rgb;
	ALPHA = c.a;
	ROUGHNESS = 1.0;
}
