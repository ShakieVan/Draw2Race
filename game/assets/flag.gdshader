shader_type spatial;
render_mode cull_disabled;

// Fahne im Wind (Rennausstattung, tools/diorama.py): UV.x = Abstand vom Mast (0 am Mast, 1 am freien Ende), Farbe aus der Vertexfarbe.
// Die Fläche wogt senkrecht zu sich selbst, zum freien Ende hin stärker; ein leichtes Durchhängen kommt dazu.
uniform float amplitude = 0.16;
uniform float speed = 2.6;

void vertex() {
	float phase = TIME * speed + VERTEX.x * 1.7 + VERTEX.z * 2.1 + VERTEX.y * 0.9;
	float amt = amplitude * UV.x * UV.x;
	VERTEX += NORMAL * (sin(phase) * amt + sin(phase * 1.9 + 1.3) * amt * 0.4);
	VERTEX.y -= UV.x * UV.x * 0.06;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.75;
	SPECULAR = 0.2;
}
