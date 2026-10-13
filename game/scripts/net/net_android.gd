class_name NetAndroid
extends RefCounted

const Proto := preload("res://scripts/net/net_protocol.gd")

# Android-Helfer für den lokalen Mehrspieler (docs/MULTIPLAYER_RECHERCHE.md 4.2–4.4). Ruft die statischen Methoden von
# android/build/src/main/java/com/godot/game/NetHelper.java über JavaClassWrapper auf – nach demselben Muster wie updater.gd.
# Außerhalb von Android liefern alle Funktionen gleichwertige Ersatzwerte (Adressen aus IP.get_local_interfaces(), Netzpräfix /24
# angenommen), damit Netztest und Suche auch am PC laufen.

static func _java() -> Array:
	# [Java-Klasse, Activity] oder [] außerhalb von Android.
	if OS.get_name() != "Android" or not Engine.has_singleton("AndroidRuntime"):
		return []
	var activity = Engine.get_singleton("AndroidRuntime").getActivity()
	var java = JavaClassWrapper.wrap("com.godot.game.NetHelper")
	return [java, activity] if java != null and activity != null else []

static func available() -> bool:
	return not _java().is_empty()

static func _json(text) -> Variant:
	var json := JSON.new()
	if text is String and json.parse(text) == OK:
		return json.data
	return null

static func state() -> Dictionary:
	# Netzwerkzustand. Android: sdk, device, networks[{transport (wifi/mobile/ethernet/vpn/…), internet, validated, default, bound,
	# iface, addresses ["ip/präfix"], gateway, handle}], default, bound (Netz oder null), wifi_gateway, dhcp_gateway, multicast_lock,
	# wifi_enabled, interfaces[{name, address, prefix, broadcast}]. Überall zusätzlich: android (bool), platform.
	var j := _java()
	var out := {}
	if not j.is_empty():
		var data = _json(j[0].state(j[1]))
		if data is Dictionary:
			out = data
		else:
			out = {"error": "Netzstatus nicht lesbar"}
	else:
		out = {"networks": [], "default": null, "bound": null, "wifi_gateway": "", "dhcp_gateway": "", "multicast_lock": false,
			"interfaces": interfaces()}
	out["android"] = not j.is_empty()
	out["platform"] = "%s %s · %s" % [OS.get_name(), OS.get_version(), OS.get_model_name()]
	return out

static func interfaces() -> Array:
	# Eigene IPv4-Adressen [{name, address, prefix, broadcast}] (ohne Loopback/Link-local).
	var j := _java()
	var out := []
	if not j.is_empty():
		var data = _json(j[0].interfaces(j[1]))
		if data is Array:
			for entry in data:
				if entry is Dictionary and Proto.usable_ipv4(str(entry.get("address", ""))):
					out.append({"name": str(entry.get("name", "")), "address": str(entry.address),
						"prefix": int(entry.get("prefix", 24)), "broadcast": str(entry.get("broadcast", ""))})
			return out
	for iface in IP.get_local_interfaces():
		for address in iface.get("addresses", []):
			if Proto.usable_ipv4(str(address)):
				out.append({"name": str(iface.get("friendly", iface.get("name", ""))), "address": str(address), "prefix": 24,
					"broadcast": Proto.directed_broadcast(str(address), 24)})
	return out

static func bind_wifi() -> String:
	# Prozess an das WLAN binden (ConnectivityManager.bindProcessToNetwork). "" = gebunden, sonst Grund.
	# Gilt nur für danach erzeugte Sockets: ENet-Peer und Such-Sockets erst nach der Bindung anlegen.
	# Welches Netz das WLAN ist, entscheidet wifi_handle() (ohne den eigenen Hotspot, den Android 16 ebenfalls als WLAN-Netz meldet –
	# Gerätetest S24 Ultra 04.10.2026: das Spiel band sich nach „WLAN aus“ an den eigenen Hotspot); Java bindet genau dieses Netz.
	var j := _java()
	if j.is_empty():
		return "Nur auf Android möglich."
	var handle := wifi_handle(state())
	if handle == "":
		return "Kein WLAN verbunden."
	return str(j[0].bindNetwork(j[1], handle))

static func bind_network(handle: String) -> String:
	# Prozess an das Netz mit diesem Handle binden (z. B. den eigenen Hotspot, Android 16). "" = gebunden, sonst Grund.
	var j := _java()
	if j.is_empty():
		return "Nur auf Android möglich."
	return str(j[0].bindNetwork(j[1], handle))

static func unbind() -> bool:
	var j := _java()
	return not j.is_empty() and bool(j[0].unbind(j[1]))

static func is_bound() -> bool:
	var s := state()
	return s.get("bound") is Dictionary

static func multicast(acquire: bool) -> bool:
	# Eigene Multicast-Sperre (zusätzlich zu der, die Godot für Rundruf-Sockets selbst nimmt). true = gehalten bzw. freigegeben.
	var j := _java()
	if j.is_empty():
		return false
	return bool(j[0].multicastAcquire(j[1])) if acquire else bool(j[0].multicastRelease(j[1]))

static func wifi_gateway(s := {}) -> String:
	# Gateway des WLANs (im Handy-Hotspot ist das der Host). "" wenn unbekannt (z. B. am PC).
	if s.is_empty():
		s = state()
	var gw := ""
	for n in wifi_networks(s):
		if str(n.get("gateway", "")) != "":
			gw = str(n.gateway)
			break
	if gw == "":
		gw = str(s.get("wifi_gateway", ""))
	if gw == "" or gw == "0.0.0.0":
		gw = str(s.get("dhcp_gateway", ""))
	return gw if Proto.ipv4_to_int(gw) > 0 else ""

static func summary(s: Dictionary) -> Array:
	# Kurze deutsche Statuszeilen für Anzeige und Log.
	var lines := []
	lines.append(str(s.get("platform", "")))
	if s.has("error"):
		lines.append("Fehler: %s" % s.error)
	if s.get("android", false):
		var nets := []
		for n in s.get("networks", []):
			if n is Dictionary:
				var flags := []
				if n.get("default", false):
					flags.append("Standard")
				if n.get("validated", false):
					flags.append("Internet geprüft")
				elif n.get("internet", false):
					flags.append("ohne Internetnachweis")
				if n.get("bound", false):
					flags.append("GEBUNDEN")
				if hotspot_network(n):
					flags.append("eigener Hotspot" + (" (lokales Netz)" if n.get("local", false) else ""))
				var iface := str(n.get("iface", ""))
				nets.append("%s%s (%s)%s" % [_transport_text(str(n.get("transport", "?"))), " " + iface if iface != "" else "", ", ".join(flags),
					" " + ", ".join(n.get("addresses", [])) if n.get("addresses", []).size() > 0 else ""])
		lines.append("Netze: " + ("; ".join(nets) if nets.size() > 0 else "keine"))
		var bound = s.get("bound")
		lines.append("Bindung: " + (("an " + _transport_text(str(bound.get("transport", "?")))) if bound is Dictionary else "keine (Standardnetz)"))
		lines.append("Multicast-Sperre: " + ("gehalten" if s.get("multicast_lock", false) else "nicht gehalten"))
	var ips := []
	for i in s.get("interfaces", []):
		if i is Dictionary:
			ips.append("%s/%d (%s)" % [i.get("address", "?"), int(i.get("prefix", 24)), i.get("name", "")])
	lines.append("Adressen: " + (", ".join(ips) if ips.size() > 0 else "keine"))
	var gw := wifi_gateway(s)
	lines.append("WLAN-Gateway: " + (gw if gw != "" else "unbekannt"))
	if s.get("android", false):
		var spots := hotspot_interfaces(s).map(func(i): return "%s/%d (%s)" % [i.address, i.prefix, i.name])
		lines.append("Eigener Hotspot: " + (", ".join(spots) if not spots.is_empty() else "aus"))
	return lines

static func _transport_text(t: String) -> String:
	return {"wifi": "WLAN", "mobile": "Mobilnetz", "ethernet": "LAN", "vpn": "VPN", "bluetooth": "Bluetooth"}.get(t, t)

# --- Einordnung fürs Spiel (WLAN-Mehrspieler, M3) ---
# Gerätetest 04.10.2026 (S24 Ultra, Android 16, Gastgeber mit eigenem Hotspot und zugleich im Heim-WLAN): Android 16 meldet den eigenen
# Hotspot als eigenes Netz – Transport WLAN, Schnittstelle swlan0 (10.110.43.61/24), ohne Gateway, „lokales Netz“. Die alte Einordnung
# hielt jede WLAN-Adresse für ein Gast-WLAN: Der Hotspot fiel nicht auf, der Gastgeber blieb ans Heim-WLAN gebunden (Antworten an die
# Hotspot-Mitspieler liefen ins Heim-WLAN), und nach „WLAN aus“ band sich das Spiel an den eigenen Hotspot. Bis Android 15 taucht der
# Hotspot nur als Schnittstelle auf (S21: swlan0 172.17.251.253/24). Beides wird hier erkannt; die Entscheidungen sind reine Funktionen
# des Netzstatus (Tests: test_lobby, test_binding/test_hotspot mit den Werten aus dem Geräteprotokoll).

# Mobilfunk, CLAT, VPN und Sonstiges: nie Hotspot (Samsung meldet beim S24 zusätzlich rmnet_data0 192.0.0.2/27).
const MOBILE_IFACES := ["rmnet", "v4-", "ccmni", "clat", "pdp", "seth", "tun", "ppp", "dummy", "lo", "rmnet_data", "umts", "wwan", "ipsec",
	"p2p", "aware", "nan"]
# Eigener Hotspot: Samsung swlan0, AOSP ap0/ap_br_ap0/softap0 – immer. wlan1/wlan2 (manche Geräte: Hotspot, andere: zweites WLAN), USB-
# (rndis0, usb0, ncm0) und Bluetooth-Tethering (bt-pan) nur ohne Gateway.
const HOTSPOT_IFACES := ["swlan", "softap", "ap"]
const MAYBE_HOTSPOT_IFACES := ["wlan1", "wlan2", "rndis", "usb", "ncm", "bt-pan", "wigig"]

static func _iface_in(iface: String, prefixes: Array) -> bool:
	var name := iface.to_lower()
	return prefixes.any(func(prefix): return name.begins_with(prefix))

static func hotspot_network(n: Dictionary) -> bool:
	# Ist dieses Netz der eigene Hotspot bzw. ein eigenes Tethering (Android 16: „lokales Netz“)? Dann ist es kein WLAN, an das sich das
	# Spiel binden darf, und seine Adresse ist eine Hotspot-Adresse. Das Standardnetz ist nie der eigene Hotspot.
	if bool(n.get("local", false)):
		return true
	if bool(n.get("default", false)):
		return false
	var iface := str(n.get("iface", ""))
	if _iface_in(iface, HOTSPOT_IFACES):
		return true
	return str(n.get("gateway", "")) == "" and (_iface_in(iface, MAYBE_HOTSPOT_IFACES) or not bool(n.get("internet", true)))

static func wifi_networks(s: Dictionary) -> Array:
	# Android: verbundene WLANs, in denen das Handy Gast ist (Heim-WLAN oder Hotspot eines anderen Handys), mit IPv4-Adresse – nie der
	# eigene Hotspot. WLANs mit Gateway zuerst. Am PC: [].
	if not s.get("android", false):
		return []
	var with_gateway := []
	var without := []
	for n in s.get("networks", []):
		if n is Dictionary and str(n.get("transport", "")) == "wifi" and not hotspot_network(n) and not (n.get("addresses", []) as Array).is_empty():
			(with_gateway if str(n.get("gateway", "")) != "" else without).append(n)
	return with_gateway + without

static func wifi_connected(s: Dictionary) -> bool:
	# Android: ein WLAN (als Gast) mit IPv4-Adresse ist verbunden. Am PC: irgendeine brauchbare eigene Adresse (LAN/WLAN).
	if not s.get("android", false):
		return not s.get("interfaces", []).is_empty()
	return not wifi_networks(s).is_empty()

static func wifi_is_default(s: Dictionary) -> bool:
	# Android: Ist das WLAN Androids Standardnetz? Dann erreichen auch ungebundene Sockets die Mitspieler im WLAN. Ohne Internet macht
	# Android bei eingeschalteten mobilen Daten das Mobilnetz zum Standardnetz.
	return wifi_networks(s).any(func(n): return bool(n.get("default", false)))

static func wifi_handle(s: Dictionary) -> String:
	# Android: Handle des WLANs, an das bind_wifi() bindet (ein WLAN mit Gateway zuerst), sonst "" (kein WLAN, PC). Ein neues WLAN –
	# auch dasselbe nach erneutem Verbinden – bekommt von Android ein neues Handle.
	for n in wifi_networks(s):
		if str(n.get("handle", "")) != "":
			return str(n.handle)
	return ""

static func wifi_addresses(s: Dictionary) -> Array:
	# Android: eigene Adressen in den Gast-WLANs (ohne Präfix).
	var out := []
	for n in wifi_networks(s):
		for a in n.get("addresses", []):
			out.append(str(a).get_slice("/", 0))
	return out

static func bound_to_wifi(s: Dictionary) -> bool:
	# Android: Ist der Prozess an ein WLAN gebunden, das gerade verbunden ist? Nach einem WLAN-Wechsel (Heim-WLAN → Hotspot) meldet
	# Android weiter das alte, verlorene Netz als gebunden (ohne Fähigkeiten, Transport „?“, nicht mehr in der Netzliste) – das zählt
	# nicht, ebenso wenig eine Bindung an den eigenen Hotspot. Vergleicht Handle und Transport mit den verbundenen Gast-WLANs.
	var b = s.get("bound")
	if not b is Dictionary or str(b.get("transport", "")) != "wifi":
		return false
	var handle := str(b.get("handle", ""))
	return wifi_networks(s).any(func(n): return str(n.get("handle", "")) == handle)

static func hotspot_interfaces(s: Dictionary) -> Array:
	# Android: Schnittstellen des eigenen Hotspots bzw. Tetherings [{name, address, prefix}]: eigene IPv4-Adressen, die zu keinem Netz
	# gehören, in dem das Handy Gast ist (WLAN, Mobilnetz, VPN) – bis Android 15 fehlt der Hotspot in der Netzliste ganz, ab Android 16
	# steht er als lokales Netz darin. Mobilfunk- und CLAT-Schnittstellen (192.0.0.0/24) zählen nie. Am PC: [].
	if not s.get("android", false):
		return []
	var guest := {}
	for n in s.get("networks", []):
		if n is Dictionary and not hotspot_network(n):
			for a in n.get("addresses", []):
				guest[str(a).get_slice("/", 0)] = true
	var out := []
	for i in s.get("interfaces", []):
		if not i is Dictionary:
			continue
		var address := str(i.get("address", ""))
		var iface := str(i.get("name", ""))
		if guest.has(address) or address.begins_with("192.0.0.") or not Proto.usable_ipv4(address) or _iface_in(iface, MOBILE_IFACES):
			continue
		if out.any(func(o): return o.address == address):
			continue
		out.append({"name": iface, "address": address, "prefix": int(i.get("prefix", 24))})
	return out

static func hotspot_addresses(s: Dictionary) -> Array:
	return hotspot_interfaces(s).map(func(i): return str(i.address))

static func in_subnet(ip: String, net_ip: String, prefix: int) -> bool:
	var a := Proto.ipv4_to_int(ip)
	var b := Proto.ipv4_to_int(net_ip)
	if a < 0 or b < 0 or prefix < 1 or prefix > 32:
		return false
	var mask := (((1 << prefix) - 1) << (32 - prefix)) & 0xFFFFFFFF
	return (a & mask) == (b & mask)

static func in_hotspot(s: Dictionary, address: String) -> bool:
	# Liegt die Adresse im Netz des eigenen Hotspots (z. B. ein Gastgeber, der mit diesem Handy verbunden ist)?
	return hotspot_interfaces(s).any(func(i): return in_subnet(address, str(i.address), int(i.prefix)))

static func hotspot_handle(s: Dictionary) -> String:
	# Android 16+: Handle des eigenen Hotspots als Netz (lokales Netz), sonst "" (bis Android 15 ist der Hotspot kein Netz; PC).
	if not s.get("android", false):
		return ""
	for n in s.get("networks", []):
		if n is Dictionary and hotspot_network(n) and str(n.get("handle", "")) != "" and not (n.get("addresses", []) as Array).is_empty():
			return str(n.handle)
	return ""

static func join_binding(s: Dictionary, address: String) -> String:
	# Mitspieler: woran binden, um den Gastgeber unter address zu erreichen? "wifi" (wie bisher), oder – liegt er im eigenen Hotspot –
	# "hotspot" (Android 16: an das Hotspot-Netz, so lief es im Gerätetest) bzw. "" (ungebunden, bis Android 15).
	if not in_hotspot(s, address):
		return "wifi"
	return "hotspot" if hotspot_handle(s) != "" else ""

static func host_plan(s: Dictionary, sockets = null) -> Dictionary:
	# Wie ein Gastgeber das Netz nutzt. Gebundene Sockets leitet Android nur über die Routing-Tabelle des gebundenen Netzes (S24 ans
	# Heim-WLAN gebunden: Antworten an die Hotspot-Mitspieler 10.110.43.x gingen ins Heim-WLAN). Ungebundene erreichen den Hotspot über
	# Androids Tabelle für lokale Netze und das WLAN über das Standardnetz, beides zugleich („zweigleisig“; S21 mit Android 15 am 03.10.
	# so belegt). Darum (bind):
	#   kein Hotspot              → "wifi"    ans WLAN binden (ein WLAN ohne Internet ist sonst nicht erreichbar)
	#   Hotspot und WLAN          → ""        ungebunden, Mitspieler in beiden Netzen
	#   nur Hotspot, Android 16+  → "hotspot" an den eigenen Hotspot binden (im Gerätetest nach „WLAN aus“ so gelaufen: Lobby und Rennen)
	#   nur Hotspot, bis 15       → ""        ungebunden (der Hotspot ist dort kein Netz; S21 so belegt)
	# Nie ans WLAN, solange der Hotspot an ist. sockets: null = Entscheidung beim Eröffnen; sonst die Bindung, mit der ENet- und
	# Such-Sockets des laufenden Spiels entstanden ("wifi", "hotspot", ""). Ergebnis: bind, reach (wen der Gastgeber erreicht: "wlan",
	# "hotspot"), wlan/hotspot (Adressen zum Eintippen), hint (deutscher Hinweis, "" = keiner), warn (es geht etwas nicht).
	var spots := hotspot_addresses(s)
	var wlan := wifi_addresses(s)
	var bind := ""
	if spots.is_empty():
		bind = "wifi" if not wlan.is_empty() else ""
	elif wlan.is_empty() and hotspot_handle(s) != "":
		bind = "hotspot"
	var tied: String = bind if sockets == null else str(sockets)
	var reach := []
	if not wlan.is_empty() and (tied == "wifi" or (tied == "" and wifi_is_default(s))):
		reach.append("wlan")
	if not spots.is_empty() and tied != "wifi":
		reach.append("hotspot")
	var hint := ""
	var warn := true
	if not spots.is_empty() and tied == "wifi":
		hint = "Dein Hotspot bzw. Spiel-WLAN ging erst an, als schon jemand da war. Mitspieler darin kommen erst rein, wenn du das Spiel neu eröffnest."
	elif not wlan.is_empty() and tied == "hotspot":
		hint = "Dein WLAN ging erst nach dem Eröffnen an. Mitspieler im WLAN kommen erst rein, wenn du das Spiel neu eröffnest."
	elif not wlan.is_empty() and not reach.has("wlan") and not spots.is_empty():
		hint = "Dein WLAN hat kein Internet: Nur Mitspieler im Hotspot erreichen dich. Fürs WLAN den Hotspot ausschalten und neu eröffnen."
	elif not wlan.is_empty() and not reach.has("wlan"):
		hint = "Dein WLAN ist nicht Androids Standardnetz (kein Internet?). Eröffne neu, damit sich das Spiel ans WLAN bindet."
	elif not spots.is_empty() and not wlan.is_empty():
		hint = "Hotspot und WLAN sind an – beide Netze können beitreten. Klappt es im Hotspot nicht: hier das WLAN aus und neu eröffnen."
		warn = false
	return {"bind": bind, "reach": reach, "wlan": wlan, "hotspot": spots, "hint": hint, "warn": warn and hint != ""}

static func host_frees(s: Dictionary, sockets: String) -> bool:
	# Gastgeber: Schließt die Bindung seiner Sockets ein inzwischen vorhandenes Netz aus (ans WLAN gebunden, der Hotspot ging an; an den
	# Hotspot gebunden, ein WLAN kam dazu)? Dann ungebunden weiter – nie neu binden, solange er Gastgeber ist.
	return (sockets == "wifi" and not hotspot_addresses(s).is_empty()) or (sockets == "hotspot" and not wifi_addresses(s).is_empty())

# --- Spiel-WLAN (Beta 1.0.2, übernommen aus Mau-Mau Flip): eigenes WLAN per LocalOnlyHotspot (android/build/.../GameWifi.java) ---
# Der Gastgeber öffnet es in der Lobby („Mitspieler einladen“, NetInvite/InvitePanel). Name und Passwort vergibt Android je Sitzung
# zufällig; kein Internet für die Gäste. Es endet mit „Spiel-WLAN schließen“, beim Verlassen des WLAN-Mehrspielers oder mit der App
# (Android kann es auch selbst beenden, z. B. im Hintergrund). Für die Bindungsregeln ist es ein eigener Hotspot (hotspot_interfaces,
# host_plan): bis Android 15 nur eine Schnittstelle (Samsung swlan0), ab Android 16 ein lokales Netz. Der normale Hotspot des Nutzers
# wird nie geändert. Am PC und in Tests ersetzt wifi_stub den Java-Helfer: {start_error: "" | Fehlercode, ssid, password, security,
# address, granted, dialog (Erlaubnis per Systemdialog statt sofort abgelehnt), sdk, ap_enabled, location_on}.

static var wifi_stub = null              # Dictionary = Simulation statt Java (PC, Tests); null = echtes Android bzw. nicht verfügbar
static var _stub_state := {}

static func _wifi_java() -> Array:
	if OS.get_name() != "Android" or not Engine.has_singleton("AndroidRuntime"):
		return []
	var activity = Engine.get_singleton("AndroidRuntime").getActivity()
	var java = JavaClassWrapper.wrap("com.godot.game.GameWifi")
	return [java, activity] if java != null and activity != null else []

static func game_wifi_available() -> bool:
	return wifi_stub is Dictionary or not _wifi_java().is_empty()

static func game_wifi_permission() -> String:
	# Nötige Laufzeit-Erlaubnis: ab Android 13 „Geräte in der Nähe“, bis 12 der genaue Standort.
	var j := _wifi_java()
	if not j.is_empty():
		return str(j[0].requiredPermission())
	return "android.permission.NEARBY_WIFI_DEVICES" if int((wifi_stub if wifi_stub is Dictionary else {}).get("sdk", 34)) >= 33 \
		else "android.permission.ACCESS_FINE_LOCATION"

static func game_wifi_request_permission() -> bool:
	# Erlaubnis anfragen (GameWifi.requestPermission: bis Android 12 genauer und grober Standort zusammen – Android 12 übergeht eine
	# Anfrage nach nur dem genauen). true = schon erteilt; false = Systemdialog offen, die Antwort kommt über
	# SceneTree.on_request_permissions_result. Ersatz: granted.
	if wifi_stub is Dictionary:
		return bool(wifi_stub.get("granted", true))
	var j := _wifi_java()
	if not j.is_empty():
		return bool(j[0].requestPermission(j[1]))
	return OS.request_permission(game_wifi_permission())

static func game_wifi_start() -> String:
	# "" = Start angestoßen (Ergebnis über game_wifi_state()), sonst Fehlercode.
	if wifi_stub is Dictionary:
		var err := str(wifi_stub.get("start_error", ""))
		if not bool(wifi_stub.get("granted", true)):
			err = "permission"
		_stub_state = {"status": "failed" if err != "" else "on", "error": err}
		return err
	var j := _wifi_java()
	if j.is_empty():
		return "unsupported"
	return str(j[0].startHotspot(j[1]))

static func game_wifi_stop() -> bool:
	# Spiel-WLAN schließen. true = es lief.
	if wifi_stub is Dictionary:
		var was := str(_stub_state.get("status", "")) == "on"
		_stub_state = {"status": "off", "error": ""}
		return was
	var j := _wifi_java()
	return not j.is_empty() and bool(j[0].stopHotspot())

static func game_wifi_state() -> Dictionary:
	# {status: off|starting|on|failed|stopped, ssid, password, security, error, sdk, permission, granted, location_on, ap_enabled
	# (1 an, 0 aus, -1 unbekannt), concurrency}. Ohne Android und Stub: status "failed", error "unsupported".
	if wifi_stub is Dictionary:
		var on := str(_stub_state.get("status", "off")) == "on"
		return {"status": str(_stub_state.get("status", "off")), "error": str(_stub_state.get("error", "")),
			"ssid": str(wifi_stub.get("ssid", "AndroidShare_4821")) if on else "",
			"password": str(wifi_stub.get("password", "k7m3x9q2w5r8t4z")) if on else "",
			"security": str(wifi_stub.get("security", "wpa2")) if on else "", "sdk": int(wifi_stub.get("sdk", 34)),
			"permission": game_wifi_permission(), "granted": bool(wifi_stub.get("granted", true)),
			"location_on": bool(wifi_stub.get("location_on", true)), "ap_enabled": int(wifi_stub.get("ap_enabled", 0)), "concurrency": true}
	var j := _wifi_java()
	if j.is_empty():
		return {"status": "failed", "error": "unsupported"}
	var data = _json(j[0].hotspotState(j[1]))
	return data if data is Dictionary else {"status": "failed", "error": "exception"}

static func stub_stop_game_wifi() -> void:
	# Nur Tests: Android beendet das Spiel-WLAN von selbst (z. B. im Hintergrund).
	_stub_state = {"status": "stopped", "error": ""}

static func wifi_qr_escape(text: String) -> String:
	# Sonderzeichen im WLAN-QR-Code (ZXing-Format): \ ; , : " mit vorangestelltem Backslash.
	var out := ""
	for ch in text:
		if ch in ["\\", ";", ",", ":", "\""]:
			out += "\\"
		out += ch
	return out

static func wifi_qr_text(ssid: String, password: String, security := "wpa2") -> String:
	# WLAN-QR-Code: WIFI:T:WPA;S:<ssid>;P:<passwort>;; – T steht auch bei WPA3 auf WPA (T:SAE erkennen viele Leser nicht).
	if security == "open" or password == "":
		return "WIFI:T:nopass;S:%s;;" % wifi_qr_escape(ssid)
	return "WIFI:T:WPA;S:%s;P:%s;;" % [wifi_qr_escape(ssid), wifi_qr_escape(password)]

static func game_wifi_address(s: Dictionary, before: Array = []) -> String:
	# Eigene Adresse im Spiel-WLAN aus den Netzwerkschnittstellen (nie 192.168 annehmen): eine Hotspot-Schnittstelle, bevorzugt eine,
	# die erst nach dem Start erschien (before = Hotspot-Adressen davor). "" = noch keine.
	var spots := hotspot_interfaces(s)
	for i in spots:
		if not before.has(str(i.address)):
			return str(i.address)
	return str(spots[0].address) if not spots.is_empty() else ""

static func game_wifi_message(st: Dictionary) -> Dictionary:
	# Deutscher Text zum Zustand: {title, text, retry (erneut versuchen sinnvoll), settings (App-Einstellungen öffnen hilft)}.
	var err := str(st.get("error", ""))
	var status := str(st.get("status", "off"))
	var old := int(st.get("sdk", 33)) < 33
	if status == "on":
		return {"title": "Spiel-WLAN ist offen", "text": "Kein Internet für die Mitspieler – das ist normal. Es endet, wenn du den WLAN-Mehrspieler verlässt.",
			"retry": false, "settings": false}
	if status == "starting":
		return {"title": "Spiel-WLAN wird geöffnet …", "text": "", "retry": false, "settings": false}
	if status == "stopped":
		return {"title": "Spiel-WLAN beendet", "text": "Android hat das Spiel-WLAN geschlossen (z. B. weil die App im Hintergrund war). Tippe auf „Neu öffnen“ – Name und Passwort ändern sich dabei.",
			"retry": true, "settings": false}
	match err:
		"permission":
			return {"title": "Erlaubnis fehlt", "text": ("Ohne die Erlaubnis „Standort“ kann die App bis Android 12 kein Spiel-WLAN öffnen. Den Standort selbst nutzt sie nicht."
				if old else "Ohne die Erlaubnis „Geräte in der Nähe“ kann die App kein Spiel-WLAN öffnen.")
				+ " Erlaube sie beim nächsten Versuch oder in den App-Einstellungen unter „Berechtigungen“.", "retry": true, "settings": true}
		"location_off":
			return {"title": "Standort ist aus", "text": "Bis Android 12 braucht das Spiel-WLAN den eingeschalteten Standort. Schalte ihn in den Schnelleinstellungen ein und tippe erneut.",
				"retry": true, "settings": false}
		"incompatible_mode", "ap_running":
			return {"title": "Dein Hotspot läuft", "text": "Beides gleichzeitig geht nicht. Schalte deinen normalen Hotspot in den Schnelleinstellungen aus – die App ändert ihn nie. Oder lass ihn an und verbinde die anderen damit.",
				"retry": true, "settings": false}
		"no_channel":
			return {"title": "Kein freier Funkkanal", "text": "Android hat gerade keinen Kanal fürs Spiel-WLAN gefunden. Versuch es gleich noch einmal.", "retry": true, "settings": false}
		"tethering_disallowed":
			return {"title": "Auf diesem Handy gesperrt", "text": "Ein eigenes WLAN ist hier nicht erlaubt (z. B. Firmen-Handy oder Mobilfunkanbieter). Nimm ein anderes Handy als Gastgeber.",
				"retry": false, "settings": false}
		"unsupported":
			return {"title": "Nicht verfügbar", "text": "Ein Spiel-WLAN geht nur auf Android 8 oder neuer.", "retry": false, "settings": false}
		"":
			return {"title": "Spiel-WLAN", "text": "Öffnet ein eigenes WLAN ohne Internet – für unterwegs oder wenn sich die Handys im Hotel- oder Gäste-WLAN nicht sehen.", "retry": true, "settings": false}
	return {"title": "Hat nicht geklappt", "text": "Das Spiel-WLAN ließ sich nicht öffnen. Versuch es noch einmal oder nutze deinen normalen Hotspot.", "retry": true, "settings": false}

# --- Einladung (② Spiel-QR) und App-Link (Beta 1.0.2) ---
# Der Spiel-QR führt auf die Einladungsseite, die der Dateidienst des Gastgebers ausliefert (NetApk, Port 24683): App herunterladen
# (ohne Internet) oder „In Draw2Race öffnen“ über den App-Link draw2race://join?h=<IP>&p=<Port>. GodotApp.java merkt das Intent
# (AppLink.java), main.gd holt es ab (take_app_link). Am PC und in Tests ersetzt app_link_stub den Java-Helfer (String = wartender
# Link, wird beim Abholen geleert).

const APP_LINK_SCHEME := "draw2race"
const APP_PACKAGE := "de.draw2race.game"
static var app_link_stub = null

static func take_app_link() -> String:
	# Wartenden App-Link abholen und vergessen ("" = keiner).
	if app_link_stub is String:
		var t: String = app_link_stub
		app_link_stub = null
		return t
	if OS.get_name() != "Android" or not Engine.has_singleton("AndroidRuntime"):
		return ""
	var java = JavaClassWrapper.wrap("com.godot.game.AppLink")
	return str(java.take()) if java != null else ""

static func private_ipv4(ip: String) -> bool:
	# Adresse in einem privaten Netz (10/8, 172.16/12, 192.168/16) – nur dorthin tritt die App per Link bei.
	var parts := ip.split(".")
	if parts.size() != 4:
		return false
	for p in parts:
		if not p.is_valid_int() or int(p) < 0 or int(p) > 255 or p.length() > 3:
			return false
	var a := int(parts[0])
	var b := int(parts[1])
	return a == 10 or (a == 172 and b >= 16 and b <= 31) or (a == 192 and b == 168)

static func invite_url(address: String, page_port: int, game_port := Proto.GAME_PORT) -> String:
	# Inhalt des Spiel-QR-Codes: Einladungsseite des Gastgebers; der Spielport steht nur dabei, wenn er vom festen abweicht (Tests).
	if address == "":
		return ""
	return "http://%s:%d/%s" % [address, page_port, "?p=%d" % game_port if game_port != Proto.GAME_PORT else ""]

static func app_link_url(address: String, port: int) -> String:
	return "%s://join?h=%s&p=%d" % [APP_LINK_SCHEME, address, port]

static func app_intent_url(address: String, port: int, fallback: String) -> String:
	# Für Chrome und Samsung Internet: intent:// öffnet die App; ohne App bleibt der Browser auf fallback (Einladungsseite).
	return "intent://join?h=%s&p=%d#Intent;scheme=%s;package=%s;S.browser_fallback_url=%s;end" % [address, port, APP_LINK_SCHEME,
		APP_PACKAGE, fallback.uri_encode()]

static func parse_app_link(link: String) -> Dictionary:
	# {ok, address, port, error}; error ist ein kurzer deutscher Satz für den Nutzer.
	var bad := {"ok": false, "address": "", "port": 0,
		"error": "Der Link zum Spiel ist unvollständig. Scanne den QR-Code beim Gastgeber noch einmal."}
	var t := link.strip_edges()
	var prefix := APP_LINK_SCHEME + "://join"
	if not t.to_lower().begins_with(prefix):
		return bad
	t = t.substr(prefix.length())
	var hash_at := t.find("#")
	if hash_at >= 0:
		t = t.substr(0, hash_at)
	t = t.trim_prefix("/")
	if not t.begins_with("?"):
		return bad
	var query := {}
	for pair in t.substr(1).split("&", false):
		var eq := pair.find("=")
		if eq > 0:
			query[pair.substr(0, eq).to_lower()] = pair.substr(eq + 1).uri_decode().strip_edges()
	var address := str(query.get("h", ""))
	var port_text := str(query.get("p", str(Proto.GAME_PORT)))
	if address == "" or not port_text.is_valid_int():
		return bad
	var port := int(port_text)
	if port < 1 or port > 65535:
		return bad
	if not private_ipv4(address) and address != "127.0.0.1":     # 127.0.0.1: das eigene Gerät (harmlos, für Tests)
		return {"ok": false, "address": address, "port": port,
			"error": "Dieser Link führt nicht zu einem Spiel in deiner Nähe. Die App tritt nur Spielen im selben WLAN bei."}
	return {"ok": true, "address": address, "port": port, "error": ""}
