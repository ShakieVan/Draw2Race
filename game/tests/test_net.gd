extends SceneTree

# Netzwerkschicht des lokalen Mehrspielers (scripts/net, docs/MULTIPLAYER_RECHERCHE.md 4 und 7 „M0“): Nachrichtenformat und
# Versionsprüfung, Format der Suche (Ankündigung/Anfrage), Adressrechnung, Befehlszeile des Netztests, eine Loopback-Sitzung
# (Host + Mitspieler im selben Prozess, eigene Testports 24780–24782), Ablehnung bei falscher Version und vollem Spiel, Suche über
# Loopback, und dass die Netzschicht die Simulation nicht berührt. Läuft synchron in _init (Sockets werden von Hand abgefragt).

const Proto := preload("res://scripts/net/net_protocol.gd")
const Session := preload("res://scripts/net/net_session.gd")
const Discovery := preload("res://scripts/net/net_discovery.gd")
const Screen := preload("res://scripts/net/net_test_screen.gd")
const PORT := 24780
const DISCOVERY_PORT := 24781
const BEACON_PORT := 24782
const NET_SCRIPTS := ["res://scripts/net/net_protocol.gd", "res://scripts/net/net_session.gd", "res://scripts/net/net_discovery.gd",
	"res://scripts/net/net_android.gd", "res://scripts/net/net_log.gd", "res://scripts/net/net_test_screen.gd", "res://scripts/net/net_cli.gd"]
const SIM_SCRIPTS := ["res://scripts/track.gd", "res://scripts/vehicle.gd", "res://scripts/race_field.gd", "res://scripts/seesaw.gd"]
var failures := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)
	else:
		print("PASS: ", message)

func _init() -> void:
	test_messages()
	test_hello()
	test_discovery_format()
	test_addresses()
	test_cli()
	test_session()
	test_reject()
	test_full()
	test_leaving_peer()
	test_timeouts()
	test_discovery_loopback()
	test_separation()
	print("RESULT: ", checks - failures, "/", checks, " passed")
	quit(1 if failures else 0)

func pump(nodes: Array, timeout_ms: int, done: Callable) -> bool:
	var end := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < end:
		for n in nodes:
			n.poll()
		if done.call():
			return true
		OS.delay_msec(2)
	return false

func new_session() -> Session:
	var s := Session.new()
	s.auto_poll = false
	s.ping_interval_ms = 40
	return s

func test_messages() -> void:
	var msg := {"t": "line", "points": PackedVector2Array([Vector2(1, 2), Vector2(3.5, -4)]), "times": PackedFloat32Array([0.0, 0.25]), "n": 7}
	var bytes := Proto.encode(msg)
	check(bytes[0] == 0x44 and bytes[1] == 0x32 and bytes[2] == Proto.VERSION, "Nachricht beginnt mit D2 und Protokollversion")
	var back := Proto.decode(bytes)
	check(back.get("t") == "line" and back.get("points") == msg.points and back.get("times") == msg.times and back.get("n") == 7, "Nachricht übersteht Ein- und Auspacken")
	check(Proto.decode(PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8])).is_empty(), "Fremdpaket (falsche Kennung) wird verworfen")
	check(Proto.decode(PackedByteArray([0x44])).is_empty(), "zu kurzes Paket wird verworfen")
	var foreign := PackedByteArray([0x44, 0x32, Proto.VERSION + 1])
	foreign.append_array(var_to_bytes({"t": "hello"}))
	var f := Proto.decode(foreign)
	check(f.get("t") == "_foreign" and f.get("proto") == Proto.VERSION + 1, "andere Protokollversion wird erkannt, ohne den Inhalt zu entpacken")
	var big := PackedByteArray([0x44, 0x32, Proto.VERSION])
	big.resize(Proto.MAX_MESSAGE_BYTES + 10)
	check(Proto.decode(big).is_empty(), "übergroßes Paket wird verworfen")
	var not_dict := PackedByteArray([0x44, 0x32, Proto.VERSION])
	not_dict.append_array(var_to_bytes([1, 2, 3]))
	check(Proto.decode(not_dict).is_empty(), "Nachricht ohne Dictionary/Typ wird verworfen")
	var reject := Proto.decode(Proto.encode_reject("game", "Andere Spielversion: Host 1.0.0, dein Gerät 0.9.0."))
	check(reject.get("t") == "reject" and reject.get("code") == "game" and str(reject.get("reason")).begins_with("Andere Spielversion"), "Ablehnung (versionsunabhängiges Format) lesbar")
	check(Proto.peek_version(Proto.encode_reject("x", "y")) == 0, "Ablehnung trägt Versionsbyte 0")

func test_hello() -> void:
	var local := {"game": Proto.game_version(), "physics": Proto.physics_version(), "track": "abc"}
	var hello := Proto.make_hello("  Anna  ", "abc")
	check(hello.name == "Anna" and hello.proto == Proto.VERSION and hello.game == Proto.game_version() and hello.physics == RaceVehicle.VERSION, "Anmeldung enthält Name, Protokoll-, Spiel- und Physikversion")
	check(Proto.check_hello(hello, local).is_empty(), "passende Anmeldung wird angenommen")
	var wrong := hello.duplicate()
	wrong.game = "0.0.1"
	var r := Proto.check_hello(wrong, local)
	check(r.get("code") == "game" and "0.0.1" in str(r.get("reason")) and Proto.game_version() in str(r.get("reason")), "falsche Spielversion: klarer Grund mit beiden Versionen")
	wrong = hello.duplicate()
	wrong.proto = Proto.VERSION + 5
	check(Proto.check_hello(wrong, local).get("code") == "protocol", "falsche Protokollversion wird abgelehnt")
	check(Proto.check_hello({"t": "_foreign", "proto": 9}, local).get("code") == "protocol" and "9" in str(Proto.check_hello({"t": "_foreign", "proto": 9}, local).reason), "fremdes Protokollbyte wird mit Versionsnummern abgelehnt")
	wrong = hello.duplicate()
	wrong.physics = "bicycle-0"
	check(Proto.check_hello(wrong, local).get("code") == "physics", "andere Fahrphysik wird abgelehnt")
	wrong = hello.duplicate()
	wrong.track = "zzz"
	check(Proto.check_hello(wrong, local).is_empty() and Proto.check_hello(wrong, local, 0, true).get("code") == "track", "Streckenprüfsumme nur geprüft, wenn verlangt (Platzhalter)")
	check(Proto.check_hello(hello, local, Proto.MAX_CLIENTS).get("code") == "full", "volles Spiel wird abgelehnt")
	wrong = hello.duplicate()
	wrong.erase("name")
	check(Proto.check_hello(wrong, local).get("code") == "bad", "unvollständige Anmeldung wird abgelehnt")
	check(Proto.clean_name("  Jürgen der Große  ") == "Jürgen der G" and Proto.clean_name("\t\n") == "Fahrer" and Proto.clean_name("A\u0007B") == "AB", "Namen: höchstens 12 Zeichen, ohne Steuerzeichen, Ersatzname")
	check(Proto.unique_name("Anna", ["Anna"]) == "Anna 2" and Proto.unique_name("Anna", ["Anna", "Anna 2"]) == "Anna 3" and Proto.unique_name("Ben", ["Anna"]) == "Ben", "gleiche Namen bekommen eine Ziffer")

func test_discovery_format() -> void:
	var beacon := Proto.make_beacon({"name": "Host Anna", "port": 24680, "players": 2, "max": 4, "sid": "ab12", "n": 5}, "gateway")
	check(beacon.size() < Proto.MAX_DISCOVERY_BYTES, "Ankündigung ist klein (%d Byte)" % beacon.size())
	var info := Proto.parse_beacon(beacon)
	check(info.get("name") == "Host Anna" and info.get("port") == 24680 and info.get("players") == 2 and info.get("max") == 4 and info.get("sid") == "ab12" and info.get("re") == "gateway" and info.get("n") == 5, "Ankündigung übersteht Ein- und Auspacken")
	check(info.get("compatible") == true and info.get("note") == "", "gleiche Version ist kompatibel")
	var other = JSON.parse_string(beacon.get_string_from_utf8())
	other.game = "0.0.1"
	var info2 := Proto.parse_beacon(JSON.stringify(other).to_utf8_buffer())
	check(info2.get("compatible") == false and "0.0.1" in str(info2.get("note")), "andere Spielversion in der Liste markiert")
	check(Proto.parse_beacon("hallo".to_utf8_buffer()).is_empty(), "Fremdpaket ist keine Ankündigung")
	check(Proto.parse_beacon("{kaputt".to_utf8_buffer()).is_empty(), "kaputtes JSON ist keine Ankündigung")
	check(Proto.parse_beacon(JSON.stringify({"m": "X", "v": 1, "port": 1}).to_utf8_buffer()).is_empty(), "falsche Kennung ist keine Ankündigung")
	check(Proto.parse_beacon(JSON.stringify({"m": Proto.BEACON_MAGIC, "v": 1, "port": 0}).to_utf8_buffer()).is_empty(), "Ankündigung ohne gültigen Port wird verworfen")
	var huge := "{" + "x".repeat(Proto.MAX_DISCOVERY_BYTES) + "}"
	check(Proto.parse_beacon(huge.to_utf8_buffer()).is_empty(), "übergroße Ankündigung wird verworfen")
	check(Proto.parse_query(beacon).is_empty() and Proto.parse_beacon(Proto.make_query("bcast")).is_empty(), "Anfrage und Ankündigung sind nicht verwechselbar")
	var q := Proto.parse_query(Proto.make_query("subnet", "cd34", 3))
	check(q.get("via") == "subnet" and q.get("sid") == "cd34" and q.get("n") == 3 and q.get("proto") == Proto.VERSION, "Suchanfrage übersteht Ein- und Auspacken")

func test_addresses() -> void:
	check(Proto.directed_broadcast("192.168.43.17", 24) == "192.168.43.255", "gerichteter Rundruf /24")
	check(Proto.directed_broadcast("10.1.2.3", 16) == "10.1.255.255", "gerichteter Rundruf /16")
	check(Proto.directed_broadcast("172.20.10.5", 28) == "172.20.10.15", "gerichteter Rundruf /28 (iPhone-Hotspot)")
	check(Proto.directed_broadcast("300.1.1.1") == "" and Proto.directed_broadcast("fe80::1") == "", "ungültige Adresse ergibt keinen Rundruf")
	check(not Proto.usable_ipv4("127.0.0.1") and not Proto.usable_ipv4("169.254.3.4") and not Proto.usable_ipv4("0.0.0.0") and Proto.usable_ipv4("192.168.0.2"), "Loopback und Link-local zählen nicht als eigenes Netz")
	var a := Proto.parse_address(" 192.168.1.5:24690 ")
	check(a.get("address") == "192.168.1.5" and a.get("port") == 24690, "Adresse mit Port")
	check(Proto.parse_address("192,168,1,5").get("address") == "192.168.1.5" and Proto.parse_address("192.168.1.5").get("port") == Proto.GAME_PORT, "Komma statt Punkt (Zahlentastatur) und Standardport")
	check(Proto.parse_address("abc").is_empty() and Proto.parse_address("1.2.3.4:99999").is_empty() and Proto.parse_address("1.2.3").is_empty(), "ungültige Adressen werden abgewiesen")

func test_cli() -> void:
	var o := Screen.cli_options(PackedStringArray(["--nettest=join:192.168.1.5:24690", "--nettest-timeout=12", "--nettest-name=Ben", "--nettest-local"]))
	check(o.get("mode") == "join" and o.get("address") == "192.168.1.5" and o.get("port") == 24690 and o.get("timeout") == 12.0 and o.get("name") == "Ben" and o.get("local") == true, "Befehlszeile: Beitritt mit Adresse und Optionen")
	check(Screen.cli_options(PackedStringArray(["--nettest=host", "--nettest-expect=3"])).get("expect") == 3, "Befehlszeile: Host mit erwarteter Mitspielerzahl")
	check(Screen.cli_options(PackedStringArray([])).is_empty() and Screen.cli_options(PackedStringArray(["--irgendwas"])).is_empty(), "ohne --nettest kein Automatikmodus")
	check(Screen.cli_options(PackedStringArray(["--nettest=fliegen"])).has("error") and Screen.cli_options(PackedStringArray(["--nettest=join:abc"])).has("error"), "unbekannter Modus/ungültige Adresse wird gemeldet")

func test_session() -> void:
	var host := new_session()
	check(host.host("Testhost", PORT) == OK and host.state == "hosting" and host.is_host, "Host startet auf Testport")
	var client := new_session()
	check(client.join("127.0.0.1", PORT, "Anna") == OK and client.state == "connecting", "Mitspieler verbindet über Loopback")
	var host_msgs := []
	var client_msgs := []
	var joined := []
	var left := []
	host.message_received.connect(func(id, m): host_msgs.append([id, m]))
	host.peer_joined.connect(func(id, _info): joined.append(id))
	host.peer_left.connect(func(id, _r): left.append(id))
	client.message_received.connect(func(id, m): client_msgs.append([id, m]))
	var ok := pump([host, client], 3000, func(): return client.state == "connected" and host.accepted_ids().size() == 1 and client.players.size() == 2)
	check(ok, "Anmeldung angenommen, Spielerliste verteilt (Zustand %s: %s)" % [client.state, client.detail])
	if not ok:
		host.free()
		client.free()
		return
	var id: int = host.accepted_ids()[0]
	check(client.my_id == id and id > 1 and host.peers[id].name == "Anna" and joined == [id], "Mitspieler-ID und Name beim Host")
	check(client.players[0].name == "Testhost" and client.players[0].host and client.players[1].name == "Anna", "Spielerliste beim Mitspieler (Host zuerst)")
	pump([host, client], 2000, func(): return int(client.stats(1).received) >= 5 and int(host.stats(id).received) >= 5)
	var cs := client.stats(1)
	var hs := host.stats(id)
	check(int(cs.received) >= 5 and float(cs.rtt_ms) >= 0.0 and float(cs.min_ms) <= float(cs.avg_ms) and float(cs.avg_ms) <= float(cs.max_ms), "Echo-Ping beim Mitspieler: %s" % JSON.stringify(cs))
	check(int(hs.received) >= 5, "Echo-Ping beim Host (%d Antworten)" % int(hs.received))
	check(float(cs.loss_pct) == 0.0 and float(cs.jitter_ms) >= 0.0, "kein Verlust über Loopback")
	check(cs.offset_valid and absf(float(cs.offset_ms)) < 5.0 and client.clock_synced(), "Uhrversatz im selben Prozess ≈ 0 (%.3f ms)" % float(cs.offset_ms))
	check(absi(client.host_time_usec() - Time.get_ticks_usec()) < 5000, "Host-Uhr beim Mitspieler stimmt")
	check(client.send(1, {"t": "lobby", "car": 3}) == OK, "Mitspieler sendet eigene Nachricht")
	host.send(id, {"t": "line", "p": PackedVector2Array([Vector2(1, 1)])})
	host.send(id, {"t": "snap", "b": PackedByteArray([1, 2, 3])}, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED, Proto.CHANNEL_SNAPSHOT)
	client.send(1, {"t": "hello"})
	pump([host, client], 1500, func(): return host_msgs.size() >= 1 and client_msgs.size() >= 2)
	check(host_msgs.size() == 1 and host_msgs[0][0] == id and host_msgs[0][1].get("car") == 3, "Host empfängt nur die eigene Nachricht (reservierte Typen bleiben intern)")
	check(client_msgs.size() == 2 and client_msgs[0][1].get("t") == "line" and client_msgs[1][1].get("b") == PackedByteArray([1, 2, 3]), "Mitspieler empfängt zuverlässige Nachricht und Schnappschuss-Kanal")
	check(host.send(99, {"t": "x"}) == ERR_DOES_NOT_EXIST, "Senden an unbekannte ID wird abgewiesen")
	var second := new_session()
	second.join("127.0.0.1", PORT, "Anna")
	ok = pump([host, client, second], 3000, func(): return second.state == "connected")
	check(ok and second.my_name == "Anna 2" and host.accepted_ids().size() == 2, "zweiter gleicher Name wird zu „Anna 2“")
	client.close("Test")
	ok = pump([host, second], 3000, func(): return left.has(id) and second.players.size() == 2)
	check(ok and host.accepted_ids().size() == 1 and client.state == "closed", "Abmeldung kommt beim Host an, Spielerliste wird aktualisiert")
	host.close("Test")
	ok = pump([second], 4000, func(): return second.state == "closed")
	check(ok and "Host" in second.detail, "Mitspieler merkt, dass der Host weg ist (%s)" % second.detail)
	host.free()
	client.free()
	second.free()

func test_reject() -> void:
	var host := new_session()
	host.host("Testhost", PORT)
	var client := new_session()
	client.hello_override = {"game": "0.0.1"}
	client.join("127.0.0.1", PORT, "Alt")
	var ok := pump([host, client], 3000, func(): return client.state == "rejected")
	check(ok and client.reject_code == "game" and "0.0.1" in client.detail and Proto.game_version() in client.detail, "falsche Spielversion wird mit deutschem Grund abgelehnt: %s" % client.detail)
	check(host.rejected_count == 1 and host.accepted_ids().is_empty(), "abgelehnter Mitspieler zählt nicht als Spieler")
	pump([host, client], 3000, func(): return host.peers.is_empty())
	check(host.peers.is_empty() and client.enet == null, "abgelehnte Verbindung wird getrennt")
	host.free()
	client.free()

func test_full() -> void:
	var host := new_session()
	host.host("Testhost", PORT)
	var clients := []
	for i in range(Proto.MAX_CLIENTS):
		var c := new_session()
		c.join("127.0.0.1", PORT, "P%d" % (i + 1))
		clients.append(c)
	var all := [host] + clients
	var ok := pump(all, 4000, func(): return clients.all(func(c): return c.state == "connected"))
	check(ok and host.accepted_ids().size() == Proto.MAX_CLIENTS and host.players.size() == Proto.MAX_PLAYERS, "Host nimmt %d Mitspieler an" % Proto.MAX_CLIENTS)
	var extra := new_session()
	extra.join("127.0.0.1", PORT, "Zuviel")
	ok = pump(all + [extra], 3000, func(): return extra.state == "rejected")
	check(ok and extra.reject_code == "full" and "voll" in extra.detail, "fünfter Spieler bekommt „Das Spiel ist voll“ (%s)" % extra.detail)
	check(host.accepted_ids().size() == Proto.MAX_CLIENTS, "volle Runde bleibt unverändert")
	for n in all + [extra]:
		n.free()

func joined_pair(ping_ms: int) -> Array:
	# Host + angenommener Mitspieler über Loopback; ping_ms = Abstand der eigenen Pings (1 = bei jeder Abfrage).
	var host := new_session()
	host.ping_interval_ms = ping_ms
	host.host("Testhost", PORT)
	var client := new_session()
	client.ping_interval_ms = ping_ms
	client.join("127.0.0.1", PORT, "Lena")
	pump([host, client], 3000, func(): return client.state == "connected" and host.accepted_ids().size() == 1)
	return [host, client]

func test_leaving_peer() -> void:
	# Fehler aus der Prüfung: Ping/Pong liefen an der Verbindungsprüfung von send() vorbei. Wird ein Partner getrennt, räumt ENet seine
	# Kanäle sofort ab, Godot führt ihn aber bis zum Trennungsereignis weiter – ein Ping dorthin ergab „ERROR: Unable to send packet on
	# channel 1, max channels: 0“ (build.ps1 und net_test.ps1 werten ^ERROR: als Fehlschlag, diese Testreihe fiele also durch).
	var pair := joined_pair(1)
	var host: Session = pair[0]
	var client: Session = pair[1]
	var id: int = host.accepted_ids()[0] if not host.accepted_ids().is_empty() else -1
	check(id > 1 and host.peers.has(id), "Paar für den Abmeldetest verbunden")
	if id < 0:
		host.free()
		client.free()
		return
	# Gezielt: Der Host trennt den Partner (ENet: Kanäle weg, Zustand „trennt“), bevor der Mitspieler antwortet – dann ein fälliger Ping.
	host.enet.get_peer(id).peer_disconnect()
	host._next_ping_ms = 0
	host.poll()
	var bytes := Proto.encode({"t": "ping", "n": 1, "c": 0})
	check(host.peers.has(id) and host._put(id, bytes, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE, Proto.CHANNEL_CONTROL, true) == ERR_UNAVAILABLE and host.skipped_sends >= 2,
		"Partner wird gerade getrennt: Ping (Abfrage und direkt) geht nicht hinaus (%d übersprungen), keine ENet-Fehlermeldung" % host.skipped_sends)
	var before := host.skipped_sends
	var sent := host.send(id, {"t": "x"})
	host.kick(id, "Test")
	check(sent == ERR_UNAVAILABLE and host.skipped_sends == before + 2, "Auch Nachricht und Ablehnung an diesen Partner werden still verworfen")
	pump([host, client], 3000, func(): return host.peers.is_empty() and client.state == "closed")
	check(host.peers.is_empty() and client.state == "closed", "Trennung kommt danach sauber an")
	host.free()
	client.free()
	# Wie im Spiel: Der Mitspieler meldet sich sauber ab („bye“), beide pingen bei jeder Abfrage – der Host trennt, der Mitspieler auch.
	for round_no in range(3):
		pair = joined_pair(1)
		host = pair[0]
		client = pair[1]
		var left := []
		host.peer_left.connect(func(peer_id, reason): left.append(reason))
		pump([host, client], 200, func(): return false)
		client.close_gracefully({"t": "bye"})
		var ok := pump([host, client], 3000, func(): return host.peers.is_empty() and client.enet == null)
		check(ok and left == ["abgemeldet"] and host.state == "hosting", "Saubere Abmeldung %d mit Ping bei jeder Abfrage: beim Host „abgemeldet“, ohne Sendefehler (übersprungen: Host %d, Mitspieler %d)" % [round_no + 1, host.skipped_sends, client.skipped_sends])
		host.free()
		client.free()

func test_timeouts() -> void:
	# ENet-Zeitgrenzen: Vorgabe 8–20 s (ein Hänger von 5,1 s am Steinbruch trennte früher bei 4–10 s), zur Laufzeit für alle Partner
	# änderbar. Der Hänger selbst: Der Mitspieler wird 1,6 s nicht abgefragt (sein Hauptthread steht) – mit kurzen Testgrenzen 0,6–1,5 s
	# fliegt er heraus, nach set_peer_timeout mit 3–5 s nicht. Dazu silent_usec(): wie lange vom Partner nichts kam.
	var fresh := Session.new()
	check(fresh.peer_timeout == [16, 8000, 20000], "Vorgabe der ENet-Zeitgrenze: 8–20 s (Grenzwert 16)")
	fresh.free()
	for long in [false, true]:
		var pair := joined_pair(250)
		var host: Session = pair[0]
		var client: Session = pair[1]
		# Beide Seiten wie NetLobby beim Laden: Auch der Hängende selbst prüft nach dem Hänger zuerst seine Zeitgrenze (vor dem Empfang).
		for s in pair:
			s.set_peer_timeout([32, 3000, 5000] if long else [32, 600, 1500])
		var id: int = host.accepted_ids()[0]
		pump([host, client], 300, func(): return false)
		var quiet_before := host.silent_usec(id)
		var t0 := Time.get_ticks_msec()
		var lost := pump([host], 1600, func(): return host.peers.is_empty())
		var quiet := host.silent_usec(id)
		pump([host, client], 1500, func(): return host.peers.is_empty() or int(client.stats(1).received) > 0 and host.silent_usec(id) < 100_000)
		if long:
			check(not lost and host.accepted_ids() == [id] and client.state == "connected", "Lange Grenze (3–5 s): Hänger von 1,6 s übersteht die Verbindung")
			check(quiet_before >= 0 and quiet_before < 300_000 and quiet > 1_400_000 and host.silent_usec(id) < 300_000,
				"silent_usec: vor dem Hänger %.0f ms, am Ende %.0f ms still, danach wieder %.0f ms" % [quiet_before / 1000.0, quiet / 1000.0, host.silent_usec(id) / 1000.0])
			check(host.silent_usec(999) == -1, "silent_usec für unbekannte Partner: -1")
		else:
			check(lost and Time.get_ticks_msec() - t0 < 1600, "Kurze Grenze (0,6–1,5 s): derselbe Hänger trennt nach %d ms" % (Time.get_ticks_msec() - t0))
		host.free()
		client.free()

func test_discovery_loopback() -> void:
	var host := Discovery.new()
	var search := Discovery.new()
	for d in [host, search]:
		d.auto_poll = false
		d.use_broadcast = false
		d.probe_local = true
		d.discovery_port = DISCOVERY_PORT
		d.beacon_port = BEACON_PORT
		d.announce_interval_ms = 100
		d.query_interval_ms = 100
	check(host.start_host({"name": "Testhost", "port": PORT, "players": 2, "max": 4}) == OK, "Ankündigung startet")
	check(search.start_search() == OK and search.passive_ok, "Suche startet (Ankündigungs-Port gebunden)")
	var key: String = host.sid
	var ok := pump([host, search], 3000, func(): return search.games.has(key) and search.games[key].via.has("local") and search.games[key].via.has("beacon"))
	check(ok, "Host über Loopback gefunden – per Anfrage und per Ankündigung (%s)" % JSON.stringify(search.games))
	if ok:
		var g: Dictionary = search.games[key]
		check(g.name == "Testhost" and g.players == 2 and g.compatible and g.port == PORT and g.address == "127.0.0.1" and g.addresses == ["127.0.0.1"], "Fundeintrag enthält Name, Spielerzahl, Adresse, Port, Version passt")
		check(g.has("reply_ms") and float(g.reply_ms) >= 0.0 and float(g.reply_ms) < 1000.0, "Antwortzeit der Suchanfrage gemessen (%.1f ms)" % float(g.get("reply_ms", -1.0)))
		check(search.sorted_games().size() == 1 and "Lokal" in search.via_text(g), "Liste und Wegtext")
	check(int(host.counters.get("query:local", 0)) > 0 and int(search.counters.get("recv:local", 0)) > 0, "Zähler für Anfragen und Antworten")
	host.stop()
	search.expire_after_ms = 300
	pump([search], 1000, func(): return search.games.is_empty())
	check(search.games.is_empty(), "verschwundener Host fällt aus der Liste")
	search.stop()
	host.free()
	search.free()

func test_separation() -> void:
	# Leitplanke 4: Netz/Anzeige verändern die Simulation nicht – die Netzschicht kennt keine Fahrzeuge, die Simulation kein Netz.
	for path in NET_SCRIPTS:
		var text := FileAccess.get_file_as_string(path)
		check(text != "" and not ("RaceField" in text or "Circuit" in text or ".step(" in text or "weather_grip" in text), "%s rechnet nicht an der Simulation" % path.get_file())
	for path in SIM_SCRIPTS:
		var text := FileAccess.get_file_as_string(path)
		check(text != "" and not ("scripts/net" in text or "NetSession" in text or "ENetMultiplayerPeer" in text), "%s kennt kein Netz" % path.get_file())
