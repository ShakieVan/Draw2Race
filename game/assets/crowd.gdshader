shader_type spatial;
render_mode blend_mix, cull_disabled, specular_disabled;

// Zuschauerstreifen (Rennausstattung, tools/make_event_textures.py): Draufsicht auf Menschen; die Menge wiegt und hüpft leicht.
// UV.x läuft mit der Streckenlänge (6 m je Bildbreite), UV.y quer zur Reihe (0 = hinten, 1 = am Gitter).
// Nachts: Laternen-/Flutlicht der Lichtkarte wie auf dem Boden daneben (lamp_lit, höchstens Tageslicht) plus die Grundhelligkeit der Nacht
// (lamp_floor); vorher war die Menge neben beleuchteter Fahrbahn fast schwarz. Kein Eigenleuchten: alles ist Albedo x Licht.
//
// Zwei Durchgänge (world.gd, event_material "menge"; Befund 02.10.2026: Zuschauer wirkten in Dämmerung und Nacht blass und durchsichtig wie
// Geister). Ursache war nicht das Licht der Menge, sondern die Reihenfolge der durchsichtigen Durchgänge: Die Menge lag als halbtransparente
// Auflage 4 mm über den Tribünenstufen und schrieb keine Tiefe; das additive Laternen-Zusatzlicht der Stufen darunter (lit_overlay, nur bei
// Dunkelheit, ebenso die Schneedecke) wurde je nach Blickwinkel danach gezeichnet und addierte Sitzfarbe x Licht auf die Menschen.
// - Hauptdurchgang (dieser Shader): undurchsichtig mit Ausschnitt (ALPHA_SCISSOR_THRESHOLD = CROWD_SOLID). Die Menschen schreiben Tiefe;
//   Zusatzlicht, Schneedecke, Nebelbänke und Regen der Umgebung verdecken bzw. überlagern sie wie jede feste Fläche.
// - Weichteil-Durchgang (next_pass, dieselbe Datei mit CROWD_SOFT): nur die weichen Teile des Bildes (Schlagschatten, Umriss, Kantenglättung,
//   alpha < CROWD_SOLID) halbtransparent wie bisher; render_priority 1, also nach dem Zusatzlicht der Stufen: Schatten und Kanten liegen über
//   der beleuchteten Stufe.
// Alpha kommt nur aus dem Ausschnitt der Textur, nie aus dem Licht; beide Durchgänge rechnen Farbe und Licht gleich (am Tag wie vorher).
#include "res://assets/lamp_light.gdshaderinc"

const float CROWD_SOLID = 0.95;      // ab hier undurchsichtig (Innenflächen der Menschen; Bildkompression lässt 255 nicht ganz unverändert)

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float sway = 1.0;
uniform float light_gain = 1.6;      // Lichtkarte -> Licht auf der Menge (Boden: 2,3; die Menge steht höher und ist teils verschattet)

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV;
	float t = TIME;
	uv.y += (sin(t * 2.3 + UV.x * 38.0) * 0.034 + sin(t * 3.7 + UV.x * 71.0) * 0.022) * sway;
	uv.x += sin(t * 1.9 + UV.y * 17.0 + UV.x * 23.0) * 0.004 * sway;
	vec4 c = texture(albedo_tex, uv);
#ifdef CROWD_SOFT
	if (c.a >= CROWD_SOLID) {
		discard;                     // schon im Hauptdurchgang gezeichnet
	}
	ALPHA = c.a;
#else
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = CROWD_SOLID;
#endif
	ALBEDO = c.rgb;
	ROUGHNESS = 1.0;
	EMISSION = lamp_lit(c.rgb, lamp_at(world_pos.xz), light_gain, 0.9, 0.35, 0.7) + c.rgb * lamp_floor(1.0);
}
