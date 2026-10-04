class_name NetSession
extends Node

# ENet-Sitzung für den lokalen Mehrspieler (docs/MULTIPLAYER_RECHERCHE.md 4.1, 5.2): Host auf festem Port mit höchstens drei
# Mitspielern oder Beitritt per Adresse, Anmeldung mit Versionsprüfung, Echo-Ping mit RTT-/Jitter-/Verluststatistik und Schätzung
# des Uhrversatzes (schnellste Antwort der letzten Pings zählt). Benutzt den ENetMultiplayerPeer direkt – ohne SceneMultiplayer und
# RPCs –, damit die Sitzung nichts an Knotenpfade bindet und den Rest des Spiels nicht berührt. Rendering/UI/Netz verändern die
# Simulation nicht: Diese Klasse kennt keine Fahrzeuge.
#
# Nutzung: add_child(session); session.host("Anna") bzw. session.join("192.168.43.1", NetProtocol.GAME_PORT, "Ben").
# Eigene Nachrichten: session.send(peer_id, {"t": "lobby", …}) / send_all(…); Empfang über message_received(peer_id, msg).

const Proto := preload("res://scripts/net/net_protocol.gd")

signal state_changed(state: String, detail: String)
signal peer_joined(peer_id: int, info: Dictionary)
signal peer_left(peer_id: int, reason: String)
signal players_changed(players: Array)
signal message_received(peer_id: int, msg: Dictionary)
signal log_line(text: String)

const HELLO_TIMEOUT_MS := 5000
const KICK_GRACE_MS := 2000
const PING_TIMEOUT_USEC := 2_000_000
# ENet senkt seine Paketdrossel ca. 1 s nach dem Verbinden einmal für eine Sekunde auf 1/32 (gemessen am PC, Godot 4.6.1) und
# verwirft so lange unzuverlässige Pakete. Pings aus dieser Anlaufzeit zählen nicht als Netzverlust (summary: early_lost).
const WARMUP_USEC := 2_500_000
const THROTTLE_INTERVAL_MS := 1000
const THROTTLE_ACCELERATION := 32         # = ENetPacketPeer.PACKET_THROTTLE_SCALE: nach jedem guten Messwert sofort ungedrosselt
const ENET_PING_INTERVAL_MS := 100
# Eigene Trennung bei Funkstille (_tick) frühestens nach so vielen ms: In der Anlaufzeit verwirft ENet gut eine Sekunde lang alle
# unzuverlässigen Pakete (Ping/Pong), dann kommen nur die zuverlässigen an. Kürzere Grenzen (Tests) überlässt die Prüfung ENet.
const SILENCE_FLOOR_MS := 3000

var connect_timeout_ms := 6000
var ping_interval_ms := 250          # 0 = keine automatischen Pings
var ping_mode := MultiplayerPeer.TRANSFER_MODE_UNRELIABLE   # Pings messen die echte Laufzeit: ohne Wiederholung
var auto_poll := true                # false: poll() selbst aufrufen (Tests ohne Szenenbaum)
var state := "idle"                  # idle | hosting | connecting | handshake | connected | rejected | closing | closed
var detail := ""                     # deutscher Klartext zum Zustand (Fehler-/Ablehnungsgrund)
var reject_code := ""
var is_host := false
var my_id := 0
var my_name := "Fahrer"
var track_hash := ""                 # Platzhalter (Prüfsumme der Streckendatei, ab M3/M4 geprüft)
var check_track := false
var join_block := ""                 # Host: nicht leer = neue Mitspieler mit diesem Grund ablehnen (z. B. Rennen läuft schon)
# ENet-Zeitgrenze je Partner [Grenzwert, Minimum ms, Maximum ms]: so schnell fällt ein stummer Partner (abgestürzt, App lange im
# Hintergrund, aus dem WLAN) aus der Liste. ENet trennt, wenn ein zuverlässiges Paket seit Minimum ms unbestätigt ist und schon so oft
# wiederholt wurde, dass 2^(Versuche−1) den Grenzwert erreicht, spätestens nach Maximum ms – geprüft wird aber nur, wenn eine
# Wiederholung fällig ist, und deren Abstand verdoppelt sich: Ohne eigene Prüfung trennte ENet irgendwann zwischen Minimum und dem
# Doppelten. Darum trennt _tick() selbst, sobald ein Partner Minimum ms lang nichts geschickt hat (lebende Partner pingen und antworten
# alle ping_interval_ms). Ein Hänger des Hauptthreads zählt wie Funkstille: Am Steinbruch hing ein Gerät 5,1 s und flog mit der früheren
# Grenze 4–10 s heraus. Darum 8–20 s; beim Laden der Strecke (langsame Handys wie das S10) setzt NetLobby noch längere Grenzen
# (set_peer_timeout). Wo es schnell gehen muss, wacht die Anwendung selbst über silent_usec() (Turbo im Rennen, NetRace).
var peer_timeout := [16, 8000, 20000]
var hello_override := {}             # nur Tests: Felder der eigenen Anmeldung ersetzen (z. B. falsche Spielversion)
var hello_extra := {}                # weitere Felder der eigenen Anmeldung (NetLobby: „apk“, Angebot der eigenen APK, NetApk)
# Host: Zusatz zur Ablehnung (NetProtocol.encode_reject, „x“) – Callable(peer_id, problem {code, reason}, hello) -> Dictionary.
var reject_hook := Callable()
var reject_extra := {}               # Mitspieler: Zusatz der letzten Ablehnung (z. B. Spielversion und APK-Angebot des Gastgebers)
var enet: ENetMultiplayerPeer
var host_address := ""
var port := 0
var peers := {}                      # peer_id -> {name, accepted, address, port, game, model, os, since_ms, stats: PingStats}
var players: Array = []              # [{id, name, host}] – vom Host verteilt
var rejected_count := 0
var _state_ms := 0
var _next_ping_ms := 0
var _in_poll := false
var _close_after_poll := ""
var _kick_at := {}                   # peer_id -> Zeit (ms), ab der hart getrennt wird
var skipped_sends := 0               # Pakete, die nicht hinausgingen, weil der Partner gerade getrennt wird (siehe _put)
var _graceful_until := 0             # close_gracefully: spätestens dann schließen (ms), 0 = nicht aktiv

class PingStats:
	# Echo-Ping eines Partners: RTT (ms), Jitter nach RFC 3550 (geglättet), Verlust, Uhrversatz (Partner minus eigene Uhr, µs).
	var seq := 0
	var pending := {}                # seq -> Sendezeit (µs)
	var sent := 0
	var received := 0
	var lost := 0
	var late := 0
	var early_lost := 0
	var warmup_until_usec := 0       # Verluste von Pings vor diesem Zeitpunkt zählen als Anlauf (siehe WARMUP_USEC)
	var last_rtt := -1.0
	var min_rtt := -1.0
	var max_rtt := -1.0
	var sum_rtt := 0.0
	var jitter := 0.0
	var recent: Array = []           # letzte 40 Ergebnisse (true = Antwort, false = verloren)
	var samples: Array = []          # letzte 16 [rtt_usec, offset_usec]
	var offset_usec := 0
	var offset_valid := false

	func next(now: int) -> int:
		seq += 1
		pending[seq] = now
		sent += 1
		return seq

	func on_pong(n: int, sent_usec: int, remote_usec: int, now: int) -> void:
		if not pending.has(n) or int(pending[n]) != sent_usec:
			late += 1
			return
		pending.erase(n)
		var rtt_usec := maxi(0, now - sent_usec)
		var rtt := rtt_usec / 1000.0
		if last_rtt >= 0.0:
			jitter += (absf(rtt - last_rtt) - jitter) / 16.0
		last_rtt = rtt
		min_rtt = rtt if min_rtt < 0.0 else minf(min_rtt, rtt)
		max_rtt = maxf(max_rtt, rtt)
		sum_rtt += rtt
		received += 1
		_mark(true)
		# Partneruhr beim Empfang ≈ remote + rtt/2 → Versatz = remote + rtt/2 − now. Die schnellste der letzten 16 Antworten zählt.
		samples.append([rtt_usec, remote_usec + rtt_usec / 2 - now])
		if samples.size() > 16:
			samples.pop_front()
		var best: Array = samples[0]
		for s in samples:
			if int(s[0]) < int(best[0]):
				best = s
		offset_usec = int(best[1])
		offset_valid = true

	func expire(now: int) -> void:
		for n in pending.keys():
			if now - int(pending[n]) > PING_TIMEOUT_USEC:
				if int(pending[n]) < warmup_until_usec:
					early_lost += 1         # Anlauf: ENet-Drossel nach dem Verbinden, nicht das Netz
				else:
					lost += 1
					_mark(false)
				pending.erase(n)

	func _mark(ok: bool) -> void:
		recent.append(ok)
		if recent.size() > 40:
			recent.pop_front()

	func summary() -> Dictionary:
		var recent_lost := recent.count(false)
		return {"rtt_ms": last_rtt, "min_ms": min_rtt, "max_ms": max_rtt, "avg_ms": sum_rtt / received if received > 0 else -1.0,
			"jitter_ms": jitter, "sent": sent, "received": received, "lost": lost, "late": late,
			"early_lost": early_lost, "pending": pending.size(), "loss_pct": 100.0 * lost / maxi(1, received + lost), "recent_loss_pct": 100.0 * recent_lost / maxi(1, recent.size()),
			"offset_ms": offset_usec / 1000.0 if offset_valid else 0.0, "offset_valid": offset_valid}

# --- Öffentliche Schnittstelle ---

func host(player_name := "Host", game_port := Proto.GAME_PORT) -> Error:
	close()
	enet = ENetMultiplayerPeer.new()
	# Ein Platz mehr als erlaubt: Der vierte Mitspieler bekommt so noch den Grund „Spiel ist voll“ statt einer stummen Absage.
	var err := enet.create_server(game_port, Proto.MAX_CLIENTS + 1, Proto.CUSTOM_CHANNELS)
	if err != OK:
		enet = null
		_set_state("closed", "Host konnte Port %d nicht öffnen (%s) – läuft schon ein Host auf diesem Gerät?" % [game_port, error_string(err)])
		return err
	_wire()
	is_host = true
	my_id = 1
	my_name = Proto.clean_name(player_name, "Host")
	port = game_port
	host_address = ""
	players = [{"id": 1, "name": my_name, "host": true}]
	_set_state("hosting", "Warte auf Mitspieler (Port %d)" % game_port)
	_log("Host gestartet auf Port %d als „%s“ (Protokoll %d, Spiel %s, Physik %s)" % [game_port, my_name, Proto.VERSION, Proto.game_version(), Proto.physics_version()])
	return OK

func join(address: String, game_port := Proto.GAME_PORT, player_name := "Fahrer") -> Error:
	close()
	enet = ENetMultiplayerPeer.new()
	var err := enet.create_client(address, game_port, Proto.CUSTOM_CHANNELS)
	if err != OK:
		enet = null
		_set_state("closed", "Verbindung zu %s:%d nicht möglich (%s)" % [address, game_port, error_string(err)])
		return err
	_wire()
	is_host = false
	my_id = 0
	reject_code = ""
	reject_extra = {}
	my_name = Proto.clean_name(player_name)
	host_address = address
	port = game_port
	_set_state("connecting", "Verbinde mit %s:%d …" % [address, game_port])
	_log("Verbinde mit %s:%d als „%s“" % [address, game_port, my_name])
	return OK

func close(reason := "") -> void:
	# Beendet die Sitzung; während poll() erst danach (ENet-Signale laufen dort).
	if _in_poll:
		_close_after_poll = reason if reason != "" else "Sitzung beendet"
		return
	if enet != null:
		_log("Sitzung geschlossen%s" % (": " + reason if reason != "" else ""))
		enet.close()
		enet = null
	peers.clear()
	players.clear()
	_kick_at.clear()
	_graceful_until = 0
	is_host = false
	my_id = 0
	if state not in ["idle", "closed", "rejected"]:
		_set_state("closed", reason if reason != "" else "Sitzung beendet")

func close_gracefully(msg := {}, wait_ms := 600) -> void:
	# Eine letzte Nachricht schicken (Host: „Gastgeber hat beendet“, Mitspieler: „bye“) und sauber trennen – ENet trennt erst, wenn die
	# zuverlässigen Pakete angekommen sind (sonst sieht die Gegenseite die Trennung vor der Nachricht). Die Sitzung schließt, sobald
	# alle weg sind, spätestens nach wait_ms; poll() weiter rufen.
	if enet == null or not is_ready() or (is_host and accepted_ids().is_empty()):
		close("Spiel beendet" if is_host else "Verlassen")
		return
	if not msg.is_empty():
		send_all(msg)
	flush()
	if is_host:
		for id in peers.keys():
			_disconnect_later(id)
	else:
		var packet_peer := enet.get_peer(1)
		if packet_peer != null:
			packet_peer.peer_disconnect_later()
	_graceful_until = Time.get_ticks_msec() + wait_ms
	_set_state("closing", "Spiel wird beendet …" if is_host else "Melde mich ab …")
	_log("Beende die Sitzung – trenne %d Partner" % peers.size())

func is_active() -> bool:
	return enet != null and state in ["hosting", "connecting", "handshake", "connected"]

func is_ready() -> bool:
	# Host läuft bzw. Mitspieler angenommen.
	return state == "hosting" or state == "connected"

func accepted_ids() -> Array:
	var out := []
	for id in peers:
		if peers[id].accepted:
			out.append(id)
	return out

func send(peer_id: int, msg: Dictionary, mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE, channel := Proto.CHANNEL_CONTROL) -> Error:
	# Mitspieler senden an den Host mit peer_id 1. Größe höchstens NetProtocol.MAX_MESSAGE_BYTES.
	if enet == null or enet.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return ERR_UNCONFIGURED
	if not peers.has(peer_id) or (is_host and not peers[peer_id].accepted):
		return ERR_DOES_NOT_EXIST
	var bytes := Proto.encode(msg)
	if bytes.size() > Proto.MAX_MESSAGE_BYTES:
		return ERR_INVALID_DATA
	return _put(peer_id, bytes, mode, channel)

func send_all(msg: Dictionary, mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE, channel := Proto.CHANNEL_CONTROL) -> void:
	# Host: an alle angenommenen Mitspieler; Mitspieler: an den Host.
	if not is_host:
		send(1, msg, mode, channel)
		return
	for id in accepted_ids():
		send(id, msg, mode, channel)

func kick(peer_id: int, reason: String, code := "kick", extra := {}) -> void:
	if not is_host or not peers.has(peer_id):
		return
	_put(peer_id, Proto.encode_reject(code, reason, extra), MultiplayerPeer.TRANSFER_MODE_RELIABLE, Proto.CHANNEL_CONTROL)
	_disconnect_later(peer_id)

func stats(peer_id: int) -> Dictionary:
	# Ping-Statistik eines Partners (Mitspieler: peer_id 1 = Host) plus ENet-eigene RTT. {} wenn unbekannt.
	if not peers.has(peer_id):
		return {}
	var out: Dictionary = peers[peer_id].stats.summary()
	out["enet_rtt_ms"] = -1.0
	if enet != null:
		var packet_peer := enet.get_peer(peer_id)
		if packet_peer != null:
			out["enet_rtt_ms"] = packet_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)
			out["enet_loss"] = packet_peer.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS) / float(ENetPacketPeer.PACKET_LOSS_SCALE)
			# Paketdrossel (32 = ungedrosselt). ENet senkt sie ca. 1 s nach dem Verbinden einmal auf 1 und verwirft dann unzuverlässige
			# Pakete, bis sie wieder steigt (am PC gemessen, Godot 4.6.1) – darum zeigt der Ping kurz nach dem Beitritt Verlust.
			out["enet_throttle"] = packet_peer.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE)
	return out

func set_peer_timeout(values: Array) -> void:
	# ENet-Zeitgrenze [Grenzwert, Minimum ms, Maximum ms] sofort für alle verbundenen Partner und für künftige (NetLobby: lang beim
	# Laden, sonst normal). ENet liest die Werte bei jeder Prüfung neu – auch eine schon laufende Funkstille gilt danach länger.
	peer_timeout = values.duplicate()
	if enet == null:
		return
	for id in peers:
		var packet_peer := enet.get_peer(id)
		if packet_peer != null and packet_peer.is_active():
			packet_peer.set_timeout(int(peer_timeout[0]), int(peer_timeout[1]), int(peer_timeout[2]))

func silent_usec(peer_id: int) -> int:
	# Seit wie vielen µs kam von diesem Partner kein Paket mehr (Nachricht, Ping oder Pong)? -1 = unbekannt. Für schnelle Erkennung in
	# der Anwendung (NetRace: Turbo eines abgestürzten Mitspielers nach 0,5 s loslassen) – ENet selbst wartet absichtlich Sekunden.
	if not peers.has(peer_id):
		return -1
	return Time.get_ticks_usec() - int(peers[peer_id].get("heard_usec", Time.get_ticks_usec()))

func host_time_usec() -> int:
	# Gemeinsame Uhr: die Host-Uhr (Time.get_ticks_usec() des Hosts), beim Mitspieler über den geschätzten Versatz.
	if is_host or not peers.has(1):
		return Time.get_ticks_usec()
	return Time.get_ticks_usec() + int(peers[1].stats.offset_usec)

func clock_synced() -> bool:
	return is_host or (peers.has(1) and int(peers[1].stats.received) >= 4)

# --- Ablauf ---

func _ready() -> void:
	set_process(true)

func _process(_delta: float) -> void:
	if auto_poll:
		poll()

func _exit_tree() -> void:
	close("Bildschirm geschlossen")

func poll() -> void:
	if enet == null:
		return
	_in_poll = true
	enet.poll()
	while enet != null and enet.get_available_packet_count() > 0:
		var from := enet.get_packet_peer()
		var bytes := enet.get_packet()
		if peers.has(from):
			peers[from]["heard_usec"] = Time.get_ticks_usec()
		_handle(from, bytes)
	_in_poll = false
	if _close_after_poll != "":
		var reason := _close_after_poll
		_close_after_poll = ""
		close(reason)
		return
	_tick()

func _tick() -> void:
	if enet == null:
		return
	var now_ms := Time.get_ticks_msec()
	var waited := now_ms - _state_ms
	if state == "connecting":
		if enet.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
			close("Keine Verbindung zu %s:%d – Host nicht erreichbar." % [host_address, port])
		elif waited > connect_timeout_ms:
			close("Host %s:%d antwortet nicht (%.0f s). Gleiches WLAN? Mobile Daten aus oder „an WLAN binden“ probieren." % [host_address, port, connect_timeout_ms / 1000.0])
		return
	if state == "handshake" and waited > HELLO_TIMEOUT_MS:
		close("Host hat die Anmeldung nicht beantwortet.")
		return
	if _graceful_until > 0 and (peers.is_empty() or now_ms > _graceful_until):
		close("Spiel beendet")
		return
	if is_host:
		for id in peers.keys():
			if not peers[id].accepted and not _kick_at.has(id) and now_ms - int(peers[id].since_ms) > HELLO_TIMEOUT_MS:
				_log("Gerät %d hat sich nicht angemeldet – getrennt" % id)
				kick(id, "Anmeldung fehlt.", "bad")
		for id in _kick_at.keys():
			if now_ms > int(_kick_at[id]):
				_kick_at.erase(id)
				if peers.has(id):
					enet.disconnect_peer(id, true)
					_drop_peer(id, "getrennt")
	if ping_interval_ms > 0 and is_ready():
		# Funkstille ab der ENet-Mindestgrenze: gleich trennen statt auf ENets nächste, sich verdoppelnde Wiederholung zu warten. Nach einem
		# eigenen Hänger kommen die gestauten Pakete in poll() vor dieser Prüfung an – der Hängende trennt also niemanden zu Unrecht.
		var limit := maxi(int(peer_timeout[1]), SILENCE_FLOOR_MS) * 1000
		for id in (accepted_ids() if is_host else [1]):
			var quiet := silent_usec(id)
			if quiet <= limit:
				continue
			if is_host:
				_log("Mitspieler %d „%s“ seit %.1f s stumm – getrennt" % [id, peers[id].name, quiet / 1000000.0])
				_kick_at.erase(id)
				enet.disconnect_peer(id, true)
				_drop_peer(id, "Verbindung getrennt")
			else:
				close("Verbindung zum Host verloren (%.1f s ohne Antwort)." % (quiet / 1000000.0))
				return
	var now := Time.get_ticks_usec()
	for id in peers:
		peers[id].stats.expire(now)
	if ping_interval_ms > 0 and now_ms >= _next_ping_ms and is_ready():
		_next_ping_ms = now_ms + ping_interval_ms
		for id in (accepted_ids() if is_host else [1]):
			if peers.has(id):
				var n: int = peers[id].stats.next(now)
				_put(id, Proto.encode({"t": "ping", "n": n, "c": now}), ping_mode, Proto.CHANNEL_CONTROL, true)

func _wire() -> void:
	enet.peer_connected.connect(_on_peer_connected)
	enet.peer_disconnected.connect(_on_peer_disconnected)

func _on_peer_connected(id: int) -> void:
	# ENet drosselt unzuverlässige Pakete (Paketdrossel 0–32), sobald die gemessene RTT schwankt – mit Abfrage je Bild schwankt sie
	# immer; am PC gingen so über die Hälfte der Pings verloren. Darum: Drossel nie senken (Verzögerung 0), bei jeder guten Messung
	# sofort voll öffnen (Beschleunigung 32), und ENet-eigene Pings alle 100 ms, damit es oft genug misst. Rest: ENet setzt ca. 1 s nach
	# dem Verbinden einmal für etwa eine Sekunde die Obergrenze auf 1 (Anlaufzeit, siehe WARMUP_USEC).
	var throttled := enet.get_peer(id)
	if throttled != null:
		throttled.throttle_configure(THROTTLE_INTERVAL_MS, THROTTLE_ACCELERATION, 0)
		throttled.ping_interval(ENET_PING_INTERVAL_MS)
		throttled.set_timeout(int(peer_timeout[0]), int(peer_timeout[1]), int(peer_timeout[2]))
	if is_host:
		var address := ""
		var remote_port := 0
		var packet_peer := enet.get_peer(id)
		if packet_peer != null:
			address = packet_peer.get_remote_address()
			remote_port = packet_peer.get_remote_port()
		peers[id] = {"name": "?", "accepted": false, "address": address, "port": remote_port, "game": "", "model": "", "os": "",
			"since_ms": Time.get_ticks_msec(), "heard_usec": Time.get_ticks_usec(), "stats": PingStats.new()}
		_log("Gerät %d verbunden von %s:%d – warte auf Anmeldung" % [id, address, remote_port])
	elif id == 1:
		peers[1] = {"name": "Host", "accepted": true, "address": host_address, "port": port, "game": "", "model": "", "os": "",
			"since_ms": Time.get_ticks_msec(), "heard_usec": Time.get_ticks_usec(), "stats": PingStats.new()}
		_set_state("handshake", "Verbunden – Anmeldung läuft …")
		var hello := Proto.make_hello(my_name, track_hash)
		hello.merge(hello_extra, true)
		hello.merge(hello_override, true)
		_put(1, Proto.encode(hello), MultiplayerPeer.TRANSFER_MODE_RELIABLE, Proto.CHANNEL_CONTROL)
		_log("ENet-Verbindung zu %s:%d steht nach %d ms – sende Anmeldung" % [host_address, port, Time.get_ticks_msec() - _state_ms])

func _on_peer_disconnected(id: int) -> void:
	if is_host:
		_kick_at.erase(id)
		_drop_peer(id, "Verbindung getrennt")
	elif id == 1:
		var reason := "Verbindung zum Host verloren."
		if state == "handshake":
			reason = "Host hat die Verbindung während der Anmeldung getrennt."
		peers.erase(1)
		if state == "rejected":
			reason = detail
		if _in_poll:
			_close_after_poll = reason
		else:
			close(reason)

func _drop_peer(id: int, reason: String) -> void:
	if not peers.has(id):
		return
	var was_accepted: bool = peers[id].accepted
	var who: String = peers[id].name
	if peers[id].get("bye", false):
		reason = "abgemeldet"
	peers.erase(id)
	if was_accepted:
		_log("Mitspieler %d „%s“ weg (%s)" % [id, who, reason])
		peer_left.emit(id, reason)
		_update_players()

func _handle(from: int, bytes: PackedByteArray) -> void:
	var msg := Proto.decode(bytes)
	if msg.is_empty():
		_log("Ungültiges Paket von %d (%d Byte) verworfen" % [from, bytes.size()])
		return
	var type: String = msg.t
	if type == "ping":
		if peers.has(from) and (not is_host or peers[from].accepted):
			_put(from, Proto.encode({"t": "pong", "n": msg.get("n", 0), "c": msg.get("c", 0), "h": Time.get_ticks_usec()}),
				ping_mode, Proto.CHANNEL_CONTROL, true)
		return
	if type == "pong":
		if peers.has(from) and msg.get("n") is int and msg.get("c") is int and msg.get("h") is int:
			peers[from].stats.on_pong(msg.n, msg.c, msg.h, Time.get_ticks_usec())
		return
	if is_host:
		_handle_host(from, type, msg)
	else:
		_handle_client(from, type, msg)

func _handle_host(from: int, type: String, msg: Dictionary) -> void:
	if not peers.has(from):
		return
	var peer: Dictionary = peers[from]
	if not peer.accepted:
		if type != "hello" and type != "_foreign":
			return
		var local := {"game": Proto.game_version(), "physics": Proto.physics_version(), "track": track_hash}
		# Reihenfolge der Gründe: Version/Protokoll/Strecken, dann „Rennen läuft“, dann „voll“.
		var problem := Proto.check_hello(msg, local, 0 if join_block != "" else accepted_ids().size(), check_track)
		if problem.is_empty() and join_block != "":
			problem = {"code": "busy", "reason": join_block}
		peer.game = str(msg.get("game", "?"))
		peer.model = str(msg.get("model", "")).left(40)
		peer.os = str(msg.get("os", "")).left(20)
		if not problem.is_empty():
			rejected_count += 1
			_log("Gerät %d (%s, %s %s, Spiel %s) abgelehnt: %s" % [from, peer.address, peer.os, peer.model, peer.game, problem.reason])
			var extra = reject_hook.call(from, problem, msg) if reject_hook.is_valid() else {}
			kick(from, problem.reason, problem.code, extra if extra is Dictionary else {})
			return
		var taken := []
		for p in players:
			taken.append(p.name)
		peer.name = Proto.unique_name(Proto.clean_name(str(msg.get("name", ""))), taken)
		peer.accepted = true
		peer.stats.warmup_until_usec = Time.get_ticks_usec() + WARMUP_USEC
		_put(from, Proto.encode({"t": "welcome", "id": from, "name": peer.name, "host": my_name, "game": Proto.game_version(),
			"proto": Proto.VERSION, "host_time": Time.get_ticks_usec()}), MultiplayerPeer.TRANSFER_MODE_RELIABLE, Proto.CHANNEL_CONTROL)
		_log("Mitspieler %d „%s“ angenommen (%s, %s %s)" % [from, peer.name, peer.address, peer.os, peer.model])
		_update_players()
		peer_joined.emit(from, peer)
		return
	if type == "bye":
		_log("Mitspieler %d meldet sich ab" % from)
		peer["bye"] = true
		_disconnect_later(from)
		return
	if type in Proto.RESERVED or type.begins_with("_"):
		return
	message_received.emit(from, msg)

func _handle_client(from: int, type: String, msg: Dictionary) -> void:
	if from != 1:
		return
	match type:
		"reject":
			reject_code = str(msg.get("code", ""))
			reject_extra = msg.get("x", {}) if msg.get("x") is Dictionary else {}
			var reason := str(msg.get("reason", "Abgelehnt.")).left(300)
			_log("Vom Host abgelehnt (%s): %s" % [reject_code, reason])
			_set_state("rejected", reason)
			_close_after_poll = reason
		"welcome":
			if state != "handshake":
				return
			my_id = enet.get_unique_id()
			my_name = str(msg.get("name", my_name))
			peers[1].name = Proto.clean_name(str(msg.get("host", "Host")), "Host")
			peers[1].game = str(msg.get("game", ""))
			_set_state("connected", "Verbunden mit „%s“ als „%s“" % [peers[1].name, my_name])
			_log("Angenommen als %d „%s“ nach %d ms" % [my_id, my_name, Time.get_ticks_msec() - _state_ms])
			_next_ping_ms = 0
			peers[1].stats.warmup_until_usec = Time.get_ticks_usec() + WARMUP_USEC
		"players":
			if msg.get("list") is Array:
				players = []
				for p in msg.list:
					if p is Dictionary:
						players.append({"id": int(p.get("id", 0)), "name": Proto.clean_name(str(p.get("name", "?"))), "host": bool(p.get("host", false))})
				players_changed.emit(players)
		_:
			if state == "connected" and not type in Proto.RESERVED and not type.begins_with("_"):
				message_received.emit(from, msg)

func _update_players() -> void:
	if state == "closing":
		return
	players = [{"id": 1, "name": my_name, "host": true}]
	var ids := accepted_ids()
	ids.sort()
	for id in ids:
		players.append({"id": id, "name": peers[id].name, "host": false})
	send_all({"t": "players", "list": players})
	players_changed.emit(players)

func _disconnect_later(id: int) -> void:
	var packet_peer: ENetPacketPeer = enet.get_peer(id) if enet != null else null
	if packet_peer != null:
		packet_peer.peer_disconnect_later()
	_kick_at[id] = Time.get_ticks_msec() + KICK_GRACE_MS

func flush() -> void:
	# Wartende Pakete sofort senden statt erst beim nächsten poll() (z. B. direkt nach einem Schnappschuss).
	if enet != null and enet.host != null:
		enet.host.flush()

func _put(peer_id: int, bytes: PackedByteArray, mode: int, channel: int, now := false) -> Error:
	# Alle Pakete laufen hier durch, auch Ping/Pong, Anmeldung und Ablehnung: nur an Partner, die ENet gerade als verbunden führt. Wird
	# ein Partner getrennt (Abmeldung „bye“, Ablehnung, Spielende), räumt ENet seine Kanäle sofort ab, Godot führt ihn aber bis zum
	# Trennungsereignis weiter – ein Paket dorthin ergäbe „Unable to send packet on channel 1, max channels: 0“.
	if enet == null or enet.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED or not peers.has(peer_id):
		return ERR_UNCONFIGURED
	var packet_peer := enet.get_peer(peer_id)
	if packet_peer == null or packet_peer.get_state() != ENetPacketPeer.STATE_CONNECTED:
		skipped_sends += 1
		return ERR_UNAVAILABLE
	enet.set_target_peer(peer_id)
	enet.set_transfer_mode(mode)
	enet.set_transfer_channel(channel)
	var err := enet.put_packet(bytes)
	if now:
		flush()   # Ping/Pong: Laufzeit ohne Warten auf den nächsten Bildtakt messen
	return err

func _set_state(new_state: String, text: String) -> void:
	state = new_state
	detail = text
	_state_ms = Time.get_ticks_msec()
	state_changed.emit(new_state, text)

func _log(text: String) -> void:
	log_line.emit(text)
