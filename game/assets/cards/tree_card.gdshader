shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
// Baumkarte (Billboard): ein Bild mit Transparenz, immer der Hauptkamera zugewandt (auch im Schattendurchgang,
// damit der Schatten zur sichtbaren Silhouette passt). Beleuchtet wie der Boden (Sonne, Himmel) plus
// vorberechnetes Laternenlicht.
#include "res://assets/lamp_light.gdshaderinc"

uniform sampler2D card : source_color, filter_linear_mipmap, repeat_disable;

varying vec3 world_pos;
varying float shade;

void vertex() {
	// Instanz-Position/-Skalierung behalten, Ausrichtung von der Hauptkamera übernehmen.
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	mat4 facing = mat4(MAIN_CAM_INV_VIEW_MATRIX[0], MAIN_CAM_INV_VIEW_MATRIX[1], MAIN_CAM_INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	// Spiegelung je Instanz über das Vorzeichen der x-Achse (Abwechslung im Wald).
	float flip = sign(dot(MODEL_MATRIX[0].xyz, vec3(1.0, 0.0, 0.0)) + 0.0001);
	// Höhe gestaucht: Ein senkrechter Baum erscheint aus dem Kamerawinkel (~53°) nur mit ~65 % seiner Höhe.
	vec4 local = vec4(VERTEX.x * scale.x * flip, VERTEX.y * scale.y * 0.65, 0.0, 1.0);
	world_pos = (facing * local).xyz;
	MODELVIEW_MATRIX = VIEW_MATRIX * facing;
	VERTEX = local.xyz;
	// Normale nach oben/zur Kamera gemischt: Kronen werden von oben beleuchtet wie der Boden.
	NORMAL = normalize(mat3(inverse(facing)) * vec3(0.0, 0.8, 0.6));
	shade = 0.75 + 0.25 * UV.y;
}

void fragment() {
	vec4 c = texture(card, UV);
	ALBEDO = c.rgb * mix(0.8, 1.0, 1.0 - UV.y);
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
	EMISSION = ALBEDO * lamp_at(world_pos.xz) * 1.4;
}
