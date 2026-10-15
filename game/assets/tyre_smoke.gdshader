shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// Reifenqualm, Gischt und Staub hinter den Autos (world.gd: smoke_mesh, dust_material). Ohne Eigenleuchten wie Nebel und Schnee
// (fog_bank.gdshader, snow.gdshader): so hell wie das Licht an seiner Stelle – Tageslicht relativ zum Tag (day_light, nachts klein) und
// Laternen-/Flutlicht aus der Lichtkarte (Nutzerregel „nichts leuchtet nachts selbst“). Beleuchtet wie ein Standardmaterial wurde der
// Qualm nachts zu dunkelblauen Flecken auf der von den Laternen erhellten Fahrbahn (Kontrollbild).
// Billboard für Partikel wie BILLBOARD_PARTICLES (Drehung aus INSTANCE_CUSTOM.x), aber mit der Größe des Partikels: Ohne „keep scale“
// verlor das Standardmaterial die Größe, und die Ballen quollen nicht auf.
uniform sampler2D puff_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 day_light = vec3(1.0);
uniform float lamp_gain = 1.4;
// Deckkraft je Emitter: Der Geist setzt 0,35 (main.gd spawn_ghost). GeometryInstance3D.transparency wirkt hier nicht – der Shader setzt
// ALPHA selbst, und der Mobile-Renderer kennt sie ohnehin nicht.
instance uniform float fade = 1.0;
#include "res://assets/lamp_light.gdshaderinc"
varying vec3 world_pos;

void vertex() {
	mat4 mat_world = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	mat_world = mat_world * mat4(vec4(cos(INSTANCE_CUSTOM.x), -sin(INSTANCE_CUSTOM.x), 0.0, 0.0), vec4(sin(INSTANCE_CUSTOM.x), cos(INSTANCE_CUSTOM.x), 0.0, 0.0),
		vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	float size = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat_world * mat4(vec4(size, 0.0, 0.0, 0.0), vec4(0.0, size, 0.0, 0.0), vec4(0.0, 0.0, size, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	// Um die halbe Ballengröße zur Kamera rücken: Sonst schneidet die Fahrbahn den unteren Teil der schräg stehenden Scheibe gerade ab
	// (harte Kante im Kontrollbild). Die Kamera ist weit weg, die Größe ändert sich dadurch nicht sichtbar.
	MODELVIEW_MATRIX[3].z += size * 0.5;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	world_pos = MODEL_MATRIX[3].xyz;
}

void fragment() {
	vec4 puff = texture(puff_tex, UV);
	vec3 light = day_light + lamp_day(lamp_at(world_pos.xz) * lamp_gain);
	ALBEDO = COLOR.rgb * puff.rgb * light;
	ALPHA = COLOR.a * puff.a * fade;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	// OpenGL-Rückfall (Geräte ohne Vulkan): Dort landet die Farbe dieses Shaders ohne Umrechnung nach sRGB im Bildpuffer und wird dort
	// überblendet. Qualm wirkte blass und grau (Kontrast zur Fahrbahn ≈42 statt ≈107 Graustufen, Gegenprüfung 15.10.2026; dichter Qualm
	// höchstens 159 statt 201 – genau der lineare Wert). Deshalb hier selbst nach sRGB umrechnen und die Deckkraft anheben, sodass eine
	// Lage auf dunklem Asphalt etwa so hell wird wie bei linearer Überblendung. Exponent 1,6: ausgeglichen für Asphalt (sRGB ≈0,32) unter
	// Qualm (≈0,82) mit 10–60 % Deckkraft (genau wären 1,9 bis 1,4).
	ALBEDO = mix(ALBEDO * 12.92, 1.055 * pow(ALBEDO, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), ALBEDO));
	ALPHA = 1.0 - pow(1.0 - clamp(ALPHA, 0.0, 1.0), 1.6);
#endif
}
