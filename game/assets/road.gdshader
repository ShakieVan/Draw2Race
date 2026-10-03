shader_type spatial;
render_mode cull_disabled;
// Fahrbahn (Premium-Grafik): Körnung, Nässe, Pfützen und echte Spiegelungen.
// Die Spiegelung rendert eine an der Fahrbahnebene gespiegelte Kamera (atmosphere.gd) in reflection_tex.
// Pfützen liegen an festen Weltkoordinaten (Rauschtextur), Regen lässt die Spiegelung leicht wabern.

uniform vec4 base_color : source_color = vec4(0.22, 0.29, 0.31, 1.0);
uniform sampler2D grain_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D puddle_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform sampler2D reflection_tex : source_color, filter_linear, repeat_disable;
uniform bool use_reflection = false;
uniform bool flip_x = true;
uniform float grain_strength = 0.35;
uniform float wetness = 0.0;     // 0 trocken, 1 nasser Film
uniform float puddles = 0.0;     // 0 keine, 1 Pfützen sichtbar
uniform float snow = 0.0;        // 0 kein Schnee, 1 Schneeschleier
uniform float rain = 0.0;        // Regenstärke für die Wellen in der Spiegelung
uniform float puddle_cover = 0.62; // Schwelle der Pfützen-Rauschtextur (kleiner = mehr Pfützen)
uniform float wear = 0.0;         // Diorama: Verschleiß (Ausbesserungen, Risse, Ölflecken), 0 aus, 1 voll
// Diorama: Fototextur (Weltkoordinaten, Kachelgröße albedo_scale) und gebackene Umgebungsverdeckung (zweite UV-Ebene).
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool use_albedo = false;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform float albedo_scale = 6.0;
uniform sampler2D ao_tex : hint_default_white, filter_linear, repeat_disable;
uniform bool use_ao = false;
// Spurenkarte der Laufzeit-Fahrbahn (world.gd apply_wear_map; UV = Seitenversatz m, Bogenlänge m): R Gummi, G Politur, B Spurrinne
// (Erzeuger tests/make_wear.gd, docs/dioramen/README.md „Nutzungsspuren“). Unbunt: Gummi alt = weich, gräulich, höchstens 30 % dunkler
// (frische Laufzeitspuren liegen dunkler und scharf darüber); Politur höchstens 8 % glatter; Rinnen auf Schotter verdichtet (weniger
// Körnung, dunkler, falsche Normale ≤ 3 cm – nachts wirkt nur die Abdunklung, das Laternenlicht hängt nicht an der Normale);
// Regen: Gummi glänzt etwas, Pfützen sammeln sich in Rinnen; Schnee bleibt in Rinnen und auf der Politur weniger liegen.
// wear_strength 0 = keine Karte (alles wie ohne Spuren).
uniform sampler2D wear_map : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float wear_strength = 0.0;
uniform float wear_lat = 6.0;
uniform float wear_len = 1.0;

#include "res://assets/lamp_light.gdshaderinc"

varying vec2 world_xz;

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	float g1 = texture(grain_tex, world_xz * 0.45).r;
	float g2 = texture(grain_tex, world_xz * 2.1 + vec2(0.37, 0.71)).r;
	vec3 base = base_color.rgb;
	if (use_albedo) {
		base = texture(albedo_tex, world_xz / albedo_scale).rgb * albedo_tint.rgb;
	}
	vec3 used = vec3(0.0);
	if (wear_strength > 0.001) {
		used = texture(wear_map, vec2((UV.x + wear_lat) / (2.0 * wear_lat), UV.y / max(wear_len, 0.001))).rgb * wear_strength;
	}
	// Verdichtete Rinne: feinere Oberfläche (weniger Körnung).
	float grain_k = grain_strength * (1.0 - 0.6 * used.b);
	vec3 col = base * (1.0 - grain_k * 0.5 + grain_k * (0.6 * g1 + 0.4 * g2));
	if (wear > 0.001) {
		// Abgenutzter Asphalt: Ausbesserungsflecken mit scharfer Kante, feine Risse entlang von Höhenlinien der Rauschtextur,
		// vereinzelt dunkle Ölflecken. Alles in Weltkoordinaten, ohne zusätzliche Geometrie.
		float wa = texture(puddle_tex, world_xz * 0.085).r;
		float wb = texture(puddle_tex, world_xz * 0.27 + vec2(0.7, 0.2)).r;
		float wc = texture(puddle_tex, world_xz * 0.6 + vec2(0.13, 0.55)).r;
		float patch = smoothstep(0.60, 0.605, wa) * (0.55 + 0.45 * wb);
		float crack = (1.0 - smoothstep(0.0, 0.010, abs(wb - 0.5))) * smoothstep(0.30, 0.55, wa);
		float oil = smoothstep(0.66, 0.74, wc) * smoothstep(0.45, 0.6, wa);
		col *= 1.0 - wear * (0.15 * patch + 0.30 * crack + 0.17 * oil);
		col *= 1.0 + wear * 0.07 * (wb - 0.5);
	}
	// Pfützen: viele kleine, unregelmäßige Lachen (Rauschlagen 9 m, 3 m und 1 m), in den Fahrspuren länglich; um jede Lache bleibt
	// der Asphalt feucht und dunkel.
	if (wear_strength > 0.001) {
		// Alter Gummiabrieb: leicht entsättigt (gräulich) und höchstens 30 % dunkler; Rinne bis 16 % dunkler.
		float lum = dot(col, vec3(0.299, 0.587, 0.114));
		col = mix(col, mix(col, vec3(lum), 0.4) * 0.70, used.r);
		col *= 1.0 - 0.16 * used.b;
	}
	// Falsche Normale der Rinnen (Höhe −3 cm·B) aus Bildschirmableitungen; immer gerechnet (Ableitungen nicht in Verzweigungen),
	// ohne Karte ist B 0 und die Normale bleibt unverändert.
	float rut_h = -0.03 * used.b;
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	float dhx = dFdx(rut_h);
	float dhy = dFdy(rut_h);
	float rut = 0.0;
	if (COLOR.r < 0.5) {
		float lat = UV.x * 6.0;     // Hauptband: Querabstand zur Mittellinie (m)
		rut = exp(-pow((abs(lat) - 1.05) / 0.4, 2.0)) + exp(-pow((abs(lat) - 2.55) / 0.4, 2.0));
	}
	vec2 pc = world_xz;
	float pn = texture(puddle_tex, pc * 0.09).r * 0.5 + texture(puddle_tex, pc * 0.29 + vec2(0.31, 0.17)).r * 0.32 + texture(puddle_tex, pc * 0.83 + vec2(0.6, 0.4)).r * 0.18;
	pn += rut * 0.07 + used.b * 0.12;
	float puddle = smoothstep(puddle_cover, puddle_cover + 0.028, pn) * puddles;
	float damp = smoothstep(puddle_cover - 0.07, puddle_cover, pn) * puddles;
	float wet = clamp(max(max(wetness * 0.65, puddle), damp * 0.8), 0.0, 1.0);
	col *= mix(1.0, 0.5, wet);
	// Aufschlagringe der Regentropfen: je 0,45-m-Zelle ein Tropfen mit eigener Phase und Lage, zwei Lagen.
	float rings = 0.0;
	if (rain > 0.01) {
		for (int layer = 0; layer < 2; layer++) {
			vec2 cell_uv = world_xz / 0.45 + float(layer) * vec2(0.37, 0.61);
			vec2 cell = floor(cell_uv);
			vec2 local = fract(cell_uv) - 0.5;
			float h1 = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
			float h2 = fract(sin(dot(cell, vec2(39.3467, 11.135))) * 24634.6345);
			vec2 center = (vec2(h1, h2) - 0.5) * 0.5;
			float age = fract(TIME * (1.1 + h1 * 0.6) + h2);
			float radius = age * 0.42;
			float dist = length(local - center);
			rings += (1.0 - smoothstep(0.0, 0.035, abs(dist - radius))) * (1.0 - age) * (1.0 - age);
		}
		rings *= rain * mix(0.35, 1.0, puddle);
	}
	// Schnee bleibt in Rinnen und auf der Politur (Ideallinie) weniger liegen.
	float snow_k = snow * (1.0 - 0.5 * used.b) * (1.0 - 0.35 * used.g);
	col = mix(col, vec3(0.88, 0.91, 0.95), snow_k * (0.82 + 0.14 * g2));      // starker Schneefall: die Straße ist kaum noch zu erkennen
	ALBEDO = col;
	if (used.b > 0.002) {
		vec3 r1 = cross(dpdy, NORMAL);
		vec3 r2 = cross(NORMAL, dpdx);
		float det = dot(dpdx, r1);
		if (abs(det) > 1e-10) {
			NORMAL = normalize(abs(det) * NORMAL - sign(det) * (dhx * r1 + dhy * r2));
		}
	}
	if (use_ao) {
		AO = texture(ao_tex, UV2).r;
		AO_LIGHT_AFFECT = 0.85;
	}
	ROUGHNESS = max(0.04, mix(mix(0.88, 0.06, wet), 0.8, snow_k) - 0.08 * used.g - 0.10 * used.r * wetness);
	SPECULAR = mix(0.4, 0.6, wet);
	if (use_reflection && wet > 0.01) {
		vec2 ripple = (vec2(texture(grain_tex, world_xz * 0.9 + vec2(TIME * 0.21, TIME * 0.13)).r,
				texture(grain_tex, world_xz * 0.9 - vec2(TIME * 0.17, TIME * 0.19)).r) - 0.5) * 0.012 * rain;
		vec2 uv = SCREEN_UV + ripple + vec2(rings * 0.006);
		if (flip_x) {
			uv.x = 1.0 - uv.x;
		}
		vec3 refl = texture(reflection_tex, clamp(uv, vec2(0.001), vec2(0.999))).rgb;
		// Spiegelbild neutraler halten: der Himmel der Dämmerung färbt sonst ganze Pfützen violett.
		refl = mix(vec3(dot(refl, vec3(0.299, 0.587, 0.114))), refl, 0.55);
		// Pfützen spiegeln fast wie ein Spiegel, der nasse Film nur schwach.
		float strength = mix(wetness * 0.2, 0.62, puddle) + 0.06 * used.r * wetness * (1.0 - puddle);
		EMISSION = refl * strength;
		ALBEDO *= 1.0 - strength * 0.6;
	}
	// Ringe hellen die Oberfläche kurz auf (spiegeln das Himmelslicht).
	EMISSION += vec3(0.55, 0.62, 0.7) * rings * 0.35;
	// Laternenlicht (vorberechnet, mit weichen Gebäudeschatten) als beleuchtete Albedo.
	// Diffus (Farbe x Licht) plus Glanzanteil: Asphalt – vor allem nasser – wirft Laternenlicht auch als Schimmer zurück.
	// Der diffuse Teil ist höchstens Tageslicht (lamp_day, lamp_light.gdshaderinc): unter dicht stehenden Flutlichtern wurde der Asphalt sonst heller als am Tag.
	vec3 lamp = lamp_at(world_xz);
	EMISSION += ALBEDO * lamp_day(lamp * mix(2.6, 0.9, snow)) + lamp * vec3(0.07 + 0.16 * wetness + 0.25 * puddle);
}
