extends SceneTree

# Gemeinsame Musik im WLAN-Mehrspieler (Nutzerwunsch 04.10.2026; scripts/sound.gd, NetLobby.sync_music): Der Gastgeber führt (Stück,
# Musikstil, Überblendungen, nächstes Stück), Mitspieler spielen dasselbe Stück an derselben Stelle der gemeinsamen Uhr – auch nach
# spätem Beitritt; zur Wertung hören alle dasselbe Stück. Der Gastgeber kann die Musik der Mitspieler für die Sitzung abschalten,
# nach der Sitzung gilt wieder die eigene Einstellung. Die Musik wird ohne Audiogerät nur gerechnet (RaceSound.enable_virtual).
# Erst die Klangseite allein, dann Gastgeber und zwei Mitspieler im selben Prozess über 127.0.0.1 (Testports 24810–24812).
const PORT := 24810
const TEST_OVERRIDES := {"game_port": PORT, "discovery_port": PORT + 1, "beacon_port": PORT + 2, "probe_local": true,
	"use_broadcast": false, "use_binding": false, "log_path": "", "auto_poll": false, "peer_timeout": [32, 600, 1500], "load_timeout": [32, 600, 1500]}
const TRACKS := ["azure", "city", "forest", "harbor", "serra", "fair", "quarry", "arena", "kids"]
var failures := 0
var checks := 0
var lobbies: Array = []
var sounds := {}            # Lobby -> RaceSound

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
	test_sound()
	test_human_won()
	test_session()
	for lb in lobbies:
		if is_instance_valid(lb):
			lb.exit()
			lb.free()
	for s in sounds.values():
		s.free()
	print("RESULT: ", checks - failures, "/", checks, " passed")
	quit(1 if failures else 0)

func make_sound(style: String) -> RaceSound:
	var s := RaceSound.new()
	root.add_child(s)
	s.enable_virtual()
	s.set_style(style)
	return s

func shift(s: RaceSound, seconds: float) -> void:
	# Virtuelles Abspielen um seconds vorspulen (positiv = später im Stück).
	s.started_usec -= int(seconds * 1000000.0)

func gap(a: RaceSound, b: RaceSound) -> float:
	return absf(a.music_position() - b.music_position())

# ---------- Klangseite ----------
func test_sound() -> void:
	var host := make_sound("energie")
	var guest := make_sound("ruhig")
	check(not host.tracks.is_empty() and host.music_active(), "Musikliste ohne Audiogerät geladen (%d Stücke)" % host.tracks.size())
	host.update_music(false, true, 0.016)
	guest.update_music(false, true, 0.016)
	check(str(host.current.set) == "energie" and str(guest.current.set) == "ruhig", "Ohne Sitzung: jeder seine eigene Playlist im eigenen Stil")
	host.set_net_role("lead")
	guest.set_net_role("follow")
	var st := host.music_state()
	check(st.has("file") and st.has("origin") and int(st.n) == host.track_serial, "Gastgeber meldet Stück, Stelle 0 und Einsatz %s" % str(st))
	guest.follow(str(st.file), int(st.origin), float(st.fade))
	check(guest.current.file == host.current.file and gap(host, guest) < 0.01 and guest.sync_log.starts == 1,
		"Mitspieler folgt: gleiches Stück, gleiche Stelle (Abstand %.4f s)" % gap(host, guest))
	check(is_equal_approx(guest.last_crossfade, RaceSound.SYNC_FIRST_FADE), "Erster Einsatz mit weicher Überblendung (%.1f s)" % guest.last_crossfade)
	# Der Mitspieler wechselt nie selbst, auch nicht am Ausklingpunkt; der Gastgeber schon.
	var mix_out := float(guest.current.mix_out)
	shift(host, mix_out - host.music_position() + 0.05)
	shift(guest, mix_out - guest.music_position() + 0.05)
	var before := str(host.current.file)
	guest.update_music(false, true, 0.016)
	check(str(guest.current.file) == before, "Mitspieler bleibt am Ausklingpunkt beim Stück (der Gastgeber bestimmt den Wechsel)")
	host.update_music(false, true, 0.016)
	check(str(host.current.file) != before and str(host.current.set) == "energie", "Gastgeber blendet am Ausklingpunkt ins nächste Stück über")
	st = host.music_state()
	guest.follow(str(st.file), int(st.origin), float(st.fade))
	check(guest.current.file == host.current.file and gap(host, guest) < 0.01 and is_equal_approx(guest.last_crossfade, host.last_crossfade),
		"Neues Stück beim Mitspieler mit der Überblendung des Gastgebers (%.1f s)" % guest.last_crossfade)
	# Nachführen: kleine Abweichung bleibt, große wird nach der Beruhigungszeit ausgeglichen.
	shift(guest, 0.1)
	guest.follow_settle_ms = 0
	guest.follow(str(st.file), int(st.origin), float(st.fade))
	check(guest.sync_log.fixes == 0, "Abweichung 0,1 s: kein Nachführen (Toleranz %.2f s)" % RaceSound.SYNC_TOLERANCE)
	shift(guest, 0.3)
	guest.follow_settle_ms = Time.get_ticks_msec() + 5000
	guest.follow(str(st.file), int(st.origin), float(st.fade))
	check(guest.sync_log.fixes == 0, "Kurz nach einem Einsatz wird nicht nachgeführt")
	guest.follow_settle_ms = 0
	guest.follow(str(st.file), int(st.origin), float(st.fade))
	check(guest.sync_log.fixes == 1 and gap(host, guest) < 0.01 and is_equal_approx(guest.last_crossfade, RaceSound.SYNC_FIX_FADE),
		"Abweichung 0,4 s: nachgeführt mit kurzer Überblendung (Abstand danach %.4f s)" % gap(host, guest))
	# Unbekanntes Stück, Stelle hinter dem Ende: nichts tun.
	var file_now := str(guest.current.file)
	guest.follow("gibt_es_nicht.ogg", int(st.origin), 1.0)
	guest.follow(str(host.tracks[0].file), Time.get_ticks_usec() - int((float(host.tracks[0].duration) + 5.0) * 1000000.0), 1.0)
	check(str(guest.current.file) == file_now, "Unbekanntes Stück und Stelle hinter dem Ende werden übergangen")
	# Wertung: Der Mitspieler wählt nichts selbst, der Gastgeber das gemeinsame Stück.
	guest.set_context("result", false)
	check(str(guest.current.file) == file_now and guest.special == "", "Mitspieler: Wertung startet kein eigenes Sieg-/Niederlage-Stück")
	host.set_context("result", true)
	check(str(host.current.role) == "sieg", "Gastgeber: gemeinsames Stück der Wertung (ein Mensch hat gewonnen → Sieg)")
	st = host.music_state()
	guest.follow(str(st.file), int(st.origin), float(st.fade))
	check(guest.current.file == host.current.file, "Mitspieler hört dasselbe Wertungsstück")
	# Ende der Sitzung: zurück zur eigenen Playlist im eigenen Stil.
	guest.set_context("menu")
	guest.set_net_role("")
	check(str(guest.current.role) == "playlist" and str(guest.current.set) == "ruhig", "Nach der Sitzung: eigene Playlist im eigenen Stil (%s)" % str(guest.current.file))
	var own := str(guest.current.file)
	guest.set_net_role("follow")
	guest.set_net_role("")
	check(str(guest.current.file) == own, "Passendes eigenes Stück läuft nach der Sitzung einfach weiter")
	host.set_net_role("")
	# Ohne Audiogerät und ohne virtual (wie headless im Spiel): Musik bleibt aus, nichts wird gerechnet.
	var plain := RaceSound.new()
	root.add_child(plain)
	plain.follow(str(st.file), int(st.origin), 1.0)
	check(not plain.music_active() and plain.current.is_empty() and plain.music_state().is_empty(), "Headless ohne Rechenmodus: keine Musik")
	plain.free()
	host.free()
	guest.free()

func test_human_won() -> void:
	var f := RaceField.new(Circuit.load_track("azure"))
	f.human_mask.assign([false, true, false])
	var rows := [{"index": 0, "rank": 1, "crashed": false}, {"index": 1, "rank": 2, "crashed": false}, {"index": 2, "rank": 3, "crashed": false}]
	check(not NetRace.human_won(rows, f), "Wertungsmusik: KI vorn → Niederlage-Stück für alle")
	rows[0].index = 1
	rows[1].index = 0
	check(NetRace.human_won(rows, f), "Wertungsmusik: Mensch vorn → Sieg-Stück für alle")
	rows[0]["crashed"] = true
	check(not NetRace.human_won(rows, f), "Wertungsmusik: abgestürzter Erster zählt nicht")
	check(not NetRace.human_won([{"index": 1, "rank": 1, "crashed": false, "in_time": false}], f), "Drift: außerhalb des Zeitlimits zählt nicht")

# ---------- Sitzung ----------
func make(player_name: String, style: String) -> NetLobby:
	var saved: Dictionary = NetLobby.overrides
	NetLobby.overrides = TEST_OVERRIDES
	var lb := NetLobby.new()
	NetLobby.overrides = saved
	lb.tracks = TRACKS.duplicate()
	root.add_child(lb)
	lb.enter(player_name, 0)
	lobbies.append(lb)
	sounds[lb] = make_sound(style)
	return lb

func pump(list: Array, timeout_ms: int, done: Callable) -> bool:
	# Wie main.gd je Bild: Netz abfragen, Musik abgleichen, Musik weiterrechnen.
	var end := Time.get_ticks_msec() + timeout_ms
	var last := Time.get_ticks_usec()
	while Time.get_ticks_msec() < end:
		var now := Time.get_ticks_usec()
		var dt := float(now - last) / 1000000.0
		last = now
		for lb in list:
			if is_instance_valid(lb):
				lb.poll()
				lb.sync_music(sounds[lb])
				sounds[lb].update_music(false, not lb.music_muted(), dt)
		if done.call():
			return true
		OS.delay_msec(4)
	return false

func in_sync(host: NetLobby, guests: Array, tolerance := 0.03) -> bool:
	var h: RaceSound = sounds[host]
	return guests.all(func(g): return sounds[g].current.get("file") == h.current.get("file") and gap(h, sounds[g]) < tolerance)

func music_on(own_setting: bool, lb: NetLobby) -> bool:
	# Wie main.music_on(): eigene Einstellung, im WLAN vom Gastgeber für die Sitzung abschaltbar.
	return own_setting and (lb == null or not lb.music_muted())

func test_session() -> void:
	check(NetProtocol.VERSION == 7, "Protokollversion 7 (gemeinsame Musik)")
	var host := make("Anna", "energie")
	var a := make("Ben", "ruhig")
	check(host.host("azure", 0) == OK, "Spiel eröffnet")
	a.join("127.0.0.1", PORT)
	var ok := pump([host, a], 5000, func(): return a.is_joined and a.session.clock_synced() and in_sync(host, [a]))
	check(ok and sounds[host].net_role == "lead" and sounds[a].net_role == "follow", "Mitspieler folgt dem Gastgeber nach dem Uhrabgleich (Abstand %.4f s)" % gap(sounds[host], sounds[a]))
	check(str(sounds[a].current.set) == "energie", "Der Musikstil des Gastgebers gilt (Mitspieler hat „ruhig“ eingestellt)")
	check(not a.music.is_empty() and a.music.file == host.music.file and absi(int(a.music.origin) - int(host.music.origin)) < 30000,
		"Stück und Stelle 0 (Host-Uhr) kommen an")
	# Neues Stück beim Gastgeber (Ausklingpunkt): kommt sofort, ohne auf den Zustand je Sekunde zu warten.
	var h: RaceSound = sounds[host]
	shift(h, float(h.current.mix_out) - h.music_position() + 0.01)
	var old := str(h.current.file)
	var t0 := Time.get_ticks_msec()
	ok = pump([host, a], 3000, func(): return str(h.current.file) != old and in_sync(host, [a]))
	check(ok and Time.get_ticks_msec() - t0 < 500, "Stückwechsel des Gastgebers ist sofort beim Mitspieler (%d ms)" % (Time.get_ticks_msec() - t0))
	check(is_equal_approx(sounds[a].last_crossfade, h.last_crossfade), "Mit derselben Überblendung (%.1f s)" % sounds[a].last_crossfade)
	# Später Beitritt mitten im Stück
	shift(h, 20.0)
	var b := make("Cem", "energie")
	b.join("127.0.0.1", PORT)
	ok = pump([host, a, b], 5000, func(): return b.is_joined and b.session.clock_synced() and in_sync(host, [a, b]))
	check(ok, "Später Beitritt: gleiches Stück an derselben Stelle (%s bei %.1f s)" % [str(h.current.file), h.music_position()])
	# Mitspieler hing (Laden): Stelle springt nicht mit, er wird nachgeführt.
	shift(sounds[b], -1.0)
	sounds[b].follow_settle_ms = 0
	ok = pump([host, a, b], 2000, func(): return in_sync(host, [a, b]))
	check(ok and sounds[b].sync_log.fixes >= 1, "Nach einem Hänger nachgeführt")
	# Musik bei allen aus/an (Gastgeber, jederzeit, ohne Bereit zurückzusetzen)
	var settings_before: Dictionary = host.settings.duplicate()
	a.set_ready(true)
	pump([host, a, b], 2000, func(): return bool(host.player(a.my_id()).get("ready", false)))
	host.set_guest_music(false)
	ok = pump([host, a, b], 2000, func(): return a.music_muted() and b.music_muted())
	check(ok and host.music_muted() and host.settings == settings_before and bool(host.player(a.my_id()).ready),
		"Gastgeber schaltet die Musik bei allen ab (Einstellungen und Bereit bleiben)")
	check(not music_on(true, a) and not music_on(true, b) and not music_on(true, host), "Bei allen stumm, auch beim Gastgeber")
	ok = pump([host, a, b], 600, func(): return false)
	check(in_sync(host, [a, b]), "Stumm laufen die Mitspieler an derselben Stelle weiter")
	host.set_guest_music(true)
	ok = pump([host, a, b], 2000, func(): return not a.music_muted() and not b.music_muted())
	check(ok and music_on(true, a) and not music_on(false, a), "Wieder an: jeder hat seine eigene Einstellung (an bleibt an, aus bleibt aus)")
	host.set_guest_music(false)
	pump([host, a, b], 2000, func(): return a.music_muted())
	# Verlassen: Stummschaltung weg, eigene Musik
	a.leave()
	pump([host, a, b], 1500, func(): return host.players.size() == 2)
	check(not a.music_muted() and music_on(true, a) and sounds[a].net_role == "" and a.music.is_empty(),
		"Nach dem Verlassen: eigene Einstellung wieder da, eigene Musik")
	check(str(sounds[a].current.set) == "ruhig", "Und wieder im eigenen Stil (%s)" % str(sounds[a].current.file))
	# Wertung: gemeinsames Stück
	h.set_context("result", false)
	sounds[b].set_context("result", true)
	ok = pump([host, b], 2000, func(): return str(h.current.role) == "niederlage" and in_sync(host, [b]))
	check(ok, "Wertung: alle hören dasselbe Stück (%s), nicht jeder sein eigenes" % str(h.current.file))
	# Gastgeber beendet: Mitspieler wieder mit eigener Musik und eigener Einstellung
	host.leave()
	ok = pump([host, b], 3000, func(): return b.mode == "" and sounds[b].net_role == "")
	check(ok and not b.music_muted() and music_on(true, b) and str(sounds[b].current.role) == "playlist", "Gastgeber beendet: Mitspieler zurück bei der eigenen Musik")
	check(host.guest_music and host.music.is_empty(), "Neue Sitzung beginnt ohne Vorgabe (Musik bei allen wieder an)")
