shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
// Reifenspuren als Ringpuffer-MultiMesh: je Spurstück eine Instanz (Farbe, Entstehungszeit in INSTANCE_CUSTOM.x).
// Ausblenden über die letzten 12 s der Lebensdauer im Shader – kein Neuaufbau des Netzes mehr.
#include "res://assets/lamp_light.gdshaderinc"

uniform float now = 0.0;
uniform float lifetime = 45.0;

varying vec4 tint;
varying vec2 world_xz;

void vertex() {
	tint = COLOR;
	tint.a *= clamp((lifetime - (now - INSTANCE_CUSTOM.x)) / 12.0, 0.0, 1.0);
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	ALBEDO = tint.rgb;
	ALPHA = tint.a;
	ROUGHNESS = 1.0;
	EMISSION = ALBEDO * lamp_at(world_xz) * 1.5;
}
