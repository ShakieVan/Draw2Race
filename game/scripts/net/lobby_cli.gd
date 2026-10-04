extends SceneTree

# Lobby- und Renn-Szenario für PC-Läufe mit mehreren Prozessen (tools/net_test.ps1 -Lobby, Meilensteine M3–M5), ohne Oberfläche:
#   Godot --headless --path game --script res://scripts/net/lobby_cli.gd -- --lobbytest=host --lobbytest-expect=3
#   Godot --headless --path game --script res://scripts/net/lobby_cli.gd -- --lobbytest=join            (suchen, dann beitreten)
#   Godot --headless --path game --script res://scripts/net/lobby_cli.gd -- --lobbytest=join:127.0.0.1 --lobbytest-fake=track
# Host: wartet auf N Mitspieler, stellt Stadt / Stufe 3 / KI 3 (wird bei 4 Menschen 0) / ohne Berührungen ein, startet, sobald alle
# bereit sind, wartet aufs gemeinsame Laden. Mitspieler: treten bei, wünschen sich Auto 0 (alle fahren dasselbe Auto) und die Farbe
# --lobbytest-color (alle dieselbe: der Host vergibt eindeutig, belegt → nächste freie), melden sich bereit, sobald die Einstellungen
# da sind, und laden die Strecke. Dann zeichnen alle als Bots (M4): nach dem gemeinsamen Zeichenstart
# Fortschritt in Stufen, danach eine KI-Linie (ai_route, Stärke je Name) abgeben; der Host verteilt alle Linien, jeder prüft, dass
# seine eigene unverändert dabei ist, und meldet die Prüfsumme aller Linien (digest=…; tools/net_test.ps1 vergleicht sie).
# Rennen (M5): Der Host rechnet, alle „zeigen“ es (Marionetten auf die Anzeigezeit, je Bild) und drücken den Turbo nach einem festen
# Plan je Name. Jeder misst, wie ruhig die Anzeige läuft (größter Sprung über die gefahrene Strecke hinaus, Lücken, Weiterrechnen).
# Am Ende meldet jeder die Prüfsumme der Wertung (wertung=…) und der Simulation (sim=…); der Host rechnet das Rennen zusätzlich ohne
# Netz mit RaceField nach (gleiche Linien, gleiche angewandte Turbo-Wechsel) und vergleicht bitgenau (nachgerechnet=ja). Jeder meldet
# die Spielerfarben, wie er sie im Rennen zeigt (farben=ID:Farbe,…; alle Menschen im selben Auto, jede Farbe nur einmal). Danach
# beendet der Host das Spiel; die Mitspieler erwarten die Nachricht „Gastgeber hat beendet“.
# Musik (gemeinsam, Nutzerwunsch 04.10.2026): Jeder Prozess rechnet seine Musik ohne Audiogerät (RaceSound.enable_virtual, eigene
# zufällige Playlist) und gleicht sie wie main.gd über NetLobby.sync_music ab. Der Host schaltet die Musik bei allen (auch bei sich) beim Einstellen
# aus und zum Rennen wieder an, zur Wertung setzt er das gemeinsame Stück (Sieg, wenn ein Mensch gewonnen hat). Jeder meldet Stück und
# Stelle 0 auf der Host-Uhr 2 s nach dem Start und kurz nach der Wertung (musik=Datei@ms;Datei@ms, tools/net_test.ps1 vergleicht);
# Mitspieler müssen „stumm“ gesehen haben und am Ende wieder Musik haben, der Abmelder nach dem Abmelden wieder seiner eigenen folgen.
# --lobbytest-fake=track|version: absichtlich falsche Streckendaten bzw. Spielversion, erwartet wird die Ablehnung. Optionen:
# --lobbytest-name, --lobbytest-timeout (s), --lobbytest-car, --lobbytest-color (Wunschfarbe, Index in PlayerColors), --lobbytest-log, --lobbytest-speed (Zeitraffer des Rennens),
# --lobbytest-drop (Mitspieler: Anteil verworfener Schnappschüsse, z. B. 0.1), --lobbytest-jump (Grenze für Sprünge in m, 0,5),
# --lobbytest-stall (s: Hauptthread hängt so lange beim Laden der Strecke, wie ein langsames Handy – niemand darf herausfliegen),
# --lobbytest-leave (s: Mitspieler meldet sich so lange nach dem Beitritt sauber ab, Ergebnis „abgemeldet“; der Host zählt die
# sauberen Abmeldungen in abgemeldet=…, beim Abmelden darf keine ENet-Fehlermeldung entstehen).
# Ergebniszeile „LOBBYTEST-ERGEBNIS: …“, Exitcode 0 = OK.

const Proto := preload("res://scripts/net/net_protocol.gd")
const TRACKS := ["azure", "city", "forest", "harbor", "serra", "fair", "quarry", "arena", "kids"]
const WANT := {"track": "city", "stage": 2, "ai": 0, "contacts": false}

var opt := {}
var lobby: NetLobby
var start_ms := 0
var configured := false
var ready_seen := {}
var ready_ms := -1
var done := false
var me_seen := {}
var circuit: Circuit
var bot_step := -1                 # Zeichen-Bot: nächste Stufe (0–3 Fortschritt, 4 = abgeben), -1 = noch nicht gestartet
var bot_next_us := 0
var plans_seen := {}               # {digest, count, own_ok, start_at}
var race: NetRace
var presses: Array = []            # Turbo-Plan: [[an ab s, aus ab s], …] (Rennzeit)
var press_k := 0
var pressed := false
var last_view := {}                # je Auto: [Anzeigetakt, Lage]
var worst_jump := 0.0
var worst_at := ""
var frames := 0
var final_ms := -1
var joined_ms := -1
var signed_off := 0                # Host: sauber abgemeldete Mitspieler
var sound: RaceSound               # Musik ohne Audiogerät (nur gerechnet), abgeglichen wie in main.gd
var music_samples: Array = []      # ["Datei@Stelle-0-auf-der-Host-Uhr-in-ms", …] (2 s nach dem Start, nach der Wertung)
var muted_seen := false            # Mitspieler: Musik war vom Gastgeber abgeschaltet
var muted_end := true              # Mitspieler: beim letzten Messpunkt noch abgeschaltet?

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var key := arg.get_slice("=", 0)
		var value := arg.substr(key.length() + 1) if "=" in arg else ""
		opt[key.trim_prefix("--lobbytest").trim_prefix("-")] = value
	if not opt.has(""):
		_finish(false, "kein --lobbytest=host|join[:adresse] angegeben")
		return
	Engine.max_fps = 120           # wie ein Handy (sonst dreht jeder Prozess Leerlauf mit tausenden Bildern je Sekunde)
	start_ms = Time.get_ticks_msec()
	NetLobby.overrides = {"log_path": str(opt.get("log", "")), "race_speed": float(opt.get("speed", "1")),
		"snapshot_drop": float(opt.get("drop", "0"))}   # Protokoll nur auf Wunsch (Zeilen stehen ohnehin in der Ausgabe)
	lobby = NetLobby.new()
	NetLobby.overrides = {}
	lobby.tracks = TRACKS.duplicate()
	root.add_child(lobby)
	sound = RaceSound.new()
	root.add_child(sound)
	sound.enable_virtual()
	lobby.log_line.connect(func(t): print(t))
	lobby.round_started.connect(_on_started)
	lobby.round_ready.connect(_on_ready)
	lobby.race_ready.connect(_on_race)
	lobby.failed.connect(_on_failed)
	lobby.closed.connect(_on_closed)
	lobby.joined.connect(func():
		joined_ms = Time.get_ticks_msec()
		lobby.set_car(int(opt.get("car", "0")))
		if opt.has("color"):
			lobby.set_color(int(opt.color)))
	lobby.session.peer_left.connect(func(_id, reason):
		if reason == "abgemeldet":
			signed_off += 1)
	lobby.enter(str(opt.get("name", "PC")), int(opt.get("car", "0")))
	var fake := str(opt.get("fake", ""))
	if fake == "track":
		lobby.hello_override = {"track": "falsch"}
	elif fake == "version":
		lobby.hello_override = {"game": "0.0.1"}
	var mode := str(opt[""])
	if mode == "host":
		if lobby.host("azure", 0) != OK:
			_finish(false, "host: " + lobby.session.detail)
	elif mode.begins_with("join:"):
		var target := Proto.parse_address(mode.substr(5))
		if target.is_empty():
			_finish(false, "ungültige Adresse " + mode.substr(5))
		else:
			lobby.join(str(target.address), int(target.port))
	elif mode == "join":
		lobby.search()
	else:
		_finish(false, "unbekannter Modus " + mode)

func _process(delta: float) -> bool:
	if done or lobby == null:
		return false
	_bot_tick()
	_race_tick()
	_music_tick(delta)
	var elapsed := (Time.get_ticks_msec() - start_ms) / 1000.0
	if elapsed > float(opt.get("timeout", "40")):
		_finish(false, "Zeitgrenze (Modus %s, Phase %s, Spieler %d, Rennen %s)" % [lobby.mode, lobby.phase, lobby.players.size(),
			("Takt %d, Phase %s, Wertung %d" % [race.tick, race.phase, race.rows.size()]) if race != null else "–"])
		return false
	if lobby.is_host():
		_host_tick()
	elif lobby.mode == "search":
		var games := lobby.games()
		if games.size() > 0 and games[0].compatible:
			print("Gefunden: %s %s:%d über %s" % [games[0].name, games[0].address, games[0].port, lobby.discovery.via_text(games[0])])
			lobby.join(str(games[0].address), int(games[0].port))
	elif lobby.mode == "join" and lobby.is_joined and opt.has("leave"):
		if Time.get_ticks_msec() - joined_ms > int(float(opt.leave) * 1000.0):
			_sign_off()
	elif lobby.mode == "join" and lobby.is_joined and lobby.phase == "lobby":
		if lobby.settings == WANT and not bool(lobby.me().get("ready", false)):
			lobby.set_ready(true)
	return false

func _sign_off() -> void:
	# Wie „Verlassen“ in der Lobby: bye, dann sauber trennen (leave() setzt den Modus sofort zurück, darum nur einmal).
	var who: String = str(lobby.me().get("name", "?"))
	var role := sound.net_role
	lobby.leave()
	await create_timer(1.0).timeout
	# Nach dem Abmelden wieder die eigene Musik (Rolle „“), keine Stummschaltung mehr.
	var music_ok := role == "follow" and sound.net_role == "" and not lobby.music_muted()
	_finish(lobby.session.enet == null and music_ok, "abgemeldet als %s, Musik %s → %s" % [who, role, sound.net_role if sound.net_role != "" else "eigene"])

func _host_tick() -> void:
	var expect := int(opt.get("expect", "3"))
	if not configured and lobby.client_count() >= expect:
		configured = true
		lobby.set_track(WANT.track)
		lobby.set_stage(WANT.stage)
		lobby.set_ai(3)
		lobby.set_contacts(WANT.contacts)
		lobby.set_guest_music(false)       # Musik bei allen aus (zum Rennen wieder an)
	if configured and lobby.phase == "lobby" and lobby.start_problem() == "" and plans_seen.is_empty():
		lobby.start_round()
	if race != null and race.final and final_ms > 0 and Time.get_ticks_msec() - final_ms > 1000 and lobby.mode == "host":
		# Rennen fertig und bei allen angezeigt: nachrechnen, melden, Spiel beenden.
		var cars := {}
		var colors := {}
		var names := {}
		for p in lobby.players:
			cars[p.car] = true
			colors[p.color] = true
			names[p.name] = true
		var check := _replay()
		# Autowahl: alle im selben Auto, jede Spielerfarbe nur einmal (in der Lobby und im Rennen).
		var ok: bool = lobby.players.size() == expect + 1 and cars.size() == 1 and colors.size() == lobby.players.size() and _colors_ok() \
			and names.size() == lobby.players.size() and lobby.settings == WANT \
			and int(plans_seen.get("count", 0)) == expect + 1 and bool(plans_seen.get("own_ok", false)) and bool(check.ok) and _smooth_ok()
		var s: Dictionary = race.stats
		var seconds := float(race.tick) / 60.0
		print("SCHNAPPSCHUSS: %d gesendet in %.1f s Rennzeit (%.1f je s), im Mittel %d Byte, höchstens %d Byte, %d Ereignis-Nachrichten, Turbo-Meldungen %d, davon zu spät %d" % [
			int(s.snaps), seconds, float(s.snaps) / maxf(seconds, 0.001), int(s.snap_bytes) / maxi(1, int(s.snaps)), int(s.snap_max), int(s.event_msgs), int(s.inputs), int(s.late)])
		var text := "host abgemeldet=%d spieler=%d autos=%s farben=%s namen=%s einstellungen=%s linien=%d digest=%s takte=%d wertung=%s sim=%s nachgerechnet=%s turbo=%d %s" % [signed_off,
			lobby.players.size(), str(lobby.players.map(func(p): return p.car)), _colors_text(), str(lobby.players.map(func(p): return p.name)), JSON.stringify(lobby.settings),
			int(plans_seen.get("count", 0)), str(plans_seen.get("digest", "")).left(16), race.tick, _rows_hash(), str(race.final_info.digest).left(16),
			"ja" if check.ok else "NEIN (%s)" % check.why, _turbo_changes(), _smooth_text()] + " musik=" + ";".join(music_samples)
		ok = ok and music_samples.size() == 2
		plans_seen = {}
		race = null
		lobby.leave()
		await create_timer(1.0).timeout
		_finish(ok, text)

func _replay() -> Dictionary:
	# Dasselbe Rennen ohne Netz mit RaceField: frische Strecke, Teilnehmerliste der Runde, angewandte Turbo-Wechsel, gleiche Phasen.
	var info: Dictionary = race.final_info
	var f := NetRace.replay(Circuit.load_track(race.track.id), race.entries, race.contacts, race.grip, info.turbo, int(info.ticks), race.result_tick)
	var same := NetRace.sim_digest(f) == str(info.digest) and NetRace.sim_digest(race.sim) == str(info.digest)
	var times := true
	for i in range(f.cars.size()):
		if f.cars[i].finish_time != race.sim.cars[i].finish_time:
			times = false
	return {"ok": same and times, "why": "Prüfsumme" if not same else "Zielzeiten"}

func _colors_text() -> String:
	# Spielerfarben, wie dieses Gerät sie im Rennen zeigt (Spieler-ID:Farbe in Startreihenfolge) – bei allen Geräten gleich?
	if race == null:
		return "-"
	var parts: Array = []
	for e in race.view.entries:
		if bool(e.human):
			parts.append("%d:%s" % [int(e.get("peer", 0)), (e.paint as Color).to_html(false) if e.has("paint") else "?"])
	return ",".join(parts)

func _colors_ok() -> bool:
	# Alle Menschen im selben Auto, jeder in einer eigenen Farbe aus der Palette, Lack = Farbe der Runde (Spielerliste).
	if race == null:
		return false
	var paints := {}
	var cars := {}
	var humans := 0
	for e in race.view.entries:
		if not bool(e.human):
			continue
		humans += 1
		cars[int(e.car)] = true
		var shown: Color = e.get("paint", Color(0, 0, 0, 0))
		var listed: Dictionary = race.draw.entry(int(e.get("peer", 0)))
		if listed.is_empty() or shown != PlayerColors.color(int(listed.color)):
			return false
		paints[shown.to_html(false)] = true
	return humans >= 2 and paints.size() == humans and cars.size() == 1

func _turbo_changes() -> int:
	var n := 0
	for changes in race.final_info.get("turbo", []):
		n += (changes as Array).size()
	return n

func _rows_hash() -> String:
	# Wertung so, wie sie ankam (Index, Platz, Zeit/Punkte, Zustand) – bei allen Geräten gleich?
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(var_to_bytes(race.rows))
	return ctx.finish().hex_encode().left(16)

func _on_started(info: Dictionary) -> void:
	# Wie main.gd: Strecke laden, Prüfsumme melden.
	circuit = Circuit.load_track(str(info.settings.track))
	var stall := float(opt.get("stall", "0"))
	if stall > 0.0:
		# Langsames Handy: Der Hauptthread steht beim Laden (Strecke, Welt), ENet wird so lange nicht abgefragt.
		print("HÄNGER: %.1f s beim Laden" % stall)
		OS.delay_msec(int(stall * 1000.0))
	lobby.report_loaded(circuit.file_hash, circuit)

func _on_ready(info: Dictionary) -> void:
	ready_seen = info
	me_seen = lobby.me().duplicate()
	ready_ms = Time.get_ticks_msec()
	print("RUNDE BEREIT ", JSON.stringify(info))
	lobby.draw.plans_ready.connect(_on_plans)
	bot_step = 0
	bot_next_us = int(lobby.draw.draw_at)

func _bot_tick() -> void:
	# Zeichen-Bot: ab dem gemeinsamen Zeichenstart in vier Stufen „zeichnen“, dann die KI-Linie abgeben (Wartezeit je Name verschieden).
	var d: NetDraw = lobby.draw
	if d == null or bot_step < 0 or bot_step > 4 or d.host_now() < bot_next_us:
		return
	if bot_step == 0:
		print("ZEICHENSTART (Abweichung zur Host-Uhr %.1f ms)" % (float(d.host_now() - d.draw_at) / 1000.0))
	if bot_step < 4:
		d.set_progress(0.25 * bot_step)
	else:
		var problem := d.submit(LineRecorder.plan_to_data(circuit.ai_route(_skill(), 0.0)))
		print("LINIE ABGEGEBEN %s" % ("ok" if problem == "" else problem))
	bot_step += 1
	bot_next_us = d.host_now() + 150_000 + (absi(str(opt.get("name", "PC")).hash()) % 400) * 1000

func _skill() -> float:
	return 0.5 + float(absi(str(opt.get("name", "PC")).hash()) % 30) / 10.0

func _on_plans() -> void:
	var d: NetDraw = lobby.draw
	var own: Array = LineRecorder.plan_to_data(circuit.ai_route(_skill(), 0.0))
	plans_seen = {"digest": d.plan_digest, "count": d.plans.size(), "start_at": d.start_at,
		"own_ok": var_to_bytes(d.plans.get(d.my_id, [])) == var_to_bytes(own)}
	print("LINIEN DA: %d, Prüfsumme %s, eigene unverändert: %s, Enthüllung in %.0f ms" % [d.plans.size(), d.plan_digest.left(16),
		"ja" if plans_seen.own_ok else "NEIN", d.seconds_until(d.reveal_at) * 1000.0])

# ---------- Rennen (M5) ----------
func _on_race() -> void:
	race = lobby.race
	race.results_changed.connect(func():
		if race != null and race.final and final_ms < 0:
			final_ms = Time.get_ticks_msec()
			print("WERTUNG ENDGÜLTIG: %s" % JSON.stringify(race.rows)))
	# Turbo-Plan je Name: drei Stöße zu verschiedenen Zeiten (Rennzeit), damit sich die Wechsel der Spieler überlappen.
	var h := absi(str(opt.get("name", "PC")).hash())
	var base := 1.0 + float(h % 7) * 0.31
	presses = [[base, base + 1.2], [base + 5.0, base + 5.8], [base + 11.0, base + 12.5]]
	if lobby.is_host():
		lobby.set_guest_music(true)
	press_k = 0
	pressed = false
	print("RENNEN ANGELEGT: %d Autos, mein Auto %d, Start in %.2f s, Turbo-Plan %s" % [race.view.cars.size(), race.my_index, race.seconds_until_go(), str(presses)])

func _race_tick() -> void:
	if race == null or lobby.race != race:
		return
	# Turbo nach Plan (wie ein Finger auf dem Knopf)
	var now := race.race_seconds()
	if press_k < presses.size():
		var p: Array = presses[press_k]
		if not pressed and now >= float(p[0]):
			pressed = true
			race.set_turbo(true)
		elif pressed and now >= float(p[1]):
			pressed = false
			race.set_turbo(false)
			press_k += 1
	# Anzeige wie main.gd: Marionetten auf die Anzeigezeit, Ereignisse abholen; Sprünge messen.
	var t := race.display_ticks()
	race.apply_view(t)
	race.take_events(t)
	if t <= 0.0:
		return
	frames += 1
	for i in range(race.view.cars.size()):
		var v: RaceVehicle = race.view.cars[i]
		if last_view.has(i):
			var last: Array = last_view[i]
			var dt := (t - float(last[0])) / 60.0
			if dt > 0.0 and not v.crashed and v.finish_time < 0.0 and not v.in_loop and not bool(last[3]):
				var reach := maxf(v.velocity.length(), float(last[2])) * dt + 0.05
				var jump := v.pos.distance_to(last[1]) - reach
				if jump > worst_jump:
					worst_jump = jump
					worst_at = "Auto %d bei Takt %.1f" % [i, t]
		last_view[i] = [t, v.pos, v.velocity.length(), v.crashed or v.finish_time >= 0.0 or v.in_loop]

func _music_tick(delta: float) -> void:
	# Wie main.gd je Bild: Gastgeber führt, Mitspieler folgen; Wertung: gemeinsames Stück vom Gastgeber. Messpunkte auf der Host-Uhr.
	lobby.sync_music(sound)
	sound.update_music(false, not lobby.music_muted(), delta)
	if lobby.music_muted():
		muted_seen = true
	if race == null or lobby.race != race:
		return
	if final_ms > 0 and sound.context != "result":
		sound.set_context("result", NetRace.human_won(race.rows, race.view))
	var due := music_samples.size() == 0 and race.race_seconds() >= 2.0 or music_samples.size() == 1 and final_ms > 0 and Time.get_ticks_msec() - final_ms >= 700
	if due:
		var state := sound.music_state()
		var to_host := lobby.session.host_time_usec() - Time.get_ticks_usec()
		music_samples.append("%s@%d" % [str(state.get("file", "-")), int((int(state.get("origin", 0)) + to_host) / 1000)])
		muted_end = lobby.music_muted()
		print("MUSIK %d: %s (Stelle %.2f s%s)" % [music_samples.size(), music_samples[-1], sound.music_position(), ", stumm" if muted_end else ""])

func _smooth_ok() -> bool:
	return worst_jump <= float(opt.get("jump", "0.5"))

func _smooth_text() -> String:
	var s: Dictionary = race.stats if race != null else {}
	return "anzeige=%d bilder, sprung=%.3f m%s, schnappschüsse=%d empfangen, %d verworfen (Testverlust), größte Lücke %d Takte, weitergerechnet %d, angehalten %d" % [
		frames, worst_jump, (" (" + worst_at + ")") if worst_at != "" else "", int(s.get("received", 0)), int(s.get("dropped", 0)), int(s.get("max_gap", 0)),
		int(s.get("extrapolated", 0)), int(s.get("held", 0))]

func _on_failed(reason: String) -> void:
	var fake := str(opt.get("fake", ""))
	var expected := (fake == "track" and reason.contains("Streckendaten")) or (fake == "version" and reason.contains("Andere Spielversion"))
	_finish(expected, "join abgelehnt%s: %s" % [" (erwartet)" if expected else "", reason])

func _on_closed(reason: String) -> void:
	var final_ok := race != null and race.final and not race.rows.is_empty()
	var ok := not ready_seen.is_empty() and reason.contains("beendet") and JSON.stringify(ready_seen.settings) == JSON.stringify(WANT) and str(opt.get("fake", "")) == "" \
		and not plans_seen.is_empty() and bool(plans_seen.own_ok) and final_ok and _smooth_ok() and _colors_ok() \
		and music_samples.size() == 2 and muted_seen and not muted_end
	var dropped: int = int(race.stats.dropped) if race != null else 0
	if float(opt.get("drop", "0")) > 0.0 and dropped == 0:
		ok = false
	_finish(ok, "join runde=%s auto=%s farben=%s name=%s linien=%d digest=%s wertung=%s sim=%s %s, Ende: %s" % [JSON.stringify(ready_seen.get("settings", {})), str(me_seen.get("car", "?")),
		_colors_text(), str(me_seen.get("name", "?")), int(plans_seen.get("count", 0)), str(plans_seen.get("digest", "")).left(16),
		_rows_hash() if final_ok else "-", str(race.final_info.get("digest", "")).left(16) if final_ok else "-", _smooth_text(), reason]
		+ " musik=%s stumm=%s/%s" % [";".join(music_samples), "gesehen" if muted_seen else "nie", "noch" if muted_end else "aufgehoben"])

func _finish(ok: bool, text: String) -> void:
	if done:
		return
	done = true
	print("LOBBYTEST-ERGEBNIS: %s %s" % ["OK" if ok else "FEHLER", text])
	if lobby != null:
		lobby.exit()
	await create_timer(0.3).timeout
	quit(0 if ok else 1)
