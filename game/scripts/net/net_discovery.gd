class_name NetDiscovery
extends Node

# Host-Suche im lokalen Netz (docs/MULTIPLAYER_RECHERCHE.md 4.2), dreistufig:
#  1. Rundruf: Der Host kündigt sich jede Sekunde an (UDP an 255.255.255.255 und an den gerichteten Rundruf jedes eigenen
#     IPv4-Netzes, Port BEACON_PORT). Mitspieler fragen zusätzlich selbst per Rundruf („Wer ist Host?“, Port DISCOVERY_PORT);
#     der Host antwortet direkt an den Absender.
#  2. Gateway-Probe: Im Handy-Hotspot ist der Host das Gateway der anderen – die Anfrage geht dort direkt hin (Unicast).
#  3. Manuelle Adresse: dieselbe Anfrage an eine eingetippte Adresse.
# Jede Antwort trägt den Weg der Anfrage („re“), damit der Netztest zeigt, welcher Weg auf welchem Gerät funktioniert.
# Der gerichtete Rundruf ist nötig, weil 255.255.255.255 bei eingeschalteten mobilen Daten oft ins Mobilnetz statt ins WLAN geht.
# Die Suche beeinflusst keine Simulation; sie liefert nur Adressen.

const Proto := preload("res://scripts/net/net_protocol.gd")
const Android := preload("res://scripts/net/net_android.gd")

signal game_found(key: String, info: Dictionary)
signal games_changed
signal log_line(text: String)

var discovery_port := Proto.DISCOVERY_PORT
var beacon_port := Proto.BEACON_PORT
var announce_interval_ms := 1000
var query_interval_ms := 1000
var expire_after_ms := 4500
var refresh_targets_ms := 5000
var stats_interval_ms := 10000
var auto_poll := true
var use_broadcast := true           # false: nur Unicast-Ziele (Gateway, Adressen, lokal) – für Tests
var probe_local := false            # zusätzlich 127.0.0.1 fragen bzw. dorthin ankündigen (PC-Tests)
var mode := ""                      # "" | "host" | "search"
var host_info := {}                 # name, port, players, max
var sid := ""                       # Sitzungskennung: eigene Ankündigungen werden ignoriert
var gateway := ""                   # Gateway-Probe (Android: NetAndroid.wifi_gateway())
var manual: Array = []              # eingetippte Adressen
var games := {}                     # Sitzungskennung (sonst "ip:port") -> {address, addresses, port, name, players, max, game,
                                    #   physics, proto, compatible, note, busy, via {kürzel: Anzahl}, first_ms, last_ms, sid, reply_ms}
var counters := {}                  # "send:<weg>", "err:<weg>", "recv:<weg>", "query:<weg>" -> Anzahl
var targets: Array = []             # [{address, kind, iface}]
var passive_ok := false             # Mitspieler: Ankündigungs-Port gebunden
var _listen: PacketPeerUDP          # Host: DISCOVERY_PORT; Mitspieler: BEACON_PORT (passiv)
var _query: PacketPeerUDP           # Mitspieler: freier Port für Anfragen und Antworten
var _start_ms := 0
var _next_send_ms := 0
var _next_targets_ms := 0
var _next_stats_ms := 0
var _seq := 0
var _query_sent := {}               # Nummer der Anfrage -> Sendezeit (µs), für die Antwortzeit
var _logged := {}                   # einmalige Logzeilen (Fehler je Ziel, erste Anfrage je Absender)
var _last_stats := ""

func start_host(info: Dictionary) -> Error:
	# Ankündigen und auf Anfragen antworten. info: name, port (ENet), players, max.
	stop()
	mode = "host"
	host_info = info.duplicate()
	sid = "%08x" % (randi() & 0x7fffffff)
	host_info["sid"] = sid
	_listen = PacketPeerUDP.new()
	_listen.set_broadcast_enabled(true)
	var err := _listen.bind(discovery_port, "0.0.0.0")   # nur IPv4: Rundruf gibt es nur dort
	if err != OK:
		_log("Such-Port %d nicht frei (%s) – nur Ankündigungen, keine Antworten" % [discovery_port, error_string(err)])
	_begin()
	_log("Ankündigung gestartet: „%s“, ENet-Port %d, Such-Port %d, Ankündigungs-Port %d" % [host_info.get("name", "?"), int(host_info.get("port", 0)), discovery_port, beacon_port])
	return OK

func update_host_info(info: Dictionary) -> void:
	for key in info:
		host_info[key] = info[key]

func restart_host() -> Error:
	# Ankündigung mit neuem Socket fortsetzen, gleiche Sitzungskennung (die Suchenden sehen dasselbe Spiel). Nötig, wenn die WLAN-Bindung
	# gelöst wurde: Android-Sockets behalten die Bindung, mit der sie entstanden – ein gebundener erreicht den eigenen Hotspot nicht.
	if mode != "host":
		return ERR_UNCONFIGURED
	var keep := sid
	var info := host_info.duplicate()
	var err := start_host(info)
	sid = keep
	host_info["sid"] = keep
	return err

func start_search() -> Error:
	stop()
	mode = "search"
	if sid == "":
		sid = "%08x" % (randi() & 0x7fffffff)
	_query = PacketPeerUDP.new()
	_query.set_broadcast_enabled(true)
	var err := _query.bind(0, "0.0.0.0")
	if err != OK:
		_log("Such-Socket nicht anlegbar (%s)" % error_string(err))
		_query = null
		mode = ""
		return err
	_listen = PacketPeerUDP.new()
	_listen.set_broadcast_enabled(true)
	passive_ok = _listen.bind(beacon_port, "0.0.0.0") == OK
	if not passive_ok:
		_listen = null
		_log("Ankündigungs-Port %d belegt – nur aktive Suche (Anfrage/Antwort)" % beacon_port)
	_begin()
	_log("Suche gestartet (Antwort-Port %d, Ankündigungen %s)" % [_query.get_local_port(), "an" if passive_ok else "aus"])
	return OK

func stop() -> void:
	if mode != "":
		_log("%s beendet" % ("Ankündigung" if mode == "host" else "Suche"))
		_log_stats(true)
	if _listen != null:
		_listen.close()
	if _query != null:
		_query.close()
	_listen = null
	_query = null
	mode = ""
	passive_ok = false

func clear_games() -> void:
	games.clear()
	games_changed.emit()

func add_manual(address: String) -> void:
	if Proto.ipv4_to_int(address) > 0 and not manual.has(address):
		manual.append(address)

func sorted_games() -> Array:
	# Gefundene Spiele, passende zuerst, dann nach erster Sichtung.
	var list := games.values()
	list.sort_custom(func(a, b): return a.compatible and not b.compatible or (a.compatible == b.compatible and int(a.first_ms) < int(b.first_ms)))
	return list

func via_text(info: Dictionary) -> String:
	var parts := []
	for kind in info.get("via", {}):
		parts.append(Proto.VIA_TEXT.get(kind, kind))
	return ", ".join(parts)

func elapsed_ms() -> int:
	return Time.get_ticks_msec() - _start_ms

# --- Ablauf ---

func _process(_delta: float) -> void:
	if auto_poll:
		poll()

func _exit_tree() -> void:
	stop()

func poll() -> void:
	if mode == "":
		return
	var now := Time.get_ticks_msec()
	if now >= _next_targets_ms:
		_next_targets_ms = now + refresh_targets_ms
		_refresh_targets()
	if mode == "host":
		_poll_host(now)
	else:
		_poll_search(now)
	if now >= _next_stats_ms:
		_next_stats_ms = now + stats_interval_ms
		_log_stats(false)

func _begin() -> void:
	_start_ms = Time.get_ticks_msec()
	_next_send_ms = 0
	_next_targets_ms = 0
	_next_stats_ms = _start_ms + stats_interval_ms
	counters.clear()
	_logged.clear()
	_last_stats = ""

func _refresh_targets() -> void:
	var fresh := []
	if use_broadcast:
		fresh.append({"address": "255.255.255.255", "kind": "bcast", "iface": ""})
		for iface in Android.interfaces():
			var bc := str(iface.get("broadcast", ""))
			if Proto.ipv4_to_int(bc) <= 0:
				bc = Proto.directed_broadcast(str(iface.address), int(iface.get("prefix", 24)))
			if bc != "" and not fresh.any(func(t): return t.address == bc):
				fresh.append({"address": bc, "kind": "subnet", "iface": "%s %s/%d" % [iface.get("name", ""), iface.address, int(iface.get("prefix", 24))]})
	if mode == "search":
		if Proto.ipv4_to_int(gateway) > 0:
			fresh.append({"address": gateway, "kind": "gateway", "iface": ""})
		for address in manual:
			fresh.append({"address": str(address), "kind": "manual", "iface": ""})
	if probe_local:
		fresh.append({"address": "127.0.0.1", "kind": "local", "iface": ""})
	var text := ", ".join(fresh.map(func(t): return "%s (%s%s)" % [t.address, Proto.VIA_TEXT.get(t.kind, t.kind), (" " + t.iface) if t.iface != "" else ""]))
	if text != ", ".join(targets.map(func(t): return "%s (%s%s)" % [t.address, Proto.VIA_TEXT.get(t.kind, t.kind), (" " + t.iface) if t.iface != "" else ""])):
		_log("Ziele: " + (text if text != "" else "keine"))
	targets = fresh

func _send(socket: PacketPeerUDP, address: String, port: int, bytes: PackedByteArray, kind: String) -> void:
	socket.set_dest_address(address, port)
	var err := socket.put_packet(bytes)
	if err == OK:
		_count("send:" + kind)
	else:
		_count("err:" + kind)
		var key := "err %s %s %d" % [kind, address, err]
		if not _logged.has(key):
			_logged[key] = true
			_log("Senden an %s:%d (%s) fehlgeschlagen: %s" % [address, port, Proto.VIA_TEXT.get(kind, kind), error_string(err)])

func _poll_host(now: int) -> void:
	if _listen == null:
		return
	if now >= _next_send_ms:
		_next_send_ms = now + announce_interval_ms
		_seq += 1
		host_info["n"] = _seq
		var beacon := Proto.make_beacon(host_info)
		for t in targets:
			_send(_listen, t.address, beacon_port, beacon, t.kind)
	while _listen.get_available_packet_count() > 0:
		var bytes := _listen.get_packet()
		var ip := _listen.get_packet_ip()
		var from_port := _listen.get_packet_port()
		var q := Proto.parse_query(bytes)
		if q.is_empty() or q.sid == sid:
			continue
		var via: String = q.via if Proto.VIA_TEXT.has(q.via) else "manual"
		_count("query:" + via)
		var key := "query %s %s" % [ip, via]
		if not _logged.has(key):
			_logged[key] = true
			_log("Suchanfrage von %s:%d über %s (Spiel %s, Protokoll %d) – antworte" % [ip, from_port, Proto.VIA_TEXT.get(via, via), q.game, q.proto])
		var reply := host_info.duplicate()
		reply["q"] = q.n
		_send(_listen, ip, from_port, Proto.make_beacon(reply, via), "reply")

func _poll_search(now: int) -> void:
	if _query == null:
		return
	if now >= _next_send_ms:
		_next_send_ms = now + query_interval_ms
		_seq += 1
		_query_sent[_seq] = Time.get_ticks_usec()
		_query_sent.erase(_seq - 10)
		for t in targets:
			_send(_query, t.address, discovery_port, Proto.make_query(t.kind, sid, _seq), t.kind)
	while _query.get_available_packet_count() > 0:
		var bytes := _query.get_packet()
		_found(_query.get_packet_ip(), bytes, "")
	if _listen != null:
		while _listen.get_available_packet_count() > 0:
			var bytes := _listen.get_packet()
			_found(_listen.get_packet_ip(), bytes, "beacon")
	var gone := []
	for key in games:
		if now - int(games[key].last_ms) > expire_after_ms:
			gone.append(key)
	for key in gone:
		_log("Nicht mehr gesehen: „%s“ %s:%d" % [games[key].name, games[key].address, games[key].port])
		games.erase(key)
	if gone.size() > 0:
		games_changed.emit()

func _found(ip: String, bytes: PackedByteArray, passive_via: String) -> void:
	var info := Proto.parse_beacon(bytes)
	if info.is_empty() or info.sid == sid or Proto.ipv4_to_int(ip) < 0:
		return
	var via: String = passive_via if passive_via != "" else (info.re if Proto.VIA_TEXT.has(info.re) else "manual")
	_count("recv:" + via)
	# Ein Host = ein Eintrag, auch wenn er über mehrere Adressen antwortet (z. B. LAN und Loopback): Schlüssel ist seine
	# Sitzungskennung; "address" bleibt die zuerst gesehene, "addresses" sammelt alle.
	var key := str(info.sid) if str(info.sid) != "" else "%s:%d" % [ip, info.port]
	var now := Time.get_ticks_msec()
	var known: bool = games.has(key)
	var entry: Dictionary = games[key] if known else {"address": ip, "addresses": [], "via": {}, "first_ms": now - _start_ms}
	if not entry.addresses.has(ip):
		entry.addresses.append(ip)
	for field in ["name", "port", "players", "max", "game", "physics", "proto", "compatible", "note", "sid", "busy"]:
		entry[field] = info[field]
	entry["last_ms"] = now
	if passive_via == "" and _query_sent.has(info.q):
		# Antwortzeit über reines UDP (ohne ENet): Laufzeit des Netzwegs plus Abfrage je Bild auf beiden Seiten.
		entry["reply_ms"] = (Time.get_ticks_usec() - int(_query_sent[info.q])) / 1000.0
	if not entry.via.has(via):
		entry.via[via] = 0
		_log("%s „%s“ %s:%d über %s nach %d ms (Spiel %s, %d/%d Spieler%s%s)" % ["Gefunden:" if not known else "Auch", entry.name, ip, entry.port,
			Proto.VIA_TEXT.get(via, via), now - _start_ms, entry.game, entry.players, entry.max, ", " + entry.note if entry.note != "" else "",
			", Antwort nach %.1f ms" % entry.reply_ms if passive_via == "" and entry.has("reply_ms") else ""])
	entry.via[via] += 1
	games[key] = entry
	if not known:
		game_found.emit(key, entry)
	games_changed.emit()

func _count(key: String) -> void:
	counters[key] = int(counters.get(key, 0)) + 1

func stats_text() -> String:
	var keys := counters.keys()
	keys.sort()
	return ", ".join(keys.map(func(k): return "%s=%d" % [k, counters[k]]))

func _log_stats(force: bool) -> void:
	var text := stats_text()
	if text != "" and (force or text != _last_stats):
		_last_stats = text
		_log("Zähler nach %.0f s: %s" % [elapsed_ms() / 1000.0, text])

func _log(text: String) -> void:
	log_line.emit(text)
