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
		hint = "Dein Hotspot ging erst nach dem Eröffnen an. Hotspot-Mitspieler kommen erst rein, wenn du das Spiel neu eröffnest."
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
