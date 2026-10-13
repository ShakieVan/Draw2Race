extends SceneTree

# Mitspieler einladen (Beta 1.0.2, Nutzerwunsch 13.10.2026, Vorbild Mau-Mau Flip): Spiel-WLAN, WLAN- und Spiel-QR, Einladungsseite,
# Beitreten per QR-Code und App-Link.
#   1. Reine Regeln: WLAN-QR-Text, Einladungsadresse, App-Link, Auswertung gescannter Codes (QrJoin.parse), Texte zu Fehlercodes,
#      Netzart (NetInvite.detect_mode), Adresse im Spiel-WLAN, Einladungsseite (NetApk.page_html, invite_route, host_header, nearby).
#   2. Einladungsseite über HTTP (127.0.0.1, eigener Testport): Seite, Download vor und nach der Vorbereitung, HEAD, favicon, Zähler,
#      die Weitergabe-Adresse zwischen zwei Apps unverändert, ohne Seite kein „/“.
#   3. Gastgeber (NetLobby, Android-Ersatz, NetAndroid.wifi_stub): Spiel-WLAN öffnen → Name, Passwort, Adresse, QR-Texte; die Sockets
#      werden ungebunden neu angelegt (Hotspot-Regel); Schritte (Seite aufgerufen, Mitspieler da, alle weg); Erlaubnis verweigert,
#      normaler Hotspot läuft, kein Funkkanal, Android beendet es; Schließen; Verlassen schließt es.
#   4. Mitspieler (QrJoin mit scan_stub/wifi_stub): Spiel-QR → beitreten; WLAN-QR → verbinden, an das Spiel-WLAN binden (auch bei
#      WLAN-Wechselmeldungen nicht zurück ans Heim-WLAN), am Gateway beitreten; verloren → freigeben, wieder ans WLAN; Verlassen gibt
#      frei; alter eingespeister Text zählt nicht; Android 9 und ohne Google-Dienste: Hinweise.
#   5. Oberfläche (main.tscn): WLAN-Bildschirm mit „QR-Code scannen“ → Beitritt; App-Link im Menü → Beitritt; Gastgeber-Lobby →
#      „Mitspieler einladen“ → Panel mit ① und ②, Spiel-WLAN öffnen, Fertig (bleibt offen), schließen; Verlassen schließt es.
# Testports 24820–24824 (Spiel, Suche, Ankündigung, Dateidienst der Lobby, Dateidienst allein).
const PORT := 24820
const APK_PORT := 24823
const RAW_PORT := 24824
const TEST_OVERRIDES := {"game_port": PORT, "discovery_port": PORT + 1, "beacon_port": PORT + 2, "apk_port": APK_PORT, "probe_local": true,
	"use_broadcast": false, "use_binding": false, "log_path": "", "auto_poll": false, "peer_timeout": [32, 600, 1500], "load_timeout": [32, 600, 1500]}
const TRACKS := ["azure", "city", "forest", "harbor", "serra", "fair", "quarry", "arena", "kids"]
const HOME := {"handle": "100", "transport": "wifi", "iface": "wlan0", "addresses": ["192.0.2.20/24"], "gateway": "192.0.2.1", "internet": true,
	"validated": true, "default": true}
const GAME_WIFI := {"ssid": "AndroidShare_7k2m", "password": "q9w3e7r2t5y8u4i", "security": "wpa2", "address": "10.94.17.1", "sdk": 34}
const SPOT := {"name": "swlan0", "address": "10.94.17.1", "prefix": 24}
var failures := 0
var checks := 0
var lobbies: Array = []
var ui_app: Node
var _tick := 0

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
	test_page_rules()
	test_http()
	test_host()
	test_guest()
	await test_ui()
	NetLobby.overrides = {}
	NetAndroid.wifi_stub = null
	QrJoin.scan_stub = null
	QrJoin.wifi_stub = null
	for lb in lobbies:
		if is_instance_valid(lb):
			lb.exit()
			lb.free()
	print("RESULT: ", checks - failures, "/", checks, " passed")
	quit(1 if failures else 0)

# ---------- Hilfen ----------
class FakeAndroid extends RefCounted:
	# Android-Ersatz wie in test_lobby: Netze mit Handle, eigene Hotspot-Schnittstellen (hotspot), Bindung.
	var nets: Array = []
	var hotspot: Array = []
	var bound_net := {}
	var binds := 0
	var unbinds := 0
	func available() -> bool:
		return true
	func multicast(_on: bool) -> bool:
		return true
	func is_bound() -> bool:
		return not bound_net.is_empty()
	func state() -> Dictionary:
		var list: Array = []
		var ifaces: Array = hotspot.duplicate()
		for n in nets:
			list.append((n as Dictionary).merged({"bound": str(n.handle) == str(bound_net.get("handle", ""))}, true))
			for addr in n.addresses:
				ifaces.append({"name": str(n.get("iface", "wlan0")), "address": str(addr).get_slice("/", 0), "prefix": int(str(addr).get_slice("/", 1))})
		var b = null
		if not bound_net.is_empty():
			b = {"handle": bound_net.handle, "transport": "?", "addresses": [], "gateway": ""}
			for n in nets:
				if str(n.handle) == str(bound_net.handle):
					b = (n as Dictionary).duplicate()
		return {"android": true, "networks": list, "bound": b, "interfaces": ifaces, "dhcp_gateway": "", "wifi_gateway": ""}
	func bind_wifi() -> String:
		binds += 1
		var handle := NetAndroid.wifi_handle(state())
		for n in nets:
			if str(n.handle) == handle:
				bound_net = (n as Dictionary).duplicate()
				return ""
		return "Kein WLAN verbunden."
	func bind_network(handle: String) -> String:
		binds += 1
		for n in nets:
			if str(n.handle) == handle:
				bound_net = (n as Dictionary).duplicate()
				return ""
		return "Das WLAN ist nicht mehr verbunden."
	func unbind() -> bool:
		unbinds += 1
		bound_net = {}
		return true

func make(player_name: String, extra := {}) -> NetLobby:
	var saved: Dictionary = NetLobby.overrides
	NetLobby.overrides = TEST_OVERRIDES.merged(extra, true)
	var lb := NetLobby.new()
	NetLobby.overrides = saved
	lb.tracks = TRACKS.duplicate()
	root.add_child(lb)
	lb.enter(player_name, 0)
	lobbies.append(lb)
	return lb

func dispose(lb) -> void:
	if is_instance_valid(lb):
		lb.exit()
		lobbies.erase(lb)
		lb.free()

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

func later() -> int:
	# Zeitpunkt für poll(now) jenseits aller Abfrage-Abstände (die Abläufe fragen sonst höchstens alle 0,25–2 s nach).
	_tick += 10000
	return Time.get_ticks_msec() + _tick

func http(port: int, method: String, path: String, host := "127.0.0.1") -> Dictionary:
	# Kleine HTTP/1.1-Anfrage an 127.0.0.1 (blockierend, höchstens 6 s): {code, head, body}; liest bis Content-Length.
	var peer := StreamPeerTCP.new()
	if peer.connect_to_host("127.0.0.1", port) != OK:
		return {"code": -1, "head": "", "body": PackedByteArray()}
	var end := Time.get_ticks_msec() + 6000
	while peer.get_status() == StreamPeerTCP.STATUS_CONNECTING and Time.get_ticks_msec() < end:
		peer.poll()
		OS.delay_msec(2)
	peer.put_data(("%s %s HTTP/1.1\r\nHost: %s:%d\r\nUser-Agent: Test\r\nConnection: close\r\n\r\n" % [method, path, host, port]).to_ascii_buffer())
	var buf := PackedByteArray()
	var head := ""
	var body_at := -1
	var length := -1
	while Time.get_ticks_msec() < end:
		peer.poll()
		var n := peer.get_available_bytes()
		if n > 0:
			buf.append_array(peer.get_partial_data(n)[1])
			if body_at < 0:
				for i in range(maxi(0, buf.size() - 3)):
					if buf[i] == 13 and buf[i + 1] == 10 and buf[i + 2] == 13 and buf[i + 3] == 10:
						body_at = i + 4
						head = buf.slice(0, i).get_string_from_ascii()
						for line in head.split("\r\n"):
							if line.to_lower().begins_with("content-length:"):
								length = int(line.substr(15).strip_edges())
						break
			if body_at >= 0 and (method == "HEAD" or (length >= 0 and buf.size() - body_at >= length)):
				break
		elif peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			break
		else:
			OS.delay_msec(2)
	peer.disconnect_from_host()
	var code := int(head.get_slice(" ", 1)) if head != "" else -1
	return {"code": code, "head": head, "body": buf.slice(body_at) if body_at >= 0 else PackedByteArray()}

# ---------- 1. Reine Regeln ----------
func test_rules() -> void:
	check(NetAndroid.wifi_qr_text("AndroidShare_7k2m", "q9w3e7r2t5y8u4i") == "WIFI:T:WPA;S:AndroidShare_7k2m;P:q9w3e7r2t5y8u4i;;"
		and NetAndroid.wifi_qr_text("Offen", "", "open") == "WIFI:T:nopass;S:Offen;;"
		and NetAndroid.wifi_qr_text("a;b", "c:d,e\\f\"g") == "WIFI:T:WPA;S:a\\;b;P:c\\:d\\,e\\\\f\\\"g;;"
		and NetAndroid.wifi_qr_text("WPA3", "geheim123", "wpa3").begins_with("WIFI:T:WPA;"),
		"WLAN-QR: WPA (auch bei WPA3), offen ohne Passwort, Sonderzeichen mit Backslash geschützt")
	check(NetAndroid.invite_url("10.94.17.1", 24683) == "http://10.94.17.1:24683/" and NetAndroid.invite_url("10.94.17.1", 24683, 24790) == "http://10.94.17.1:24683/?p=24790"
		and NetAndroid.invite_url("", 24683) == "", "Spiel-QR: Einladungsseite, Spielport nur, wenn er vom festen abweicht")
	check(NetAndroid.app_link_url("10.94.17.1", 24680) == "draw2race://join?h=10.94.17.1&p=24680", "App-Link")
	var intent := NetAndroid.app_intent_url("10.94.17.1", 24680, "http://10.94.17.1:24683/?ohne-app")
	check(intent.begins_with("intent://join?h=10.94.17.1&p=24680#Intent;scheme=draw2race;package=de.draw2race.game;S.browser_fallback_url=http")
		and intent.ends_with(";end") and not intent.contains("://10.94.17.1:24683/?ohne-app"), "Browser-Link (intent://) mit Paket und verschlüsselter Rückfallseite: %s" % intent)
	var ok := NetAndroid.parse_app_link("draw2race://join?h=10.94.17.1&p=24680")
	var no_port := NetAndroid.parse_app_link("DRAW2RACE://join/?h=192.168.1.5#x")
	var public := NetAndroid.parse_app_link("draw2race://join?h=8.8.8.8&p=24680")
	var bad_port := NetAndroid.parse_app_link("draw2race://join?h=10.0.0.2&p=70000")
	check(ok.ok and ok.address == "10.94.17.1" and ok.port == 24680 and no_port.ok and no_port.port == NetProtocol.GAME_PORT
		and not public.ok and str(public.error).contains("nicht zu einem Spiel in deiner Nähe") and not bad_port.ok
		and not NetAndroid.parse_app_link("maumauflip://join?h=10.0.0.2&p=1").ok and not NetAndroid.parse_app_link("draw2race://join").ok,
		"App-Link lesen: Adresse und Port, ohne Port der feste, fremde Netze, kaputte Ports und fremde Schemata abgelehnt")
	check(NetAndroid.private_ipv4("10.1.2.3") and NetAndroid.private_ipv4("172.31.0.1") and NetAndroid.private_ipv4("192.168.0.1")
		and not NetAndroid.private_ipv4("172.32.0.1") and not NetAndroid.private_ipv4("8.8.8.8") and not NetAndroid.private_ipv4("10.1.2")
		and not NetAndroid.private_ipv4("10.1.2.300"), "Private IPv4-Netze")
	# Gescannte Codes
	var w := QrJoin.parse("WIFI:S:AndroidShare_7k2m;T:WPA;P:q9w3e7r2t5y8u4i;H:false;;")
	var w3 := QrJoin.parse("wifi:t:SAE;s:\"Spiel\";p:\"geheim123\";;")
	var open := QrJoin.parse("WIFI:T:nopass;S:Offen;;")
	check(w.kind == "wifi" and w.ssid == "AndroidShare_7k2m" and w.password == "q9w3e7r2t5y8u4i" and w.security == "wpa2" and not w.hidden
		and w3.kind == "wifi" and w3.security == "wpa3" and w3.ssid == "Spiel" and w3.password == "geheim123"
		and open.kind == "wifi" and open.security == "open" and open.password == "",
		"WLAN-QR lesen: Reihenfolge, Groß/Klein, Anführungszeichen, WPA3, offen")
	check(QrJoin.parse("WIFI:T:WPA;S:X;P:kurz;;").kind == "invalid" and QrJoin.parse("WIFI:T:WEP;S:X;P:12345678;;").kind == "invalid"
		and QrJoin.parse("WIFI:T:WPA;P:12345678;;").kind == "invalid", "WLAN-QR: zu kurzes Passwort, WEP und fehlender Name abgelehnt")
	var inv := QrJoin.parse("http://10.94.17.1:24683/")
	var inv_p := QrJoin.parse("HTTP://192.168.43.1:24683/?p=24790")
	var link := QrJoin.parse("draw2race://join?h=10.94.17.1&p=24680")
	check(inv.kind == "wlan" and inv.address == "10.94.17.1" and inv.port == NetProtocol.GAME_PORT and inv_p.kind == "wlan" and inv_p.port == 24790
		and link.kind == "wlan" and link.port == 24680, "Spiel-QR und App-Link: beitreten am Spielport (der Port der Seite zählt nicht)")
	check(QrJoin.parse("https://example.com/").kind == "unknown" and QrJoin.parse("Hallo").kind == "unknown" and str(QrJoin.parse("Hallo").error).contains("kein QR-Code von Draw2Race")
		and QrJoin.parse("http://10.0.0.1:24683/?p=0").kind == "invalid" and QrJoin.parse("draw2race://join?h=8.8.8.8").kind == "invalid"
		and QrJoin.parse("").kind == "unknown", "Fremde Codes, fremde Netze und kaputte Ports: klare Meldung")
	# Texte zu den Fehlercodes des Spiel-WLANs
	for code in ["permission", "location_off", "incompatible_mode", "ap_running", "no_channel", "tethering_disallowed", "unsupported", "generic", "exception"]:
		var m := NetAndroid.game_wifi_message({"status": "failed", "error": code, "sdk": 34})
		check(str(m.title) != "" and str(m.text) != "" and not str(m.text).contains("I18n"), "Meldung „%s“: %s" % [code, m.title])
	check(str(NetAndroid.game_wifi_message({"status": "failed", "error": "permission", "sdk": 31}).text).contains("Standort")
		and str(NetAndroid.game_wifi_message({"status": "failed", "error": "permission", "sdk": 34}).text).contains("Geräte in der Nähe")
		and NetAndroid.game_wifi_message({"status": "stopped"}).retry and not NetAndroid.game_wifi_message({"status": "failed", "error": "tethering_disallowed"}).retry,
		"Erlaubnis: bis Android 12 Standort, ab 13 „Geräte in der Nähe“; Neu öffnen nur, wo es hilft")
	# Netzart und Adresse
	var none := {"android": true, "networks": [], "interfaces": []}
	var home := {"android": true, "networks": [HOME], "interfaces": [{"name": "wlan0", "address": "192.0.2.20", "prefix": 24}]}
	var spot := {"android": true, "networks": [], "interfaces": [SPOT]}
	check(NetInvite.detect_mode(none, {"status": "off"}, "") == "none" and NetInvite.detect_mode(home, {"status": "off"}, "") == "wlan"
		and NetInvite.detect_mode(spot, {"status": "off"}, "") == "hotspot" and NetInvite.detect_mode(home, {"status": "off", "ap_enabled": 1}, "") == "hotspot"
		and NetInvite.detect_mode(home, {"status": "on"}, "") == "game_wifi" and NetInvite.detect_mode(none, {"status": "starting"}, "") == "starting"
		and NetInvite.detect_mode(home, {"status": "on"}, "permission") == "problem"
		and NetInvite.detect_mode({"android": false, "interfaces": [{"address": "192.0.2.7"}]}, {}, "") == "wlan",
		"Netzart: kein Netz, WLAN, eigener bzw. normaler Hotspot, Spiel-WLAN offen bzw. im Aufbau, Problem, PC")
	var both := {"android": true, "networks": [HOME], "interfaces": [{"name": "wlan0", "address": "192.0.2.20", "prefix": 24},
		{"name": "swlan0", "address": "192.168.43.1", "prefix": 24}, SPOT]}
	check(NetAndroid.game_wifi_address(both, ["192.168.43.1"]) == "10.94.17.1" and NetAndroid.game_wifi_address(both) == "192.168.43.1"
		and NetAndroid.game_wifi_address(home) == "", "Adresse im Spiel-WLAN: die neu erschienene Hotspot-Schnittstelle (nie 192.168 annehmen)")

func test_page_rules() -> void:
	var info := {"name": "<Rita & Co>", "version": "1.0.2", "address": "10.94.17.1", "game_port": 24680, "apk": true, "size": 312638820, "prepare": ""}
	var page := NetApk.page_html(info, "10.94.17.1", 24683, true)
	check(page.contains("&lt;Rita &amp; Co&gt;") and not page.contains("<Rita"), "Seite: Name des Gastgebers sicher eingesetzt")
	check(page.contains("href=\"intent://join?h=10.94.17.1&amp;p=24680#Intent;scheme=draw2race;package=de.draw2race.game;S.browser_fallback_url=")
		and page.contains("In Draw2Race öffnen"), "Seite: „In Draw2Race öffnen“ (App-Link mit Rückfall auf die Seite)")
	check(page.contains("href=\"/Draw2Race-1.0.2.apk\"") and page.contains("298 MB") and page.contains("Trotzdem herunterladen")
		and page.contains("mobile Daten kurz ausschalten") and not page.contains("http-equiv=\"refresh\""),
		"Seite mit fertiger Datei: Download-Knopf mit Größe, Installationsschritte, Hinweis auf mobile Daten, kein Neuladen")
	var prep := NetApk.page_html(info.merged({"prepare": "40 %"}, true), "10.94.17.1", 24683, false)
	check(prep.contains("http-equiv=\"refresh\"") and prep.contains("vorbereitet (40 %)") and not prep.contains(".apk\""),
		"Seite während der Vorbereitung: Fortschritt, lädt sich neu, noch kein Download")
	var none := NetApk.page_html(info.merged({"apk": false}, true), "10.94.17.1", 24683, false, "ohne-app")
	check(none.contains("noch nicht installiert") and none.contains("github.com/ShakieVan/Draw2Race") and not none.contains("refresh"),
		"Seite ohne App-Datei (PC): Verweis auf GitHub; nach erfolglosem App-Link: „noch nicht installiert“")
	check(NetApk.invite_route("/", "1.0.2") == "page" and NetApk.invite_route("/?ohne-app", "1.0.2") == "page" and NetApk.invite_route("/index.html", "1.0.2") == "page"
		and NetApk.invite_route("/Draw2Race-1.0.2.apk", "1.0.2") == "download" and NetApk.invite_route("/Draw2Race-1.0.1.apk", "1.0.2") == ""
		and NetApk.invite_route("/favicon.ico", "1.0.2") == "icon" and NetApk.invite_route("/draw2race-%s.apk" % "a".repeat(64), "1.0.2") == "",
		"Wege der Einladung: Seite, Download der eigenen Version, favicon – die Weitergabe-Adresse gehört nicht dazu")
	check(NetApk.host_header("GET / HTTP/1.1\r\nhost: 10.94.17.1:24683\r\nAccept: */*") == "10.94.17.1" and NetApk.host_header("GET / HTTP/1.1\r\nHost: [fe80::1]:24683") == ""
		and NetApk.host_header("GET / HTTP/1.1") == "", "Host-Kopfzeile ohne Port (IPv6 nicht als App-Link-Adresse)")
	check(NetApk.nearby("127.0.0.1") and NetApk.nearby("10.94.17.20") and not NetApk.nearby("8.8.8.8") and NetApk.peer_ip("::ffff:10.94.17.20") == "10.94.17.20"
		and not NetApk.nearby(NetApk.peer_ip("2001:db8::1")), "Seite und Datei nur für Geräte in der Nähe (private Netze, 127.0.0.1)")

# ---------- 2. Einladungsseite über HTTP ----------
func test_http() -> void:
	var t := NetApk.new()
	check(t.serve(RAW_PORT) == OK, "Dateidienst läuft (Port %d)" % RAW_PORT)
	var r := http(RAW_PORT, "GET", "/")
	check(r.code == 503, "Ohne Seite: „/“ gehört nicht zur Einladung (wie bisher 503, solange keine Datei bereitsteht)")
	t.set_page({"name": "Rita", "version": "1.0.2", "address": "10.94.17.1", "game_port": 24680, "apk": true, "size": 0, "prepare": "12 %"})
	r = http(RAW_PORT, "GET", "/", "10.94.17.1")
	var body: String = r.body.get_string_from_utf8()
	check(r.code == 200 and str(r.head).contains("text/html; charset=utf-8") and body.contains("Rita lädt dich") and body.contains("vorbereitet (12 %)")
		and body.contains("intent://join?h=10.94.17.1&amp;p=24680"), "Seite: 200, HTML, App-Link mit der Adresse aus der Anfrage, Vorbereitung")
	r = http(RAW_PORT, "GET", "/", "192.168.178.29")
	check(r.body.get_string_from_utf8().contains("intent://join?h=192.168.178.29&amp;"), "App-Link folgt der Adresse, die der Browser benutzt hat")
	r = http(RAW_PORT, "GET", "/", "draw2race.local")
	check(r.body.get_string_from_utf8().contains("intent://join?h=10.94.17.1&amp;"), "Unbrauchbare Host-Angabe: eigene Adresse aus den Seitenangaben")
	r = http(RAW_PORT, "GET", "/Draw2Race-1.0.2.apk")
	check(r.code == 303 and str(r.head).contains("Location: /"), "Download vor der Vorbereitung: zurück zur Seite (303)")
	check(http(RAW_PORT, "GET", "/favicon.ico").code == 404 and http(RAW_PORT, "POST", "/").code == 400, "favicon 404, POST 400")
	# Datei bereitstellen (wie set_file nach der Kopie der APK)
	var path := "user://test_invite_%d.apk" % Time.get_ticks_usec()
	var data := PackedByteArray()
	data.resize(300 * 1024 + 17)
	for i in data.size():
		data[i] = (i * 31 + 7) % 251
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(data)
	f.close()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data)
	var sha := ctx.finish().hex_encode()
	t.set_file(ProjectSettings.globalize_path(path), data.size(), sha)
	r = http(RAW_PORT, "GET", "/?ohne-app")
	body = r.body.get_string_from_utf8()
	check(r.code == 200 and body.contains("href=\"/Draw2Race-1.0.2.apk\"") and body.contains("noch nicht installiert") and not body.contains("refresh"),
		"Seite mit fertiger Datei: Download-Knopf, Hinweis nach erfolglosem App-Link")
	r = http(RAW_PORT, "HEAD", "/Draw2Race-1.0.2.apk")
	check(r.code == 200 and str(r.head).contains("Content-Length: %d" % data.size()) and r.body.is_empty(), "HEAD: nur Kopfzeilen mit Länge")
	r = http(RAW_PORT, "GET", "/Draw2Race-1.0.2.apk")
	check(r.code == 200 and str(r.head).contains("filename=\"Draw2Race-1.0.2.apk\"") and str(r.head).contains("application/vnd.android.package-archive")
		and r.body == data, "Download: ganze Datei, richtiger Name und Typ (%d Byte)" % r.body.size())
	r = http(RAW_PORT, "GET", "/draw2race-%s.apk" % sha)
	check(r.code == 200 and str(r.head).contains("filename=\"Draw2Race.apk\"") and r.body == data, "Weitergabe zwischen zwei Apps wie bisher (Adresse mit Prüfsumme)")
	check(http(RAW_PORT, "GET", "/draw2race-%s.apk" % "0".repeat(64)).code == 404, "Fremde Prüfsumme: 404 wie bisher")
	OS.delay_msec(50)
	var st := t.stats()
	check(int(st.pages) == 4 and int(st.downloads) == 1 and int(st.served) == 2, "Zähler: 4 Seitenaufrufe, 1 Download über die Seite, 2 vollständige Sendungen (%s)" % [st])
	t.set_page({})
	check(not t.page_on() and http(RAW_PORT, "GET", "/").code == 404 and http(RAW_PORT, "GET", "/Draw2Race-1.0.2.apk").code == 404,
		"Seite aus: „/“ und der Download sind weg, die Weitergabe bleibt")
	t.close()
	check(not t.serving() and not t.page_on(), "Dienst beendet, Seite gelöscht")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

# ---------- 3. Gastgeber ----------
func test_host() -> void:
	NetAndroid.wifi_stub = GAME_WIFI.duplicate()
	var fake := FakeAndroid.new()
	fake.nets = [HOME]
	var host := make("Chef", {"use_binding": true, "android_api": fake})
	check(host.host("azure", 0) == OK and host.bound and str(fake.bound_net.get("handle", "")) == "100", "Gastgeber im Heim-WLAN: ans WLAN gebunden")
	var inv := host.invite
	inv.open()
	host.refresh_status()
	inv.refresh(true)
	check(host.transfer.serving() and host.transfer.page_on() and inv.mode == "wlan" and inv.page_url() == "http://192.0.2.20:%d/?p=%d" % [APK_PORT, PORT]
		and inv.qr_text() == "" and inv.glow() == 1, "Panel offen: Einladungsseite läuft, Netzart WLAN, Spiel-QR mit der WLAN-Adresse, noch kein WLAN-QR, ① leuchtet")
	check(host._service_tied, "Der Dateidienst entstand, während der Gastgeber ans WLAN gebunden war")
	var enet = host.session.enet
	fake.hotspot = [SPOT]               # die Schnittstelle des Spiel-WLANs erscheint mit dem Start
	inv.open_wifi()
	inv.poll(later())
	check(inv.mode == "game_wifi" and inv.address == "10.94.17.1" and inv.qr_text() == "WIFI:T:WPA;S:AndroidShare_7k2m;P:q9w3e7r2t5y8u4i;;"
		and inv.page_url() == "http://10.94.17.1:%d/?p=%d" % [APK_PORT, PORT], "Spiel-WLAN offen: Name und Passwort im WLAN-QR, Spiel-QR mit der Adresse im Spiel-WLAN")
	check(fake.bound_net.is_empty() and host.session.enet != enet and host.status.reach == ["wlan", "hotspot"]
		and LobbyScreens.host_addresses(host.status, inv.address) == "Zum Eintippen: WLAN 192.0.2.20  ·  Spiel-WLAN 10.94.17.1",
		"Noch niemand da: Bindung gelöst, Sockets ungebunden neu – erreichbar im WLAN und im Spiel-WLAN (%s)" % LobbyScreens.host_addresses(host.status, inv.address))
	check(not host._service_tied and host.transfer.serving() and host.transfer.page_on(),
		"Gerätetest 13.10.: auch der Dateidienst ist ungebunden neu angelegt (sonst erreichten Gäste im Spiel-WLAN die Seite nicht), Seite wieder da")
	# ① ist geschafft, sobald jemand die Seite aufruft
	var r := http(APK_PORT, "GET", "/", "10.94.17.1")
	inv.poll(later())
	check(r.code == 200 and r.body.get_string_from_utf8().contains("Chef lädt dich") and inv.pages() == 1 and inv.step1_done() and inv.glow() == 2,
		"Seite aufgerufen: ① geschafft, ② leuchtet")
	var guest := make("Jo")
	guest.join("127.0.0.1", PORT)
	var ok := pump([host, guest], 3000, func(): return guest.is_joined and host.client_count() == 1)
	inv.poll(later())
	check(ok and inv.glow() == 0 and inv.step2_done(), "Mitspieler da: beide Schritte geschafft")
	guest.leave()
	ok = pump([host, guest], 3000, func(): return host.client_count() == 0)
	inv.poll(later())
	check(ok and inv.glow() == 1 and not inv.step1_done(), "Alle weg: es beginnt von vorn")
	dispose(guest)
	# „Fertig“ lässt es offen: dieselben Zugangsdaten beim nächsten Öffnen
	inv.open()
	check(inv.mode == "game_wifi" and str(inv.wifi.ssid) == "AndroidShare_7k2m", "Panel neu geöffnet: Spiel-WLAN noch offen, gleicher Name")
	inv.close_wifi()
	fake.hotspot = []
	inv.poll(later())
	check(inv.mode == "wlan" and inv.qr_text() == "" and inv.address == "" and str(NetAndroid.game_wifi_state().status) == "off", "Spiel-WLAN geschlossen: zurück zum WLAN")
	# Probleme
	NetAndroid.wifi_stub.granted = false
	inv.open_wifi()
	check(inv.mode == "problem" and inv.problem == "permission" and str(inv.message().title) == "Erlaubnis fehlt", "Erlaubnis verweigert: Hinweis „Erlaubnis fehlt“")
	inv.dismiss_problem()
	# Erlaubnis per Systemdialog: warten, dann erteilt → Start; ohne Antwort nach 60 s → „Erlaubnis fehlt“
	NetAndroid.wifi_stub.dialog = true
	inv.open_wifi()
	check(inv._waiting_permission and inv.mode == "starting" and inv.busy(), "Erlaubnisdialog offen: „wird geöffnet …“, Lobby fragt weiter nach")
	inv._next_poll_ms = 0
	inv.poll(Time.get_ticks_msec() + 1000)
	check(inv._waiting_permission and inv.mode == "starting", "Noch keine Antwort: wartet weiter")
	NetAndroid.wifi_stub.granted = true
	fake.hotspot = [SPOT]
	inv._next_poll_ms = 0
	inv.poll(Time.get_ticks_msec() + 2000)
	check(not inv._waiting_permission and inv.mode == "game_wifi", "Erlaubnis erteilt (auch ohne Rückmeldung erkannt): Spiel-WLAN geht auf")
	inv.close_wifi()
	fake.hotspot = []
	NetAndroid.wifi_stub.granted = false
	inv.open_wifi()
	inv._next_poll_ms = 0
	inv.poll(Time.get_ticks_msec() + NetInvite.PERMISSION_WAIT_MS + 1000)
	check(not inv._waiting_permission and inv.mode == "problem" and inv.problem == "permission", "Keine Antwort auf die Anfrage: nach 60 s „Erlaubnis fehlt“ statt endlos „wird geöffnet …“")
	inv.dismiss_problem()
	NetAndroid.wifi_stub.dialog = false
	NetAndroid.wifi_stub.granted = true
	inv._next_poll_ms = 0
	check(inv.mode == "wlan", "Zurück: wieder WLAN")
	NetAndroid.wifi_stub.ap_enabled = 1
	inv.poll(later())
	check(inv.mode == "hotspot", "Normaler Hotspot läuft: Netzart Hotspot")
	inv.open_wifi()
	check(inv.mode == "problem" and inv.problem == "ap_running" and str(inv.message().title) == "Dein Hotspot läuft", "Spiel-WLAN neben dem normalen Hotspot: klare Meldung")
	inv.dismiss_problem()
	NetAndroid.wifi_stub.ap_enabled = 0
	NetAndroid.wifi_stub.start_error = "no_channel"
	inv.open_wifi()
	inv.poll(later())
	check(inv.mode == "problem" and inv.problem == "no_channel" and bool(inv.message().retry), "Kein freier Kanal: Meldung mit „Neu öffnen“")
	NetAndroid.wifi_stub.start_error = ""
	inv.open_wifi()
	fake.hotspot = [SPOT]
	inv.poll(later())
	check(inv.mode == "game_wifi", "Neu öffnen klappt")
	NetAndroid.stub_stop_game_wifi()
	fake.hotspot = []
	inv.poll(later())
	check(inv.mode == "problem" and inv.problem == "stopped" and str(inv.message().title) == "Spiel-WLAN beendet" and inv.page_url() == "",
		"Android beendet das Spiel-WLAN: Meldung, kein Spiel-QR mehr")
	inv.open_wifi()
	fake.hotspot = [SPOT]
	inv.poll(later())
	host.exit()
	check(str(NetAndroid.game_wifi_state().status) == "off" and not host.transfer.serving() and not inv.active, "Verlassen des WLAN-Mehrspielers schließt Spiel-WLAN und Seite")
	dispose(host)
	NetAndroid.wifi_stub = null

# ---------- 4. Mitspieler ----------
func test_guest() -> void:
	QrJoin.scan_stub = {"available": true, "results": []}
	QrJoin.wifi_stub = {"sdk": 34, "state": {"status": "idle"}, "released": 0}
	var fake := FakeAndroid.new()
	fake.nets = [HOME]
	var g := make("Gast", {"use_binding": true, "android_api": fake})
	g.search()
	var binds := fake.binds
	var joins: Array = []
	g.qr.join_ready.connect(func(a, p, l): joins.append([a, p, l]))
	# Spiel-QR
	g.qr.scan()
	check(g.qr.scanning and g.qr.text == "", "Scanner offen")
	QrJoin.scan_stub.results = [{"status": "done", "text": "http://10.94.17.1:24683/", "source": "camera"}]
	g.qr.poll(later())
	check(joins.size() == 1 and joins[0][0] == "10.94.17.1" and joins[0][1] == PORT and not g.qr.scanning and not g.qr.active(),
		"Spiel-QR gescannt: beitreten an 10.94.17.1, Spielport der Lobby, ohne WLAN-Anfrage")
	# Fremder Code, abgebrochen, Scanner-Fehler
	g.qr.scan()
	QrJoin.scan_stub.results = [{"status": "done", "text": "Hallo"}]
	g.qr.poll(later())
	check(g.qr.warn and g.qr.text.contains("kein QR-Code von Draw2Race") and joins.size() == 1, "Fremder Code: Hinweis, kein Beitritt")
	g.qr.scan()
	QrJoin.scan_stub.results = [{"status": "cancelled"}]
	g.qr.poll(later())
	check(not g.qr.scanning and g.qr.text == "", "Abgebrochen: still")
	g.qr.scan()
	QrJoin.scan_stub.results = [{"status": "failed", "error": "module"}]
	g.qr.poll(later())
	check(g.qr.warn and g.qr.text.contains("von Google geladen"), "Scanner-Modul fehlt noch: Hinweis")
	# Eingespeister alter Text zählt nicht (Testeinstieg d2r_scan, älter als 2 min)
	QrJoin.scan_stub.results = [{"status": "done", "text": "http://10.94.17.1:24683/", "source": "intent", "at": 0, "now": 200000}]
	g.qr.poll(later())
	check(joins.size() == 1, "Alter eingespeister Text: kein Beitritt")
	# WLAN-QR: verbinden, an das Spiel-WLAN binden, am Gateway beitreten
	QrJoin.scan_stub.results = [{"status": "done", "text": NetAndroid.wifi_qr_text("AndroidShare_7k2m", "q9w3e7r2t5y8u4i"), "source": "intent", "at": 1000, "now": 2000}]
	g.qr.poll(later())
	check(g.qr.active() and not g.qr.pinned and g.qr.text.contains("Verbinde mit dem Spiel-WLAN „AndroidShare_7k2m“") and joins.size() == 1,
		"WLAN-QR (frisch eingespeist): Anfrage läuft, Hinweis auf die Android-Nachfrage")
	QrJoin.wifi_stub.state = {"status": "available", "gateway": "10.94.17.1", "address": "10.94.17.20/24", "handle": "900", "ssid": "AndroidShare_7k2m"}
	var qr_net := {"handle": "900", "transport": "wifi", "iface": "wlan1", "addresses": ["10.94.17.20/24"], "gateway": "10.94.17.1", "internet": false}
	fake.nets = [HOME, qr_net]
	g.qr.poll(later())
	fake.bound_net = qr_net.duplicate()      # wie QrWifi.bind: der Prozess hängt jetzt am Spiel-WLAN
	check(g.qr.pinned and joins.size() == 2 and joins[1] == ["10.94.17.1", PORT, "AndroidShare_7k2m"] and g.mode == "search" and g.bound and fake.binds == binds,
		"Spiel-WLAN verbunden: Suche daran gebunden (nicht ans Heim-WLAN), Beitritt am Gateway 10.94.17.1")
	fake.nets = [qr_net, HOME]          # Android meldet die Netze in anderer Reihenfolge („WLAN gewechselt“)
	g.refresh_status()
	check(fake.binds == binds and g.qr.pinned and g.mode == "search", "WLAN-Wechselmeldung: Bindung bleibt beim Spiel-WLAN")
	g.session.connect_timeout_ms = 300
	g.join("10.94.17.1", PORT)
	check(fake.binds == binds and g.bound, "Beitritt bindet ebenfalls ans Spiel-WLAN")
	g.cancel_join()
	g.search()
	# Gastgeber schließt das Spiel-WLAN: Android meldet es als verloren → freigeben, wieder ans Heim-WLAN
	QrJoin.wifi_stub.state = {"status": "lost"}
	fake.nets = [HOME]
	fake.bound_net = {}                      # wie QrWifi.release: Bindung ans Spiel-WLAN gelöst
	g.qr.poll(later())
	check(not g.qr.pinned and not g.qr.active() and int(QrJoin.wifi_stub.released) == 1 and g.qr.text.contains("ist weg") and fake.binds == binds + 1
		and str(fake.bound_net.get("handle", "")) == "100", "Spiel-WLAN verloren: freigegeben, Hinweis, wieder ans Heim-WLAN gebunden")
	# Verbindung scheitert (Systemdialog abgelehnt)
	g.qr.handle(NetAndroid.wifi_qr_text("AndroidShare_7k2m", "q9w3e7r2t5y8u4i"))
	QrJoin.wifi_stub.state = {"status": "unavailable"}
	g.qr.poll(later())
	check(not g.qr.active() and g.qr.warn and g.qr.text.contains("Keine Verbindung") and int(QrJoin.wifi_stub.released) == 2, "Keine Verbindung: Hinweis, Anfrage freigegeben")
	# Verlassen gibt frei
	g.qr.handle(NetAndroid.wifi_qr_text("AndroidShare_7k2m", "q9w3e7r2t5y8u4i"))
	QrJoin.wifi_stub.state = {"status": "available", "gateway": "10.94.17.1", "handle": "900"}
	g.qr.poll(later())
	g.exit()
	check(not g.qr.active() and not g.qr.pinned and int(QrJoin.wifi_stub.released) == 3, "Verlassen des WLAN-Mehrspielers gibt das Spiel-WLAN frei")
	# Android 9 und ohne Google-Dienste
	QrJoin.wifi_stub.sdk = 28
	g.qr.handle(NetAndroid.wifi_qr_text("AndroidShare_7k2m", "q9w3e7r2t5y8u4i"))
	check(not g.qr.active() and g.qr.text.contains("WLAN-Einstellungen") and g.qr.text.contains("q9w3e7r2t5y8u4i"), "Android 9: Name und Passwort zum Eintragen")
	QrJoin.scan_stub.available = false
	g.qr.scan()
	check(not g.qr.scanning and g.qr.text.contains("Google-Play-Dienste"), "Ohne Google-Play-Dienste: Hinweis statt Scanner")
	dispose(g)
	QrJoin.scan_stub = null
	QrJoin.wifi_stub = null

# ---------- 5. Oberfläche ----------
func node(app: Node, node_name: String) -> Node:
	for n in app.hud.content.find_children(node_name, "", true, false):
		if not n.is_queued_for_deletion():
			return n
	return null

func frames_until(done: Callable, timeout_ms := 4000) -> bool:
	# Wie test_lobby: Netz von Hand abfragen, höchstens alle 100 ms ein Bild (build.ps1 erlaubt 180 Bilder je Testreihe).
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
	NetLobby.overrides = TEST_OVERRIDES.merged({"auto_poll": true}, true)   # die Lobby, die main.gd anlegt
	QrJoin.scan_stub = {"available": true, "results": []}
	NetAndroid.wifi_stub = GAME_WIFI.duplicate()
	var app: Node = load("res://main.tscn").instantiate()
	ui_app = app
	root.add_child(app)
	app.set_physics_process(false)
	await process_frame
	var test_path := "user://test_invite_%s.json" % Time.get_ticks_usec()
	app.store = ProgressStore.new(test_path)
	app.store.set_player_name("Shakie")
	app.store.save()
	app.show_menu()
	# Mitspieler: QR-Code scannen im WLAN-Bildschirm
	var rita := make("Rita")
	rita.auto_poll = true
	rita.host("harbor", 0)
	app.open_wlan()
	check(node(app, "ScanButton") != null and app.phase == "net_menu", "WLAN-Bildschirm: Knopf „QR-Code scannen“")
	app.lobby.forced_status = {"android": true, "networks": [], "interfaces": []}
	app.lobby.refresh_status()
	var status := node(app, "NetStatus") as Label
	check(status != null and status.text.contains("Spiel-WLAN") and status.text.contains("Mitspieler einladen"), "Ohne WLAN: Hinweis aufs eigene Spiel-WLAN")
	app.lobby.forced_status = {}
	app.lobby.refresh_status()
	(node(app, "ScanButton") as Button).pressed.emit()
	QrJoin.scan_stub.results = [{"status": "done", "text": "http://127.0.0.1:24683/?p=%d" % PORT}]
	var ok: bool = await frames_until(func(): return app.phase == "net_lobby" and rita.client_count() == 1)
	check(ok, "Spiel-QR gescannt → verbunden, Lobby von Rita")
	app.net_leave_lobby()
	ok = await frames_until(func(): return rita.client_count() == 0 and app.phase == "net_menu")
	app.show_menu()
	check(ok and app.lobby == null, "Zurück im Menü")
	# App-Link aus dem Browser (Einladungsseite): tritt im Menü sofort bei
	NetAndroid.app_link_stub = "draw2race://join?h=127.0.0.1&p=%d" % PORT
	app.poll_app_link()
	ok = await frames_until(func(): return app.phase == "net_lobby" and rita.client_count() == 1)
	check(ok and app.lobby != null and not app.lobby.is_host(), "App-Link im Menü: WLAN-Mehrspieler geöffnet und beigetreten")
	app.net_leave_lobby()
	ok = await frames_until(func(): return rita.client_count() == 0)
	dispose(rita)
	# Gastgeber: Mitspieler einladen
	app.net_host()
	var invite_button := node(app, "InviteButton") as Button
	check(app.phase == "net_lobby" and app.lobby.is_host() and invite_button != null, "Gastgeber-Lobby: Knopf „Mitspieler einladen“")
	invite_button.pressed.emit()
	var panel := node(app, "Invite") as InvitePanel
	check(panel != null and node(app, "Step1") != null and node(app, "Step2") != null and app.hud.overlay_open(), "Panel mit ① WLAN und ② Spiel")
	panel.refresh(true)
	check(app.lobby.invite.mode == "wlan" and (node(app, "OwnWifi") as Button).visible and not (node(app, "CloseWifi") as Button).visible
		and (panel.cards[1].qr as TextureRect).texture != null and (panel.cards[0].qr as TextureRect).texture == null,
		"Im (PC-)Netz: „Eigenes Spiel-WLAN öffnen“, Spiel-QR da, noch kein WLAN-QR")
	(node(app, "OwnWifi") as Button).pressed.emit()
	app.lobby.invite.poll(later())
	panel.refresh(true)
	var name_label := node(app, "Name") as Label
	var pass_label := node(app, "Passwort") as Label
	check(app.lobby.invite.mode == "game_wifi" and (panel.cards[0].qr as TextureRect).texture != null and name_label != null and name_label.text == "AndroidShare_7k2m"
		and pass_label != null and pass_label.text == "q9w3e7r2t5y8u4i" and (node(app, "CloseWifi") as Button).visible,
		"Spiel-WLAN offen: WLAN-QR, Name und Passwort, „Spiel-WLAN schließen“")
	var address := node(app, "Adresse") as Label
	check(address != null and address.text.begins_with("10.94.17.1:%d" % APK_PORT), "② zeigt die Adresse im Spiel-WLAN: %s" % (address.text if address else "–"))
	(node(app, "InviteDone") as Button).pressed.emit()
	await process_frame
	check(node(app, "Invite") == null and str(NetAndroid.game_wifi_state().status) == "on", "Fertig: Panel zu, Spiel-WLAN bleibt offen")
	(node(app, "InviteButton") as Button).pressed.emit()
	panel = node(app, "Invite") as InvitePanel
	panel.refresh(true)
	(node(app, "CloseWifi") as Button).pressed.emit()
	panel.refresh(true)
	check(str(NetAndroid.game_wifi_state().status) == "off" and not (node(app, "CloseWifi") as Button).visible, "„Spiel-WLAN schließen“ beendet es")
	(node(app, "OwnWifi") as Button).pressed.emit()
	app.go_back()
	await process_frame
	check(node(app, "Invite") == null and app.phase == "net_lobby", "Zurück-Taste schließt nur das Panel")
	app.go_back()
	ok = await frames_until(func(): return app.phase == "net_menu")
	app.go_back()
	check(app.phase == "menu" and app.lobby == null and str(NetAndroid.game_wifi_state().status) == "off", "Verlassen: Menü, Spiel-WLAN geschlossen")
	app.queue_free()
	ui_app = null
	await process_frame
	print("INFO: Bilder bis zum Ende: %d (build.ps1: höchstens 180)" % Engine.get_process_frames())
	for suffix in ["", ".bak", ".tmp", ".run"]:
		if FileAccess.file_exists(test_path + suffix):
			DirAccess.remove_absolute(test_path + suffix)
