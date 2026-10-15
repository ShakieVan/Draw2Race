class_name RaceVehicle
extends RefCounted

# Dynamic bicycle model. World position is integrated ONLY here.
const VERSION := "bicycle-7"   # 15.10.2026: Vorzeichenfehler im Einspurmodell behoben (Querachse zeigte nach rechts, Schräglauf, Kraft und
                               # Giermoment rechneten mit links); Antriebsart je Auto, Drift King mit Heckantrieb über den Reibkreis der
                               # Hinterachse (Traktionsgrenze, rear_spin). Alle Fahrten ändern sich: alte Geister nicht mehr abspielen.
                               # Am selben Tag (noch unveröffentlicht, daher dieselbe Version): Fahrer-Regler mit Rückkehr-Episoden statt
                               # 7-m/s-Schalter, Bremsdosierung, Freifahren/Zurücksetzen, Fortschritt im Bezug der eigenen Linie an
                               # Abkürzungen, Bug und Heck an der Wippenseite; nach der Gegenprüfung: Episode gegen die geglättete Linie,
                               # Anlauf der Schwungzonen ohne Rückkehrdeckel, Gas im Reibkreis, Wrack nur bei Linie durchs Hindernis.
                               # bicycle-6 (03.10.2026): Randpfosten der Schotterpisten als Hindernisse (Holz bricht), dritter Prüfkreis für
                               # schlanke Hindernisse, Leitpfosten/Torbogen/Schildmasten der Serra
                               # bicycle-5 (03.10.2026): Wandreibung skaliert mit dem Stoß, Höhenebenen und Wippe
# Fahrer-Regler; gemessen mit tests/tune_controller.gd.
static var LOOK_BASE := 4.0
static var LOOK_GAIN := 0.40
static var YAW_DAMPING := 0.18
static var STEER_RATE := 2.6
# Haftungsfaktor des aktuellen Wetters (1 trocken, 0,85 nass, 0,7 Schnee); setzt main.gd je Rennen.
static var weather_grip := 1.0
const SURFACE_GRIP := {"asphalt": 1.0, "curb": 0.95, "gravel": 0.8, "dirt": 0.65, "mud": 0.5}
const SURFACE_DRAG := {"asphalt": 0.0, "curb": 0.05, "gravel": 0.18, "dirt": 0.55, "mud": 1.1}
const ISLAND_LIMIT := Circuit.HALF_WIDTH + 10.0
# Fahrzeuge der Karriere. grip/power wirken in der Reifen- bzw. Antriebsphysik, offroad teilt die Strafen
# neben der Fahrbahn (2 = halbe Strafe), turbo skaliert Laden und Verbrauchsdauer. unlock = benötigtes Gold.
# rear = Anteil der Haftung an der Hinterachse (Standard 0,47), drive = Antriebsart ("awd" Standard, "rwd" Heckantrieb).
const CARS := [
	{"id":"sprint","name":"Sprint","grip":12.0,"power":9.0,"offroad":1.0,"turbo":1.0,"color":"f16c4c","style":"coupe","unlock":0,"text":"Leicht & schnell – der Allrounder."},
	{"id":"grip","name":"Grip","grip":13.8,"power":7.8,"offroad":1.0,"turbo":1.0,"color":"5ac4d1","style":"hatch","unlock":1,"text":"Mehr Haftung, sanfterer Antrieb."},
	{"id":"rally","name":"Dirt Hawk","grip":12.6,"power":9.4,"offroad":2.2,"turbo":1.0,"color":"e8c866","style":"rally","unlock":3,"text":"Rallye: kaum Tempoverlust neben der Straße."},
	{"id":"muscle","name":"Thunder V8","grip":11.4,"power":11.2,"offroad":0.9,"turbo":0.85,"color":"a593cf","style":"muscle","unlock":6,"text":"Brachiale Kraft, braucht Gefühl in Kurven."},
	{"id":"gt","name":"Apex GT","grip":14.2,"power":10.6,"offroad":0.9,"turbo":1.3,"color":"ececec","style":"gt","unlock":9,"text":"Die Spitze: Haftung, Kraft, starker Turbo."},
	{"id":"roadster","name":"Col Racer","grip":14.6,"power":9.6,"offroad":1.1,"turbo":1.1,"color":"2e86c1","style":"roadster","unlock":12,"text":"Leicht und wendig – gemacht für Kehren."},
	{"id":"pickup","name":"Quarry Truck","grip":12.4,"power":10.4,"offroad":2.6,"turbo":0.9,"color":"7d8c4a","style":"pickup","unlock":15,"text":"Unverwüstlich auf Schotter und Matsch."},
	{"id":"drift","name":"Drift King","grip":13.0,"power":10.8,"offroad":0.9,"turbo":1.0,"rear":0.42,"drive":"rwd","color":"d35400","style":"drift","unlock":18,"text":"Heckantrieb: Gas in der Kurve, und das Heck kommt – für Drift-Punkte."},
]
var pos := Vector2.ZERO
var velocity := Vector2.ZERO
var heading := 0.0
var yaw := 0.0
var steering := 0.0
var turbo := 0.35
var boosting := false
var braking := 0.0
var slip := 0.0
# Nur für den Motorklang ausgelesen (0 = Schub, 1 = Vollgas); beeinflusst die Simulation nicht.
var throttle := 0.0
# Seitlicher Ausweichversatz des Zielpunkts; setzt main.gd nur für Gegner.
var avoid_offset := 0.0
var progress := 0.0
var previous_phase := 0.0
var finish_time := -1.0
var cursor := 0
var grip := 12.0
var power := 9.0
var offroad := 1.0
var turbo_factor := 1.0
var route: Array[Dictionary] = []
var track: Circuit
var max_slip := 0.0
var rear_share := 0.47     # Anteil der Haftung an der Hinterachse (Drift-Auto: weniger)
# Antriebsart (CARS "drive"): "awd" (Standard) überträgt jede Längskraft und kürzt damit nur die Seitenführung beider Achsen (52/48);
# "rwd" (Heckantrieb) schickt den Vortrieb allein über den Reibkreis der Hinterachse. Im Drift-Modus treiben die Allrad-Autos hecklastig an
# (DRIFT_AWD_REAR).
var rear_drive := false
# Antrieb, den die Hinterräder nicht auf die Straße bringen (m/s², >= 0, d. h. sie drehen durch). Nur für Reifenqualm, Spuren und Klang
# ausgelesen; beeinflusst die Simulation nicht. 0 in der Luft, im Looping, nach Ziel und Wrack. Beim Allrad-Grundmodell (Rennmodus) immer 0:
# Das ist eine Modellgrenze (es überträgt jede Längskraft und kürzt dafür nur die Seitenführung, Durchdrehen kennt es nicht).
var rear_spin := 0.0
const SLIP_FADE_SPEED := 1.0   # m/s Achsgeschwindigkeit, ab der die Seitenkraft voll aufgebaut ist
# --- Drift-Wertung (nur im Drift-Modus ausgewertet; beeinflusst die Fahrt nicht) ---
var drift_score := 0.0
var drift_multiplier := 1.0
var drift_time := 0.0      # Dauer des aktuellen Drifts
var drift_angle := 0.0     # aktueller Driftwinkel (Grad)
var drift_chain := 0.0     # Punkte des laufenden Drifts (Kette): weg bei Wandberührung oder Dreher (score_drift)
var chain_lost := 0        # verlorene Ketten (Anzeige im Ergebnis)
const DRIFT_SPIN := PI * 0.5   # rad quer: Dreher, die Kette ist weg
var wall_hits := 0
var wall_contact := false
# Drift-Modus: Ausbrechen ist gewollt. Seit 15.10.2026 fährt dort ein Profi-Drifter (drift_driver; der Rennmodus bleibt unberührt). Der
# Fahrer vom 03.10. (Pure Pursuit auf die Nase, Gas nach dem Plantempo) lenkte die Nase statt des Kurses und hielt das Tempo statt des
# Winkels: Mit der vorzeichenrichtigen Physik (bicycle-7) driftete der Drift King erst bei grob überzeichneten Kurven (×1,45: 0 Punkte,
# ×1,7: 1500), andere Autos fast gar nicht. Der Profi
# - führt den Kurs (Geschwindigkeitsvektor) zur Linie, nicht die Nase: Die Vorderräder zeigen in die Bewegungsrichtung der Vorderachse
#   (im Drift ist das Gegenlenken), dazu der Schräglauf für Kurs und Gierrate;
# - liest die gezeichnete Linie: Überschuss Plantempo² · Krümmung / Bezugshaftung, ab DRIFT_E_ON verlangt die Kurve einen Driftwinkel,
#   je schneller gezeichnet, desto mehr (die Tempofarbe bleibt der Plan); er stellt das Auto DRIFT_T_INIT s vor der Kurve an;
# - hält den Winkel mit dem Gas (Heckantrieb: Gas lässt das Heck kommen, Lupfen lässt es greifen), aber nie über das Plantempo hinaus;
# - fängt vor Nadelöhren ab (dort kein Anstellen), setzt zurück, wenn er verloren steht (drift_reverse, wie beim Freifahren; danach erst
#   vorwärts, DRIFT_REV_HOLD), kehrt abseits der Fahrbahn wie im Rennmodus zurück (race_driver) und fährt nach dem Hängen um die Ecke des
#   Hindernisses herum (drift_detour); ohne Fortschritt über DRIFT_STALL_TIME ist das Auto festgefahren (Wrack).
# Verlangt die Linie mehr Winkel, als sich halten lässt, dreht sich das Auto; zu schnell in die Kurve trägt es nach außen. Beides kostet
# Punkte: Dreher und Wand nehmen die Kette des laufenden Drifts (score_drift).
const DRIFT_LOST_ERROR := 2.0     # rad: Ziel seitlich hinter dem Auto (gedreht)
const DRIFT_LOST_EDGE := 1.0      # m jenseits des Fahrbahnrands (dort ist der Drift ohnehin schon als Wandberührung bestraft)
const DRIFT_TURN_SPEED := 3.0     # m/s Kriechtempo, solange ein verlorenes Auto sich zum Ziel umdreht
const DRIFT_LOST_COURSE := 1.2    # rad: gedreht ist das Auto erst, wenn auch der Kurs vom Ziel weg zeigt (im Drift steht die Nase quer)
const DRIFT_REV_SPEED := 1.5      # m/s: verloren und fast stehend -> zurücksetzen (drift_reverse) statt im Kreis zu kriechen
const DRIFT_LOCK := 0.85          # rad Lenkeinschlag des Profis (Grundfahrer 0,62): Gegenlenken bis 49°
const DRIFT_STEER_RATE := 5.0     # rad/s, er fängt schnell ab (Grundfahrer 2,6)
const DRIFT_KP := 0.9             # Schräglauf vorn (rad) je rad Kursfehler
const DRIFT_KR := 0.4             # je rad/s Gierfehler (dreht die Nase schneller als der Kurs, wird gegengelenkt)
const DRIFT_KBU := 0.4            # je rad fehlender Driftwinkel: Anstellen vor und in der Kurve
const DRIFT_GEO0 := 4.0           # m/s: darunter lenkt er geometrisch (Pure Pursuit) – Schräglaufbefehle wirken im Schritttempo nicht …
const DRIFT_GEO1 := 8.0           # … ab hier ganz nach Schräglauf
const DRIFT_REF_GRIP := 13.0      # m/s² Bezugshaftung, an der er die Linie liest (Drift King trocken): gleiche Linie, gleicher Plan – für
                                  #   jedes Auto und jedes Wetter; was das Auto daraus macht, entscheidet seine Physik (Regen: weniger Haftung).
                                  #   Auf anderem Belag skaliert mit dessen Haftung allein (SURFACE_GRIP), ohne die Geländegängigkeit des Autos
const DRIFT_E_ON := 0.75          # Überschuss der Linie, ab dem quer gefahren wird (KI-Linie ai_route(1,5) liegt bei 0,65)
const DRIFT_GAIN := 45.0 * PI / 180.0       # Zielwinkel je Einheit Überschuss …
const DRIFT_BETA_MAX := 60.0 * PI / 180.0   # … höchstens
const DRIFT_BETA_HARD := 55.0 * PI / 180.0  # darüber Gas weg …
const DRIFT_BETA_OVER := 15.0 * PI / 180.0  # … bzw. erst so weit über dem Zielwinkel: Verlangt die Linie viel Winkel, hält er drauf und dreht sich
const DRIFT_THR0 := 0.4           # Gas (Anteil) bei erreichtem Zielwinkel …
const DRIFT_THR_GAIN := 3.0       # … je rad fehlendem Winkel mehr
const DRIFT_COAST := 1.25         # m/s über dem Plantempo rollt er im Drift, erst darüber bremst er
const DRIFT_CATCH := 10.0 * PI / 180.0      # quer ohne Driftwunsch (Kurvenausgang, vor dem Nadelöhr): nur den Fahrwiderstand halten, das Heck greift
const DRIFT_LOOK := 20.0          # m, so weit voraus liest er die Linie höchstens
const DRIFT_T_INIT := 0.6         # s vor einer Kurve beginnt das Anstellen (voll), …
const DRIFT_RAMP := 8.0           # … davor auf so vielen Metern eingeblendet
const DRIFT_NARROW := 4.0         # m halbe Breite: darunter Nadelöhr …
const DRIFT_T_CATCH := 0.7        # … so viele s davor fängt er ab, und hinter ihm angestellt wird erst …
const DRIFT_EXIT := 3.0           # … so viele m vor dem Ausgang
const DRIFT_DETOUR := 1.2         # m Abstand der Umwegpunkte von den Ecken des Hindernisses (zusätzlich zu CAR_RADIUS; drift_detour) …
const DRIFT_DETOUR_AIM := 8.0     # … Ziel des Umwegs: so weit voraus auf der Linie …
const DRIFT_DETOUR_SPEED := 5.0   # … gefahren mit so viel m/s, …
const DRIFT_DETOUR_TIME := 6.0    # … je Umwegpunkt höchstens so viele s, …
const DRIFT_DETOUR_HOPS := 3      # … und über höchstens so viele Ecken
const DRIFT_REV_HOLD := 1.0       # s bzw. …
const DRIFT_REV_HOLD_WAY := 1.0   # … m vorwärts nach jeder Rückwärtsfahrt, bevor der Fahrer erneut zurücksetzt
const DRIFT_STALL_TIME := 15.0    # s ohne FREE_NET m Nettofortschritt: festgefahren, Wrack (das Zeitlimit liegt bei 55 s)
var detour_on := false            # Umweg begonnen (drift_detour)
var detour_point := Vector2.ZERO  # angefahrene Ecke
var detour_index := -1            # Hindernis, um das der Umweg führt
var detour_hops := 0
var detour_clock := 0.0
var detour_tries := 0             # Versuche des Freifahrens beim Beginn des Umwegs (einer mehr: erneut gehangen)
var detour_backs := 0             # Rückwärtszüge dieses Umwegs
var detour_back := false          # Umweg: rückwärts wenden
var detour_from := Vector2.ZERO
var detour_back_time := 0.0
var drift_back := false           # verloren: zurücksetzen (drift_reverse)
var drift_back_time := 0.0
var drift_back_from := Vector2.ZERO
var drift_hold := 0.0             # s Sperre gegen erneutes Zurücksetzen (DRIFT_REV_HOLD) …
var drift_hold_from := Vector2.ZERO
var drift_mark := 0.0             # Fortschritt bei den letzten FREE_NET m (Stillstandswache) …
var drift_stall := 0.0            # … und die Zeit seither
var drift_goal := 0.0             # Zielwinkel des Profis (rad), nur Auswertung
# Antrieb der Allrad-Autos im Drift-Modus: hecklastig, DRIFT_AWD_REAR des Antriebs hinten, je Achse durch ihren Reibkreis (wie der Drift-Modus
# realer Allrad-Sportwagen, die 70–100 % nach hinten schicken). Mit dem Allrad-Grundmodell lässt sich kein Drift halten, gleich mit welchem
# Fahrer: Ist das Heck am Reibkreis (ab ~8° Schwimmwinkel), muss die Vorderachse das Giermoment halten, 1,1 · F_vorn ≥ 1,2 · F_hinten +
# Gierdämpfung (1,9 · 0,55 · Gierrate). Die Haftung vorn reicht dafür nicht (Sprint: 1,1 · 6,36 = 7,0 gegen 1,2 · 5,64 + 1,05 = 7,8 bei
# 1 rad/s), und Gas kürzt beide Achsen gleich – das Auto richtet sich auf und schiebt nach außen (gemessen: Sprint, Thunder V8 und Apex GT
# 0–600 Punkte, 3–19 m außen). Hecklastig kürzt das Gas vor allem hinten die Seitenführung, und der Drift lässt sich halten. Der Drift King
# (reiner Heckantrieb, Haftung hinten 0,42 statt 0,47) bleibt der williger driftende; mit reinem Heckantrieb für alle (1,0) driftete der
# Thunder V8 (Antrieb 11,2 bei Haftung 11,4) fast gleich gut.
const DRIFT_AWD_REAR := 0.85
var recovering := false    # Rückkehr (Rennmodus) bzw. Erholungsdeckel (Drift-Modus) gerade wirksam (nur Auswertung)
# --- Rückkehr auf die Linie im Rennmodus (15.10.2026, ersetzt den 7-m/s-Schalter) ---
# Bis dahin galt ab 3 m Abstand zum Fortschrittspunkt oder 0,85 rad Zielabweichung hart 7 m/s, darunter sofort wieder das volle Plantempo:
# Das Auto bremste mit 12 m/s² (in der Kurve kam dabei das Heck), gab erst direkt auf der Linie wieder Gas und schwang 0,6 m über die Linie
# hinaus (Pure Pursuit mit festem Vorausblick ist unterdämpft). Jetzt beginnt jenseits der normalen Abweichung der Linienfolge eine
# Rückkehr-Episode: Die Richtung kommt von einem fernen Punkt der Linie (mindestens REC_DAMP · Vorausblick voraus; Richtung aus der Ferne,
# Krümmung aus dem nahen Abstand ist aperiodisch gedämpft, ζ ≈ √(REC_DAMP/2)), steiler zurück auf den Belag und dann flach, höchstens bis zum
# nächsten Kurveneingang und bis vor die nächste Einfahrt (Looping, Schanze, Absprungkante, Wippen-Deck). Das Tempo nähert sich stetig dem
# Plan, je näher und je besser ausgerichtet das Auto ist; begrenzt nur durch den Bogen, den es dafür fahren muss (Querhaftung bei Wetter und
# Untergrund), nie unter REC_SPEED; das Gas ebenso im Reibkreis. Steht das Auto quer zur Linie, wirkt das alles sofort und mit vollem Einschlag.
# Die Episode endet erst auf der Linie und längs ihrer Richtung. Darunter folgt der Regler wie bisher.
const REC_START := 2.2          # m Querabstand (trocken): normale Linienfolge gemessen bis 1,9 m (Thunder V8, Stadt), Ausflüge darüber
const REC_START_WET := 1.5      # m mehr je fehlender Haftung des Wetters (nass +0,23, Schnee +0,45 m: dort schneidet und rutscht die KI weiter)
const REC_HEAD := 0.85          # rad Kurs gegen die Linienrichtung oder Abweichung zum nahen Zielpunkt: Episode beginnt auch so (gedreht,
const REC_HEAD_OFF := 1.0       # m  quer, Nase von der Linie weg; schiebt über die Vorderräder) – Letzteres erst so weit neben der Linie
                                #    (in einer engen Kehre auf der Linie liegt der Zielpunkt ebenso weit seitlich)
const REC_END := 0.6            # m: Episode endet nahe der Linie mit dem Kurs längs ihrer lokalen Richtung …
const REC_END_COURSE := 0.15    # rad
const REC_END_BAND := 1.0       # m … oder nach REC_SETTLE in diesem Band (wellige Linien und Kurven: dort pendelt der Kurs um die Linie,
const REC_SETTLE := 0.4         # s  und das Kurvenschneiden der normalen Linienfolge reicht über REC_END hinaus)
const REC_FADE := 4.0           # 1/s Ein- und Ausblenden der Episode (kein Sprung in Zielpunkt und Tempo); über den Kurs begonnen: sofort
const REC_DAMP := 2.0           # ferner Zielpunkt mindestens REC_DAMP · Vorausblick voraus
const REC_ANGLE_ROAD := 0.30    # rad Annäherungswinkel an die Linie auf dem Belag …
const REC_ANGLE_OFF := 0.75     # rad … und abseits davon (erst steil zurück auf die Straße)
const REC_OFF_MARGIN := 0.6     # m innerhalb des Fahrbahnrands zählt schon als abseits
const REC_TURN := 0.45          # rad: ferner Zielpunkt höchstens bis zum Kurveneingang (Linie um so viel gedreht) …
const REC_ENTRY_SHARE := 0.5    # … und höchstens bis zur Hälfte des Wegs zur nächsten Einfahrt (die andere Hälfte zum Ausrichten)
const REC_SPEED := 7.0          # m/s Untergrenze des Rückkehrtempos
const REC_ARC_GRIP := 0.9       # Anteil der Querhaftung für den Bogen zurück und das Ausrichten auf die Linie
const REC_ALIGN_MIN := 1.0      # m kleinster Querweg zum Ausrichten
const REC_LAG := 0.25           # s bis Lenkung und Gierrate zum Zurückdrehen stehen (Querweg, der dabei verloren geht)
const REC_STEER_USE0 := 0.3     # Anteil der Querhaftung, den das Ausrichten verlangt: ab hier lenkt der Fahrer dafür schon weg …
const REC_STEER_USE1 := 0.6     # … und ab hier mit dem ganzen verlangten Bogen
# Die Episode misst gegen die geglättete Linie (Ausgleichsgerade über ± REC_SMOOTH · Vorausblick, smooth_line): Eine wellig gezeichnete
# Linie (±1,6 m, Wellenlänge 12–25 m) schneidet die normale Linienfolge wie ein Tiefpass, das ist kein Ausflug. Gegen die rohe Linie begann
# dort im Sekundentakt eine Episode, und das Ausrichten gegen die pendelnde Linienrichtung bremste jedes Mal (Azure +43 %, Gegenprüfung).
const REC_SMOOTH := 1.0
# Anlauf einer Schwungzone (Looping, Schanze, Absprungkante; nicht das Lineal): Dort geht Tempo vor Querlage – der Looping nimmt Querversatz bis
# zum Fahrbahnrand, aber nicht 2 m/s zu wenig. Ab REC_RUNUP_FAR m vor der Einfahrt blendet der Rückkehrdeckel aus, ab REC_RUNUP_NEAR m drückt
# die Episode das Tempo nicht mehr unter den Plan und kürzt das Gas nicht, auf einer Schanze bis zur Kante ebenso (vorher stürzte das Auto 15–30 m
# vor dem Looping gestartet mit 12–15 statt 15–16 m/s ab).
const REC_RUNUP_NEAR := 30.0
const REC_RUNUP_FAR := 50.0
# Nach einer Landung beginnt eine Episode erst REC_LAND_EXTRA m weiter draußen (bis REC_LAND_TIME s nach dem Aufsetzen, dann ausblendend): Im Flug
# fährt das Auto geradeaus, während die Linie weiterlaufen kann, und nach dem Aufsetzen baut sich die Haftung erst auf (LANDING_TIME). So liegt es
# kurz 2–3 m neben der Linie, ohne auszubrechen; die normale Linienfolge holt das ein (Jahrmarkt, Landung hinter der Lücke in der Kurve: mit
# Episode bremste sie im Reibkreis und kostete jeden Goldlauf 0,1–0,4 s).
const REC_LAND_EXTRA := 1.0
const REC_LAND_TIME := 1.0
var rec_episode := false
var rec_fade := 0.0
var rec_settle := 0.0
var land_clock := 9.0           # s seit dem letzten Flug
var line_offset := 0.0          # m Querabstand zur eigenen Linie (links positiv), nur im Rennmodus gemessen
var line_course := 0.0          # rad Kurs gegen die lokale Linienrichtung
var line_dir := Vector2.RIGHT
var line_index := 0             # nächster Linienpunkt (lokale Suche ab dem Vortakt)
var rec_offset := 0.0           # m Querabstand zur geglätteten Linie (Episode; außerhalb gleich line_offset)
var rec_course := 0.0           # rad Kurs gegen ihre Richtung
# Bremsdosierung (Rennmodus): Bremsen ist im Modell nicht durch die Haftung begrenzt, kürzt aber die Seitenführung beider Achsen (bis auf
# 1 m/s²); an der Haftungsgrenze reicht sie hinten zuerst nicht mehr, und das Heck kommt. Der Fahrer bremst deshalb wie mit einer
# Stabilitätskontrolle: Rutscht das Auto schon quer (Schwimmwinkel über BRAKE_SLIDE0), nimmt er die Bremse bis auf BRAKE_FLOOR zurück – vorher
# drehte eine Vollbremsung in der schnellen Kurve das Auto von 12° auf 26° quer. Schiebt es dagegen geradeaus über die Vorderräder (zu schnell
# für den Bogen, kaum Schwimmwinkel), bremst er voll: Tempo abbauen ist dann der einzige Weg in die Kurve (Steinbruch-Kehre: mit gedrosselter
# Bremse rutschte das Auto bis an die Absperrung).
# In der Rückkehr-Episode zudem nach dem Reibkreis: Passt der Bogen zurück bei diesem Tempo in die Haftung, bremst der Fahrer nur so stark,
# dass Längs- und Querbedarf zusammen hineinpassen (er braucht die Seitenführung zum Zurücklenken); ist das Auto für den Bogen deutlich zu
# schnell, bremst er voll.
const BRAKE_FLOOR := 2.0        # m/s²: so stark bremst der Fahrer immer
const BRAKE_SLIDE0 := 0.07      # rad Schwimmwinkel (4°), ab dem die Bremse zurückgeht …
const BRAKE_SLIDE1 := 0.17      # … und bei dem (10°) nur noch BRAKE_FLOOR bleibt
const BRAKE_OVER := 1.5         # Querbedarf / Haftung, ab dem in der Episode voll gebremst wird (bei 1 nach dem Reibkreis)
var brake_room := 12.0          # m/s² Bremse, die der Fahrer in diesem Takt zulässt (Episode)
# Gas in der Episode ebenso nach dem Reibkreis: Längszug kürzt die Seitenführung, die das Auto zum Zurücklenken braucht. Vorher gab der Fahrer
# neben der Fahrbahn Vollgas, während der Kurs noch von der Linie weg zeigte, und rutschte in die Randpfosten (Serra, zu schnell gezeichnet).
var drive_room := 99.0          # m/s² Antrieb, den der Fahrer in diesem Takt zulässt (Episode)
const REC_AWAY := 0.15          # rad Kurs von der Linie weg, ab dem der Fahrer in der Episode nur noch das Tempo hält
# --- Höhe und Flug (2,5D, Leitplanke 8) ---
const GRAVITY := 9.81
const LANDING_TIME := 0.35
var z := 0.0              # Höhe über Null (m)
var vz := 0.0             # senkrechte Geschwindigkeit (m/s)
var airborne := false
var landing := 0.0        # Restzeit, in der die Haftung nach der Landung wieder aufgebaut wird
var crashed := false      # abgestürzt (Lücke zu kurz übersprungen, Looping zu langsam, Abgrund)
var air_time := 0.0       # Summe der Flugzeit (für Tests/Anzeige)
var in_loop := false
var loop_theta := 0.0     # Winkel im Looping (0 unten, PI oben)
var loop_speed := 0.0
var loop_radius := 0.0
var loop_origin := Vector2.ZERO    # Punkt der Mittellinie auf Höhe der Einfahrt
var loop_forward := Vector2.RIGHT
var loop_entry := 0.0              # seitlicher Versatz bei der Einfahrt
var loop_fall := false             # im Looping abgestürzt (jenseits der Senkrechten ohne Anpresskraft)
var rolled_back := false           # im Looping vor der Senkrechten stehen geblieben und zurückgerollt
var seesaws: Array = []            # Wippen dieses Rennens (RaceField; der Geist hat eigene)
var loop_entered_at := -9.0        # Fortschritt bei der letzten Looping-Einfahrt

func _init(circuit: Circuit, plan: Array[Dictionary], start_s := 0.0, lane := 0.0, car := 0) -> void:
	track = circuit
	route = plan
	pos = track.at(start_s, lane)
	heading = track.tangent(start_s).angle()
	progress = start_s
	previous_phase = track.phase_near(pos, start_s)
	z = track.ground_height(previous_phase)
	var spec: Dictionary = CARS[clampi(car, 0, CARS.size() - 1)]
	grip = float(spec.grip)
	power = float(spec.power)
	offroad = float(spec.offroad)
	turbo_factor = float(spec.turbo)
	rear_share = float(spec.get("rear", 0.47))
	rear_drive = str(spec.get("drive", "awd")) == "rwd"

func step(dt: float, boost: bool, time: float) -> void:
	rear_spin = 0.0
	if finish_time >= 0.0 or crashed:
		return
	if in_loop:
		step_loop(dt)
		return
	var before := progress
	var before_pos := pos
	# Sprintstrecke: Startplatz hinter der Linie (RaceField). Davor kein Rand-/Inselcheck und keine Rückkehr auf die Linie.
	var behind_line := track.open and progress < 0.0
	# Only search forward through a bounded part of the drawn route.
	while cursor < route.size() - 2 and float(route[cursor + 1].s) <= maxf(progress, 0.0):
		cursor += 1
	var drift_mode := track.mode == "drift"
	# Untergrund: Erde/Matsch bremsen über Rollwiderstand und mindern die Haftung (Leitplanke 3). Auch der Fahrer richtet sich danach.
	var ground := str(track.surface_at(pos, previous_phase).kind)
	var surface_grip: float = (1.0 - (1.0 - float(SURFACE_GRIP.get(ground, 1.0))) / offroad) * weather_grip
	# Fahrer: Lenkung (setzt steering) und Wunschtempo; < 0 = zurücksetzen.
	var ground_drag: float = float(SURFACE_DRAG.get(ground, 0.0)) / offroad
	var desired_speed: float
	brake_room = 12.0
	drive_room = power
	near_q = edge_q
	edge_q = {}
	if reversing:
		desired_speed = free_driver(dt)
	elif drift_mode:
		desired_speed = drift_driver(dt, behind_line)
	else:
		desired_speed = race_driver(dt, behind_line, surface_grip, ground_drag)
	var forward := Vector2.from_angle(heading)
	# Querachse "links" = Richtung positiver Gierrate und positiven Lenkwinkels (heading wächst zu from_angle(heading + PI/2)).
	# Bis bicycle-6 stand hier forward.orthogonal(), das zeigt nach rechts, während Schräglauf (v ± Hebel·Gier), Kraftrichtung und
	# Giermoment mit links rechneten. Folgen: Beim Einlenken drückte die Vorderachse erst nach außen, jede Kurve lief mit Schein-Drift
	# (Nase 11–15° innen), und ein ausbrechendes Heck ließ das Auto untersteuern statt eindrehen (gemessen 15.10.2026).
	var left := -forward.orthogonal()
	var u := velocity.dot(forward)
	var v := velocity.dot(left)
	var ground_grip := surface_grip
	if landing > 0.0:
		# Nach der Landung baut sich die Haftung erst wieder auf.
		ground_grip *= lerpf(1.0, 0.3, landing / LANDING_TIME)
		landing = maxf(0.0, landing - dt)
	# Woran der Fahrer das Plantempo misst: im Rennen am Längstempo, im Drift-Modus am Fahrtempo. Quer rutschend sinkt das Längstempo
	# (u = v·cos Driftwinkel); gemessen daran gab der Fahrer im Drift Vollgas über den Plan hinaus und schob das Auto aus der Kurve.
	var pace := signf(u) * velocity.length() if drift_mode else u
	var drive := pedals(desired_speed, pace, u, not drift_mode)
	# Kein Turbo beim Zurücksetzen. Im Drift-Modus setzt der Profi auch über drift_reverse und den Umweg rückwärts zurück (ohne reversing):
	# Mit gehaltenem Turbo schob +8,5 m/s² das Auto dort sonst wieder vorwärts, es pendelte um u ≈ 0 und verbrannte den Turbo.
	boosting = boost and turbo > 0.005 and braking < 0.5 and not reversing and not (drift_mode and desired_speed < 0.0)
	throttle = absf(drive) / power
	if boosting:
		drive += 8.5
		throttle = 1.0
		turbo = maxf(0.0, turbo - dt * 0.30 / turbo_factor)
	elif braking > 0.2 and u > 3.0:
		# Regeneration is proportional to energy actually removed, never time alone.
		turbo = minf(1.0, turbo + braking * u * dt * 0.00065 * turbo_factor)
	# Die Bremse wirkt gegen die Bewegung (auch rückwärts) und kehrt sie in einem Takt höchstens bis zum Stillstand um.
	var brake_force := signf(u) * minf(braking, absf(u) / dt)
	var longitudinal := drive - brake_force - 0.010 * u * absf(u) - u * (0.09 + ground_drag)
	# Radkraft (Heckantrieb: durch den Reibkreis). Die Fahrwiderstände bilden mit der festen Antriebsgrenze power die Leistungskurve nach (echter
	# Luftwiderstand wäre bei 20 m/s rund zehnmal kleiner) und zählen deshalb wie ein Triebstrangverlust zur Radkraft, ebenso der Rollwiderstand
	# des Untergrunds (eine Spielstrafe, als Kraft am Wagen ließe sie den Heckantrieb im Schnee auf Schotter bei 15 m/s verhungern). Der
	# Hangabtrieb greift dagegen am Wagen an: Bergauf drehen die Räder so eher durch, bergab wird die Schwerkraft nicht vom Reibkreis gekappt.
	var wheel := longitudinal
	var slope := 0.0           # Hangabtrieb (m/s², bergauf positiv)
	if not airborne:
		# Steigung/Gefälle (2,5D): Hangabtrieb entlang der Fahrtrichtung. Auf dem Wippendeck aus dessen Neigung, auf einer
		# Abkürzung aus dem Gelände bei pos ± 1 m, sonst aus der Fahrbahn der Hauptstrecke.
		var grade: float
		if deck != null:
			grade = sin(deck.phi) * forward.dot(deck.u)
		elif on_shortcut:
			grade = (track.terrain_height(pos + forward * signf(u)) - track.terrain_height(pos)) * signf(u)
		else:
			var ahead_s := previous_phase + signf(u) * 1.0 / track.length
			grade = (track.ground_height(ahead_s) - track.ground_height(previous_phase)) * signf(u)
		if absf(grade) < 2.0:
			slope = GRAVITY * grade / sqrt(1.0 + grade * grade)
			longitudinal -= slope
	# Schräglauf der Achsen (Schwerpunkt 1,1 m hinter der Vorder-, 1,2 m vor der Hinterachse); Seitenkraft wirkt entgegen dem Schräglauf.
	# Rückwärts rollend kehrt sich die Wirkung des Lenkwinkels um (Quergeschwindigkeit im Radbezug ≈ v − u·δ): nach links gelenkt dreht
	# das Heck nach links, die Nase nach rechts.
	var alpha_front := atan2(v + yaw * 1.1, absf(u) + 1.8) - (steering if u >= 0.0 else -steering)
	var alpha_rear := atan2(v - yaw * 1.2, absf(u) + 1.8)
	# Unter SLIP_FADE_SPEED Achsgeschwindigkeit baut der Reifen keine Seitenkraft auf (er rollt nicht und rutscht nicht): Sonst erzeugte
	# allein der Lenkeinschlag über "− steering" eine Kraft, und ein stehendes Auto drehte sich auf der Stelle (gemessen 59° in 2 s).
	alpha_front *= clampf(Vector2(u, v + yaw * 1.1).length() / SLIP_FADE_SPEED, 0.0, 1.0)
	alpha_rear *= clampf(Vector2(u, v - yaw * 1.2).length() / SLIP_FADE_SPEED, 0.0, 1.0)
	var front_grip := grip * ground_grip * (1.0 - rear_share)
	var rear_grip := grip * ground_grip * rear_share
	var front_force: float
	var rear_force: float
	if rear_drive and wheel > 0.0:
		# Heckantrieb unter Zug: Die Radkraft läuft allein über den Reibkreis der Hinterachse (Traktionsgrenze). Was er nicht überträgt,
		# lässt die Räder durchdrehen (rear_spin) und fehlt dem Vortrieb; zugleich bleibt hinten weniger Seitenführung – Gas in der Kurve
		# lässt das Heck kommen (Leistungsübersteuern). Die Vorderräder rollen frei und führen mit voller Haftung.
		front_force = clampf(-alpha_front * 36.0, -front_grip, front_grip)
		var rear := friction_circle(wheel, -alpha_rear * 40.0, rear_grip)
		rear_force = rear.y
		rear_spin = maxf(0.0, wheel - rear.x)
		longitudinal = rear.x - slope
	elif drift_mode and wheel > 0.0:
		# Allrad im Drift-Modus (DRIFT_AWD_REAR; nur dort, der Rennmodus bleibt bitgleich): Der Antrieb ist hecklastig verteilt und läuft je Achse
		# durch ihren Reibkreis wie beim Heckantrieb – Gas lässt das Heck kommen, die Vorderachse zieht mit und behält weniger Seitenführung.
		var rear_part := wheel * DRIFT_AWD_REAR
		var front := friction_circle(wheel - rear_part, -alpha_front * 36.0, front_grip)
		var rear := friction_circle(rear_part, -alpha_rear * 40.0, rear_grip)
		front_force = front.y
		rear_force = rear.y
		rear_spin = maxf(0.0, rear_part - rear.x)
		longitudinal = front.x + rear.x - slope
	else:
		# Allrad (Grundmodell), beim Heckantrieb Bremsen und Rollen: Längskraft 52/48 auf die Achsen; sie wird voll übertragen und kürzt
		# die Seitenführung (Modellgrenze: Bremsen ist nicht durch die Haftung begrenzt, die Seitenführung fällt bis auf 1 m/s²).
		var front_capacity := sqrt(maxf(1.0, pow(front_grip, 2) - pow(longitudinal * 0.52, 2)))
		var rear_capacity := sqrt(maxf(1.0, pow(rear_grip, 2) - pow(longitudinal * 0.48, 2)))
		front_force = clampf(-alpha_front * 36.0, -front_capacity, front_capacity)
		rear_force = clampf(-alpha_rear * 40.0, -rear_capacity, rear_capacity)
	if airborne:
		# In der Luft: keine Reifenkräfte (kein Grip, keine Lenkung, kein Antrieb/Bremsen), nur Luftwiderstand.
		front_force = 0.0
		rear_force = 0.0
		longitudinal = -0.010 * u * absf(u)
		braking = 0.0
		boosting = false
		rear_spin = 0.0
	# Giermoment: Seitenkraft vorn dreht zur Kraftrichtung, hinten dagegen (Trägheit 1,9 m², dazu Dämpfung 0,55/s).
	yaw += ((front_force * 1.1 - rear_force * 1.2) / 1.9 - yaw * 0.55) * dt
	yaw = clampf(yaw, -3.0, 3.0)
	velocity += (forward * longitudinal + left * (front_force + rear_force)) * dt
	heading += yaw * dt
	pos += velocity * dt
	slip = maxf(absf(alpha_front), absf(alpha_rear))
	max_slip = maxf(max_slip, slip)
	# Harte Grenze erst am Inselrand; davor entscheidet der Untergrund.
	if not behind_line and track.center_distance(pos, previous_phase) > ISLAND_LIMIT + track.hw(previous_phase) - Circuit.HALF_WIDTH:
		var q := track.query_branch(pos, previous_phase)
		var normal: Vector2 = (pos - q.point).normalized()
		pos = q.point + normal * (ISLAND_LIMIT + track.hw(previous_phase) - Circuit.HALF_WIDTH)
		var outward := velocity.dot(normal)
		if outward > 0.0:
			velocity -= normal * outward * 1.35
		velocity *= 0.84
	touched = false
	touch_rear = false
	touch_front = false
	if not seesaws.is_empty():
		seesaw_contact(before_pos)
	collide_obstacles(dt)
	if track.mode == "drift":
		score_drift(dt)
	if behind_line:
		# Vor der Startlinie: Fortschritt = −Abstand zur Linie entlang der Starttangente.
		var along := (pos - track.at(0.0)).dot(track.tangent(0.0))
		if along < 0.0:
			progress = along / track.length
			update_height(0.0, dt)
			previous_phase = 0.0
			return
		progress = 0.0
		previous_phase = 0.0
	var ph := line_phase()
	var ds := wrapf(ph - previous_phase, -0.5, 0.5)
	if absf(ds) < 0.08:
		progress += ds
	on_shortcut = not track.shortcut_here(pos, ph).is_empty() if not track.shortcuts.is_empty() else false
	update_height(ph, dt)
	if crashed:
		rear_spin = 0.0    # Absturz an Kante, Lippe oder Abgrund in diesem Takt
	if not airborne and not crashed:
		var loop := track.loop_between(previous_phase, ph)
		# Nach der Ausfahrt liegt das Auto wieder an der Einfahrtsstelle: dieselbe Einfahrt erst nach 3 m erneut zählen
		# (sonst projiziert die Ausfahrtsspur gelegentlich knapp davor und das Auto fährt den Looping zweimal).
		if not loop.is_empty() and absf(progress - loop_entered_at) * track.length > 3.0:
			loop_entered_at = progress
			enter_loop(loop)
	if not crashed and not in_loop:
		update_hang(dt)
	previous_phase = ph
	var goal := float(track.laps)
	if before < goal and progress >= goal:
		finish_time = time - dt + dt * clampf((goal - before) / maxf(0.00001, progress - before), 0.0, 1.0)
		rear_spin = 0.0    # im Ziel wird nicht mehr gerechnet (sonst qualmte das Auto mit dem letzten Wert weiter)

# ---------- Fahrer ----------
func aim(lo: float, hi: float) -> Vector2:
	# Zielpunkt (Pure Pursuit) = Mittel der Linienpunkte lo … hi Meter voraus (entlang der Linie ab dem Fortschrittscursor). Das filtert
	# Zacken der gezeichneten Linie heraus.
	var target_index := cursor
	var ahead_distance := 0.0
	var target_sum := Vector2.ZERO
	var target_count := 0
	# Liegt im ganzen Bereich voraus (großzügig: dreifacher Weg) keine Looping-Einfahrt, entfällt die Prüfung je Linienstück – gleiches
	# Ergebnis, aber auf Strecken mit Looping ein Viertel der Rechenzeit des Fahrers.
	var loops := not track.loops.is_empty() and not track.loop_between(float(route[cursor].s), float(route[cursor].s) + (3.0 * hi + 5.0) / track.length).is_empty()
	while target_index < route.size() - 1 and ahead_distance < hi:
		# Nicht über eine Looping-Einfahrt hinaus zielen: dahinter liegt die Ausfahrtsspur (seitlich versetzt).
		# Stattdessen geradeaus auf der Einfahrtsspur weiterzielen (gedachte Punkte in Streckenrichtung).
		if loops and not track.loop_between(float(route[target_index].s), float(route[target_index+1].s)).is_empty():
			var last := Vector2(route[target_index].p)
			var dir := track.tangent(float(route[target_index].s))
			var extra := 0.0
			while ahead_distance + extra < hi:
				extra += 0.5
				if ahead_distance + extra >= lo:
					target_sum += last + dir * extra
					target_count += 1
			break
		ahead_distance += Vector2(route[target_index].p).distance_to(route[target_index+1].p)
		target_index += 1
		if ahead_distance >= lo:
			target_sum += Vector2(route[target_index].p)
			target_count += 1
	return target_sum / target_count if target_count > 0 else Vector2(route[target_index].p)

func steer_to(error: float, target_distance: float, speed: float, dt: float) -> float:
	# Pure Pursuit (Lenkwinkel für den Bogen zum Zielpunkt, Radstand 2,3 m) mit Gierdämpfung: dreht das Auto schneller als der Bogen
	# verlangt, wird Lenkung zurückgenommen. Rückgabe: verlangter Lenkwinkel vor dem Anschlag (> 0,62 = der Bogen ist nicht fahrbar).
	var desired_steer := atan2(4.6 * sin(clampf(error,-1.4,1.4)), target_distance)
	var expected_yaw := speed * 2.0 * sin(clampf(error,-1.4,1.4)) / target_distance
	var demand := desired_steer + YAW_DAMPING * (expected_yaw - yaw)
	steering = move_toward(steering, clampf(demand, -0.62, 0.62), dt * STEER_RATE)
	return demand

func race_driver(dt: float, behind_line: bool, surface_grip: float, ground_drag: float) -> float:
	# Fahrer im Rennmodus: folgt der Linie (naher Zielpunkt im tempoabhängigen Vorausblick); nach einem Ausflug Rückkehr-Episode (siehe
	# REC_*). Setzt steering, liefert das Wunschtempo.
	var speed := velocity.length()
	var lookahead := LOOK_BASE + speed * LOOK_GAIN
	var target := aim(lookahead * 0.65, lookahead * 1.35)
	var guided := not behind_line and progress <= track.laps - 0.015
	var far := Vector2.INF
	var freeing := free_series and free_tries > 0
	var runup := 0.0
	land_clock = 0.0 if airborne else land_clock + dt
	if guided:
		measure_line()
		var start := REC_START + REC_START_WET * (1.0 - weather_grip) + REC_LAND_EXTRA * (1.0 - smoothstep(REC_LAND_TIME, REC_LAND_TIME + 0.5, land_clock))
		# Gegen die geglättete Linie nur rechnen, wo sie zählt: in der Episode und wenn die rohen Maße schon über der Schwelle liegen (eine
		# Episode beginnt erst, wenn beide es tun). Die normale Linienfolge bleibt so unverändert und kostet nichts mehr.
		if rec_episode or rec_fade > 0.0 or absf(line_offset) > start or absf(line_course) > REC_HEAD:
			smooth_line(lookahead)
		else:
			rec_offset = line_offset
			rec_course = line_course
		if not rec_episode:
			if absf(line_course) > REC_HEAD and absf(rec_course) > REC_HEAD:
				begin_episode(true)
			elif absf(line_offset) > start and absf(rec_offset) > start:
				begin_episode(false)
		rec_fade = move_toward(rec_fade, 1.0 if rec_episode else 0.0, dt * REC_FADE)
		if rec_fade > 0.0:
			# Anlauf einer Schwungzone (REC_RUNUP_*) und die Schanze bis zur Kante (dort bremste der Reibkreis das Gas, und ein Gegner sprang im
			# Schnee mit 7 statt 12 m/s ins Hafenbecken); nicht für ein Auto, das quer zur Linie steht oder noch von ihr weg fährt – das kommt
			# ohnehin nicht durch (Hafen, Schnee, zu schnell gezeichnet: mit Vollgas 5 m jenseits des Rands in die Masten).
			var zone := 1.0 if on_ramp() else 1.0 - smoothstep(REC_RUNUP_NEAR, REC_RUNUP_FAR, meters_to_entry(false))
			runup = zone * (1.0 - smoothstep(REC_HEAD, 1.3, absf(rec_course))) * (1.0 - smoothstep(0.0, 2.0 * REC_AWAY, signf(rec_offset) * rec_course))
		# Nach dem Zurücksetzen (bis das Auto am Hängepunkt vorbei ist) direkt zum nahen Zielpunkt: Der flache Anlauf über den fernen Punkt
		# führte am Hindernis entlang wieder hinein.
		if rec_fade > 0.0 and not freeing:
			far = recovery_target(lookahead, rec_fade)
	else:
		rec_episode = false
		rec_fade = 0.0
	if absf(avoid_offset) > 0.01:
		# Ausweichen (nur Gegner): Zielpunkt seitlich versetzen statt aufzufahren.
		target += (target - pos).normalized().orthogonal() * avoid_offset
		if far != Vector2.INF:
			far += (far - pos).normalized().orthogonal() * avoid_offset
	if progress > track.laps - 0.015:
		target = track.at(progress + 0.025)
	var target_distance := maxf(2.3, pos.distance_to(target))
	var near_error := wrapf((target - pos).angle() - heading, -PI, PI)
	if guided and not rec_episode and absf(near_error) > REC_HEAD and absf(line_offset) > REC_HEAD_OFF:
		smooth_line(lookahead)
		if absf(rec_offset) > REC_HEAD_OFF:
			begin_episode(true)
	# In der Episode Richtung vom fernen Punkt (langsame äußere Schleife: flacher Winkel, gedämpft), Krümmung über den nahen Abstand.
	var error := near_error if far == Vector2.INF else wrapf((far - pos).angle() - heading, -PI, PI)
	# Bogen zurück, nach dem sich das Tempo richtet: der Bogen zum Zielpunkt der Episode selbst (fern), nicht die schnelle Lenkantwort
	# darauf (über den nahen Abstand doppelt so eng) – mit ihr bremste der Fahrer nach der Landung neben der Linie, wo der Bogen frei passte.
	var k_back := 2.0 * absf(sin(clampf(error, -1.4, 1.4))) / (target_distance if far == Vector2.INF else maxf(target_distance, pos.distance_to(far)))
	# Bogen, den der Fahrer fahren möchte (vor der Begrenzung unten): sein Querbedarf bemisst das Gas im Reibkreis.
	var k_want := 2.0 * absf(sin(clampf(error, -1.4, 1.4))) / target_distance
	# Quer zur Linie (Kurs gegen sie über REC_HEAD, z. B. Nase zur Leitplanke): voller Einschlag. Die Begrenzung unten gilt dem sanften Zurücklenken;
	# mit ihr lenkte ein Auto, das 90° zur Kante stand, nur −0,25 statt −0,62 ein und durchbrach die Planke (Serra, Gegenprüfung).
	var steep := absf(rec_course) > REC_HEAD
	if rec_fade > 0.0 and speed > 1.0 and not airborne and not steep:
		# Die Lenkantwort der Episode höchstens bis an den Anteil der Querhaftung, den das Rückkehrtempo vorsieht (kein Rutschen beim Zurücklenken).
		var k_avail := REC_ARC_GRIP * grip * surface_grip / (speed * speed)
		if 2.0 * absf(sin(clampf(error, -1.4, 1.4))) / target_distance > k_avail:
			error = asin(clampf(k_avail * target_distance * 0.5, 0.0, 0.985)) * signf(error)
	if (rec_episode or rec_fade > 0.0) and not freeing and speed > 1.0 and not airborne and -signf(rec_offset) * rec_course > 0.0:
		# Schräg auf die Linie zu: Verlangt das Ausrichten bis zur Linie (align_curvature) schon einen merklichen Teil der Querhaftung, dreht
		# der Fahrer mindestens so stark von ihr weg, dass der Kurs bis dorthin parallel wird. Die gedämpfte äußere Schleife allein fing eine
		# schnelle Annäherung zu spät ab (2,5 m daneben, 20° bei 18 m/s: 0,75 m darüber hinaus). Darunter nähert sich das Auto weiter frei.
		var turn := signf(rec_offset)
		var need := align_curvature()
		need *= smoothstep(REC_STEER_USE0, REC_STEER_USE1, need * speed * speed / (REC_ARC_GRIP * grip * surface_grip))
		if need > 0.0 and 2.0 * sin(clampf(error, -1.4, 1.4)) / target_distance * turn < need:
			error = asin(clampf(need * target_distance * 0.5, 0.0, 0.985)) * turn
	var demand := steer_to(error, target_distance, speed, dt)
	var desired_speed: float = route[cursor].speed
	recovering = false
	if not guided and behind_line:
		return desired_speed
	if rec_fade > 0.0 and speed > 1.0 and not airborne:
		# Rückkehrtempo stetig: höchstens so schnell, dass der Bogen zum Zielpunkt und das Ausrichten auf die Linie in die Querhaftung
		# (Wetter, Untergrund) passen, nie unter REC_SPEED. Nahe der Linie und längs ihr ist das Plantempo samt Planbeschleunigung frei.
		# Im Anlauf einer Schwungzone nicht unter den Plan (runup).
		var bend := maxf(maxf(k_back, align_curvature()), 0.0005)
		var cap := maxf(REC_SPEED, sqrt(REC_ARC_GRIP * grip * surface_grip / bend))
		cap = lerpf(cap, maxf(cap, desired_speed), runup)
		desired_speed = lerpf(desired_speed, minf(desired_speed, cap), rec_fade)
		recovering = cap < float(route[cursor].speed)
		var hold := grip * surface_grip
		var need := speed * speed * bend
		var u := velocity.dot(Vector2.from_angle(heading))
		var drag := 0.010 * u * absf(u) + u * (0.09 + ground_drag)
		var circle := maxf(BRAKE_FLOOR, sqrt(maxf(0.0, hold * hold - need * need)) - drag)
		brake_room = lerpf(12.0, lerpf(circle, 12.0, smoothstep(1.0, BRAKE_OVER, need / hold)), rec_fade)
		if u > 1.0:
			# Gas: Antrieb abzüglich Fahrwiderstand höchstens, was neben dem gewünschten Bogen im Reibkreis bleibt (drive_room). Zeigt der Kurs
			# noch von der Linie weg, hält der Fahrer nur das Tempo: Mit Gas trieb das Auto auf Erde weiter hinaus (Serra, zu schnell gezeichnet:
			# 4,6 m jenseits des Rands in die Randpfosten).
			var want := speed * speed * maxf(bend, k_want)
			var room := sqrt(maxf(0.0, hold * hold - want * want)) + maxf(drag, 0.0)
			room = lerpf(room, maxf(drag, 0.0), smoothstep(0.0, REC_AWAY, signf(rec_offset) * rec_course))
			drive_room = lerpf(power, minf(power, room), rec_fade * (1.0 - runup))
	if rec_episode:
		# Ende gegen die rohe oder die geglättete Linie, je nachdem, welche näher liegt: In einer Kurve liegt die geglättete innen (Kurve mit
		# R 30 m: 0,8 m), dort hing die Episode sonst die ganze Kurve lang; auf einer welligen Linie pendelt die rohe.
		var near_line := minf(absf(line_offset), absf(rec_offset))
		rec_settle = rec_settle + dt if near_line < REC_END_BAND and speed > 1.0 else 0.0
		var aligned := (absf(line_offset) < REC_END and absf(line_course) < REC_END_COURSE) or (absf(rec_offset) < REC_END and absf(rec_course) < REC_END_COURSE)
		if rec_settle >= REC_SETTLE or (aligned and speed > 1.0):
			rec_episode = false
	if absf(demand) > 0.62 and not airborne:
		# Lenkung am Anschlag (der Bogen ist zu eng für das Tempo): Gas weg, bis er fahrbar wird – im Anlauf einer Schwungzone nicht. Auch auf
		# den letzten Metern vor dem Ziel (ohne Episode): Dort fuhr ein Auto, das quer am Ende der Serra ankam, mit Vollgas im Kreis durch die Planke.
		desired_speed = lerpf(minf(desired_speed, maxf(REC_SPEED, speed * 0.62 / absf(demand))), desired_speed, runup)
	return desired_speed

func begin_episode(urgent: bool) -> void:
	# Rückkehr-Episode beginnt. urgent (Kurs quer zur Linie, Auto schiebt über die Vorderräder): ohne Einblenden, Zielpunkt und Tempodeckel
	# wirken sofort. Mit 0,25 s Einblenden gab der Fahrer erst noch Plantempo-Gas und bremste zu spät (Nase zur Leitplanke, Serra).
	rec_episode = true
	rec_settle = 0.0
	if urgent:
		rec_fade = 1.0

func drift_driver(dt: float, behind_line: bool) -> float:
	# Profi-Drifter im Drift-Modus (DRIFT_*, 15.10.2026). Setzt steering, liefert das Wunschtempo; das Gas im Drift über drive_room (pedals
	# gibt höchstens so viel Antrieb, wie der Fahrer in diesem Takt zulässt).
	var speed := velocity.length()
	var lookahead := LOOK_BASE + speed * LOOK_GAIN
	var target := aim(lookahead * 0.65, lookahead * 1.35)
	if absf(avoid_offset) > 0.01:
		target += (target - pos).normalized().orthogonal() * avoid_offset
	if progress > track.laps - 0.015:
		target = track.at(progress + 0.025)
	var error := wrapf((target - pos).angle() - heading, -PI, PI)        # Nase gegen das Ziel
	var course := velocity.angle() if speed > 2.0 else heading
	var e_c := wrapf((target - pos).angle() - course, -PI, PI)           # Kurs gegen das Ziel
	# Verloren: gedreht (Ziel seitlich hinter der Nase, und der Kurs zeigt nicht mehr hin – im Drift steht die Nase quer, der Kurs nicht)
	# oder mehr als DRIFT_LOST_EDGE jenseits des Fahrbahnrands.
	var spun := absf(error) > DRIFT_LOST_ERROR and (speed < 4.0 or absf(e_c) > DRIFT_LOST_COURSE)
	recovering = not behind_line and (spun or beyond_edge(DRIFT_LOST_EDGE))
	var target_distance := maxf(2.3, pos.distance_to(target))
	var turning := recovering and absf(error) > 1.4
	# Stillstandswache: Ohne FREE_NET m Nettofortschritt in DRIFT_STALL_TIME s ist das Auto festgefahren (Wrack), auch ohne Bugkontakt. Ein
	# Wechsel aus Vor und Zurück ohne Berührung zählte sonst nie als Hängen (Gegenprüfung: 81 s Stillstand neben einer Reifenwand).
	if behind_line or (progress - drift_mark) * track.length > FREE_NET:
		drift_mark = maxf(progress, 0.0)
		drift_stall = 0.0
	else:
		drift_stall += dt
		if drift_stall > DRIFT_STALL_TIME:
			wreck_cause = "fest " + (touch_kind if touch_kind != "" else "stand")
			wreck()
			return 0.0
	# Sperre gegen erneutes Zurücksetzen: Rollt das Auto rückwärts (Zurücksetzen jeder Art, auch das Freifahren), darf der Fahrer erst wieder
	# zurücksetzen, wenn es DRIFT_REV_HOLD s oder DRIFT_REV_HOLD_WAY m vorwärts gefahren ist. Endete das Zurücksetzen mit dem Heck am Hindernis
	# (touch_rear), stand das Auto sonst im nächsten Takt wieder „gedreht und fast stehend“ da und setzte erneut zurück – Dutzende Male.
	if velocity.dot(Vector2.from_angle(heading)) < -0.3:
		drift_hold = DRIFT_REV_HOLD
		drift_hold_from = pos
	elif drift_hold > 0.0:
		drift_hold = 0.0 if pos.distance_to(drift_hold_from) > DRIFT_REV_HOLD_WAY else drift_hold - dt
	# Umweg um ein Hindernis neben der Fahrbahn, an dem das Auto hing (drift_detour). Erneut gehangen (Freifahren zählt einen Versuch mehr):
	# neu ansetzen. An der angefahrenen Ecke: ist der Weg zur Linie jetzt frei, endet er, sonst geht es zur nächsten Ecke.
	if detour_on and free_tries > detour_tries:
		detour_on = false
	if not detour_on:
		drift_detour()
	elif pos.distance_to(detour_point) < 1.5 or detour_clock > DRIFT_DETOUR_TIME:
		detour_on = false
		if detour_hops < DRIFT_DETOUR_HOPS:
			detour_route(detour_index)
	if detour_on:
		# Nach dem Zurücksetzen an einem Hindernis neben der Fahrbahn (Reifenwand, Mast): erst um dessen Ecke herum, dann zur Linie. Zur Linie
		# voraus führte der Weg sonst wieder geradewegs hinein (fünfmal hängen, Wrack). Liegt die Ecke weit seitlich, erst rückwärts mit
		# Gegeneinschlag, bis die Nase zu ihr zeigt (Wenden in drei Zügen). Der Umweg gilt, bis das Auto die Ecke erreicht hat oder
		# DRIFT_DETOUR_TIME vergangen ist; vorher wurde er jeden Takt neu entschieden und kippte an der Schwelle hin und her (vor, zurück, vor …
		# ohne je 1 m/s zu erreichen).
		detour_clock += dt
		recovering = true
		drift_goal = 0.0
		var e_d := wrapf((detour_point - pos).angle() - heading, -PI, PI)
		if not detour_back and absf(e_d) > 1.0 and speed < DRIFT_REV_SPEED and (detour_backs == 0 or drift_hold <= 0.0):
			detour_back = true
			detour_backs += 1
			detour_from = pos
			detour_back_time = 0.0
		if detour_back:
			detour_back_time += dt
			if absf(e_d) < 0.5 or (touch_rear and detour_back_time > 0.3) or pos.distance_to(detour_from) > REV_MAX or detour_back_time > REV_TIME:
				detour_back = false
		if detour_back:
			steering = move_toward(steering, nose_free(-DRIFT_LOCK * signf(e_d)), dt * DRIFT_STEER_RATE)
			return -REV_SPEED
		var geo_d := atan2(4.6 * sin(clampf(e_d, -1.4, 1.4)), maxf(2.3, pos.distance_to(detour_point)))
		steering = move_toward(steering, clampf(geo_d, -DRIFT_LOCK, DRIFT_LOCK), dt * DRIFT_STEER_RATE)
		return minf(float(route[cursor].speed), DRIFT_DETOUR_SPEED)
	if not drift_back and turning and speed < DRIFT_REV_SPEED and not behind_line and drift_hold <= 0.0:
		drift_back = true
		drift_back_time = 0.0
		drift_back_from = pos
	if drift_back:
		return drift_reverse(dt)
	var ground := str(track.surface_at(pos, previous_phase).kind)
	var surface := 1.0 - (1.0 - float(SURFACE_GRIP.get(ground, 1.0))) / offroad
	if recovering and not turning:
		# Abseits der Fahrbahn, aber nicht gedreht: Rückkehr wie im Rennmodus (race_driver: Episode erst steil zurück auf die Fahrbahn, dann
		# flach; nach dem Freifahren direkt zum nahen Zielpunkt). Geradewegs zum Linienpunkt voraus fuhr das Auto neben der Fahrbahn immer
		# wieder in dieselbe Reifenwand (Hängen, Zurücksetzen, wieder hinein) und war nach fünf Versuchen ein Wrack.
		drift_goal = 0.0
		var back := race_driver(dt, behind_line, surface * weather_grip, float(SURFACE_DRAG.get(ground, 0.0)) / offroad)
		recovering = true
		return back
	# Linie lesen. Nach einem Ausflug und nach dem Freifahren (bis das Auto am Hängepunkt vorbei ist) kein Drift.
	var freeing := free_series and free_tries > 0
	var line := Vector2.ZERO if (recovering or freeing or behind_line) else drift_line(speed, float(SURFACE_GRIP.get(ground, 1.0)))
	drift_goal = line.x
	var bend := line.y if drift_goal > 0.0 else (signf(e_c) if absf(e_c) > 0.02 else signf(yaw))
	var slip_angle := wrapf(heading - course, -PI, PI) if speed > 2.0 else 0.0
	var beta := slip_angle * bend                                        # Driftwinkel, + = Nase zur Kurveninnenseite
	# Lenkung. Im Drift: Vorderräder in die Bewegungsrichtung der Vorderachse (gamma_f; im Drift ist das Gegenlenken), dazu der Schräglauf
	# für den Kurs zum Ziel, die Gierrate des Kursbogens und das Anstellen (fehlender Winkel), begrenzt auf den Haftbereich vorn.
	var forward := Vector2.from_angle(heading)
	var u := velocity.dot(forward)
	var v := velocity.dot(-forward.orthogonal())
	var omega_d := speed * 2.0 * sin(clampf(e_c, -1.4, 1.4)) / target_distance
	var gamma_f := atan2(v + 1.1 * yaw, absf(u) + 1.8)
	var cap_f := grip * surface * weather_grip * (1.0 - rear_share)
	var desired_steer: float
	if turning:
		desired_steer = DRIFT_LOCK * signf(error)
	else:
		var a_cmd := DRIFT_KP * e_c + DRIFT_KR * (omega_d - yaw)
		if drift_goal > 0.0:
			a_cmd += DRIFT_KBU * maxf(0.0, drift_goal - beta) * bend
		desired_steer = clampf(gamma_f + clampf(a_cmd, -cap_f / 36.0, cap_f / 36.0), -DRIFT_LOCK, DRIFT_LOCK)
		# Langsam oder verloren: geometrisch zum Ziel (Pure Pursuit mit Gierdämpfung). Ein Schräglaufbefehl lenkt im Schritttempo kaum (das
		# verlorene Auto fuhr neben der Fahrbahn geradeaus in die Reifenwand).
		var geo := atan2(4.6 * sin(clampf(error, -1.4, 1.4)), target_distance)
		geo = clampf(geo + YAW_DAMPING * (speed * 2.0 * sin(clampf(error, -1.4, 1.4)) / target_distance - yaw), -DRIFT_LOCK, DRIFT_LOCK)
		desired_steer = lerpf(geo, desired_steer, 0.0 if recovering else smoothstep(DRIFT_GEO0, DRIFT_GEO1, speed))
	steering = move_toward(steering, desired_steer, dt * DRIFT_STEER_RATE)
	# Pedale.
	var plan: float = route[cursor].speed
	if recovering:
		return minf(plan, DRIFT_TURN_SPEED if turning else REC_SPEED)
	if freeing:
		plan = minf(plan, REC_SPEED)
	var pace := signf(u) * speed     # wie in step(): im Drift-Modus zählt das Fahrtempo
	if drift_goal > 0.0 and pace < plan + DRIFT_COAST:
		# Gas hält den Winkel: zu wenig -> mehr Gas (das Heck dreht durch und verliert Seitenführung), zu viel -> lupfen (es greift). Über das
		# Plantempo hinaus gibt er kein Gas (die gezeichnete Tempofarbe bleibt die Obergrenze), bis DRIFT_COAST darüber rollt er.
		var want := clampf(DRIFT_THR0 + DRIFT_THR_GAIN * (drift_goal - beta), 0.0, 1.0) * power
		if pace >= plan or beta > maxf(DRIFT_BETA_HARD, drift_goal + DRIFT_BETA_OVER):
			want = 0.0
		drive_room = want
		return pace + 99.0
	if speed > 2.0 and absf(slip_angle) > DRIFT_CATCH:
		# Quer ohne Driftwunsch (Kurvenausgang, vor einem Nadelöhr): nur den Fahrwiderstand halten, damit das Heck wieder greift. Mit dem Gas
		# nach Plan drehte der Heckantrieb am Kurvenausgang weiter ein und stand im Nadelöhr quer.
		drive_room = minf(power, maxf(0.0, 0.010 * u * absf(u) + u * 0.09) + 0.5)
	return plan

func drift_reverse(dt: float) -> float:
	# Verloren und fast stehend, das Ziel seitlich hinter dem Auto (Drift-Modus): zurücksetzen wie beim Freifahren (rückwärts, die Nase dreht
	# zum Ziel REV_GOAL m voraus auf der Linie), statt mit vollem Einschlag im Kreis zu kriechen – dafür fehlt neben Reifenwand und Inselrand oft
	# der Platz. Ende wie beim Freifahren (ausgerichtet nach REV_MIN m, REV_MAX m, REV_TIME s oder Heck am Hindernis), danach erst vorwärts
	# (DRIFT_REV_HOLD): Wenden in mehreren Zügen. Eigener Ablauf statt free_driver, damit Hängen (update_hang, das während des Freifahrens
	# ruht) und die Stillstandswache weiterzählen: Klemmte das Auto zwischen zwei Absperrgittern, setzte es sonst alle 0,3 s erneut zurück –
	# ohne je als festgefahren zu gelten (Gegenprüfung: 38 Zurücksetz-Starts, 23 s Stillstand).
	drift_back_time += dt
	recovering = true
	drift_goal = 0.0
	while cursor > 0 and float(route[cursor].s) > progress:
		cursor -= 1
	var goal := aim(REV_GOAL, REV_GOAL + 2.0)
	var error := wrapf((goal - pos).angle() - heading, -PI, PI)
	steering = move_toward(steering, nose_free(-DRIFT_LOCK * clampf(error / 0.6, -1.0, 1.0)), dt * DRIFT_STEER_RATE)
	var backed := pos.distance_to(drift_back_from)
	if (touch_rear and drift_back_time > 0.3) or (backed >= REV_MIN and absf(error) < REV_ALIGN) or backed >= REV_MAX or drift_back_time >= REV_TIME:
		drift_back = false
		drift_hold = DRIFT_REV_HOLD
		drift_hold_from = pos
	return -REV_SPEED

func nose_free(steer: float) -> float:
	# Rückwärts (Drift-Modus): Liegt die Nase an einem Hindernis an, erst so einschlagen, dass sie von ihm wegschwenkt (rückwärts schwenkt die
	# Nase gegen den Einschlag). Der Einschlag zum Ziel auf der Linie drückte sie an den quer stehenden Reifenwänden der Arena in die Wand, und
	# das Auto schrammte mit 0,1 m/s an ihr entlang (weiche Hindernisse bremsen das Entlanggleiten), bis es nach fünf Versuchen ein Wrack war.
	if not touch_front or touch_index < 0 or touch_index >= track.obstacles.size():
		return steer
	var hit := track.obstacle_contact(track.obstacles[touch_index], pos + Vector2.from_angle(heading) * CAR_REACH, CAR_RADIUS + 0.2)
	if hit.z <= 0.0:
		return steer
	var away := Vector2(hit.x, hit.y).dot(-Vector2.from_angle(heading).orthogonal())     # > 0: weg = nach links
	return -DRIFT_LOCK * signf(away) if absf(away) > 0.2 else steer

func drift_detour() -> void:
	# Beginnt den Umweg um das Hindernis, an dem das Auto zuletzt hing (Drift-Modus, nach dem Zurücksetzen), wenn es den geraden Weg zur Linie
	# (DRIFT_DETOUR_AIM m voraus) versperrt. Die Ecken stehen in der Lage des Hindernisses, nicht der Strecke: Die Reifenwände der Arena stehen
	# in den Kurven quer zur Fahrbahn (bis 5,5 m tief), dort lag der frühere Umwegpunkt „hinter dem Ende in Streckenrichtung“ mal vor, mal hinter
	# der Wand, je nachdem, wie die Streckenrichtung am Auto gerade fiel.
	if not (free_series and free_tries > 0) or touch_index < 0 or touch_index >= track.obstacles.size():
		return
	var o: Dictionary = track.obstacles[touch_index]
	if pos.distance_to(o.c) > 12.0:
		return
	detour_hops = 0
	detour_tries = free_tries
	detour_route(touch_index)

func detour_route(index: int) -> void:
	# Nächste Ecke des Umwegs um Hindernis index (detour_on, detour_point), falls es den Weg zum Ziel auf der Linie versperrt: unter den vom Auto
	# aus frei erreichbaren Ecken (Rechteck bzw. Kreis als Quadrat, um CAR_RADIUS + DRIFT_DETOUR erweitert, innerhalb der Insel, frei von anderen
	# Hindernissen) die mit dem kürzesten Weg Auto → Ecke → Ziel; bevorzugt eine, von der aus das Ziel frei ist.
	var o: Dictionary = track.obstacles[index]
	var goal := aim(DRIFT_DETOUR_AIM, DRIFT_DETOUR_AIM + 4.0)
	if not detour_blocked(o, pos, goal):
		return
	var c: Vector2 = o.c
	var u: Vector2 = Vector2(o.u) if o.has("u") else (goal - pos).normalized()
	var v := Vector2(-u.y, u.x)
	var half := Vector2(o.h) if o.has("h") else Vector2(float(o.r), float(o.r))
	var m := CAR_RADIUS + DRIFT_DETOUR
	var best := Vector2.INF
	var best_cost := INF
	for i: float in [-1.0, 1.0]:
		for j: float in [-1.0, 1.0]:
			var k: Vector2 = c + u * (half.x + m) * i + v * (half.y + m) * j
			if pos.distance_to(k) < 1.5 or detour_blocked(o, pos, k):
				continue
			if track.center_distance(k, previous_phase) > ISLAND_LIMIT + track.hw(previous_phase) - Circuit.HALF_WIDTH - 1.0:
				continue
			var free := true
			for idx in track.obstacles_near(k):
				if idx != index and track.obstacle_contact(track.obstacles[idx], k, CAR_RADIUS).z > 0.0:
					free = false
			if not free:
				continue
			var cost: float = pos.distance_to(k) + k.distance_to(goal) + (20.0 if detour_blocked(o, k, goal) else 0.0)
			if cost < best_cost:
				best_cost = cost
				best = k
	if best == Vector2.INF:
		return
	detour_on = true
	drift_back = false
	detour_point = best
	detour_index = index
	detour_hops += 1
	detour_clock = 0.0
	detour_backs = 0
	detour_back = false

func detour_blocked(o: Dictionary, a: Vector2, b: Vector2) -> bool:
	# Versperrt das Hindernis die Strecke a → b (Proben alle 0,5 m, halbe Wagenbreite)?
	var n := maxi(1, int(a.distance_to(b) / 0.5))
	for i in range(n + 1):
		if track.obstacle_contact(o, a.lerp(b, float(i) / n), 0.6).z > 0.0:
			return true
	return false

func drift_line(speed: float, surface: float) -> Vector2:
	# Liest die gezeichnete Linie voraus (Drift-Modus): Zielwinkel (rad) und Kurvenrichtung (links +1). Überschuss je Stelle = Plantempo² ·
	# Krümmung (Menger-Kreis durch Linienpunkte im Abstand 4 m) / Bezugshaftung (DRIFT_REF_GRIP · surface, surface = Haftung des Belags allein,
	# ohne die Geländegängigkeit des Autos: gleiche Linie, gleicher Plan für jedes Auto); Zielwinkel = (Überschuss − DRIFT_E_ON) · DRIFT_GAIN, höchstens
	# DRIFT_BETA_MAX. Kurven bis DRIFT_T_INIT s voraus zählen voll, dahinter auf DRIFT_RAMP m eingeblendet; es zählt die größte.
	# Nadelöhr (halbe Breite unter DRIFT_NARROW): DRIFT_T_CATCH s davor kein Driftwunsch (abfangen), Kurven dahinter zählen nicht; im Nadelöhr
	# erst DRIFT_EXIT m vor dem Ausgang. Die 20-m-Vorausschau des Prototyps stellte das Auto schon im 2,6-m-Nadelöhr für die nächste Kurve an,
	# es drehte sich dort und verkeilte sich zwischen den Betonblöcken.
	var near := maxf(4.0, speed * DRIFT_T_INIT)
	var reach := minf(DRIFT_LOOK, near + DRIFT_RAMP)
	var check_narrow := not track.widths.is_empty()
	var in_narrow := check_narrow and track.hw(previous_phase) < DRIFT_NARROW
	var d_narrow := 0.0 if in_narrow else INF      # Meter bis zum nächsten Nadelöhr
	var d_wide := 0.0                               # im Nadelöhr: Meter bis zu seinem Ausgang
	var scan := maxf(reach + 8.0, speed * DRIFT_T_CATCH + 2.0) if check_narrow else reach + 8.0
	var idx: Array[int] = [cursor]
	var dist: Array[float] = [0.0]
	var walked := 0.0
	var i := cursor
	while i < route.size() - 1 and walked < scan:
		walked += Vector2(route[i].p).distance_to(route[i + 1].p)
		i += 1
		if check_narrow:
			var narrow := track.hw(float(route[i].s)) < DRIFT_NARROW
			if narrow and d_narrow == INF:
				d_narrow = walked
			if in_narrow and not narrow and d_wide == 0.0:
				d_wide = walked
		if walked >= 4.0 * idx.size() and walked <= reach + 8.0:
			idx.append(i)
			dist.append(walked)
	if in_narrow and d_wide == 0.0:
		d_wide = INF
	if (not in_narrow and d_narrow < speed * DRIFT_T_CATCH) or (in_narrow and d_wide > DRIFT_EXIT):
		return Vector2.ZERO
	var best := Vector2.ZERO
	var ref := DRIFT_REF_GRIP * surface
	for j in range(idx.size() - 2):
		var d := dist[j + 1]
		if d >= d_narrow and not in_narrow:
			break
		if in_narrow and d < d_wide:
			continue
		var a := Vector2(route[idx[j]].p)
		var b := Vector2(route[idx[j + 1]].p)
		var c := Vector2(route[idx[j + 2]].p)
		var den := a.distance_to(b) * b.distance_to(c) * c.distance_to(a)
		if den < 1e-4:
			continue
		var k := 2.0 * (b - a).cross(c - b) / den
		var vm := float(route[idx[j + 1]].speed)
		var goal := clampf((vm * vm * absf(k) / maxf(1.0, ref) - DRIFT_E_ON) * DRIFT_GAIN, 0.0, DRIFT_BETA_MAX)
		goal *= 1.0 - clampf((d - near) / DRIFT_RAMP, 0.0, 1.0)
		if goal > best.x:
			best = Vector2(goal, signf(k))
	return best

func free_driver(dt: float) -> float:
	# Zurücksetzen (siehe HANG_TIME): rückwärts, die Nase dreht zum Ziel ein Stück voraus auf der Linie. Rückwärts gelenkt dreht das Auto
	# umgekehrt, deshalb wird gegen die Zielrichtung gelenkt. Ende: ausgerichtet und genug Abstand, Weg oder Zeit aufgebraucht, oder das
	# Heck stößt an; danach vorwärts mit Rückkehr auf die Linie. Neben einem verfehlten Wippen-Deck (rev_goal, deck_retry_point) setzt es
	# stattdessen mit dem Heck voran bis auf die Linie vor der Einfahrt zurück und nimmt neuen Anlauf.
	rev_time += dt
	recovering = true
	# Der Fortschrittscursor läuft sonst nur vorwärts; rückwärts muss er mit, sonst zielte das Auto danach vom Hängepunkt aus weiter.
	while cursor > 0 and float(route[cursor].s) > progress:
		cursor -= 1
	var done := touch_rear and rev_time > 0.3
	if rev_goal != Vector2.INF:
		var back := wrapf((rev_goal - pos).angle() - heading - PI, -PI, PI)
		steering = move_toward(steering, -0.62 * clampf(back / 0.6, -1.0, 1.0), dt * STEER_RATE)
		done = done or pos.distance_to(rev_goal) < 1.5 or (rev_goal - pos).dot(Vector2.from_angle(heading)) > 0.0 or rev_time >= REV_DECK_TIME
	else:
		# Ziel nah voraus auf der Linie: Die Nase dreht steil zu ihr (vom Hindernis weg); mit einem fernen Ziel (bisher 6–10 m) führte der
		# Weg danach wieder flach am Hindernis entlang hinein.
		# Mit jedem weiteren Versuch liegt das Ziel REV_GOAL_STEP weiter voraus: Steht ein Mast oder Baum zwischen Auto und Linie, führte der
		# steile Weg jedes Mal wieder auf ihn (Wald, Pfostenreihe: fünf Versuche, Wrack); flacher gleitet das Auto an ihm vorbei.
		var reach := REV_GOAL + REV_GOAL_STEP * float(maxi(free_tries - 1, 0))
		var goal := aim(reach, reach + 2.0)
		var error := wrapf((goal - pos).angle() - heading, -PI, PI)
		steering = move_toward(steering, -0.62 * clampf(error / 0.6, -1.0, 1.0), dt * STEER_RATE)
		var backed := pos.distance_to(rev_from)
		done = done or (backed >= REV_MIN and absf(error) < REV_ALIGN) or backed >= REV_MAX or rev_time >= REV_TIME
	if done:
		reversing = false
		if track.mode != "drift":
			rec_episode = true
		if rev_goal != Vector2.INF:
			# Neuer Anlauf: Die Uhr der Hängeserie beginnt neu (das Zurücksetzen allein dauert bis 10 s, danach wäre jedes weitere Hängen sofort
			# ein Wrack gewesen); Versuche und Hängepunkt bleiben, bis das Auto an ihm vorbei ist.
			free_clock = 0.0
	return -REV_SPEED

func deck_retry_point() -> Vector2:
	# Neben einem Wippen-Deck hängengeblieben, über das die eigene Linie führt (Deck verfehlt): Seitlich kommt das Auto nicht hinauf
	# (Seitenwand, Stiftenden am Drehpunkt, gleich daneben Bausteine). Ziel des Zurücksetzens ist deshalb der Linienpunkt REV_DECK m vor der
	# Einfahrt; von dort nimmt es neuen Anlauf. Sonst Vector2.INF (kurzes Zurücksetzen wie bisher).
	for wv in seesaws:
		var w: Seesaw = wv
		if w.shortcut < 0 or deck == w or not takes_shortcut(w.shortcut):
			continue
		var l: Vector2 = w.local(pos)
		if absf(l.x) > w.half_len + 1.0 or absf(l.y) > w.half_w + 3.0:
			continue
		var start := w.world(-w.half_len - REV_DECK)
		var best := Vector2.INF
		for j in range(maxi(0, cursor - 80), mini(route.size(), cursor + 20)):
			if best == Vector2.INF or start.distance_squared_to(route[j].p) < start.distance_squared_to(best):
				best = route[j].p
		return best
	return Vector2.INF

func pedals(desired_speed: float, pace: float, u: float, dose: bool) -> float:
	# Gas und Bremse des Fahrers: setzt braking (wirkt gegen die Bewegung), liefert den Antrieb (m/s², < 0 = Rückwärtsgang).
	if desired_speed < 0.0:
		# Zurücksetzen: erst anhalten, dann rückwärts bis REV_SPEED.
		if u > 0.3:
			braking = clampf(u * 1.6 + 2.0, 0.0, 12.0)
			return 0.0
		braking = clampf((u - desired_speed) * -1.6, 0.0, 12.0)
		return clampf((desired_speed - u) * 2.2, -REV_DRIVE, 0.0)
	var limit := brake_room
	if dose and velocity.length() > 3.0:
		# Bremsdosierung (BRAKE_*): quer rutschend nur noch BRAKE_FLOOR.
		var slide := absf(wrapf(heading - velocity.angle(), -PI, PI))
		limit = minf(limit, lerpf(12.0, BRAKE_FLOOR, smoothstep(BRAKE_SLIDE0, BRAKE_SLIDE1, slide)))
	braking = clampf((pace - desired_speed) * 1.6, 0.0, limit)
	return clampf((desired_speed - pace) * 2.2, 0.0, minf(power, drive_room))

func measure_line() -> void:
	# Querabstand zur eigenen Linie (links positiv), Kurs gegen ihre lokale Richtung (über ~2 m geglättet). Lokale Suche ab dem nächsten
	# Linienpunkt des Vortakts, im Fenster um den Fortschrittscursor; Linienstücke über eine Looping-Einfahrt (Spurwechsel) zählen nicht.
	var last := route.size() - 1
	var lo := maxi(0, cursor - 12)
	var hi := mini(last, cursor + 40)
	var j := clampi(line_index, lo, hi)
	var d := pos.distance_squared_to(route[j].p)
	while j < hi:
		var dn := pos.distance_squared_to(route[j + 1].p)
		if dn > d:
			break
		d = dn
		j += 1
	while j > lo:
		var dp := pos.distance_squared_to(route[j - 1].p)
		if dp >= d:
			break
		d = dp
		j -= 1
	line_index = j
	var best := INF
	for k in [j - 1, j]:
		if k < 0 or k >= last:
			continue
		if not track.loops.is_empty() and not track.loop_between(float(route[k].s), float(route[k + 1].s)).is_empty():
			continue
		var a: Vector2 = route[k].p
		var b: Vector2 = route[k + 1].p
		var q := Geometry2D.get_closest_point_to_segment(pos, a, b)
		if k == 0 and (pos - a).dot(b - a) < 0.0 and a.distance_squared_to(b) > 0.0001:
			# Vor dem ersten Linienpunkt (Startplätze hinter der Linie): Querabstand zur Verlängerung des ersten Stücks. Der Punktabstand (3–19 m)
			# ließ jedes Auto ab Startplatz 2 mit einer Episode losfahren.
			q = a + (b - a) * ((pos - a).dot(b - a) / a.distance_squared_to(b))
		var dq := pos.distance_squared_to(q)
		if dq < best:
			best = dq
			line_offset = signf((b - a).cross(pos - q)) * sqrt(dq)
	if best == INF:
		line_offset = 0.0
	var ahead: Vector2 = route[mini(j + 4, last)].p
	var behind: Vector2 = route[maxi(j - 1, 0)].p
	if ahead.distance_squared_to(behind) > 0.01:
		line_dir = (ahead - behind).normalized()
	line_course = wrapf(velocity.angle() - line_dir.angle(), -PI, PI) if velocity.length() > 0.5 else wrapf(heading - line_dir.angle(), -PI, PI)

func smooth_line(lookahead: float) -> void:
	# Querabstand und Kurs gegen die geglättete eigene Linie (rec_offset, rec_course): Ausgleichsgerade (Hauptachse) der Linienpunkte bis
	# REC_SMOOTH · Vorausblick vor und hinter dem nächsten Punkt, nicht über eine Looping-Einfahrt (Spurwechsel) hinweg, dazu der Bogen der
	# mittleren Krümmung des Fensters (Richtungsänderung vom ersten zum letzten Stück je Meter). Auf einer Geraden und in einer Kurve gleich der
	# rohen Linie; eine Welle von etwa der Fensterlänge mittelt sie heraus (ihre Richtung ist an beiden Fensterenden fast gleich). Ohne den Bogen
	# lag die Ausgleichsgerade in einer Kurve um Reichweite²·Krümmung/6 innen (R 30 m: 0,8 m), und die Episode fand dort kein Ende.
	rec_offset = line_offset
	rec_course = line_course
	var last := route.size() - 1
	var j := clampi(line_index, 0, last)
	var origin: Vector2 = route[j].p
	var reach := REC_SMOOTH * lookahead
	var n := 1.0
	var sx := 0.0
	var sy := 0.0
	var sxx := 0.0
	var sxy := 0.0
	var syy := 0.0
	var span := 0.0
	var ends := [Vector2.ZERO, Vector2.ZERO]   # Richtung des äußersten Stücks hinten und vorn (in Fahrtrichtung)
	var loops := not track.loops.is_empty()
	for side in [0, 1]:
		# Jeder zweite Linienpunkt (etwa 1 m Abstand) genügt für die Mittelung und halbiert die Rechenzeit; die Looping-Prüfung nur für ein
		# langes Stück (der Spurwechsel an der Einfahrt ist 1,8 m breit).
		var dir := -2 if side == 0 else 2
		var k := j
		var walked := 0.0
		while walked < reach:
			var nk: int = clampi(k + dir, 0, last)
			if nk == k:
				break
			var step := (Vector2(route[nk].p) - Vector2(route[k].p)) * signf(float(dir))
			if loops and step.length_squared() > 2.6 and not track.loop_between(float(route[mini(k, nk)].s), float(route[maxi(k, nk)].s)).is_empty():
				break
			var r: Vector2 = Vector2(route[nk].p) - origin
			walked += step.length()
			if step.length_squared() > 0.0001:
				ends[side] = step
			sx += r.x
			sy += r.y
			sxx += r.x * r.x
			sxy += r.x * r.y
			syy += r.y * r.y
			n += 1.0
			k = nk
		span += walked
	if n < 4.0 or ends[0] == Vector2.ZERO or ends[1] == Vector2.ZERO:
		return
	var mx := sx / n
	var my := sy / n
	var cxx := sxx / n - mx * mx
	var cxy := sxy / n - mx * my
	var cyy := syy / n - my * my
	if cxx + cyy < 0.01:
		return
	var axis := Vector2.from_angle(0.5 * atan2(2.0 * cxy, cxx - cyy))
	if axis.dot(line_dir) < 0.0:
		axis = -axis
	var rel := pos - (origin + Vector2(mx, my))
	var along := rel.dot(axis)
	var spread := cxx * axis.x * axis.x + 2.0 * cxy * axis.x * axis.y + cyy * axis.y * axis.y   # mittleres Quadrat längs der Achse
	var bend := wrapf(Vector2(ends[1]).angle() - Vector2(ends[0]).angle(), -PI, PI) / maxf(span, 1.0)
	rec_offset = axis.cross(rel) - bend * (along * along - spread) * 0.5
	rec_course = wrapf((velocity.angle() if velocity.length() > 0.5 else heading) - (axis.angle() + bend * along), -PI, PI)

func align_curvature() -> float:
	# Krümmung, die das Ausrichten auf die (geglättete) Linie verlangt: Kurs um ψ gegen ihre Richtung. Auf die Linie zu bleibt der verbleibende
	# Querabstand zum Zurückdrehen (e = R·(1 − cos ψ)), abzüglich des Wegs, den das Auto quer zurücklegt, bis Lenkung und Gierrate stehen
	# (REC_LAG); von ihr weg nur REC_ALIGN_MIN.
	var toward := -signf(rec_offset) * rec_course
	var room := REC_ALIGN_MIN
	if toward >= 0.0:
		room = maxf(absf(rec_offset) - velocity.length() * sin(absf(rec_course)) * REC_LAG, REC_ALIGN_MIN)
	return (1.0 - cos(rec_course)) / room

func recovery_target(lookahead: float, w: float) -> Vector2:
	# Ferner Zielpunkt der Rückkehr: so weit voraus, dass die Annäherung unter begrenztem Winkel geschieht (abseits des Belags steiler,
	# auf ihm flach), mindestens REC_DAMP · Vorausblick; höchstens bis zum Kurveneingang und zur halben Strecke vor die nächste Einfahrt.
	# Die Fahrbahnabfrage kommt aus edge_check des Vortakts (gleiche Lage; spart ein Drittel der Episodenrechnung), sonst frisch.
	var q := near_q if not near_q.is_empty() else track.query_branch(pos, previous_phase)
	var beyond := maxf(0.0, float(q.distance) - (track.hw(float(q.s)) - REC_OFF_MARGIN))
	var a := absf(rec_offset)
	var a_off := minf(beyond, a)
	var reach := maxf(REC_DAMP * lookahead, a_off / tan(REC_ANGLE_OFF) + (a - a_off) / tan(REC_ANGLE_ROAD))
	reach = minf(reach, maxf(lookahead, REC_ENTRY_SHARE * meters_to_entry()))
	if reach > lookahead:
		reach = minf(reach, maxf(lookahead, straight_reach(reach + lookahead * 0.35) - lookahead * 0.35))
	var center := lerpf(lookahead, reach, w)
	if center <= lookahead + 0.01:
		return Vector2.INF
	return aim(center - lookahead * 0.35, center + lookahead * 0.35)

func straight_reach(limit: float) -> float:
	# Meter voraus bis zum Kurveneingang: bis sich die Linie gegenüber ihrer Richtung am Cursor (über ~2 m) um REC_TURN gedreht hat.
	var last := route.size() - 1
	if cursor >= last:
		return 0.0
	var dir0 := (Vector2(route[mini(cursor + 3, last)].p) - Vector2(route[cursor].p)).angle()
	var dist := 0.0
	var i := cursor
	while i < last and dist < limit:
		var a: Vector2 = route[i].p
		var b: Vector2 = route[i + 1].p
		if absf(wrapf((b - a).angle() - dir0, -PI, PI)) > REC_TURN:
			break
		dist += a.distance_to(b)
		i += 1
	return minf(dist, limit)

func meters_to_entry(decks := true) -> float:
	# Meter bis zur nächsten Einfahrt, vor der das Auto auf seiner Linie sein muss (Circuit.momentum_entries; ein Wippen-Deck nur, wenn
	# die eigene Linie in dieser Runde über die Abkürzung führt; decks = false: nur Schwungzonen).
	var best := INF
	for e in track.momentum_entries():
		var k := int(e[1])
		if k >= 0 and (not decks or not takes_shortcut(k)):
			continue
		var d := (float(e[0]) - progress) * track.length if track.open else fposmod(float(e[0]) - progress, 1.0) * track.length
		if d >= 0.0:
			best = minf(best, d)
	return best

func on_ramp() -> bool:
	# Auf einer Schanze zwischen ihrem Fuß (der Einfahrt in momentum_entries) und der Absprungkante: Auch dort zählt nur noch Tempo.
	for r in track.ramps:
		if fposmod(track.unit(progress) - float(r.s), 1.0) * track.length <= float(r.length):
			return true
	return false

func line_phase() -> float:
	# Streckenanteil des Autos im Bezug seiner eigenen Linie (Hysterese an Abkürzungen): Hauptstrecke und Pfad sind verschieden
	# parametriert (Kinder: bis 9,9 m Unterschied). Nach der bloßen Lage wechselte der Bezug an Abzweig, Kreuzung und Einmündung hin und her,
	# der Fortschritt sprang dabei bis 16,7 m in einem Takt. Führt die Linie über den Pfad, bleibt er der Bezug, solange das Auto in dessen
	# Korridor ist; führt sie über die Hauptstrecke, bleibt diese es, solange das Auto auf ihrer Fahrbahn ist.
	if not track.shortcuts.is_empty():
		var k := int(route[cursor].get("sc", -1))
		if k >= 0:
			var on := track.shortcut_on(pos, k)
			if not on.is_empty() and float(on.u) < 0.999:
				return float(on.s)
		else:
			var q := track.query_branch(pos, previous_phase)
			if float(q.distance) <= track.hw(float(q.s)):
				return track.main_phase_near(pos, previous_phase, 0.08)
	return track.phase_near(pos, previous_phase, 0.08)

func takes_shortcut(k: int) -> bool:
	# Führt die eigene Linie in der laufenden Runde über die Abkürzung k? (Linienpunkt in der Mitte ihres Streckenbereichs, Binärsuche.)
	var sc: Dictionary = track.shortcuts[k]
	var probe := floorf(maxf(progress, 0.0)) + (float(sc.from) + float(sc.to)) * 0.5
	var lo := 0
	var hi := route.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if float(route[mid].s) < probe:
			lo = mid
		else:
			hi = mid
	return int(route[hi].get("sc", -1)) == k

static func friction_circle(x: float, y: float, cap: float) -> Vector2:
	# Reibkreis einer Achse: Wunschkraft (längs x, quer y) auf die Haftgrenze kürzen, Richtung bleibt. Mehr Längskraft lässt so
	# weniger Seitenführung übrig.
	var m := sqrt(x * x + y * y)
	return Vector2(x, y) * (cap / m) if m > cap else Vector2(x, y)

func score_drift(dt: float) -> void:
	# Punkte = Driftwinkel (Grad) × Tempo × Zeit × Multiplikator. Der Multiplikator wächst mit der Dauer eines
	# durchgehenden Drifts (bis ×4). Die Punkte des laufenden Drifts (Kette, drift_chain) sind erst sicher, wenn er endet
	# (Multiplikator wieder ×1): Berührt das Auto die Fahrbahnbegrenzung, sind die Kette und 60 Punkte weg; dreht es sich
	# (über 90° quer, DRIFT_SPIN), ist die Kette weg. Danach beginnt der Multiplikator wieder bei ×1.
	# Seit 15.10.2026 (Gegenprüfung des Profi-Drifters): Vorher kostete eine Wand nur 60 Punkte und ein Dreher nichts – eine grob
	# zu schnell gezeichnete Linie (überall 21 m/s) schaffte mit 2–3 Wänden, Drehern und 10 m Abweichung alle drei Stufen.
	var speed := velocity.length()
	var angle := 0.0
	if speed > 1.0:
		angle = absf(wrapf(velocity.angle() - heading, -PI, PI))
	drift_angle = rad_to_deg(angle)
	if not airborne and speed > 6.0 and angle > deg_to_rad(12.0) and angle < deg_to_rad(75.0):
		drift_time += dt
		drift_multiplier = minf(4.0, 1.0 + drift_time * 0.6)
		var gain := drift_angle * speed * dt * 0.25 * drift_multiplier
		drift_score += gain
		drift_chain += gain
	else:
		drift_time = maxf(0.0, drift_time - dt * 3.0)
		if drift_time <= 0.0:
			drift_multiplier = 1.0
			drift_chain = 0.0
	if speed > 2.0 and angle > DRIFT_SPIN and drift_chain > 0.0:
		drift_score = maxf(0.0, drift_score - drift_chain)
		chain_lost += 1
		drift_chain = 0.0
		drift_multiplier = 1.0
		drift_time = 0.0
	var q := track.query_branch(pos, previous_phase)
	var touching := float(q.distance) > track.hw(float(q.s)) - 0.5
	if touching and not wall_contact:
		wall_hits += 1
		if drift_chain > 0.0:
			chain_lost += 1
		drift_score = maxf(0.0, drift_score - drift_chain - 60.0)
		drift_chain = 0.0
		drift_multiplier = 1.0
		drift_time = 0.0
	wall_contact = touching

func beyond_edge(margin: float) -> bool:
	# Mehr als margin jenseits des Fahrbahnrands (Breitenprofil der Strecke, auch auf Abzweigen)?
	var q := track.query_branch(pos, previous_phase)
	return float(q.distance) > track.hw(float(q.s)) + margin

func update_height(ph: float, dt: float) -> void:
	# Senkrechte Bewegung: am Boden folgt z der Fahrbahn; fällt der Boden schneller weg als der freie Fall
	# (Schanzenkante, Kuppe, Lücke), hebt das Auto mit seiner senkrechten Geschwindigkeit ab.
	var was_deck := deck
	deck = deck_under(pos)
	var ground := deck.deck_y(deck.local(pos).x) if deck != null else (track.terrain_height(pos) if on_shortcut else track.ground_height(ph))
	if not airborne and not in_loop and deck == null and not on_shortcut and edge_check(ph, ground):
		return
	if airborne:
		vz -= GRAVITY * dt
		z += vz * dt
		air_time += dt
		if z <= ground:
			if deck == null and not on_shortcut and track.in_gap(previous_phase) and not track.in_gap(ph):
				# Landelippe: erster Takt hinter der Lücke, die Fahrbahn liegt mehr als "lip" über dem Auto -> Stirnseite.
				var lip := track.gap_lip(previous_phase)
				if lip >= 0.0 and ground - z > lip:
					lip_hit = velocity.length()
					obstacle_hit = maxf(obstacle_hit, lip_hit)
					obstacle_kind = "mauer"
					crashed = true
					velocity = Vector2.ZERO
					return
			airborne = false
			landing = LANDING_TIME
			# Harte Landung kostet etwas Tempo – gemessen an der senkrechten Geschwindigkeit relativ zur Fahrbahn (Gefälle!).
			var vz_road := ground_rate(ph, dt)
			velocity *= clampf(1.0 + (vz - vz_road) * 0.01, 0.85, 1.0)
			z = ground
			vz = vz_road
		elif z < (track.terrain_height(pos) if on_shortcut or deck != null else track.base_height(ph)) - 3.0:
			crashed = true
		return
	if deck != null and was_deck != deck:
		# Auffahren aufs Deck (Kante <= edge_ok, seesaw_contact hat Höheres abgefangen): Höhe übernehmen, kein Katapult über die
		# Steigratenregel; eine spürbare Stufe kostet etwas Tempo und Haftung.
		if ground - z > 0.05:
			velocity *= 0.96
			landing = maxf(landing, 0.15)
		z = ground
		vz = deck.deck_vy(deck.local(pos).x)
		return
	var follow := (ground - z) / dt
	# Abheben nur, wenn der Boden deutlich (> 5 cm) unter die Flugbahn wegfällt; kleinere Knicke schluckt die Federung.
	var ballistic := z + vz * dt - 0.5 * GRAVITY * dt * dt
	if ground < ballistic - 0.05:
		airborne = true
		vz -= GRAVITY * dt
		z += vz * dt
		return
	# Steigrate begrenzen: Sprünge im Höhenprofil dürfen das Auto nicht katapultieren.
	vz = clampf(follow, -25.0, 25.0)
	z = ground

var fall_speed := 0.0      # nur Darstellung: Absturz ins Tal / von der Brücke
var deck: Seesaw = null    # Wippe, auf deren Deck das Auto gerade steht (Boden = Deck)
var on_shortcut := false   # auf dem Pfad einer Abkürzung: Boden = Gelände, kein Randabsturz
var edge_hit := 0.0        # Stoß an der Einfahrtskante einer Wippe (m/s; Ton/Funken)
var lip_hit := 0.0         # an der Landelippe einer Lücke zerschellt (Tempo beim Aufprall), 0 = nein

func ground_rate(ph: float, dt: float) -> float:
	# Senkrechte Geschwindigkeit der Fahrbahn unter dem Auto bei seiner Bewegung (Landung auf Gefälle übernimmt sie).
	if deck != null:
		return sin(deck.phi) * velocity.dot(deck.u) + deck.deck_vy(deck.local(pos).x)
	if on_shortcut:
		return (track.terrain_height(pos + velocity * dt) - track.terrain_height(pos)) / dt
	var u := velocity.dot(track.tangent(ph))
	return (track.ground_height(ph + u * dt / track.length) - track.ground_height(ph)) / dt

func deck_under(p: Vector2) -> Seesaw:
	# Wippe, deren Deck an p die Bodenhöhe bildet: in der Grundfläche und das Auto nicht darunter (z ≥ y − LOAD_TOL).
	for wv in seesaws:
		var w: Seesaw = wv
		if w.inside(p):
			var y: float = w.deck_y(w.local(p).x)
			if z >= y - Seesaw.LOAD_TOL:
				return w
	return null

func seesaw_contact(before_pos: Vector2) -> void:
	# Wippe als Körper: Einfahrtskante (Stoß bzw. Wrack je nach Kantenhöhe), Seiten und hohes Ende als festes Rechteck für Autos
	# unterhalb der Deckhöhe. Auffahren (Kante <= edge_ok) übernimmt update_height.
	var forward := Vector2.from_angle(heading)
	for wv in seesaws:
		var w: Seesaw = wv
		var l: Vector2 = w.local(pos)
		var lb: Vector2 = w.local(before_pos)
		var front: Vector2 = w.local(pos + forward * CAR_REACH)
		var in_rect := absf(l.x) <= w.half_len and absf(l.y) <= w.half_w
		var front_hits := not in_rect and absf(front.x) <= w.half_len and absf(front.y) <= w.half_w and l.x < -w.half_len
		if not in_rect and not front_hits:
			if not airborne and absf(l.y) > w.half_w and absf(l.x) <= w.half_len:
				# Seitlich neben dem Deck: Bug und Heck bleiben außerhalb der Seitenwand, wo das Deck höher steht als das Auto. Bisher hielt nur
				# die Wagenmitte Abstand: Ein Auto, das das Deck verfehlt hatte und an der Seite entlang zur Linie oben einlenkte, schob den Bug
				# bis 1 m unter das Deck, verkeilte sich dort am Stiftende und kam auch rückwärts nicht mehr frei (15.10.2026).
				# Der Stoß wirkt an der Berührstelle wie an einem Hindernis (Abprall, Reibung, Drehimpuls, Wrack über WRECK_SPEED); zuerst
				# schluckte die Regel jeden Stoß lautlos, auch mit 24 m/s seitlich ins Lineal.
				for end in [CAR_REACH, -CAR_REACH]:
					var p: Vector2 = w.local(pos + forward * end)
					if absf(p.x) <= w.half_len and absf(p.y) < w.half_w and w.deck_y(p.x) - z > w.edge_ok:
						var side := Vector2(-w.u.y, w.u.x) * signf(l.y)
						pos += side * (w.half_w - absf(p.y) + 0.02)
						touched = true
						touch_kind = "lineal"
						touch_index = -1
						# Nur der Bug zählt als Hängen; das Heck beendet hier kein Zurücksetzen (touch_rear): Beim neuen Anlauf rollt das Auto mit
						# dem Heck an der Seitenwand entlang zurück.
						touch_front = touch_front or end > 0.0
						var r: Vector2 = forward * end
						var vc := velocity + Vector2(-r.y, r.x) * yaw
						var vn := vc.dot(side)
						if vn < 0.0:
							var rn := r.x * side.y - r.y * side.x
							var j := -1.3 * vn / (1.0 + rn * rn / CAR_INERTIA)
							velocity += side * j
							yaw = clampf(yaw + rn * j / CAR_INERTIA, -3.0, 3.0)
							var t := Vector2(-side.y, side.x)
							var vt := vc.dot(t)
							velocity -= t * signf(vt) * minf(absf(vt) * 0.22, WALL_FRICTION * j)
							obstacle_hit = maxf(obstacle_hit, -vn)
							obstacle_kind = "lineal"
							if -vn > WRECK_SPEED:
								wreck_cause = "Aufprall lineal"
								wreck()
								return
						break
			continue
		if in_rect and deck == w:
			continue
		var a := -w.half_len if front_hits else l.x
		var step_up: float = w.deck_y(a) - z
		if step_up <= w.edge_ok or (airborne and in_rect and step_up <= Seesaw.LOAD_TOL):
			continue
		var speed := velocity.length()
		if not airborne and (front_hits or (lb.x < -w.half_len and absf(lb.y) <= w.half_w + 0.3)):
			# Stirnkante an der Einfahrt: bis edge_wreck harter Stoß (Längstempo 0, das Lineal kommt durch das Gegengewicht zurück),
			# darüber Wrack – der Crash für Nachfolger, die zu dicht hinter einem Vordermann einfahren.
			edge_hit = speed
			obstacle_hit = maxf(obstacle_hit, speed)
			obstacle_kind = "lineal"
			if step_up > w.edge_wreck:
				wreck()
				return
			touched = true
			touch_front = true
			touch_index = -1
			touch_kind = "lineal"
			var back := (front.x + w.half_len + 0.02) if front_hits else (l.x + w.half_len + 0.02 + CAR_REACH)
			pos -= w.u * back
			var along := velocity.dot(w.u)
			if along > 0.0:
				velocity -= w.u * along
			continue
		# Seite oder hohes Ende: wie eine Mauer (Abprall, Wrack über WRECK_SPEED).
		var dx := w.half_len - absf(l.x)
		var dy := w.half_w - absf(l.y)
		var n: Vector2 = w.u * signf(l.x if l.x != 0.0 else 1.0) if dx < dy else Vector2(-w.u.y, w.u.x) * signf(l.y if l.y != 0.0 else 1.0)
		pos += n * (minf(dx, dy) + 0.02)
		touched = true
		touch_front = true
		touch_index = -1
		touch_kind = "lineal"
		var vn := velocity.dot(n)
		if vn < 0.0:
			velocity -= n * vn * 1.3
			obstacle_hit = maxf(obstacle_hit, -vn)
			obstacle_kind = "lineal"
			if -vn > WRECK_SPEED:
				wreck()
				return

func edge_check(ph: float, road: float) -> bool:
	# Neben der Fahrbahn fällt das Gelände steil ab (Brücke, Bergstraße, Steilküste)?
	# Mit Leitplanke: Abprallen, ab BREAK_SPEED senkrecht zur Planke bricht sie -> Absturz. Ohne: Absturz.
	var q := track.query_branch(pos, previous_phase)
	edge_q = q
	var distance := float(q.distance)
	var edge := track.hw(float(q.s)) + 0.7
	if distance <= edge:
		return false
	var drop := road - track.terrain_height(pos)
	if drop < 2.5:
		return false
	var normal: Vector2 = (pos - Vector2(q.point)).normalized()
	var t := track.tangent(float(q.s))
	var side := normal.dot(Vector2(-t.y, t.x))
	var impact := velocity.dot(normal)
	if track.guardrail_at(float(q.s), side) and impact < Circuit.BREAK_SPEED:
		pos = Vector2(q.point) + normal * edge
		if impact > 0.0:
			velocity -= normal * impact * 1.4
		velocity *= 0.8
		guard_hit = impact
		return false
	crashed = true
	broke_rail = track.guardrail_at(float(q.s), side)
	return true

var guard_hit := 0.0       # Aufprallgeschwindigkeit an der Leitplanke (Funken/Geräusch), vom Aufrufer zurückgesetzt
var edge_q := {}           # Fahrbahnabfrage (query_branch) aus edge_check dieses Takts …
var near_q := {}           # … und des Vortakts (für recovery_target; leer, wenn edge_check nicht lief)
var broke_rail := false

func enter_loop(loop: Dictionary) -> void:
	in_loop = true
	rear_spin = 0.0
	loop_theta = 0.0
	loop_radius = float(loop.radius)
	loop_forward = track.tangent(float(loop.s))
	loop_speed = maxf(0.0, velocity.dot(loop_forward))
	var center := track.at(float(loop.s))
	var side := Vector2(-loop_forward.y, loop_forward.x)
	loop_entry = clampf((pos - center).dot(side), -Circuit.HALF_WIDTH, Circuit.HALF_WIDTH)
	loop_origin = center + loop_forward * (pos - center).dot(loop_forward)
	heading = loop_forward.angle()

func step_loop(dt: float) -> void:
	# Autonome Durchfahrt mit dem Schwung: tangentiale Verzögerung durch Schwerkraft und Luftwiderstand.
	# Vor der Senkrechten (θ < 90°) drückt die Bahn immer an: reicht der Schwung nicht, rollt das Auto rückwärts
	# wieder hinunter. Jenseits davon fällt es ab, sobald die Anpresskraft (v²/R + g·cos θ) fehlt.
	loop_speed += (-GRAVITY * sin(loop_theta) - 0.010 * loop_speed * absf(loop_speed)) * dt
	loop_theta += loop_speed / loop_radius * dt
	var normal := loop_speed * loop_speed / loop_radius + GRAVITY * cos(loop_theta)
	if loop_theta > PI * 0.5 and (normal < 0.0 or loop_speed < 0.5):
		crashed = true
		in_loop = false
		loop_fall = true
		return
	if loop_theta <= 0.0:
		# Rückwärts aus der Einfahrt gerollt: ausgeschieden, das Auto bleibt unten stehen.
		in_loop = false
		crashed = true
		rolled_back = true
		loop_theta = 0.0
		pos = loop_origin + Vector2(-loop_forward.y, loop_forward.x) * track.loop_lateral(0.0, loop_entry)
		z = track.ground_height(previous_phase)
		velocity = Vector2.ZERO
		return
	var forward := loop_forward
	var side := Vector2(-forward.y, forward.x)
	pos = loop_origin + forward * loop_radius * sin(loop_theta) + side * track.loop_lateral(loop_theta, loop_entry)
	z = track.base_height(previous_phase) + loop_radius * (1.0 - cos(loop_theta))
	if loop_theta >= TAU:
		in_loop = false
		pos = loop_origin - side * Circuit.LOOP_LANE
		z = track.ground_height(previous_phase)
		velocity = forward * loop_speed
		yaw = 0.0

const AVOID_PREVIEW := 1.5     # s Vorausschau: Schwungzone oder Kurve so weit voraus -> Versatz schon zurücknehmen
const AVOID_RETURN := 1.5      # m/s Rücknahme des Versatzes (Aufbau 3 m/s · Nässe)
const AVOID_K0 := 1.0 / 40.0   # Krümmung, bis zu der voll ausgewichen wird (Radius 40 m) ...
const AVOID_K1 := 1.0 / 18.0   # ... und ab der gar nicht mehr (Radius 18 m)
const AVOID_EDGE := 1.3        # m: Zielspur bleibt so weit innerhalb des Fahrbahnrands
const AVOID_USE0 := 0.45       # Anteil der Querhaftung, bis zu dem voll ausgewichen wird ...
const AVOID_USE1 := 0.8        # ... und ab dem gar nicht mehr

static func update_avoidance(cars: Array, dt: float, humans: Array = []) -> void:
	# Gegner weichen Autos aus, die schräg vor oder neben ihnen fahren. Menschen fahren ihre Linie: humans[i] = true (RaceField.human_mask);
	# ohne Liste ist wie bisher Index 0 der Mensch.
	# Kein Versatz gegen Autos auf einer anderen Ebene (|Δz| > 1 m), in Schwungzonen (Anlauf von Sprung und Looping), auf erhöhter
	# Fahrbahn und auf Wippen-Abkürzungen: dort kostet jeder Schlenker Schwung oder führt über die Kante.
	# Bei Nässe und Schnee kleinere und sanftere Schlenker (sonst schaukelt sich das Zurücklenken bis neben die Fahrbahn auf).
	# Seit 03.10.2026 (Prüfung Nachtschicht): Versatz nur auf Geraden (in Kurven dreht der verschobene Zielpunkt das Auto über, am Kurvenausgang
	# folgt mit Vollgas ein Heckrutscher bis an Wall oder Absperrung), nie über den Fahrbahnrand hinaus, und vor einer Schwungzone schon
	# AVOID_PREVIEW s vorher sanft zurück auf 0 (abruptes Zurücksetzen am Zonenbeginn ließ das Auto bis zum Absprung pendeln).
	var wet := weather_grip * weather_grip
	for i in range(cars.size()):
		if (i == 0) if humans.is_empty() else (i < humans.size() and bool(humans[i])):
			continue
		var me: RaceVehicle = cars[i]
		var goal := 0.0
		var forward := Vector2.from_angle(me.heading)
		var speed := me.velocity.length()
		var ahead_s := me.progress + (speed * AVOID_PREVIEW + 3.0) / me.track.length
		if me.track.calm_at(me.progress) or me.track.calm_at(ahead_s) or (not me.seesaws.is_empty() and me.on_seesaw_route()):
			me.avoid_offset = move_toward(me.avoid_offset, 0.0, dt * AVOID_RETURN)
			continue
		var bend := 0.0
		for k in range(3):
			bend = maxf(bend, me.track.curvature(me.track.unit(lerpf(me.progress, ahead_s, k * 0.5))))
		var straight := clampf(1.0 - (bend - AVOID_K0) / (AVOID_K1 - AVOID_K0), 0.0, 1.0)
		# Haftungsreserve: braucht die Kurve schon einen großen Teil der Querhaftung (v²·k gegen Haftung des Autos auf Belag und Wetter),
		# bleibt für einen Schlenker nichts übrig (Serra Regen, R 40 m mit 15 m/s: Schlenker -> Notbremsung -> Abflug).
		var road_grip: float = float(SURFACE_GRIP.get(me.track.road, 1.0)) * weather_grip
		var usage := speed * speed * bend / maxf(me.grip * road_grip * 0.8, 1.0)
		straight = minf(straight, clampf((AVOID_USE1 - usage) / (AVOID_USE1 - AVOID_USE0), 0.0, 1.0))
		for j in range(cars.size()):
			if j == i or cars[j].finish_time >= 0.0:
				continue
			if absf(cars[j].z - me.z) > 1.0:
				continue
			var d: Vector2 = cars[j].pos - me.pos
			var ahead := d.dot(forward)
			var side := d.dot(forward.orthogonal())
			if ahead > -0.6 and ahead < 4.5 and absf(side) < 1.9:
				var sgn := signf(side if absf(side) > 0.05 else 1.0)
				# eingeklemmt (links und rechts je ein Auto): Spur halten statt in den anderen Nachbarn zu lenken
				if goal != 0.0 and signf(goal) == sgn:
					goal = 0.0
					break
				goal = -sgn * 1.7 * wet * straight
		# Fahrbahnrand: +Versatz verschiebt das Ziel zur negativen Querlage (Circuit.at). Spur der Route − Versatz bleibt innerhalb hw − AVOID_EDGE.
		var lane := float(me.route[me.cursor].get("o", 0.0))
		var room := maxf(0.0, me.track.hw(me.track.unit(me.progress)) - AVOID_EDGE)
		goal = clampf(goal, lane - room, lane + room)
		me.avoid_offset = move_toward(me.avoid_offset, goal, dt * (3.0 * wet if absf(goal) > absf(me.avoid_offset) else AVOID_RETURN))

func on_seesaw_route() -> bool:
	# KI-Route nimmt in dieser Runde eine Wippen-Abkürzung und das Auto ist zwischen 12 m vor dem Abzweig und der Einmündung.
	for wv in seesaws:
		var w: Seesaw = wv
		if w.shortcut < 0 or w.shortcut >= track.shortcuts.size():
			continue
		var sc: Dictionary = track.shortcuts[w.shortcut]
		var x := track.unit(progress)
		if x < float(sc.from) - Circuit.SHORTCUT_BLEND / track.length or x > float(sc.to):
			continue
		var lap := floorf(progress)
		var idx := clampi(int((lap + float(sc.from)) * track.span()) + 2, 0, route.size() - 1)
		if int(route[idx].get("sc", -1)) == w.shortcut:
			return true
	return false

static func resolve_contact(a: RaceVehicle, b: RaceVehicle) -> float:
	# Rückgabe: Aufprallgeschwindigkeit (m/s) für Funken/Geräusch; 0 = keine Berührung. Nur Information,
	# die Simulation selbst bleibt unverändert.
	var delta := b.pos - a.pos
	var dist := delta.length()
	if dist > 1.15 or dist < 0.001:
		return 0.0
	if absf(a.z - b.z) > 1.0 or a.crashed or b.crashed or a.in_loop or b.in_loop:
		return 0.0   # übereinander (Sprung über die Kreuzung, Looping) oder ausgeschieden: keine Berührung
	var normal := delta / dist
	var overlap := (1.15 - dist) * 0.5
	a.pos -= normal * overlap
	b.pos += normal * overlap
	var closing := (b.velocity - a.velocity).dot(normal)
	if closing < 0.0:
		var impulse := -closing * 0.65
		a.velocity -= normal * impulse
		b.velocity += normal * impulse
		return -closing
	return 0.0

# ---------- Zusammenstoß mit Hindernissen (Häuser, Absperrungen, Laternen, Bäume, parkende Autos …) ----------
# Das Auto ist zwei Kreise (vorn, hinten). Der Stoß wirkt an der Berührstelle: Abprall entlang der Normalen (Rückprall je nach
# Art), Reibung quer dazu und ein Drehimpuls um die Hochachse – schräge Treffer drehen das Auto. Bleibt das Auto an einem
# Hindernis hängen, setzt es zurück und versucht es erneut (update_hang); führt die Linie hindurch, ist es ein Wrack.
const CAR_REACH := 1.25
const CAR_RADIUS := 0.95
const CAR_INERTIA := 1.8
const WRECK_SPEED := 17.0      # m/s senkrecht in eine Wand oder ein Auto: Totalschaden
const WALL_FRICTION := 0.6     # Reibbeiwert Auto–Hindernis (Tangentialstoß höchstens μ · Normalstoß)
# Schlanke Hindernisse (Kreis bis 0,3 m: Randpfosten, Masten, Poller) prüft zusätzlich ein dritter Kreis in der Wagenmitte: Zwischen den
# beiden Kreisen (±CAR_REACH) bleibt eine Taille, durch die ein seitlich rutschendes Auto sonst einen Pfosten „hindurchließ“ (03.10.2026).
const THIN_OBSTACLE := 0.3
# Holzpfosten neben der Schotterpiste (Hindernis "w") geben nach: Ein Stoß mit mehr als POST_BREAK_SPEED senkrecht bricht den Pfosten;
# das kostet das Auto die Bruchenergie ½·POST_BREAK_SPEED² je Masse (es behält √(vn² − V²) seiner Normalgeschwindigkeit, fährt also
# hindurch). Schwächere Stöße prallen ab wie an einem Mast und summieren sich (Normalstoß je Masse); ab POST_LOAD gibt der Pfosten
# ebenfalls nach – wer langsam dagegen drückt, schiebt ihn um, statt sich festzufahren. Umgefallene Pfosten (post_state, je Rennen
# von RaceField für alle Autos geteilt) haben keinen Körper mehr; World legt sie im Bild um. Feldsteine bleiben fest.
const POST_BREAK_SPEED := 2.0
const POST_LOAD := 2.5
var post_state: Dictionary = {}     # Hindernis-Index -> {load: Normalstoß bisher (m/s), down: umgefallen, dir: Fallrichtung}
var obstacle_hit := 0.0         # stärkster Aufprall (m/s) seit dem letzten Abholen, für Geräusch/Funken (Aufrufer setzt zurück)
var obstacle_kind := ""
var wrecked := false
var wreck_cause := ""       # nur Auswertung (Feldtest): Aufprall oder Festhängen und woran

# ---------- Festhängen und Freifahren (15.10.2026) ----------
# Hängt das Auto an einem Hindernis, einer Wand oder der Seite einer Wippe (angelehnt und in HANG_TIME keinen Meter vorangekommen), setzt
# es zurück: rückwärts, die Nase dreht dabei zum Ziel auf der Linie, bis es ausgerichtet ist (Weg und Zeit begrenzt), dann wieder vorwärts
# mit Rückkehr auf die Linie (bis es am Hängepunkt vorbei ist, direkt zum nahen Zielpunkt). Neben einem verfehlten Wippen-Deck setzt es
# stattdessen bis vor die Einfahrt zurück und nimmt neuen Anlauf (deck_retry_point). Bisher drückte es weiter gegen das Hindernis und war
# nach 3 s ein Wrack, auch wo ein kurzes Zurücksetzen genügt hätte (Wand längs nach einem Dreher, Stiftende neben dem Lineal,
# Reifenstapel). Führt die Linie wirklich durch das Hindernis (line_blocked), hängt das Auto an derselben Stelle wieder: nach FREE_TRIES
# erfolglosen Versuchen oder STUCK_TIME ohne FREE_NET Nettofortschritt ist es ein Wrack. Sonst (Baum- und Steinfelder neben der Piste, das
# Lineal) versucht es weiter, bis FREE_TRIES_OPEN bzw. STUCK_TIME_OPEN – zuerst war es auch dort nach zwei Versuchen ein Wrack, wo es vorher
# an den Steinen entlang wieder herauskam. Als Hängen zählt nur Bug- oder Seitenkontakt: Nach dem Zurücksetzen stand das Auto oft noch mit dem
# Heck an einem Baum, und das zählte schon als nächstes Hängen. Der Spieler fährt ebenso (die Linie ist der Plan; Zurücksetzen gehört zum
# Fahren, nicht zur Linie).
const HANG_TIME := 0.6         # s angelehnt …
const HANG_GAIN := 1.0         # … ohne so viele Meter Fortschritt: zurücksetzen
const REV_SPEED := 3.0         # m/s rückwärts
const REV_DRIVE := 4.0         # m/s² Rückwärtsgang
const REV_MIN := 1.2           # m mindestens zurück …
const REV_ALIGN := 0.3         # rad … und die Nase so genau zum Ziel, dann vorwärts
const REV_MAX := 5.0           # m höchstens zurück
const REV_TIME := 3.0          # s höchstens
const REV_GOAL := 2.0          # m voraus auf der Linie liegt das Ziel, zu dem die Nase beim Zurücksetzen dreht …
const REV_GOAL_STEP := 4.0     # … je weiterem Versuch so viel weiter
const REV_DECK := 8.0          # m vor der Deck-Einfahrt nimmt ein Auto neuen Anlauf, das das Deck verfehlt hat …
const REV_DECK_TIME := 10.0    # s … und so lange setzt es dafür höchstens zurück
const FREE_TRIES := 2          # Versuche, bevor ein erneutes Hängen das Aus ist (Linie durchs Hindernis) …
const FREE_TRIES_OPEN := 5     # … sonst
const FREE_NET := 2.0          # m Nettofortschritt beenden eine Hängeserie
const STUCK_TIME := 6.0        # s Hängeserie ohne FREE_NET Nettofortschritt: Wrack (Linie durchs Hindernis) …
const STUCK_TIME_OPEN := 20.0  # … sonst
const BLOCK_AHEAD := 15.0      # m der Linie ab dem Fortschrittscursor, die line_blocked prüft …
const BLOCK_RADIUS := 0.6      # … und so nah am Hindernis gilt sie als hindurchführend (halbe Wagenbreite abzüglich Lenkspiel)
var touched := false           # in diesem Takt an einem Hindernis oder einer Wippenseite angelegen
var touch_rear := false        # … mit dem hinteren Kreis (beendet das Zurücksetzen)
var touch_front := false       # … mit dem vorderen oder mittleren Kreis bzw. seitlich (zählt als Hängen)
var touch_index := -1          # Hindernis (track.obstacles) des letzten Bug- oder Seitenkontakts; -1 Wippe
var touch_kind := ""
var last_touch := 9.0          # s seit der letzten Berührung
var hang := 0.0
var hang_from := 0.0           # Fortschritt beim Anlehnen
var reversing := false
var rev_time := 0.0
var rev_from := Vector2.ZERO
var rev_goal := Vector2.INF    # Ziel des Heck-voran-Zurücksetzens (Deck verfehlt), sonst INF
var free_series := false
var free_tries := 0
var free_mark := 0.0           # Fortschritt beim ersten Hängen der Serie
var free_clock := 0.0

func collide_obstacles(_dt: float) -> void:
	if track.obstacles.is_empty():
		return
	var forward := Vector2.from_angle(heading)
	for off in [CAR_REACH, -CAR_REACH, 0.0]:
		var c: Vector2 = pos + forward * off
		for idx in track.obstacles_near(c):
			var o: Dictionary = track.obstacles[idx]
			if off == 0.0 and float(o.get("r", 1.0)) > THIN_OBSTACLE and str(o.k) != "feldstein":
				# Wagenmitte nur gegen schlanke Hindernisse (Pfosten, Masten) und die Feldsteine der Pfostenreihe (r 0,38): sie passten
				# sonst zwischen die beiden Kreise (Prüfung 03.10.: seitlich rutschend lag ein Feldstein bis 0,08 m an der Wagenachse).
				continue
			var wooden := o.has("w")
			if wooden and bool(post_state.get(idx, {}).get("down", false)):
				continue      # umgefahrener Pfosten
			if o.has("b"):
				# Hindernis mit Unterkante (Bruchwand, Wall auf dem Damm, Stift): nur bei Höhenüberlappung, am Boden wie in der Luft.
				if not Circuit.obstacle_reaches(o, z):
					continue
			elif airborne and z > float(o.y):
				continue
			var hit := track.obstacle_contact(o, c, CAR_RADIUS)
			if hit.z <= 0.0:
				continue
			touched = true
			if off < 0.0:
				touch_rear = true
			else:
				touch_front = true
				touch_index = idx
				touch_kind = str(o.k)
			var n := Vector2(hit.x, hit.y)
			if wooden:
				var r0 := c - pos
				var vc0 := velocity + Vector2(-r0.y, r0.x) * yaw
				if -vc0.dot(n) > POST_BREAK_SPEED:
					knock_post(idx, o, n, r0, vc0)
					continue
			pos += n * hit.z
			c += n * hit.z
			var r := c - pos
			var vc := velocity + Vector2(-r.y, r.x) * yaw
			var vn := vc.dot(n)
			if vn >= 0.0:
				continue
			var soft: bool = str(o.k) in Circuit.SOFT_OBSTACLES
			var e := 0.12 if soft else 0.3
			var rn := r.x * n.y - r.y * n.x
			var j := -(1.0 + e) * vn / (1.0 + rn * rn / CAR_INERTIA)
			velocity += n * j
			yaw = clampf(yaw + rn * j / CAR_INERTIA, -3.0, 3.0)
			# Reibung entlang der Wand nach Coulomb: höchstens μ·Normalstoß, gedeckelt auf den bisherigen Anteil der Tangentialgeschwindigkeit.
			# Ein harter Treffer bremst wie bisher; ein Auto, das nur anliegt und weiterschiebt, schrammt entlang statt festzukleben (Prüfung
			# 03.10.: mit dem festen Anteil je Takt und −10 % je Takt an weichen Hindernissen blieben Gegner mit Vollgas bei 0,2 m/s an
			# Absperrung und Wall hängen und wurden nach STUCK_TIME zum Wrack).
			var t := Vector2(-n.y, n.x)
			var vt := vc.dot(t)
			velocity -= t * signf(vt) * minf(absf(vt) * (0.35 if soft else 0.22), WALL_FRICTION * j)
			if soft:
				# Weiche Hindernisse schlucken beim Aufprall Energie (bis 10 % ab 3 m/s Stoß), nicht beim bloßen Anliegen.
				velocity *= 1.0 - 0.1 * clampf(-vn / 3.0, 0.0, 1.0)
			if -vn > obstacle_hit:
				obstacle_hit = -vn
				obstacle_kind = str(o.k)
			if wooden:
				var st: Dictionary = post_state.get(idx, {"load": 0.0, "down": false})
				st.load = float(st.load) + j
				if float(st.load) > POST_LOAD:
					st.down = true
					st.dir = -n
				post_state[idx] = st
			if not soft and -vn > WRECK_SPEED and str(o.k) in ["mauer", "auto"]:
				wreck_cause = "Aufprall " + str(o.k)
				wreck()
				return

func update_hang(dt: float) -> void:
	# Festhängen erkennen (mit Bug oder Seite angelehnt, kaum Fortschritt), Zurücksetzen auslösen, Wrack nach erfolglosen Versuchen.
	last_touch = 0.0 if touch_front else last_touch + dt
	if free_series:
		free_clock += dt
		if (progress - free_mark) * track.length > FREE_NET:
			free_series = false
			free_tries = 0
	if reversing:
		return
	if last_touch < 0.3 and not airborne:
		if hang == 0.0:
			hang_from = progress
		hang += dt
		if (progress - hang_from) * track.length > HANG_GAIN:
			hang = 0.0
	else:
		hang = 0.0
	if hang < HANG_TIME:
		return
	hang = 0.0
	if not free_series:
		free_series = true
		free_tries = 0
		free_mark = progress
		free_clock = 0.0
	if (free_tries >= FREE_TRIES or free_clock > STUCK_TIME) and (free_tries >= FREE_TRIES_OPEN or free_clock > STUCK_TIME_OPEN or line_blocked()):
		wreck_cause = "fest " + touch_kind
		wreck()
		return
	free_tries += 1
	reversing = true
	rev_time = 0.0
	rev_from = pos
	rev_goal = deck_retry_point()

func line_blocked() -> bool:
	# Führt die eigene Linie durch das Hindernis, an dem das Auto hängt (BLOCK_AHEAD m ab kurz vor dem Fortschrittscursor, BLOCK_RADIUS)? Dann
	# hilft kein weiterer Versuch. Wippen (touch_index −1) nicht: Über das Deck führt die Linie von der Einfahrt aus (deck_retry_point).
	if touch_index < 0 or touch_index >= track.obstacles.size():
		return false
	var o: Dictionary = track.obstacles[touch_index]
	var i := maxi(0, cursor - 6)
	var walked := 0.0
	while i < route.size() - 1 and walked < BLOCK_AHEAD:
		if track.obstacle_contact(o, route[i].p, BLOCK_RADIUS).z > 0.0:
			return true
		walked += Vector2(route[i].p).distance_to(route[i + 1].p)
		i += 1
	return false

func knock_post(idx: int, o: Dictionary, n: Vector2, r: Vector2, vc: Vector2) -> void:
	# Holzpfosten bricht: Bruchenergie aus der Normalbewegung an der Berührstelle, Drehimpuls und Reibung wie beim Abprall.
	var vn := vc.dot(n)
	var keep := sqrt(vn * vn - POST_BREAK_SPEED * POST_BREAK_SPEED)
	var rn := r.x * n.y - r.y * n.x
	var j := (-vn - keep) / (1.0 + rn * rn / CAR_INERTIA)
	velocity += n * j
	yaw = clampf(yaw + rn * j / CAR_INERTIA, -3.0, 3.0)
	var t := Vector2(-n.y, n.x)
	var vt := vc.dot(t)
	velocity -= t * signf(vt) * minf(absf(vt) * 0.22, WALL_FRICTION * j)
	# Der Pfosten fällt in Bewegungsrichtung der Berührstelle (nur fürs Bild).
	post_state[idx] = {"load": POST_LOAD, "down": true, "dir": vc.normalized()}
	if -vn > obstacle_hit:
		obstacle_hit = -vn
		obstacle_kind = str(o.k)

func wreck() -> void:
	# Totalschaden bzw. festgefahren: das Auto bleibt stehen (kein Absturz aus dem Bild).
	crashed = true
	wrecked = true
	velocity = Vector2.ZERO
	yaw = 0.0
	rear_spin = 0.0
