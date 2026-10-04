extends SceneTree

# Neuere Version weitergeben (Nutzerwunsch 04.10.2026, scripts/net/net_apk.gd, scripts/apk_share.gd): Regeln (wer wem anbietet, nie ein
# Downgrade), Ablehnungsformat (ältere Versionen lesen den Grund unverändert), Anmeldung fremder Protokollversion, Übertragung im
# selben Prozess über 127.0.0.1 (Prüfsumme, Fortschritt, Warten auf die Vorbereitung, Abbruch, verfälschte Datei, falsche Größe,
# fremde Datei, keine Gegenseite, Hauptthread ohne Hänger) und der Ablauf in der Lobby in beiden Richtungen (Testports 24800–24806).
const PORT := 24800
const APK_PORT := 24803
const GUEST_APK_PORT := 24804
const RAW_PORT := 24805
const TEST_OVERRIDES := {"game_port": PORT, "discovery_port": PORT + 1, "beacon_port": PORT + 2, "probe_local": true,
	"use_broadcast": false, "use_binding": false, "log_path": "", "auto_poll": false, "peer_timeout": [32, 600, 1500], "load_timeout": [32, 600, 1500]}
const DIR := "user://apktest/suite"
const SHA_A := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
var failures := 0
var checks := 0

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
	test_format()
	var src := make_file(DIR + "/quelle.bin", 24)
	test_transfer(src)
	test_lobby_flow(src)
	_clean(DIR)
	print("RESULT: ", checks - failures, "/", checks, " passed")
	quit(1 if failures else 0)

# ---------- Hilfen ----------
func make_file(path: String, mb: int) -> Dictionary:
	# Zufallsdatei (mb MiB) und ihre Prüfsumme.
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var crypto := Crypto.new()
	for i in range(mb):
		var chunk := crypto.generate_random_bytes(1048576)
		f.store_buffer(chunk)
		ctx.update(chunk)
	f.close()
	return {"path": path, "size": mb * 1048576, "sha256": ctx.finish().hex_encode()}

func file_sha(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	while f.get_position() < f.get_length():
		ctx.update(f.get_buffer(1 << 20))
	return ctx.finish().hex_encode()

func _clean(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for name in dir.get_files():
		dir.remove(name)
	for sub in dir.get_directories():
		_clean(dir_path + "/" + sub)
		dir.remove(sub)

var worst_ms := 0.0
func pump(objs: Array, timeout_ms: int, done: Callable) -> bool:
	# Wie ein Bildtakt: alle abfragen, die Dauer jeder Runde (Hauptthread-Arbeit) messen.
	var end := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < end:
		var t0 := Time.get_ticks_usec()
		for o in objs:
			if is_instance_valid(o):
				o.poll()
		worst_ms = maxf(worst_ms, (Time.get_ticks_usec() - t0) / 1000.0)
		if done.call():
			return true
		OS.delay_msec(4)
	return false

# ---------- Regeln ----------
func test_rules() -> void:
	check(NetApk.newer("0.2.33", "0.2.32") and NetApk.newer("0.10.0", "0.9.9") and not NetApk.newer("0.2.32", "0.2.32")
		and not NetApk.newer("0.2.31", "0.2.32") and not NetApk.newer("?", "0.2.32") and not NetApk.newer("0.2.33", ""), "Versionen: nur echt höher gilt als neuer")
	var offer := {"size": 3000, "sha256": SHA_A, "port": 24683}
	check(NetApk.clean_offer({"size": 3000.0, "sha256": SHA_A.to_upper(), "port": 24683.0}) == offer, "Angebot aus JSON (Zahlen als float, Prüfsumme groß) wird bereinigt")
	for bad in [{"size": 0, "sha256": SHA_A, "port": 1}, {"size": NetApk.MAX_BYTES + 1, "sha256": SHA_A, "port": 1}, {"size": 5, "sha256": "xyz", "port": 1},
			{"size": 5, "sha256": SHA_A, "port": 0}, {"size": "5", "sha256": SHA_A, "port": 1}, "kein Angebot"]:
		check(NetApk.clean_offer(bad).is_empty(), "Ungültiges Angebot verworfen: %s" % str(bad).left(60))
	# Gastgeber neuer: Angebot an den Mitspieler, eigene Datei bereitstellen
	var d := NetApk.host_decision("game", "0.2.33", {"game": "0.2.32", "name": "Ben"}, offer, true)
	check(d.extra.game == "0.2.33" and d.extra.apk == offer and d.serve and d.offer.is_empty() and not d.extra.has("pull"), "Gastgeber neuer: Ablehnung mit Angebot, Datei bereitstellen")
	d = NetApk.host_decision("protocol", "0.2.33", {"game": "0.2.31"}, offer, false)
	check(d.extra.has("apk") and d.serve, "Gastgeber neuer, anderes Protokoll: ebenfalls Angebot")
	d = NetApk.host_decision("game", "0.2.33", {"game": "0.2.32"}, {}, true)
	check(d.extra == {"game": "0.2.33"} and not d.serve, "Gastgeber neuer ohne fertige Prüfsumme: kein Angebot, nur seine Version")
	# Mitspieler neuer: der Gastgeber darf holen
	d = NetApk.host_decision("game", "0.2.32", {"game": "0.2.33", "name": "Ben", "apk": offer}, offer, true)
	check(d.extra.get("pull") == true and not d.extra.has("apk") and not d.serve and d.offer.version == "0.2.33" and d.offer.name == "Ben"
		and d.offer.sha256 == SHA_A and d.offer.port == 24683, "Mitspieler neuer: Gastgeber bekommt das Angebot (pull), bietet selbst nichts an")
	d = NetApk.host_decision("game", "0.2.32", {"game": "0.2.33", "apk": offer}, offer, false)
	check(not d.extra.has("pull") and d.offer.is_empty(), "Gastgeber ohne Installationsmöglichkeit (PC): kein Holen")
	d = NetApk.host_decision("game", "0.2.32", {"game": "0.2.33"}, offer, true)
	check(not d.extra.has("pull") and d.offer.is_empty(), "Mitspieler neuer ohne Angebot: nichts zu holen")
	# Kein Downgrade, nur bei anderer Spielversion
	d = NetApk.host_decision("game", "0.2.33", {"game": "0.2.32", "apk": offer}, {}, true)
	check(d.offer.is_empty() and not d.extra.has("pull"), "Kein Downgrade: die ältere APK des Mitspielers wird dem Gastgeber nie angeboten")
	for code in ["full", "busy", "track", "physics", "bad", "kick"]:
		d = NetApk.host_decision(code, "0.2.33", {"game": "0.2.32", "apk": offer}, offer, true)
		check(d.extra.is_empty() and not d.serve and d.offer.is_empty(), "Ablehnung „%s“: kein Zusatz, kein Angebot" % code)
	d = NetApk.host_decision("game", "0.2.32", {"game": "0.2.32", "apk": offer}, offer, true)
	check(not d.extra.has("apk") and not d.extra.has("pull") and d.offer.is_empty(), "Gleiche Version: nichts anzubieten")
	# Mitspieler nach der Ablehnung
	var g := NetApk.guest_decision("game", "0.2.32", {"game": "0.2.33", "name": "Anna", "apk": offer}, true, true)
	check(g.offer.version == "0.2.33" and g.offer.name == "Anna" and g.offer.size == 3000 and not g.serve and g.host_version == "0.2.33",
		"Mitspieler älter: Angebot vom Gastgeber")
	g = NetApk.guest_decision("game", "0.2.32", {"game": "0.2.33", "apk": offer}, true, false)
	check(g.offer.is_empty(), "Mitspieler ohne Installationsmöglichkeit (PC): kein Angebot")
	g = NetApk.guest_decision("game", "0.2.34", {"game": "0.2.33", "name": "Anna", "apk": offer}, true, true)
	check(g.offer.is_empty() and not g.serve, "Kein Downgrade: das Angebot des älteren Gastgebers wird nie angenommen")
	g = NetApk.guest_decision("game", "0.2.34", {"game": "0.2.33", "name": "Anna", "pull": true}, true, true)
	check(g.serve and g.offer.is_empty() and g.host_name == "Anna", "Mitspieler neuer und Gastgeber holt: eigene Datei bereitstellen")
	g = NetApk.guest_decision("game", "0.2.34", {"game": "0.2.33", "pull": true}, false, true)
	check(not g.serve, "Ohne eigene APK (PC): nichts bereitstellen")
	g = NetApk.guest_decision("game", "0.2.34", {"game": "0.2.33"}, true, true)
	check(not g.serve, "Gastgeber holt nicht (kein pull): nichts bereitstellen")
	g = NetApk.guest_decision("track", "0.2.32", {"game": "0.2.33", "apk": offer}, true, true)
	check(g.offer.is_empty() and not g.serve, "Andere Ablehnung (Streckendaten): kein Angebot")
	g = NetApk.guest_decision("game", "0.2.32", {}, true, true)
	check(g.offer.is_empty() and g.host_version == "", "Ablehnung eines älteren Gastgebers ohne Zusatz: nichts")
	check(NetApk.progress_text({"received": 120 * 1048576, "size": 310 * 1048576, "eta": 11.2}) == "120 von 310 MB · noch 12 s"
		and NetApk.progress_text({"received": 0, "size": 310 * 1048576, "eta": 200.0}) == "0.0 von 310 MB · noch 4 min", "Fortschrittstext mit MB und Restzeit")

# ---------- Format der Ablehnung und Anmeldung ----------
func old_decode(bytes: PackedByteArray) -> Dictionary:
	# Lesart bis 0.2.31 (NetProtocol.decode, Versionsbyte 0) – unverändert übernommen.
	var text := bytes.slice(3).get_string_from_utf8()
	var cut := text.find("\n")
	return {"t": "reject", "code": text.left(cut) if cut >= 0 else "", "reason": text.substr(cut + 1) if cut >= 0 else text}

func test_format() -> void:
	var reason := "Andere Spielversion: Host 0.2.33, dein Gerät 0.2.32. Bitte beide Geräte auf dieselbe Version aktualisieren."
	var extra := {"game": "0.2.33", "name": "Anna", "apk": {"size": 325000000, "sha256": SHA_A, "port": 24683}}
	var bytes := NetProtocol.encode_reject("game", reason, extra)
	var msg := NetProtocol.decode(bytes)
	check(msg.t == "reject" and msg.code == "game" and msg.reason == reason and NetApk.clean_offer(msg.x.get("apk")).size == 325000000
		and msg.x.game == "0.2.33" and msg.x.name == "Anna", "Ablehnung mit Zusatz: Grund und Angebot kommen an")
	var old := old_decode(bytes)
	check(old.code == "game" and old.reason == reason, "Ältere Version (bis 0.2.31) liest denselben Grund ohne Zusatz-Müll: „%s“" % old.reason.left(40))
	var plain := NetProtocol.encode_reject("full", "Das Spiel ist voll.")
	check(old_decode(plain).reason == "Das Spiel ist voll." and NetProtocol.decode(plain).x == {} and not 0 in plain.slice(3),
		"Ohne Zusatz: Format wie bisher (kein Nullbyte)")
	var junk := NetProtocol.encode_reject("game", reason)
	junk.append(0)
	junk.append_array("kein json".to_utf8_buffer())
	check(NetProtocol.decode(junk).x == {} and NetProtocol.decode(junk).reason == reason, "Kaputter Zusatz wird ignoriert")
	# Anmeldung einer künftigen Protokollversion: Spielversion, Name und Angebot bleiben lesbar
	var hello := NetProtocol.make_hello("Ben")
	hello.game = "0.3.0"
	hello["apk"] = extra.apk
	var future := PackedByteArray([NetProtocol.MAGIC_0, NetProtocol.MAGIC_1, NetProtocol.VERSION + 1])
	future.append_array(var_to_bytes(hello))
	var f := NetProtocol.decode(future)
	check(f.t == "_foreign" and f.proto == NetProtocol.VERSION + 1 and f.game == "0.3.0" and f.name == "Ben" and NetApk.clean_offer(f.get("apk")).size == 325000000,
		"Anmeldung fremder Protokollversion: Spielversion, Name und Angebot lesbar")
	var problem := NetProtocol.check_hello(f, {"game": "0.2.32", "physics": NetProtocol.physics_version(), "track": ""})
	check(problem.code == "protocol" and NetApk.host_decision(problem.code, "0.2.32", f, {}, true).offer.version == "0.3.0",
		"Fremdes Protokoll: Ablehnung „protocol“, der Gastgeber darf die neuere Version holen")
	var other := PackedByteArray([NetProtocol.MAGIC_0, NetProtocol.MAGIC_1, NetProtocol.VERSION + 1])
	other.append_array(var_to_bytes({"t": "race_snap", "game": "9.9.9"}))
	check(not NetProtocol.decode(other).has("game"), "Andere Nachrichten fremder Version: nichts gelesen")

# ---------- Übertragung ----------
func test_transfer(src: Dictionary) -> void:
	var server := NetApk.new()
	check(server.serve(RAW_PORT) == OK and server.serving(), "Dateidienst lauscht auf Port %d" % RAW_PORT)
	# 1. Datei noch nicht bereit (503): Empfänger wartet, dann vollständige, geprüfte Übertragung
	var client := NetApk.new()
	var out := DIR + "/empfang"
	client.fetch("127.0.0.1", RAW_PORT, int(src.size), str(src.sha256), out)
	pump([server, client], 4000, func(): return client.progress_raw().get("state") == "wait")
	check(client.progress_raw().get("state") == "wait", "Datei noch in Vorbereitung: Empfänger wartet (503)")
	server.set_file(str(src.path), int(src.size), str(src.sha256))
	var samples: Array = []
	var etas := 0
	worst_ms = 0.0
	var t0 := Time.get_ticks_msec()
	var ok := pump([server, client], 30000, func():
		var p := client.progress()
		if p.state == "load":
			if samples.is_empty() or int(samples[-1]) != int(p.received):
				samples.append(int(p.received))
			if float(p.eta) >= 0.0:
				etas += 1
		return p.state in ["done", "error"])
	var p := client.progress()
	var sorted := samples.duplicate()
	sorted.sort()
	check(ok and p.state == "done" and file_sha(str(p.path)) == str(src.sha256) and str(p.path) == "%s/%s.apk" % [out, src.sha256],
		"%d MB in %.2f s übertragen und geprüft (%s)" % [int(src.size) / 1048576, (Time.get_ticks_msec() - t0) / 1000.0, str(p.get("error", ""))])
	check(samples.size() >= 3 and samples == sorted, "Fortschritt: %d steigende Zwischenstände" % samples.size())
	check(worst_ms < 50.0, "Hauptthread: längste Abfrage %.2f ms (Grenze 50 ms)" % worst_ms)
	pump([server], 2000, func(): return int(server.stats().served) == 1)
	check(int(server.stats().served) == 1 and int(server.stats().sending) == 0 and int(server.stats().sent) == int(src.size), "Dienst zählt eine vollständige Sendung")
	# 2. Abbruch mitten im Laden (gedrosselt auf 8 MB/s)
	server.max_rate = 8 * 1048576
	var slow := NetApk.new()
	slow.fetch("127.0.0.1", RAW_PORT, int(src.size), str(src.sha256), DIR + "/abbruch")
	pump([server, slow], 10000, func(): return int(slow.progress_raw().get("received", 0)) > 3 * 1048576)
	pump([server, slow], 1500, func(): return float(slow.progress().eta) >= 0.0)
	var eta := float(slow.progress().eta)
	var t_cancel := Time.get_ticks_usec()
	slow.cancel_fetch()
	var cancel_ms := (Time.get_ticks_usec() - t_cancel) / 1000.0
	check(slow.progress_raw().state == "cancelled" and not slow.fetching() and not FileAccess.file_exists(DIR + "/abbruch/%s.apk.part" % src.sha256)
		and not FileAccess.file_exists(DIR + "/abbruch/%s.apk" % src.sha256), "Abbruch: Zustand „abgebrochen“, Teildatei gelöscht")
	check(cancel_ms < 50.0, "Abbruch kehrt nach %.1f ms zurück (Thread beendet)" % cancel_ms)
	check(eta > 0.5 and eta < 10.0, "Restzeit beim gedrosselten Laden geschätzt: %.1f s" % eta)
	pump([server], 3000, func(): return int(server.stats().aborted) >= 1 and int(server.stats().sending) == 0)
	check(int(server.stats().aborted) == 1 and int(server.stats().sending) == 0, "Dienst merkt den Abbruch und gibt die Sendung frei")
	server.max_rate = 0
	# 2b. Drossel schaltet mitten in einer schnellen Sendung ein (Rennstart beim Gastgeber): Die Übertragung muss sofort mit der
	# neuen Rate weiterlaufen. Vorher maß die Drossel den Durchschnitt seit Beginn und pausierte, bis der Empfänger abbrach (Prüfung 04.10.).
	server.max_rate = 0
	var turn := NetApk.new()
	turn.fetch("127.0.0.1", RAW_PORT, int(src.size), str(src.sha256), DIR + "/umschalten")
	pump([server, turn], 10000, func(): return int(turn.progress_raw().get("received", 0)) > 6 * 1048576)
	server.max_rate = 1048576
	var at_switch := int(turn.progress_raw().get("received", 0))
	pump([server, turn], 1500, func(): return int(turn.progress_raw().get("received", 0)) > at_switch + 262144)
	var moved := int(turn.progress_raw().get("received", 0)) - at_switch
	check(moved > 262144 and turn.progress_raw().get("state") == "load", "Drossel mitten in der Sendung: läuft sofort weiter (%d KB in ≤ 1,5 s)" % (moved / 1024))
	turn.cancel_fetch()
	pump([server], 3000, func(): return int(server.stats().sending) == 0)
	server.max_rate = 0
	# 3. Verfälschte Datei: ein Byte unterwegs verändert → abgelehnt, nichts bleibt liegen
	server.corrupt_at = 5 * 1048576 + 17
	var bad := NetApk.new()
	bad.fetch("127.0.0.1", RAW_PORT, int(src.size), str(src.sha256), DIR + "/falsch")
	pump([server, bad], 30000, func(): return bad.progress_raw().get("state") in ["done", "error"])
	check(bad.progress_raw().state == "error" and str(bad.progress_raw().error).contains("Prüfsumme") and not FileAccess.file_exists(DIR + "/falsch/%s.apk" % src.sha256)
		and not FileAccess.file_exists(DIR + "/falsch/%s.apk.part" % src.sha256), "Verfälschte Datei abgelehnt: „%s“" % bad.progress_raw().get("error", ""))
	server.corrupt_at = -1
	# 4. Größe passt nicht zur Ankündigung, 5. fremde Prüfsumme (andere Datei)
	var size_wrong := NetApk.new()
	size_wrong.fetch("127.0.0.1", RAW_PORT, int(src.size) + 1, str(src.sha256), DIR + "/groesse")
	pump([server, size_wrong], 8000, func(): return size_wrong.progress_raw().get("state") in ["done", "error"])
	check(size_wrong.progress_raw().state == "error" and str(size_wrong.progress_raw().error).contains("Größe"), "Falsche Größe: „%s“" % size_wrong.progress_raw().get("error", ""))
	var foreign := NetApk.new()
	foreign.fetch("127.0.0.1", RAW_PORT, int(src.size), SHA_A, DIR + "/fremd")
	pump([server, foreign], 8000, func(): return foreign.progress_raw().get("state") in ["done", "error"])
	check(foreign.progress_raw().state == "error" and str(foreign.progress_raw().error).contains("nicht mehr an"), "Fremde Datei angefragt: „%s“" % foreign.progress_raw().get("error", ""))
	# 6. Schluss: Dienst beenden geht schnell, danach ist niemand mehr da
	var t_stop := Time.get_ticks_usec()
	server.stop_serving()
	var stop_ms := (Time.get_ticks_usec() - t_stop) / 1000.0
	check(not server.serving() and stop_ms < 60.0, "Dienst beendet in %.1f ms" % stop_ms)
	var nobody := NetApk.new()
	var t_none := Time.get_ticks_msec()
	nobody.fetch("127.0.0.1", RAW_PORT, int(src.size), str(src.sha256), DIR + "/niemand")
	pump([nobody], 12000, func(): return nobody.progress_raw().get("state") in ["done", "error"])
	check(nobody.progress_raw().state == "error" and str(nobody.progress_raw().error).contains("nicht erreichbar"),
		"Keine Gegenseite: „%s“ nach %.1f s" % [nobody.progress_raw().get("error", ""), (Time.get_ticks_msec() - t_none) / 1000.0])
	check(worst_ms < 50.0, "Hauptthread über alle Übertragungen: längste Abfrage %.2f ms" % worst_ms)

# ---------- Ablauf in der Lobby ----------
func make_lobby(player_name: String, apk: ApkShare, extra := {}) -> NetLobby:
	var saved: Dictionary = NetLobby.overrides
	NetLobby.overrides = TEST_OVERRIDES.merged(extra, true)
	var lb := NetLobby.new()
	NetLobby.overrides = saved
	lb.tracks = ["azure", "city"]
	lb.apk = apk
	root.add_child(lb)
	lb.enter(player_name, 0)
	return lb

func make_share(override: Dictionary) -> ApkShare:
	var sh := ApkShare.new()
	sh.source_override = override
	root.add_child(sh)
	sh.setup()
	return sh

func failed_reason(lb: NetLobby) -> Array:
	var got: Array = []
	lb.failed.connect(func(r): got.append(r))
	return got

func test_lobby_flow(src: Dictionary) -> void:
	var own := NetProtocol.game_version()
	# A: Gastgeber neuer (Mitspieler meldet 0.0.1) – Angebot in der Ablehnung, Mitspieler holt und prüft
	var host_share := make_share({"path": src.path, "version": own, "receive": true})
	var host := make_lobby("Anna", host_share, {"apk_port": APK_PORT, "apk_dir": DIR + "/gastgeber"})
	pump([host], 5000, func(): return host_share.sha256 != "")
	check(host_share.sha256 == str(src.sha256) and host.own_offer().port == APK_PORT, "Gastgeber kennt die Prüfsumme seiner APK (im Hintergrund berechnet)")
	check(host.host("azure", 0) == OK, "Gastgeber eröffnet")
	var guest_share := make_share({"receive": true})
	var guest := make_lobby("Ben", guest_share, {"apk_dir": DIR + "/mitspieler"})
	guest.hello_override = {"game": "0.0.1"}
	var reasons := failed_reason(guest)
	check(guest.apk_role_for(own) == "fetch" and guest.apk_role_for("0.0.0") == "" and host.apk_role_for("0.0.1") == "give" and host.apk_role_for(own) == "",
		"Liste: neuere Version antippbar zum Holen, ältere zum Weitergeben, gleiche nicht")
	guest.join("127.0.0.1", PORT)
	pump([host, guest], 4000, func(): return not reasons.is_empty())
	var o := guest.apk_offer
	check(not reasons.is_empty() and str(reasons[0]).contains("Andere Spielversion") and o.get("from") == "host" and o.get("version") == own
		and o.get("sha256") == src.sha256 and int(o.get("size", 0)) == int(src.size) and o.get("port") == APK_PORT and o.get("address") == "127.0.0.1" and o.get("name") == "Anna",
		"Abgelehnt mit Grund und Angebot „Neue Version (%s) vom Gastgeber holen“" % own)
	check(host.transfer.serving() and host.apk_offer.is_empty(), "Gastgeber stellt seine Datei bereit und bekommt selbst kein Angebot")
	host.phase = "ready"
	host.poll()
	var capped := host.transfer.max_rate
	host.phase = "lobby"
	host.poll()
	check(capped == NetLobby.APK_ROUND_RATE and host.transfer.max_rate == 0, "Während einer Runde sendet der Gastgeber gedrosselt (Schnappschüsse haben Vorrang)")
	guest.search()           # wie main.net_failed: zurück zur Suche, das Angebot bleibt
	check(not guest.apk_offer.is_empty() and guest.apk_fetch(), "Holen gestartet (aus dem WLAN-Bildschirm)")
	worst_ms = 0.0
	var ok := pump([host, guest], 30000, func(): return guest.transfer.progress_raw().get("state") in ["done", "error"])
	var p := guest.transfer.progress_raw()
	check(ok and p.state == "done" and file_sha(str(p.path)) == str(src.sha256) and str(p.path).begins_with(DIR + "/mitspieler/"),
		"Mitspieler hat die neue Version geholt und geprüft (%s)" % str(p.get("error", "")))
	check(worst_ms < 50.0, "Hauptthread beim Holen in der Lobby: längste Abfrage %.2f ms" % worst_ms)
	# Verlassen mitten im Holen: sauber abgebrochen, Threads beendet
	host.apk_rate = 6 * 1048576
	guest.transfer.reset_fetch()
	guest.apk_fetch()
	pump([host, guest], 6000, func(): return int(guest.transfer.progress_raw().get("received", 0)) > 1048576)
	var t_exit := Time.get_ticks_usec()
	guest.exit()
	var exit_ms := (Time.get_ticks_usec() - t_exit) / 1000.0
	check(not guest.transfer.fetching() and guest.apk_offer.is_empty() and not FileAccess.file_exists(DIR + "/mitspieler/%s.apk.part" % src.sha256),
		"Verlassen bricht das Holen sauber ab (Teildatei weg, Angebot vergessen)")
	check(exit_ms < 60.0, "Verlassen während des Holens dauert %.1f ms" % exit_ms)
	host.apk_rate = 0
	guest.free()
	# B: Mitspieler neuer (9.9.9) – Anmeldung mit Angebot, der Gastgeber holt beim Mitspieler
	var src2 := make_file(DIR + "/neu.bin", 6)
	var new_share := make_share({"path": src2.path, "version": "9.9.9", "receive": true})
	var newer := make_lobby("Cleo", new_share, {"apk_port": GUEST_APK_PORT, "apk_dir": DIR + "/neu"})
	newer.hello_override = {"game": "9.9.9"}
	pump([newer], 5000, func(): return new_share.sha256 != "")
	var reasons2 := failed_reason(newer)
	newer.join("127.0.0.1", PORT)
	pump([host, newer], 4000, func(): return not reasons2.is_empty())
	var ho := host.apk_offer
	check(not reasons2.is_empty() and newer.apk_pull.get("name") == "Anna" and newer.apk_pull.get("version") == own and newer.transfer.serving() and newer.apk_offer.is_empty(),
		"Mitspieler neuer: abgelehnt, stellt seine Datei für den Gastgeber bereit")
	check(ho.get("from") == "guest" and ho.get("version") == "9.9.9" and ho.get("name") == "Cleo" and ho.get("sha256") == src2.sha256 and ho.get("port") == GUEST_APK_PORT,
		"Gastgeber sieht „Neue Version von Cleo holen“")
	newer.search()
	check(host.apk_fetch() and host.start_problem().contains("neue Version"), "Gastgeber holt beim Mitspieler (Start gesperrt, solange er holt)")
	ok = pump([host, newer], 30000, func(): return host.transfer.progress_raw().get("state") in ["done", "error"])
	p = host.transfer.progress_raw()
	check(ok and p.state == "done" and file_sha(str(p.path)) == str(src2.sha256), "Gastgeber hat die neue Version des Mitspielers geholt und geprüft")
	pump([host, newer], 3000, func(): return int(newer.transfer.stats().served) >= 1)
	check(int(newer.transfer.stats().served) == 1, "Mitspieler zählt die vollständige Sendung")
	newer.exit()
	check(not newer.transfer.serving(), "Verlassen beendet den Dateidienst")
	newer.free()
	# C: kein Downgrade – ein älterer Mitspieler mit eigener APK wird dem Gastgeber nicht angeboten; D: Gastgeber ohne APK (PC)
	host.apk_dismiss()
	var old_share := make_share({"path": src2.path, "version": "0.0.1", "receive": true})
	var older := make_lobby("Dora", old_share, {"apk_port": GUEST_APK_PORT, "apk_dir": DIR + "/alt"})
	older.hello_override = {"game": "0.0.1"}
	pump([older], 5000, func(): return old_share.sha256 != "")
	var reasons3 := failed_reason(older)
	older.join("127.0.0.1", PORT)
	pump([host, older], 4000, func(): return not reasons3.is_empty())
	check(not reasons3.is_empty() and host.apk_offer.is_empty() and older.apk_pull.is_empty() and not older.transfer.serving() and older.apk_offer.get("version") == own,
		"Kein Downgrade: der Gastgeber bekommt die ältere Version nie angeboten, der Ältere bekommt das Angebot")
	older.exit()
	older.free()
	host.exit()
	host.free()
	var plain_host := make_lobby("Emil", null)
	plain_host.host("azure", 0)
	var guest2 := make_lobby("Finn", make_share({"receive": true}))
	guest2.hello_override = {"game": "0.0.1"}
	var reasons4 := failed_reason(guest2)
	guest2.join("127.0.0.1", PORT)
	pump([plain_host, guest2], 4000, func(): return not reasons4.is_empty())
	check(not reasons4.is_empty() and str(reasons4[0]).contains("Andere Spielversion") and guest2.apk_offer.is_empty(), "Gastgeber ohne eigene APK (PC): klare Ablehnung, kein Angebot")
	guest2.exit()
	guest2.free()
	plain_host.exit()
	plain_host.free()
	# Lobby bleibt getrennt von Simulation und Spielstand
	var source := FileAccess.get_file_as_string("res://scripts/net/net_apk.gd") + FileAccess.get_file_as_string("res://scripts/apk_share.gd")
	check(not source.contains("RaceField") and not source.contains("store.") and not source.contains("RaceVehicle"), "Weitergabe rechnet nichts und schreibt keinen Spielstand")
