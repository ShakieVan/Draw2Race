class_name NetLobby
extends Node

# Lobby des WLAN-Mehrspielers (M3, docs/MULTIPLAYER_RECHERCHE.md 5.2 Schritte 1–2): Spiel eröffnen (Host) oder beitreten (Suche per
# Rundruf, Ankündigung, Gateway-Probe oder eingetippter Adresse), Spielerliste mit Name, Auto, Bereit und Ping, Einstellungen des
# Hosts (Strecke, Herausforderung, KI, Berührungen) live bei allen, Start mit gemeinsamem Laden der Strecke (Prüfsumme) als Übergabe
# an das Zeichnen (M4). Der Host führt den Zustand; Mitspieler schicken nur Wünsche (Auto, Name, Bereit, Hintergrund) und spiegeln,
# was der Host verteilt. Reines Netz und Daten: keine Szene, keine Simulation, kein Spielstand (Oberfläche: lobby_hud.gd, Ablauf:
# main.gd). Regeln (Nutzerentscheidungen 03.10.2026): alle Strecken und Autos frei, mehrere dürfen dasselbe Auto fahren (Autowahl),
# jeder hat eine eigene Spielerfarbe (PlayerColors; belegt → der Host vergibt die nächste freie, wie Ziffern bei gleichen Namen), KI
# wählbar (zusammen höchstens 4 Autos), Berührungen abschaltbar, Drift-Arena ohne KI und ohne Berührungen.
#
# Nachrichten (zuverlässig, Kanal 0). Host → alle:
#   lobby {rev, phase, round, settings {track, stage, ai, contacts}, players [{id, name, car, color, ready, host, away, loaded, ping}]}
#   start {round {id, settings, players [{id, name, car, color}], hash}}   Strecke laden, danach „loaded“ melden
#   go {id, players, draw_at, now}                                  alle haben geladen → gemeinsames Zeichnen (M4, NetDraw) um draw_at
#   back {id, reason}                                               zurück in die Lobby
#   close {reason}                                                  Host beendet das Spiel (danach trennt er sauber)
# Mitspieler → Host: pick {car, color, name, seq} (color −1 = keine Wahl), ready {on, seq}, away {on, seq}, loaded {id, hash}
# Typen „draw_…“ gehen an das gemeinsame Zeichnen (draw: NetDraw, net_draw.gd), solange eine Runde läuft, Typen „race_…“ an das
# gemeinsame Rennen (race: NetRace, net_race.gd, M5; entsteht, sobald alle Linien verteilt sind). Alle anderen Typen gehen unverändert
# an custom_message; senden: session.send(1, …) bzw. session.send_all(…).
# Revanche (M5/M6): Der Host startet aus der Wertung eine neue Runde mit denselben Einstellungen und den noch anwesenden Spielern in
# umgekehrter Zielreihenfolge (rematch) – ohne Bereit-Runde, alle laden sofort und zeichnen neu.
#
# WLAN-Bindung (Nutzerentscheidung 03.10.2026): Beim Betreten (enter) bindet sich das Spiel auf Android ans WLAN, beim Verlassen
# (exit) wird gelöst, damit Update-Suche und Internet wieder gehen. Ausnahme: Eröffnet ein Handy mit eingeschaltetem eigenem Hotspot
# das Spiel, bleibt es ungebunden – an ein Netz gebundene Sockets leitet Android nur über dessen Routing-Tabelle, und dort fehlt das
# Hotspot-Netz der Mitspieler (Gerätetest offen). Die Bindung gilt nur für danach angelegte Sockets: erst binden, dann Sitzung/Suche.

const Proto := preload("res://scripts/net/net_protocol.gd")
const Session := preload("res://scripts/net/net_session.gd")
const Discovery := preload("res://scripts/net/net_discovery.gd")
const Android := preload("res://scripts/net/net_android.gd")
const Log := preload("res://scripts/net/net_log.gd")

signal changed                              # Spieler, Einstellungen, Bereit, Ping oder Phase
signal status_changed                       # Netzstatus (WLAN, Hotspot, Bindung)
signal games_changed                        # Suche: gefundene Spiele
signal joined                               # Mitspieler: angenommen, erster Lobby-Zustand ist da
signal failed(reason: String)               # Beitritt gescheitert (abgelehnt, nicht erreichbar) – zurück zur Suche
signal closed(reason: String)               # Sitzung zu Ende (Host hat beendet, Verbindung verloren)
signal notice(text: String)                 # kurze Hinweise („Ben ist beigetreten.“)
signal round_started(info: Dictionary)     # Start: Strecke laden und report_loaded() rufen
signal round_ready(info: Dictionary)       # alle haben geladen: Einstieg ins gemeinsame Zeichnen (M4)
signal round_cancelled(reason: String)      # zurück in die Lobby
signal custom_message(from: int, msg: Dictionary)   # andere Nachrichtentypen, from = Absender
signal race_ready                           # alle Linien verteilt: race (NetRace) ist angelegt, Ampel um race.start_at
signal log_line(text: String)

const MAX_CARS := 4                         # Autos im Feld (Menschen + KI), wie im Einzelspieler
const STATE_INTERVAL_MS := 1000             # Host verteilt den Zustand (mit Ping) mindestens so oft
const STATUS_INTERVAL_MS := 2000            # Netzstatus neu lesen (WLAN später verbunden? dann binden)
const PHASES := ["lobby", "loading", "ready"]

# Vorgaben (Tests setzen sie über overrides, bevor die Lobby entsteht)
static var overrides := {}                  # Feldname -> Wert, z. B. Ports, probe_local, use_broadcast, use_binding, log_path
var tracks: Array = ["azure"]               # erlaubte Strecken (main.TRACKS), Reihenfolge = Anzeige
var game_port := Proto.GAME_PORT
var discovery_port := Proto.DISCOVERY_PORT
var beacon_port := Proto.BEACON_PORT
var probe_local := false                    # zusätzlich 127.0.0.1 (PC-Tests)
var use_broadcast := true
var use_binding := true                     # Android: ans WLAN binden
var auto_poll := true
# ENet-Zeitgrenzen [Grenzwert, Minimum ms, Maximum ms] (NetSession.peer_timeout): normal 8–20 s; vom Start einer Runde (Strecke laden,
# Welt bauen, erstes Bild – ein langsames Handy wie das S10 hängt dabei mehrere Sekunden) bis load_grace_ms nach dem gemeinsamen
# Zeichenstart lang. Alle Geräte schalten zugleich um: der Gastgeber vor dem Verschicken von „start“, die Mitspieler beim Empfang.
var peer_timeout := [16, 8000, 20000]
var load_timeout := [16, 25000, 45000]
var load_grace_ms := 3000
var android_api = Android                   # Android-Anbindung (NetAndroid); Tests setzen einen Ersatz mit denselben Funktionen
var log_path := "user://mehrspieler.log"    # "" = kein Protokoll (adb shell run-as de.draw2race.game cat files/mehrspieler.log)
var hello_override := {}                    # nur Tests: Felder der eigenen Anmeldung ersetzen (falsche Version/Strecken)
var forced_status := {}                     # nur Tests/Bilder: Netzstatus vorgeben statt lesen
var draw_lead_ms := 3000                    # Host: gemeinsamer Zeichenstart so lange nach „alle geladen“ (3-2-1)
var reveal_lead_ms := 800                   # Host: Enthüllung so lange nach dem Verteilen der Linien (Übertragung)
var reveal_ms := 3000                       # Host: so lange sind alle Linien vor der Ampel zu sehen (wie PassParty.REVEAL_TIME)
var race_speed := 1.0                       # nur Tests: Zeitraffer des Rennens (NetRace.speed)
var snapshot_drop := 0.0                    # nur Tests: Anteil verworfener Schnappschüsse beim Mitspieler (Funkverlust nachstellen)
var race_history := false                   # nur Tests: Gastgeber merkt sich die Lage aller Autos je Takt (NetRace.history)

var session: Session
var discovery: Discovery
var netlog: Log
var mode := ""                              # "" | "search" | "join" | "host"
var is_joined := false                      # Mitspieler: angenommen und Zustand empfangen
var my_name := "Fahrer"                     # gewünschter Name (der Host macht ihn eindeutig)
var my_car := 0                             # gewünschtes Auto
var my_color := -1                          # gewünschte Spielerfarbe (Index in PlayerColors), −1 = Vorgabe nach Platz
var settings := {"track": "azure", "stage": 0, "ai": 1, "contacts": true}
var players: Array = []                     # [{id, name, car, color, ready, host, away, loaded, ping}] – Host zuerst, dann Beitrittsfolge
var phase := "lobby"                        # lobby | loading (Strecke wird geladen) | ready (M4: Zeichnen)
var current_round := {}                     # laufende Runde (start/go)
var draw: NetDraw                           # gemeinsames Zeichnen der laufenden Runde (ab „go“), sonst null
var race: NetRace                           # gemeinsames Rennen der laufenden Runde (ab dem Verteilen der Linien), sonst null
var _circuit: Circuit                       # beim Laden gemeldete Strecke der Runde (Prüfung der Linien)
var round_id := 0
var rev := 0
var close_reason := ""
var status := {}                            # {android, wifi, hotspot [ip], bound, problem, addresses [ip], gateway}
var bound := false
var bind_problem := ""
var _ai_wish := 1                           # Host: gewünschte KI-Zahl (wird bei vollem Feld begrenzt, danach wieder erreicht)
var _seq := 0                               # Mitspieler: Nummer des letzten Wunschs; der Host bestätigt sie je Spieler („ack“)
var _ping := {}                             # Spieler-ID (Mitspieler: 1 = eigener Ping zum Host) -> geglättete RTT (ms)
var _next_state_ms := 0
var _next_status_ms := 0
var _next_ping_ms := 0
var _entered := false
var _free_when_closed := false
var _track_hashes := {}
var _timeouts := "normal"                   # gerade gesetzte ENet-Zeitgrenze: normal | load
var _bind_wifi := ""                        # Handle des WLANs, für das zuletzt gebunden (bzw. die Bindung versucht) wurde

func _init() -> void:
	for key in overrides:
		set(key, overrides[key])
	session = Session.new()
	session.name = "NetSession"
	session.auto_poll = false
	session.peer_timeout = peer_timeout.duplicate()
	add_child(session)
	discovery = Discovery.new()
	discovery.name = "NetDiscovery"
	discovery.auto_poll = false
	discovery.discovery_port = discovery_port
	discovery.beacon_port = beacon_port
	discovery.probe_local = probe_local
	discovery.use_broadcast = use_broadcast
	add_child(discovery)
	if log_path != "":
		netlog = Log.new(log_path)
	session.state_changed.connect(_on_state)
	session.peer_joined.connect(_on_peer_joined)
	session.peer_left.connect(_on_peer_left)
	session.message_received.connect(_on_message)
	session.log_line.connect(func(t): _log("ENet: " + t))
	discovery.log_line.connect(func(t): _log("Suche: " + t))
	discovery.games_changed.connect(func(): games_changed.emit())

func _process(_delta: float) -> void:
	if auto_poll:
		poll()

# ---------- Reine Regeln (auch für Tests und M4) ----------
static func _int(value, fallback: int) -> int:
	return int(value) if (value is int or value is float) else fallback

static func _bool(value, fallback := false) -> bool:
	return bool(value) if value is bool else fallback

static func max_ai(track_id: String, humans: int) -> int:
	return 0 if PassParty.track_is_drift(track_id) else maxi(0, MAX_CARS - humans)

static func clean_settings(s: Dictionary, humans: int, track_ids: Array) -> Dictionary:
	# Gültige Einstellungen: bekannte Strecke, Stufe 0–2, KI 0 bis 4 − Menschen, Drift ohne KI und ohne Berührungen.
	var track := str(s.get("track", ""))
	if not track in track_ids:
		track = str(track_ids[0]) if not track_ids.is_empty() else "azure"
	var drift := PassParty.track_is_drift(track)
	return {"track": track, "stage": clampi(_int(s.get("stage"), 0), 0, 2),
		"ai": clampi(_int(s.get("ai"), 0), 0, max_ai(track, humans)), "contacts": not drift and _bool(s.get("contacts"), true)}

static func track_file_hash(track_id: String) -> String:
	# Wie Circuit.file_hash: SHA-256 der Streckendatei.
	return FileAccess.get_sha256("res://tracks/%s.json" % track_id)

static func tracks_hash(track_ids: Array) -> String:
	# Prüfsumme aller Streckendaten für die Anmeldung: Geräte mit anderen Strecken werden mit klarem Grund abgelehnt.
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for id in track_ids:
		ctx.update(("%s=%s;" % [id, track_file_hash(str(id))]).to_utf8_buffer())
	return ctx.finish().hex_encode().left(32)

static func clean_players(list) -> Array:
	# Spielerliste aus einer Nachricht: höchstens 4 Einträge, bekannte Felder mit festen Typen.
	var out: Array = []
	if not list is Array:
		return out
	for p in list:
		if out.size() >= Proto.MAX_PLAYERS:
			break
		if p is Dictionary and _int(p.get("id"), 0) > 0:
			var name := ProgressStore.clean_name(str(p.get("name", "")))
			out.append({"id": _int(p.id, 0), "name": name if name != "" else "?", "car": clampi(_int(p.get("car"), 0), 0, RaceVehicle.CARS.size() - 1),
				"color": clampi(_int(p.get("color"), 0), 0, PlayerColors.count() - 1), "ready": _bool(p.get("ready")), "host": _bool(p.get("host")), "away": _bool(p.get("away")), "loaded": _bool(p.get("loaded")),
				"ping": clampi(_int(p.get("ping"), -1), -1, 9999), "ack": maxi(0, _int(p.get("ack"), 0))})
	return out

func start_problem() -> String:
	# Warum der Host (noch) nicht starten kann; "" = Start möglich.
	if mode != "host":
		return "Nur der Gastgeber startet das Rennen."
	if phase != "lobby":
		return "Das Rennen läuft schon."
	var clients := players.filter(func(p): return not p.host)
	if clients.is_empty():
		return "Warte auf Mitspieler – sie tippen „Beitreten“."
	var waiting := clients.filter(func(p): return not p.ready or p.away)
	if not waiting.is_empty():
		return "Noch nicht bereit: " + ", ".join(waiting.map(func(p): return p.name))
	return ""

func round_party() -> PassParty:
	# Runde als PassParty (für M4/M5: entries(), Namen, Farben, Startaufstellung): Spieler in Lobby-Reihenfolge, Startplätze in dieser
	# Reihenfolge. Linien (routes) setzt M4. ids() liefert die Spieler-IDs in derselben Reihenfolge.
	var p := PassParty.new()
	var s: Dictionary = current_round.get("settings", settings)
	p.track_id = str(s.track)
	p.stage = int(s.stage)
	p.ai = int(s.ai)
	p.contacts = bool(s.contacts)
	for entry in current_round.get("players", players):
		p.players.append({"name": str(entry.name), "car": int(entry.car), "color": int(entry.get("color", 0))})
	p.start_round()
	return p

func round_ids() -> Array:
	return current_round.get("players", players).map(func(e): return int(e.id))

# ---------- Abfragen ----------
func is_host() -> bool:
	return mode == "host"

func my_id() -> int:
	return 1 if mode == "host" else session.my_id

func me() -> Dictionary:
	return player(my_id())

func player(id: int) -> Dictionary:
	for p in players:
		if int(p.id) == id:
			return p
	return {}

func client_count() -> int:
	return players.filter(func(p): return not p.host).size()

func taken_colors(except_id := -1) -> Array:
	# Spielerfarben der anderen (except_id = eigene Spieler-ID).
	var out: Array = []
	for p in players:
		if int(p.id) != except_id:
			out.append(int(p.get("color", 0)))
	return out

func host_name() -> String:
	for p in players:
		if p.host:
			return str(p.name)
	return str(session.peers[1].name) if session.peers.has(1) else "Host"

func ping_of(p: Dictionary) -> int:
	# Ping zum Host: Mitspieler sehen ihren eigenen Wert selbst gemessen, die übrigen so, wie der Host sie misst.
	if p.host:
		return -1
	if mode == "join" and int(p.id) == session.my_id:
		return roundi(float(_ping[1])) if _ping.has(1) else -1
	return int(p.get("ping", -1))

func games() -> Array:
	return discovery.sorted_games()

# ---------- Betreten und Verlassen des WLAN-Mehrspielers ----------
func enter(player_name: String, car: int) -> void:
	_entered = true
	my_name = player_name
	my_car = car
	_log("=== WLAN-Mehrspieler betreten: Draw2Race %s, Protokoll %d, Physik %s, %s %s, Name „%s“ ===" % [Proto.game_version(), Proto.VERSION,
		Proto.physics_version(), OS.get_name(), OS.get_model_name(), player_name])
	if android_api.available():
		_log("Multicast-Sperre: %s" % ("gehalten" if android_api.multicast(true) else "FEHLER (Berechtigung?)"))
	_bind(false)
	refresh_status()

func exit() -> void:
	# Sitzung verlassen, Suche beenden, Bindung und Multicast-Sperre lösen.
	leave()
	discovery.stop()
	mode = ""
	if android_api.available() and (bound or android_api.is_bound()):
		_log("WLAN-Bindung gelöst: %s" % ("ja" if android_api.unbind() else "FEHLER"))
	bound = false
	_bind_wifi = ""
	if android_api.available():
		android_api.multicast(false)
	if _entered:
		_log("=== WLAN-Mehrspieler verlassen ===")
	_entered = false

func dispose() -> void:
	# Lobby entfernen; ein Host trennt seine Mitspieler noch sauber (höchstens 0,6 s), dann verschwindet der Knoten.
	exit()
	if session.enet != null:
		_free_when_closed = true
	else:
		queue_free()

func refresh_status() -> void:
	_next_status_ms = Time.get_ticks_msec() + STATUS_INTERVAL_MS
	var raw := _net_state()
	var addresses: Array = []
	for i in raw.get("interfaces", []):
		if i is Dictionary:
			addresses.append(str(i.get("address", "")))
	if bool(raw.get("android", false)):
		bound = Android.bound_to_wifi(raw)    # gebunden zählt nur, wenn das gebundene Netz das verbundene WLAN ist
	var fresh := {"android": bool(raw.get("android", false)), "wifi": Android.wifi_connected(raw), "hotspot": Android.hotspot_addresses(raw),
		"bound": bound, "problem": bind_problem, "addresses": addresses, "gateway": Android.wifi_gateway(raw)}
	var wifi := Android.wifi_handle(raw)
	if mode == "search" and use_binding and android_api.available() and wifi != "" and wifi != _bind_wifi:
		# Anderes WLAN als beim letzten Binden: erst jetzt verbunden (Nutzer kam aus den Einstellungen zurück) oder gewechselt (Heim-WLAN →
		# Hotspot des Gastgebers). Die alte Bindung zeigte sonst auf ein verlorenes Netz – neu binden und mit neuer Bindung weitersuchen.
		# Nur einmal je WLAN: Scheitert die Bindung, bleibt es beim Hinweis (keine Suche im Zwei-Sekunden-Takt).
		_log("WLAN %s (vorher %s) – binde neu und suche neu" % [wifi, _bind_wifi if _bind_wifi != "" else "keins"])
		status = fresh
		search()
		status.bound = bound
		status.problem = bind_problem
		status_changed.emit()
		return
	if fresh != status:
		status = fresh
		status_changed.emit()

func _net_state() -> Dictionary:
	return forced_status if not forced_status.is_empty() else android_api.state()

func _bind(for_host: bool) -> void:
	if not use_binding or not android_api.available():
		return
	var raw: Dictionary = android_api.state()
	_bind_wifi = Android.wifi_handle(raw)
	if for_host and not Android.hotspot_addresses(raw).is_empty():
		if raw.get("bound") is Dictionary:
			_log("Eigener Hotspot an – Gastgeber löst die WLAN-Bindung (Hotspot-Mitspieler sonst unerreichbar): %s" % ("ja" if android_api.unbind() else "FEHLER"))
		bound = false
		bind_problem = ""
		return
	if Android.bound_to_wifi(raw):
		bound = true
		bind_problem = ""
		return
	if raw.get("bound") is Dictionary:
		# Gebunden an ein Netz, das nicht (mehr) das verbundene WLAN ist – z. B. das Heim-WLAN nach dem Wechsel in den Hotspot.
		var old: Dictionary = raw.bound
		_log("Bindung zeigt auf ein verlorenes Netz (%s, %s) – binde neu" % [str(old.get("handle", "?")), str(old.get("transport", "?"))])
	var problem: String = android_api.bind_wifi()
	bound = problem == ""
	bind_problem = problem
	_log("An WLAN binden: %s" % ("gebunden" if bound else "nicht möglich – " + problem))

# ---------- Suchen, Beitreten, Eröffnen ----------
func search() -> void:
	# WLAN-Bildschirm: Spiele suchen (Rundruf, Ankündigung, Gateway-Probe; eingetippte Adressen zusätzlich). Bindet vorher neu, falls
	# die Bindung nicht (mehr) zum verbundenen WLAN passt; neue Such-Sockets entstehen danach mit der neuen Bindung.
	leave()
	_bind(false)
	var raw := _net_state()
	discovery.gateway = Android.wifi_gateway(raw)
	discovery.clear_games()
	discovery.start_search()
	mode = "search"
	status_changed.emit()

func join(address: String, port := -1) -> Error:
	# Beitreten. Ergebnis kommt als joined (angenommen) oder failed(Grund).
	leave()
	discovery.stop()
	_bind(false)
	mode = "join"
	_reset_round()
	players.clear()
	close_reason = ""
	session.track_hash = tracks_hash(tracks)
	session.hello_override = hello_override
	# Scheitert schon das Anlegen, meldet _on_state() das als failed (Zustand „closed“).
	return session.join(address, port if port > 0 else game_port, my_name)

func cancel_join() -> void:
	if mode == "join" and not is_joined:
		leave()

func host(track_id: String, stage: int) -> Error:
	# Spiel eröffnen: ENet-Host und Ankündigung; Einstellungen beginnen mit Strecke und Herausforderung des Menüs.
	leave()
	discovery.stop()
	_bind(true)
	session.track_hash = tracks_hash(tracks)
	session.check_track = true
	session.join_block = ""
	var err := session.host(my_name, game_port)
	if err != OK:
		mode = ""
		return err
	mode = "host"
	_reset_round()
	_ai_wish = stage + 1
	settings = clean_settings({"track": track_id, "stage": stage, "ai": _ai_wish, "contacts": true}, 1, tracks)
	players = [{"id": 1, "name": session.my_name, "car": posmod(my_car, RaceVehicle.CARS.size()),
		"color": posmod(my_color, PlayerColors.count()) if my_color >= 0 else PlayerColors.default_for(0), "ready": true, "host": true,
		"away": false, "loaded": false, "ping": -1}]
	discovery.start_host({"name": session.my_name, "port": game_port, "players": 1, "max": Proto.MAX_PLAYERS, "busy": false})
	_log("Spiel eröffnet: „%s“, Port %d, Strecke %s, Stufe %d" % [session.my_name, game_port, settings.track, settings.stage + 1])
	_broadcast()
	return OK

func leave() -> void:
	# Sitzung verlassen (zurück zum WLAN-Bildschirm). Host: alle Mitspieler erfahren es und kehren ins Menü zurück.
	var was := mode
	var host_shown := host_name()
	mode = ""                     # zuerst: das Schließen unten meldet sonst „Verbindung verloren“ (closed)
	if was == "host" and session.enet != null:
		session.close_gracefully({"t": "close", "reason": "Der Gastgeber „%s“ hat das Spiel beendet." % host_shown})
	elif was == "join" and session.enet != null:
		session.close_gracefully({"t": "bye"})
	if was in ["host", "join"]:
		_log("Sitzung verlassen")
	discovery.stop()
	is_joined = false
	players.clear()
	_reset_round()
	_ping.clear()

func _reset_round() -> void:
	phase = "lobby"
	current_round = {}
	draw = null
	race = null
	_circuit = null
	round_id = 0
	rev = 0

# ---------- Eigene Wahl (Host und Mitspieler) ----------
func set_car(car: int) -> void:
	# Auto aus der Garage: jedes Auto, auch eines, das ein anderer schon fährt.
	var mine := me()
	if not mine.is_empty() and phase == "lobby":
		_pick({"car": posmod(car, RaceVehicle.CARS.size())})

func set_color(index: int) -> void:
	# Spielerfarbe aus der Garage; ist sie schon vergeben, bekommt man die nächste freie (der Host entscheidet endgültig).
	var mine := me()
	if not mine.is_empty() and phase == "lobby":
		_pick({"color": PlayerColors.free_color(index, taken_colors(int(mine.id)))})

func set_player_name(text: String) -> void:
	var clean := ProgressStore.clean_name(text)
	if clean == "" or phase != "lobby":
		return
	my_name = clean
	_pick({"name": clean})

func _pick(wish: Dictionary) -> void:
	if wish.has("car"):
		my_car = int(wish.car)
	if wish.has("color"):
		my_color = int(wish.color)
	if mode == "host":
		_apply_pick(1, wish)
		_broadcast()
	elif mode == "join" and is_joined:
		var mine := me()
		if mine.is_empty():
			return
		if wish.has("car"):
			mine.car = int(wish.car)       # sofort zeigen; der Host bestätigt oder korrigiert
		if wish.has("color"):
			mine.color = int(wish.color)
		mine.ready = false
		_wish({"t": "pick", "car": int(wish.get("car", mine.car)), "color": int(wish.get("color", mine.color)), "name": str(wish.get("name", my_name))})
		changed.emit()

func set_ready(on: bool) -> void:
	if mode != "join" or not is_joined or phase != "lobby":
		return
	var mine := me()
	if not mine.is_empty():
		mine.ready = on
	_wish({"t": "ready", "on": on})
	changed.emit()

func set_away(on: bool) -> void:
	# App geht in den Hintergrund bzw. kommt zurück: sofort melden (danach hält Android die App an).
	var mine := me()
	if mine.is_empty() or bool(mine.away) == on:
		return
	_log("App %s" % ("im Hintergrund" if on else "wieder da"))
	if mode == "host":
		mine.away = on
		_broadcast()
	elif mode == "join" and is_joined:
		mine.away = on
		if on:
			mine.ready = false
		_wish({"t": "away", "on": on})
	session.flush()

# ---------- Einstellungen (nur Host) ----------
func set_track(id: String) -> void:
	if mode == "host" and phase == "lobby" and id in tracks:
		settings.track = id
		_settings_changed()

func set_stage(value: int) -> void:
	if mode == "host" and phase == "lobby":
		settings.stage = clampi(value, 0, 2)
		_settings_changed()

func set_ai(value: int) -> void:
	if mode == "host" and phase == "lobby":
		_ai_wish = maxi(0, value)
		_settings_changed()

func set_contacts(on: bool) -> void:
	if mode == "host" and phase == "lobby":
		settings.contacts = on
		_settings_changed()

func _settings_changed() -> void:
	# Geänderte Einstellungen gelten erst, wenn alle sie gesehen haben: Bereit der Mitspieler zurücksetzen.
	_clamp_settings()
	for p in players:
		if not p.host:
			p.ready = false
	_log("Einstellungen: %s" % JSON.stringify(settings))
	_broadcast()

func _clamp_settings() -> void:
	var wanted := settings.duplicate()
	wanted.ai = _ai_wish
	settings = clean_settings(wanted, players.size(), tracks)

# ---------- Runde: Start, Laden, Zurück ----------
func start_round() -> bool:
	# Host: alle bereit → Strecke laden lassen; neue Beitritte werden ab jetzt abgelehnt.
	if start_problem() != "":
		return false
	_begin_round([])
	return true

func rematch() -> bool:
	# Host aus der Wertung: Revanche mit denselben Einstellungen; Startreihenfolge = umgekehrte Zielreihenfolge (der Sieger startet
	# hinten), dahinter Spieler ohne Ergebnis. Wer gegangen ist, fehlt. Ohne Mitspieler zurück in die Lobby.
	if mode != "host" or phase != "ready" or race == null or race.rows.is_empty():
		return false
	if client_count() == 0:
		back_to_lobby("Alle Mitspieler sind gegangen.")
		return false
	var order: Array = race.rematch_order().filter(func(id): return not player(int(id)).is_empty())
	for p in players:
		if not order.has(int(p.id)):
			order.append(int(p.id))
	_log("Revanche: Startreihenfolge %s" % str(order))
	_begin_round(order)
	return true

func _begin_round(order: Array) -> void:
	round_id += 1
	phase = "loading"
	draw = null
	race = null
	session.join_block = "Das Rennen hat schon begonnen. Warte, bis ihr wieder in der Lobby seid."
	for p in players:
		p.loaded = false
	current_round = {"id": round_id, "settings": settings.duplicate(), "players": _round_players(order), "hash": track_file_hash(str(settings.track)),
		"order": order.duplicate()}
	_log("Start Runde %d: %s" % [round_id, JSON.stringify(current_round)])
	_apply_timeouts()
	session.send_all({"t": "start", "round": current_round})
	_broadcast()
	# Sofort hinaus, nicht erst beim nächsten poll(): Gleich lädt auch dieses Gerät die Strecke und steht dabei womöglich Sekunden – die
	# Mitspieler sollen „start“ (und damit ihre langen Zeitgrenzen) vorher haben.
	session.flush()
	round_started.emit(current_round)

func report_loaded(file_hash: String, circuit: Circuit = null) -> void:
	# Nach dem Laden der Strecke (main.gd: track.file_hash, die Strecke selbst prüft im Zeichnen die Linien). Der Host wartet, bis
	# alle mit derselben Prüfsumme geladen haben.
	if phase != "loading":
		return
	_circuit = circuit
	var mine := me()
	if mode == "host":
		if file_hash != str(current_round.hash):
			_log("Eigene Strecke weicht ab (%s statt %s)" % [file_hash, current_round.hash])
			back_to_lobby("Die Strecke ließ sich nicht laden.")
			return
		mine.loaded = true
		_check_loaded()
	elif mode == "join":
		if not mine.is_empty():
			mine.loaded = true
		session.send(1, {"t": "loaded", "id": round_id, "hash": file_hash})
		changed.emit()

func back_to_lobby(reason := "") -> void:
	# Host: Runde abbrechen bzw. beenden, alle zurück in die Lobby (Bereit der Mitspieler zurückgesetzt).
	if mode != "host" or phase == "lobby":
		return
	phase = "lobby"
	session.join_block = ""
	for p in players:
		p.loaded = false
		if not p.host:
			p.ready = false
	session.send_all({"t": "back", "id": round_id, "reason": reason})
	current_round = {}
	draw = null
	race = null
	_log("Zurück in die Lobby%s" % (": " + reason if reason != "" else ""))
	_broadcast()
	round_cancelled.emit(reason)

func _check_loaded() -> void:
	if mode != "host" or phase != "loading":
		return
	if client_count() == 0:
		back_to_lobby("Alle Mitspieler sind gegangen.")
		return
	if players.all(func(p): return p.loaded):
		phase = "ready"
		current_round.players = _round_players(current_round.get("order", []))
		var now := session.host_time_usec()
		current_round.draw_at = now + draw_lead_ms * 1000
		_start_draw(now)
		session.send_all({"t": "go", "id": round_id, "players": current_round.players, "draw_at": current_round.draw_at, "now": now})
		_log("Alle haben geladen – Runde %d beginnt, Zeichnen in %.1f s" % [round_id, draw_lead_ms / 1000.0])
		_broadcast()
		round_ready.emit(current_round)
	else:
		_broadcast()

func _start_draw(now_host_usec: int) -> void:
	# Gemeinsames Zeichnen der Runde anlegen (Host und Mitspieler gleich, aus current_round).
	var circuit := _circuit
	if circuit == null or circuit.id != str(current_round.settings.track):
		circuit = Circuit.load_track(str(current_round.settings.track))
	draw = NetDraw.new(self, current_round, circuit, mode == "host", int(current_round.draw_at), now_host_usec)
	draw.reveal_lead_usec = reveal_lead_ms * 1000
	draw.reveal_usec = reveal_ms * 1000
	draw.log_line.connect(func(t): _log("Zeichnen: " + t))
	draw.changed.connect(func(): changed.emit())
	draw.plans_ready.connect(_on_plans_ready)

func _on_plans_ready() -> void:
	# M5: Alle Linien sind da – das Rennen der Runde anlegen. Der Host rechnet ab race.go_at (auch ohne Oberfläche, über poll()),
	# alle zeigen ab race.start_at die Ampel.
	if draw == null:
		return
	race = NetRace.new(self, draw, race_speed)
	race.drop_rate = snapshot_drop if mode == "join" else 0.0
	race.record_history = race_history
	race.log_line.connect(func(t): _log("Rennen: " + t))
	race_ready.emit()

func _round_players(order: Array = []) -> Array:
	# Spieler der Runde in Startreihenfolge: Lobby-Reihenfolge bzw. order (Spieler-IDs, Revanche); nicht genannte hinten an.
	var list: Array = []
	for id in order:
		var p := player(int(id))
		if not p.is_empty():
			list.append(p)
	for p in players:
		if not list.has(p):
			list.append(p)
	return list.map(func(p): return {"id": int(p.id), "name": str(p.name), "car": int(p.car), "color": int(p.color)})

# ---------- Ablauf ----------
func poll() -> void:
	if discovery.mode != "":
		discovery.poll()
	session.poll()
	var now := Time.get_ticks_msec()
	if _entered and now >= _next_status_ms:
		refresh_status()
	if mode == "host" and session.is_ready() and now >= _next_state_ms:
		_broadcast()
	elif mode == "join" and is_joined and now >= _next_ping_ms:
		_next_ping_ms = now + STATE_INTERVAL_MS
		_smooth_ping(1, session.stats(1))
		changed.emit()
	if draw != null:
		draw.poll()
	if race != null:
		race.poll()
	_apply_timeouts()
	if _free_when_closed and session.enet == null:
		_free_when_closed = false
		queue_free()

func loading_window() -> bool:
	# Von „start“ bis load_grace_ms nach dem gemeinsamen Zeichenstart: Strecke laden, Welt bauen, erstes Bild der Welt – dabei hängen
	# langsame Handys (gemessen 5,1 s am Steinbruch). Solange gelten auf allen Geräten die langen ENet-Zeitgrenzen (load_timeout).
	if mode == "" or phase == "lobby":
		return false
	if phase == "loading":
		return true
	return draw != null and session.host_time_usec() < draw.draw_at + load_grace_ms * 1000

func _apply_timeouts() -> void:
	var want := "load" if loading_window() else "normal"
	if want == _timeouts:
		return
	_timeouts = want
	session.set_peer_timeout(load_timeout if want == "load" else peer_timeout)
	_log("ENet-Zeitgrenze %s: %d–%d ms" % ["lang (Laden)" if want == "load" else "normal", int(session.peer_timeout[1]), int(session.peer_timeout[2])])

func _broadcast() -> void:
	# Host: ganzen Zustand an alle (klein, < 1 KB) – sofort nach jeder Änderung und jede Sekunde mit frischem Ping.
	if mode != "host":
		return
	_next_state_ms = Time.get_ticks_msec() + STATE_INTERVAL_MS
	for p in players:
		if not p.host:
			_smooth_ping(int(p.id), session.stats(int(p.id)))
			p.ping = roundi(float(_ping[int(p.id)])) if _ping.has(int(p.id)) else -1
	rev += 1
	session.send_all(state_message())
	discovery.update_host_info({"name": host_name(), "players": players.size(), "busy": phase != "lobby"})
	changed.emit()

func state_message() -> Dictionary:
	return {"t": "lobby", "rev": rev, "phase": phase, "round": round_id, "settings": settings.duplicate(), "players": players.duplicate(true)}

func _smooth_ping(id: int, s: Dictionary) -> void:
	if s.is_empty() or int(s.get("received", 0)) == 0 or float(s.get("rtt_ms", -1.0)) < 0.0:
		return
	var rtt := float(s.rtt_ms)
	_ping[id] = rtt if not _ping.has(id) else lerpf(float(_ping[id]), rtt, 0.35)

func _on_state(state: String, text: String) -> void:
	if mode != "join":
		return
	match state:
		"connected":
			# Angenommen: Wunschauto und -name melden; der Host antwortet mit dem Lobby-Zustand.
			_wish({"t": "pick", "car": my_car, "color": my_color, "name": my_name})
		"closed", "rejected":
			if state == "rejected":
				_log("Abgelehnt: " + text)
			if session.enet == null or state == "rejected":
				var was_joined := is_joined
				var reason := close_reason if close_reason != "" else text
				mode = ""
				is_joined = false
				players.clear()
				_reset_round()
				if state == "closed" and close_reason == "":
					# Kein Grund vom Gastgeber (keine Ablehnung, kein „close“): Netz weg, Gastgeber abgestürzt oder nicht erreichbar.
					reason = "Die Verbindung zum Gastgeber ist abgebrochen." if was_joined else \
						"Keine Verbindung zum Gastgeber (%s). Seid ihr im selben WLAN – oder im Hotspot des Gastgebers?" % session.host_address
				if was_joined:
					_log("Sitzung beendet: %s (%s)" % [reason, text])
					closed.emit(reason)
				else:
					_log("Beitritt gescheitert: %s (%s)" % [reason, text])
					failed.emit(reason)

func _on_peer_joined(id: int, info: Dictionary) -> void:
	if mode != "host":
		return
	# Auto 0 und die Farbe des Platzes (bzw. die nächste freie), bis der Wunsch des Mitspielers („pick“) ankommt.
	players.append({"id": id, "name": str(info.get("name", "?")), "car": 0, "color": PlayerColors.free_color(PlayerColors.default_for(players.size()), taken_colors()),
		"ready": false, "host": false, "away": false, "loaded": false, "ping": -1})
	_clamp_settings()
	notice.emit("%s ist beigetreten." % info.get("name", "?"))
	_broadcast()

func _on_peer_left(id: int, reason: String) -> void:
	if mode != "host":
		return
	var p := player(id)
	if p.is_empty():
		return
	players.erase(p)
	_ping.erase(id)
	notice.emit(("%s hat das Spiel verlassen." if reason == "abgemeldet" else "Verbindung zu %s verloren.") % p.name)
	_clamp_settings()
	if draw != null:
		draw.peer_left(id)
	if race != null:
		race.peer_left(id)      # sein Auto fährt seine Linie ohne Turbo zu Ende
	if phase == "loading":
		_check_loaded()
	elif phase == "ready" and client_count() == 0 and race == null:
		back_to_lobby("Alle Mitspieler sind gegangen.")    # beim Zeichnen; ein angelegtes Rennen fährt der Host zu Ende
	else:
		_broadcast()

func _on_message(from: int, msg: Dictionary) -> void:
	if mode == "host":
		_host_message(from, msg)
	elif mode == "join" and from == 1:
		_client_message(msg)

func _wish(msg: Dictionary) -> void:
	# Mitspieler → Host, mit fortlaufender Nummer: Bis der Host sie bestätigt, zeigt die eigene Zeile den Wunsch (sonst überschriebe
	# ein Zustand, den der Host vor dem Wunsch verschickt hat, kurz die eigene Wahl – „Bereit“ würde flackern).
	_seq += 1
	msg["seq"] = _seq
	session.send(1, msg)

func _host_message(from: int, msg: Dictionary) -> void:
	var p := player(from)
	if p.is_empty():
		return
	if msg.t in ["pick", "ready", "away"]:
		p["ack"] = maxi(int(p.get("ack", 0)), _int(msg.get("seq"), 0))
	match str(msg.t):
		"pick":
			if phase == "lobby":
				_apply_pick(from, msg)
				_broadcast()
		"ready":
			if phase == "lobby":
				p.ready = _bool(msg.get("on")) and not p.away
				_broadcast()
		"away":
			p.away = _bool(msg.get("on"))
			if p.away:
				p.ready = false
				if race != null:
					race.force_off(from)     # im Hintergrund drückt niemand Turbo
			_broadcast()
		"loaded":
			if phase == "loading" and _int(msg.get("id"), -1) == round_id:
				if str(msg.get("hash", "")) == str(current_round.hash):
					p.loaded = true
					_check_loaded()
				else:
					_log("%s hat eine andere Strecke geladen – getrennt" % p.name)
					session.kick(from, "Deine Streckendaten für „%s“ unterscheiden sich vom Gastgeber. Bitte beide Geräte auf dieselbe Draw2Race-Version bringen." % current_round.settings.track, "track")
		_:
			if race != null and str(msg.t).begins_with("race_"):
				race.on_message(from, msg)
			elif draw != null and str(msg.t).begins_with("draw_"):
				draw.on_message(from, msg)
			else:
				custom_message.emit(from, msg)

func _apply_pick(id: int, wish: Dictionary) -> void:
	# Host: Wunsch eines Spielers übernehmen – Auto frei wählbar (auch doppelt), Farbe eindeutig (belegt → nächste freie), Name
	# eindeutig (Ziffer anhängen).
	var p := player(id)
	if p.is_empty():
		return
	var before := [p.car, p.color, p.name]
	if wish.get("car") is int:
		p.car = posmod(int(wish.car), RaceVehicle.CARS.size())
	if wish.get("color") is int and int(wish.color) >= 0:
		p.color = PlayerColors.free_color(int(wish.color), taken_colors(id))
	if wish.get("name") is String:
		var wanted := ProgressStore.clean_name(str(wish.name))
		if wanted != "":
			var others: Array = []
			for q in players:
				if int(q.id) != id:
					others.append(str(q.name))
			p.name = NameTags.unique_name(wanted, others)
			if id == 1:
				session.my_name = p.name
			elif session.peers.has(id):
				session.peers[id].name = p.name
	if before != [p.car, p.color, p.name] and not p.host:
		p.ready = false

func _client_message(msg: Dictionary) -> void:
	match str(msg.t):
		"lobby":
			var list := clean_players(msg.get("players"))
			if list.is_empty() or not msg.get("settings") is Dictionary:
				return
			var own := me()
			for q in list:
				if int(q.id) == session.my_id and not own.is_empty() and int(q.ack) < _seq:
					for key in ["car", "color", "ready", "away"]:
						q[key] = own[key]       # eigener Wunsch noch unbestätigt
			players = list
			settings = clean_settings(msg.settings, players.size(), tracks)
			rev = _int(msg.get("rev"), rev)
			var p := str(msg.get("phase", "lobby"))
			phase = p if p in PHASES else "lobby"
			if not is_joined:
				is_joined = true
				_log("In der Lobby von „%s“ als „%s“" % [host_name(), str(me().get("name", my_name))])
				joined.emit()
			changed.emit()
		"start":
			var r = msg.get("round")
			if not r is Dictionary or not r.get("settings") is Dictionary:
				return
			var list := clean_players(r.get("players"))
			current_round = {"id": _int(r.get("id"), 0), "settings": clean_settings(r.settings, list.size(), tracks), "players": list.map(func(e): return {"id": e.id, "name": e.name, "car": e.car, "color": e.color}),
				"hash": str(r.get("hash", "")).left(64)}
			round_id = int(current_round.id)
			phase = "loading"
			draw = null              # Revanche: die Runde davor ist vorbei
			race = null
			settings = current_round.settings.duplicate()
			_log("Start Runde %d: %s" % [round_id, JSON.stringify(current_round)])
			_apply_timeouts()        # vor dem Laden (round_started), das dieses Gerät gleich Sekunden anhalten kann
			round_started.emit(current_round)
		"go":
			if _int(msg.get("id"), -1) == round_id and phase == "loading":
				phase = "ready"
				var list := clean_players(msg.get("players"))
				if not list.is_empty():
					current_round.players = list.map(func(e): return {"id": e.id, "name": e.name, "car": e.car, "color": e.color})
				var now := _int(msg.get("now"), session.host_time_usec())
				current_round.draw_at = _int(msg.get("draw_at"), now + draw_lead_ms * 1000)
				_start_draw(now)
				_log("Alle haben geladen – Runde %d beginnt, Zeichnen in %.2f s" % [round_id, draw.seconds_until(int(current_round.draw_at))])
				round_ready.emit(current_round)
		"back":
			if phase != "lobby":
				phase = "lobby"
				current_round = {}
				draw = null
				race = null
				var reason := str(msg.get("reason", "")).left(200)
				_log("Zurück in die Lobby%s" % (": " + reason if reason != "" else ""))
				round_cancelled.emit(reason)
		"close":
			close_reason = str(msg.get("reason", "Der Gastgeber hat das Spiel beendet.")).left(200)
			_log("Gastgeber beendet: " + close_reason)
		_:
			if race != null and str(msg.t).begins_with("race_"):
				race.on_message(1, msg)
			elif draw != null and str(msg.t).begins_with("draw_"):
				draw.on_message(1, msg)
			else:
				custom_message.emit(1, msg)

func _log(text: String) -> void:
	if netlog != null:
		netlog.write(text)
	log_line.emit(text)
