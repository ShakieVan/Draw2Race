extends SceneTree

# WLAN-Mehrspieler M5 „Rennen“ mit den Fehlerfällen aus M6 (scripts/net/net_race.gd, Anschluss in net_lobby.gd, main.gd, lobby_hud.gd):
# 1. Schnappschüsse packen/entpacken (Genauigkeit, Größe, Looping-, Wippen-, Drift- und Pfostendaten, kaputte Pakete), Wertung.
# 2. Host + 2 Mitspieler im selben Prozess über 127.0.0.1 (Testports 24800–24802, Zeitraffer): Lobby → Zeichnen (Bot-Linien) →
#    gemeinsame Ampel → Rennen mit Turbo nach Plan → Wertung. Geprüft: Wertung und Simulation bei allen gleich, der Host rechnet
#    bitgleich wie RaceField ohne Netz (Linien aus Sicht eines Mitspielers, angewandte Turbo-Wechsel), Turbo mit fester Verzögerung,
#    30 Schnappschüsse je Sekunde, Anzeige nah an der Wahrheit und ohne Sprünge – auch mit 10 % verworfenen Schnappschüssen –,
#    Revanche in umgekehrter Zielreihenfolge.
# 3. Fehlerfälle: Mitspieler geht im Rennen (Auto fährt ohne Turbo weiter, alle sehen es, Wertung trotzdem), Gastgeber verstummt
#    (Anzeige steht mit Hinweis, Sitzung endet mit klarem Grund).
# 4. Echte Oberfläche (main.tscn) als Mitspieler: Ampel, Rennen mit eigenem Turbo, Wertung, Revanche, Spielstand bytegleich.
const PORT := 24800
const DISCOVERY_PORT := 24801
const BEACON_PORT := 24802
const SPEED := 6.0
const TEST_OVERRIDES := {"game_port": PORT, "discovery_port": DISCOVERY_PORT, "beacon_port": BEACON_PORT, "probe_local": true,
	"use_broadcast": false, "use_binding": false, "log_path": "", "auto_poll": false, "peer_timeout": [32, 600, 1500], "load_timeout": [32, 600, 1500],
	"draw_lead_ms": 300, "reveal_lead_ms": 150, "reveal_ms": 300, "race_speed": SPEED, "race_history": true}
const TRACKS := ["azure", "city", "forest", "harbor", "serra", "fair", "quarry", "arena", "kids"]
var failures := 0
var checks := 0
var lobbies: Array = []
var events := {}
var circuits := {}
var ui_app: Node

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
	test_pack()
	test_race()
	test_faults()
	test_silence()
	test_drift()
	await test_ui()
	NetLobby.overrides = {}
	print("RESULT: ", checks - failures, "/", checks, " passed")
	quit(1 if failures else 0)

# ---------- Hilfen ----------
func circuit(id: String) -> Circuit:
	if not circuits.has(id):
		circuits[id] = Circuit.load_track(id)
	return circuits[id]

func bot_line(id: String, skill: float, lane := 0.0) -> Array:
	return LineRecorder.plan_to_data(circuit(id).ai_route(skill, lane))

func make(player_name: String, car := 0, extra := {}) -> NetLobby:
	var saved: Dictionary = NetLobby.overrides
	NetLobby.overrides = TEST_OVERRIDES.merged(extra, true)
	var lb := NetLobby.new()
	NetLobby.overrides = saved
	lb.tracks = TRACKS.duplicate()
	root.add_child(lb)
	events[lb] = []
	for sig in ["joined", "failed", "closed", "notice", "round_started", "round_ready", "round_cancelled"]:
		lb.connect(sig, func(value = null): events[lb].append([sig, value]))
	lb.race_ready.connect(func(): lb.race.notice.connect(func(t): events[lb].append(["race_notice", t])))
	lb.enter(player_name, car)
	lobbies.append(lb)
	return lb

func got(lb: NetLobby, sig: String) -> Array:
	return events[lb].filter(func(e): return e[0] == sig).map(func(e): return e[1])

func pump(list: Array, timeout_ms: int, done: Callable, each := Callable()) -> bool:
	var end := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < end:
		for lb in list:
			if is_instance_valid(lb):
				lb.poll()
		if each.is_valid():
			each.call()
		if done.call():
			return true
		OS.delay_msec(1)
	return false

func dispose(lb) -> void:
	if is_instance_valid(lb):
		lb.exit()
		lb.free()

func session(host_name: String, names: Array, track_id: String, ai: int, contacts: bool, drops := {}, extra := {}) -> Array:
	# Host und Mitspieler in der Lobby, Einstellungen gesetzt, alle bereit, Runde gestartet und geladen → gemeinsames Zeichnen.
	var host := make(host_name, 0, extra)
	host.host(track_id, 0)
	var clients: Array = []
	for k in range(names.size()):
		var c := make(str(names[k]), k + 1, extra.merged({"snapshot_drop": float(drops.get(names[k], 0.0))}, true))
		c.join("127.0.0.1", PORT)
		clients.append(c)
	var all := [host] + clients
	pump(all, 4000, func(): return clients.all(func(c): return c.is_joined) and host.players.size() == all.size())
	host.set_track(track_id)
	host.set_ai(ai)
	host.set_contacts(contacts)
	pump(all, 2000, func(): return clients.all(func(c): return c.settings == host.settings))
	for c in clients:
		c.set_ready(true)
	pump(all, 3000, func(): return host.start_problem() == "")
	host.start_round()
	pump(all, 3000, func(): return clients.all(func(c): return c.phase == "loading"))
	for x in all:
		x.report_loaded(NetLobby.track_file_hash(track_id), circuit(track_id))
	pump(all, 3000, func(): return all.all(func(x): return x.draw != null))
	return all

func lines_in(all: Array, track_id: String, skills: Array) -> bool:
	# Jeder gibt seine Bot-Linie ab; danach legt jedes Gerät das Rennen an (race_ready).
	for k in range(all.size()):
		var problem: String = all[k].draw.submit(bot_line(track_id, float(skills[k]), 0.0 if k % 2 == 0 else 1.2))
		if problem != "":
			printerr("Linie abgelehnt: ", problem)
	return pump(all, 4000, func(): return all.all(func(x): return x.race != null))

func render(lb: NetLobby, book: Dictionary) -> void:
	# Wie main.gd je Bild: Anzeigezeit, Marionetten, Ereignisse; dazu Abstand zur Wahrheit (Host-Verlauf) und Sprünge messen.
	var r: NetRace = lb.race
	if r == null:
		return
	var t := r.display_ticks()
	r.apply_view(t)
	r.take_events(t)
	var truth: Array = book.host.race.history if book.has("host") else []
	if t < 1.0:
		return
	book.frames = int(book.get("frames", 0)) + 1
	var a := int(floor(t))
	for i in range(r.view.cars.size()):
		var v: RaceVehicle = r.view.cars[i]
		if a >= 1 and a < truth.size():
			var p0: Vector2 = truth[a - 1][i]
			var p1: Vector2 = truth[a][i]
			if p0.distance_to(p1) < 2.0:
				var err := v.pos.distance_to(p0.lerp(p1, t - float(a)))
				if err > float(book.get("err", 0.0)):
					book.err = err
					book.err_at = "Auto %d, Takt %.1f" % [i, t]
		var last: Dictionary = book.get("last", {})
		if last.has(i) and not v.crashed and v.finish_time < 0.0:
			var dt := (t - float(last[i][0])) / 60.0
			var jump: float = v.pos.distance_to(last[i][1]) - maxf(v.velocity.length(), float(last[i][2])) * dt - 0.05
			book.jump = maxf(float(book.get("jump", 0.0)), jump)
		last[i] = [t, v.pos, v.velocity.length()]
		book.last = last

# ---------- 1. Schnappschüsse ----------
func test_pack() -> void:
	var worst := {"pos": 0.0, "s": 0.0, "h": 0.0, "z": 0.0, "v": 0.0, "turbo": 0.0}
	var flags_ok := true
	var loop_seen := false
	var see_seen := false
	var drift_seen := false
	var posts_seen := false
	var sizes := {}
	for id in ["quarry", "kids", "arena", "forest", "fair"]:
		var c := circuit(id)
		RaceVehicle.weather_grip = 1.0
		var f := RaceField.new(c)
		var sc := int(c.seesaws[0].get("shortcut", -1)) if not c.seesaws.is_empty() else -1
		f.setup(c.ai_route(2.3, 0.0, sc), 2, 0, -1)    # Kinderzimmer: über das Lineal
		var drift: bool = c.mode == "drift"
		for t in range(1, 60 * 70):
			f.step(1.0 / 60.0, t / 60.0, RaceField.player_boost_test(f.cars[0]))
			if t % 7 != 0:
				continue
			var b := NetRace.pack_snapshot(t, f.cars, f.seesaws, f.post_state, c, drift)
			var s := NetRace.unpack_snapshot(b, f.cars.size(), f.seesaws.size())
			if s.is_empty():
				flags_ok = false
				printerr("Schnappschuss %s Takt %d nicht entpackbar" % [id, t])
				break
			sizes[id] = b.size()
			for k in range(f.cars.size()):
				var v := f.cars[k]
				var q: Dictionary = s.cars[k]
				worst.pos = maxf(worst.pos, v.pos.distance_to(q.p))
				worst.s = maxf(worst.s, absf(v.progress - float(q.s)))
				worst.h = maxf(worst.h, absf(wrapf(v.heading - float(q.h), -PI, PI)))
				worst.z = maxf(worst.z, absf(v.z - float(q.z)))
				worst.v = maxf(worst.v, v.velocity.distance_to(q.v) / maxf(1.0, v.velocity.length()))
				worst.turbo = maxf(worst.turbo, absf(v.turbo - float(q.turbo)))
				var f_bits := int(q.f)
				if (f_bits & NetRace.F_CRASH != 0) != v.crashed or (f_bits & NetRace.F_AIR != 0) != v.airborne or (f_bits & NetRace.F_LOOP != 0) != v.in_loop \
						or (f_bits & NetRace.F_FINISH != 0) != (v.finish_time >= 0.0) or (f_bits & NetRace.F_BOOST != 0) != v.boosting:
					flags_ok = false
				if v.in_loop:
					loop_seen = loop_seen or (q.has("loop") and absf(float(q.loop.th) - v.loop_theta) < 1e-6 and int(q.loop.i) < c.loops.size())
				if drift and q.has("ds"):
					drift_seen = drift_seen or absf(float(q.ds) - v.drift_score) < 0.01 and v.drift_score > 0.0
			for k in range(f.seesaws.size()):
				see_seen = see_seen or absf(float(s.see[k]) - f.seesaws[k].phi) < 0.002 and f.seesaws[k].phi != f.seesaws[k].theta
			posts_seen = posts_seen or not s.posts.is_empty()
			if f.done():
				break
	check(worst.pos < 1e-6 and worst.s < 1e-6 and worst.h < 1e-4 and worst.z <= 0.0051, "Lage verlustfrei (f32), Fortschritt ±%s, Richtung ±%s rad, Höhe ±%.4f m" % [str(worst.s), str(worst.h), worst.z])
	check(worst.v < 0.002 and worst.turbo <= 0.002, "Tempo (f16) relativ %.4f, Turbo %.4f" % [worst.v, worst.turbo])
	check(flags_ok, "Zustandsbits (Absturz, Flug, Looping, Ziel, Turbo) stimmen in jedem Schnappschuss")
	check(loop_seen, "Looping: Winkel und Looping-Nummer im Schnappschuss (Steinbruch)")
	check(see_seen, "Wippe: Neigung im Schnappschuss (Kinderzimmer)")
	check(drift_seen, "Drift-Arena: Punkte im Schnappschuss")
	print("INFO: Schnappschuss-Größen (Byte, ohne Hülle): %s; umgefallene Pfosten gesehen: %s" % [str(sizes), str(posts_seen)])
	# Kaputte Pakete
	var c2 := circuit("azure")
	var f2 := RaceField.new(c2)
	f2.setup(c2.ai_route(2.0), 1)
	var good := NetRace.pack_snapshot(5, f2.cars, f2.seesaws, f2.post_state, c2, false)
	check(good.size() == NetRace.HEADER_BYTES + f2.cars.size() * NetRace.CAR_BYTES, "Rundkurs mit %d Autos: %d Byte (Kopf 8 + 34 je Auto)" % [f2.cars.size(), good.size()])
	var cut := good.slice(0, good.size() - 3)
	var bad := good.duplicate()
	bad.encode_float(NetRace.HEADER_BYTES, NAN)
	check(NetRace.unpack_snapshot(cut, f2.cars.size(), 0).is_empty() and NetRace.unpack_snapshot(good, f2.cars.size() + 1, 0).is_empty()
		and NetRace.unpack_snapshot(bad, f2.cars.size(), 0).is_empty() and NetRace.unpack_snapshot(PackedByteArray([1, 2]), 1, 0).is_empty(),
		"Gekürzte, unpassende und ungültige Schnappschüsse werden verworfen")
	# Wertung
	var res := RaceField.run_field(c2, 2)
	var field: RaceField = res.field
	var rows := NetRace.rank_rows(field.cars, false, 0.0)
	var sorted := true
	for k in range(1, rows.size()):
		if float(rows[k].time) >= 0.0 and float(rows[k].time) < float(rows[k - 1].time):
			sorted = false
	check(rows.size() == field.cars.size() and sorted and int(rows[0].rank) == 1 and NetRace.clean_rows(rows, field.cars.size()) == rows,
		"Wertung nach Zielzeit, übersteht die Prüfung beim Empfang unverändert")
	check(NetRace.clean_rows([{"index": 9}, {"index": 0, "time": INF}, {"index": 0}], 4).size() == 1 and NetRace.clean_rows("x", 4).is_empty(),
		"Ungültige Wertungszeilen fallen weg (fremder Index, doppelt, kein Array)")

# ---------- 2. Rennen über das Netz ----------
func test_race() -> void:
	var all := session("Hans", ["Ida", "Jan"], "azure", 1, true, {"Ida": 0.1})
	var host: NetLobby = all[0]
	var ida: NetLobby = all[1]
	var jan: NetLobby = all[2]
	check(all.all(func(x): return x.draw != null), "Drei Geräte im gemeinsamen Zeichnen (Küste, 1 KI, Berührungen an)")
	check(lines_in(all, "azure", [2.4, 1.8, 3.0]), "Alle Linien da → jedes Gerät legt das Rennen an")
	var r_host: NetRace = host.race
	var r_ida: NetRace = ida.race
	var r_jan: NetRace = jan.race
	check(r_host.sim != null and r_ida.sim == null and r_jan.sim == null, "Nur der Gastgeber rechnet (sim), die Mitspieler zeigen nur an")
	check(r_host.view.cars.size() == 4 and r_ida.view.cars.size() == 4 and [r_host.my_index, r_ida.my_index, r_jan.my_index] == [0, 1, 2] and r_ida.peer_of == r_host.peer_of,
		"Startaufstellung überall gleich: 3 Menschen auf 0–2, KI auf 3")
	var grid_same := true
	for i in range(4):
		grid_same = grid_same and r_ida.view.cars[i].pos == r_host.sim.cars[i].pos and r_jan.view.cars[i].heading == r_host.sim.cars[i].heading
	check(grid_same and r_host.go_at == r_ida.go_at, "Marionetten stehen vor dem Start genau wie die Autos des Gastgebers; gemeinsame Startzeit")
	# Turbo nach Plan: [Gerät, an ab s, aus ab s]
	var plan := [[host, 0.5, 1.6], [ida, 1.0, 2.2], [jan, 1.0, 1.4], [host, 6.0, 7.0], [ida, 6.5, 6.8]]
	var requested := {0: [], 1: [], 2: []}
	var state := {}
	var logs := {host: {}, ida: {"host": host}, jan: {"host": host}}
	var each := func():
		for p in plan:
			var lb: NetLobby = p[0]
			var key := str(plan.find(p))
			var now := lb.race.race_seconds()
			var phase := int(state.get(key, 0))
			if (phase == 0 and now >= float(p[1])) or (phase == 1 and now >= float(p[2])):
				var on: bool = phase == 0
				requested[lb.race.my_index].append([int(floor(lb.race.race_seconds() * 60.0)), on])
				lb.race.set_turbo(on)
				state[key] = phase + 1
		render(host, logs[host])
		render(ida, logs[ida])
		render(jan, logs[jan])
	var countdown_seen := r_ida.display_ticks() < 0.0
	var ok := pump(all, 30000, func(): return all.all(func(x): return x.race.final) and r_ida.display_ticks() > float(r_host.tick) + 2.0, each)
	check(countdown_seen and ok, "Ampel (Anzeigezeit < 0) → Rennen → endgültige Wertung bei allen")
	var seconds := float(r_host.tick) / 60.0
	print("INFO: Rennen %.1f s (Takt %d, Wertung ab Takt %d); Gastgeber: %s" % [seconds, r_host.tick, r_host.result_tick, JSON.stringify(r_host.stats)])
	print("INFO: Ida (10 %% Verlust): %s; Jan: %s" % [JSON.stringify(r_ida.stats), JSON.stringify(r_jan.stats)])
	check(var_to_bytes(r_ida.rows) == var_to_bytes(r_host.rows) and var_to_bytes(r_jan.rows) == var_to_bytes(r_host.rows) and r_host.rows.size() == 4,
		"Wertung bei allen bytegleich: %s" % JSON.stringify(r_host.rows.map(func(w): return [w.index, w.rank, snappedf(float(w.time), 0.001)])))
	check(r_ida.final_info.digest == NetRace.sim_digest(r_host.sim) and r_jan.final_info.digest == r_ida.final_info.digest, "Prüfsumme der Simulation bei allen gleich")
	# Bitgleich nachrechnen: Teilnehmerliste und Turbo-Wechsel aus Sicht eines Mitspielers (Ida), frische Strecke
	var f := NetRace.replay(Circuit.load_track("azure"), r_ida.entries, r_ida.contacts, r_ida.grip, r_ida.final_info.turbo, int(r_ida.final_info.ticks), r_ida.rows_tick)
	var same_times := true
	for i in range(f.cars.size()):
		same_times = same_times and f.cars[i].finish_time == r_host.sim.cars[i].finish_time and f.cars[i].pos == r_host.sim.cars[i].pos
	check(NetRace.sim_digest(f) == r_ida.final_info.digest and same_times, "Gastgeber rechnet bitgleich wie RaceField ohne Netz (gleiche Linien, gleiche angewandte Turbo-Wechsel)")
	# Turbo: angewandt genau DELAY_TICKS nach dem Drücken (Takt der gemeinsamen Uhr), für alle gleich
	var delay_ok := true
	var applied_count := 0
	for i in range(3):
		var applied: Array = r_host.sim.turbo_log[i]
		var asked: Array = requested[i]
		applied_count += applied.size()
		if applied.size() != asked.size():
			delay_ok = false
			printerr("Auto %d: %d Wechsel verlangt, %d angewandt" % [i, asked.size(), applied.size()])
			continue
		for k in range(applied.size()):
			var at := roundi(float(applied[k].time) * 60.0)
			if absi(at - (int(asked[k][0]) + NetRace.DELAY_TICKS)) > 1 or bool(applied[k].held) != bool(asked[k][1]):
				delay_ok = false
				printerr("Auto %d Wechsel %d: verlangt Takt %d, angewandt %d" % [i, k, int(asked[k][0]), at])
	check(delay_ok and applied_count == 10 and int(r_host.stats.late) == 0, "Turbo aller Menschen (auch des Gastgebers) gilt %d Takte (0,1 s) nach dem Drücken, nichts zu spät" % NetRace.DELAY_TICKS)
	var rate := float(r_host.stats.snaps) / maxf(seconds, 0.001)
	var mean := int(r_host.stats.snap_bytes) / maxi(1, int(r_host.stats.snaps))
	check(absf(rate - 30.0) < 1.0 and int(r_host.stats.snap_max) < 260, "Schnappschüsse: %.1f je s, im Mittel %d Byte, höchstens %d Byte (4 Autos, mit Hülle)" % [rate, mean, int(r_host.stats.snap_max)])
	var loss := float(r_ida.stats.dropped) / maxf(1.0, float(r_ida.stats.received))
	check(loss > 0.06 and loss < 0.14 and int(r_jan.stats.dropped) == 0, "Ida verwirft %.1f %% der Schnappschüsse (Funkverlust nachgestellt)" % (loss * 100.0))
	var e_jan := float(logs[jan].get("err", 9.0))
	var e_ida := float(logs[ida].get("err", 9.0))
	# Größter Abstand meist beim Zieleinlauf: Das Auto steht in der Simulation sofort, die Anzeige überblendet über 2 Takte.
	check(e_jan < 0.2 and float(logs[jan].get("jump", 9.0)) < 0.1, "Jan: Anzeige höchstens %.3f m neben der Simulation (%s), keine Sprünge (%.3f m)" % [e_jan, str(logs[jan].get("err_at", "")), float(logs[jan].get("jump", 9.0))])
	check(e_ida < 0.5 and float(logs[ida].get("jump", 9.0)) < 0.5, "Ida mit 10 %% Verlust: höchstens %.3f m daneben (%s), größter Sprung %.3f m, größte Lücke %d Takte" % [e_ida, str(logs[ida].get("err_at", "")),
		float(logs[ida].get("jump", 9.0)), int(r_ida.stats.max_gap)])
	check(int(logs[ida].get("frames", 0)) > 200 and int(logs[host].get("frames", 0)) > 200, "Auch der Gastgeber zeigt aus dem Puffer (%d bzw. %d Bilder)" % [int(logs[host].get("frames", 0)), int(logs[ida].get("frames", 0))])
	var fin_same := true
	for i in range(4):
		var want: float = r_host.sim.cars[i].finish_time
		fin_same = fin_same and (want < 0.0 or (float(r_ida.finish_times.get(i, -1.0)) == want and r_ida.view.cars[i].finish_time == want))
	check(fin_same, "Zielzeiten kommen als Ereignis genau an (Marionetten zeigen die exakte Zeit)")
	check(r_ida.result_shown(float(r_host.result_tick)) and not r_ida.result_shown(float(r_host.result_tick) - 1.0), "Wertung gilt ab dem Takt, in dem alle Menschen fertig waren")
	# Revanche: umgekehrte Zielreihenfolge der Menschen
	var humans: Array = r_host.rows.filter(func(w): return int(w.index) < 3).map(func(w): return r_host.peer_of[int(w.index)])
	humans.reverse()
	check(host.rematch(), "Gastgeber startet die Revanche aus der Wertung")
	ok = pump(all, 3000, func(): return [ida, jan].all(func(x): return x.phase == "loading" and x.round_id == 2 and x.race == null))
	check(ok and host.current_round.players.map(func(p): return int(p.id)) == humans and ida.current_round.players.map(func(p): return int(p.id)) == humans,
		"Revanche: alle laden neu, Startreihenfolge %s (der Sieger hinten)" % str(humans))
	for x in all:
		x.report_loaded(NetLobby.track_file_hash("azure"), circuit("azure"))
	ok = pump(all, 3000, func(): return all.all(func(x): return x.draw != null and x.draw.round_id == 2))
	check(ok and ida.draw.ids() == humans, "Revanche: neues gemeinsames Zeichnen mit der neuen Reihenfolge")
	host.back_to_lobby()
	ok = pump(all, 2000, func(): return all.all(func(x): return x.phase == "lobby" and x.race == null and x.draw == null))
	check(ok, "Zurück in die Lobby: Runde und Rennen weg")
	for x in all:
		dispose(x)
	lobbies.clear()
	RaceVehicle.weather_grip = 1.0

# ---------- 3. Fehlerfälle ----------
func test_faults() -> void:
	var all := session("Kai", ["Lea", "Max"], "azure", 0, true)
	var host: NetLobby = all[0]
	var lea: NetLobby = all[1]
	var max_lb: NetLobby = all[2]
	lines_in(all, "azure", [2.0, 2.2, 2.6])
	var r: NetRace = host.race
	var lea_race: NetRace = lea.race
	var max_index: int = max_lb.race.my_index
	var each := func():
		for x in [host, lea]:
			if is_instance_valid(x) and x.race != null:
				x.race.apply_view(x.race.display_ticks())
	# Max hält den Turbo und geht dann mitten im Rennen (Verbindung weg, ohne Abmeldung)
	var ok := pump(all, 6000, func(): return r.race_seconds() > 1.0, each)
	max_lb.race.set_turbo(true)
	pump(all, 6000, func(): return r.race_seconds() > 3.0, each)
	var progress_then: float = r.sim.cars[max_index].progress
	max_lb.session.enet.close()      # wie ein abgestürztes Handy: keine Abmeldung
	lobbies.erase(max_lb)
	max_lb.free()
	ok = pump([host, lea], 4000, func(): return r.gone.has(max_index) and lea_race.gone.has(max_index), each)
	check(ok and r.sim.cars[max_index].finish_time < 0.0, "Max weg mitten im Rennen: Gastgeber und Lea wissen es")
	check(got(lea, "race_notice").any(func(t): return str(t).contains("Max") and str(t).contains("ohne Turbo")), "Lea sieht den Hinweis „%s“" % str(got(lea, "race_notice")))
	ok = pump([host, lea], 30000, func(): return r.final and lea_race.final, each)
	var changes: Array = r.sim.turbo_log[max_index]
	check(ok and r.sim.cars[max_index].progress > progress_then + 0.5 and not changes.is_empty() and not bool(changes[-1].held),
		"Sein Auto fährt seine Linie ohne Turbo weiter (Fortschritt %.2f → %.2f, letzter Turbo-Wechsel: aus)" % [progress_then, r.sim.cars[max_index].progress])
	var row := r.row_of(max_index)
	check(var_to_bytes(lea_race.rows) == var_to_bytes(r.rows) and bool(row.get("gone", false)), "Wertung trotzdem bei allen gleich, Max als „weg“ markiert")
	check(host.phase == "ready" and host.race == r, "Gastgeber bleibt in der Runde (Wertung, dann Revanche oder Lobby)")
	# Gastgeber verstummt mitten im nächsten Rennen (Absturz / WLAN weg): Lea sieht die stehende Anzeige, dann einen klaren Grund
	check(host.rematch(), "Revanche nur mit Lea")
	pump([host, lea], 3000, func(): return lea.phase == "loading")
	for x in [host, lea]:
		x.report_loaded(NetLobby.track_file_hash("azure"), circuit("azure"))
	pump([host, lea], 3000, func(): return host.draw != null and lea.draw != null)
	lines_in([host, lea], "azure", [2.0, 2.2])
	r = host.race
	lea_race = lea.race
	pump([host, lea], 6000, func(): return lea_race.display_ticks() > 120.0, func(): lea_race.apply_view(lea_race.display_ticks()))
	check(not lea_race.stale(), "Rennen läuft, Lea bekommt Schnappschüsse")
	var t0 := Time.get_ticks_msec()
	var seen := {"stale": false, "held": 0}
	ok = pump([lea], 5000, func(): return not got(lea, "closed").is_empty(), func():
		if lea.race != null:
			lea.race.apply_view(lea.race.display_ticks())
			seen.stale = bool(seen.stale) or lea.race.stale()
			seen.held = int(lea.race.stats.held))
	check(bool(seen.stale) and int(seen.held) > 0, "Ohne Schnappschüsse: Anzeige steht nach kurzem Weiterrechnen (%d Bilder angehalten) und meldet „Verbindung hakt“" % int(seen.held))
	check(ok and str(got(lea, "closed")[0]).contains("abgebrochen"), "Nach %d ms: Sitzung zu Ende mit Grund „%s“" % [Time.get_ticks_msec() - t0, str(got(lea, "closed")[0]) if ok else "–"])
	check(lea.race == null and lea.mode == "", "Lea hängt nicht: Runde und Rennen aufgeräumt")
	for x in [host, lea]:
		dispose(x)
	lobbies.clear()
	RaceVehicle.weather_grip = 1.0

func test_silence() -> void:
	# Fehler aus der Prüfung: Wer mit gehaltenem Turbo abstürzte oder aus dem WLAN fiel, behielt den Turbo bis zur ENet-Zeitgrenze
	# (gemessen 5,6 s, Rennen gewonnen). Jetzt lässt der Gastgeber nach 0,5 s Funkstille los – über die Warteschlange, also im turbo_log
	# und bitgleich nachrechenbar. ENet-Grenze hier 4–6 s: Die Funkstille endet nicht als Abgang, die Anwendung erkennt sie selbst.
	var long := [32, 4000, 6000]
	var all := session("Ole", ["Pia"], "azure", 0, true, {}, {"peer_timeout": long, "load_timeout": long, "race_speed": 3.0})
	var host: NetLobby = all[0]
	var pia: NetLobby = all[1]
	check(lines_in(all, "azure", [2.2, 2.4]), "Ole und Pia: Rennen angelegt")
	var r: NetRace = host.race
	var rp: NetRace = pia.race
	var i: int = rp.my_index
	var held := func() -> bool: return not r.sim.turbo_log[i].is_empty() and bool(r.sim.turbo_log[i][-1].held)
	pump(all, 8000, func(): return r.race_seconds() > 1.0)
	rp.set_turbo(true)
	var ok := pump(all, 2000, held)
	pump(all, 500, func(): return false)
	check(ok and int(rp.stats.alive) >= 3 and int(r.stats.silenced) == 0, "Pia hält den Turbo; Lebenszeichen 10 Hz (%d gesendet), keine Fehlauslösung" % int(rp.stats.alive))
	# Funkstille: Pia wird nicht mehr abgefragt (Absturz, WLAN weg) – ENet hält die Verbindung noch Sekunden
	var t0 := Time.get_ticks_msec()
	var seen := {"ms": -1}
	ok = pump([host], 1500, func():
		if int(seen.ms) < 0 and int(r.stats.silenced) > 0:
			seen.ms = Time.get_ticks_msec() - t0
		return not held.call())
	var off_tick: int = roundi(float(r.sim.turbo_log[i][-1].time) * 60.0)
	check(ok and int(seen.ms) >= 380 and int(seen.ms) <= 750 and not r.gone.has(i) and host.players.size() == 2,
		"Gastgeber lässt Pias Turbo %d ms nach ihrer letzten Abfrage los (0,5 s nach ihrem letzten Paket, Takt %d), sie ist noch verbunden" % [int(seen.ms), off_tick])
	pump([host], 300, func(): return false)
	check(not held.call() and int(r.stats.silenced) == 1, "Turbo bleibt aus, solange Pia stumm ist (einmal ausgelöst)")
	# Pia ist wieder da und hält den Knopf noch: Ihr Lebenszeichen gibt den Turbo zurück (mit der üblichen Verzögerung)
	ok = pump(all, 1500, held)
	check(ok and int(r.stats.resumed) == 1, "Pia meldet sich wieder (Knopf noch gehalten): Turbo gilt wieder")
	rp.set_turbo(false)
	ok = pump(all, 1500, func(): return not held.call())
	check(ok, "Pia lässt los: kommt normal an")
	ok = pump(all, 30000, func(): return r.final and rp.final)
	var f := NetRace.replay(Circuit.load_track("azure"), rp.entries, rp.contacts, rp.grip, rp.final_info.turbo, int(rp.final_info.ticks), rp.rows_tick)
	var states: Array = r.sim.turbo_log[i].map(func(c): return bool(c.held))
	check(ok and NetRace.sim_digest(f) == rp.final_info.digest and states == [true, false, true, false],
		"Wertung da, Gastgeber bitgleich wie RaceField ohne Netz; Pias Turbo-Wechsel %s (an, Funkstille aus, wieder an, aus)" % str(states))
	for x in all:
		dispose(x)
	lobbies.clear()
	RaceVehicle.weather_grip = 1.0

func test_drift() -> void:
	# Drift-Arena zu zweit: gleichzeitig, ohne Berührungen und ohne KI (Lobby-Regel), Wertung nach Punkten im Zeitlimit.
	var all := session("Uwe", ["Vera"], "arena", 2, true, {}, {"race_speed": 12.0})
	var host: NetLobby = all[0]
	var vera: NetLobby = all[1]
	check(int(host.settings.ai) == 0 and not bool(host.settings.contacts), "Drift-Arena: die Lobby erzwingt keine KI und keine Berührungen")
	check(lines_in(all, "arena", [1.6, 2.6]), "Drift-Arena: beide Linien da, Rennen angelegt")
	var r: NetRace = host.race
	var rv: NetRace = vera.race
	check(r.drift and rv.drift and not r.sim.contacts and r.sim.cars.size() == 2 and r.drift_limit > 30.0, "Drift: 2 Autos, ohne Berührungen, Zeitlimit %.1f s" % r.drift_limit)
	var ok := pump(all, 30000, func(): return r.final and rv.final and rv.display_ticks() > float(r.tick) + 1.0, func(): rv.apply_view(rv.display_ticks()))
	var rows: Array = rv.rows
	var by_points := rows.size() == 2 and rows.all(func(w): return w.has("score") and w.has("in_time"))
	if by_points and bool(rows[0].in_time) == bool(rows[1].in_time):
		by_points = int(rows[0].score) >= int(rows[1].score)
	check(ok and by_points and var_to_bytes(rv.rows) == var_to_bytes(r.rows), "Drift-Wertung nach Punkten, bei beiden gleich: %s" % JSON.stringify(rows.map(func(w): return [w.index, w.rank, w.get("score", -1), w.get("in_time", false)])))
	var score_shown := absf(rv.view.cars[1].drift_score - r.sim.cars[1].drift_score) < 1.0
	var f := NetRace.replay(Circuit.load_track("arena"), rv.entries, rv.contacts, rv.grip, rv.final_info.turbo, int(rv.final_info.ticks), rv.rows_tick)
	check(score_shown and NetRace.sim_digest(f) == r.final_info.digest, "Drift: Punkte der Marionette wie in der Simulation, Gastgeber bitgleich wie RaceField")
	for x in all:
		dispose(x)
	lobbies.clear()
	RaceVehicle.weather_grip = 1.0

# ---------- 4. Echte Oberfläche ----------
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

func frames_until(done: Callable, timeout_ms := 6000) -> bool:
	# Wie test_draw: Netz ohne Bildtakt abfragen, höchstens alle 100 ms ein Bild (build.ps1: höchstens 180 Bilder je Testreihe).
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
	NetLobby.overrides = TEST_OVERRIDES.merged({"auto_poll": true, "race_speed": 10.0, "race_history": false}, true)
	var app: Node = load("res://main.tscn").instantiate()
	ui_app = app
	root.add_child(app)
	await process_frame
	var test_path := "user://test_race_%s.json" % Time.get_ticks_usec()
	app.store = ProgressStore.new(test_path)
	app.store.set_player_name("Shakie")
	app.store.data["ghost"] = false
	app.store.save()
	app.select_track("azure")
	app.stage = 0
	var saved := FileAccess.get_file_as_string(test_path)
	app.open_wlan()
	var rita := make("Rita", 3, {"auto_poll": true, "race_speed": 10.0, "race_history": false})
	rita.host("azure", 0)
	app.net_join("127.0.0.1", PORT, "Rita")
	var ok: bool = await frames_until(func(): return app.phase == "net_lobby" and rita.players.size() == 2)
	# Autowahl: Shakie nimmt Ritas Auto (Thunder V8), die Farben bleiben verschieden.
	app.lobby.set_car(3)
	ok = await frames_until(func(): return int(rita.player(app.lobby.my_id()).get("car", -1)) == 3)
	check(ok and int(rita.player(app.lobby.my_id()).color) != int(rita.me().color), "Shakie wählt Ritas Auto, die Spielerfarben bleiben verschieden")
	rita.set_ai(1)
	app.lobby.set_ready(true)
	ok = await frames_until(func(): return rita.start_problem() == "")
	rita.start_round()
	ok = await frames_until(func(): return app.phase == "net_round")
	rita.report_loaded(NetLobby.track_file_hash("azure"), circuit("azure"))
	ok = await frames_until(func(): return app.phase == "draw")
	var route: Array[Dictionary] = circuit("azure").ai_route(2.2)
	app.recorder.route = route
	app.recorder.progress = float(app.track.laps)
	app.recorder.complete = true
	app.line_complete()
	app.net_submit()
	rita.draw.submit(bot_line("azure", 2.6))
	ok = await frames_until(func(): return app.phase in ["countdown", "race"])
	var r: NetRace = app.lobby.race
	check(ok and r != null and app.field == r.view and app.vehicles == r.view.cars and app.me == r.my_index and app.me == 1,
		"Gemeinsame Ampel: Anzeige mit den Marionetten, mein Auto ist Startplatz 2")
	check(node(app, "NetBack") != null and (node(app, "NetBack") as Button).text == "Verlassen" and node(app, "TurboGauge") != null and node(app, "NetStale") != null,
		"Renn-Anzeige: „Verlassen“ statt Pause, Turbo-Knopf, Hinweis bei Funkstille (verdeckt)")
	check((node(app, "TurboGauge") as TurboGauge).tint == PlayerColors.color(int(app.lobby.me().color)), "Turbo-Knopf in meiner Spielerfarbe")
	# Gleiches Auto, verschiedene Spielerfarben: Lack/Schild je Mensch in seiner Farbe aus der Runde, bei Gastgeber und Mitspieler gleich;
	# die KI in einer Autofarbe, die sich von beiden abhebt.
	var paints_ok: bool = app.models.size() == 3 and rita.race != null
	for i in range(2):
		var e: Dictionary = r.view.entries[i]
		var listed: Dictionary = rita.draw.entry(int(e.peer))
		paints_ok = paints_ok and int(e.car) == 3 and not listed.is_empty() and e.paint == PlayerColors.color(int(listed.color)) 			and app.models[i].get_meta("tag_color") == e.paint and rita.race.view.entries[i].paint == e.paint
	var ai_tint: Color = app.models[2].get_meta("tag_color") if app.models.size() == 3 else Color.BLACK
	check(paints_ok and r.view.entries[0].paint != r.view.entries[1].paint and PlayerColors.distance(ai_tint, r.view.entries[0].paint) >= PlayerColors.CLASH
		and PlayerColors.distance(ai_tint, r.view.entries[1].paint) >= PlayerColors.CLASH, "Gleiches Auto in zwei Spielerfarben, bei beiden Geräten gleich; KI hebt sich ab")
	check(not app.solo() and app.ghost == null, "WLAN-Rennen: solo() = nein, kein Geisterauto")
	# Hinweis „Bremsen lädt den Turbo.“ ragte früher in den Turbo-Knopf: jetzt einzeilig links daneben, mit Abstand
	var hint := node(app, "TurboHint") as Label
	var knob := (node(app, "TurboGauge") as Control).get_parent() as Control
	var hint_ok := false
	var hint_info := "fehlt"
	if hint != null:
		var font := hint.get_theme_font("font")
		var width := font.get_string_size(hint.text, HORIZONTAL_ALIGNMENT_LEFT, -1, hint.get_theme_font_size("font_size")).x
		var box := Rect2(hint.global_position, Vector2(hint.size.x, maxf(hint.size.y, hint.get_combined_minimum_size().y)))
		var text_rect := Rect2(box.end.x - width - 5.0, box.position.y, width + 10.0, box.size.y)   # rechtsbündig, mit Kontur
		hint_ok = width <= hint.size.x and hint.get_line_count() == 1 and not text_rect.intersects(knob.get_global_rect()) and not box.intersects(knob.get_global_rect())
		hint_info = "Text %.0f px in %.0f px, endet %.0f px vor dem Knopf" % [width, hint.size.x, knob.get_global_rect().position.x - box.end.x]
	check(hint_ok, "Turbo-Hinweis überlappt den Knopf nicht (%s)" % hint_info)
	ok = await frames_until(func(): return app.phase == "race" and app.race_time > 0.3)
	check(ok and app.models.size() == 3 and app.car_names[1] == "Shakie" and app.car_names[0] == "Rita", "Los: Rennen mit Namen (Rita, Shakie, KI)")
	app.turbo_held = true
	ok = await frames_until(func(): return not rita.race.sim.turbo_log[1].is_empty())
	check(ok and bool(rita.race.sim.turbo_log[1][0].held), "Mein Turbo-Knopf kommt beim Gastgeber an (mit 0,1 s Verzögerung angewandt)")
	app.turbo_held = false
	app.go_back()
	check(node(app, "NetConfirm") != null and any_text(app, "Rennen verlassen?"), "Zurück im Rennen: Nachfrage „Rennen verlassen?“")
	app.go_back()
	ok = await frames_until(func(): return app.phase == "result", 9000)
	check(ok and node(app, "NetResults") != null and node(app, "LeaveButton") != null and node(app, "RematchButton") == null, "Wertung vom Gastgeber: Namen und Zeiten, als Mitspieler „Verlassen“")
	check(any_text(app, "Shakie  (du)") and any_text(app, "Rita") and app.lobby.race.row_of(1).size() > 0, "Wertung zeigt mich und Rita")
	ok = await frames_until(func(): return app.lobby.race.final and rita.race.final)
	check(ok and var_to_bytes(app.lobby.race.rows) == var_to_bytes(rita.race.rows), "Endgültige Wertung gleich wie beim Gastgeber")
	rita.rematch()
	ok = await frames_until(func(): return app.phase == "net_round" or app.phase == "net_countdown")
	check(ok and app.vehicles.is_empty() and app.lobby.race == null, "Revanche: alte Autos weg, neue Runde lädt")
	rita.report_loaded(NetLobby.track_file_hash("azure"), circuit("azure"))
	ok = await frames_until(func(): return app.phase == "net_countdown")
	check(ok and app.lobby.draw.ids().size() == 2, "Revanche: gemeinsames 3-2-1 vor dem neuen Zeichnen (Startreihenfolge %s)" % str(app.lobby.draw.ids()))
	app.go_back()
	check(node(app, "NetConfirm") != null, "Zurück: Nachfrage")
	(node(app, "ConfirmYes") as Button).pressed.emit()
	ok = await frames_until(func(): return app.phase == "net_menu")
	app.go_back()
	check(app.phase == "menu" and app.lobby == null, "Verlassen → Suche → Menü")
	check(FileAccess.get_file_as_string(test_path) == saved and app.track_id == "azure", "Spielstand bytegleich (keine Bestenliste, kein Gold, kein Geist)")
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
