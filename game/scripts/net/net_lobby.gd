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
#   lobby {rev, phase, round, settings {track, stage, ai, contacts}, players [{id, name, car, color, ready, host, away, loaded, ping}],
#          music {file, origin, fade}, guest_music}
#   music {music {file, origin, fade}}                              neues Stück beim Gastgeber (sofort; sonst jede Sekunde im Zustand)
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
# (exit) wird gelöst, damit Update-Suche und Internet wieder gehen. Die Bindung gilt nur für danach angelegte Sockets: erst binden,
# dann Sitzung/Suche. Eigener Hotspot (Gerätetest S24 Ultra 04.10.2026, NetAndroid.host_plan): Ein Gastgeber mit eingeschaltetem
# Hotspot ist nie ans WLAN gebunden – gebundene Sockets leitet Android nur über die Routing-Tabelle des WLANs, dort fehlt das
# Hotspot-Netz. Mit Hotspot und WLAN bleibt er ungebunden und erreicht Mitspieler in beiden Netzen; mit nur dem Hotspot bindet er sich
# (ab Android 16, wo der Hotspot ein eigenes Netz ist) an den Hotspot, wie es im Gerätetest lief. Kommt nach dem Eröffnen ein Netz
# dazu, das seine Bindung ausschließt, löst er sie, legt die Such-Sockets neu an und – solange noch niemand beigetreten ist – auch
# den ENet-Host, sonst erscheint ein Hinweis; neu gebunden wird beim Gastgeber nie. Mitspieler binden sich weiter ans WLAN, außer der
# Gastgeber liegt im eigenen Hotspot.
#
# Musik (Nutzerwunsch 04.10.2026): Alle Handys spielen dieselbe Musik. Die Musik des Gastgebers entscheidet (Stück, Musikstil,
# Überblendungen an den gemessenen Punkten, nächstes Playlist-Stück); er verteilt Stück und Stelle 0 auf der gemeinsamen Uhr
# (origin, µs Host-Uhr). Mitspieler spielen dasselbe Stück an derselben Stelle (sync_music → RaceSound.follow), auch nach spätem
# Beitritt und nach dem Laden. Der Gastgeber kann die Musik bei allen Mitspielern für die Sitzung abschalten (guest_music,
# music_muted); gespeichert wird davon nichts, nach der Sitzung gilt wieder die eigene Einstellung jedes Handys.
#
# Neuere Version weitergeben (Nutzerwunsch 04.10.2026, NetApk): Wird ein Beitritt wegen einer anderen Spielversion abgelehnt, darf die
# Seite mit der älteren Version die APK der neueren übers WLAN holen (apk_offer, apk_fetch) – nie ein Downgrade. Die neuere Seite stellt
# ihre Datei bereit (apk: ApkShare), bis der WLAN-Mehrspieler verlassen wird. Geprüft und installiert wird über den Updater.

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
signal apk_changed                          # Angebot oder Übertragung der neueren Version (NetApk) hat sich geändert

const MAX_CARS := 4                         # Autos im Feld (Menschen + KI), wie im Einzelspieler
const STATE_INTERVAL_MS := 1000             # Host verteilt den Zustand (mit Ping) mindestens so oft
const STATUS_INTERVAL_MS := 2000            # Netzstatus neu lesen (WLAN später verbunden? dann binden)
const PHASES := ["lobby", "loading", "ready"]
const APK_ROUND_RATE := 2 * 1048576         # Gastgeber in einer laufenden Runde: Weitergabe gedrosselt (Schnappschüsse haben Vorrang)

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
var _host_sockets := ""                     # Gastgeber: Bindung, mit der der ENet-Host entstand ("wifi", "hotspot", "" = ungebunden)
var _beacon_sockets := ""                   # Gastgeber: ebenso für den Such-/Ankündigungs-Socket
var guest_music := true                     # Musik bei den Mitspielern (Gastgeber stellt ein, gilt nur für diese Sitzung)
var music := {}                             # Musik des Gastgebers {file, origin (Host-Uhr, µs, Stelle 0), fade}; Mitspieler: zuletzt empfangen
var _music_sent := ""                       # Gastgeber: zuletzt sofort verteilter Einsatz („Datei#Nummer“)
var _join_unanswered := ""                  # Beitritt: Name des Spiels, das nur per Ankündigung zu sehen war (Antworten kamen nie an)
# Neuere Version weitergeben (NetApk)
var apk = null                              # Quelle der eigenen APK (ApkShare: available, can_receive, offer, prepare_hash, want_file,
                                            # file_ready, file_path, release_file); null = keine Weitergabe
var apk_port := NetApk.PORT                 # eigener Dateidienst (Tests: eigene Ports)
var apk_dir := "user://updates"             # Ziel geholter APKs (wie Updater.DIR; Tests: eigener Ordner je Prozess)
var apk_rate := 0                           # nur Tests: Sendetempo begrenzen (Bytes/s, NetApk.max_rate)
var apk_corrupt := -1                       # nur Tests: ein Byte verfälscht senden (NetApk.corrupt_at)
var transfer := NetApk.new()
var apk_offer := {}                         # neuere Version beim anderen Gerät: {version, name, address, port, size, sha256, from: host|guest}
var apk_pull := {}                          # Mitspieler: der ältere Gastgeber darf die eigene Version holen {version, name}
var _apk_serve := false                     # eigene Datei bereitstellen (Dienst läuft, Datei folgt, sobald sie bereit ist)
var _apk_sig := ""
var _apk_emit_ms := 0

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
	session.reject_hook = _reject_extra
	transfer.log_line.connect(func(t): _log("APK: " + t))

func _process(_delta: float) -> void:
	if auto_poll:
		poll()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and transfer != null:
		transfer.close()     # Threads der Weitergabe (NetApk) nie offen zurücklassen

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
	if transfer.fetching():
		return "Die neue Version wird gerade geholt – erst abwarten oder abbrechen."
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
		_log_net(android_api.state())
	if apk != null and apk.available():
		apk.prepare_hash()     # Prüfsumme der eigenen APK für ein mögliches Angebot (einmal je Version)
	_bind("search")
	refresh_status()

func exit() -> void:
	# Sitzung verlassen, Suche beenden, Bindung und Multicast-Sperre lösen.
	leave()
	discovery.stop()
	mode = ""
	transfer.close()               # Empfang abbrechen, Dateidienst beenden
	_apk_serve = false
	apk_offer = {}
	apk_pull = {}
	if apk != null:
		apk.release_file()
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
	if mode == "host" and _host_frees(raw):
		raw = _net_state()
	var addresses: Array = []
	for i in raw.get("interfaces", []):
		if i is Dictionary:
			addresses.append(str(i.get("address", "")))
	if bool(raw.get("android", false)):
		bound = Android.bound_to_wifi(raw)    # gebunden zählt nur, wenn das gebundene Netz das verbundene WLAN ist
	# Erreichbarkeit und Hinweis: beim Gastgeber so, wie seine Sockets tatsächlich entstanden sind, sonst als Vorschau fürs Eröffnen.
	var plan := Android.host_plan(raw, (_host_sockets if _host_sockets != "" else _beacon_sockets) if mode == "host" else null)
	var fresh := {"android": bool(raw.get("android", false)), "wifi": Android.wifi_connected(raw), "hotspot": plan.hotspot, "wlan": plan.wlan,
		"bound": bound, "problem": bind_problem, "addresses": addresses, "gateway": Android.wifi_gateway(raw), "reach": plan.reach,
		"hint": plan.hint, "warn": plan.warn}
	var wifi := Android.wifi_handle(raw)
	var fetching := transfer.fetching()        # Holen der neueren Version: Bindung nicht umwerfen (der Socket hängt an ihr)
	if mode == "search" and not fetching and use_binding and android_api.available() and wifi == "" and raw.get("bound") is Dictionary and not Android.bound_to_wifi(raw):
		# Kein WLAN mehr, die Bindung zeigt aber noch auf das verlorene Netz (oder den eigenen Hotspot): neue Sockets gingen ins Leere –
		# lösen und ungebunden weitersuchen (z. B. ein Spiel im eigenen Hotspot).
		_log("Kein WLAN mehr – löse die alte Bindung und suche neu")
		status = fresh
		search()
		status_changed.emit()
		return
	if mode == "search" and not fetching and use_binding and android_api.available() and wifi != "" and wifi != _bind_wifi:
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

func _log_net(raw: Dictionary) -> void:
	# Netzlage ins Geräteprotokoll (für den nächsten Gerätetest: Netze, Hotspot, Bindung).
	_log("Netz: " + " | ".join(Android.summary(raw)))

func _host_frees(raw: Dictionary) -> bool:
	# Gastgeber: Die Bindung seiner Sockets schließt ein inzwischen vorhandenes Netz aus – ans WLAN gebunden und der eigene Hotspot ging
	# an, oder an den Hotspot gebunden und ein WLAN kam dazu (NetAndroid.host_frees). Dann ungebunden weiter, nie neu binden: Bindung
	# lösen, Ankündigung mit neuem, ungebundenem Socket fortsetzen und – solange niemand beigetreten ist und keine Runde läuft – auch den
	# ENet-Host neu anlegen. Sind schon Mitspieler da, bleibt deren Verbindung; der Hinweis (host_plan) bittet ums Neueröffnen, und sobald
	# alle weg sind, wird neu angelegt. true = Bindung oder Sockets geändert.
	if not use_binding or not android_api.available():
		return false
	if not Android.host_frees(raw, _host_sockets) and not Android.host_frees(raw, _beacon_sockets):
		return false
	var changed := false
	if raw.get("bound") is Dictionary:
		_log("Netz kam dazu (Hotspot %s, WLAN %s) – Gastgeber löst die Bindung: %s" % [", ".join(Android.hotspot_addresses(raw)),
			", ".join(Android.wifi_addresses(raw)), "ja" if android_api.unbind() else "FEHLER"])
		bound = false
		changed = true
		_log_net(raw)
	if _beacon_sockets != "":
		_beacon_sockets = ""
		discovery.restart_host()
		changed = true
	if _host_sockets != "" and session.peers.is_empty() and phase == "lobby" and session.enet != null:
		var err := session.host(session.my_name, game_port)
		if err != OK:
			_log("ENet-Host ließ sich nicht neu anlegen (%s) – Spiel beendet" % error_string(err))
			mode = ""
			discovery.stop()
			closed.emit("Das Spiel ließ sich nach dem Netzwechsel nicht neu eröffnen. Bitte neu eröffnen.")
			return true
		_host_sockets = ""
		changed = true
		_log("ENet-Host ungebunden neu angelegt – jetzt für Mitspieler im WLAN und im Hotspot erreichbar")
	return changed

func _only_announced(address: String) -> String:
	# Beitritt: Name des Spiels an address, wenn es bisher nur über seine Ankündigung zu sehen war, auf mindestens drei Suchanfragen aber
	# nie eine Antwort kam – dann kann der Gastgeber uns nicht erreichen (Gerätetest S24: gebunden ans Heim-WLAN, Mitspieler im Hotspot).
	for g in discovery.games.values():
		var via: Dictionary = g.get("via", {})
		if (g.get("addresses", []) as Array).has(address) and int(via.get("beacon", 0)) >= 3 and via.keys().all(func(k): return k == "beacon"):
			return str(g.get("name", "?"))
	return ""

func _bind(purpose: String, address := "") -> String:
	# Bindung vor dem Anlegen neuer Sockets. purpose: "search" (WLAN-Bildschirm), "join" (Beitritt zu address), "host" (Eröffnen).
	# Ergebnis: woran die gleich entstehenden Sockets gebunden sind – "wifi", "hotspot" (Android 16: das Netz des eigenen Hotspots) oder "".
	if not use_binding or not android_api.available():
		return ""
	var raw: Dictionary = android_api.state()
	_bind_wifi = Android.wifi_handle(raw)
	var spots := Android.hotspot_addresses(raw)
	var target := "wifi"
	var why := ""
	if purpose == "host" and not spots.is_empty():
		target = Android.host_plan(raw).bind
		why = "Eigener Hotspot an (%s)%s" % [", ".join(spots), " und WLAN %s" % ", ".join(Android.wifi_addresses(raw)) if _bind_wifi != "" else ""]
	elif purpose == "join" and Android.in_hotspot(raw, address):
		target = Android.join_binding(raw, address)
		why = "Gastgeber %s liegt im eigenen Hotspot" % address
	if target == "hotspot":
		# Nur der eigene Hotspot, und Android führt ihn als Netz (ab Android 16): daran binden – so lief es im Gerätetest.
		var problem: String = android_api.bind_network(Android.hotspot_handle(raw))
		bound = false
		bind_problem = ""
		if problem == "":
			_log("%s – an den eigenen Hotspot gebunden" % why)
			_log_net(raw)
			return "hotspot"
		_log("%s – Bindung an den Hotspot nicht möglich (%s), bleibe ungebunden" % [why, problem])
		target = ""
	if target == "":
		var was_bound: bool = raw.get("bound") is Dictionary
		var ok: bool = android_api.unbind() if was_bound else true
		_log("%s – ungebunden%s%s" % [why, " (Mitspieler im Hotspot und im WLAN)" if purpose == "host" and _bind_wifi != "" else "",
			(", Bindung gelöst: %s" % ("ja" if ok else "FEHLER")) if was_bound else ""])
		bound = false
		bind_problem = ""
		_log_net(raw)
		return ""
	if Android.bound_to_wifi(raw):
		bound = true
		bind_problem = ""
		return "wifi"
	if raw.get("bound") is Dictionary:
		# Gebunden an ein Netz, das nicht (mehr) das verbundene WLAN ist – z. B. das Heim-WLAN nach dem Wechsel in den Hotspot oder (Android
		# 16) der eigene Hotspot. Ohne WLAN wird nur gelöst.
		var old: Dictionary = raw.bound
		_log("Bindung zeigt auf ein verlorenes Netz oder den eigenen Hotspot (%s, %s) – %s" % [str(old.get("handle", "?")),
			str(old.get("transport", "?")), "binde neu" if _bind_wifi != "" else "löse sie"])
		if _bind_wifi == "":
			android_api.unbind()
	if _bind_wifi == "":
		bound = false
		bind_problem = "Kein WLAN verbunden."
		_log("An WLAN binden: nicht möglich – kein WLAN verbunden")
		_log_net(raw)
		return ""
	var problem: String = android_api.bind_wifi()
	bound = problem == ""
	bind_problem = problem
	_log("An WLAN binden: %s" % ("gebunden" if bound else "nicht möglich – " + problem))
	return "wifi" if bound else ""

# ---------- Suchen, Beitreten, Eröffnen ----------
func search() -> void:
	# WLAN-Bildschirm: Spiele suchen (Rundruf, Ankündigung, Gateway-Probe; eingetippte Adressen zusätzlich). Bindet vorher neu, falls
	# die Bindung nicht (mehr) zum verbundenen WLAN passt; neue Such-Sockets entstehen danach mit der neuen Bindung.
	leave()
	_bind("search")
	var raw := _net_state()
	discovery.gateway = Android.wifi_gateway(raw)
	discovery.clear_games()
	discovery.start_search()
	mode = "search"
	status_changed.emit()

func join(address: String, port := -1) -> Error:
	# Beitreten. Ergebnis kommt als joined (angenommen) oder failed(Grund).
	_join_unanswered = _only_announced(address)
	leave()
	discovery.stop()
	_bind("join", address)
	mode = "join"
	_reset_round()
	players.clear()
	close_reason = ""
	session.track_hash = tracks_hash(tracks)
	session.hello_override = hello_override
	var mine := own_offer()
	session.hello_extra = {"apk": mine} if not mine.is_empty() else {}
	if not transfer.fetching() and str(apk_offer.get("from", "")) == "host":
		apk_offer = {}
	apk_pull = {}
	# Scheitert schon das Anlegen, meldet _on_state() das als failed (Zustand „closed“).
	return session.join(address, port if port > 0 else game_port, my_name)

func cancel_join() -> void:
	if mode == "join" and not is_joined:
		leave()

func host(track_id: String, stage: int) -> Error:
	# Spiel eröffnen: ENet-Host und Ankündigung; Einstellungen beginnen mit Strecke und Herausforderung des Menüs.
	leave()
	discovery.stop()
	_host_sockets = _bind("host")  # ENet- und Such-Sockets entstehen gleich mit dieser Bindung
	_beacon_sockets = _host_sockets
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
	if transfer.fetching():
		transfer.cancel_fetch()       # Holen der neueren Version endet mit dem Verlassen
		apk_changed.emit()

func _reset_round() -> void:
	# Auch Beginn und Ende einer Sitzung (host, leave, Verbindung weg): Musik des Gastgebers und seine Musikvorgabe vergessen.
	if mode == "":
		music = {}
		_music_sent = ""
		guest_music = true
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
	_apk_poll()
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
	return {"t": "lobby", "rev": rev, "phase": phase, "round": round_id, "settings": settings.duplicate(), "players": players.duplicate(true),
		"music": music.duplicate(), "guest_music": guest_music}

# ---------- Musik (alle hören dasselbe) ----------
func set_guest_music(on: bool) -> void:
	# Gastgeber: Musik bei allen an/aus (auch bei ihm selbst; Nutzerwunsch 04.10.2026) – jederzeit während der Sitzung, ohne Bereit
	# zurückzusetzen. Der Name guest_music bleibt fürs Protokoll.
	if mode == "host" and on != guest_music:
		guest_music = on
		_log("Musik bei allen: %s" % ("an" if on else "aus"))
		_broadcast()

func music_muted() -> bool:
	# Der Gastgeber hat die Musik bei allen abgeschaltet, auch bei sich selbst (nur für die Sitzung, der Spielstand bleibt unberührt).
	# Er führt die Playlist stumm weiter (Sound.update_music), damit beim Wiedereinschalten alle an derselben Stelle sind.
	return not guest_music and (mode == "host" or mode == "join" and is_joined)

func publish_music(state: Dictionary) -> void:
	# Gastgeber, je Bild: Stück und Stelle 0 (RaceSound.music_state, lokale Uhr = Host-Uhr). Ein neuer Einsatz geht sofort an alle, sonst
	# reist die frische Stelle jede Sekunde im Zustand mit (Nachführen, später Beitritt).
	if mode != "host" or state.is_empty():
		return
	music = {"file": str(state.file), "origin": int(state.origin), "fade": float(state.get("fade", 1.5))}
	var key := "%s#%d" % [music.file, int(state.get("n", 0))]
	if key != _music_sent and session.is_ready():
		_music_sent = key
		session.send_all({"t": "music", "music": music.duplicate()})
		_log("Musik: %s" % music.file)

func _take_music(m) -> void:
	# Mitspieler: Musik des Gastgebers aus einer Nachricht (nur Name und Zahlen; gespielt werden nur Stücke aus der eigenen Liste).
	if not m is Dictionary or not m.get("file") is String or not m.get("origin") is int:
		return
	var f = m.get("fade")
	music = {"file": str(m.file).left(200), "origin": int(m.origin), "fade": clampf(float(f), 0.0, 6.0) if (f is float or f is int) else 1.5}

func sync_music(sound: RaceSound) -> void:
	# Je Bild (main.gd, lobby_cli.gd): Gastgeber führt, Mitspieler folgen auf der gemeinsamen Uhr (Host-Zeit → eigene Uhr), sonst eigene
	# Playlist. Mitspieler folgen erst mit abgeglichener Uhr (nach etwa 1 s), bis dahin läuft ihre eigene Musik weiter.
	if sound == null:
		return
	if mode == "host":
		sound.set_net_role("lead")
		publish_music(sound.music_state())
	elif mode == "join" and is_joined:
		sound.set_net_role("follow")
		if not music.is_empty() and session.clock_synced():
			var to_local := Time.get_ticks_usec() - session.host_time_usec()
			sound.follow(str(music.file), int(music.origin) + to_local, float(music.fade))
	else:
		sound.set_net_role("")

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
				_apk_after_reject()
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
					if not was_joined and _join_unanswered != "":
						# Der Gastgeber kündigt sich an (der Rundruf geht über jede Schnittstelle), seine Antworten kommen aber nie an.
						reason = ("„%s“ ist zu sehen, antwortet aber nicht. Hat der Gastgeber seinen Hotspot und zugleich ein WLAN an? Dann soll er " +
							"dort das WLAN ausschalten und das Spiel neu eröffnen.") % _join_unanswered
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
			_take_music(msg.get("music"))
			guest_music = _bool(msg.get("guest_music"), true)
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
		"music":
			_take_music(msg.get("music"))
		"close":
			close_reason = str(msg.get("reason", "Der Gastgeber hat das Spiel beendet.")).left(200)
			_log("Gastgeber beendet: " + close_reason)
			# Sofort schließen statt auf die ENet-Trennung zu warten: Hing der Gastgeber danach (früher: Strecke laden am Stück), kam sie
			# erst nach der Zeitgrenze (bis 45 s beim Laden) – so lange blieb der Mitspieler in der Lobby stehen (Gerätetest 04.10.2026).
			session.close(close_reason)
		_:
			if race != null and str(msg.t).begins_with("race_"):
				race.on_message(1, msg)
			elif draw != null and str(msg.t).begins_with("draw_"):
				draw.on_message(1, msg)
			else:
				custom_message.emit(1, msg)

# ---------- Neuere Version weitergeben (NetApk) ----------
func own_version() -> String:
	# Eigene Spielversion, wie sie die Anmeldung meldet (Tests ersetzen sie über hello_override).
	return str(hello_override.get("game", Proto.game_version()))

func own_offer() -> Dictionary:
	# Angebot der eigenen APK {size, sha256, port}, {} solange die Prüfsumme fehlt (oder ohne Weitergabe, z. B. am PC).
	if apk == null or not apk.available():
		return {}
	var o: Dictionary = apk.offer()
	if o.is_empty():
		return {}
	o["port"] = apk_port
	return o

func apk_role_for(version: String) -> String:
	# Gefundenes Spiel mit anderer Version: "fetch" (dort neuer, holen möglich), "give" (dort älter, eigene Version weitergeben), "".
	if apk == null or version == own_version():
		return ""
	if NetApk.newer(version, own_version()) and apk.can_receive():
		return "fetch"
	if NetApk.newer(own_version(), version) and apk.available():
		return "give"
	return ""

func _reject_extra(peer_id: int, problem: Dictionary, hello: Dictionary) -> Dictionary:
	# Gastgeber, NetSession.reject_hook: Zusatz zur Ablehnung bei anderer Spielversion (NetApk.host_decision).
	var d := NetApk.host_decision(str(problem.get("code", "")), own_version(), hello, own_offer(), apk != null and apk.can_receive())
	if d.extra.is_empty():
		return {}
	d.extra["name"] = session.my_name
	if d.serve:
		_log("Ablehnung mit Angebot: Version %s für „%s“ (Version %s)" % [own_version(), Proto.clean_name(str(hello.get("name", ""))), str(hello.get("game", "?"))])
		_want_serve()
	if not d.offer.is_empty() and not transfer.fetching():
		var offer: Dictionary = d.offer
		offer["address"] = str(session.peers.get(peer_id, {}).get("address", ""))
		offer["from"] = "guest"
		if apk_offer.is_empty() or apk_offer.get("sha256") != offer.sha256:
			apk_offer = offer
			transfer.reset_fetch()
			_log("„%s“ hat die neuere Version %s – sie lässt sich von %s:%d holen" % [offer.name, offer.version, offer.address, offer.port])
			notice.emit("%s hat die neuere Version %s." % [offer.name, offer.version])
			apk_changed.emit()
	return d.extra

func _apk_after_reject() -> void:
	# Mitspieler: Ablehnung des Gastgebers auswerten (NetApk.guest_decision) – neuere Version holen oder die eigene bereitstellen.
	var d := NetApk.guest_decision(session.reject_code, own_version(), session.reject_extra, not own_offer().is_empty(), apk != null and apk.can_receive())
	if not d.offer.is_empty() and not transfer.fetching():
		var offer: Dictionary = d.offer
		offer["address"] = session.host_address
		offer["from"] = "host"
		apk_offer = offer
		transfer.reset_fetch()
		_log("Gastgeber hat die neuere Version %s – Angebot %s:%d, %d Byte" % [offer.version, offer.address, offer.port, offer.size])
		apk_changed.emit()
	elif d.serve:
		apk_pull = {"version": d.host_version, "name": d.host_name}
		_log("Gastgeber „%s“ hat die ältere Version %s – stelle die eigene bereit" % [d.host_name, d.host_version])
		_want_serve()
		apk_changed.emit()

func _want_serve() -> void:
	_apk_serve = true
	apk.want_file()
	if not transfer.serving():
		transfer.max_rate = apk_rate
		transfer.corrupt_at = apk_corrupt
		var err := transfer.serve(apk_port)
		_log("Dateidienst auf Port %d: %s" % [apk_port, "läuft" if err == OK else "nicht möglich (%s)" % error_string(err)])
	_apk_poll()

func apk_fetch() -> bool:
	# Angebotene neuere Version holen (Fortschritt: transfer.progress(), apk_changed). Mitspieler binden sich dafür wie beim Beitritt
	# zu diesem Gastgeber; ein Gastgeber bindet sich nie neu (seine Bindung erreicht seine Mitspieler schon).
	if apk_offer.is_empty() or transfer.fetching():
		return false
	if mode != "host" and str(apk_offer.get("from", "")) == "host":
		_bind("join", str(apk_offer.address))
	transfer.fetch(str(apk_offer.address), int(apk_offer.port), int(apk_offer.size), str(apk_offer.sha256), apk_dir)
	_log("Hole Version %s von „%s“ (%s:%d, %s MB)" % [apk_offer.version, apk_offer.name, apk_offer.address, apk_offer.port, NetApk.megabytes(int(apk_offer.size))])
	apk_changed.emit()
	return true

func apk_cancel() -> void:
	if transfer.fetching():
		transfer.cancel_fetch()
		_log("Holen der neuen Version abgebrochen")
		apk_changed.emit()

func apk_dismiss() -> void:
	# Angebot verwerfen („Später“); ein laufendes Holen bleibt davon unberührt.
	if not transfer.fetching() and not apk_offer.is_empty():
		apk_offer = {}
		transfer.reset_fetch()
		apk_changed.emit()

func _apk_poll() -> void:
	transfer.poll()
	var cap := apk_rate if mode != "host" or phase == "lobby" else (mini(apk_rate, APK_ROUND_RATE) if apk_rate > 0 else APK_ROUND_RATE)
	if transfer.max_rate != cap:
		transfer.max_rate = cap
	if apk != null and apk.has_method("poll"):
		apk.poll()
	if _apk_serve and not transfer.has_file() and apk != null and apk.file_ready():
		var o: Dictionary = apk.offer()
		transfer.set_file(apk.file_path(), int(o.size), str(o.sha256))
		_log("Datei bereit zum Senden: %s (%s MB)" % [apk.file_path().get_file(), NetApk.megabytes(int(o.size))])
	var p := transfer.progress_raw()
	var st := transfer.stats()
	var sig := "%s|%s|%d|%d|%d" % [p.get("state", ""), p.get("error", ""), int(st.served), int(st.aborted), int(st.sending)]
	var now := Time.get_ticks_msec()
	if sig != _apk_sig or ((transfer.fetching() or int(st.sending) > 0) and now >= _apk_emit_ms):
		_apk_sig = sig
		_apk_emit_ms = now + 200
		apk_changed.emit()

func _log(text: String) -> void:
	if netlog != null:
		netlog.write(text)
	log_line.emit(text)
