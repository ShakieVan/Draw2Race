class_name NetInvite
extends RefCounted

# Mitspieler einladen (Beta 1.0.2, Nutzerwunsch 13.10.2026, übernommen aus Mau-Mau Flip „Spiel-WLAN“). Der Gastgeber öffnet in der
# Lobby ein eigenes WLAN (Android LocalOnlyHotspot, NetAndroid.game_wifi_*) und gibt es zusammen mit dem Link zum Spiel per QR-Code
# weiter:
#   ① WLAN:  WLAN-QR (WIFI:T:WPA;S:…;P:…;;) – mit der Kamera gescannt verbindet sich das Handy. Im Heim-WLAN oder im normalen Hotspot
#            des Gastgebers genügt der Hinweis, sich damit zu verbinden (deren Passwort kennt die App nicht).
#   ② Spiel: http://<IP>:24683/ – Einladungsseite des Dateidienstes (NetApk): „In Draw2Race öffnen“ (App-Link) oder die App
#            herunterladen, ganz ohne Internet. Die App-Gäste finden das Spiel ohnehin von selbst (Suche) oder scannen den Code in der App.
# Zustand und Regeln stehen hier (ohne Oberfläche, testbar), die Anzeige baut InvitePanel. Netzarten (mode): none | wlan | hotspot |
# starting | game_wifi | problem. Leuchten und Haken (glow): ① gilt als geschafft, sobald jemand die Einladungsseite aufruft oder
# beitritt (Android verrät normalen Apps nicht, wer im Spiel-WLAN ist), ② mit dem ersten Mitspieler; es leuchtet der nächste offene
# Schritt, und fällt eine Bedingung weg (Netz gewechselt, alle weg), beginnt es von vorn.
# Das Spiel-WLAN bleibt bei „Fertig“ offen (beim Wiederöffnen dieselben Zugangsdaten) und schließt sich mit „Spiel-WLAN schließen“
# oder beim Verlassen des WLAN-Mehrspielers (NetLobby.exit; in Mau-Mau Flip blieb es offen – dort ein bekannter Mangel). Für die
# Bindungsregeln ist es ein eigener Hotspot (NetAndroid.host_plan): Geht es nach dem Eröffnen auf, solange noch niemand da ist, legt
# die Lobby ihre Sockets ungebunden neu an (NetLobby._host_frees) und erreicht so Mitspieler im Spiel-WLAN und im WLAN.

signal changed

const KINDS := ["none", "wlan", "hotspot", "game_wifi"]   # feste Netzarten; „starting“ und „problem“ sind Zwischenstände
const POLL_MS := 400                # Spiel-WLAN geht auf bzw. Adresse fehlt noch
const NET_POLL_MS := 1500           # sonst: Netz neu bewerten (Android kann das Spiel-WLAN beenden)
const ADDRESS_WAIT_MS := 6000       # so lange nach „on“ auf die Adresse der neuen Schnittstelle warten
const PERMISSION_WAIT_MS := 60000   # Erlaubnisdialog: so lange auf die Antwort warten (eine unterbrochene Anfrage meldet Android nicht)

var lobby: NetLobby
var wifi := {}                      # letzter Zustand (NetAndroid.game_wifi_state)
var mode := "none"
var address := ""                   # eigene Adresse im Spiel-WLAN
var problem := ""                   # Fehlercode (wie GameWifi.java, dazu ap_running, stopped), "" = keiner
var active := false                 # das Panel war offen: Einladungsseite und APK werden bereitgestellt
var page_seen := false              # ① geschafft: jemand hat die Einladungsseite aufgerufen
var _kind := "none"                 # letzte feste Netzart (Wechsel → Schritte von vorn)
var _pages := 0
var _guests := 0
var _before: Array = []             # Hotspot-Adressen vor dem Start (die neue ist die des Spiel-WLANs)
var _started := false               # ein Öffnen wurde angestoßen (ein Fehlschlag zählt dann als Problem)
var _waiting_permission := false
var _ask_ms := 0                    # Erlaubnis angefragt um (ms)
var _on_since := 0
var _next_poll_ms := 0
var _sig := ""
var _page_sig := ""

func _init(owner: NetLobby) -> void:
	lobby = owner

func available() -> bool:
	return NetAndroid.game_wifi_available()

# ---------- Netzart ----------
static func detect_mode(s: Dictionary, st: Dictionary, problem_code: String) -> String:
	# Netzart aus Netzstatus (NetAndroid.state bzw. Ersatz), Spiel-WLAN-Zustand und Fehler.
	if problem_code != "":
		return "problem"
	var status := str(st.get("status", "off"))
	if status == "on":
		return "game_wifi"
	if status == "starting":
		return "starting"
	if bool(s.get("android", false)):
		if int(st.get("ap_enabled", -1)) == 1:
			return "hotspot"
		if NetAndroid.wifi_connected(s):
			return "wlan"
		if not NetAndroid.hotspot_interfaces(s).is_empty():
			return "hotspot"
		return "none"
	return "wlan" if not (s.get("interfaces", []) as Array).is_empty() else "none"

func page_address() -> String:
	# Adresse für ② (Einladungsseite): im Spiel-WLAN dessen Adresse, sonst die erste, unter der der Gastgeber erreichbar ist
	# (NetAndroid.host_plan: reach); am PC die erste eigene. "" = kein Netz.
	if mode == "game_wifi":
		return address
	if mode in ["none", "starting", "problem"] and bool(lobby.status.get("android", false)):
		return ""
	var st: Dictionary = lobby.status
	var reach: Array = st.get("reach", [])
	if reach.has("wlan") and not (st.get("wlan", []) as Array).is_empty():
		return str(st.wlan[0])
	if reach.has("hotspot") and not (st.get("hotspot", []) as Array).is_empty():
		return str(st.hotspot[0])
	if not bool(st.get("android", false)):
		for ip in st.get("addresses", []):
			if NetProtocol.usable_ipv4(str(ip)) and not str(ip).begins_with("127."):
				return str(ip)
	return ""

func page_url() -> String:
	return NetAndroid.invite_url(page_address(), lobby.apk_port, lobby.game_port)

func qr_text() -> String:
	# Inhalt des WLAN-QR-Codes ("" = keiner: nur fürs offene Spiel-WLAN, das Passwort anderer WLANs kennt die App nicht).
	if mode != "game_wifi" or str(wifi.get("ssid", "")) == "":
		return ""
	return NetAndroid.wifi_qr_text(str(wifi.get("ssid", "")), str(wifi.get("password", "")), str(wifi.get("security", "wpa2")))

func message() -> Dictionary:
	# Text zum Problem (NetAndroid.game_wifi_message).
	if problem == "stopped":
		return NetAndroid.game_wifi_message({"status": "stopped"})
	return NetAndroid.game_wifi_message({"status": "failed", "error": problem, "sdk": int(wifi.get("sdk", 33))})

func address_late() -> bool:
	# Spiel-WLAN offen, aber die eigene Adresse darin bleibt unbekannt (dann gibt es keinen Spiel-QR).
	return mode == "game_wifi" and address == "" and Time.get_ticks_msec() - _on_since > ADDRESS_WAIT_MS

# ---------- Schritte (Leuchten und Haken) ----------
func step1_done() -> bool:
	return _guests > 0 or (page_address() != "" and page_seen)

func step2_done() -> bool:
	return _guests > 0

func glow() -> int:
	# 1 oder 2 = dieser Schritt leuchtet, 0 = beide erledigt.
	if not step1_done():
		return 1
	if not step2_done():
		return 2
	return 0

func pages() -> int:
	return _pages

func downloads() -> int:
	return int(lobby.transfer.stats().get("downloads", 0))

# ---------- Ablauf ----------
func open() -> void:
	# Panel geöffnet: Einladungsseite und – falls vorhanden – die APK bereitstellen (Kopie im Hintergrund, NetApk/ApkShare).
	active = true
	lobby.serve_invite()
	refresh(true)

func open_wifi() -> void:
	problem = ""
	address = ""
	_started = true
	if not available():
		problem = "unsupported"
		refresh(true)
		return
	wifi = NetAndroid.game_wifi_state()
	if str(wifi.get("status", "")) in ["on", "starting"]:
		_on_since = Time.get_ticks_msec()
		refresh(true)
		return
	if not bool(wifi.get("granted", true)) and not _ask_permission():
		return
	_start()

func close_wifi() -> void:
	# „Spiel-WLAN schließen“: die Lobby bleibt; Mitspieler im Spiel-WLAN verlieren die Verbindung.
	var was := NetAndroid.game_wifi_stop()
	if was:
		lobby._log("Spiel-WLAN geschlossen")
	problem = ""
	address = ""
	_started = false
	_waiting_permission = false
	wifi = NetAndroid.game_wifi_state() if available() else {}
	lobby.refresh_status()
	refresh(true)

func dismiss_problem() -> void:
	problem = ""
	_started = false
	if available():
		wifi = NetAndroid.game_wifi_state()
	refresh(true)

func close() -> void:
	# Verlassen des WLAN-Mehrspielers (NetLobby.exit): ein offenes Spiel-WLAN schließen, nichts mehr bereitstellen.
	if available() and str(NetAndroid.game_wifi_state().get("status", "")) in ["on", "starting"]:
		NetAndroid.game_wifi_stop()
		lobby._log("Spiel-WLAN geschlossen (WLAN-Mehrspieler verlassen)")
	active = false
	problem = ""
	address = ""
	_started = false
	_waiting_permission = false
	wifi = {}
	page_seen = false
	_page_sig = ""

func _ask_permission() -> bool:
	# true = Erlaubnis da; false = Systemdialog offen (Antwort über on_request_permissions_result) bzw. im Ersatz abgelehnt.
	var perm := NetAndroid.game_wifi_permission()
	if NetAndroid.wifi_stub is Dictionary and not bool(NetAndroid.wifi_stub.get("dialog", false)):
		problem = "permission"
		refresh(true)
		return false
	if NetAndroid.game_wifi_request_permission():
		return true
	_waiting_permission = true
	_ask_ms = Time.get_ticks_msec()
	var tree := lobby.get_tree()
	if tree != null and not tree.on_request_permissions_result.is_connected(_on_permission):
		tree.on_request_permissions_result.connect(_on_permission)
	wifi["status"] = "starting"
	lobby._log("Spiel-WLAN: frage nach der Erlaubnis %s" % perm.get_slice(".", 2))
	refresh(true)
	return false

func _on_permission(permission: String, granted: bool) -> void:
	if not _waiting_permission or permission != NetAndroid.game_wifi_permission():
		return
	_waiting_permission = false
	lobby._log("Spiel-WLAN: Erlaubnis %s" % ("erteilt" if granted else "abgelehnt"))
	if granted:
		_start()
	else:
		problem = "permission"
		wifi = NetAndroid.game_wifi_state()
		refresh(true)

func _start() -> void:
	wifi = NetAndroid.game_wifi_state()
	if int(wifi.get("ap_enabled", -1)) == 1:
		problem = "ap_running"
		refresh(true)
		return
	_before = NetAndroid.hotspot_addresses(lobby._net_state())
	address = ""
	problem = NetAndroid.game_wifi_start()
	wifi = NetAndroid.game_wifi_state()
	_on_since = Time.get_ticks_msec()
	lobby._log("Spiel-WLAN öffnen: %s" % ("angestoßen" if problem == "" else "nicht möglich (%s)" % problem))
	refresh(true)

func busy() -> bool:
	# Muss NetLobby.poll() hier vorbeischauen? (Panel offen, Spiel-WLAN offen bzw. im Aufbau, Erlaubnisdialog)
	return active or _waiting_permission or str(wifi.get("status", "")) in ["on", "starting"]

func poll(now := -1) -> void:
	if now < 0:
		now = Time.get_ticks_msec()
	if now < _next_poll_ms:
		return
	if _waiting_permission:
		# Erlaubnisdialog offen: Die Antwort kommt normalerweise über _on_permission. Bleibt sie aus (unterbrochene Anfrage), hilft der
		# eigene Blick auf den Stand; nach PERMISSION_WAIT_MS gilt sie als verweigert.
		_next_poll_ms = now + POLL_MS
		var st := NetAndroid.game_wifi_state()
		if bool(st.get("granted", false)):
			_waiting_permission = false
			lobby._log("Spiel-WLAN: Erlaubnis erteilt (ohne Rückmeldung erkannt)")
			_start()
		elif now - _ask_ms > PERMISSION_WAIT_MS:
			_waiting_permission = false
			problem = "permission"
			wifi = st
			lobby._log("Spiel-WLAN: keine Antwort auf die Erlaubnisanfrage")
			refresh(true)
		return
	var st := str(wifi.get("status", ""))
	var waiting := problem == "" and (st == "starting" or (st == "on" and address == ""))
	_next_poll_ms = now + (POLL_MS if waiting else NET_POLL_MS)
	if available():
		var was := st
		wifi = NetAndroid.game_wifi_state()        # Android kann das Spiel-WLAN auch selbst beenden
		var now_st := str(wifi.get("status", ""))
		if now_st == "on" and was != "on":
			_on_since = now
			lobby._log("Spiel-WLAN offen: „%s“ (%s)" % [str(wifi.get("ssid", "")), str(wifi.get("security", ""))])
		elif was == "on" and now_st != "on":
			lobby._log("Spiel-WLAN beendet (%s)" % now_st)
	refresh()

func refresh(force := false) -> void:
	# Netz und Schritte neu bewerten; changed nur bei einer sichtbaren Änderung (force: immer).
	var st := str(wifi.get("status", ""))
	if problem == "" and _started and st in ["failed", "stopped"]:
		problem = (str(wifi.get("error", "")) if st == "failed" else "stopped")
		if problem == "":
			problem = "generic"
		_started = false
		lobby._log("Spiel-WLAN: Problem „%s“" % problem)
	if st == "on" and problem == "":
		if address == "":
			address = _find_address()
			if address != "":
				lobby._log("Spiel-WLAN: eigene Adresse %s" % address)
				lobby.refresh_status()        # Hotspot dazugekommen: Bindung und Sockets nach host_plan (NetLobby._host_frees)
	elif st != "on":
		address = ""
	mode = detect_mode(lobby._net_state(), wifi, problem)
	# Schritte: Seitenaufrufe zählen, Wechsel der Netzart oder kein Netz → von vorn; alle Mitspieler weg → von vorn.
	var pages_now := int(lobby.transfer.stats().get("pages", 0))
	if pages_now > _pages:
		page_seen = true
	_pages = pages_now
	var guests := lobby.client_count() if lobby.mode == "host" else 0
	if guests <= 0 and _guests > 0:
		page_seen = false
	_guests = maxi(guests, 0)
	if KINDS.has(mode) and mode != _kind:
		page_seen = false
		_kind = mode
	if page_address() == "":
		page_seen = false
	_update_page()
	var sig := "%s|%s|%s|%s|%s|%d|%d|%s|%d|%s" % [mode, address, problem, wifi.get("ssid", ""), page_url(), glow(), _pages, address_late(),
		downloads(), prepare_text()]
	if force or sig != _sig:
		_sig = sig
		changed.emit()

func _find_address() -> String:
	if NetAndroid.wifi_stub is Dictionary and str(NetAndroid.wifi_stub.get("address", "")) != "":
		return str(NetAndroid.wifi_stub.address)
	return NetAndroid.game_wifi_address(lobby._net_state(), _before)

func prepare_text() -> String:
	# Fortschritt der APK-Kopie für die Seite („40 %“), "" = fertig oder keine.
	var a = lobby.apk
	if not active or a == null or not a.available() or lobby.transfer.has_file():
		return ""
	var pct = a.get("percent")
	return "%d %%" % pct if pct is int and pct >= 0 and str(a.get("job")) == "copy" else ""

func preparing() -> bool:
	# Die App zum Herunterladen wird noch vorbereitet.
	return active and lobby.apk != null and lobby.apk.available() and not lobby.transfer.has_file()

func page_changed() -> void:
	# Der Dateidienst wurde neu angelegt (NetLobby._restart_service) und hat die Seitenangaben verloren: beim nächsten Blick neu setzen.
	_page_sig = ""
	_update_page()

func _update_page() -> void:
	# Angaben der Einladungsseite (NetApk.set_page) – nur beim Gastgeber, nur solange der Dienst läuft.
	if not active or lobby.mode != "host" or not lobby.transfer.serving():
		if _page_sig != "":
			lobby.transfer.set_page({})
			_page_sig = ""
		return
	var a = lobby.apk
	var info := {"name": lobby.session.my_name, "version": lobby.own_version(), "address": page_address(), "game_port": lobby.game_port,
		"apk": a != null and a.available(), "size": int(a.size_bytes()) if a != null and a.available() else 0, "prepare": prepare_text()}
	var sig := JSON.stringify(info)
	if sig != _page_sig:
		_page_sig = sig
		lobby.transfer.set_page(info)
