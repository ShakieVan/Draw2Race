// Vorberechnetes Laternenlicht (Atmosphere.bake_lamp_light): Draufsicht-Karte mit Farbe x Stärke, inklusive
// weicher Schatten der Gebäude. Gemeinsam für Fahrbahn, Gelände, Kulisse, Autos und Regen.
global uniform sampler2D lamp_light : source_color, filter_linear, repeat_disable;
global uniform vec2 lamp_origin;
global uniform vec2 lamp_size;
global uniform float lamp_strength;
global uniform float street_wet;

vec3 lamp_at(vec2 xz) {
	vec2 uv = (xz - lamp_origin) / lamp_size;
	if (uv.x <= 0.0 || uv.y <= 0.0 || uv.x >= 1.0 || uv.y >= 1.0) {
		return vec3(0.0);
	}
	return texture(lamp_light, uv).rgb * lamp_strength;
}
