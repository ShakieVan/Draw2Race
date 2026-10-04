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
	var j := _java()
	if j.is_empty():
		return "Nur auf Android möglich."
	return str(j[0].bindWifi(j[1]))

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
	var gw := str(s.get("wifi_gateway", ""))
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
				nets.append("%s (%s)%s" % [_transport_text(str(n.get("transport", "?"))), ", ".join(flags), " " + ", ".join(n.get("addresses", [])) if n.get("addresses", []).size() > 0 else ""])
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
	return lines

static func _transport_text(t: String) -> String:
	return {"wifi": "WLAN", "mobile": "Mobilnetz", "ethernet": "LAN", "vpn": "VPN", "bluetooth": "Bluetooth"}.get(t, t)

# --- Einordnung fürs Spiel (WLAN-Mehrspieler, M3) ---

const MOBILE_IFACES := ["rmnet", "v4-", "ccmni", "clat", "pdp", "seth", "tun", "ppp", "dummy", "lo", "rmnet_data", "umts", "wwan"]

static func wifi_connected(s: Dictionary) -> bool:
	# Android: ein WLAN (als Mitspieler/Client) mit IPv4-Adresse ist verbunden. Am PC: irgendeine brauchbare eigene Adresse (LAN/WLAN).
	if not s.get("android", false):
		return not s.get("interfaces", []).is_empty()
	for n in s.get("networks", []):
		if n is Dictionary and str(n.get("transport", "")) == "wifi" and not (n.get("addresses", []) as Array).is_empty():
			return true
	return false

static func wifi_handle(s: Dictionary) -> String:
	# Android: Handle des WLANs, an das bind_wifi() binden würde (wie NetHelper.findWifi: ein WLAN mit Gateway zuerst), sonst "" (kein
	# WLAN, PC). Ein neues WLAN – auch dasselbe nach erneutem Verbinden – bekommt von Android ein neues Handle.
	if not s.get("android", false):
		return ""
	var fallback := ""
	for n in s.get("networks", []):
		if n is Dictionary and str(n.get("transport", "")) == "wifi" and str(n.get("handle", "")) != "":
			if str(n.get("gateway", "")) != "":
				return str(n.handle)
			fallback = str(n.handle)
	return fallback

static func bound_to_wifi(s: Dictionary) -> bool:
	# Android: Ist der Prozess an ein WLAN gebunden, das gerade verbunden ist? Nach einem WLAN-Wechsel (Heim-WLAN → Hotspot) meldet
	# Android weiter das alte, verlorene Netz als gebunden (ohne Fähigkeiten, Transport „?“, nicht mehr in der Netzliste) – das zählt
	# nicht. Vergleicht Handle und Transport mit den verbundenen WLANs.
	var b = s.get("bound")
	if not b is Dictionary or str(b.get("transport", "")) != "wifi":
		return false
	var handle := str(b.get("handle", ""))
	for n in s.get("networks", []):
		if n is Dictionary and str(n.get("transport", "")) == "wifi" and str(n.get("handle", "")) == handle and not (n.get("addresses", []) as Array).is_empty():
			return true
	return false

static func hotspot_addresses(s: Dictionary) -> Array:
	# Android: eigene Adressen, die zu keinem Netz der Verbindungsverwaltung gehören – das sind die Schnittstellen des eigenen
	# Hotspots (Samsung swlan0, sonst ap0/wlan1/softap0). Mobilfunk- und CLAT-Schnittstellen (192.0.0.x) zählen nicht. Am PC: [].
	if not s.get("android", false):
		return []
	var known := {}
	for n in s.get("networks", []):
		if n is Dictionary:
			for a in n.get("addresses", []):
				known[str(a).get_slice("/", 0)] = true
	var out := []
	for i in s.get("interfaces", []):
		if not i is Dictionary:
			continue
		var address := str(i.get("address", ""))
		var iface := str(i.get("name", "")).to_lower()
		if known.has(address) or address.begins_with("192.0.0.") or not Proto.usable_ipv4(address):
			continue
		if MOBILE_IFACES.any(func(prefix): return iface.begins_with(prefix)):
			continue
		out.append(address)
	return out
