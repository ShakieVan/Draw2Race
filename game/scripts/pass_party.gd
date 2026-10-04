class_name PassParty
extends RefCounted

# Mehrspieler „Weitergeben“ (M2b, docs/MULTIPLAYER_RECHERCHE.md 7): 2–4 Menschen auf EINEM Handy, ohne Netz. Hier stehen nur die
# Einstellungen der Runde und die gezeichneten Linien; Ablauf und Anzeige macht main.gd (Phasen party_setup → handover → draw →
# drawn → reveal → countdown → race → result), die Bildschirme party_hud.gd.
# Regeln (Nutzerentscheidungen 03.10.2026, Abschnitt 9):
# - Im Mehrspieler sind alle Strecken und Autos frei; danach gilt wieder der eigene Fortschritt. Die Runde schreibt NICHTS in den
#   Spielstand (Freischaltungen, Gold, Bestenliste, Geister, letzte Fahrt) – auch Namen und Auswahl bleiben nur in dieser Sitzung.
# - Gezeichnet wird nacheinander; die Linien bleiben verdeckt, bis alle fertig sind, dann erscheinen sie gemeinsam (Enthüllung).
# - Autowahl (Nutzerentscheidung 03.10.2026 nach dem ersten Test): Mehrere Spieler dürfen dasselbe Auto fahren. Jeder hat seine eigene
#   Spielerfarbe (PlayerColors, je Runde nur einmal): Lack, Schild, Lichtkranz, Turboknopf, Linie und Wertung. Gewählt wird in der
#   Garage wie im Einzelspieler (RaceHUD.garage), mit allen Autos.
# - KI auffüllen: 0 bis 4 − Menschen; Stärke nach Herausforderung wie in der Karriere. Drift-Arena: alle Menschen gleichzeitig,
#   ohne KI und ohne Berührungen, Wertung nach Punkten.
# - Startaufstellung: erstes Rennen in Spielerreihenfolge, bei der Revanche in umgekehrter Reihenfolge des letzten Ergebnisses.

const MIN_PLAYERS := 2
const MAX_PLAYERS := 4
const MAX_CARS := 4               # Autos im Feld insgesamt (wie im Einzelspieler höchstens 1 + 3)
const REVEAL_TIME := 3.0          # s: so lange sind alle Linien vor dem Start zu sehen

var players: Array[Dictionary] = []   # je Spieler {name, car, color} (color = Index in PlayerColors.PALETTE)
var track_id := "azure"
var stage := 0
var ai := 1                       # KI-Gegner
var contacts := true              # Berührungen zwischen den Autos (Drift: immer aus)
var routes: Array = []            # gezeichnete Linie je Spieler (Array[Dictionary]); leer = noch nicht gezeichnet
var turn := 0                     # Spieler, der gerade zeichnet bzw. als Nächster dran ist
var grid: Array[int] = []         # Startreihenfolge: Spielerindex je Startplatz (Menschen vorn)
var races := 0                    # gefahrene Rennen dieser Runde
var last_ranking: Array[int] = [] # Spieler in der Reihenfolge des letzten Ergebnisses (Revanche: umgekehrt aufstellen)

static func create(own_name: String, own_car: int, track := "azure", challenge := 0) -> PassParty:
	# Neue Runde: Spieler 1 mit dem gespeicherten Namen und Auto, Spieler 2 mit „Spieler 2“ und demselben Auto (ebenbürtig);
	# Farben nach Platz (PlayerColors.default_for).
	var p := PassParty.new()
	p.track_id = track
	p.stage = clampi(challenge, 0, 2)
	p.players.append({"name": ProgressStore.clean_name(own_name), "car": clampi(own_car, 0, RaceVehicle.CARS.size() - 1), "color": PlayerColors.default_for(0)})
	p.add_player()
	p.ai = p.default_ai()
	return p

func count() -> int:
	return players.size()

static var _drift_cache := {}   # Strecke -> Drift-Modus? (einmal geladen)

static func track_is_drift(id: String) -> bool:
	if not _drift_cache.has(id):
		_drift_cache[id] = Circuit.load_track(id).mode == "drift"
	return bool(_drift_cache[id])

func is_drift() -> bool:
	return track_is_drift(track_id)

func max_ai() -> int:
	return 0 if is_drift() else maxi(0, MAX_CARS - count())

func default_ai() -> int:
	# Wie in der Karriere: Herausforderung n hat n Rivalen – soweit Plätze frei sind.
	return mini(stage + 1, max_ai())

func set_stage(value: int) -> void:
	stage = clampi(value, 0, 2)
	ai = mini(ai, max_ai())

func set_track(id: String) -> void:
	track_id = id
	ai = mini(ai, max_ai())
	if is_drift():
		ai = 0

func taken_colors(except := -1) -> Array:
	# Farben der anderen Spieler (except = eigener Spielerindex).
	var out: Array = []
	for k in range(players.size()):
		if k != except:
			out.append(color_index(k))
	return out

func color_owner(c: int) -> int:
	# Spieler mit der Farbe c (-1 = frei).
	for k in range(players.size()):
		if color_index(k) == c:
			return k
	return -1

func add_player() -> bool:
	# Neuer Spieler: dasselbe Auto wie der letzte (ebenbürtig), Farbe nach Platz bzw. die nächste freie.
	if count() >= MAX_PLAYERS:
		return false
	var last := int(players[-1].car) if not players.is_empty() else 0
	players.append({"name": "", "car": last, "color": PlayerColors.free_color(PlayerColors.default_for(players.size()), taken_colors())})
	ai = mini(ai, max_ai())
	return true

func remove_player(k: int) -> bool:
	if count() <= MIN_PLAYERS or k < 0 or k >= count():
		return false
	players.remove_at(k)
	return true

func set_car(k: int, car: int) -> void:
	# Auto von Spieler k (Garage): jedes Auto, auch eines, das ein anderer schon fährt.
	players[k].car = posmod(car, RaceVehicle.CARS.size())

func set_color(k: int, wanted: int) -> void:
	# Farbe von Spieler k: die gewünschte oder, wenn ein anderer sie hat, die nächste freie.
	players[k].color = PlayerColors.free_color(wanted, taken_colors(k))

func set_name(k: int, text: String) -> void:
	players[k].name = ProgressStore.clean_name(text)

func names() -> Array[String]:
	# Anzeigenamen: leer = „Spieler n“, gleiche Namen bekommen eine Ziffer (NameTags.unique_name, wie im Netz).
	var out: Array[String] = []
	for k in range(count()):
		var wanted := ProgressStore.clean_name(str(players[k].name))
		if wanted == "":
			wanted = "Spieler %d" % (k + 1)
		out.append(NameTags.unique_name(wanted, out))
	return out

func color_index(k: int) -> int:
	return posmod(int(players[k].get("color", PlayerColors.default_for(k))), PlayerColors.count())

func color(k: int) -> Color:
	# Spielerfarbe (Lack, Schild, Lichtkranz, Turboknopf, Linie, Wertung).
	return PlayerColors.color(color_index(k))

func colors() -> Array[Color]:
	var out: Array[Color] = []
	for k in range(count()):
		out.append(color(k))
	return out

# ---------- Ablauf einer Runde ----------
func start_round() -> void:
	# Erstes Rennen: Startplätze in Spielerreihenfolge.
	races = 0
	last_ranking.clear()
	grid.clear()
	for k in range(count()):
		grid.append(k)
	reset_lines()

func rematch() -> void:
	# Revanche mit denselben Einstellungen: neu zeichnen, Aufstellung umgekehrt zum letzten Ergebnis (der Sieger startet hinten).
	if last_ranking.size() == count():
		grid.clear()
		for k in range(count() - 1, -1, -1):
			grid.append(last_ranking[k])
	reset_lines()

func reset_lines() -> void:
	routes.clear()
	routes.resize(count())
	for k in range(count()):
		routes[k] = []
	turn = 0

func store_line(route: Array) -> void:
	routes[turn] = route.duplicate(true)

func all_drawn() -> bool:
	for r in routes:
		if (r as Array).is_empty():
			return false
	return routes.size() == count()

func slot_of(player: int) -> int:
	# Startplatz (= Index im Feld) eines Spielers.
	return grid.find(player)

func player_at(slot: int) -> int:
	return grid[slot] if slot >= 0 and slot < grid.size() else -1

func entries() -> Array[Dictionary]:
	# Teilnehmerliste fürs Feld: Menschen in Startreihenfolge mit Linie, Auto, Name (dazu "player" = Spielerindex und "paint" =
	# Spielerfarbe, nur Darstellung), dahinter die KI wie im Einzelspieler (RaceField.lineup: Stärke und Spur der Herausforderung).
	var shown := names()
	var humans: Array = []
	for k in grid:
		var e := RaceField.human_entry(RaceField.as_plan(routes[k]), int(players[k].car), shown[k])
		e["player"] = k
		e["paint"] = color(k)
		humans.append(e)
	return RaceField.lineup(humans, stage, count() + (0 if is_drift() else ai), is_drift())

func note_result(slot_ranking: Array) -> void:
	# Ergebnis merken (Startplätze in Zielreihenfolge, auch KI): daraus die Spielerreihenfolge für die Revanche.
	races += 1
	last_ranking.clear()
	for slot in slot_ranking:
		var k := player_at(int(slot))
		if k >= 0:
			last_ranking.append(k)
