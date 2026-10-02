// Vorberechnetes Laternenlicht (Atmosphere.bake_lamp_light): Draufsicht-Karte mit Farbe x Stärke, inklusive
// weicher Schatten der Gebäude. Gemeinsam für Fahrbahn, Gelände, Kulisse, Autos und Regen.
global uniform sampler2D lamp_light : source_color, filter_linear, repeat_disable;
global uniform vec2 lamp_origin;
global uniform vec2 lamp_size;
global uniform float lamp_strength;
global uniform float street_wet;

vec3 lamp_at(vec2 xz) {
	vec2 uv = (xz - lamp_origin) / lamp_size;
	if (uv.x <= 0.0 || uv.y <= 0.0 || uv.x >= 1.0 || uv.y >= 1.0) {
		return vec3(0.0);
	}
	return texture(lamp_light, uv).rgb * lamp_strength;
}

// Beleuchtete Fläche: Albedo x Laternen-/Flutlicht als Emission, physikalisch gezähmt. Vorher addierte jeder Boden Albedo x Licht x 2,6 ohne
// Obergrenze; gesättigter Rasen unter Flutlicht lief so in ein neonhelles Lindgrün (Nutzerbefund 02.10.2026). Jetzt:
// - Farbe des Lichts und seine Stärke kommen unverändert aus der Lichtkarte (Lichtfarbe x Energie je Lampe, Summe überlappender Lampen);
// - die Albedo wird bei Kunstlicht zur Luminanz hin entsättigt (sat = Anteil der Eigenfarbe; 1 = unverändert), damit Gras unter warmem Licht
//   olivgrün statt giftgrün wirkt und das Licht die Sättigung nicht noch verstärkt;
// - das wirksame Licht ist höchstens Tageslicht (lamp_day, LAMP_DAY): keine beleuchtete Fläche wird nachts heller als ihre Albedo;
// - die Helligkeit der Emission läuft weich in ein Maximum (Knie bei knee, Grenzwert peak, Farbton bleibt): Überlappungen und starke Lampen
//   brennen nicht aus. Unterhalb des Knies greift die Begrenzung nicht ein.
const vec3 LAMP_LUMA = vec3(0.299, 0.587, 0.114);

vec3 lamp_limit(vec3 e, float knee, float peak) {
	float le = dot(e, LAMP_LUMA);
	if (le <= knee) {
		return e;
	}
	float room = max(peak - knee, 0.001);
	float limited = knee + room * (1.0 - exp(-(le - knee) / room));
	return e * (limited / le);
}

// Tageslicht-Grenze (Befund Azure-Stadion bei Nacht, 02.10.2026): Unter sieben Flutlichtern und vierzehn Masten summierte sich das Licht auf ein
// Mehrfaches des Tageslichts; Rasen und Fahrbahn waren nachts heller als am Tag (blasses Lindgrün). Deshalb wird zuerst das wirksame Licht
// (Lichtkarte x gain) weich auf LAMP_DAY begrenzt: Eine beleuchtete Fläche wird höchstens so hell wie ihre Albedo (Tageslicht des Spiels:
// Sonne 0,95 unter 52 Grad plus Himmel, etwa Albedo x 1,2; das Mondlicht kommt nachts noch dazu). Unterhalb von LAMP_DAY_KNEE ändert sich nichts,
// gewöhnliche Laternen (Stadt, Hafen, Jahrmarkt) bleiben im Rand ihres Lichtkegels wie bisher; nur ihre Mitte brennt nicht mehr aus.
const float LAMP_DAY = 1.0;
const float LAMP_DAY_KNEE = 0.6;

vec3 lamp_day(vec3 light) {
	return lamp_limit(light, LAMP_DAY_KNEE, LAMP_DAY);
}

vec3 lamp_lit(vec3 albedo, vec3 light, float gain, float sat, float knee, float peak) {
	vec3 alb = mix(vec3(dot(albedo, LAMP_LUMA)), albedo, sat);
	return lamp_limit(alb * lamp_day(light * gain), knee, peak);
}

// Grundhelligkeit der Nacht für Laufzeit-Bauteile (Leitplanken, Wände, Looping, Zuschauer): Albedo x Mond-/Himmelslicht, wie es der Boden nachts
// ohnehin bekommt (Mond 0,12 von oben plus Himmel; senkrechte Flächen und Unterseiten bekämen sonst fast nichts). Kein Eigenleuchten: das Ergebnis
// ist Albedo x Licht und folgt lamp_strength (Tag 0, Dämmerung 0,6, Nacht 1).
const vec3 LAMP_NIGHT_FLOOR = vec3(0.045, 0.055, 0.085);

vec3 lamp_floor(float amount) {
	return LAMP_NIGHT_FLOOR * amount * lamp_strength;
}
