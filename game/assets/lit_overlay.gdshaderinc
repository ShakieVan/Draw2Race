// Zusatzlicht für Gebäude und Kulisse (als material_overlay über dem normalen Material), gemeinsam für lit_overlay.gdshader (einseitig, cull_back) und
// lit_overlay_two_sided.gdshader (beidseitig, cull_disabled, TWO_SIDED: Rückseiten mit umgedrehter Normale):
// - direkt: Flächen, die einer von Laternen beleuchteten Stelle zugewandt sind, werden angestrahlt;
// - indirekt: beleuchteter (bei Nässe stärker spiegelnder) Boden hellt die unteren Wandbereiche farbig auf.
// Laufzeit-Bauteile (Leitplanken, Wände, Looping, Seitenstreifen) bekommen dazu eine kleine Grundhelligkeit der Nacht (ambient_floor). Offene Bänder und das Looping
// nehmen die beidseitige Fassung: Die Oberseite des Rings ist aus der Draufsicht die Rückseite und bekam vorher kein Zusatzlicht.
#include "res://assets/lamp_light.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform vec4 tint : source_color = vec4(1.0);
uniform float light_gain = 1.0;          // Stärke des Zusatzlichts
uniform bool soft_clip = false;          // helle Stellen weich abfangen (helle Bausatz-Wände würden sonst weiß ausbrennen)
uniform bool use_vertex_color = false;   // Bausatz-Häuser: Putzton und Verschattung stecken in der Vertexfarbe
uniform float light_sat = 1.0;           // Anteil der Eigenfarbe unter Kunstlicht (Rasen: kleiner als 1, damit er nicht neongrün leuchtet)
uniform float ambient_floor = 0.0;       // Grundhelligkeit der Nacht (lamp_floor): 1 = Mond-/Himmelslicht wie auf dem Boden
uniform float omni = 0.0;                // Licht der Karte unabhängig von der Normale (halbtransparentes Looping-Band über beleuchteter Fahrbahn)

varying vec3 world_pos;
varying vec3 world_normal;
varying vec3 vcol;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vcol = COLOR.rgb;
}

void fragment() {
	if (lamp_strength <= 0.001) {
		discard;
	}
#ifdef TWO_SIDED
	vec3 wn = FRONT_FACING ? world_normal : -world_normal;
#else
	vec3 wn = world_normal;
#endif
	vec3 base = texture(albedo_tex, UV).rgb * tint.rgb;
	if (use_vertex_color) {
		base *= vcol;
	}
	vec2 n = wn.xz;
	float up = clamp(wn.y, 0.0, 1.0);
	// Licht vor der Fläche (in Blickrichtung der Normalen) gegenüber dahinter: zugewandte Seiten werden hell.
	vec3 front = lamp_at(world_pos.xz + n * 1.2);
	vec3 here = lamp_at(world_pos.xz);
	float height = world_pos.y;
	// Laternenköpfe hängen bei ~4 m: darüber nimmt das Licht auf Wänden rasch ab.
	float reach = 1.0 - smoothstep(3.0, 9.0, height);
	vec3 direct = front * length(n) * reach * 1.8 + here * up * 0.75 * reach;
	// Indirekt: vom Boden zurückgeworfen, nur nahe am Boden, nasser Boden reflektiert mehr.
	vec3 bounce = front * (1.0 - smoothstep(0.0, 3.5, height)) * (0.25 + 0.35 * street_wet);
	vec3 lit = (direct + bounce + here * omni * (1.0 - smoothstep(4.0, 12.0, height))) * light_gain;
	if (soft_clip) {
		lit = lit / (1.0 + 0.8 * lit);
	}
	// Albedo x Licht mit weicher Helligkeitsgrenze (lamp_light.gdshaderinc): auch überlappende Lichter brennen nicht aus.
	ALBEDO = lamp_lit(base, lit, 1.0, light_sat, 0.5, 0.95) + base * lamp_floor(ambient_floor);
}
