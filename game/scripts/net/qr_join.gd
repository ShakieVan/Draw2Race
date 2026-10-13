class_name QrJoin
extends RefCounted

# QR-Code scannen im WLAN-Bildschirm (Beta 1.0.2, Nutzerwunsch 13.10.2026, übernommen aus Mau-Mau Flip 1.4.3). Der Gast scannt in der
# App einen der beiden Codes des Gastgebers (NetInvite/InvitePanel):
#   ① WLAN-QR (WIFI:…):  Die App verbindet sich selbst mit dem Spiel-WLAN (QrWifi.java, WifiNetworkSpecifier ab Android 10, Android
#                        fragt einmal nach), bindet sich daran – mobile Daten stören nicht – und tritt dem Gastgeber am Gateway bei.
#   ② Spiel-QR (http://<IP>:24683/…) oder App-Link (draw2race://join?h=…&p=…): direkt beitreten.
# Scanner: Google Code Scanner (QrScan.java, ohne Kamera-Erlaubnis, braucht die Google-Play-Dienste). Statische Teile: Auswertung (parse,
# rein, testbar) und Java-Anbindung; am PC und in Tests ersetzen scan_stub/wifi_stub die Java-Helfer. Der Ablauf (Instanz) gehört der
# Lobby (NetLobby.qr): Solange das Spiel-WLAN aus dem QR-Code läuft (pinned), binden Suche und Beitritt an dieses Netz statt ans WLAN
# (NetLobby._bind). Freigegeben wird es beim Verlassen des WLAN-Mehrspielers (NetLobby.exit) und, sobald Android es als verloren meldet
# (Gastgeber hat es geschlossen) – sonst fände ein Handy ohne zweiten WLAN-Empfänger nicht ins normale WLAN zurück (Gerätetest Mau-Mau
# Flip 1.4.3, S10).

signal changed                                              # Statuszeile (text, warn) hat sich geändert
signal join_ready(address: String, port: int, label: String)   # jetzt beitreten (main.net_join)

const MAX_TEXT := 1024
const INJECT_MAX_AGE_MS := 120000
const SCAN_POLL_MS := 250
const WIFI_POLL_MS := 400
const LOST_CHECK_MS := 2000

static var scan_stub = null      # Dictionary {available, start_error, results: Array[Dictionary]} statt Java; null = echtes Android
static var wifi_stub = null      # Dictionary {sdk, connect_error, state: Dictionary, bind_error, released (Zähler)} statt Java

# ---------- Auswertung (rein) ----------
static func parse(raw: String, game_port := NetProtocol.GAME_PORT) -> Dictionary:
	# {kind, …}:
	#   "wlan":    address, port       (http://<private IP>[:Port]/[?p=Spielport] – Einladungsseite; draw2race://join?h=&p=)
	#   "wifi":    ssid, password, security (wpa2|wpa3|open), hidden   (WIFI:S:…;T:WPA;P:…;;)
	#   "invalid": error (erkannt, aber unbrauchbar)      "unknown": error (kein Code dieses Spiels)
	var t := raw.strip_edges()
	if t == "" or t.length() > MAX_TEXT:
		return _unknown()
	var low := t.to_lower()
	if low.begins_with("wifi:"):
		return parse_wifi(t)
	if low.begins_with(NetAndroid.APP_LINK_SCHEME + "://"):
		var link := NetAndroid.parse_app_link(t)
		if not bool(link.get("ok", false)):
			return {"kind": "invalid", "error": str(link.get("error", ""))}
		return {"kind": "wlan", "address": str(link.address), "port": int(link.port)}
	if low.begins_with("http://") or low.begins_with("https://"):
		return _parse_invite(t, game_port)
	return _unknown()

static func _unknown() -> Dictionary:
	return {"kind": "unknown", "error": "Das ist kein QR-Code von Draw2Race. Scanne einen der beiden Codes auf dem Handy des Gastgebers."}

static func _parse_invite(t: String, game_port: int) -> Dictionary:
	# http://10.94.17.1:24683/ bzw. …/?p=24790 (Einladungsseite des Gastgebers). Der Port in der Adresse gehört zur Seite, beigetreten
	# wird am Spielport (fest, nur in Tests über ?p= abweichend). Groß/Klein egal.
	var rest := t.substr(t.find("://") + 3)
	var query := ""
	var q := rest.find("?")
	if q >= 0:
		query = rest.substr(q + 1).get_slice("#", 0)
	for cut in ["/", "?", "#"]:
		var i := rest.find(cut)
		if i >= 0:
			rest = rest.left(i)
	var host := rest.get_slice(":", 0)
	var port := game_port
	for pair in query.split("&", false):
		if pair.to_lower().begins_with("p="):
			var p := pair.substr(2)
			if not p.is_valid_int() or int(p) < 1 or int(p) > 65535:
				return {"kind": "invalid", "error": "Der Link zum Spiel ist unvollständig. Scanne den QR-Code beim Gastgeber noch einmal."}
			port = int(p)
	if NetAndroid.private_ipv4(host) or host == "127.0.0.1":
		return {"kind": "wlan", "address": host, "port": port}
	return {"kind": "unknown", "error": "Dieser Link führt nicht zu einem Spiel in deiner Nähe. Scanne den QR-Code auf dem Handy des Gastgebers."}

static func parse_wifi(t: String) -> Dictionary:
	# WLAN-QR (ZXing-Format): WIFI:T:WPA;S:<ssid>;P:<passwort>;H:true;; – Felder in beliebiger Reihenfolge, Schlüssel groß oder klein,
	# \ ; , : " mit Backslash geschützt; ein Wert in Anführungszeichen (ältere Erzeuger) wird ausgepackt.
	var bad := {"kind": "invalid", "error": "Dieser WLAN-Code ist unvollständig. Lass den Gastgeber das Spiel-WLAN neu öffnen und scanne noch einmal."}
	var body := t.substr(5)
	var fields := {}
	var key := ""
	var value := ""
	var in_value := false
	var esc := false
	for ch in body:
		if esc:
			if in_value:
				value += ch
			else:
				key += ch
			esc = false
		elif ch == "\\":
			esc = true
		elif ch == ";":
			if key.strip_edges() != "":
				fields[key.strip_edges().to_upper()] = value
			key = ""
			value = ""
			in_value = false
		elif ch == ":" and not in_value:
			in_value = true
		elif in_value:
			value += ch
		else:
			key += ch
	if esc:
		return bad
	if key.strip_edges() != "":
		fields[key.strip_edges().to_upper()] = value
	var ssid := _unquote(str(fields.get("S", "")))
	var password := _unquote(str(fields.get("P", "")))
	var type := str(fields.get("T", "")).strip_edges().to_upper()
	if ssid == "" or ssid.to_utf8_buffer().size() > 32:
		return bad
	var security := ""
	match type:
		"WPA", "WPA2", "WPA/WPA2", "WPA2/WPA3":
			security = "wpa2"
		"SAE", "WPA3":
			security = "wpa3"
		"NOPASS", "NONE", "OPEN":
			security = "open"
		"":
			security = "wpa2" if password != "" else "open"
		"WEP":
			return {"kind": "invalid", "error": "Dieses WLAN nutzt eine veraltete Verschlüsselung (WEP). Verbinde dich bitte in den WLAN-Einstellungen."}
		_:
			return bad
	if security == "open":
		password = ""
	elif password.length() < 8 or password.length() > 64:
		return bad
	var hidden := str(fields.get("H", "")).strip_edges().to_lower() == "true"
	return {"kind": "wifi", "ssid": ssid, "password": password, "security": security, "hidden": hidden}

static func _unquote(v: String) -> String:
	if v.length() >= 2 and v.begins_with("\"") and v.ends_with("\""):
		return v.substr(1, v.length() - 2)
	return v

# ---------- Java-Anbindung ----------
static func _java(cls: String) -> Array:
	if OS.get_name() != "Android" or not Engine.has_singleton("AndroidRuntime"):
		return []
	var activity = Engine.get_singleton("AndroidRuntime").getActivity()
	var java = JavaClassWrapper.wrap("com.godot.game." + cls)
	return [java, activity] if java != null and activity != null else []

static func scan_available() -> bool:
	if scan_stub is Dictionary:
		return bool(scan_stub.get("available", true))
	var j := _java("QrScan")
	return not j.is_empty() and bool(j[0].available(j[1]))

static func scan_start() -> String:
	# "" = Scanner geöffnet (Ergebnis über scan_take), sonst Fehlercode: no_gms | busy | exception | android
	if scan_stub is Dictionary:
		return str(scan_stub.get("start_error", "")) if scan_available() else "no_gms"
	var j := _java("QrScan")
	if j.is_empty():
		return "android"
	return str(j[0].start(j[1]))

static func scan_take() -> Dictionary:
	# {status: idle|scanning|done|cancelled|failed, text, error, source}; ein über adb eingespeister Text (source "intent", Extra
	# d2r_scan) älter als 2 min zählt nicht.
	var r := {}
	if scan_stub is Dictionary:
		var list: Array = scan_stub.get("results", [])
		r = list.pop_front() if not list.is_empty() else {"status": "idle"}
	else:
		var j := _java("QrScan")
		if j.is_empty():
			return {"status": "idle"}
		var data = JSON.parse_string(str(j[0].take()))
		r = data if data is Dictionary else {"status": "idle"}
	if str(r.get("source", "")) == "intent" and float(r.get("now", 0)) - float(r.get("at", 0)) > INJECT_MAX_AGE_MS:
		return {"status": "idle"}
	return r

static func scan_error_text(code: String) -> String:
	match code:
		"cancelled", "busy", "":
			return ""
		"no_gms", "android":
			return "Der QR-Scanner braucht die Google-Play-Dienste, die es hier nicht gibt. Tritt über die Liste oder „Adresse eingeben“ bei."
		"module":
			return "Der Scanner wird gerade von Google geladen. Versuch es in einem Moment noch einmal."
	return "Der Scanner ließ sich nicht öffnen. Tritt über die Liste oder „Adresse eingeben“ bei."

static func wifi_supported() -> bool:
	# WifiNetworkSpecifier gibt es ab Android 10 (SDK 29).
	if wifi_stub is Dictionary:
		return int(wifi_stub.get("sdk", 34)) >= 29
	return not _java("QrWifi").is_empty() and int(NetAndroid.state().get("sdk", 0)) >= 29

static func _wifi_request(ssid: String, password: String, security: String) -> String:
	# "" = Anfrage läuft (Systemdialog), sonst Fehlercode old_android | exception | android
	if wifi_stub is Dictionary:
		var err := str(wifi_stub.get("connect_error", "")) if wifi_supported() else "old_android"
		if err == "":
			wifi_stub["state"] = {"status": "connecting", "ssid": ssid}     # wie QrWifi.request: sofort „connecting“
		return err
	var j := _java("QrWifi")
	return "android" if j.is_empty() else str(j[0].request(j[1], ssid, password, security))   # nicht „connect“ (Object.connect)

static func wifi_state() -> Dictionary:
	# {status: idle|connecting|available|unavailable|lost, ssid, handle, gateway, address}
	if wifi_stub is Dictionary:
		var st: Variant = wifi_stub.get("state", {})
		return (st as Dictionary).duplicate() if st is Dictionary else {}
	var j := _java("QrWifi")
	if j.is_empty():
		return {"status": "idle"}
	var data = JSON.parse_string(str(j[0].state(j[1])))
	return data if data is Dictionary else {"status": "idle"}

static func _wifi_bind() -> String:
	# Prozess an das Spiel-WLAN binden. "" = gebunden, sonst Grund.
	if wifi_stub is Dictionary:
		return str(wifi_stub.get("bind_error", ""))
	var j := _java("QrWifi")
	return "Nur auf Android möglich." if j.is_empty() else str(j[0].bind(j[1]))

static func _wifi_release() -> bool:
	if wifi_stub is Dictionary:
		var was := str((wifi_stub.get("state", {}) as Dictionary).get("status", "idle")) != "idle"
		wifi_stub["released"] = int(wifi_stub.get("released", 0)) + 1
		wifi_stub["state"] = {"status": "idle"}
		return was
	var j := _java("QrWifi")
	return not j.is_empty() and bool(j[0].release(j[1]))

static func wifi_status_text(st: Dictionary, ssid: String) -> String:
	match str(st.get("status", "")):
		"connecting":
			return "Verbinde mit dem Spiel-WLAN „%s“ … Bestätige die Anfrage von Android." % ssid
		"available":
			return "Im Spiel-WLAN „%s“ – suche das Spiel …" % ssid
		"unavailable":
			return "Keine Verbindung zum Spiel-WLAN „%s“. Ist es beim Gastgeber noch offen und bist du in der Nähe? Scanne noch einmal." % ssid
		"lost":
			return "Das Spiel-WLAN „%s“ ist weg. Scanne den WLAN-Code noch einmal." % ssid
	return ""

static func old_android_text(ssid: String, password: String) -> String:
	if password == "":
		return "Verbinde dich in den WLAN-Einstellungen mit „%s“ und komm dann hierher zurück – das Spiel erscheint in der Liste." % ssid
	return "Verbinde dich in den WLAN-Einstellungen mit „%s“ (Passwort: %s) und komm dann hierher zurück – das Spiel erscheint in der Liste." % [ssid, password]

# ---------- Ablauf (gehört NetLobby) ----------
var lobby: NetLobby
var text := ""                  # Statuszeile für den WLAN-Bildschirm ("" = keine)
var warn := false               # Statuszeile als Warnung (Fehler, Hinweis)
var scanning := false           # Scanner ist offen
var pinned := false             # Spiel-WLAN aus dem QR-Code ist da: Suche und Beitritt binden daran
var _wait := {}                 # Spiel-WLAN aus dem QR-Code wird verbunden: {ssid}
var _active := false            # Anfrage ans Spiel-WLAN läuft (bis release)
var _ssid := ""
var _next_scan_ms := 0
var _next_wifi_ms := 0
var _next_lost_ms := 0

func _init(owner: NetLobby) -> void:
	lobby = owner

func active() -> bool:
	return _active

func _say(t: String, is_warn := false) -> void:
	if t != text or is_warn != warn:
		text = t
		warn = is_warn
		changed.emit()

func scan() -> void:
	# Knopf „QR-Code scannen“.
	_say("")
	if not scan_available():
		_say(scan_error_text("no_gms"), true)
		return
	var err := scan_start()
	if err != "":
		lobby._log("QR-Scanner: nicht geöffnet (%s)" % err)
		_say(scan_error_text(err), true)
		return
	scanning = true
	_next_scan_ms = 0

func handle(raw: String) -> void:
	# Gescannten Text auswerten und beitreten (bzw. erst ins Spiel-WLAN).
	var r := parse(raw, lobby.game_port)
	lobby._log("QR-Code gescannt: %s" % str(r.kind))
	match str(r.kind):
		"wlan":
			_say("")
			join_ready.emit(str(r.address), int(r.port), str(r.address))
		"wifi":
			join_wifi(str(r.ssid), str(r.password), str(r.security))
		_:
			_say(str(r.get("error", "")), true)

func join_wifi(ssid: String, password: String, security: String) -> void:
	# Spiel-WLAN aus dem WLAN-QR: verbinden (Systemdialog), dann binden und am Gateway beitreten (poll).
	release()
	if not wifi_supported():
		_say(old_android_text(ssid, password), true)
		return
	var err := _wifi_request(ssid, password, security)
	if err != "":
		lobby._log("Spiel-WLAN aus dem QR-Code: Anfrage nicht möglich (%s)" % err)
		_say(old_android_text(ssid, password) if err == "old_android" else wifi_status_text({"status": "unavailable"}, ssid), true)
		return
	_active = true
	_ssid = ssid
	_wait = {"ssid": ssid}
	_next_wifi_ms = 0
	lobby._log("Spiel-WLAN aus dem QR-Code: verbinde mit „%s“" % ssid)
	_say(wifi_status_text({"status": "connecting"}, ssid))

func release() -> bool:
	# Anfrage ans Spiel-WLAN zurückziehen (Android trennt es, das Handy kommt wieder ins normale WLAN). true = es lief eine.
	var was := _active
	_active = false
	pinned = false
	_wait = {}
	if was:
		was = _wifi_release() or was
		lobby._log("Spiel-WLAN aus dem QR-Code freigegeben („%s“)" % _ssid)
	return was

func bind() -> String:
	# NetLobby._bind: Prozess an das Spiel-WLAN aus dem QR-Code binden. "" = gebunden, sonst Grund.
	return _wifi_bind()

func poll(now := -1) -> void:
	if now < 0:
		now = Time.get_ticks_msec()
	# Scanner (und der Testeinstieg d2r_scan) nur auf dem WLAN-Bildschirm bzw. solange er offen ist.
	if (scanning or lobby.mode == "search") and now >= _next_scan_ms:
		_next_scan_ms = now + SCAN_POLL_MS
		var r := scan_take()
		match str(r.get("status", "idle")):
			"done":
				scanning = false
				handle(str(r.get("text", "")))
			"cancelled":
				scanning = false
			"failed":
				scanning = false
				lobby._log("QR-Scanner: Fehler „%s“" % str(r.get("error", "")))
				_say(scan_error_text(str(r.get("error", ""))), true)
	if not _wait.is_empty() and now >= _next_wifi_ms:
		_next_wifi_ms = now + WIFI_POLL_MS
		_poll_wifi()
	elif pinned and now >= _next_lost_ms:
		_next_lost_ms = now + LOST_CHECK_MS
		if str(wifi_state().get("status", "")) in ["lost", "unavailable"]:
			lobby._log("Spiel-WLAN aus dem QR-Code verloren – gebe es frei")
			var ssid := _ssid
			release()
			_say(wifi_status_text({"status": "lost"}, ssid), true)
			if lobby.mode == "search":
				lobby.search()            # wieder ans normale WLAN binden

func _poll_wifi() -> void:
	var ssid := str(_wait.get("ssid", ""))
	var st := wifi_state()
	match str(st.get("status", "")):
		"available":
			_wait = {}
			pinned = true
			var gateway := str(st.get("gateway", ""))
			lobby._log("Spiel-WLAN aus dem QR-Code verbunden: „%s“, Adresse %s, Gateway %s" % [ssid, str(st.get("address", "")), gateway])
			lobby.search()                # Such-Sockets neu, jetzt im Spiel-WLAN (NetLobby._bind → bind())
			_say(wifi_status_text(st, ssid))
			if NetProtocol.ipv4_to_int(gateway) > 0:
				join_ready.emit(gateway, lobby.game_port, ssid)   # im Spiel-WLAN ist das Handy des Gastgebers das Gateway
		"unavailable", "lost", "idle":
			_wait = {}
			lobby._log("Spiel-WLAN aus dem QR-Code: keine Verbindung (%s)" % str(st.get("status", "")))
			_say(wifi_status_text(st, ssid) if str(st.get("status", "")) != "idle" else wifi_status_text({"status": "unavailable"}, ssid), true)
			release()
