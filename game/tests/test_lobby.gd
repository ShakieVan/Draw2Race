extends SceneTree

# WLAN-Mehrspieler M3 „Lobby und Verbindung“ (scripts/net/net_lobby.gd, scripts/lobby_hud.gd): Regeln der Lobby (Einstellungen,
# eindeutige Autos und Namen, Prüfsumme der Streckendaten), dann ein Host und drei Mitspieler im selben Prozess über 127.0.0.1
# (eigene Testports 24790–24792): Suche, Beitritt, gleicher Zustand bei allen, Einstellungen live, Bereit, Start und gemeinsames
# Laden, Ablehnung (voll, Rennen läuft, Spielversion, Protokoll, Streckendaten, abweichende Strecke beim Laden), Verlassen,
# Verbindungsabbruch eines Mitspielers und des Hosts, Hintergrund. Zum Schluss die echte Oberfläche (main.tscn) als Mitspieler und
# als Gastgeber samt Zurück-Taste; der Spielstand bekommt dabei weder Gold noch Bestzeiten.
const PORT := 24790
const DISCOVERY_PORT := 24791
const BEACON_PORT := 24792
const TEST_OVERRIDES := {"game_port": PORT, "discovery_port": DISCOVERY_PORT, "beacon_port": BEACON_PORT, "probe_local": true,
	"use_broadcast": false, "use_binding": false, "log_path": "", "auto_poll": false, "peer_timeout": [32, 600, 1500], "load_timeout": [32, 600, 1500]}
const TRACKS := ["azure", "city", "forest", "harbor", "serra", "fair", "quarry", "arena", "kids"]
var failures := 0
var checks := 0
var lobbies: Array = []
var events := {}            # Lobby -> Liste [signal, wert]
var ui_app: Node            # Oberflächentest: main.tscn (dessen Lobby wird in frames_until mit abgefragt)

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)
	else:
		print("PASS: ", message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	test_rules()
	await test_sessions()
	test_stall()
	test_binding()
	test_hotspot()
	await test_ui()
	NetLobby.overrides = {}
	print("RESULT: ", checks - failures, "/", checks, " passed")
	quit(1 if failures else 0)

# ---------- Hilfen ----------
func make(player_name: String, car := 0, auto := false, extra := {}) -> NetLobby:
	# Lobby mit Testports; auto = fragt sich selbst je Bild ab (Oberflächentest), sonst pump(); extra = weitere Vorgaben.
	var saved: Dictionary = NetLobby.overrides
	NetLobby.overrides = TEST_OVERRIDES.merged({"auto_poll": auto}, true).merged(extra, true)
	var lb := NetLobby.new()
	NetLobby.overrides = saved
	lb.tracks = TRACKS.duplicate()
	root.add_child(lb)
	events[lb] = []
	for sig in ["joined", "failed", "closed", "notice", "round_started", "round_ready", "round_cancelled"]:
		lb.connect(sig, func(value = null): events[lb].append([sig, value]))
	lb.custom_message.connect(func(from: int, msg: Dictionary): events[lb].append(["custom", [from, msg]]))
	lb.enter(player_name, car)
	lobbies.append(lb)
	return lb

func got(lb: NetLobby, sig: String) -> Array:
	return events[lb].filter(func(e): return e[0] == sig).map(func(e): return e[1])

func pump(list: Array, timeout_ms: int, done: Callable) -> bool:
	var end := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < end:
		for lb in list:
			if is_instance_valid(lb):
				lb.poll()
		if done.call():
			return true
		OS.delay_msec(2)
	return false

func view(lb: NetLobby) -> String:
	# Vergleichbarer Zustand ohne Ping (Ping misst jeder selbst).
	return JSON.stringify({"s": lb.settings, "p": lb.players.map(func(p): return [p.id, p.name, p.car, p.color, p.ready, p.host, p.away]), "ph": lb.phase})

func same_view(host: NetLobby, clients: Array) -> bool:
	var want := view(host)
	return clients.all(func(c): return view(c) == want)

func dispose(lb) -> void:
	if is_instance_valid(lb):
		lb.exit()
		lb.free()

# ---------- Regeln ----------
func test_rules() -> void:
	check(NetProtocol.VERSION >= 3, "Protokollversion %d (ab 3: Lobby, gemeinsames Zeichnen)" % NetProtocol.VERSION)
	var drift := NetLobby.clean_settings({"track": "arena", "stage": 1, "ai": 3, "contacts": true}, 2, TRACKS)
	check(drift.ai == 0 and not drift.contacts and drift.track == "arena", "Drift-Arena: ohne KI und ohne Berührungen %s" % str(drift))
	var full := NetLobby.clean_settings({"track": "city", "stage": 7, "ai": 3, "contacts": false}, 3, TRACKS)
	check(full.ai == 1 and full.stage == 2 and not full.contacts, "KI höchstens 4 − Menschen, Stufe 0–2 %s" % str(full))
	var junk := NetLobby.clean_settings({"track": "../../etc", "stage": "x", "ai": -4}, 1, TRACKS)
	check(junk.track == "azure" and junk.stage == 0 and junk.ai == 0 and junk.contacts, "Unbekannte Strecke und falsche Typen → gültige Vorgaben %s" % str(junk))
	check(PlayerColors.free_color(2, [2, 3]) == 4 and PlayerColors.free_color(5, [5, 0]) == 1 and PlayerColors.free_color(1, [0]) == 1,
		"Belegte Farbe → nächste freie in Palettenfolge")
	# Palette: deutlich verschieden, auch bei Rot-Grün-Schwäche; die vier Vorgaben je Platz am weitesten auseinander.
	var closest := INF
	for a in range(PlayerColors.count()):
		for b in range(a + 1, PlayerColors.count()):
			closest = minf(closest, PlayerColors.distance(PlayerColors.color(a), PlayerColors.color(b)))
	var closest_default := INF
	for a in range(4):
		for b in range(a + 1, 4):
			closest_default = minf(closest_default, PlayerColors.distance(PlayerColors.color(PlayerColors.default_for(a)), PlayerColors.color(PlayerColors.default_for(b))))
	check(closest >= 0.14 and closest_default >= 0.24, "Spielerfarben deutlich verschieden (auch Protanopie/Deuteranopie): Palette ≥ %.3f, Vorgaben ≥ %.3f" % [closest, closest_default])
	check(PlayerColors.distance(Color("e53935"), Color("d35400")) < PlayerColors.CLASH and PlayerColors.distance(Color("ff0000"), Color("ff0000")) == 0.0,
		"Abstandsmaß erkennt ähnliche Farben (Rot neben Drift-King-Orange)")
	# KI-Autos neben jeder Paarung aus zwei bzw. drei Spielerfarben: genug Autofarben, die sich deutlich abheben.
	var all_cars: Array = range(RaceVehicle.CARS.size())
	var rivals_ok := true
	for a in range(PlayerColors.count()):
		for b in range(a + 1, PlayerColors.count()):
			for c in range(b, PlayerColors.count()):
				var paints: Array = [PlayerColors.color(a), PlayerColors.color(b)] + ([PlayerColors.color(c)] if c != b else [])
				var order := PlayerColors.rival_order(all_cars, [], paints)
				for k in range(4 - paints.size()):
					for p in paints:
						rivals_ok = rivals_ok and PlayerColors.distance(Color(RaceVehicle.CARS[int(order[k])].color), p) >= PlayerColors.CLASH
	check(rivals_ok, "Für alle Farbpaarungen finden sich KI-Autos, die sich von den Spielerfarben abheben")
	var h := NetLobby.tracks_hash(TRACKS)
	check(h.length() == 32 and h == NetLobby.tracks_hash(TRACKS) and h != NetLobby.tracks_hash(TRACKS.slice(0, 8)), "Prüfsumme der Streckendaten stabil, anderer Streckensatz → andere")
	check(NetLobby.track_file_hash("city") == Circuit.load_track("city").file_hash, "Prüfsumme je Strecke wie track.file_hash")
	var players := NetLobby.clean_players([{"id": 1, "name": "A<script>", "car": 99, "color": 42, "ready": "ja"}, "x", {"id": 0}, {"id": 2}, {"id": 3}, {"id": 4}, {"id": 5}])
	check(players.size() == 4 and players[0].name == "Ascript" and players[0].car == RaceVehicle.CARS.size() - 1 and players[0].color == PlayerColors.count() - 1
		and players[1].color == 0 and not players[0].ready and players[1].name == "?",
		"Spielerliste aus dem Netz: höchstens 4, Typen und Namen bereinigt")
	var beacon := NetProtocol.parse_beacon(NetProtocol.make_beacon({"name": "Anna", "busy": true}))
	check(beacon.busy and not NetProtocol.parse_beacon(NetProtocol.make_beacon({"name": "Anna"})).busy, "Ankündigung meldet „Rennen läuft“")
	var raw := {"android": true, "networks": [{"transport": "wifi", "addresses": ["192.168.1.20/24"]}, {"transport": "mobile", "addresses": ["10.1.2.3/30"]}],
		"interfaces": [{"name": "wlan0", "address": "192.168.1.20"}, {"name": "rmnet_data0", "address": "10.1.2.3"}, {"name": "swlan0", "address": "172.17.251.1"},
		{"name": "v4-rmnet_data1", "address": "192.0.0.4"}]}
	check(NetAndroid.wifi_connected(raw) and NetAndroid.hotspot_addresses(raw) == ["172.17.251.1"], "Android: WLAN erkannt, Hotspot-Adresse ohne Mobil-/CLAT-Schnittstellen")
	raw.networks = [raw.networks[1]]
	check(not NetAndroid.wifi_connected(raw) and not NetAndroid.wifi_connected({"android": false, "interfaces": []}), "Ohne WLAN: kein WLAN gemeldet (Hinweis erscheint)")

# ---------- Sitzungen im selben Prozess ----------
func test_sessions() -> void:
	var host := make("Anna", 0)
	check(host.host("azure", 1) == OK and host.is_host() and host.players.size() == 1 and host.settings.ai == 2, "Spiel eröffnet (Stufe 2 → 2 KI vorgeschlagen)")
	var a := make("Ben", 0)
	a.search()
	var found := pump([host, a], 4000, func(): return a.games().size() == 1 and a.games()[0].compatible)
	check(found and a.games()[0].name == "Anna" and int(a.games()[0].players) == 1, "Suche findet das Spiel (Ankündigung/Anfrage über 127.0.0.1)")
	a.join("127.0.0.1", PORT)
	var b := make("Anna", 0)          # gleicher Name wie der Gastgeber
	b.join("127.0.0.1", PORT)
	var c := make("Cem", 3)
	c.join("127.0.0.1", PORT)
	var clients := [a, b, c]
	var all := [host, a, b, c]
	# Bis alle Wünsche beim Gastgeber angekommen sind (ack): erst dann gilt Cems Wunschauto.
	var acked := func(): return host.players.all(func(p): return p.host or int(p.get("ack", 0)) >= 1)
	var ok := pump(all, 5000, func(): return clients.all(func(x): return x.is_joined and x.players.size() == 4) and host.players.size() == 4 and same_view(host, clients) and acked.call())
	check(ok, "Drei Mitspieler in der Lobby, alle sehen denselben Zustand")
	var names: Array = host.players.map(func(p): return p.name)
	check(names == ["Anna", "Ben", "Anna 2", "Cem"], "Namen eindeutig (gleicher Name bekommt eine Ziffer) %s" % str(names))
	var cars: Array = host.players.map(func(p): return p.car)
	var colours: Array = host.players.map(func(p): return p.color)
	check(cars == [0, 0, 0, 3] and colours == [0, 1, 2, 3], "Autos wie gewünscht (auch dreimal dasselbe), Farben nach Platz %s %s" % [str(cars), str(colours)])
	check(got(host, "notice").size() == 3 and str(got(host, "notice")[0]).contains("beigetreten"), "Gastgeber erfährt jeden Beitritt")
	check(a.ping_of(a.me()) >= 0 or pump(all, 2500, func(): return a.ping_of(a.me()) >= 0 and host.ping_of(host.player(a.my_id())) >= 0), "Ping wird gemessen und angezeigt")
	# Voll: fünfter Spieler
	var d := make("Dora", 0)
	d.join("127.0.0.1", PORT)
	pump(all + [d], 3000, func(): return not got(d, "failed").is_empty())
	check(not got(d, "failed").is_empty() and str(got(d, "failed")[0]).contains("voll") and host.players.size() == 4, "Fünfter Spieler: „Das Spiel ist voll“")
	# Einstellungen live
	host.set_track("city")
	host.set_stage(2)
	host.set_ai(3)
	host.set_contacts(false)
	ok = pump(all, 2000, func(): return same_view(host, clients))
	check(ok and a.settings == {"track": "city", "stage": 2, "ai": 0, "contacts": false}, "Einstellungen kommen bei allen an (KI auf 0 begrenzt: 4 Menschen) %s" % str(a.settings))
	# Bereit, Start erst wenn alle bereit
	a.set_ready(true)
	b.set_ready(true)
	pump(all, 2000, func(): return host.player(a.my_id()).ready and host.player(b.my_id()).ready)
	check(host.start_problem().contains("Cem") and not host.start_round(), "Start gesperrt, solange nicht alle bereit sind: %s" % host.start_problem())
	host.set_stage(1)
	ok = pump(all, 2000, func(): return same_view(host, clients))
	check(ok and not a.me().ready and not b.me().ready, "Geänderte Einstellung setzt „Bereit“ zurück")
	# Autowahl (Nutzerentscheidung 03.10.2026): dasselbe Auto mehrfach, Farben eindeutig
	a.set_car(5)
	b.set_car(5)
	c.set_car(5)
	host.set_car(5)
	ok = pump(all, 2000, func(): return same_view(host, clients) and host.players.all(func(p): return p.car == 5))
	check(ok and not a.me().ready, "Alle vier im selben Auto (Col Racer); eine neue Wahl setzt „Bereit“ zurück")
	a.set_color(4)
	b.set_color(4)
	ok = pump(all, 2000, func(): return same_view(host, clients) and host.player(a.my_id()).color != 1 and host.player(b.my_id()).color != 2)
	var got_colours := [int(host.player(a.my_id()).color), int(host.player(b.my_id()).color)]
	got_colours.sort()
	var unique := {}
	for p in host.players:
		unique[p.color] = true
	check(ok and unique.size() == 4 and got_colours == [4, 5], "Zwei wollen gleichzeitig dieselbe Farbe: der Zweite bekommt die nächste freie %s" % str(got_colours))
	c.set_color(0)
	ok = pump(all, 2000, func(): return same_view(host, clients) and host.player(c.my_id()).color != 3)
	check(ok and c.me().color == 1, "Farbe des Gastgebers gewünscht → nächste freie (Himmelblau) bei allen")
	a.set_player_name("Cem")
	ok = pump(all, 2000, func(): return same_view(host, clients) and host.player(a.my_id()).name != "Ben")
	check(ok and a.me().name == "Cem 2", "Umbenennen auf vergebenen Namen → „Cem 2“")
	# Hintergrund
	b.set_ready(true)
	pump(all, 1500, func(): return host.player(b.my_id()).ready)
	b.set_away(true)
	ok = pump(all, 2000, func(): return host.player(b.my_id()).away and same_view(host, clients))
	check(ok and not host.player(b.my_id()).ready and host.start_problem().contains("Anna 2"), "App im Hintergrund: alle sehen es, „Bereit“ fällt weg")
	b.set_away(false)
	# Alle bereit → Start → gemeinsames Laden
	for x in clients:
		x.set_ready(true)
	ok = pump(all, 2000, func(): return host.start_problem() == "" and same_view(host, clients))
	check(ok, "Alle bereit → Start möglich")
	check(host.start_round(), "Start")
	ok = pump(all, 2000, func(): return clients.all(func(x): return got(x, "round_started").size() == 1))
	var r0: Dictionary = got(host, "round_started")[0]
	check(ok and clients.all(func(x): return JSON.stringify(got(x, "round_started")[0].settings) == JSON.stringify(r0.settings) and got(x, "round_started")[0].hash == r0.hash),
		"Alle bekommen dieselbe Runde (Strecke, Stufe, KI, Berührungen, Prüfsumme)")
	var e := make("Emil", 0)
	e.join("127.0.0.1", PORT)
	pump(all + [e], 3000, func(): return not got(e, "failed").is_empty())
	check(not got(e, "failed").is_empty() and str(got(e, "failed")[0]).contains("begonnen"), "Beitritt während der Runde: abgelehnt mit Grund")
	for x in all:
		x.report_loaded(NetLobby.track_file_hash("city"))
	ok = pump(all, 2000, func(): return all.all(func(x): return got(x, "round_ready").size() == 1))
	check(ok and all.all(func(x): return x.phase == "ready"), "Alle haben geladen → gemeinsamer Einstieg (M4)")
	host.session.send_all({"t": "m4_probe", "n": 7})
	a.session.send(1, {"t": "m4_probe", "n": 8})
	ok = pump(all, 2000, func(): return clients.all(func(x): return got(x, "custom").size() == 1) and got(host, "custom").size() == 1)
	check(ok and got(b, "custom")[0][1].n == 7 and got(host, "custom")[0][0] == a.my_id() and got(host, "custom")[0][1].n == 8,
		"Eigene Nachrichtentypen (M4/M5) kommen als custom_message an, mit Absender")
	var party := c.round_party()
	check(party.count() == 4 and party.track_id == "city" and party.stage == 1 and party.names() == ["Anna", "Cem 2", "Anna 2", "Cem"] and c.round_ids() == host.round_ids(),
		"Runde als PassParty für M4: %s" % str(party.names()))
	host.back_to_lobby()
	ok = pump(all, 2000, func(): return clients.all(func(x): return x.phase == "lobby" and got(x, "round_cancelled").size() == 1) and same_view(host, clients))
	check(ok and not a.me().ready and host.session.join_block == "", "Zurück in die Lobby: Bereit zurückgesetzt, Beitritt wieder offen")
	# Abweichende Strecke beim Laden: wird getrennt, die anderen fahren weiter
	for x in clients:
		x.set_ready(true)
	pump(all, 2000, func(): return host.start_problem() == "")
	host.start_round()
	pump(all, 2000, func(): return clients.all(func(x): return got(x, "round_started").size() == 2))
	host.report_loaded(NetLobby.track_file_hash("city"))
	a.report_loaded(NetLobby.track_file_hash("city"))
	c.report_loaded(NetLobby.track_file_hash("city"))
	b.report_loaded("falsch")
	ok = pump(all, 3000, func(): return not got(b, "closed").is_empty() and got(host, "round_ready").size() == 2)
	check(ok and str(got(b, "closed")[0]).contains("Streckendaten") and host.players.size() == 3, "Andere Strecke geladen: dieser Mitspieler wird mit Grund getrennt, die Runde geht weiter")
	host.back_to_lobby()
	# Verlassen und Abbruch
	a.leave()
	ok = pump(all, 3000, func(): return host.players.size() == 2 and c.players.size() == 2)
	check(ok and str(got(host, "notice")[-1]).contains("verlassen") and got(a, "closed").is_empty(), "Mitspieler verlässt die Lobby: Liste bei allen aktualisiert")
	var t0 := Time.get_ticks_msec()
	ok = pump([host], 5000, func(): return host.players.size() == 1)     # c wird nicht mehr abgefragt: stumm
	check(ok and str(got(host, "notice")[-1]).contains("verloren"), "Stummer Mitspieler fällt nach %d ms aus der Liste" % (Time.get_ticks_msec() - t0))
	ok = pump([c], 5000, func(): return not got(c, "closed").is_empty())
	check(ok and str(got(c, "closed")[0]).contains("abgebrochen"), "Der Stumme merkt es selbst: „Verbindung abgebrochen“")
	var f := make("Fritz", 0)
	f.join("127.0.0.1", PORT)
	pump([host, f], 3000, func(): return f.is_joined)
	host.leave()
	ok = pump([host, f], 3000, func(): return not got(f, "closed").is_empty() and host.session.enet == null)
	check(ok and str(got(f, "closed")[0]) == "Der Gastgeber „Anna“ hat das Spiel beendet.", "Gastgeber beendet: Mitspieler bekommt die Nachricht, Host trennt sauber")
	# Gastgeber stürzt ab (wird nicht mehr abgefragt)
	var host2 := make("Hans", 0)
	host2.host("azure", 0)
	var g := make("Gina", 0)
	g.join("127.0.0.1", PORT)
	pump([host2, g], 3000, func(): return g.is_joined)
	ok = pump([g], 5000, func(): return not got(g, "closed").is_empty())
	check(ok and str(got(g, "closed")[0]).contains("abgebrochen"), "Gastgeber stumm: Mitspieler bekommt „Verbindung abgebrochen“")
	dispose(host2)
	# Gastgeber beendet und hängt gleich danach (Gerätetest 04.10.2026: früher Strecke laden am Stück): Die Nachricht „close“ genügt, der
	# Mitspieler wartet nicht auf die ENet-Trennung (bis zur Zeitgrenze, beim Laden bis 45 s).
	var host4 := make("Hanna", 0)
	host4.host("azure", 0)
	var h := make("Holger", 0)
	h.join("127.0.0.1", PORT)
	pump([host4, h], 3000, func(): return h.is_joined)
	host4.session.send_all({"t": "close", "reason": "Die Gastgeberin „Hanna“ hat das Spiel beendet."})
	host4.session.flush()
	var t_close := Time.get_ticks_msec()
	ok = pump([h], 3000, func(): return not got(h, "closed").is_empty())
	check(ok and str(got(h, "closed")[0]).contains("beendet") and Time.get_ticks_msec() - t_close < 1000 and h.session.enet == null,
		"Gastgeber beendet und hängt: Mitspieler ist nach %d ms raus (ohne auf die Trennung zu warten)" % (Time.get_ticks_msec() - t_close))
	dispose(h)
	dispose(host4)
	# Ablehnungen bei der Anmeldung
	var host3 := make("Ida", 0)
	host3.host("azure", 0)
	for wrong in [[{"game": "0.0.1"}, "Andere Spielversion"], [{"proto": 1}, "Netzprotokoll"], [{"track": "abc"}, "Streckendaten"], [{"physics": "bicycle-0"}, "Fahrphysik"]]:
		var x := make("Jo", 0)
		x.hello_override = wrong[0]
		x.join("127.0.0.1", PORT)
		pump([host3, x], 3000, func(): return not got(x, "failed").is_empty())
		check(not got(x, "failed").is_empty() and str(got(x, "failed")[0]).contains(wrong[1]) and host3.players.size() == 1, "Abgelehnt mit klarem Grund: %s" % (str(got(x, "failed")[0]) if not got(x, "failed").is_empty() else "–"))
		dispose(x)
	var nobody := make("Kai", 0)
	nobody.session.connect_timeout_ms = 800
	nobody.join("127.0.0.1", PORT + 7)
	pump([nobody], 4000, func(): return not got(nobody, "failed").is_empty())
	check(not got(nobody, "failed").is_empty() and str(got(nobody, "failed")[0]).contains("selben WLAN"), "Niemand unter der Adresse: Hinweis aufs gemeinsame WLAN")
	for lb in lobbies:
		dispose(lb)
	lobbies.clear()
	# Getrennt von der Simulation und vom Spielstand
	var source := FileAccess.get_file_as_string("res://scripts/net/net_lobby.gd") + FileAccess.get_file_as_string("res://scripts/lobby_hud.gd")
	check(not source.contains("RaceField") and not source.contains(".save(") and not source.contains("store.data") and not source.contains("store.set"),
		"Lobby und Lobby-Bildschirme rechnen nichts und schreiben keinen Spielstand")

# ---------- Hänger beim Laden (ENet-Zeitgrenzen) ----------
func test_stall() -> void:
	# Fehler aus der Prüfung: Steht der Hauptthread eines Geräts ≥ 4 s (gemessen 5,1 s beim Laden des Steinbruchs; das S10 baut die
	# Welt ähnlich lange), trennte ENet mit 4–10 s. Jetzt: Vom Start der Runde bis kurz nach dem Zeichenstart gelten auf allen Geräten
	# lange Grenzen, sonst normale. Maßstab hier: normal 0,6–1,5 s (Testvorgabe; ENet trennt damit nach 0,6–2,5 s), beim Laden
	# 5–8 s, Hänger 3 s.
	var extra := {"load_timeout": [32, 5000, 8000], "load_grace_ms": 400, "draw_lead_ms": 300}
	var host := make("Olga", 0, false, extra)
	host.host("azure", 0)
	var a := make("Paul", 1, false, extra)
	var b := make("Rosa", 2, false, extra)
	a.join("127.0.0.1", PORT)
	b.join("127.0.0.1", PORT)
	var all := [host, a, b]
	var ok := pump(all, 4000, func(): return a.is_joined and b.is_joined and host.players.size() == 3)
	check(ok and all.all(func(x): return x.session.peer_timeout == [32, 600, 1500]), "Lobby: normale Zeitgrenze auf allen Geräten")
	for x in [a, b]:
		x.set_ready(true)
	pump(all, 2000, func(): return host.start_problem() == "")
	check(host.start_round() and host.session.peer_timeout == [32, 5000, 8000], "Start: Gastgeber schaltet vor „start“ auf die lange Zeitgrenze")
	# Gastgeber lädt und hängt 3 s (wird nicht abgefragt): „start“ ist schon draußen, die Mitspieler schalten ebenfalls um.
	pump([a, b], 3000, func(): return false)
	check([a, b].all(func(x): return got(x, "round_started").size() == 1 and x.session.peer_timeout == [32, 5000, 8000]),
		"„start“ kommt während des Hängers des Gastgebers an, die Mitspieler schalten beim Empfang um")
	pump(all, 400, func(): return false)
	ok = host.client_count() == 2 and [a, b].all(func(x): return x.session.state == "connected")
	check(ok and got(a, "closed").is_empty() and got(b, "closed").is_empty() and host.players.size() == 3, "Hänger des Gastgebers (3 s) beim Laden: niemand fliegt heraus")
	# Mitspieler Paul hängt 3 s beim Laden
	host.report_loaded(NetLobby.track_file_hash("azure"))
	b.report_loaded(NetLobby.track_file_hash("azure"))
	pump([host, b], 3000, func(): return false)
	a.report_loaded(NetLobby.track_file_hash("azure"))
	ok = pump(all, 2000, func(): return all.all(func(x): return x.phase == "ready"))
	check(ok and host.players.size() == 3 and got(a, "closed").is_empty(), "Hänger eines Mitspielers (3 s) beim Laden: er bleibt, danach beginnt die Runde")
	check(all.all(func(x): return x.session.peer_timeout == [32, 5000, 8000] and x.loading_window()), "Bis kurz nach dem Zeichenstart bleibt die lange Grenze (erstes Bild der Welt)")
	ok = pump(all, 3000, func(): return all.all(func(x): return x.session.peer_timeout == [32, 600, 1500]))
	check(ok and all.all(func(x): return not x.loading_window()), "%d ms nach dem Zeichenstart: wieder normale Grenze" % extra.load_grace_ms)
	host.back_to_lobby()
	pump(all, 1500, func(): return [a, b].all(func(x): return x.phase == "lobby"))
	var t0 := Time.get_ticks_msec()
	ok = pump([host, a], 3000, func(): return host.players.size() == 2)
	check(ok and Time.get_ticks_msec() - t0 < 3000, "Derselbe Hänger (3 s) in der Lobby trennt nach %d ms – echte Ausfälle bleiben schnell erkannt" % (Time.get_ticks_msec() - t0))
	for x in all:
		dispose(x)
	lobbies.clear()

# ---------- WLAN-Bindung nach einem WLAN-Wechsel ----------
class FakeAndroid extends RefCounted:
	# Ersatz für NetAndroid wie NetHelper.java: Netze mit Handle. Nach einem WLAN-Wechsel meldet Android das verlorene Netz weiter als
	# gebunden – ohne Fähigkeiten (Transport „?“) und nicht mehr in der Netzliste. Netze tragen wie in state() iface, gateway, default,
	# internet und local (Android 16: eigener Hotspot als lokales Netz); hotspot = Hotspot nur als Schnittstelle (bis Android 15),
	# extra = weitere Schnittstellen (z. B. rmnet_data0 192.0.0.2/27 des S24).
	var nets: Array = []
	var hotspot: Array = []             # eigene Hotspot-Schnittstellen [{name, address, prefix}]
	var extra: Array = []
	var bound_net := {}
	var binds := 0
	var unbinds := 0
	var refuse := false
	func available() -> bool:
		return true
	func multicast(_on: bool) -> bool:
		return true
	func is_bound() -> bool:
		return not bound_net.is_empty()
	func state() -> Dictionary:
		var list: Array = []
		var ifaces: Array = hotspot.duplicate() + extra.duplicate()
		for n in nets:
			list.append((n as Dictionary).merged({"bound": str(n.handle) == str(bound_net.get("handle", ""))}, true))
			for addr in n.addresses:
				ifaces.append({"name": str(n.get("iface", "wlan0")), "address": str(addr).get_slice("/", 0), "prefix": int(str(addr).get_slice("/", 1))})
		var b = null
		if not bound_net.is_empty():
			b = {"handle": bound_net.handle, "transport": "?", "addresses": [], "gateway": ""}
			for n in nets:
				if str(n.handle) == str(bound_net.handle):
					b = (n as Dictionary).duplicate()
		return {"android": true, "networks": list, "bound": b, "interfaces": ifaces, "dhcp_gateway": "",
			"wifi_gateway": str(nets[0].get("gateway", "")) if not nets.is_empty() else ""}
	func bind_wifi() -> String:
		# wie NetAndroid.bind_wifi: das WLAN nach wifi_handle (nie der eigene Hotspot), Java bindet genau dieses Handle
		binds += 1
		if refuse:
			return "Android hat die Bindung abgelehnt."
		var handle := NetAndroid.wifi_handle(state())
		for n in nets:
			if str(n.handle) == handle:
				bound_net = (n as Dictionary).duplicate()
				return ""
		return "Kein WLAN verbunden."
	func bind_network(handle: String) -> String:
		binds += 1
		for n in nets:
			if str(n.handle) == handle:
				bound_net = (n as Dictionary).duplicate()
				return ""
		return "Das WLAN ist nicht mehr verbunden."
	func unbind() -> bool:
		unbinds += 1
		bound_net = {}
		return true

func test_binding() -> void:
	# Fehler aus der Prüfung: _bind() hielt jede Bindung für gültig. Wechselte jemand bei offenem WLAN-Bildschirm das WLAN (Heim-WLAN →
	# Hotspot des Gastgebers), blieb das Spiel an das verlorene Netz gebunden und fand nichts. Adressen aus den Dokumentationsnetzen.
	var home := {"handle": "100", "transport": "wifi", "addresses": ["192.0.2.20/24"], "gateway": "192.0.2.1"}
	var spot := {"handle": "200", "transport": "wifi", "addresses": ["198.51.100.20/24"], "gateway": "198.51.100.1"}
	var lost := {"android": true, "networks": [spot], "bound": {"handle": "100", "transport": "?", "addresses": []}}
	check(NetAndroid.bound_to_wifi({"android": true, "networks": [home], "bound": home}) and not NetAndroid.bound_to_wifi(lost)
		and not NetAndroid.bound_to_wifi({"android": true, "networks": [home], "bound": null})
		and not NetAndroid.bound_to_wifi({"android": true, "networks": [home, {"handle": "7", "transport": "mobile", "addresses": ["10.0.0.2/30"]}], "bound": {"handle": "7", "transport": "mobile"}}),
		"bound_to_wifi: nur eine Bindung an ein verbundenes WLAN zählt (nicht an ein verlorenes Netz, nicht ans Mobilnetz)")
	check(NetAndroid.wifi_handle(lost) == "200" and NetAndroid.wifi_handle({"android": true, "networks": []}) == "" and NetAndroid.wifi_handle({"android": false}) == "",
		"wifi_handle: Handle des verbundenen WLANs, sonst leer (auch am PC)")
	var fake := FakeAndroid.new()
	fake.nets = [home]
	var lb := make("Bea", 0, false, {"use_binding": true, "android_api": fake})
	lb.search()
	check(lb.bound and fake.binds == 1 and str(fake.bound_net.handle) == "100" and lb.status.bound and lb.mode == "search", "Betreten: ans Heim-WLAN gebunden, Suche läuft")
	lb.refresh_status()
	check(fake.binds == 1, "Unverändertes WLAN: keine neue Bindung")
	# Wechsel ins Hotspot-WLAN des Gastgebers, der WLAN-Bildschirm bleibt offen
	fake.nets = [spot]
	var changed := [0]
	lb.status_changed.connect(func(): changed[0] += 1)
	lb.refresh_status()
	check(fake.binds == 2 and str(fake.bound_net.handle) == "200" and lb.bound and lb.status.bound and lb.mode == "search" and lb.discovery.mode == "search"
		and lb.discovery.gateway == "198.51.100.1" and changed[0] > 0, "WLAN gewechselt: neu gebunden (Hotspot), Suche neu gestartet, Gateway-Probe zum Gastgeber")
	lb.refresh_status()
	check(fake.binds == 2, "Danach keine weitere Bindung")
	# Bindung scheitert im nächsten WLAN: Hinweis statt Suche im Zwei-Sekunden-Takt
	fake.refuse = true
	fake.nets = [{"handle": "300", "transport": "wifi", "addresses": ["203.0.113.20/24"], "gateway": "203.0.113.1"}]
	lb.refresh_status()
	lb.refresh_status()
	lb.refresh_status()
	check(fake.binds == 3 and not lb.bound and not lb.status.bound and str(lb.status.problem).contains("abgelehnt"), "Bindung abgelehnt: einmal versucht, Hinweis „%s“" % str(lb.status.problem))
	fake.refuse = false
	fake.nets = []
	lb.refresh_status()
	check(not lb.status.wifi and fake.binds == 3 and fake.unbinds == 1 and fake.bound_net.is_empty() and lb.mode == "search",
		"WLAN weg: Hinweis, kein Bindeversuch, die Bindung ans verlorene Netz ist gelöst (neue Sockets gingen sonst ins Leere)")
	fake.nets = [home.merged({"handle": "400"}, true)]
	lb.refresh_status()
	check(fake.binds == 4 and str(fake.bound_net.handle) == "400" and lb.status.bound and lb.status.wifi, "WLAN wieder da (neues Handle): gebunden, Suche läuft")
	# Gastgeber mit eigenem Hotspot bleibt ungebunden; Verlassen löst die Bindung
	fake.hotspot = [{"name": "swlan0", "address": "172.17.251.1"}]
	check(lb.host("azure", 0) == OK and not lb.bound and fake.bound_net.is_empty() and fake.unbinds == 2, "Gastgeber mit eigenem Hotspot: Bindung gelöst")
	fake.hotspot = []
	lb.search()
	check(lb.bound and fake.binds == 5, "Zurück zur Suche: wieder gebunden")
	lb.exit()
	check(fake.bound_net.is_empty() and not lb.bound and fake.unbinds == 3, "Verlassen löst die Bindung")
	dispose(lb)
	lobbies.clear()

# ---------- Eigener Hotspot (Gerätetest S24 Ultra, 04.10.2026) ----------
# Werte aus dem Geräteprotokoll des S24 (Android 16, Gastgeber mit eigenem Hotspot und zugleich im Heim-WLAN): wlan0 192.168.178.4/16
# (Gateway 192.168.178.1), Hotspot swlan0 10.110.43.61/24, Mitspieler 10.110.43.150 und 10.110.43.201, nach „WLAN aus“ zusätzlich
# rmnet_data0 192.0.0.2/27; das verlorene Heim-WLAN hatte das Handle 3233221103629. Android 16 meldet den Hotspot als lokales Netz
# (Transport WLAN, ohne Gateway); das Handle dieses Netzes stand nicht im Protokoll und ist hier frei gewählt.
const S24_WLAN := {"handle": "3233221103629", "transport": "wifi", "iface": "wlan0", "addresses": ["192.168.178.4/16"], "gateway": "192.168.178.1",
	"internet": true, "validated": true, "default": true}
const S24_SPOT := {"handle": "3237516070925", "transport": "wifi", "iface": "swlan0", "addresses": ["10.110.43.61/24"], "gateway": "",
	"internet": false, "validated": false, "default": false, "local": true}
const S24_MOBILE := {"handle": "432902426637", "transport": "mobile", "iface": "rmnet_data0", "addresses": ["192.0.0.2/27"], "gateway": "",
	"internet": true, "validated": true, "default": true}
const S24_IFACES := [{"name": "wlan0", "address": "192.168.178.4", "prefix": 16, "broadcast": "192.168.255.255"},
	{"name": "swlan0", "address": "10.110.43.61", "prefix": 24, "broadcast": "10.110.43.255"}]
const S24_RMNET := {"name": "rmnet_data0", "address": "192.0.0.2", "prefix": 27, "broadcast": "192.0.0.31"}

func s24(nets: Array, ifaces: Array, bound = null) -> Dictionary:
	return {"android": true, "networks": nets, "interfaces": ifaces, "bound": bound, "wifi_gateway": "", "dhcp_gateway": ""}

func test_hotspot() -> void:
	# 1. WLAN und Hotspot zugleich, wie Android 16 es meldet (Hotspot als lokales Netz mit Transport WLAN).
	var both := s24([S24_WLAN, S24_SPOT], S24_IFACES)
	var plan := NetAndroid.host_plan(both)
	check(NetAndroid.hotspot_network(S24_SPOT) and not NetAndroid.hotspot_network(S24_WLAN) and not NetAndroid.hotspot_network(S24_MOBILE),
		"S24: swlan0 (lokales Netz, ohne Gateway) ist der eigene Hotspot, wlan0 und das Mobilnetz nicht")
	check(NetAndroid.wifi_networks(both).size() == 1 and NetAndroid.wifi_handle(both) == "3233221103629" and NetAndroid.wifi_addresses(both) == ["192.168.178.4"]
		and NetAndroid.hotspot_addresses(both) == ["10.110.43.61"], "S24: WLAN = wlan0 (Bindung dorthin), Hotspot = 10.110.43.61 – früher galt der Hotspot als WLAN")
	check(plan.bind == "" and plan.reach == ["wlan", "hotspot"] and plan.wlan == ["192.168.178.4"] and plan.hotspot == ["10.110.43.61"] and plan.hint != "" and not plan.warn,
		"S24 als Gastgeber mit WLAN und Hotspot: ungebunden, erreichbar in beiden Netzen („zweigleisig“), Hinweis ohne Warnung")
	check(NetAndroid.in_hotspot(both, "10.110.43.150") and NetAndroid.in_hotspot(both, "10.110.43.201") and not NetAndroid.in_hotspot(both, "192.168.178.20")
		and not NetAndroid.in_hotspot(both, "10.110.44.1"), "S24: Mitspieler 10.110.43.150/.201 liegen im eigenen Hotspot, 192.168.178.20 nicht")
	# Gebunden ans Heim-WLAN (Stand des Gerätetests): Antworten an den Hotspot gehen ins Leere – genau das zeigt der Plan mit gebundenen Sockets.
	var tied := NetAndroid.host_plan(both, "wifi")
	check(tied.reach == ["wlan"] and tied.warn and tied.hint.contains("neu eröffnest"), "Gebundene Sockets: nur WLAN erreichbar, Hinweis „neu eröffnen“")
	# 2. Ohne Kennzeichen „local“ (anderer Hersteller): swlan0 ohne Gateway bleibt Hotspot.
	var spot_plain: Dictionary = S24_SPOT.duplicate()
	spot_plain.erase("local")
	var plain := s24([S24_WLAN, spot_plain], S24_IFACES)
	check(NetAndroid.hotspot_addresses(plain) == ["10.110.43.61"] and NetAndroid.wifi_handle(plain) == "3233221103629" and NetAndroid.host_plan(plain).reach == ["wlan", "hotspot"],
		"Ohne „lokales Netz“: Hotspot am Schnittstellennamen swlan0 erkannt")
	# 3. Bis Android 15 (S21 am 03.10.): Hotspot nur als Schnittstelle, nicht in der Netzliste.
	var old := s24([S24_WLAN], S24_IFACES)
	check(NetAndroid.hotspot_addresses(old) == ["10.110.43.61"] and NetAndroid.wifi_handle(old) == "3233221103629" and NetAndroid.host_plan(old).bind == "",
		"Android 15: Hotspot nur als Schnittstelle erkannt, Gastgeber ungebunden")
	# 4. Nach „WLAN aus“ (zweite Hälfte des Protokolls): Mobilnetz ist Standard, Bindung zeigt aufs verlorene Heim-WLAN.
	var lost_bind := {"handle": "3233221103629", "transport": "?", "addresses": [], "gateway": ""}
	var off := s24([S24_MOBILE, S24_SPOT], [S24_IFACES[1], S24_RMNET], lost_bind)
	var off_plan := NetAndroid.host_plan(off)
	check(not NetAndroid.wifi_connected(off) and NetAndroid.wifi_handle(off) == "" and not NetAndroid.bound_to_wifi(off)
		and NetAndroid.hotspot_addresses(off) == ["10.110.43.61"] and off_plan.bind == "hotspot" and NetAndroid.hotspot_handle(off) == "3237516070925" and off_plan.reach == ["hotspot"] and off_plan.hint == "",
		"WLAN aus: kein WLAN (der eigene Hotspot zählt nicht), rmnet_data0 192.0.0.2/27 ist kein Hotspot; Gastgeber bindet an den Hotspot (so lief es im Gerätetest)")
	var off15 := s24([S24_MOBILE], [S24_IFACES[1], S24_RMNET])
	check(NetAndroid.host_plan(off15).bind == "" and NetAndroid.host_plan(off15).reach == ["hotspot"] and NetAndroid.hotspot_handle(off15) == "",
		"Nur Hotspot bis Android 15 (kein Netz): ungebunden")
	var later := NetAndroid.host_plan(both, "hotspot")
	check(later.reach == ["hotspot"] and later.warn and later.hint.contains("WLAN ging erst") and NetAndroid.host_frees(both, "hotspot")
		and NetAndroid.host_frees(both, "wifi") and not NetAndroid.host_frees(both, "") and not NetAndroid.host_frees(off, "hotspot")
		and not NetAndroid.host_frees(s24([S24_WLAN], [S24_IFACES[0]]), "wifi"),
		"An den Hotspot gebunden, WLAN kam dazu: nur Hotspot erreichbar, Hinweis; host_frees erkennt, wann ungebunden weiter")
	check(NetAndroid.join_binding(both, "10.110.43.150") == "hotspot" and NetAndroid.join_binding(old, "10.110.43.150") == ""
		and NetAndroid.join_binding(both, "192.168.178.20") == "wifi", "Beitritt: Gastgeber im eigenen Hotspot → an den Hotspot (Android 16) bzw. ungebunden, sonst WLAN")
	check(not NetAndroid.bound_to_wifi(s24([S24_MOBILE, S24_SPOT], S24_IFACES, S24_SPOT)), "An den eigenen Hotspot gebunden zählt nicht als WLAN-Bindung")
	# 5. WLAN ohne Internet (nicht Standardnetz) plus Hotspot: nur Hotspot-Mitspieler erreichbar → Warnung.
	var dull: Dictionary = S24_WLAN.merged({"validated": false, "default": false}, true)
	var dull_plan := NetAndroid.host_plan(s24([dull, S24_MOBILE, S24_SPOT], S24_IFACES + [S24_RMNET]))
	check(dull_plan.reach == ["hotspot"] and dull_plan.warn and dull_plan.hint.contains("kein Internet"),
		"WLAN ohne Internet und Hotspot: nur Hotspot erreichbar, klare Warnung")
	# 6. Ohne Hotspot: wie bisher ans WLAN binden.
	var home := NetAndroid.host_plan(s24([S24_WLAN], [S24_IFACES[0]]))
	check(home.bind == "wifi" and home.reach == ["wlan"] and home.hint == "" and home.hotspot.is_empty(), "Ohne Hotspot: Gastgeber bindet ans WLAN, kein Hinweis")
	# 7. AOSP-Namen: ap0 (nur Schnittstelle), softap0, wlan1 ohne Gateway = Hotspot; wlan1 mit Gateway (zweites WLAN) und CLAT nicht.
	var aosp := {"android": true, "networks": [{"handle": "1", "transport": "wifi", "iface": "wlan0", "addresses": ["192.0.2.5/24"], "gateway": "192.0.2.1", "default": true},
		{"handle": "2", "transport": "wifi", "iface": "wlan1", "addresses": ["198.51.100.1/24"], "gateway": ""}],
		"interfaces": [{"name": "wlan0", "address": "192.0.2.5", "prefix": 24}, {"name": "wlan1", "address": "198.51.100.1", "prefix": 24},
		{"name": "ap0", "address": "192.168.43.1", "prefix": 24}, {"name": "softap0", "address": "192.168.44.1", "prefix": 24},
		{"name": "v4-rmnet_data1", "address": "192.0.0.4", "prefix": 32}, {"name": "rmnet_data2", "address": "10.20.30.40", "prefix": 30}]}
	check(NetAndroid.hotspot_addresses(aosp) == ["198.51.100.1", "192.168.43.1", "192.168.44.1"] and NetAndroid.wifi_handle(aosp) == "1",
		"AOSP: wlan1 ohne Gateway, ap0 und softap0 sind Hotspot; CLAT und Mobilfunk nicht")
	aosp.networks[1].gateway = "198.51.100.254"
	check(NetAndroid.hotspot_addresses(aosp) == ["192.168.43.1", "192.168.44.1"] and NetAndroid.wifi_networks(aosp).size() == 2,
		"wlan1 mit Gateway ist ein zweites WLAN, kein Hotspot")
	check(NetAndroid.host_plan({"android": false, "interfaces": [{"name": "Ethernet", "address": "192.0.2.7"}]}).hotspot.is_empty()
		and NetAndroid.in_subnet("10.110.43.150", "10.110.43.61", 24) and not NetAndroid.in_subnet("10.110.44.1", "10.110.43.61", 24)
		and NetAndroid.in_subnet("192.168.1.9", "192.168.178.4", 16), "PC ohne Hotspot; Netzvergleich mit Präfix")

	# --- Lobby mit Android-Ersatz: S24 eröffnet mit WLAN und Hotspot ---
	var fake := FakeAndroid.new()
	fake.nets = [S24_WLAN, S24_SPOT]
	var lb := make("Chef", 0, false, {"use_binding": true, "android_api": fake})
	check(str(fake.bound_net.get("handle", "")) == "3233221103629" and lb.bound, "S24 betritt den WLAN-Mehrspieler: ans Heim-WLAN gebunden (nicht an den Hotspot)")
	check(lb.host("forest", 0) == OK and fake.bound_net.is_empty() and not lb.bound and fake.unbinds == 1, "S24 eröffnet: Bindung gelöst, bevor ENet- und Such-Sockets entstehen")
	lb.refresh_status()
	check(lb.status.reach == ["wlan", "hotspot"] and lb.status.hotspot == ["10.110.43.61"] and lb.status.wlan == ["192.168.178.4"]
		and LobbyScreens.host_addresses(lb.status) == "Zum Eintippen: WLAN 192.168.178.4  ·  Hotspot 10.110.43.61",
		"Lobby zeigt beide Adressen: %s" % LobbyScreens.host_addresses(lb.status))
	var binds := fake.binds
	fake.nets = [S24_MOBILE, S24_SPOT]
	fake.extra = [S24_RMNET]
	lb.refresh_status()
	fake.nets = [S24_WLAN, S24_SPOT]
	fake.extra = []
	lb.refresh_status()
	check(fake.binds == binds and fake.bound_net.is_empty() and lb.mode == "host", "Gastgeber bindet nie neu – auch nicht, wenn das WLAN geht und wiederkommt")
	lb.search()
	check(str(fake.bound_net.get("handle", "")) == "3233221103629", "Zurück zur Suche: wieder ans Heim-WLAN gebunden")
	# Beitritt zu einem Gastgeber im eigenen Hotspot: ungebunden; zu einem im WLAN: gebunden.
	lb.session.connect_timeout_ms = 300
	lb.join("10.110.43.150", PORT + 9)
	check(str(fake.bound_net.get("handle", "")) == "3237516070925" and not lb.bound, "Beitritt zu 10.110.43.150 (im eigenen Hotspot, Android 16): an den Hotspot gebunden")
	lb.cancel_join()
	lb.join("192.168.178.20", PORT + 9)
	check(str(fake.bound_net.get("handle", "")) == "3233221103629", "Beitritt zu 192.168.178.20 (im WLAN): ans WLAN gebunden")
	lb.cancel_join()
	dispose(lb)
	lobbies.clear()

	# --- S24 eröffnet nur mit Hotspot (WLAN aus), danach kommt das WLAN dazu ---
	fake = FakeAndroid.new()
	fake.nets = [S24_MOBILE, S24_SPOT]
	fake.extra = [S24_RMNET]
	var solo := make("Chef", 0, false, {"use_binding": true, "android_api": fake})
	check(fake.bound_net.is_empty() and not solo.bound and solo.status.hotspot == ["10.110.43.61"] and not solo.status.wifi,
		"Nur Hotspot: kein WLAN, nicht gebunden (früher: an den eigenen Hotspot als „WLAN“)")
	check(solo.host("forest", 0) == OK and str(fake.bound_net.get("handle", "")) == "3237516070925" and not solo.bound,
		"Nur Hotspot: Gastgeber an den eigenen Hotspot gebunden")
	solo.refresh_status()
	check(solo.status.reach == ["hotspot"] and solo.status.hint == "" and LobbyScreens.host_addresses(solo.status) == "Zum Eintippen: Hotspot 10.110.43.61",
		"Nur Hotspot: erreichbar im Hotspot, %s" % LobbyScreens.host_addresses(solo.status))
	var solo_enet = solo.session.enet
	fake.nets = [S24_WLAN, S24_MOBILE.merged({"default": false}, true), S24_SPOT]
	solo.refresh_status()
	check(fake.bound_net.is_empty() and solo.session.enet != solo_enet and solo.status.reach == ["wlan", "hotspot"] and not solo.status.warn,
		"WLAN kam dazu, noch niemand da: Bindung gelöst, ENet-Host ungebunden neu – jetzt zweigleisig")
	dispose(solo)
	lobbies.clear()

	# --- Hotspot geht erst nach dem Eröffnen an ---
	fake = FakeAndroid.new()
	fake.nets = [S24_WLAN]
	var host := make("Chef", 0, false, {"use_binding": true, "android_api": fake})
	check(host.host("forest", 0) == OK and host.bound and str(fake.bound_net.get("handle", "")) == "3233221103629", "Ohne Hotspot: Gastgeber ans WLAN gebunden")
	# Ein Mitspieler über das WLAN (hier 127.0.0.1) ist schon da: dessen Verbindung bleibt, der ENet-Host wird nicht neu angelegt.
	var guest := make("Gast", 1)
	guest.join("127.0.0.1", PORT)
	var ok := pump([host, guest], 3000, func(): return guest.is_joined and host.players.size() == 2)
	var sid := host.discovery.sid
	var enet = host.session.enet
	fake.nets = [S24_WLAN, S24_SPOT]
	host.refresh_status()
	check(ok and fake.bound_net.is_empty() and host.session.enet == enet and host.discovery.sid == sid and host.discovery.mode == "host"
		and host.status.warn and str(host.status.hint).contains("neu eröffnest") and host.status.reach == ["wlan"],
		"Hotspot geht an, ein Mitspieler ist da: Bindung gelöst, Ankündigung neu (gleiche Kennung), ENet bleibt, Hinweis „neu eröffnen“")
	guest.leave()
	ok = pump([host, guest], 3000, func(): return host.players.size() == 1 and host.session.peers.is_empty())
	host.refresh_status()
	check(ok and host.session.enet != enet and host.session.enet != null and host.mode == "host" and host.status.reach == ["wlan", "hotspot"]
		and not host.status.warn and fake.binds == 1, "Alle weg: ENet-Host ungebunden neu angelegt, jetzt für WLAN und Hotspot erreichbar – ohne neue Bindung")
	guest.join("127.0.0.1", PORT)
	ok = pump([host, guest], 3000, func(): return guest.is_joined and host.players.size() == 2)
	check(ok, "Nach dem Neuanlegen kann man wieder beitreten")
	dispose(guest)
	dispose(host)
	lobbies.clear()

	# --- Mitspieler: Gastgeber sichtbar, antwortet aber nie (wie im Gerätetest) → Hinweis „WLAN ausschalten“ ---
	var seeker := make("Borst", 0)
	seeker.discovery.games["abc"] = {"address": "127.0.0.1", "addresses": ["127.0.0.1"], "name": "Chef", "via": {"beacon": 5}, "port": PORT + 9}
	check(seeker._only_announced("127.0.0.1") == "Chef", "Nur Ankündigungen, nie eine Antwort: erkannt")
	seeker.session.connect_timeout_ms = 300
	seeker.join("127.0.0.1", PORT + 9)
	ok = pump([seeker], 3000, func(): return not got(seeker, "failed").is_empty())
	var why: Array = got(seeker, "failed")
	check(ok and str(why[0]).contains("antwortet aber nicht") and str(why[0]).contains("WLAN ausschalten"), "Beitritt scheitert mit Hinweis: %s" % (why[0] if ok else "–"))
	seeker.discovery.games["abc"].via = {"beacon": 5, "subnet": 3}
	check(seeker._only_announced("127.0.0.1") == "", "Mit Antworten: kein Hotspot-Hinweis")
	dispose(seeker)
	lobbies.clear()

# ---------- Echte Oberfläche ----------
func buttons(app: Node, prefix: String) -> Array:
	var out: Array = []
	for bt in app.hud.content.find_children("*", "Button", true, false):
		if bt.is_inside_tree() and not bt.is_queued_for_deletion() and (bt as Button).text.begins_with(prefix):
			out.append(bt)
	return out

func press(app: Node, prefix: String) -> bool:
	var list := buttons(app, prefix)
	if list.size() != 1 or (list[0] as Button).disabled:
		printerr("Knopf „%s“: %d gefunden%s" % [prefix, list.size(), " (gesperrt)" if list.size() == 1 else ""])
		return false
	(list[0] as Button).pressed.emit()
	return true

func node(app: Node, node_name: String) -> Node:
	for n in app.hud.content.find_children(node_name, "", true, false):
		if not n.is_queued_for_deletion():
			return n
	return null

func any_text(app: Node, fragment: String) -> bool:
	for l in app.hud.content.find_children("*", "Label", true, false):
		if not l.is_queued_for_deletion() and (l as Label).text.contains(fragment):
			return true
	return false

func frames_until(_list: Array, done: Callable, timeout_ms := 4000) -> bool:
	# Warten aufs Netz ohne Bildtakt: build.ps1 begrenzt jede Testreihe auf 180 Bilder. Alle Lobbys (auch die von main.gd) werden
	# von Hand abgefragt, höchstens alle 100 ms läuft ein Bild (verzögertes Freigeben, call_deferred).
	var end := Time.get_ticks_msec() + timeout_ms
	var next_frame := Time.get_ticks_msec() + 100
	while Time.get_ticks_msec() < end:
		if done.call():
			return true
		if ui_app != null and is_instance_valid(ui_app) and ui_app.lobby != null and is_instance_valid(ui_app.lobby):
			ui_app.lobby.poll()
		for lb in lobbies:
			if is_instance_valid(lb):
				lb.poll()
		OS.delay_msec(2)
		if Time.get_ticks_msec() >= next_frame:
			await process_frame
			next_frame = Time.get_ticks_msec() + 100
	return done.call()

func test_ui() -> void:
	NetLobby.overrides = TEST_OVERRIDES.merged({"auto_poll": true}, true)   # die Lobby, die main.gd anlegt
	var app: Node = load("res://main.tscn").instantiate()
	ui_app = app
	root.add_child(app)
	app.set_physics_process(false)
	await process_frame
	var test_path := "user://test_lobby_%s.json" % Time.get_ticks_usec()
	app.store = ProgressStore.new(test_path)
	app.store.set_player_name("Shakie")
	app.store.result("azure", 0, 0, 25.5, true)
	app.store.save()
	app.select_track("azure")
	app.stage = 0
	var gold: Array = app.store.data.gold.duplicate()
	var best: Dictionary = app.store.data.best.duplicate(true)
	var times: Dictionary = app.store.data.times.duplicate(true)
	var car_before: int = app.car_choice
	# Menü → Mehrspieler → Im WLAN
	app.show_menu()
	check(press(app, "Mehrspieler"), "Menü: Mehrspieler")
	check(app.solo(), "Einzelspieler-Menü: solo() = ja")
	check(press(app, "Im WLAN"), "„Im WLAN“ ist jetzt wählbar")
	check(not app.solo(), "WLAN-Mehrspieler offen: solo() = nein (kein Gold, keine Bestenliste, kein Geist – auch ohne Feld)")
	check(app.phase == "net_menu" and app.lobby != null and app.lobby.mode == "search" and buttons(app, "Spiel eröffnen").size() == 1 and buttons(app, "Adresse eingeben").size() == 1,
		"WLAN-Bildschirm: Eröffnen, Live-Suche, Adresse eingeben")
	app.lobby.forced_status = {"android": true, "networks": [{"transport": "mobile", "addresses": ["10.0.0.2/30"]}], "interfaces": [{"name": "rmnet_data0", "address": "10.0.0.2"}]}
	app.lobby.refresh_status()
	await process_frame
	var status := node(app, "NetStatus") as Label
	check(status != null and status.text.begins_with("Kein WLAN") and status.text.contains("Hotspot"), "Ohne WLAN: klarer Hinweis mit Hotspot-Vorschlag")
	app.lobby.forced_status = {}
	app.lobby.refresh_status()
	# Als Mitspieler: ein Gastgeber „Rita“ im selben Prozess
	var rita := make("Rita", (car_before + 1) % RaceVehicle.CARS.size(), true)
	rita.host("harbor", 1)
	var ok: bool = await frames_until([], func(): return node(app, "Game0") != null)
	check(ok and (node(app, "Game0") as Button).text.contains("Rita") and not (node(app, "Game0") as Button).disabled, "Gefundenes Spiel erscheint in der Liste")
	(node(app, "Game0") as Button).pressed.emit()
	check(app.hud.overlay_open() and node(app, "ConnectCard") != null, "Verbinden …")
	ok = await frames_until([], func(): return app.phase == "net_lobby" and rita.players.size() == 2)
	check(ok and any_text(app, "Shakie  (du)") and any_text(app, "Gastgeber") and node(app, "ReadyButton") != null and node(app, "StartButton") == null,
		"Lobby als Mitspieler: Spielerliste, eigener Eintrag, „Bereit“ statt Start")
	check(app.lobby.me().car == car_before, "Eigenes Auto aus dem Menü vorgewählt")
	rita.set_track("forest")
	ok = await frames_until([], func(): return (node(app, "LobbyTrack") as Label) != null and (node(app, "LobbyTrack") as Label).text == Circuit.load_track("forest").name)
	check(ok, "Einstellung des Gastgebers erscheint sofort")
	# Garage wie im Einzelspieler: dasselbe Auto wie Rita, eigene Farbe (Ritas Farbe gesperrt)
	(node(app, "CarButton") as Button).pressed.emit()
	check(app.phase == "net_garage" and node(app, "GarageCard") != null and is_instance_valid(app.hud.showcase_car), "Auto antippen: Garage mit drehendem Auto")
	(node(app, "CarNext") as Button).pressed.emit()
	ok = await frames_until([], func(): return rita.player(app.lobby.my_id()).car == rita.me().car)
	check(ok and app.phase == "net_garage" and (node(app, "CarName") as Label).text == str(RaceVehicle.CARS[rita.me().car].name), "Auto wechseln (→): dasselbe Auto wie Rita kommt beim Gastgeber an")
	var swatch := node(app, "Swatch%d" % int(rita.me().color)) as Button
	check(swatch != null and swatch.disabled, "Ritas Farbe ist gesperrt")
	(node(app, "Swatch4") as Button).pressed.emit()
	ok = await frames_until([], func(): return rita.player(app.lobby.my_id()).color == 4)
	check(ok and app.phase == "net_garage" and (node(app, "ColorName") as Label).text.begins_with("Orange"), "Farbe wählen kommt beim Gastgeber an (Orange)")
	(node(app, "GarageDone") as Button).pressed.emit()
	check(app.phase == "net_lobby" and node(app, "LobbyName") != null and (node(app, "CarButton") as Button).text.begins_with(str(RaceVehicle.CARS[rita.me().car].name)),
		"Fertig: zurück in die Lobby, gewähltes Auto zu sehen")
	var edit := node(app, "LobbyName") as LineEdit
	edit.text = "Rita"
	edit.text_submitted.emit(edit.text)
	ok = await frames_until([], func(): return rita.player(app.lobby.my_id()).name == "Rita 2")
	check(ok and app.store.player_name() == "Rita", "Name aus der Lobby: eindeutig gemacht und als eigener Name gespeichert")
	(node(app, "ReadyButton") as Button).pressed.emit()
	ok = await frames_until([], func(): return rita.start_problem() == "")
	check(ok and (node(app, "ReadyButton") as Button).text.begins_with("Bereit"), "„Ich bin bereit“ → Gastgeber kann starten")
	rita.start_round()
	ok = await frames_until([], func(): return app.phase == "net_round")
	check(ok and app.track_id == "forest", "Start: Strecke der Runde geladen")
	rita.report_loaded(NetLobby.track_file_hash("forest"))
	ok = await frames_until([], func(): return app.lobby.phase == "ready")
	await process_frame
	check(ok and app.phase == "net_countdown" and node(app, "DrawCountdown") != null, "Alle haben geladen → gemeinsames 3-2-1 vor dem Zeichnen (M4)")
	app.go_back()
	check(node(app, "NetConfirm") != null, "Zurück im Countdown: Nachfrage")
	app.go_back()
	check(node(app, "NetConfirm") == null and app.phase in ["net_countdown", "draw"], "Zurück schließt die Nachfrage")
	rita.back_to_lobby()
	ok = await frames_until([], func(): return app.phase == "net_lobby")
	check(ok, "Gastgeber holt alle zurück in die Lobby")
	rita.leave()
	ok = await frames_until([], func(): return app.phase == "menu" and node(app, "NetMessage") != null)
	check(ok and any_text(app, "Rita") and app.lobby == null, "Gastgeber beendet: Hinweis, zurück im Menü, WLAN-Modus verlassen")
	dispose(rita)
	app.hud.close_overlays()
	# Als Gastgeber
	app.open_wlan()
	press(app, "Spiel eröffnen")
	check(app.phase == "net_lobby" and app.lobby.is_host() and (node(app, "StartButton") as Button).disabled and any_text(app, "Warte auf Mitspieler"), "Gastgeber: Lobby, Start gesperrt ohne Mitspieler")
	var jo := make("Jo", 0, true)
	jo.join("127.0.0.1", PORT)
	ok = await frames_until([], func(): return jo.is_joined and any_text(app, "Jo") and any_text(app, "1 von 4") == false)
	check(ok and any_text(app, "2 von 4") and any_text(app, "wählt noch"), "Mitspieler erscheint in der Liste")
	jo.set_ready(true)
	ok = await frames_until([], func(): return not (node(app, "StartButton") as Button).disabled)
	check(ok, "Mitspieler bereit → Start frei")
	check(press(app, "Stadt"), "Gastgeber wählt die Strecke")
	ok = await frames_until([], func(): return jo.settings.track == "city" and not jo.me().ready)
	check(ok and (node(app, "StartButton") as Button).disabled, "Neue Strecke bei Jo, sein „Bereit“ zurückgesetzt")
	jo.set_ready(true)
	ok = await frames_until([], func(): return not (node(app, "StartButton") as Button).disabled)
	(node(app, "StartButton") as Button).pressed.emit()
	ok = await frames_until([], func(): return app.phase == "net_round" and got(jo, "round_started").size() == 1)
	jo.report_loaded(NetLobby.track_file_hash("city"))
	ok = ok and await frames_until([], func(): return app.lobby.phase == "ready")
	check(ok and app.track_id == "city", "Start als Gastgeber, alle geladen")
	app.go_back()
	check(node(app, "NetConfirm") != null and any_text(app, "Runde abbrechen?"), "Gastgeber: Zurück in der Runde fragt „Runde abbrechen?“")
	(node(app, "ConfirmYes") as Button).pressed.emit()
	ok = await frames_until([], func(): return app.phase == "net_lobby" and jo.phase == "lobby")
	check(ok, "Beide wieder in der Lobby")
	app.go_back()
	check(node(app, "NetConfirm") != null, "Gastgeber mit Mitspielern: Nachfrage vor dem Beenden")
	(node(app, "ConfirmYes") as Button).pressed.emit()
	ok = await frames_until([], func(): return not got(jo, "closed").is_empty() and app.phase == "net_menu")
	check(ok and str(got(jo, "closed")[0]).contains("beendet"), "Spiel beendet: Mitspieler bekommt Bescheid, Gastgeber sucht wieder")
	dispose(jo)
	# Adresse eingeben
	press(app, "Adresse eingeben")
	var field := node(app, "AddressEdit") as LineEdit
	field.text = "999.1"
	(node(app, "AddressConnect") as Button).pressed.emit()
	check(node(app, "AddressEdit") != null and any_text(app, "keine gültige Adresse"), "Ungültige Adresse: Hinweis, Dialog bleibt")
	app.go_back()
	await process_frame
	check(node(app, "AddressEdit") == null and app.phase == "net_menu", "Zurück schließt die Adresseingabe")
	app.go_back()
	check(app.phase == "menu" and app.lobby == null and app.solo(), "Zurück auf dem WLAN-Bildschirm: Menü (Bindung gelöst), wieder Einzelspieler")
	check(app.store.data.gold == gold and app.store.data.best == best and app.store.data.times == times and app.car_choice == car_before and app.track_id == "azure" and app.stage == 0,
		"Kein Gold, keine Bestzeit; Auto, Strecke und Stufe des Einzelspielers unverändert")
	for lb in lobbies:
		dispose(lb)
	lobbies.clear()
	app.queue_free()
	ui_app = null
	await process_frame
	print("INFO: Bilder bis zum Ende: %d (build.ps1: höchstens 180)" % Engine.get_process_frames())
	for suffix in ["", ".bak", ".tmp", ".run"]:
		if FileAccess.file_exists(test_path + suffix):
			DirAccess.remove_absolute(test_path + suffix)
