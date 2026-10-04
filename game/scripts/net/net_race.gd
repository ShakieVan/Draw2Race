class_name NetRace
extends RefCounted

# Gemeinsames Rennen im WLAN-Mehrspieler (M5, docs/MULTIPLAYER_RECHERCHE.md 5.2 Schritte 6–8, 5.3, 5.4) mit den wichtigsten
# Fehlerfällen (M6). Entsteht in NetLobby, sobald alle Linien verteilt sind (NetDraw.plans_ready), und lebt bis zum Ende der Runde.
# Reines Netz und Daten wie NetDraw: keine Szene, kein Spielstand (Anzeige: main.gd liest view, Wertung: lobby_hud.gd).
#
# Der Gastgeber rechnet allein (5.1): RaceField (sim) mit allen Linien und der KI der Lobby im festen 60-Hz-Takt auf der gemeinsamen
# Uhr ab go_at (= Ampelbeginn start_at + 3 s). Takt n gehört zur Rennzeit n/60 – wie im Einzelspieler.
# Turbo (fair, Nutzerentscheidung): Jeder Mensch, auch der Gastgeber, meldet seine Knopfwechsel mit der Taktnummer der gemeinsamen
# Uhr; angewandt werden sie DELAY_TICKS (0,1 s) später. Kommt eine Meldung zu spät, gilt sie im nächsten Takt (stats.late). Die
# tatsächlich angewandten Wechsel stehen in sim.turbo_log (Wiederholung, Geist, Prüfung: dasselbe Rennen lokal nachrechnen).
# Mitspieler rechnen nichts: Der Gastgeber schickt 30 Schnappschüsse je Sekunde (unzuverlässig-geordnet auf Kanal 1, pack_snapshot)
# und Ereignisse zuverlässig. Alle Geräte – auch der Gastgeber („gleiche Bilder“, Entscheidung 7) – zeigen das Rennen DISPLAY_DELAY
# (0,1 s) verzögert aus einem Puffer: zwischen zwei Schnappschüssen überblendet, über Lücken (Verlust im Hotspot 8–9 %) bis
# EXTRAPOLATE weitergerechnet, danach angehalten. Die Marionetten (view) sind gewöhnliche RaceVehicle-Objekte, die nie selbst
# schreiten: Modelle, Reifenspuren, Motorklang, Kamera, Schilder und Turbo-Anzeige lesen sie wie im Einzelspieler. Die Ampel läuft
# auf jedem Gerät nach der gemeinsamen Uhr (Anzeigezeit < 0). Die Wertung (Namen, Zeiten bzw. Punkte) kommt vom Gastgeber.
#
# Nachrichten (Runde = id):
#   Host → alle:  race_snap {id, b}            unzuverlässig-geordnet, Kanal 1, jeden 2. Takt (b = pack_snapshot)
#                 race_ev {id, ev}             zuverlässig, ev = [[Takt, Art, …], …]: hit a b Stoß | rail i Stoß | obst i Stoß Art |
#                                              clack w Stoß | fin i Zielzeit | gone i (Spieler weg, Auto fährt ohne Turbo weiter)
#                 race_result {id, tick, rows, final [, snap, ticks, digest, turbo, late]}   Wertung (Ende der Menschen, KI im Ziel,
#                                              final: mit dem letzten Schnappschuss, zuverlässig)
#   Mitspieler → Host:  race_turbo {id, on, tick, seq}   zuverlässig: Knopfwechsel mit dem Takt der gemeinsamen Uhr (seq zählt sie)
#                       race_alive {id, on, tick, seq}   unzuverlässig, 10-mal je Sekunde: Lebenszeichen mit dem gehaltenen Zustand
# Funkstille (Absturz, WLAN weg, Hauptthread hängt): Kam SILENCE (0,5 s) lang kein Paket eines Mitspielers an, lässt der Gastgeber
# seinen Turbo los – über dieselbe Warteschlange wie jeden Wechsel, also im turbo_log (Wiederholung bleibt bitgleich). ENet selbst
# merkt den Ausfall erst nach Sekunden (NetSession.peer_timeout). Meldet sich der Mitspieler wieder und hält den Knopf noch
# (race_alive mit derselben seq wie der zuletzt angekommene Wechsel), gilt der Turbo wieder – mit der üblichen Verzögerung.
# Fehlerfälle (M6): Ein Mitspieler geht → sein Auto fährt seine Linie ohne Turbo zu Ende (peer_left). Der Gastgeber geht → die
# Sitzung schließt (NetLobby.closed) und main.gd kehrt mit Hinweis ins Menü zurück; bis dahin bleibt das letzte Bild stehen und
# stale() meldet die Funkstille. App im Hintergrund: Turbo wird losgelassen; kommt sie rechtzeitig zurück, springt die Anzeige zur
# gemeinsamen Zeit, sonst endet die Sitzung sauber über die ENet-Zeitgrenze.

signal results_changed              # neue Wertung vom Gastgeber
signal notice(text: String)         # kurzer Hinweis (Mitspieler: „Ben ist weg …“)
signal log_line(text: String)

const DELAY_TICKS := 6              # Turbo: fester Eingabeverzug für alle Menschen (0,1 s)
const SNAP_EVERY := 2               # Schnappschuss jeden 2. Takt (30 Hz)
const DISPLAY_DELAY := 0.1          # s: Anzeige läuft so weit hinter der Simulation (Puffer), auf allen Geräten gleich
const EXTRAPOLATE := 0.25           # s: höchstens so weit über den letzten Schnappschuss hinaus weiterrechnen
const COUNTDOWN := 3.0              # s Ampel (start_at → go_at)
const AFTER_WINNER := 30.0          # s: das Rennen endet spätestens so lange nach dem ersten Zieleinlauf (5.2)
const RACE_LIMIT := 180.0           # s: harte Grenze (wie im Einzelspieler)
const AI_LIMIT := 30.0              # s nach dem Ende der Menschen: so lange darf die KI noch ins Ziel fahren
const MAX_STEPS := 8                # Takte je Abfrage (Aufholen nach einem Hänger, z. B. App kurz im Hintergrund)
const KEEP_TICKS := 240             # Schnappschüsse so viele Takte zurück aufheben
const STALE_SECONDS := 0.5          # so lange ohne Schnappschuss: Hinweis „Verbindung hakt“
const SILENCE := 0.5                # s (echte Zeit) ohne Paket eines Mitspielers: Gastgeber lässt seinen Turbo los
const ALIVE_EVERY := 0.1            # s (echte Zeit): Mitspieler senden so oft race_alive
const JUMP := 8.0                   # m zwischen zwei Schnappschüssen: Sprung, nicht überblenden
const HEADER_BYTES := 8
const CAR_BYTES := 34
const LOOP_BYTES := 15
const DRIFT_BYTES := 6
const F_BOOST := 1
const F_FINISH := 2
const F_CRASH := 4
const F_AIR := 8
const F_LOOP := 16
const F_LOOPFALL := 32
const F_ROLLED := 64
const F_WRECK := 128
const F_SHORTCUT := 256
const F_RAIL := 512
const F_LIP := 1024
const F_EDGE := 2048
const F_LOOPDATA := 4096
const G := 9.81

var lobby: Node                     # NetLobby (Sitzung)
var draw: NetDraw                   # Linien, Spielerliste und gemeinsame Uhr der Runde
var round_id := 0
var is_host := false
var my_id := 0
var track: Circuit                  # Strecke der Anzeige
var entries: Array[Dictionary] = [] # Teilnehmerliste (PassParty.entries, "peer" = Spieler-ID der Menschen)
var peer_of: Array[int] = []        # je Auto: Spieler-ID, 0 = KI
var my_index := -1                  # mein Auto (-1: ich fahre nicht mit)
var start_at := 0                   # Host-Uhr (µs): Ampel beginnt
var go_at := 0                      # Host-Uhr (µs): Start, Takt 0
var speed := 1.0                    # Zeitraffer (nur Tests): Rennzeit = Host-Zeit × speed
var stage := 0
var contacts := true
var drift := false
var drift_limit := 0.0
var grip := 1.0                     # Wetter-Haftung der Herausforderung (RaceVehicle.weather_grip beim Rechnen)
var view: RaceField                 # Marionetten (alle Geräte): Aufstellung wie sim, schreiten nie
var gone := {}                      # Autoindex -> true: Spieler weg, sein Auto fährt ohne Turbo weiter

# Gastgeber: Simulation
var sim: RaceField
var tick := 0
var phase := "wait"                 # wait (Ampel) | race | result (nur noch KI) | done
var result_tick := -1               # Takt, in dem alle Menschen fertig waren (Wertung)
var record_history := false         # nur Tests: Lage aller Autos je Takt in history
var history: Array = []
var _inputs: Array[bool] = []
var _queue := {}                    # Autoindex -> [[Takt, an?], …] (angewandt ab diesem Takt)
var _last_apply := {}
var _crash_wait: Array[float] = []
var _first_finish := -1.0
var _was_finished: Array[bool] = []
var _events: Array = []
var _new_finish := false
var _want := {}                     # Autoindex -> zuletzt gemeldeter Knopfzustand (Gastgeber: Wechsel, nach Funkstille losgelassen)
var _seq_in := {}                   # Autoindex -> seq des zuletzt angekommenen Wechsels
var _silenced := {}                 # Autoindex -> true: wegen Funkstille losgelassen, Lebenszeichen darf den Turbo zurückgeben
var stats := {"snaps": 0, "snap_bytes": 0, "snap_max": 0, "event_msgs": 0, "inputs": 0, "late": 0,
	"received": 0, "dropped": 0, "bad": 0, "extrapolated": 0, "held": 0, "max_gap": 0, "alive": 0, "silenced": 0, "resumed": 0}

# Anzeige (alle Geräte)
var snaps: Array = []               # entpackte Schnappschüsse, aufsteigend nach Takt
var events: Array = []              # angekommene, noch nicht gezeigte Ereignisse [[Takt, Art, …]]
var rows: Array = []                # Wertung vom Gastgeber
var rows_tick := -1                 # ab diesem Takt (Anzeigezeit) gilt sie
var final := false
var final_info := {}                # final: ticks, digest, turbo, late
var finish_times := {}              # Autoindex -> genaue Zielzeit (Ereignis „fin“)
var drop_rate := 0.0                # nur Tests: Anteil verworfener Schnappschüsse (Funkverlust nachstellen)
var _rng := RandomNumberGenerator.new()
var _shown := 0.0
var _clock_ready := false
var _last_real := 0
var _last_snap_usec := 0
var _local_on := false
var _local_until := 0
var _sent_on := false
var _turbo_seq := 0                 # Mitspieler: Zahl der gemeldeten Knopfwechsel
var _next_alive := 0                # Mitspieler: nächstes Lebenszeichen (µs, eigene Uhr)

func _init(owner_lobby: Node, d: NetDraw, race_speed := 1.0) -> void:
	lobby = owner_lobby
	draw = d
	round_id = d.round_id
	is_host = d.is_host
	my_id = d.my_id
	track = d.circuit
	speed = maxf(0.01, race_speed)
	start_at = d.start_at
	go_at = d.start_at + int(COUNTDOWN * 1000000.0 / speed)
	_rng.seed = 2026 + my_id
	var party := d.party()
	stage = party.stage
	drift = party.is_drift()
	contacts = party.contacts and not drift
	grip = float(Atmosphere.WEATHER_GRIP.get(str(track.conditions_for(stage).weather), 1.0))
	entries = party.entries()
	for e in entries:
		var id := 0
		if bool(e.human):
			var k := int(e.get("player", -1))
			if k >= 0 and k < d.roster.size():
				id = int(d.roster[k].id)
				if bool(d.roster[k].get("gone", false)):
					gone[peer_of.size()] = true
		e["peer"] = id
		peer_of.append(id)
	my_index = peer_of.find(my_id)
	view = RaceField.new(track)
	view.setup_entries(puppet_entries(entries))
	view.contacts = contacts
	if is_host:
		# Eigene Strecke für die Simulation: Anzeige und Rechnung teilen keinen Zustand (Leitplanke 4).
		var circuit := Circuit.load_track(track.id)
		sim = RaceField.new(circuit)
		var saved := RaceVehicle.weather_grip
		RaceVehicle.weather_grip = grip    # KI-Routen planen mit der Nässe (wie im Einzelspieler nach apply_atmosphere)
		sim.setup_entries(entries)
		if drift:
			drift_limit = drift_limit_for(circuit)
		RaceVehicle.weather_grip = saved
		sim.contacts = contacts
		_inputs.resize(sim.cars.size())
		_crash_wait.resize(sim.cars.size())
		_was_finished.resize(sim.cars.size())
		for i in range(sim.cars.size()):
			_queue[i] = []
	_log("Rennen angelegt: %d Autos (%d Menschen), Berührungen %s, Start in %.2f s" % [entries.size(), peer_of.filter(func(p): return p > 0).size(),
		"an" if contacts else "aus", seconds_until_go()])

# ---------- Uhr ----------
func host_now() -> int:
	return draw.host_now()

func race_seconds() -> float:
	# Rennzeit der Simulation (gemeinsame Uhr, ohne Anzeigeverzug); vor dem Start negativ.
	return float(host_now() - go_at) * speed / 1000000.0

func seconds_until_go() -> float:
	return float(go_at - host_now()) / 1000000.0

func display_ticks() -> float:
	# Anzeigezeit in Takten (Rennzeit − DISPLAY_DELAY), weich nachgeführt: Der Uhrabgleich springt um einige ms, die Anzeige nicht.
	var now := Time.get_ticks_usec()
	var target := (race_seconds() - DISPLAY_DELAY) * 60.0
	if not _clock_ready:
		_clock_ready = true
		_shown = target
	else:
		var real := float(now - _last_real) / 1000000.0
		_shown += real * speed * 60.0
		var err := target - _shown
		if absf(err) > 15.0:
			_shown = target           # großer Sprung (App war im Hintergrund): sofort zur gemeinsamen Zeit
		else:
			_shown += err * clampf(real * 2.0, 0.0, 1.0)
	_last_real = now
	return _shown

# ---------- Eigener Turbo ----------
func set_turbo(on: bool) -> void:
	# Knopfwechsel melden (Takt der gemeinsamen Uhr); der Gastgeber wendet ihn DELAY_TICKS später an. Flamme und Ton zeigt die eigene
	# Anzeige sofort (nur Optik), bis die Schnappschüsse den Wechsel enthalten.
	if my_index < 0 or on == _sent_on or phase == "done" or final:
		return
	_sent_on = on
	_local_on = on
	_local_until = Time.get_ticks_usec() + int((float(DELAY_TICKS) / 60.0 + DISPLAY_DELAY + 0.12) * 1000000.0 / speed)
	var t := maxi(0, int(floor(race_seconds() * 60.0)))
	if is_host:
		_queue_turbo(my_index, on, t)
	else:
		_turbo_seq += 1
		lobby.session.send(1, {"t": "race_turbo", "id": round_id, "on": on, "tick": t, "seq": _turbo_seq})
		lobby.session.flush()
		_next_alive = Time.get_ticks_usec() + int(ALIVE_EVERY * 1000000.0)

func _send_alive() -> void:
	# Mitspieler: Lebenszeichen mit dem gehaltenen Zustand (10 Hz, unzuverlässig), solange das Rennen läuft.
	var now := Time.get_ticks_usec()
	if my_index < 0 or final or gone.has(my_index) or now < _next_alive:
		return
	_next_alive = now + int(ALIVE_EVERY * 1000000.0)
	stats.alive += 1
	lobby.session.send(1, {"t": "race_alive", "id": round_id, "on": _sent_on, "tick": maxi(0, int(floor(race_seconds() * 60.0))), "seq": _turbo_seq},
		MultiplayerPeer.TRANSFER_MODE_UNRELIABLE, NetProtocol.CHANNEL_CONTROL)

func _queue_turbo(i: int, on: bool, t: int) -> void:
	if sim == null or phase == "done" or not sim.is_human(i):
		return
	var at := clampi(t, 0, tick + 600) + DELAY_TICKS
	if at <= tick:
		stats.late += 1
		at = tick + 1
	at = maxi(at, int(_last_apply.get(i, 0)))
	_last_apply[i] = at
	(_queue[i] as Array).append([at, on])

func force_off(id: int) -> void:
	# Gastgeber: Spieler ist im Hintergrund oder weg – sein Turbo gilt ab dem nächsten Takt als losgelassen.
	var i := peer_of.find(id)
	if not is_host or sim == null or i < 0:
		return
	(_queue[i] as Array).clear()
	(_queue[i] as Array).append([tick + 1, false])
	_last_apply[i] = tick + 1
	_want[i] = false
	_silenced.erase(i)

func _check_silence() -> void:
	# Gastgeber: Mitspieler mit gehaltenem Turbo, von denen SILENCE lang nichts kam (abgestürzt, WLAN weg) – Turbo loslassen.
	for i in _want:
		var id := peer_of[i]
		if id <= 1 or not bool(_want[i]) or gone.has(i):
			continue
		var quiet: int = lobby.session.silent_usec(id)
		if quiet > int(SILENCE * 1000000.0):
			force_off(id)
			_silenced[i] = true
			stats.silenced += 1
			_log("Spieler %d seit %.2f s stumm – Turbo ab Takt %d losgelassen" % [id, quiet / 1000000.0, tick + 1])

func _on_alive(i: int, msg: Dictionary) -> void:
	# Lebenszeichen nach Funkstille: Hält der Mitspieler den Knopf noch und kennt der Gastgeber alle seine Wechsel (gleiche seq), gilt
	# der Turbo wieder (wie ein neuer Wechsel zum Takt des Lebenszeichens). Ältere oder vorauseilende Zeichen zählen nicht.
	if not _silenced.has(i) or NetLobby._int(msg.get("seq"), -1) != int(_seq_in.get(i, 0)):
		return
	_silenced.erase(i)
	if NetLobby._bool(msg.get("on")):
		stats.resumed += 1
		_want[i] = true
		_queue_turbo(i, true, NetLobby._int(msg.get("tick"), tick))
		_log("Spieler %d meldet sich wieder und hält den Turbo – gilt wieder" % peer_of[i])

func peer_left(id: int) -> void:
	# Gastgeber: Ein Mitspieler ist weg; sein Auto fährt seine Linie ohne Turbo zu Ende (5.3), alle erfahren es.
	var i := peer_of.find(id)
	if not is_host or i < 0 or gone.has(i):
		return
	gone[i] = true
	force_off(id)
	if phase != "done":
		_events.append([tick, "gone", i])
	_log("Spieler %d weg – Auto %d fährt ohne Turbo weiter" % [id, i])

# ---------- Gastgeber: rechnen und senden ----------
func poll() -> void:
	if not is_host:
		_send_alive()
		return
	if sim == null or phase == "done":
		return
	_check_silence()
	var now_s := race_seconds()
	if phase == "wait":
		if now_s < 0.0:
			return
		phase = "race"
		_log("Start – der Gastgeber rechnet")
	var target := int(floor(now_s * 60.0))
	var budget := int(ceil(MAX_STEPS * speed))
	var sent := false
	while tick < target and budget > 0 and phase != "done":
		budget -= 1
		_step_once()
		if tick % SNAP_EVERY == 0 or phase == "done":
			_send_snapshot()
			sent = true
	if sent:
		lobby.session.flush()

func _step_once() -> void:
	tick += 1
	var dt := 1.0 / 60.0
	var time := float(tick) / 60.0
	for i in _queue:
		var q: Array = _queue[i]
		while not q.is_empty() and int(q[0][0]) <= tick:
			_inputs[i] = bool(q.pop_front()[1])
	var saved := RaceVehicle.weather_grip
	RaceVehicle.weather_grip = grip
	sim.step_inputs(dt, time, _inputs, "race" if phase == "race" else "result")
	RaceVehicle.weather_grip = saved
	_collect_events()
	if record_history:
		var lage: Array = []
		for v in sim.cars:
			lage.append(v.pos)
		history.append(lage)
	if phase == "race":
		if _first_finish < 0.0:
			for v in sim.cars:
				if v.finish_time >= 0.0:
					_first_finish = time
					break
		if _humans_done(dt) or (drift and time > drift_limit) or (_first_finish >= 0.0 and time > _first_finish + AFTER_WINNER) or time > RACE_LIMIT:
			phase = "result"
			result_tick = tick
			_log("Alle Menschen fertig nach %.2f s (Takt %d)" % [time, tick])
			_send_result(false)
	elif phase == "result":
		if sim.done() or time > float(result_tick) / 60.0 + AI_LIMIT:
			phase = "done"
			_log("Rennen zu Ende nach Takt %d" % tick)
			_send_result(true)
		elif _new_finish:
			_send_result(false)
	_new_finish = false

func _humans_done(dt: float) -> bool:
	# Wie main.humans_done: alle Menschen im Ziel oder ausgeschieden; nach einem Absturz noch kurz zusehen (1,6 s, Looping 2,4 s).
	var all := true
	for i in sim.human_indices():
		var v := sim.cars[i]
		if v.crashed:
			_crash_wait[i] += dt
		if not (v.finish_time >= 0.0 or _crash_wait[i] > (2.4 if v.loop_fall else 1.6)):
			all = false
	return all

func _collect_events() -> void:
	# Kurze Stöße der Simulation (sonst liest sie im Einzelspieler race_sounds und setzt sie zurück – ohne Einfluss auf die Physik).
	for hit in sim.impacts:
		if float(hit[2]) >= 0.8:
			_events.append([tick, "hit", int(hit[0]), int(hit[1]), float(hit[2])])
	for i in range(sim.cars.size()):
		var v := sim.cars[i]
		if v.guard_hit > 0.4:
			_events.append([tick, "rail", i, v.guard_hit])
		v.guard_hit = 0.0
		if v.obstacle_hit > 1.0:
			_events.append([tick, "obst", i, v.obstacle_hit, v.obstacle_kind])
		v.obstacle_hit = 0.0
		if v.finish_time >= 0.0 and not _was_finished[i]:
			_was_finished[i] = true
			_new_finish = true
			_events.append([tick, "fin", i, v.finish_time])
	for k in range(sim.seesaws.size()):
		if sim.seesaws[k].clack > 0.15:
			_events.append([tick, "clack", k, sim.seesaws[k].clack])

func _send_snapshot() -> void:
	var bytes := pack_snapshot(tick, sim.cars, sim.seesaws, sim.post_state, sim.track, drift)
	var msg := {"t": "race_snap", "id": round_id, "b": bytes}
	lobby.session.send_all(msg, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED, NetProtocol.CHANNEL_SNAPSHOT)
	var size := NetProtocol.encode(msg).size()
	stats.snaps += 1
	stats.snap_bytes += size
	stats.snap_max = maxi(int(stats.snap_max), size)
	_push_snapshot(bytes)               # eigene Anzeige: dieselben Daten mit derselben Verzögerung
	_flush_events()

func _flush_events() -> void:
	if _events.is_empty():
		return
	lobby.session.send_all({"t": "race_ev", "id": round_id, "ev": _events})
	stats.event_msgs += 1
	_take_events_in(_events)
	_events = []

func _send_result(is_final: bool) -> void:
	_flush_events()
	var msg := {"t": "race_result", "id": round_id, "tick": result_tick, "rows": rank_rows(sim.cars, drift, drift_limit, gone), "final": is_final}
	if is_final:
		# Letzter Stand zuverlässig mitschicken: Ging der letzte Schnappschuss verloren, bliebe die Anzeige sonst auf einem älteren stehen.
		msg["snap"] = pack_snapshot(tick, sim.cars, sim.seesaws, sim.post_state, sim.track, drift)
		msg["ticks"] = tick
		msg["digest"] = sim_digest(sim)
		msg["turbo"] = sim.turbo_log.duplicate(true)
		msg["late"] = int(stats.late)
	lobby.session.send_all(msg)
	lobby.session.flush()
	_take_result(msg)

# ---------- Empfang ----------
func on_message(from: int, msg: Dictionary) -> void:
	if NetLobby._int(msg.get("id"), -1) != round_id:
		return
	match str(msg.t):
		"race_turbo":
			var i := peer_of.find(from)
			if is_host and i >= 0 and not gone.has(i):
				stats.inputs += 1
				var on := NetLobby._bool(msg.get("on"))
				_want[i] = on
				_seq_in[i] = maxi(int(_seq_in.get(i, 0)), NetLobby._int(msg.get("seq"), 0))
				_silenced.erase(i)
				_queue_turbo(i, on, NetLobby._int(msg.get("tick"), tick))
		"race_alive":
			var i := peer_of.find(from)
			if is_host and i >= 0 and not gone.has(i):
				_on_alive(i, msg)
		"race_snap":
			if not is_host and from == 1 and msg.get("b") is PackedByteArray:
				stats.received += 1
				if drop_rate > 0.0 and _rng.randf() < drop_rate:
					stats.dropped += 1
					return
				_push_snapshot(msg.b)
		"race_ev":
			if not is_host and from == 1 and msg.get("ev") is Array:
				_take_events_in(msg.ev)
		"race_result":
			if not is_host and from == 1:
				_take_result(msg)

func _push_snapshot(bytes: PackedByteArray) -> void:
	var s := unpack_snapshot(bytes, view.cars.size(), view.seesaws.size(), track)
	if s.is_empty():
		stats.bad += 1
		return
	if not snaps.is_empty() and int(s.tick) <= int(snaps[-1].tick):
		return
	if not snaps.is_empty():
		stats.max_gap = maxi(int(stats.max_gap), int(s.tick) - int(snaps[-1].tick))
	snaps.append(s)
	_last_snap_usec = Time.get_ticks_usec()
	while snaps.size() > 2 and int(snaps[0].tick) < int(s.tick) - KEEP_TICKS:
		snaps.pop_front()

func _take_events_in(list: Array) -> void:
	for e in list:
		if not (e is Array and (e as Array).size() >= 3 and (e[0] is int) and (e[1] is String) and (e[2] is int)):
			continue
		if int(e[2]) < 0 or int(e[2]) >= view.cars.size() + view.seesaws.size():
			continue
		if str(e[1]) == "gone":
			# Sofort zeigen (Hinweis), nicht erst zur Anzeigezeit.
			var i := int(e[2])
			if not gone.has(i) and i < entries.size():
				gone[i] = true
				if not is_host:
					notice.emit("%s ist weg – sein Auto fährt seine Linie ohne Turbo." % str(entries[i].get("name", "?")))
			continue
		events.append(e)

func _take_result(msg: Dictionary) -> void:
	var list := clean_rows(msg.get("rows"), view.cars.size())
	if list.is_empty():
		return
	rows = list
	rows_tick = NetLobby._int(msg.get("tick"), rows_tick)
	if msg.get("snap") is PackedByteArray:
		_push_snapshot(msg.snap)
	if NetLobby._bool(msg.get("final")):
		final = true
		final_info = {"ticks": NetLobby._int(msg.get("ticks"), 0), "digest": str(msg.get("digest", "")).left(64),
			"turbo": msg.get("turbo") if msg.get("turbo") is Array else [], "late": NetLobby._int(msg.get("late"), 0)}
	results_changed.emit()

# ---------- Anzeige ----------
func apply_view(r: float) -> void:
	# Marionetten auf die Anzeigezeit r (Takte) stellen: zwischen den umgebenden Schnappschüssen überblenden, über eine Lücke kurz
	# weiterrechnen, ohne Daten (vor dem Start) die Startaufstellung lassen.
	for w in view.seesaws:
		w.clack = 0.0
	if snaps.is_empty():
		_local_turbo()
		return
	var i := snaps.size() - 1
	while i >= 0 and float(snaps[i].tick) > r:
		i -= 1
	if i < 0:
		_local_turbo()
		return
	var a: Dictionary = snaps[i]
	var b: Dictionary = snaps[i + 1] if i + 1 < snaps.size() else {}
	var alpha := 0.0
	var ex := 0.0
	var yaw_dt := 0.0
	if not b.is_empty():
		alpha = clampf((r - float(a.tick)) / float(int(b.tick) - int(a.tick)), 0.0, 1.0)
	elif not final:
		ex = clampf((r - float(a.tick)) / 60.0, 0.0, EXTRAPOLATE)
		if r - float(a.tick) > 0.5:
			stats.extrapolated += 1
		if (r - float(a.tick)) / 60.0 > EXTRAPOLATE:
			stats.held += 1
		if i > 0:
			yaw_dt = float(int(a.tick) - int(snaps[i - 1].tick)) / 60.0
	var prev: Array = snaps[i - 1].cars if i > 0 else []
	for k in range(view.cars.size()):
		_put(k, a.cars[k], b.cars[k] if not b.is_empty() else {}, alpha, ex, prev[k] if not prev.is_empty() else {}, yaw_dt, int(a.tick))
	var see_b: Array = b.see if not b.is_empty() else []
	for k in range(view.seesaws.size()):
		var w: Seesaw = view.seesaws[k]
		w.phi = lerpf(float(a.see[k]), float(see_b[k]), alpha) if not see_b.is_empty() else float(a.see[k])
		w.prev_phi = w.phi
	for p in a.posts:
		if not view.post_state.has(int(p[0])):
			view.post_state[int(p[0])] = {"load": 0.0, "down": true, "dir": Vector2.from_angle(float(p[1]))}
	_local_turbo()

func _put(k: int, a: Dictionary, b: Dictionary, alpha: float, ex: float, prev: Dictionary, yaw_dt: float, a_tick: int) -> void:
	var v: RaceVehicle = view.cars[k]
	var f := int(a.f)
	var pos: Vector2 = a.p
	var heading := float(a.h)
	var z := float(a.z)
	var vel: Vector2 = a.v
	var vz := float(a.vz)
	var progress := float(a.s)
	var ph := float(a.ph)
	var slip := float(a.slip)
	var brake := float(a.brake)
	var steer := float(a.steer)
	var thr := float(a.thr)
	var turbo := float(a.turbo)
	var theta := float(a.loop.th) if a.has("loop") else 0.0
	var score := float(a.get("ds", 0.0))
	if not b.is_empty() and alpha > 0.0:
		if pos.distance_to(b.p) < JUMP:
			pos = pos.lerp(b.p, alpha)
			heading = lerp_angle(heading, float(b.h), alpha)
			z = lerpf(z, float(b.z), alpha)
			vel = vel.lerp(b.v, alpha)
			vz = lerpf(vz, float(b.vz), alpha)
			progress = lerpf(progress, float(b.s), alpha)
			var d := float(b.ph) - ph
			d -= roundf(d)
			ph = fposmod(ph + d * alpha, 1.0)
			slip = lerpf(slip, float(b.slip), alpha)
			brake = lerpf(brake, float(b.brake), alpha)
			steer = lerpf(steer, float(b.steer), alpha)
			thr = lerpf(thr, float(b.thr), alpha)
			turbo = lerpf(turbo, float(b.turbo), alpha)
			if a.has("loop") and b.has("loop"):
				theta = lerpf(theta, float(b.loop.th), alpha)
			score = lerpf(score, float(b.get("ds", score)), alpha)
		elif alpha >= 0.5:
			pos = b.p
			heading = float(b.h)
			z = float(b.z)
			progress = float(b.s)
			ph = float(b.ph)
	elif ex > 0.0 and f & (F_FINISH | F_CRASH | F_LOOP) == 0:
		pos += vel * ex
		z += vz * ex - (0.5 * G * ex * ex if f & F_AIR else 0.0)
		progress += vel.length() * ex / maxf(track.length, 1.0)
		if not prev.is_empty() and yaw_dt > 0.0:
			heading += wrapf(heading - float(prev.h), -PI, PI) / yaw_dt * ex
	v.pos = pos
	v.heading = heading
	v.z = z
	v.velocity = vel
	v.vz = vz
	v.progress = progress
	v.previous_phase = ph
	v.slip = slip
	v.braking = brake
	v.steering = steer
	v.throttle = thr
	v.turbo = turbo
	v.boosting = f & F_BOOST != 0
	v.crashed = f & F_CRASH != 0
	v.airborne = f & F_AIR != 0
	v.in_loop = f & F_LOOP != 0
	v.loop_fall = f & F_LOOPFALL != 0
	v.rolled_back = f & F_ROLLED != 0
	v.wrecked = f & F_WRECK != 0
	v.on_shortcut = f & F_SHORTCUT != 0
	v.broke_rail = f & F_RAIL != 0
	v.lip_hit = 1.0 if f & F_LIP else 0.0
	v.edge_hit = 1.0 if f & F_EDGE else 0.0
	v.finish_time = float(finish_times.get(k, float(a_tick) / 60.0)) if f & F_FINISH else -1.0
	var deck := int(a.deck)
	v.deck = view.seesaws[deck] if deck >= 0 and deck < view.seesaws.size() else null
	if a.has("loop"):
		var loop: Dictionary = a.loop
		var idx := int(loop.i)
		if idx < track.loops.size():
			v.loop_radius = float(track.loops[idx].radius)
			v.loop_forward = track.tangent(float(track.loops[idx].s))
		v.loop_theta = theta
		v.loop_origin = loop.o
		v.loop_entry = float(loop.e)
	if a.has("ds"):
		v.drift_score = score
		v.drift_multiplier = float(a.dm)
		v.wall_hits = int(a.wh)

func _local_turbo() -> void:
	# Eigener Knopf: Flamme und Ton sofort (nur Optik), bis die Schnappschüsse den Wechsel zeigen.
	if my_index < 0 or my_index >= view.cars.size() or Time.get_ticks_usec() >= _local_until:
		return
	var v: RaceVehicle = view.cars[my_index]
	v.boosting = _local_on and v.turbo > 0.005 and v.finish_time < 0.0 and not v.crashed

func take_events(r: float) -> Array:
	# Ereignisse bis zur Anzeigezeit r: setzt die kurzen Stöße an den Marionetten (Ton, Funken, Blasen) und liefert die Berührungen
	# [a, b, Stoß] wie RaceField.impacts.
	var hits: Array = []
	while not events.is_empty() and float(events[0][0]) <= r:
		var e: Array = events.pop_front()
		var i := int(e[2])
		match str(e[1]):
			"hit":
				if e.size() >= 5 and i < view.cars.size() and int(e[3]) >= 0 and int(e[3]) < view.cars.size():
					hits.append([i, int(e[3]), float(e[4])])
			"rail":
				if e.size() >= 4 and i < view.cars.size():
					view.cars[i].guard_hit = maxf(view.cars[i].guard_hit, float(e[3]))
			"obst":
				if e.size() >= 5 and i < view.cars.size():
					view.cars[i].obstacle_hit = maxf(view.cars[i].obstacle_hit, float(e[3]))
					view.cars[i].obstacle_kind = str(e[4]).left(24)
			"clack":
				if e.size() >= 4 and i < view.seesaws.size():
					view.seesaws[i].clack = float(e[3])
			"fin":
				if e.size() >= 4 and i < view.cars.size():
					finish_times[i] = float(e[3])
	return hits

func stale() -> bool:
	# Mitspieler: seit STALE_SECONDS kein Schnappschuss (Gastgeber weg oder Funk hakt) – die Anzeige steht.
	if is_host or final:
		return false
	var now := Time.get_ticks_usec()
	if _last_snap_usec == 0:
		return race_seconds() > STALE_SECONDS + DISPLAY_DELAY
	return float(now - _last_snap_usec) / 1000000.0 > STALE_SECONDS / speed

func result_shown(r: float) -> bool:
	# Wertung da und die Anzeige hat den Moment erreicht, in dem alle Menschen fertig waren.
	return not rows.is_empty() and rows_tick >= 0 and r >= float(rows_tick)

func row_of(index: int) -> Dictionary:
	for row in rows:
		if int(row.index) == index:
			return row
	return {}

func rematch_order() -> Array:
	# Revanche wie beim Weitergeben: Menschen in umgekehrter Zielreihenfolge (der Sieger startet hinten).
	var order: Array = []
	for row in rows:
		var id := peer_of[int(row.index)] if int(row.index) < peer_of.size() else 0
		if id > 0:
			order.append(id)
	order.reverse()
	return order

func _log(text: String) -> void:
	log_line.emit(text)

# ---------- Statische Hilfen (auch für Tests) ----------
static func puppet_entries(list: Array) -> Array:
	# Marionetten: dieselbe Aufstellung, aber ohne KI-Routen (sie fahren nie selbst; spart das Planen auf jedem Gerät).
	var stub: Array[Dictionary] = []
	for e in list:
		if bool(e.human) and not (e.plan as Array).is_empty():
			stub = RaceField.as_plan(e.plan)
			break
	var out: Array = []
	for e in list:
		var c: Dictionary = (e as Dictionary).duplicate()
		if not bool(c.human) and not stub.is_empty():
			c["plan"] = stub
			c["skill"] = -1.0
		out.append(c)
	return out

static func drift_limit_for(circuit: Circuit) -> float:
	# Wie main.drift_limit: aus der Strecke oder 1,4 × Fahrzeit einer vorsichtigen KI-Fahrt (mindestens 30 s).
	if circuit.time_limit > 0.0:
		return circuit.time_limit
	var bot := RaceVehicle.new(circuit, circuit.ai_route(1.0))
	for t in range(60 * 240):
		bot.step(1.0 / 60.0, false, float(t + 1) / 60.0)
		if bot.finish_time >= 0.0 or bot.crashed:
			break
	return maxf(30.0, bot.finish_time * 1.4)

static func human_won(result_rows: Array, f: RaceField) -> bool:
	# Gemeinsame Musik der Wertung (Gastgeber entscheidet für alle): Platz 1 gehört einem Menschen (nicht abgestürzt, im Drift im
	# Zeitlimit) → Sieg-Stück, sonst Niederlage-Stück.
	if f == null:
		return false
	for row in result_rows:
		if int(row.rank) == 1 and not bool(row.crashed) and bool(row.get("in_time", true)) and f.is_human(int(row.index)):
			return true
	return false

static func rank_rows(cars: Array, drift_mode: bool, limit: float, gone_map := {}) -> Array:
	# Wertung aller Autos wie main.sorted_results (Zielzeit, sonst Fortschritt, Ausgeschiedene hinten) bzw. im Drift wie
	# main.party_rows (im Zeitlimit im Ziel vor allen anderen, dann Punkte). Gleiche Zeit/Punkte = gleicher Platz.
	var list: Array = []
	for i in range(cars.size()):
		var v: RaceVehicle = cars[i]
		var row := {"index": i, "time": v.finish_time, "crashed": v.crashed, "gone": gone_map.has(i)}
		if drift_mode:
			row["score"] = int(v.drift_score)
			row["in_time"] = v.finish_time >= 0.0 and v.finish_time <= limit and not v.crashed
			row["walls"] = v.wall_hits
		else:
			row["progress"] = -1.0 if v.crashed else v.progress
		list.append(row)
	if drift_mode:
		list.sort_custom(func(a: Dictionary, b: Dictionary):
			if a.in_time != b.in_time: return a.in_time
			if a.score != b.score: return a.score > b.score
			return a.index < b.index)
	else:
		list.sort_custom(func(a: Dictionary, b: Dictionary):
			if a.time >= 0 and b.time >= 0: return a.time < b.time
			if a.time >= 0: return true
			if b.time >= 0: return false
			return a.progress > b.progress)
	for k in range(list.size()):
		list[k]["rank"] = k + 1
		if k > 0:
			var same: bool = (list[k].score == list[k - 1].score and list[k].in_time == list[k - 1].in_time) if drift_mode \
				else (list[k].time >= 0 and list[k].time == list[k - 1].time)
			if same:
				list[k]["rank"] = list[k - 1].rank
	return list

static func clean_rows(list, cars: int) -> Array:
	# Wertung aus einer Nachricht: höchstens ein Eintrag je Auto, bekannte Felder mit festen Typen.
	var out: Array = []
	if not list is Array:
		return out
	var seen := {}
	for r in list:
		if not r is Dictionary or out.size() >= cars:
			continue
		var i := NetLobby._int(r.get("index"), -1)
		if i < 0 or i >= cars or seen.has(i):
			continue
		seen[i] = true
		var t = r.get("time")
		var row := {"index": i, "rank": clampi(NetLobby._int(r.get("rank"), out.size() + 1), 1, cars),
			"time": float(t) if (t is float or t is int) and is_finite(float(t)) else -1.0,
			"crashed": NetLobby._bool(r.get("crashed")), "gone": NetLobby._bool(r.get("gone"))}
		if r.has("score"):
			row["score"] = NetLobby._int(r.get("score"), 0)
			row["in_time"] = NetLobby._bool(r.get("in_time"))
			row["walls"] = NetLobby._int(r.get("walls"), 0)
		else:
			var p = r.get("progress")
			row["progress"] = float(p) if (p is float or p is int) and is_finite(float(p)) else 0.0
		out.append(row)
	return out

static func sim_digest(f: RaceField) -> String:
	# Prüfsumme über den Zustand der Simulation (Bits der Lage, Bewegung, Zeiten, Turbo, Wippen und angewandten Turbo-Wechsel). Nicht
	# enthalten sind die kurzen Stoßwerte (guard_hit, obstacle_hit), die Ton und Funken abholen.
	var data: Array = []
	for v in f.cars:
		data.append([v.pos, v.velocity, v.heading, v.yaw, v.steering, v.turbo, v.z, v.vz, v.progress, v.finish_time, v.crashed,
			v.wrecked, v.in_loop, v.loop_theta, v.drift_score, v.wall_hits, v.cursor])
	for w in f.seesaws:
		data.append([w.phi, w.omega])
	data.append(f.turbo_log)
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(var_to_bytes(data))
	return ctx.finish().hex_encode()

static func loop_index(circuit: Circuit, v: RaceVehicle) -> int:
	for k in range(circuit.loops.size()):
		var loop: Dictionary = circuit.loops[k]
		if absf(float(loop.radius) - v.loop_radius) < 0.001 and circuit.tangent(float(loop.s)).dot(v.loop_forward) > 0.999:
			return k
	return 255

static func pack_snapshot(t: int, cars: Array, seesaws: Array, posts: Dictionary, circuit: Circuit, drift_mode: bool) -> PackedByteArray:
	# Kompakt (Byte): Kopf 8 (Takt u32, Autos, Wippen, Pfosten, Drift?) + je Auto 34 (Lage f32, Fortschritt f32, Richtung s16, Höhe s16
	# in cm, Tempo/Steigen/Rutschen/Bremsen f16, Lenkung s8, Gas/Turbo u8, Streckenphase u16, Zustandsbits u16, Wippe s8) + im Looping 15
	# (Winkel, Ursprung f32, Versatz f16, Looping u8) + im Drift 6 (Punkte f32, Faktor u8, Wandberührungen u8) + je Wippe 2 (Neigung
	# f16) + je umgefahrenem Pfosten 3 (Nummer u16, Fallrichtung s8).
	var down: Array = []
	for idx in posts:
		if bool((posts[idx] as Dictionary).get("down", false)) and down.size() < 255:
			down.append(idx)
	var b := PackedByteArray()
	b.resize(HEADER_BYTES + cars.size() * (CAR_BYTES + LOOP_BYTES + DRIFT_BYTES) + seesaws.size() * 2 + down.size() * 3)
	b.encode_u32(0, t)
	b[4] = cars.size()
	b[5] = seesaws.size()
	b[6] = down.size()
	b[7] = 1 if drift_mode else 0
	var o := HEADER_BYTES
	for v: RaceVehicle in cars:
		var loop_data := v.in_loop or v.loop_fall or v.rolled_back
		var f := 0
		if v.boosting: f |= F_BOOST
		if v.finish_time >= 0.0: f |= F_FINISH
		if v.crashed: f |= F_CRASH
		if v.airborne: f |= F_AIR
		if v.in_loop: f |= F_LOOP
		if v.loop_fall: f |= F_LOOPFALL
		if v.rolled_back: f |= F_ROLLED
		if v.wrecked: f |= F_WRECK
		if v.on_shortcut: f |= F_SHORTCUT
		if v.broke_rail: f |= F_RAIL
		if v.lip_hit > 0.0: f |= F_LIP
		if v.edge_hit > 0.0: f |= F_EDGE
		if loop_data: f |= F_LOOPDATA
		b.encode_float(o, v.pos.x)
		b.encode_float(o + 4, v.pos.y)
		b.encode_float(o + 8, v.progress)
		b.encode_s16(o + 12, clampi(roundi(wrapf(v.heading, -PI, PI) / PI * 32767.0), -32767, 32767))
		b.encode_s16(o + 14, clampi(roundi(v.z * 100.0), -32768, 32767))
		b.encode_half(o + 16, v.velocity.x)
		b.encode_half(o + 18, v.velocity.y)
		b.encode_half(o + 20, v.vz)
		b.encode_half(o + 22, v.slip)
		b.encode_half(o + 24, v.braking)
		b.encode_s8(o + 26, clampi(roundi(v.steering * 200.0), -127, 127))
		b[o + 27] = clampi(roundi(v.throttle * 255.0), 0, 255)
		b[o + 28] = clampi(roundi(v.turbo * 255.0), 0, 255)
		b.encode_u16(o + 29, clampi(roundi(fposmod(v.previous_phase, 1.0) * 65535.0), 0, 65535))
		b.encode_u16(o + 31, f)
		var deck := seesaws.find(v.deck) if v.deck != null else -1
		b.encode_s8(o + 33, clampi(deck, -1, 127))
		o += CAR_BYTES
		if loop_data:
			b.encode_float(o, v.loop_theta)
			b.encode_float(o + 4, v.loop_origin.x)
			b.encode_float(o + 8, v.loop_origin.y)
			b.encode_half(o + 12, v.loop_entry)
			b[o + 14] = loop_index(circuit, v)
			o += LOOP_BYTES
		if drift_mode:
			b.encode_float(o, v.drift_score)
			b[o + 4] = clampi(roundi(v.drift_multiplier * 50.0), 0, 255)
			b[o + 5] = clampi(v.wall_hits, 0, 255)
			o += DRIFT_BYTES
	for w in seesaws:
		b.encode_half(o, w.phi)
		o += 2
	for idx in down:
		b.encode_u16(o, clampi(int(idx), 0, 65535))
		var dir: Vector2 = (posts[idx] as Dictionary).get("dir", Vector2.RIGHT)
		b.encode_s8(o + 2, clampi(roundi(dir.angle() / PI * 127.0), -127, 127))
		o += 3
	b.resize(o)
	return b

static func unpack_snapshot(b: PackedByteArray, cars: int, seesaws: int, _circuit: Circuit = null) -> Dictionary:
	# Gegenstück zu pack_snapshot; {} = passt nicht zu diesem Rennen (Autos, Wippen, Länge) oder enthält ungültige Zahlen.
	if b.size() < HEADER_BYTES or b[4] != cars or b[5] != seesaws:
		return {}
	var drift_mode := b[7] & 1 != 0
	var o := HEADER_BYTES
	var list: Array = []
	for k in range(cars):
		if o + CAR_BYTES > b.size():
			return {}
		var f := b.decode_u16(o + 31)
		var c := {"p": Vector2(b.decode_float(o), b.decode_float(o + 4)), "s": b.decode_float(o + 8),
			"h": float(b.decode_s16(o + 12)) / 32767.0 * PI, "z": float(b.decode_s16(o + 14)) / 100.0,
			"v": Vector2(b.decode_half(o + 16), b.decode_half(o + 18)), "vz": b.decode_half(o + 20), "slip": b.decode_half(o + 22),
			"brake": b.decode_half(o + 24), "steer": float(b.decode_s8(o + 26)) / 200.0, "thr": float(b[o + 27]) / 255.0,
			"turbo": float(b[o + 28]) / 255.0, "ph": float(b.decode_u16(o + 29)) / 65535.0, "f": f, "deck": b.decode_s8(o + 33)}
		o += CAR_BYTES
		var nums := [c.p.x, c.p.y, c.s, c.v.x, c.v.y, c.vz, c.slip, c.brake]
		if f & F_LOOPDATA:
			if o + LOOP_BYTES > b.size():
				return {}
			c["loop"] = {"th": b.decode_float(o), "o": Vector2(b.decode_float(o + 4), b.decode_float(o + 8)), "e": b.decode_half(o + 12), "i": b[o + 14]}
			nums.append_array([c.loop.th, c.loop.o.x, c.loop.o.y, c.loop.e])
			o += LOOP_BYTES
		if drift_mode:
			if o + DRIFT_BYTES > b.size():
				return {}
			c["ds"] = b.decode_float(o)
			c["dm"] = float(b[o + 4]) / 50.0
			c["wh"] = b[o + 5]
			nums.append(c.ds)
			o += DRIFT_BYTES
		for x in nums:
			if not is_finite(float(x)) or absf(float(x)) > 100000.0:
				return {}
		list.append(c)
	var see: Array = []
	for k in range(seesaws):
		if o + 2 > b.size():
			return {}
		see.append(clampf(b.decode_half(o), -1.6, 1.6) if is_finite(b.decode_half(o)) else 0.0)
		o += 2
	var posts: Array = []
	for k in range(b[6]):
		if o + 3 > b.size():
			return {}
		posts.append([b.decode_u16(o), float(b.decode_s8(o + 2)) / 127.0 * PI])
		o += 3
	if o != b.size():
		return {}
	return {"tick": b.decode_u32(0), "cars": list, "see": see, "posts": posts}

static func replay(circuit: Circuit, list: Array, with_contacts: bool, weather: float, turbo_log: Array, ticks: int, switch_tick: int) -> RaceField:
	# Dasselbe Rennen ohne Netz nachrechnen (Prüfung „der Gastgeber rechnet wie RaceField“): Teilnehmerliste, Berührungen, Wetter und
	# die angewandten Turbo-Wechsel je Auto (sim.turbo_log), ab switch_tick + 1 nur noch die KI (Ergebnisphase) – wie beim Gastgeber.
	var saved := RaceVehicle.weather_grip
	RaceVehicle.weather_grip = weather
	var f := RaceField.new(circuit)
	f.setup_entries(list)
	f.contacts = with_contacts
	var inputs: Array[bool] = []
	inputs.resize(f.cars.size())
	for t in range(1, ticks + 1):
		var time := float(t) / 60.0
		for i in range(f.cars.size()):
			inputs[i] = f.is_human(i) and i < turbo_log.size() and turbo_log[i] is Array and RaceField.replay_turbo(turbo_log[i], time)
		f.step_inputs(1.0 / 60.0, time, inputs, "race" if switch_tick < 0 or t <= switch_tick else "result")
	RaceVehicle.weather_grip = saved
	return f
