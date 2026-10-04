class_name NetDraw
extends RefCounted

# Gemeinsames Zeichnen im WLAN-Mehrspieler (M4, docs/MULTIPLAYER_RECHERCHE.md 5.2 Schritte 3–5). Entsteht in NetLobby, sobald alle
# die Strecke geladen haben (Nachricht „go“), und lebt bis zum Ende der Runde. Reines Netz und Daten wie NetLobby: keine Szene,
# keine Simulation, kein Spielstand (Ablauf und Anzeige: main.gd, lobby_hud.gd).
#
# Ablauf (Nutzerentscheidungen 03.10.2026: kein Zeitlimit, auf alle wird gewartet, Linien verdeckt bis alle fertig sind):
# 1. Gemeinsamer Zeichenstart: Der Host legt draw_at (Host-Uhr, µs) etwa 3 s in die Zukunft und schickt es mit „go“. Jedes Gerät
#    rechnet die Zeit über den Uhrabgleich der Sitzung (NetSession.host_time_usec) in seine eigene Uhr um; alle zählen gleichzeitig 3-2-1.
# 2. Jeder zeichnet seine eigene Linie mit der normalen Zeichenansicht. Fortschritt (0–100 %) geht höchstens 4× je Sekunde an den
#    Host, der den Stand aller höchstens 5× je Sekunde verteilt („Anna zeichnet … 60 %“, „fertig ✓“). Die Linien selbst bleiben
#    auf dem eigenen Gerät, bis alle fertig sind.
# 3. „Fertig“ schickt die Linie (LineRecorder.plan_to_data, kompakt gepackt: pack_plan) zuverlässig an den Host. Er prüft sie
#    (Runde, Prüfsumme der Streckendatei, Größe, Zahlen, Lage auf der Strecke, Fortschritt ohne übersprungene Wegpunkte: check_plan)
#    und lehnt sie sonst mit Grund ab. Bis alle fertig sind, darf jeder seine abgegebene Linie zurückziehen und neu zeichnen.
# 4. Sind alle Linien da, verteilt der Host alle zugleich, unverändert so, wie sie angekommen sind, dazu eine Prüfsumme über alle
#    (digest) und die gemeinsamen Zeitpunkte: reveal_at (Enthüllung in Spielerfarben) und start_at (gemeinsame Ampel, M5).
#    Damit hat jedes Gerät bytegleich dieselben Linien.
# Abbruch eines Mitspielers während des Zeichnens (Entscheidung M4): Hat er seine Linie schon abgegeben, bleibt er in der Runde und
# sein Auto fährt sie später ohne Turbo (wie ein Abbruch im Rennen, 5.3); sonst fällt er aus der Runde (Hinweis an alle). Keine
# KI als Ersatz: Die KI-Zahl hat der Gastgeber in der Lobby gewählt, und eine fremde Linie unter dem Namen des Spielers wäre irreführend.
#
# Nachrichten (zuverlässig, Kanal 0; Runde = id):
#   Host → alle:  draw_state {id, players [{id, name, car, color, gone, p, st}]}       Stand aller (st: "draw" | "done")
#                 draw_plans {id, now, at, start, players, plans [{id, plan}], digest}   alle Linien, Enthüllung um at, Ampel um start
#                 draw_reject {id, reason}                                      an einen Mitspieler: Linie nicht angenommen
#   Mitspieler → Host:  draw_progress {id, p}, draw_plan {id, hash, plan}, draw_withdraw {id}
# Gepackte Linie (pack_plan): {n, x, z: PackedFloat32Array (Vector2 ist float32, also verlustfrei), v (Tempo), s, o:
# PackedFloat64Array, sc: PackedByteArray (Abkürzung + 1)} – rund 33 Byte je Punkt statt 144 als Dictionary-Liste.

signal changed                      # Stand der Spieler (Fortschritt, fertig, ausgestiegen)
signal notice(text: String)         # kurzer Hinweis („Ben ist ausgestiegen …“)
signal rejected(reason: String)     # eigene Linie nicht angenommen (wieder abgeben oder neu zeichnen)
signal plans_ready                  # alle Linien da: Enthüllung um reveal_at, Ampel (M5) um start_at
signal log_line(text: String)

const MAX_PLAN_POINTS := 6000       # harte Grenze je Linie (längste Strecke, gezeichnet: rund 2000 Punkte)
const POINTS_PER_METER := 6.0       # je Meter Strecke und Runde höchstens so viele Punkte (Zickzack-Linien: etwa 3–4)
const POSITION_TOLERANCE := 0.25    # m: Punkt muss zu Streckenanteil, Seitenlage und Abkürzung passen (place)
const SPEED_RANGE := Vector2(4.9, 29.1)   # LineRecorder begrenzt das Tempo auf 5–29 m/s
const MAX_STEP := 0.2               # größter Fortschritt zwischen zwei Punkten (Runden); LineRecorder verwirft schon ab 0,2 als „querfeldein“
const PROGRESS_INTERVAL_MS := 250   # Mitspieler: Fortschritt höchstens so oft senden
const STATE_INTERVAL_MS := 200      # Host: Stand höchstens so oft verteilen

var lobby: Node                     # NetLobby (Sitzung, Spielerliste)
var circuit: Circuit                # Strecke der Runde (Prüfung der Linien)
var round_id := 0
var track_hash := ""
var is_host := false
var my_id := 0
var roster: Array = []              # [{id, name, car, color, gone}] in Startreihenfolge (Lobby-Reihenfolge); color = Spielerfarbe
var status := {}                    # Spieler-ID -> {p: 0–100, st: "draw" | "done"}
var phase := "draw"                 # draw (Linien werden gesammelt) | plans (alle Linien verteilt)
var draw_at := 0                    # Host-Uhr (µs): gemeinsamer Zeichenstart
var reveal_at := 0                  # Host-Uhr (µs): Enthüllung aller Linien
var start_at := 0                   # Host-Uhr (µs): gemeinsame Ampel (M5)
var reveal_lead_usec := 800_000     # Host: Enthüllung so lange nach dem Verteilen (Übertragung bei schwachem Hotspot)
var reveal_usec := 3_000_000        # Host: so lange sind alle Linien vor der Ampel zu sehen (wie PassParty.REVEAL_TIME)
var plans := {}                     # Spieler-ID -> Linie (plan_to_data) – erst nach dem Verteilen, vorher nichts von den anderen
var packed_plans: Array = []        # verteilte Linien [{id, plan}] genau wie empfangen (bytegleich bei allen)
var plan_digest := ""
var submitted := false              # eigene Linie abgegeben (und nicht zurückgezogen)
var my_plan: Array = []             # eigene abgegebene Linie (plan_to_data)
var last_reject := ""
var _accepted := {}                 # Host: Spieler-ID -> gepackte, geprüfte Linie
var _progress := 0                  # eigener Fortschritt (%)
var _sent_progress := -1
var _next_progress_ms := 0
var _dirty := false
var _next_state_ms := 0
var _ref_local := 0                 # Rückfall ohne Uhrabgleich: Host-Zeit _ref_host entsprach der eigenen Zeit _ref_local
var _ref_host := 0

func _init(owner_lobby: Node, info: Dictionary, track: Circuit, host_side: bool, start_host_usec: int, now_host_usec: int) -> void:
	lobby = owner_lobby
	circuit = track
	is_host = host_side
	my_id = 1 if host_side else int(owner_lobby.session.my_id)
	round_id = int(info.get("id", 0))
	track_hash = str(info.get("hash", ""))
	draw_at = start_host_usec
	_ref_local = Time.get_ticks_usec()
	_ref_host = now_host_usec
	for p in info.get("players", []):
		roster.append({"id": int(p.id), "name": str(p.name), "car": int(p.car), "color": int(p.get("color", 0)), "gone": false})
		status[int(p.id)] = {"p": 0, "st": "draw"}

# ---------- Uhr ----------
func host_now() -> int:
	# Gemeinsame Uhr (Host-Zeit, µs). Ohne Uhrabgleich (sollte nach der Lobby nie vorkommen): Zeitpunkt der letzten Host-Nachricht.
	if is_host:
		return Time.get_ticks_usec()
	if lobby.session.clock_synced():
		return lobby.session.host_time_usec()
	return Time.get_ticks_usec() - _ref_local + _ref_host

func seconds_until(host_usec: int) -> float:
	return float(host_usec - host_now()) / 1000000.0

# ---------- Abfragen ----------
func ids() -> Array:
	return roster.map(func(e): return int(e.id))

func entry(id: int) -> Dictionary:
	for e in roster:
		if int(e.id) == id:
			return e
	return {}

func others() -> Array:
	return roster.filter(func(e): return int(e.id) != my_id)

func status_of(id: int) -> Dictionary:
	return status.get(id, {"p": 0, "st": "draw"})

func all_done() -> bool:
	return phase == "plans" or roster.all(func(e): return str(status_of(int(e.id)).st) == "done")

func waiting_for() -> Array:
	# Namen derer, die noch zeichnen.
	return roster.filter(func(e): return str(status_of(int(e.id)).st) != "done").map(func(e): return str(e.name))

func state_text(id: int) -> String:
	# Kurzer Stand eines Spielers für die Anzeige („zeichnet … 60 %“, „fertig ✓“, „im Hintergrund“, „ist weg“).
	var e := entry(id)
	if e.is_empty():
		return "fährt nicht mit"
	var st := status_of(id)
	var away: bool = lobby != null and bool(lobby.player(id).get("away", false))
	if bool(e.gone):
		return "ist weg – Linie da"
	if str(st.st) == "done":
		return "fertig ✓"
	if away:
		return "im Hintergrund"
	return "zeichnet … %d %%" % int(st.p)

func party() -> PassParty:
	# Runde als PassParty (M5: entries() fürs Feld, Namen, Farben): Spieler in Startreihenfolge, Linien aus den verteilten Daten.
	var p := PassParty.new()
	var s: Dictionary = lobby.current_round.get("settings", {}) if lobby != null else {}
	p.track_id = str(s.get("track", circuit.id if circuit != null else "azure"))
	p.stage = int(s.get("stage", 0))
	p.ai = int(s.get("ai", 0))
	p.contacts = bool(s.get("contacts", true))
	for e in roster:
		p.players.append({"name": str(e.name), "car": int(e.car), "color": int(e.color)})
	p.start_round()
	for k in range(roster.size()):
		var id := int(roster[k].id)
		if plans.has(id):
			p.routes[k] = LineRecorder.plan_from_data(plans[id])
	return p

func my_slot() -> int:
	return ids().find(my_id)

func gone_ids() -> Array:
	return roster.filter(func(e): return bool(e.gone)).map(func(e): return int(e.id))

# ---------- Eigene Linie ----------
func set_progress(fraction: float) -> void:
	# Eigener Zeichenfortschritt (0–1); gesendet wird gedrosselt in poll().
	var pct := clampi(int(floor(fraction * 100.0 + 0.0001)), 0, 100)
	if submitted:
		pct = 100
	if pct == _progress:
		return
	_progress = pct
	if is_host:
		var st := status_of(my_id)
		if str(st.st) != "done":
			status[my_id] = {"p": pct, "st": "draw"}
			_dirty = true
			changed.emit()

func submit(data: Array) -> String:
	# „Fertig“: Linie abgeben. Rückgabe: Grund, wenn sie schon hier durchfällt; "" = abgegeben (der Host prüft noch einmal).
	if phase != "draw":
		return "Die Linien sind schon verteilt."
	var problem := check_plan(circuit, data)
	if problem != "":
		return problem
	my_plan = data.duplicate(true)
	submitted = true
	last_reject = ""
	_progress = 100
	var packed := pack_plan(data)
	if is_host:
		_accept(my_id, packed)
	else:
		lobby.session.send(1, {"t": "draw_plan", "id": round_id, "hash": track_hash, "plan": packed})
		status[my_id] = {"p": 100, "st": "done"}
		_sent_progress = 100
		changed.emit()
	_log("Linie abgegeben (%d Punkte)" % data.size())
	return ""

func withdraw() -> bool:
	# Abgegebene Linie zurückziehen (neu zeichnen). Geht nur, solange der Host die Linien noch nicht verteilt hat.
	if phase != "draw":
		return false
	var was := submitted
	submitted = false
	my_plan = []
	_progress = 0
	if is_host:
		_accepted.erase(my_id)
		status[my_id] = {"p": 0, "st": "draw"}
		_dirty = true
	else:
		if was:
			lobby.session.send(1, {"t": "draw_withdraw", "id": round_id})
		status[my_id] = {"p": 0, "st": "draw"}
		_sent_progress = 0
	if was:
		_log("Linie zurückgezogen – zeichnet neu")
	changed.emit()
	return true

# ---------- Ablauf ----------
func poll() -> void:
	var now := Time.get_ticks_msec()
	if is_host:
		if _dirty and now >= _next_state_ms and phase == "draw":
			_broadcast_state()
	elif phase == "draw" and not submitted and _progress != _sent_progress and now >= _next_progress_ms:
		_next_progress_ms = now + PROGRESS_INTERVAL_MS
		_sent_progress = _progress
		lobby.session.send(1, {"t": "draw_progress", "id": round_id, "p": _progress})

func on_message(from: int, msg: Dictionary) -> void:
	if NetLobby._int(msg.get("id"), -1) != round_id:
		return
	if is_host:
		_host_message(from, msg)
	elif from == 1:
		_client_message(msg)

func peer_left(id: int) -> void:
	# Host: ein Mitspieler ist weg (abgemeldet oder Verbindung verloren). Mit abgegebener Linie bleibt er in der Runde.
	if not is_host:
		return
	var e := entry(id)
	if e.is_empty():
		return
	if phase == "plans" or _accepted.has(id):
		e.gone = true
		notice.emit("%s ist weg – sein Auto fährt seine Linie ohne Turbo." % e.name)
		_log("%s weg, Linie bleibt in der Runde" % e.name)
	else:
		roster.erase(e)
		status.erase(id)
		notice.emit("%s ist ausgestiegen und fährt nicht mit." % e.name)
		_log("%s ausgestiegen (ohne Linie) – aus der Runde genommen" % e.name)
	if phase == "draw":
		_broadcast_state()
		_check_all()
	changed.emit()

func _host_message(from: int, msg: Dictionary) -> void:
	var e := entry(from)
	if e.is_empty():
		return
	match str(msg.t):
		"draw_progress":
			if phase == "draw" and not _accepted.has(from):
				var pct := clampi(NetLobby._int(msg.get("p"), 0), 0, 100)
				if int(status_of(from).p) != pct:
					status[from] = {"p": pct, "st": "draw"}
					_dirty = true
					changed.emit()
		"draw_plan":
			if phase != "draw":
				return
			var problem := ""
			var data: Array = []
			if str(msg.get("hash", "")) != track_hash:
				problem = "Deine Streckendaten passen nicht zum Gastgeber."
			else:
				data = unpack_plan(msg.get("plan"))
				problem = "Die Linie ist unvollständig angekommen." if data.is_empty() else check_plan(circuit, data)
			if problem != "":
				_log("Linie von %s abgelehnt: %s" % [e.name, problem])
				lobby.session.send(from, {"t": "draw_reject", "id": round_id, "reason": problem})
				return
			_log("Linie von %s angenommen (%d Punkte)" % [e.name, data.size()])
			_accept(from, msg.plan)
		"draw_withdraw":
			if phase == "draw" and _accepted.has(from):
				_accepted.erase(from)
				status[from] = {"p": 0, "st": "draw"}
				_log("%s zeichnet neu" % e.name)
				_broadcast_state()
				changed.emit()

func _accept(id: int, packed: Dictionary) -> void:
	_accepted[id] = packed
	status[id] = {"p": 100, "st": "done"}
	_broadcast_state()
	changed.emit()
	_check_all()

func _check_all() -> void:
	# Host: Sind alle Linien da (auch die der Ausgestiegenen mit Linie), werden sie gemeinsam verteilt.
	if phase != "draw" or roster.is_empty():
		return
	for e in roster:
		if not _accepted.has(int(e.id)):
			return
	var list: Array = []
	for e in roster:
		list.append({"id": int(e.id), "plan": _accepted[int(e.id)]})
	var now := host_now()
	var at := now + reveal_lead_usec
	var msg := {"t": "draw_plans", "id": round_id, "now": now, "at": at, "start": at + reveal_usec, "players": roster.duplicate(true),
		"plans": list, "digest": plans_digest(list)}
	lobby.session.send_all(msg)
	lobby.session.flush()
	_log("Alle Linien da – verteilt (%d, Prüfsumme %s)" % [list.size(), str(msg.digest).left(12)])
	_apply_plans(msg)

func _broadcast_state() -> void:
	_dirty = false
	_next_state_ms = Time.get_ticks_msec() + STATE_INTERVAL_MS
	var list: Array = []
	for e in roster:
		var st := status_of(int(e.id))
		list.append({"id": int(e.id), "name": str(e.name), "car": int(e.car), "color": int(e.color), "gone": bool(e.gone), "p": int(st.p), "st": str(st.st)})
	lobby.session.send_all({"t": "draw_state", "id": round_id, "players": list})

func _client_message(msg: Dictionary) -> void:
	match str(msg.t):
		"draw_state":
			if phase != "draw":
				return
			var list := _clean_roster(msg.get("players"))
			if list.is_empty():
				return
			for old in roster:
				# Hinweise wie beim Host: ausgestiegen (ohne Linie) bzw. weg mit abgegebener Linie.
				var now_entry: Array = list.filter(func(e): return int(e.id) == int(old.id))
				if now_entry.is_empty():
					notice.emit("%s ist ausgestiegen und fährt nicht mit." % old.name)
				elif bool(now_entry[0].gone) and not bool(old.gone):
					notice.emit("%s ist weg – sein Auto fährt seine Linie ohne Turbo." % old.name)
			roster = list.map(func(e): return {"id": e.id, "name": e.name, "car": e.car, "color": e.color, "gone": e.gone})
			status.clear()
			for e in list:
				status[int(e.id)] = {"p": int(e.p), "st": str(e.st)}
			if status.has(my_id):
				# Eigener Stand: der lokale (eine ältere Meldung des Hosts überschriebe sonst kurz „fertig“).
				status[my_id] = {"p": 100, "st": "done"} if submitted else {"p": _progress, "st": "draw"}
			changed.emit()
		"draw_reject":
			if phase != "draw":
				return
			submitted = false
			last_reject = str(msg.get("reason", "Linie nicht angenommen.")).left(200)
			status[my_id] = {"p": _progress, "st": "draw"}
			_sent_progress = -1
			_log("Linie abgelehnt: " + last_reject)
			rejected.emit(last_reject)
			changed.emit()
		"draw_plans":
			if phase != "draw":
				return
			var list = msg.get("plans")
			if not list is Array or not msg.get("digest") is String or plans_digest(list) != str(msg.digest):
				# Kommt bei zuverlässigem ENet praktisch nicht vor; dann lieber sauber gehen als ein anderes Rennen sehen.
				_log("Linien beschädigt angekommen – Prüfsumme passt nicht")
				lobby.close_reason = "Die Linien sind nicht vollständig angekommen. Bitte noch einmal beitreten."
				lobby.session.close_gracefully({"t": "bye"})
				return
			_ref_local = Time.get_ticks_usec()
			_ref_host = NetLobby._int(msg.get("now"), host_now())
			_apply_plans(msg)

func _apply_plans(msg: Dictionary) -> void:
	# Alle Geräte (auch der Host) übernehmen die Linien aus derselben Nachricht: bytegleich.
	var roster_in := _clean_roster(msg.get("players"))
	var list: Array = msg.plans
	var got := {}
	for item in list:
		if item is Dictionary and NetLobby._int(item.get("id"), 0) > 0:
			var data := unpack_plan(item.get("plan"))
			if not data.is_empty():
				got[int(item.id)] = data
	if not roster_in.is_empty():
		roster = roster_in.map(func(e): return {"id": e.id, "name": e.name, "car": e.car, "color": e.color, "gone": e.gone})
	roster = roster.filter(func(e): return got.has(int(e.id)))
	plans = got
	packed_plans = list
	plan_digest = str(msg.get("digest", ""))
	reveal_at = NetLobby._int(msg.get("at"), host_now())
	start_at = NetLobby._int(msg.get("start"), reveal_at + reveal_usec)
	phase = "plans"
	for e in roster:
		status[int(e.id)] = {"p": 100, "st": "done"}
	_log("Linien übernommen: %d, Prüfsumme %s, Enthüllung in %.2f s" % [plans.size(), plan_digest.left(12), seconds_until(reveal_at)])
	plans_ready.emit()
	changed.emit()

func _clean_roster(list) -> Array:
	var out: Array = []
	if not list is Array:
		return out
	for p in list:
		if out.size() >= NetProtocol.MAX_PLAYERS:
			break
		if p is Dictionary and NetLobby._int(p.get("id"), 0) > 0:
			var shown := ProgressStore.clean_name(str(p.get("name", "")))
			var st := str(p.get("st", "draw"))
			out.append({"id": NetLobby._int(p.id, 0), "name": shown if shown != "" else "?", "car": clampi(NetLobby._int(p.get("car"), 0), 0, RaceVehicle.CARS.size() - 1),
				"color": clampi(NetLobby._int(p.get("color"), 0), 0, PlayerColors.count() - 1),
				"gone": NetLobby._bool(p.get("gone")), "p": clampi(NetLobby._int(p.get("p"), 0), 0, 100), "st": st if st in ["draw", "done"] else "draw"})
	return out

func _log(text: String) -> void:
	log_line.emit(text)

# ---------- Linien packen und prüfen (statisch, auch für Tests) ----------
static func pack_plan(data: Array) -> Dictionary:
	# plan_to_data → kompakte Arrays (verlustfrei: x/z stammen aus Vector2 und sind float32).
	var n := data.size()
	var x := PackedFloat32Array()
	var z := PackedFloat32Array()
	var v := PackedFloat64Array()
	var s := PackedFloat64Array()
	var o := PackedFloat64Array()
	var sc := PackedByteArray()
	for arr in [x, z, v, s, o, sc]:
		arr.resize(n)
	for i in range(n):
		var q: Dictionary = data[i]
		x[i] = float(q.x)
		z[i] = float(q.z)
		v[i] = float(q.speed)
		s[i] = float(q.s)
		o[i] = float(q.get("o", 0.0))
		sc[i] = clampi(int(q.get("sc", -1)) + 1, 0, 255)
	return {"n": n, "x": x, "z": z, "v": v, "s": s, "o": o, "sc": sc}

static func unpack_plan(packed) -> Array:
	# Gegenstück zu pack_plan, im Format von plan_to_data (gleiche Schlüssel und Reihenfolge). [] = ungültig aufgebaut.
	if not packed is Dictionary:
		return []
	var d: Dictionary = packed
	if not (d.get("x") is PackedFloat32Array and d.get("z") is PackedFloat32Array and d.get("v") is PackedFloat64Array
			and d.get("s") is PackedFloat64Array and d.get("o") is PackedFloat64Array and d.get("sc") is PackedByteArray):
		return []
	var n: int = (d.x as PackedFloat32Array).size()
	if n < 2 or n > MAX_PLAN_POINTS or NetLobby._int(d.get("n"), -1) != n:
		return []
	for key in ["z", "v", "s", "o", "sc"]:
		if d[key].size() != n:
			return []
	var x: PackedFloat32Array = d.x
	var z: PackedFloat32Array = d.z
	var v: PackedFloat64Array = d.v
	var s: PackedFloat64Array = d.s
	var o: PackedFloat64Array = d.o
	var sc: PackedByteArray = d.sc
	var out: Array = []
	out.resize(n)
	for i in range(n):
		out[i] = {"x": float(x[i]), "z": float(z[i]), "speed": v[i], "s": s[i], "o": o[i], "sc": int(sc[i]) - 1}
	return out

static func plans_digest(list: Array) -> String:
	# Prüfsumme über alle verteilten Linien (wie gesendet); jedes Gerät rechnet sie nach.
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(var_to_bytes(list))
	return ctx.finish().hex_encode()

static func max_points(track: Circuit) -> int:
	return mini(MAX_PLAN_POINTS, int(track.length * track.laps * POINTS_PER_METER) + 500)

static func check_plan(track: Circuit, data: Array) -> String:
	# Plausibel gezeichnet? "" = in Ordnung, sonst ein deutscher Grund. Geprüft wird, was LineRecorder beim Zeichnen sicherstellt:
	# Start am Startpunkt, Fortschritt nur vorwärts und ohne übersprungene Wegpunkte bis ins Ziel, Tempo 5–29 m/s, Seitenlage im
	# Zeichenbereich, bekannte Abkürzungen und Punkte, die zu Streckenanteil und Seitenlage passen.
	var n := data.size()
	if n < 2:
		return "Die Linie ist leer."
	if n > max_points(track):
		return "Die Linie hat zu viele Punkte (%d, höchstens %d)." % [n, max_points(track)]
	var widest := 0.0
	for k in range(64):
		widest = maxf(widest, track.hw(k / 64.0))
	var side_limit := LineRecorder.DRAW_LIMIT - Circuit.HALF_WIDTH + widest + 0.5
	var shortcuts := track.shortcuts.size()
	var prev_s := 0.0
	var prev_sc := -1
	for i in range(n):
		var q = data[i]
		if not q is Dictionary:
			return "Die Linie ist beschädigt."
		for key in ["x", "z", "speed", "s", "o", "sc"]:
			if not (q.get(key) is float or q.get(key) is int):
				return "Die Linie ist beschädigt."
		var x := float(q.x)
		var z := float(q.z)
		var v := float(q.speed)
		var s := float(q.s)
		var o := float(q.o)
		var sc := int(q.sc)
		if not (is_finite(x) and is_finite(z) and is_finite(v) and is_finite(s) and is_finite(o)):
			return "Die Linie enthält ungültige Zahlen."
		if i == 0 and absf(s) > 1e-6:
			return "Die Linie beginnt nicht am Start."
		if s < prev_s - 1e-9:
			return "Die Linie läuft rückwärts."
		if v < SPEED_RANGE.x or v > SPEED_RANGE.y:
			return "Das Tempo der Linie ist unmöglich (%.1f m/s)." % v
		if absf(o) > side_limit:
			return "Die Linie liegt zu weit neben der Strecke."
		if sc < -1 or sc >= shortcuts:
			return "Die Linie nutzt eine unbekannte Abkürzung."
		if i > 0:
			var allowed := MAX_STEP
			for k in [sc, prev_sc]:
				if k >= 0:
					allowed = maxf(allowed, MAX_STEP + absf(float(track.shortcuts[k].to) - float(track.shortcuts[k].from)))
			if s - prev_s > allowed:
				return "Die Linie überspringt Wegpunkte."
		if Vector2(x, z).distance_to(track.place(s, o, sc)) > POSITION_TOLERANCE:
			return "Die Linie passt nicht zur Strecke."
		prev_s = s
		prev_sc = sc
	if absf(prev_s - float(track.laps)) > 1e-6:
		return "Die Linie endet nicht im Ziel."
	return ""
