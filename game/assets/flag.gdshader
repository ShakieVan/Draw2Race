shader_type spatial;
render_mode cull_disabled;

// Fahne im Wind (Rennausstattung, tools/diorama.py): UV.x = Abstand vom Mast (0 am Mast, 1 am freien Ende), Farbe aus der Vertexfarbe.
// Die Fläche wogt senkrecht zu sich selbst, zum freien Ende hin stärker; ein leichtes Durchhängen kommt dazu.
uniform float amplitude = 0.16;
uniform float speed = 2.6;
// Nachts: Fahnen hängen hoch über dem Boden und bekämen von Mond und Umgebungslicht fast nichts (schwarz). Sie werden wie die übrige
// Rennausstattung angestrahlt: Lampenlicht der Lichtkarte am Standort plus eine Grundhelligkeit des Flutlichts (skaliert mit lamp_strength:
// Tag 0, Dämmerung 0,6, Nacht 1).
uniform float flood = 0.34;

#include "res://assets/lamp_light.gdshaderinc"

varying vec3 world_pos;

void vertex() {
	float phase = TIME * speed + VERTEX.x * 1.7 + VERTEX.z * 2.1 + VERTEX.y * 0.9;
	float amt = amplitude * UV.x * UV.x;
	VERTEX += NORMAL * (sin(phase) * amt + sin(phase * 1.9 + 1.3) * amt * 0.4);
	VERTEX.y -= UV.x * UV.x * 0.06;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.75;
	SPECULAR = 0.2;
	vec3 light = lamp_at(world_pos.xz) * 1.8 + vec3(0.85, 0.9, 1.0) * flood * lamp_strength;
	EMISSION = lamp_lit(ALBEDO, light, 1.0, 0.9, 0.35, 0.7);
}
