shader_type spatial;
// Lack für KI-erzeugte Autos: Die Bild-zu-3D-KI backt einen hellgrauen Lack in die Farbtextur. Helle, kaum
// gesättigte Stellen gelten als Lack und werden in der Wagenfarbe getönt (Helligkeitsverlauf bleibt erhalten);
// dunkle oder farbige Teile (Scheiben, Kunststoff, Carbon, Rückleuchten) bleiben unverändert.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_disable;
uniform bool has_orm = false;
uniform vec4 paint_color : source_color = vec4(0.8, 0.15, 0.1, 1.0);
uniform float paint_min_light = 0.36;   // sRGB-Helligkeit, ab der Lack beginnt (Lack der Vorlagen ≈ 0,6)
uniform float paint_max_sat = 0.16;     // bis zu dieser Sättigung ist es Lack
uniform float paint_reference = 0.64;   // typische Lackhelligkeit der Vorlage (sRGB)
uniform float glow = 0.0;               // Hervorhebung des eigenen Autos (Puls aus main.gd)

void fragment() {
	vec3 base = texture(albedo_tex, UV).rgb;          // linear (source_color)
	vec3 srgb = pow(max(base, vec3(0.0)), vec3(1.0 / 2.2));
	float hi = max(srgb.r, max(srgb.g, srgb.b));
	float lo = min(srgb.r, min(srgb.g, srgb.b));
	float sat = hi > 0.001 ? (hi - lo) / hi : 0.0;
	float mask = smoothstep(paint_min_light, paint_min_light + 0.1, hi) * (1.0 - smoothstep(paint_max_sat, paint_max_sat + 0.08, sat));
	// Helligkeit relativ zum Lackgrau der Vorlage: eingebackene Schattierungen bleiben sichtbar.
	float shade = pow(clamp(hi / paint_reference, 0.0, 1.3), 2.2);
	vec3 painted = paint_color.rgb * shade;
	ALBEDO = mix(base, painted, mask);
	float rough = 0.5;
	float metal = 0.0;
	if (has_orm) {
		vec3 orm = texture(orm_tex, UV).rgb;
		rough = orm.g;
		metal = orm.b;
	}
	ROUGHNESS = mix(rough, 0.28, mask);
	METALLIC = mix(metal, 0.45, mask);
	CLEARCOAT = mask;
	CLEARCOAT_ROUGHNESS = 0.06;
	EMISSION = paint_color.rgb * glow * mask;
}
