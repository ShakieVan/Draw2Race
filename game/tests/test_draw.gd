extends SceneTree

# WLAN-Mehrspieler M4 „Zeichnen synchron“ (scripts/net/net_draw.gd, Anschluss in net_lobby.gd, main.gd, lobby_hud.gd): Packen und
# Prüfen der Linien (verlustfrei, Größe, Ablehnungsgründe), dann ein Host und drei Mitspieler im selben Prozess über 127.0.0.1
# (eigene Testports 24796–24798): Lobby → gemeinsamer Zeichenstart → Fortschritt bei allen → Linien der Bots (ai_route) abgeben,
# eine abgelehnte, eine zurückgezogene → alle Linien bei allen bytegleich → Enthüllung und Ampelzeit gleich. Danach Abbruch beim
# Zeichnen (mit abgegebener Linie bleibt man, ohne fällt man aus der Runde) und die echte Oberfläche (main.tscn) als Mitspieler:
# 3-2-1, Stand der anderen, Fertig, Doch neu zeichnen, Enthüllung, Übergabe an M5, Zurück-Taste, Verlassen beim Zeichnen.
const PORT := 24796
const DISCOVERY_PORT := 24797
const BEACON_PORT := 24798
const TEST_OVERRIDES := {"game_port": PORT, "discovery_port": DISCOVERY_PORT, "beacon_port": BEACON_PORT, "probe_local": true,
	"use_broadcast": false, "use_binding": false, "log_path": "", "auto_poll": false, "peer_timeout": [32, 600, 1500], "load_timeout": [32, 600, 1500],
	"draw_lead_ms": 300, "reveal_lead_ms": 150, "reveal_ms": 300}
const TRACKS := ["azure", "city", "forest", "harbor", "serra", "fair", "quarry", "arena", "kids"]
var failures := 0
var checks := 0
var lobbies: Array = []
var events := {}
var ui_app: Node
var circuits := {}

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
	test_plans()
	await test_sessions()
	await test_drop()
	await test_ui()
	NetLobby.overrides = {}
	print("RESULT: ", checks - failures, "/", checks, " passed")
	quit(1 if failures else 0)

# ---------- Hilfen ----------
func circuit(id: String) -> Circuit:
	if not circuits.has(id):
		circuits[id] = Circuit.load_track(id)
	return circuits[id]

func bot_line(id: String, skill: float, lane := 0.0, shortcut := -1) -> Array:
	return LineRecorder.plan_to_data(circuit(id).ai_route(skill, lane, shortcut))

func bytes_of(v) -> PackedByteArray:
	return var_to_bytes(v)

func make(player_name: String, car := 0, auto := false) -> NetLobby:
	var saved: Dictionary = NetLobby.overrides
	NetLobby.overrides = TEST_OVERRIDES.merged({"auto_poll": auto}, true)
	var lb := NetLobby.new()
	NetLobby.overrides = saved
	lb.tracks = TRACKS.duplicate()
	root.add_child(lb)
	events[lb] = []
	for sig in ["joined", "failed", "closed", "notice", "round_started", "round_ready", "round_cancelled"]:
		lb.connect(sig, func(value = null): events[lb].append([sig, value]))
	lb.round_ready.connect(func(_info): _watch_draw(lb))
	lb.enter(player_name, car)
	lobbies.append(lb)
	return lb

func _watch_draw(lb: NetLobby) -> void:
	lb.draw.notice.connect(func(t): events[lb].append(["draw_notice", t]))
	lb.draw.rejected.connect(func(t): events[lb].append(["rejected", t]))
	lb.draw.plans_ready.connect(func(): events[lb].append(["plans", lb.draw.plan_digest]))

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

func dispose(lb) -> void:
	if is_instance_valid(lb):
		lb.exit()
		lb.free()

func start_round(host: NetLobby, clients: Array, track_id: String) -> bool:
	# Alle bereit → Start → alle laden (Prüfsumme und Strecke melden) → gemeinsames Zeichnen.
	var all := [host] + clients
	var before := got(host, "round_ready").size()
	for x in clients:
		x.set_ready(true)
	if not pump(all, 3000, func(): return host.start_problem() == ""):
		return false
	host.start_round()
	if not pump(all, 3000, func(): return clients.all(func(x): return x.phase == "loading")):
		return false
	for x in all:
		x.report_loaded(NetLobby.track_file_hash(track_id), circuit(track_id))
	return pump(all, 3000, func(): return all.all(func(x): return got(x, "round_ready").size() > before and x.draw != null))

func plans_bytes(lb: NetLobby) -> PackedByteArray:
	# Alle Linien eines Geräts in Startreihenfolge als Bytes (für den Vergleich zwischen den Geräten).
	var out: Array = []
	for id in lb.draw.ids():
		out.append([id, lb.draw.plans.get(id, [])])
	return var_to_bytes(out)

# ---------- Linien packen und prüfen ----------
func test_plans() -> void:
	check(NetProtocol.VERSION >= 3, "Protokollversion %d (ab 3: gemeinsames Zeichnen)" % NetProtocol.VERSION)
	var all_ok := true
	var lossless := true
	var biggest := 0
	for id in TRACKS:
		var t := circuit(id)
		var variants := [[0.0, 0.0, -1], [3.6, 1.2, -1], [2.0, -1.2, -1]]
		for k in range(t.shortcuts.size()):
			variants.append([2.0, 0.0, k])
		for v in variants:
			var data := bot_line(id, v[0], v[1], v[2])
			var problem := NetDraw.check_plan(t, data)
			if problem != "":
				all_ok = false
				printerr("Bot-Linie %s %s abgelehnt: %s" % [id, str(v), problem])
			var packed := NetDraw.pack_plan(data)
			biggest = maxi(biggest, var_to_bytes(packed).size())
			if bytes_of(NetDraw.unpack_plan(packed)) != bytes_of(data):
				lossless = false
	check(all_ok, "KI-Linien (ai_route, auch über Abkürzungen) gelten auf allen 9 Strecken als plausibel")
	check(lossless, "Packen und Entpacken ist verlustfrei (bytegleich mit plan_to_data)")
	check(biggest < 80 * 1024 and 4 * biggest < NetProtocol.MAX_MESSAGE_BYTES, "Gepackte Linie höchstens %d Byte (4 Linien passen in eine Nachricht)" % biggest)
	# Echt gezeichnete Linie (LineRecorder) auf der Stadt
	var t := circuit("city")
	var pen := LineRecorder.new(t)
	pen.begin(t.at(0.0), 0.0)
	var n := int(t.length * t.laps / 1.5)
	for i in range(1, n + 40):
		pen.sample(t.at(minf(float(i) / n * t.laps, t.laps + 0.01), 1.2 * sin(i * 0.03)), i / 60.0)
		if pen.complete:
			break
	var drawn := LineRecorder.plan_to_data(pen.route)
	check(pen.complete and NetDraw.check_plan(t, drawn) == "", "Gezeichnete Linie (LineRecorder) ist plausibel (%d Punkte)" % drawn.size())
	check(bytes_of(NetDraw.unpack_plan(NetDraw.pack_plan(drawn))) == bytes_of(drawn), "Gezeichnete Linie übersteht das Packen bytegleich")
	# Gerätetest 04.10.2026: Ein schneller letzter Strich über die Ziellinie (1–4 m je Bild) setzte Punkte hinter das Ziel, nur der
	# letzte wurde auf s = laps zurückgesetzt – jede so beendete Linie galt als „rückwärts“. Alle Rundkurse mit mehreren Strichtempi.
	var fast_ok := true
	var fast_fail := ""
	for id in ["azure", "city", "forest", "harbor", "fair", "quarry", "kids", "arena"]:
		var ct := circuit(id)
		for step in [1.5, 2.5, 4.0]:
			var fp := LineRecorder.new(ct)
			fp.begin(ct.at(0.0), 0.0)
			var fs := 0.0
			var tick := 0
			while not fp.complete and fp.active and tick < 20000:
				tick += 1
				fs += step / ct.length
				fp.sample(ct.at(fs, 0.8 * sin(fs * 37.0)), tick / 60.0)
			var problem := NetDraw.check_plan(ct, LineRecorder.plan_to_data(fp.route)) if fp.complete else "nicht fertig"
			if problem != "":
				fast_ok = false
				fast_fail = "%s bei %.1f m/Bild: %s" % [id, step, problem]
	check(fast_ok, "Schnell beendete Linien (1,5–4 m je Bild) sind auf allen Rundkursen plausibel %s" % fast_fail)
	# Ablehnungen
	var base := bot_line("city", 2.0)
	var bad := {}
	bad["leer"] = [[], "leer"]
	var rev := base.duplicate(true)
	rev.reverse()
	bad["rückwärts gezeichnet"] = [rev, "beginnt nicht am Start"]
	var back := base.duplicate(true)
	back[200].s = float(back[150].s)
	back[200].x = float(back[150].x)
	back[200].z = float(back[150].z)
	bad["Rücksprung"] = [back, "rückwärts"]
	bad["halbe Linie"] = [base.slice(0, base.size() / 2), "endet nicht im Ziel"]
	bad["Wegpunkte übersprungen"] = [base.slice(0, 100) + base.slice(500), "überspringt Wegpunkte"]
	var fast := base.duplicate(true)
	fast[300].speed = 45.0
	bad["Tempo"] = [fast, "Tempo"]
	var jump := base.duplicate(true)
	jump[300].x = float(jump[300].x) + 5.0
	bad["versetzter Punkt"] = [jump, "passt nicht zur Strecke"]
	var wide := base.duplicate(true)
	wide[300].o = 40.0
	bad["weit neben der Strecke"] = [wide, "zu weit neben"]
	var sc := base.duplicate(true)
	sc[300].sc = 4
	bad["unbekannte Abkürzung"] = [sc, "unbekannte Abkürzung"]
	var nan := base.duplicate(true)
	nan[300].speed = NAN
	bad["NaN"] = [nan, "ungültige Zahlen"]
	var typed := base.duplicate(true)
	typed[3].x = "x"
	bad["Text statt Zahl"] = [typed, "beschädigt"]
	var many: Array = []
	for i in range(NetDraw.max_points(t) + 1):
		many.append(base[mini(i, base.size() - 1)])
	bad["zu viele Punkte"] = [many, "zu viele Punkte"]
	for key in bad:
		var problem := NetDraw.check_plan(t, bad[key][0])
		check(problem.contains(bad[key][1]), "Abgelehnt (%s): %s" % [key, problem])
	var packed := NetDraw.pack_plan(base)
	var broken := packed.duplicate(true)
	broken.v = PackedFloat32Array([1.0, 2.0])
	var short := packed.duplicate(true)
	short.n = 7
	check(NetDraw.unpack_plan(broken).is_empty() and NetDraw.unpack_plan(short).is_empty() and NetDraw.unpack_plan("x").is_empty() and NetDraw.unpack_plan({}).is_empty(),
		"Falsch aufgebaute gepackte Linie wird nicht entpackt")
	var list := [{"id": 1, "plan": packed}]
	check(NetDraw.plans_digest(list) == NetDraw.plans_digest(list.duplicate(true)) and NetDraw.plans_digest(list) != NetDraw.plans_digest([{"id": 2, "plan": packed}]),
		"Prüfsumme über alle Linien stabil und empfindlich")
	var source := FileAccess.get_file_as_string("res://scripts/net/net_draw.gd")
	check(not source.contains("RaceField") and not source.contains("RaceVehicle.new") and not source.contains(".save(") and not source.contains("store."),
		"Gemeinsames Zeichnen rechnet nichts und schreibt keinen Spielstand")

# ---------- Host + 3 Mitspieler ----------
func test_sessions() -> void:
	var host := make("Anna", 0)
	host.host("city", 0)
	var a := make("Ben", 1)
	var b := make("Cleo", 2)
	var c := make("Dino", 3)
	var clients := [a, b, c]
	var all := [host, a, b, c]
	for x in clients:
		x.join("127.0.0.1", PORT)
	var ok := pump(all, 5000, func(): return clients.all(func(x): return x.is_joined) and host.players.size() == 4)
	check(ok, "Host und drei Mitspieler in der Lobby")
	ok = start_round(host, clients, "city")
	check(ok and all.all(func(x): return x.draw != null and x.draw.phase == "draw" and x.draw.roster.size() == 4), "Alle geladen → gemeinsames Zeichnen bei allen angelegt")
	var at := int(host.current_round.draw_at)
	check(all.all(func(x): return int(x.current_round.draw_at) == at and x.draw.draw_at == at), "Gemeinsamer Zeichenstart: derselbe Zeitpunkt (Host-Uhr) bei allen")
	var waits: Array = all.map(func(x): return x.draw.seconds_until(at))
	check(waits.all(func(w): return w <= 0.31 and absf(w - float(waits[0])) < 0.05), "Alle zählen gleichzeitig herunter (%s s)" % str(waits.map(func(w): return snappedf(w, 0.001))))
	check(all.all(func(x): return x.draw.my_id == x.my_id() and x.draw.others().size() == 3), "Jeder kennt sich und die drei anderen")
	# Fortschritt
	a.draw.set_progress(0.6)
	b.draw.set_progress(0.25)
	host.draw.set_progress(0.1)
	ok = pump(all, 2000, func(): return all.all(func(x): return int(x.draw.status_of(a.my_id()).p) == 60 and int(x.draw.status_of(b.my_id()).p) == 25 and int(x.draw.status_of(1).p) == 10))
	check(ok, "Fortschritt kommt bei allen an (Ben 60 %, Cleo 25 %, Anna 10 %)")
	check(c.draw.state_text(a.my_id()) == "zeichnet … 60 %", "Anzeige: „%s“" % c.draw.state_text(a.my_id()))
	# Abgeben: Anna (Host), Ben; Cleo erst mit abgelehnter Linie
	check(host.draw.submit(bot_line("city", 3.0)) == "", "Gastgeberin gibt ihre Linie ab")
	check(a.draw.submit(bot_line("city", 1.0, 1.2)) == "", "Ben gibt seine Linie ab")
	ok = pump(all, 2000, func(): return all.all(func(x): return str(x.draw.status_of(1).st) == "done" and str(x.draw.status_of(a.my_id()).st) == "done"))
	check(ok and b.draw.state_text(1) == "fertig ✓", "„fertig ✓“ bei allen")
	check(all.all(func(x): return x.draw.plans.is_empty() and x.draw.phase == "draw"), "Linien bleiben verdeckt, solange nicht alle fertig sind")
	check(b.draw.submit(bot_line("city", 1.0).slice(0, 300)).contains("endet nicht im Ziel"), "Halbe Linie: schon auf dem eigenen Gerät abgewiesen")
	var fast := bot_line("city", 2.0)
	fast[50].speed = 50.0
	b.session.send(1, {"t": "draw_plan", "id": b.round_id, "hash": b.draw.track_hash, "plan": NetDraw.pack_plan(fast)})
	b.session.send(1, {"t": "draw_plan", "id": b.round_id, "hash": "falsch", "plan": NetDraw.pack_plan(bot_line("city", 2.0))})
	b.session.send(1, {"t": "draw_plan", "id": b.round_id, "hash": b.draw.track_hash, "plan": {"x": "kaputt"}})
	ok = pump(all, 2000, func(): return got(b, "rejected").size() == 3)
	var reasons := got(b, "rejected")
	check(ok and str(reasons[0]).contains("Tempo") and str(reasons[1]).contains("Streckendaten") and str(reasons[2]).contains("unvollständig"),
		"Host prüft und lehnt mit Grund ab: %s" % str(reasons))
	check(str(host.draw.status_of(b.my_id()).st) == "draw" and host.draw.phase == "draw", "Abgelehnte Linie zählt nicht als fertig")
	# Ben zieht zurück und zeichnet neu
	check(a.draw.withdraw(), "Ben zieht seine Linie zurück (neu zeichnen)")
	ok = pump(all, 2000, func(): return str(host.draw.status_of(a.my_id()).st) == "draw" and str(c.draw.status_of(a.my_id()).st) == "draw")
	check(ok, "Zurückgezogen: alle sehen Ben wieder zeichnen")
	check(b.draw.submit(bot_line("city", 2.0, -1.2)) == "", "Cleo gibt eine gültige Linie ab")
	check(c.draw.submit(bot_line("city", 0.5)) == "", "Dino gibt ab")
	ok = pump(all, 2000, func(): return str(host.draw.status_of(c.my_id()).st) == "done" and str(host.draw.status_of(b.my_id()).st) == "done")
	check(ok and host.draw.phase == "draw" and host.draw.waiting_for() == ["Ben"], "Host wartet auf Ben (kein Zeitlimit): %s" % str(host.draw.waiting_for()))
	var ben_line := bot_line("city", 1.5, 1.2)
	a.draw.submit(ben_line)
	ok = pump(all, 4000, func(): return all.all(func(x): return x.draw.phase == "plans"))
	check(ok, "Alle fertig → der Host verteilt alle Linien")
	var want := plans_bytes(host)
	check(all.all(func(x): return plans_bytes(x) == want and x.draw.plan_digest == host.draw.plan_digest and x.draw.plan_digest.length() == 64),
		"Alle Linien bei allen bytegleich (%d Byte, Prüfsumme %s)" % [want.size(), host.draw.plan_digest.left(12)])
	check(bytes_of(host.draw.plans[a.my_id()]) == bytes_of(ben_line) and bytes_of(c.draw.plans[1]) == bytes_of(bot_line("city", 3.0)),
		"Verteilte Linien sind genau die abgegebenen (Ben: die neu gezeichnete)")
	check(all.all(func(x): return x.draw.reveal_at == host.draw.reveal_at and x.draw.start_at == host.draw.start_at and x.draw.start_at - x.draw.reveal_at == 300000),
		"Enthüllung und Ampel zur selben Zeit bei allen")
	check(all.all(func(x): return x.draw.seconds_until(x.draw.reveal_at) <= 0.15 and x.draw.seconds_until(x.draw.start_at) <= 0.45), "Enthüllung kurz nach dem Verteilen")
	var party := c.draw.party()
	var entries := party.entries()
	check(party.count() == 4 and party.names() == ["Anna", "Ben", "Cleo", "Dino"] and entries.size() == 4 and entries.all(func(e): return e.human and (e.plan as Array).size() > 100),
		"Runde für M5: PassParty mit allen Linien (%s)" % str(party.names()))
	check(c.draw.my_slot() == 3 and host.draw.my_slot() == 0 and c.draw.gone_ids().is_empty(), "Startplätze in Lobby-Reihenfolge")
	check(not a.draw.withdraw() and a.draw.submit(ben_line) != "", "Nach dem Verteilen: kein Zurückziehen, kein neues Abgeben")
	host.back_to_lobby()
	ok = pump(all, 2000, func(): return all.all(func(x): return x.phase == "lobby" and x.draw == null))
	check(ok, "Zurück in die Lobby: Zeichnen bei allen beendet")
	for x in all:
		dispose(x)
	lobbies.clear()

func test_drop() -> void:
	var host := make("Hans", 0)
	host.host("harbor", 1)
	var a := make("Ida", 1)
	var b := make("Jan", 2)
	var c := make("Kim", 3)
	var clients := [a, b, c]
	var all := [host, a, b, c]
	for x in clients:
		x.join("127.0.0.1", PORT)
	pump(all, 5000, func(): return clients.all(func(x): return x.is_joined) and host.players.size() == 4)
	var ok := start_round(host, clients, "harbor")
	check(ok, "Runde auf dem Hafen (mit Abkürzung)")
	check(b.draw.submit(bot_line("harbor", 2.0, 0.0, 0)) == "", "Jan gibt eine Linie über die Abkürzung ab")
	pump(all, 2000, func(): return str(host.draw.status_of(b.my_id()).st) == "done")
	var jan := b.my_id()
	var kim := c.my_id()
	b.leave()
	ok = pump(all, 3000, func(): return host.players.size() == 3 and bool(a.draw.entry(jan).get("gone", false)))
	check(ok and host.draw.entry(jan).gone and host.draw.roster.size() == 4, "Jan geht mit abgegebener Linie: bleibt in der Runde (ohne Turbo)")
	check(got(host, "draw_notice").any(func(t): return str(t).contains("Jan") and str(t).contains("ohne Turbo")), "Hinweis: „%s“" % str(got(host, "draw_notice")))
	var t0 := Time.get_ticks_msec()
	ok = pump([host, a, b], 5000, func(): return not host.draw.entry(kim).has("id") and a.draw.entry(kim).is_empty())     # Kim antwortet nicht mehr
	check(ok and host.draw.roster.size() == 3 and a.draw.roster.size() == 3, "Kim (ohne Linie) fällt nach %d ms aus der Runde, alle sehen es" % (Time.get_ticks_msec() - t0))
	check(got(host, "draw_notice").any(func(t): return str(t).contains("Kim") and str(t).contains("nicht mit")) and got(a, "draw_notice").any(func(t): return str(t).contains("Kim"))
		and got(a, "draw_notice").any(func(t): return str(t).contains("Jan") and str(t).contains("ohne Turbo")), "Hinweise bei allen: Jan fährt ohne Turbo, Kim fährt nicht mit")
	check(host.draw.phase == "draw" and host.draw.waiting_for() == ["Hans", "Ida"], "Warten nur noch auf die Verbliebenen: %s" % str(host.draw.waiting_for()))
	host.draw.submit(bot_line("harbor", 3.0))
	a.draw.submit(bot_line("harbor", 1.0, 1.2))
	ok = pump([host, a], 3000, func(): return host.draw.phase == "plans" and a.draw.phase == "plans")
	check(ok and plans_bytes(a) == plans_bytes(host) and a.draw.ids() == [1, a.my_id(), jan], "Linien verteilt: Hans, Ida und Jans Linie, ohne Kim")
	check(a.draw.gone_ids() == [jan] and a.draw.party().count() == 3 and bytes_of(a.draw.plans[jan]) == bytes_of(bot_line("harbor", 2.0, 0.0, 0)),
		"Jan ist als „weg“ markiert, seine Linie (über die Abkürzung) ist dabei")
	for x in all:
		dispose(x)
	lobbies.clear()

# ---------- Echte Oberfläche ----------
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

func press(app: Node, node_name: String) -> bool:
	var b := node(app, node_name) as Button
	if b == null or b.disabled:
		printerr("Knopf %s fehlt oder ist gesperrt" % node_name)
		return false
	b.pressed.emit()
	return true

func frames_until(done: Callable, timeout_ms := 4000) -> bool:
	# Wie test_lobby: Netz ohne Bildtakt abfragen, höchstens alle 100 ms ein Bild (build.ps1: höchstens 180 Bilder je Testreihe).
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

func finish_line(app: Node, skill: float) -> void:
	# Statt mit dem Finger: eine vollständige Linie in den Zeichner legen und wie beim Zeichnen abschließen.
	var route: Array[Dictionary] = circuit(app.track_id).ai_route(skill)
	app.recorder.route = route
	app.recorder.progress = float(app.track.laps)
	app.recorder.complete = true
	app.line_complete()

func test_ui() -> void:
	NetLobby.overrides = TEST_OVERRIDES.merged({"auto_poll": true}, true)
	var app: Node = load("res://main.tscn").instantiate()
	ui_app = app
	root.add_child(app)
	app.set_physics_process(false)
	await process_frame
	var test_path := "user://test_draw_%s.json" % Time.get_ticks_usec()
	app.store = ProgressStore.new(test_path)
	app.store.set_player_name("Shakie")
	app.store.save()
	app.select_track("azure")
	app.stage = 0
	var saved := FileAccess.get_file_as_string(test_path)
	var car_before: int = app.car_choice
	app.open_wlan()
	var rita := make("Rita", (car_before + 1) % RaceVehicle.CARS.size(), true)
	rita.host("forest", 0)
	app.net_join("127.0.0.1", PORT, "Rita")
	var ok: bool = await frames_until(func(): return app.phase == "net_lobby" and rita.players.size() == 2)
	check(ok, "Oberfläche: als Mitspieler in Ritas Lobby")
	app.lobby.set_ready(true)
	ok = await frames_until(func(): return rita.start_problem() == "")
	rita.start_round()
	ok = await frames_until(func(): return app.phase == "net_round")
	rita.report_loaded(NetLobby.track_file_hash("forest"), circuit("forest"))
	ok = await frames_until(func(): return app.phase == "net_countdown")
	check(ok and node(app, "DrawCountdown") != null and app.world.visible and app.track_id == "forest", "Alle geladen → gemeinsames 3-2-1 über der Strecke")
	ok = await frames_until(func(): return app.phase == "draw")
	check(ok and node(app, "DrawStatus") != null and any_text(app, "Du: Shakie") and any_text(app, "zeichnet … 0 %"), "Nach dem Countdown: normale Zeichenansicht mit eigenem Schild und Stand der anderen")
	rita.draw.set_progress(0.6)
	ok = await frames_until(func(): return any_text(app, "zeichnet … 60 %"))
	check(ok, "Ritas Fortschritt erscheint live („zeichnet … 60 %“)")
	var me: int = app.lobby.my_id()
	finish_line(app, 1.0)
	check(app.phase == "net_drawn" and node(app, "SubmitButton") != null, "Linie fertig: „Fertig“ und „Neu zeichnen“")
	ok = await frames_until(func(): return int(rita.draw.status_of(me).p) == 100)
	check(ok and str(rita.draw.status_of(me).st) == "draw", "Rita sieht 100 %, aber noch nicht abgegeben")
	press(app, "SubmitButton")
	ok = await frames_until(func(): return str(rita.draw.status_of(me).st) == "done")
	check(ok and (node(app, "WaitTitle") as Label).text.contains("Rita") and node(app, "RedrawButton") != null, "Abgegeben: „%s“" % (node(app, "WaitTitle") as Label).text)
	press(app, "RedrawButton")
	ok = await frames_until(func(): return str(rita.draw.status_of(me).st) == "draw")
	check(ok and app.phase == "draw" and not app.lobby.draw.submitted, "„Doch neu zeichnen“: Linie zurückgezogen, wieder in der Zeichenansicht")
	finish_line(app, 2.5)
	press(app, "SubmitButton")
	ok = await frames_until(func(): return str(rita.draw.status_of(me).st) == "done")
	app.go_back()
	check(node(app, "NetConfirm") != null and any_text(app, "Runde verlassen?"), "Zurück beim Warten: Nachfrage „Runde verlassen?“")
	app.go_back()
	check(node(app, "NetConfirm") == null and app.phase == "net_drawn", "Zurück schließt die Nachfrage")
	rita.draw.submit(bot_line("forest", 3.0))
	ok = await frames_until(func(): return app.phase == "net_reveal")
	check(ok and node(app, "LinesLegend") != null and any_text(app, "Shakie  (du)") and any_text(app, "Gemeinsamer Start"), "Alle fertig → Enthüllung aller Linien mit Legende")
	check(plans_bytes(app.lobby) == plans_bytes(rita) and bytes_of(app.lobby.draw.plans[me]) == bytes_of(bot_line("forest", 2.5)), "Oberfläche und Gastgeberin haben bytegleich dieselben Linien")
	ok = await frames_until(func(): return app.phase in ["countdown", "race"])
	check(ok and app.lobby.race != null and app.field == app.lobby.race.view and node(app, "NetBack") != null, "Zur gemeinsamen Ampelzeit: das Rennen beginnt (M5, Marionetten, „Verlassen“)")
	rita.back_to_lobby()
	ok = await frames_until(func(): return app.phase == "net_lobby")
	check(ok and not app.world.visible and app.lobby.draw == null, "Gastgeberin holt alle zurück in die Lobby")
	# Verlassen mitten im Zeichnen
	app.lobby.set_ready(true)
	ok = await frames_until(func(): return rita.start_problem() == "")
	rita.start_round()
	ok = await frames_until(func(): return app.phase == "net_round")
	rita.report_loaded(NetLobby.track_file_hash("forest"), circuit("forest"))
	ok = await frames_until(func(): return app.phase == "draw")
	app.go_back()
	press(app, "ConfirmYes")
	ok = await frames_until(func(): return app.phase == "net_menu" and rita.phase == "lobby" and rita.players.size() == 1)
	check(ok and got(rita, "round_cancelled").size() >= 1, "Mitspieler verlässt beim Zeichnen: er ist raus, die Gastgeberin (allein) zurück in der Lobby")
	app.go_back()
	check(app.phase == "menu" and app.lobby == null, "Zurück ins Menü")
	check(FileAccess.get_file_as_string(test_path) == saved and app.car_choice == car_before and app.track_id == "azure" and app.stage == 0,
		"Spielstand bytegleich; Auto, Strecke und Stufe des Einzelspielers unverändert")
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
