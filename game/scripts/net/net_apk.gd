class_name NetApk
extends RefCounted

# Neuere Spielversion im lokalen Netz weitergeben (Nutzerwunsch 04.10.2026: „dass die App die APK an benachbarte Geräte schicken
# kann (falls z. B. kein Internet verfügbar ist)“). Lehnt der Gastgeber einen Beitritt wegen einer anderen Spielversion ab (Code
# „game“ oder „protocol“), bekommt nur die Seite mit der ÄLTEREN Version das Angebot, die neuere APK vom anderen Gerät zu holen –
# nie umgekehrt, also kein Downgrade:
#   Gastgeber neuer:   Ablehnung mit Zusatz {game, name, apk {size, sha256, port}} → Mitspieler: „Neue Version (x.y.z) vom Gastgeber holen“.
#   Mitspieler neuer:  Anmeldung mit apk {size, sha256, port} → Ablehnung mit {game, name, pull: true} → der Mitspieler stellt seine
#                      Datei bereit, der Gastgeber sieht „Neue Version von <Name> holen“.
# Regeln: host_decision / guest_decision (rein, test_apk). Übertragung: kleiner HTTP/1.1-Dienst der neueren Seite auf TCP-Port PORT
# (allen Schnittstellen, also auch im eigenen Hotspot), der genau eine Datei unter /draw2race-<sha256>.apk ausliefert; Antwort 503,
# solange die Datei noch vorbereitet wird (Kopie der installierten APK, ApkShare) – der Empfänger wartet dann. Senden und Empfangen
# laufen in eigenen Threads, der Hauptthread fragt nur Zahlen ab (poll, progress). Der Empfang rechnet SHA-256 beim Laden mit und
# übernimmt die Datei nur bei passender Größe und Prüfsumme; die Installation prüft danach Paket, höhere Versionsnummer und
# identische Signatur (Updater.install_file → Updater.java). Sockets entstehen nach den WLAN-Bindungsregeln von NetLobby.

signal log_line(text: String)

const PORT := 24683                     # TCP, neben den ENet-/Such-Ports (NetProtocol)
const MAX_BYTES := 512 * 1024 * 1024    # wie Updater.MAX_APK_BYTES
const CHUNK := 256 * 1024
const HEADER_MAX := 4096
const CONNECT_TIMEOUT_MS := 8000
const CONNECT_RETRY_MS := 6000          # „Verbindung abgelehnt“ so lange wiederholen (Dienst startet gerade)
const HEADER_TIMEOUT_MS := 15000
const STALL_MS := 20000                 # so lange ohne ein Byte → abbrechen
const PREPARE_WAIT_MS := 120000         # 503: so lange auf die Vorbereitung der Gegenseite warten
const MAX_SENDS := 4                    # gleichzeitige Sendungen
const VERSION_CODES := ["game", "protocol"]
const STATES_ACTIVE := ["connect", "wait", "load", "check"]

# ---------- Regeln (rein) ----------
static func newer(a: String, b: String) -> bool:
	# a ist eine gültige, echt höhere Version als b.
	return Updater.valid_version(a) and Updater.valid_version(b) and Updater.compare_versions(a, b) > 0

static func is_sha(text: String) -> bool:
	if text.length() != 64:
		return false
	for c in text.to_lower():
		if not c in "0123456789abcdef":
			return false
	return true

static func clean_offer(d) -> Dictionary:
	# APK-Angebot aus einer Nachricht: {size, sha256, port}, sonst {}.
	if not d is Dictionary:
		return {}
	var size = d.get("size")
	var sha = d.get("sha256")
	var port = d.get("port")
	if not (size is int or size is float) or not sha is String or not (port is int or port is float):
		return {}
	if int(size) <= 0 or int(size) > MAX_BYTES or int(port) <= 0 or int(port) > 65535 or not is_sha(sha):
		return {}
	return {"size": int(size), "sha256": str(sha).to_lower(), "port": int(port)}

static func host_decision(code: String, own: String, hello: Dictionary, own_offer: Dictionary, can_receive: bool) -> Dictionary:
	# Gastgeber lehnt einen Beitritt ab (code). extra = Zusatz der Ablehnung, serve = eigene Datei bereitstellen, offer = der Gastgeber
	# darf die neuere Version des Mitspielers holen ({version, name, size, sha256, port}). Nur bei anderer Spielversion.
	var out := {"extra": {}, "serve": false, "offer": {}}
	if not code in VERSION_CODES:
		return out
	var other := str(hello.get("game", "")).left(16) if hello.get("game") is String else ""
	out.extra = {"game": own}
	if newer(own, other) and not clean_offer(own_offer).is_empty():
		out.extra["apk"] = clean_offer(own_offer)
		out.serve = true
	elif newer(other, own) and can_receive:
		var theirs := clean_offer(hello.get("apk"))
		if not theirs.is_empty():
			out.extra["pull"] = true
			theirs["version"] = other
			theirs["name"] = NetProtocol.clean_name(str(hello.get("name", "")))
			out.offer = theirs
	return out

static func guest_decision(code: String, own: String, extra: Dictionary, can_share: bool, can_receive: bool) -> Dictionary:
	# Mitspieler nach einer Ablehnung. offer = neuere Version beim Gastgeber holen ({version, name, size, sha256, port}); serve = die
	# eigene, neuere Datei für den Gastgeber bereitstellen (er hat „pull“ gemeldet); host_version = Version des Gastgebers ("" = unbekannt).
	var out := {"offer": {}, "serve": false, "host_version": "", "host_name": ""}
	if not code in VERSION_CODES or not extra.get("game") is String:
		return out
	var host := str(extra.game).left(16)
	out.host_version = host
	out.host_name = NetProtocol.clean_name(str(extra.get("name", "")), "Gastgeber")
	if newer(host, own) and can_receive:
		var theirs := clean_offer(extra.get("apk"))
		if not theirs.is_empty():
			theirs["version"] = host
			theirs["name"] = out.host_name
			out.offer = theirs
	elif newer(own, host) and can_share and extra.get("pull") == true:
		out.serve = true
	return out

static func megabytes(bytes: int) -> String:
	return "%d" % roundi(bytes / 1048576.0) if bytes >= 10 * 1048576 else "%.1f" % (bytes / 1048576.0)

static func progress_text(p: Dictionary) -> String:
	# „120 von 310 MB · noch 12 s“ (Empfang).
	var text := "%s von %s MB" % [megabytes(int(p.get("received", 0))), megabytes(int(p.get("size", 0)))]
	var eta := float(p.get("eta", -1.0))
	if eta >= 0.0:
		text += " · noch %s" % ("%d s" % ceili(eta) if eta < 90.0 else "%d min" % ceili(eta / 60.0))
	return text

# ---------- Zustand (Threads: nur unter _mutex) ----------
var _mutex := Mutex.new()
var _server: TCPServer
var _server_thread: Thread
var _stop := false
var _file := {}                 # {path, size, sha256}; leer = Datei wird noch vorbereitet (503)
var serve_port := 0
var _stats := {"served": 0, "aborted": 0, "sending": 0, "sent": 0}
var max_rate := 0               # nur Tests: Bytes/s je Sendung (0 = unbegrenzt)
var corrupt_at := -1            # nur Tests: dieses Byte verfälscht senden (der Empfänger muss die Datei ablehnen)
var _fetch_thread: Thread
var _cancel := false
var _f := {}                    # Empfang: state ("" | connect | wait | load | check | done | error | cancelled), received, size, error, path
var _samples: Array = []        # Hauptthread: [ms, Bytes] der letzten Sekunden (Tempo, Restzeit)
var _logs: Array = []

func close() -> void:
	# Alles beenden (Verlassen des WLAN-Mehrspielers): Empfang abbrechen, Dienst stoppen. Die Threads prüfen alle paar ms.
	cancel_fetch()
	stop_serving()

func poll() -> void:
	# Hauptthread, je Bild: fertige Threads einsammeln, Tempo messen, Protokollzeilen weitergeben.
	_mutex.lock()
	var lines := _logs
	_logs = []
	var state := str(_f.get("state", ""))
	var received := int(_f.get("received", 0))
	_mutex.unlock()
	for line in lines:
		log_line.emit(line)
	if _fetch_thread != null and not _fetch_thread.is_alive():
		_fetch_thread.wait_to_finish()
		_fetch_thread = null
	if state == "load":
		var now := Time.get_ticks_msec()
		if _samples.is_empty() or int(_samples[-1][1]) != received:
			_samples.append([now, received])
		while _samples.size() > 2 and now - int(_samples[0][0]) > 4000:
			_samples.pop_front()

func _log(text: String) -> void:
	_mutex.lock()
	_logs.append(text)
	_mutex.unlock()

func _stopping() -> bool:
	_mutex.lock()
	var v := _stop
	_mutex.unlock()
	return v

func _cancelled() -> bool:
	_mutex.lock()
	var v := _cancel
	_mutex.unlock()
	return v

func _count(key: String, delta: int) -> void:
	_mutex.lock()
	_stats[key] = int(_stats[key]) + delta
	_mutex.unlock()

# ---------- Dienst (neuere Seite) ----------
func serve(port := PORT) -> Error:
	# Dienst starten (alle Schnittstellen). Die Datei folgt mit set_file(), bis dahin antwortet er 503.
	if _server_thread != null:
		return OK if port == serve_port else ERR_ALREADY_IN_USE
	var server := TCPServer.new()
	var err := server.listen(port, "*")
	if err != OK:
		return err
	_server = server
	serve_port = port
	_mutex.lock()
	_stop = false
	_mutex.unlock()
	_server_thread = Thread.new()
	_server_thread.start(_serve_loop)
	return OK

func serving() -> bool:
	return _server_thread != null

func set_file(path: String, size: int, sha256: String) -> void:
	_mutex.lock()
	_file = {"path": path, "size": size, "sha256": sha256.to_lower()} if path != "" else {}
	_mutex.unlock()

func has_file() -> bool:
	_mutex.lock()
	var v := not _file.is_empty()
	_mutex.unlock()
	return v

func stats() -> Dictionary:
	# {served, aborted, sending, sent (Bytes)} des Dienstes.
	_mutex.lock()
	var out := _stats.duplicate()
	_mutex.unlock()
	return out

func stop_serving() -> void:
	if _server_thread == null:
		return
	_mutex.lock()
	_stop = true
	_mutex.unlock()
	_server_thread.wait_to_finish()
	_server_thread = null
	_server = null
	serve_port = 0
	set_file("", 0, "")

func _serve_loop() -> void:
	var handlers: Array = []
	while not _stopping():
		while _server.is_connection_available():
			var peer := _server.take_connection()
			if peer == null:
				break
			_reap(handlers)
			if handlers.size() >= MAX_SENDS:
				_reply(peer, 503, "Service Unavailable", "Retry-After: 2\r\n")
				continue
			var t := Thread.new()
			t.start(_send.bind(peer))
			handlers.append(t)
		_reap(handlers)
		OS.delay_msec(10)
	for t in handlers:
		t.wait_to_finish()
	_server.stop()

func _reap(handlers: Array) -> void:
	for t in handlers.duplicate():
		if not t.is_alive():
			t.wait_to_finish()
			handlers.erase(t)

func _send(peer: StreamPeerTCP) -> void:
	peer.set_no_delay(true)
	var who := "%s:%d" % [peer.get_connected_host(), peer.get_connected_port()]
	var head := _read_head(peer, true)
	if head.is_empty():
		peer.disconnect_from_host()
		return
	var first := str(head[0]).get_slice("\r\n", 0).split(" ")
	_mutex.lock()
	var file := _file.duplicate()
	_mutex.unlock()
	if first.size() < 2 or first[0] != "GET":
		_reply(peer, 400, "Bad Request")
		return
	if file.is_empty():
		_reply(peer, 503, "Service Unavailable", "Retry-After: 1\r\n")
		return
	if first[1] != "/draw2race-%s.apk" % file.sha256:
		_log("Anfrage von %s nach %s abgelehnt (andere Datei)" % [who, first[1].left(80)])
		_reply(peer, 404, "Not Found")
		return
	var f := FileAccess.open(str(file.path), FileAccess.READ)
	if f == null or f.get_length() != int(file.size):
		_log("Datei %s nicht lesbar oder Größe falsch" % file.path)
		_reply(peer, 500, "Internal Server Error")
		return
	var size := int(file.size)
	var header := ("HTTP/1.1 200 OK\r\nContent-Type: application/vnd.android.package-archive\r\nContent-Length: %d\r\n" +
		"Content-Disposition: attachment; filename=\"Draw2Race.apk\"\r\nConnection: close\r\n\r\n") % size
	_count("sending", 1)
	_log("Sende %s MB an %s" % [megabytes(size), who])
	var t0 := Time.get_ticks_msec()
	var ok := _write_all(peer, header.to_ascii_buffer()) and _stream(peer, f, size)
	f.close()
	_count("sending", -1)
	_count("served" if ok else "aborted", 1)
	_log(("Gesendet an %s in %.1f s" % [who, (Time.get_ticks_msec() - t0) / 1000.0]) if ok else "Sendung an %s abgebrochen" % who)
	if ok:
		# Erst trennen, wenn der Empfänger alles hat und selbst trennt (sonst könnten die letzten Bytes verloren gehen), höchstens 10 s.
		var end := Time.get_ticks_msec() + 10000
		while Time.get_ticks_msec() < end and not _stopping():
			peer.poll()
			if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				break
			if peer.get_available_bytes() > 0:
				peer.get_partial_data(peer.get_available_bytes())
			OS.delay_msec(5)
	peer.disconnect_from_host()

func _reply(peer: StreamPeerTCP, code: int, text: String, extra := "") -> void:
	_write_all(peer, ("HTTP/1.1 %d %s\r\nContent-Length: 0\r\nConnection: close\r\n%s\r\n" % [code, text, extra]).to_ascii_buffer())
	peer.disconnect_from_host()

func _stream(peer: StreamPeerTCP, f: FileAccess, size: int) -> bool:
	var sent := 0
	var start := Time.get_ticks_msec()
	var last := start
	# Drossel als gleitendes Fenster ab der letzten Änderung der Grenze: Schaltet der Gastgeber beim Rennstart von unbegrenzt auf
	# APK_ROUND_RATE, wartete eine schon schnell gelaufene Sendung sonst, bis ihr Durchschnitt seit Beginn auf die neue Grenze fiel,
	# und der Empfänger brach nach STALL_MS ab (Prüfung 04.10.2026).
	var window_rate := max_rate
	var window_start := start
	var window_sent := 0
	var buf := PackedByteArray()
	var off := 0
	while sent < size:
		if _stopping():
			return false
		if off >= buf.size():
			buf = f.get_buffer(mini(CHUNK, size - sent))
			if buf.is_empty():
				return false
			if corrupt_at >= sent and corrupt_at < sent + buf.size():
				buf[corrupt_at - sent] = buf[corrupt_at - sent] ^ 0xFF
			off = 0
		var now := Time.get_ticks_msec()
		var rate := max_rate
		if rate != window_rate:
			window_rate = rate
			window_start = now
			window_sent = 0
		if rate > 0 and window_sent > rate * (now - window_start) / 1000:
			OS.delay_msec(2)
			continue
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			return false
		var piece := buf if off == 0 else buf.slice(off)
		if rate > 0 and piece.size() > 65536:
			piece = piece.slice(0, 65536)
		var r := peer.put_partial_data(piece)
		if r[0] != OK:
			return false
		var n := int(r[1])
		if n > 0:
			off += n
			sent += n
			window_sent += n
			last = now
			_count("sent", n)
		elif now - last > STALL_MS:
			return false
		else:
			OS.delay_msec(1)
	return true

func _write_all(peer: StreamPeerTCP, bytes: PackedByteArray, server := true) -> bool:
	var off := 0
	var last := Time.get_ticks_msec()
	while off < bytes.size():
		if (server and _stopping()) or (not server and _cancelled()):
			return false
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			return false
		var r := peer.put_partial_data(bytes.slice(off))
		if r[0] != OK:
			return false
		if int(r[1]) > 0:
			off += int(r[1])
			last = Time.get_ticks_msec()
		elif Time.get_ticks_msec() - last > STALL_MS:
			return false
		else:
			OS.delay_msec(1)
	return true

func _read_head(peer: StreamPeerTCP, server: bool) -> Array:
	# Bis zur Leerzeile lesen (höchstens HEADER_MAX). [Kopf als Text, Rest-Bytes] oder [] (Zeitgrenze, Abbruch, getrennt).
	var buf := PackedByteArray()
	var end := Time.get_ticks_msec() + HEADER_TIMEOUT_MS
	while Time.get_ticks_msec() < end:
		if (server and _stopping()) or (not server and _cancelled()):
			return []
		peer.poll()
		var n := peer.get_available_bytes()
		if n > 0:
			var r := peer.get_partial_data(mini(n, 65536))
			if r[0] != OK:
				return []
			buf.append_array(r[1])
			var cut := _blank_line(buf)
			if cut >= 0:
				return [buf.slice(0, cut).get_string_from_ascii(), buf.slice(cut + 4)]
			if buf.size() > HEADER_MAX:
				return []
		elif peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			return []
		else:
			OS.delay_msec(2)
	return []

static func _blank_line(buf: PackedByteArray) -> int:
	for i in range(mini(buf.size(), HEADER_MAX + 4) - 3):
		if buf[i] == 13 and buf[i + 1] == 10 and buf[i + 2] == 13 and buf[i + 3] == 10:
			return i
	return -1

# ---------- Empfang (ältere Seite) ----------
func fetch(address: String, port: int, size: int, sha256: String, out_dir := "user://updates") -> void:
	# Datei holen und prüfen; Ergebnis über progress(): state „done“ mit path (<out_dir>/<sha256>.apk) oder „error“ mit Grund.
	cancel_fetch()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var path := "%s/%s.apk" % [out_dir, sha256.to_lower()]
	_mutex.lock()
	_cancel = false
	_f = {"state": "connect", "received": 0, "size": size, "error": "", "path": path}
	_mutex.unlock()
	_samples.clear()
	_fetch_thread = Thread.new()
	_fetch_thread.start(_fetch.bind(address, port, size, sha256.to_lower(), path))

func fetching() -> bool:
	return str(progress_raw().get("state", "")) in STATES_ACTIVE

func cancel_fetch() -> void:
	if _fetch_thread == null:
		return
	_mutex.lock()
	_cancel = true
	_mutex.unlock()
	_fetch_thread.wait_to_finish()
	_fetch_thread = null
	_mutex.lock()
	if str(_f.get("state", "")) in STATES_ACTIVE:
		_f.state = "cancelled"
		_f.error = "Abgebrochen."
	_mutex.unlock()

func reset_fetch() -> void:
	cancel_fetch()
	_mutex.lock()
	_f = {}
	_mutex.unlock()

func progress_raw() -> Dictionary:
	_mutex.lock()
	var out := _f.duplicate()
	_mutex.unlock()
	return out

func progress() -> Dictionary:
	# {state, received, size, error, path, rate (Bytes/s, -1 = unbekannt), eta (s, -1 = unbekannt)}
	var out := progress_raw()
	out["rate"] = -1.0
	out["eta"] = -1.0
	if str(out.get("state", "")) == "load" and _samples.size() >= 2:
		var a: Array = _samples[0]
		var b: Array = _samples[-1]
		var dt := (int(b[0]) - int(a[0])) / 1000.0
		if dt >= 0.3:
			out.rate = (int(b[1]) - int(a[1])) / dt
			if out.rate > 0.0:
				out.eta = (int(out.size) - int(out.received)) / out.rate
	return out

func _set_f(values: Dictionary) -> void:
	_mutex.lock()
	_f.merge(values, true)
	_mutex.unlock()

func _end(state: String, error := "") -> void:
	_set_f({"state": state, "error": error})
	_log(("Empfang: " + error) if error != "" else "Empfang fertig und geprüft")

func _fetch(address: String, port: int, size: int, sha: String, path: String) -> void:
	var started := Time.get_ticks_msec()
	var waiting_since := -1
	while true:
		if _cancelled():
			_end("cancelled", "Abgebrochen.")
			return
		_set_f({"state": "connect" if waiting_since < 0 else "wait"})
		var peer := StreamPeerTCP.new()
		var connected := false
		if peer.connect_to_host(address, port) == OK:
			var end := Time.get_ticks_msec() + CONNECT_TIMEOUT_MS
			while Time.get_ticks_msec() < end and not _cancelled():
				peer.poll()
				var st := peer.get_status()
				if st == StreamPeerTCP.STATUS_CONNECTED:
					connected = true
					break
				if st != StreamPeerTCP.STATUS_CONNECTING:
					break
				OS.delay_msec(5)
		if not connected:
			peer.disconnect_from_host()
			if _cancelled():
				continue
			if Time.get_ticks_msec() - started < CONNECT_RETRY_MS:
				_pause(500)
				continue
			_end("error", "Das andere Handy ist nicht erreichbar (%s:%d). Ist es noch im WLAN-Bildschirm?" % [address, port])
			return
		peer.set_no_delay(true)
		var request := "GET /draw2race-%s.apk HTTP/1.1\r\nHost: %s:%d\r\nUser-Agent: Draw2Race/%s\r\nConnection: close\r\n\r\n" % [
			sha, address, port, NetProtocol.game_version()]
		var head := _read_head(peer, false) if _write_all(peer, request.to_ascii_buffer(), false) else []
		if head.is_empty():
			peer.disconnect_from_host()
			if _cancelled():
				continue
			_end("error", "Das andere Handy antwortet nicht.")
			return
		var lines := str(head[0]).split("\r\n")
		var status := lines[0].get_slice(" ", 1)
		if status == "503":
			peer.disconnect_from_host()
			if waiting_since < 0:
				waiting_since = Time.get_ticks_msec()
			if Time.get_ticks_msec() - waiting_since > PREPARE_WAIT_MS:
				_end("error", "Das andere Handy hat die Datei nicht rechtzeitig vorbereitet.")
				return
			_set_f({"state": "wait"})
			_pause(1000)
			continue
		if status == "404":
			peer.disconnect_from_host()
			_end("error", "Das andere Handy bietet diese Datei nicht mehr an (andere Version?).")
			return
		if status != "200":
			peer.disconnect_from_host()
			_end("error", "Das andere Handy meldet einen Fehler (%s)." % status.left(8))
			return
		var length := -1
		for line in lines:
			if line.to_lower().begins_with("content-length:"):
				var v := line.substr(15).strip_edges()
				length = int(v) if v.is_valid_int() else -1
		if length != size:
			peer.disconnect_from_host()
			_end("error", "Die Datei hat eine andere Größe als angekündigt – nicht übernommen.")
			return
		_receive(peer, head[1], size, sha, path)
		return

func _pause(ms: int) -> void:
	var end := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < end and not _cancelled():
		OS.delay_msec(10)

func _receive(peer: StreamPeerTCP, rest: PackedByteArray, size: int, sha: String, path: String) -> void:
	var part := path + ".part"
	var f := FileAccess.open(part, FileAccess.WRITE)
	if f == null:
		peer.disconnect_from_host()
		_end("error", "Die Datei lässt sich nicht speichern (Speicher voll?).")
		return
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var got := 0
	var last := Time.get_ticks_msec()
	_set_f({"state": "load", "received": 0})
	var data := rest
	var problem := ""
	while true:
		if data.size() > 0:
			if got + data.size() > size:
				data = data.slice(0, size - got)
			f.store_buffer(data)
			ctx.update(data)
			got += data.size()
			last = Time.get_ticks_msec()
			_set_f({"received": got})
			if f.get_error() != OK:
				problem = "Speichern fehlgeschlagen (Speicher voll?)."
				break
			data = PackedByteArray()
		if got >= size:
			break
		if _cancelled():
			problem = "Abgebrochen."
			break
		peer.poll()
		var n := peer.get_available_bytes()
		if n > 0:
			var r := peer.get_partial_data(mini(n, CHUNK))
			if r[0] != OK:
				problem = "Übertragung abgebrochen (%s von %s MB)." % [megabytes(got), megabytes(size)]
				break
			data = r[1]
		elif peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			problem = "Übertragung abgebrochen (%s von %s MB)." % [megabytes(got), megabytes(size)]
			break
		elif Time.get_ticks_msec() - last > STALL_MS:
			problem = "Übertragung hängt seit %d s – abgebrochen." % (STALL_MS / 1000)
			break
		else:
			OS.delay_msec(2)
	f.close()
	peer.disconnect_from_host()
	if problem != "":
		DirAccess.remove_absolute(part)
		_end("cancelled" if problem == "Abgebrochen." else "error", problem)
		return
	_set_f({"state": "check"})
	if ctx.finish().hex_encode() != sha:
		DirAccess.remove_absolute(part)
		_end("error", "Die Datei ist beschädigt oder verändert (Prüfsumme falsch) – nicht übernommen.")
		return
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	if DirAccess.rename_absolute(part, path) != OK:
		DirAccess.remove_absolute(part)
		_end("error", "Die Datei ließ sich nicht ablegen.")
		return
	_end("done")
