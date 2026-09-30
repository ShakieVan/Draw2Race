shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// Nebelbank ohne Eigenleuchten: Ihre Farbe ist die Nebelfarbe mal dem Licht an dieser Stelle.
// - ambient_light: Umgebungs- und Sonnen-/Mondlicht relativ zum Tag (Tag = 1, nachts klein), setzt atmosphere.gd;
// - Laternenlicht aus der vorberechneten Lichtkarte (mit Schatten der Gebäude): Nebel streut es und glimmt um die Laternen.
uniform sampler2D soft_tex : source_color, filter_linear, repeat_disable;
uniform vec4 fog_color : source_color = vec4(0.9, 0.93, 0.95, 0.5);   // rgb: Nebelfarbe bei Tageslicht, a: Dichte in der Mitte der Bank
uniform vec3 ambient_light = vec3(1.0);
uniform float lamp_gain = 1.5;
#include "res://assets/lamp_light.gdshaderinc"

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float density = texture(soft_tex, UV).a * fog_color.a;
	vec3 light = ambient_light + lamp_at(world_pos.xz) * lamp_gain;
	ALBEDO = fog_color.rgb * light;
	ALPHA = density;
}
