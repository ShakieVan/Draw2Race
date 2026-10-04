extends SceneTree

# Weitergabe der neueren Version zwischen getrennten Prozessen (tools/net_test.ps1 -Apk; scripts/net/net_apk.gd, NetLobby):
#   --apktest=host   Gastgeber (Version des Spiels) mit einer Zufallsdatei als „APK“ (--apktest-mb MiB). Wartet, bis
#                    --apktest-served Sendungen vollständig und --apktest-aborted abgebrochen sind; mit --apktest-pull holt er
#                    zusätzlich die neuere Version eines Mitspielers, sobald sie angeboten wird, und prüft sie.
#   --apktest=fetch  Mitspieler mit Version 0.0.1: wird abgelehnt, holt die neue Version vom Gastgeber und prüft sie gegen die
#                    Quelldatei des Gastgebers (--apktest-source=Name). --apktest-cancel=MB: bricht nach so vielen MB ab;
#                    --apktest-expect=Text: erwartet einen Fehler mit diesem Text (verfälschte Datei).
#   --apktest=give   Mitspieler mit Version 9.9.9 und eigener Zufallsdatei: wird abgelehnt und stellt seine Datei bereit, bis der
#                    Gastgeber sie vollständig geholt hat.
# Weitere Optionen: --apktest-name, --apktest-port (Basis: ENet, +1 Suche, +2 Ankündigung, +3 Datei), --apktest-own-port
# (Dateidienst des Mitspielers), --apktest-rate (MB/s, Sendetempo des Gastgebers), --apktest-corrupt (ein Byte verfälscht senden),
# --apktest-timeout (s). Gemessen wird der längste Bildabstand, solange eine Übertragung läuft (frames=… ms; Grenze 50 ms).
# Ergebniszeile „APKTEST-ERGEBNIS: …“, Exitcode 0 = OK.

var opt := {}
var lobby: NetLobby
var share: ApkShare
var start_ms := 0
var done := false
var source := {}
var reasons: Array = []
var worst_frame := 0.0
var samples := 0
var last_received := -1
var eta_seen := false
var pulled := ""
var fetch_started := false

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var key := arg.get_slice("=", 0)
		var value := arg.substr(key.length() + 1) if "=" in arg else ""
		opt[key.trim_prefix("--apktest").trim_prefix("-")] = value
	Engine.max_fps = 120
	start_ms = Time.get_ticks_msec()
	var role := str(opt.get("", ""))
	var base := int(opt.get("port", "24710"))
	var dir := "user://apktest/%s" % opt.get("name", role)
	DirAccess.make_dir_recursive_absolute(dir)
	share = ApkShare.new()
	var version := NetProtocol.game_version()
	if role == "give":
		version = "9.9.9"
	if role in ["host", "give"]:
		source = make_file(dir + "/quelle.bin", int(opt.get("mb", "40")))
		share.source_override = {"path": source.path, "version": version, "receive": true}
	else:
		share.source_override = {"receive": true}
	root.add_child(share)
	NetLobby.overrides = {"game_port": base, "discovery_port": base + 1, "beacon_port": base + 2, "probe_local": true, "use_broadcast": false,
		"use_binding": false, "log_path": "", "apk_port": int(opt.get("own-port", str(base + 3))), "apk_dir": dir + "/empfang",
		"apk_rate": int(float(opt.get("rate", "0")) * 1048576), "apk_corrupt": 3 * 1048576 + 5 if opt.has("corrupt") else -1}
	lobby = NetLobby.new()
	NetLobby.overrides = {}
	lobby.tracks = ["azure"]
	lobby.apk = share
	root.add_child(lobby)
	lobby.log_line.connect(func(t): print(t))
	lobby.failed.connect(func(r): reasons.append(r); print("Abgelehnt: ", r); lobby.search())
	if role == "fetch":
		lobby.hello_override = {"game": "0.0.1"}
	elif role == "give":
		lobby.hello_override = {"game": "9.9.9"}
	lobby.enter(str(opt.get("name", role)), 0)
	if role == "host":
		if lobby.host("azure", 0) != OK:
			_finish(false, "host: " + lobby.session.detail)
	elif not role in ["fetch", "give"]:
		_finish(false, "unbekannte Rolle „%s“" % role)

func make_file(path: String, mb: int) -> Dictionary:
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

func _process(delta: float) -> bool:
	if done or lobby == null:
		return false
	var busy := lobby.transfer.fetching() or int(lobby.transfer.stats().sending) > 0
	if busy and Engine.get_process_frames() > 30:     # die ersten Bilder (Programmstart, Testdatei anlegen) zählen nicht
		worst_frame = maxf(worst_frame, delta * 1000.0)
	if (Time.get_ticks_msec() - start_ms) / 1000.0 > float(opt.get("timeout", "40")):
		var p := lobby.transfer.progress_raw()
		_finish(false, "Zeitgrenze (Empfang %s %s, Dienst %s, Angebot %s)" % [p.get("state", "–"), p.get("error", ""), lobby.transfer.stats(), lobby.apk_offer.get("version", "–")])
		return false
	match str(opt.get("", "")):
		"host":
			_host_tick()
		"fetch":
			_fetch_tick()
		"give":
			_give_tick()
	return false

func _sample() -> void:
	var p := lobby.transfer.progress()
	if p.state == "load" and int(p.received) != last_received:
		last_received = int(p.received)
		samples += 1
	if float(p.eta) >= 0.0:
		eta_seen = true

func _host_tick() -> void:
	if opt.has("pull"):
		if not fetch_started and str(lobby.apk_offer.get("from", "")) == "guest":
			fetch_started = lobby.apk_fetch()
		if fetch_started and pulled == "":
			var p := lobby.transfer.progress_raw()
			if p.state == "done":
				pulled = "ja" if file_sha(str(p.path)) == str(lobby.apk_offer.sha256) else "falsche Prüfsumme"
			elif p.state in ["error", "cancelled"]:
				pulled = "Fehler: " + str(p.error)
	var st := lobby.transfer.stats()
	if int(st.served) >= int(opt.get("served", "0")) and int(st.aborted) >= int(opt.get("aborted", "0")) and int(st.sending) == 0 \
			and (not opt.has("pull") or pulled != ""):
		var ok := (not opt.has("pull") or pulled == "ja") and worst_frame < 50.0
		_finish(ok, "served=%d aborted=%d pull=%s frames=%.0f" % [int(st.served), int(st.aborted), pulled if opt.has("pull") else "–", worst_frame])

func _fetch_tick() -> void:
	if lobby.mode == "" and reasons.is_empty() and not lobby.session.is_active() and not fetch_started and Time.get_ticks_msec() - start_ms > 200:
		lobby.join("127.0.0.1", int(opt.get("port", "24710")))
		return
	if reasons.is_empty():
		return
	if not fetch_started:
		var o := lobby.apk_offer
		if o.is_empty() or o.get("from") != "host" or o.get("version") != NetProtocol.game_version():
			_finish(false, "kein Angebot nach der Ablehnung (%s)" % str(reasons[0]).left(80))
			return
		fetch_started = lobby.apk_fetch()
		return
	_sample()
	var p := lobby.transfer.progress_raw()
	if opt.has("cancel") and p.state == "load" and int(p.received) > int(float(opt.cancel) * 1048576):
		var t0 := Time.get_ticks_usec()
		lobby.apk_cancel()
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		var q := lobby.transfer.progress_raw()
		var part := str(q.path) + ".part"
		_finish(q.state == "cancelled" and not FileAccess.file_exists(part) and ms < 50.0 and worst_frame < 50.0,
			"abgebrochen nach %s MB in %.1f ms, Teildatei %s, frames=%.0f" % [NetApk.megabytes(int(p.received)), ms, "weg" if not FileAccess.file_exists(part) else "DA", worst_frame])
		return
	if p.state == "error":
		var expect := str(opt.get("expect", ""))
		var ok := expect != "" and str(p.error).contains(expect) and not FileAccess.file_exists(str(p.path)) and not FileAccess.file_exists(str(p.path) + ".part")
		_finish(ok, "Fehler „%s“, nichts übernommen: %s, frames=%.0f" % [p.error, "ja" if not FileAccess.file_exists(str(p.path)) else "NEIN", worst_frame])
	elif p.state == "done":
		var got := file_sha(str(p.path))
		var host_file := "user://apktest/%s/quelle.bin" % opt.get("source", "Quelle")
		var ok := not opt.has("expect") and got == str(lobby.apk_offer.sha256) and got == file_sha(host_file) and samples >= 5 and eta_seen and worst_frame < 50.0
		_finish(ok, "geholt %s MB, Prüfsumme %s, gleich der Quelle: %s, Fortschritt %d Stände, Restzeit %s, frames=%.0f" % [
			NetApk.megabytes(int(p.size)), got.left(12), "ja" if got == file_sha(host_file) else "NEIN", samples, "ja" if eta_seen else "nein", worst_frame])

func _give_tick() -> void:
	if share.sha256 == "":
		return
	if lobby.mode == "" and reasons.is_empty() and not fetch_started:
		fetch_started = true
		lobby.join("127.0.0.1", int(opt.get("port", "24710")))
		return
	if reasons.is_empty():
		return
	if lobby.apk_pull.is_empty():
		_finish(false, "Ablehnung ohne Holen des Gastgebers (%s)" % str(reasons[0]).left(80))
		return
	var st := lobby.transfer.stats()
	if int(st.served) >= 1 and int(st.sending) == 0:
		_finish(worst_frame < 50.0, "bereitgestellt und vollständig gesendet (%s MB), frames=%.0f" % [NetApk.megabytes(int(source.size)), worst_frame])

func _finish(ok: bool, text: String) -> void:
	if done:
		return
	done = true
	print("APKTEST-ERGEBNIS: %s %s" % ["OK" if ok else "FEHLER", text])
	if lobby != null:
		lobby.exit()
	quit(0 if ok else 1)
