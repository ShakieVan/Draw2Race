class_name NetProtocol
extends RefCounted

# Lokaler Mehrspieler (docs/MULTIPLAYER_RECHERCHE.md, Abschnitt 4): Ports, Kanäle, Nachrichtenformat, Anmeldung („hello“) mit
# Versionsprüfung und das Format der Suche (Ankündigung/Anfrage per UDP). Reine Daten und Rechnungen – kein Zugriff auf Szene,
# Netz oder Simulation.
#
# Nachrichten (ENet): 2 Byte Kennung "D2", 1 Byte Protokollversion, dann var_to_bytes(Dictionary) mit dem Typ in "t".
# Objekte werden nie entpackt (bytes_to_var, nicht bytes_to_var_with_objects). Ablehnungen haben ein eigenes, für alle Versionen
# gleiches Format (Versionsbyte 0, danach UTF-8 "code\ngrund"), damit auch ein Gerät mit anderer Protokollversion den Grund lesen kann.
# Suche (UDP): JSON-Text mit Kennung "m" – klein, ohne Engine-Fehlermeldungen bei Fremdpaketen prüfbar.

const VERSION := 6                  # Protokollversion: bei jeder inkompatiblen Änderung erhöhen (2 = Lobby, M3; 3 = Zeichnen, M4; 4 = Rennen, M5;
                                    # 5 = Lebenszeichen im Rennen, race_alive; 6 = Spielerfarben, Autos mehrfach wählbar)
const GAME_PORT := 24680            # ENet (UDP), fester Port des Hosts
const DISCOVERY_PORT := 24681       # Host lauscht hier auf Suchanfragen und Gateway-Proben (UDP)
const BEACON_PORT := 24682          # Mitspieler lauschen hier auf die Ankündigung des Hosts (UDP-Rundruf, jede Sekunde)
const MAX_CLIENTS := 3              # Mitspieler; mit dem Host höchstens 4 Menschen
const MAX_PLAYERS := MAX_CLIENTS + 1
const CUSTOM_CHANNELS := 2          # eigene ENet-Kanäle zusätzlich zu Godots zwei Systemkanälen
const CHANNEL_CONTROL := 0          # Systemkanäle: zuverlässig (Lobby, Linien, Ereignisse) bzw. unzuverlässig (Ping)
const CHANNEL_SNAPSHOT := 1         # eigener Kanal für Schnappschüsse (unreliable_ordered, M5)
const MAX_MESSAGE_BYTES := 1024 * 1024   # alle vier Linien einer Runde in einer Nachricht (gepackt je rund 33 Byte/Punkt, NetDraw)
const MAX_DISCOVERY_BYTES := 1024
const MAX_NAME := 12
const MAGIC_0 := 0x44               # "D"
const MAGIC_1 := 0x32               # "2"
const BEACON_MAGIC := "D2R-HOST"
const QUERY_MAGIC := "D2R-SUCHE"
# Typen, die NetSession selbst behandelt; alles andere geht an message_received.
const RESERVED := ["hello", "welcome", "reject", "ping", "pong", "players", "bye"]
# Wege, auf denen ein Host gefunden wurde (Suche) – Kürzel im Protokoll, Texte für Anzeige und Log.
const VIA_TEXT := {"beacon": "Ankündigung", "bcast": "Rundruf", "subnet": "Netz-Rundruf", "gateway": "Gateway",
	"manual": "Adresse", "local": "Lokal"}

static func game_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))

static func physics_version() -> String:
	return RaceVehicle.VERSION

static func clean_name(text: String, fallback := "Fahrer") -> String:
	# Höchstens 12 Zeichen, keine Steuerzeichen, Umlaute erlaubt.
	var out := ""
	for i in range(text.length()):
		var c := text.unicode_at(i)
		if c >= 32 and c != 127:
			out += char(c)
	out = out.strip_edges().left(MAX_NAME).strip_edges()
	return out if out != "" else fallback

static func unique_name(wanted: String, taken: Array) -> String:
	# Gleiche Namen in einer Lobby bekommen eine Ziffer („Anna“, „Anna 2“ …).
	if not taken.has(wanted):
		return wanted
	for n in range(2, 100):
		var suffix := " %d" % n
		var candidate := wanted.left(MAX_NAME - suffix.length()).strip_edges() + suffix
		if not taken.has(candidate):
			return candidate
	return wanted

# --- Nachrichten (ENet) ---

static func encode(msg: Dictionary) -> PackedByteArray:
	var out := PackedByteArray([MAGIC_0, MAGIC_1, VERSION])
	out.append_array(var_to_bytes(msg))
	return out

static func encode_reject(code: String, reason: String) -> PackedByteArray:
	var out := PackedByteArray([MAGIC_0, MAGIC_1, 0])
	out.append_array((code + "\n" + reason).to_utf8_buffer())
	return out

static func peek_version(bytes: PackedByteArray) -> int:
	# Protokollversion eines Pakets, -1 = kein Draw2Race-Paket, 0 = Ablehnung.
	if bytes.size() < 3 or bytes[0] != MAGIC_0 or bytes[1] != MAGIC_1:
		return -1
	return bytes[2]

static func decode(bytes: PackedByteArray) -> Dictionary:
	# {} = ungültig. Fremde Protokollversion: {"t": "_foreign", "proto": n} (der Host lehnt dann mit klarem Grund ab).
	if bytes.size() > MAX_MESSAGE_BYTES:
		return {}
	var version := peek_version(bytes)
	if version < 0:
		return {}
	if version == 0:
		var text := bytes.slice(3).get_string_from_utf8()
		var cut := text.find("\n")
		return {"t": "reject", "code": text.left(cut) if cut >= 0 else "", "reason": text.substr(cut + 1) if cut >= 0 else text}
	if version != VERSION:
		return {"t": "_foreign", "proto": version}
	if bytes.size() < 7:
		return {}
	var data = bytes_to_var(bytes.slice(3))
	if not data is Dictionary or not data.get("t") is String:
		return {}
	return data

# --- Anmeldung ---

static func make_hello(player_name: String, track_hash := "") -> Dictionary:
	# track_hash: Prüfsumme aller Streckendateien (NetLobby.tracks_hash), der Host vergleicht sie (check_track).
	return {"t": "hello", "proto": VERSION, "game": game_version(), "physics": physics_version(), "track": track_hash,
		"name": clean_name(player_name), "os": OS.get_name(), "model": OS.get_model_name()}

static func check_hello(msg: Dictionary, local: Dictionary, accepted := 0, check_track := false) -> Dictionary:
	# Prüfung beim Host. {} = in Ordnung, sonst {"code", "reason"}; der Grund ist aus Sicht des Mitspielers formuliert.
	if str(msg.get("t", "")) == "_foreign" or int(msg.get("proto", -1)) != VERSION:
		return {"code": "protocol", "reason": "Netzprotokoll passt nicht (Host: %d, dein Gerät: %d). Bitte beide Geräte auf dieselbe Draw2Race-Version bringen." % [VERSION, int(msg.get("proto", -1))]}
	for key in ["game", "physics", "track", "name"]:
		if not msg.get(key) is String:
			return {"code": "bad", "reason": "Anmeldung unvollständig – bitte Draw2Race neu starten."}
	if msg.game != local.get("game", ""):
		return {"code": "game", "reason": "Andere Spielversion: Host %s, dein Gerät %s. Bitte beide Geräte auf dieselbe Version aktualisieren." % [local.get("game", "?"), msg.game]}
	if msg.physics != local.get("physics", ""):
		return {"code": "physics", "reason": "Andere Fahrphysik: Host „%s“, dein Gerät „%s“. Bitte beide Geräte auf dieselbe Version aktualisieren." % [local.get("physics", "?"), msg.physics]}
	if check_track and msg.track != local.get("track", ""):
		return {"code": "track", "reason": "Die Streckendaten unterscheiden sich vom Host. Bitte beide Geräte auf dieselbe Version aktualisieren."}
	if accepted >= MAX_CLIENTS:
		return {"code": "full", "reason": "Das Spiel ist voll (höchstens %d Spieler)." % MAX_PLAYERS}
	return {}

# --- Suche (UDP) ---

static func make_beacon(info: Dictionary, reply_to := "") -> PackedByteArray:
	# info: name, port, players, max, sid, busy (Rennen läuft, kein Beitritt). reply_to: Weg der beantworteten Anfrage ("" = regelmäßige Ankündigung).
	var data := {"m": BEACON_MAGIC, "v": VERSION, "game": game_version(), "physics": physics_version(),
		"name": clean_name(str(info.get("name", "Host")), "Host"), "port": int(info.get("port", GAME_PORT)),
		"players": int(info.get("players", 1)), "max": int(info.get("max", MAX_PLAYERS)), "sid": str(info.get("sid", "")),
		"re": reply_to, "busy": bool(info.get("busy", false))}
	if info.has("n"):
		data["n"] = int(info.n)
	if info.has("q"):
		data["q"] = int(info.q)   # Nummer der beantworteten Anfrage (Antwortzeit beim Suchenden)
	return JSON.stringify(data).to_utf8_buffer()

static func make_query(via: String, sid := "", n := 0) -> PackedByteArray:
	return JSON.stringify({"m": QUERY_MAGIC, "v": VERSION, "game": game_version(), "via": via, "sid": sid, "n": n}).to_utf8_buffer()

static func _parse_json(bytes: PackedByteArray, magic: String) -> Dictionary:
	# Fremdpakete still verwerfen: nur kleine JSON-Objekte (erstes Zeichen "{"), richtige Kennung, Protokollnummer als Zahl.
	if bytes.size() < 2 or bytes.size() > MAX_DISCOVERY_BYTES or bytes[0] != 0x7B:
		return {}
	for b in bytes:
		if b < 9:
			return {}
	var json := JSON.new()
	if json.parse(bytes.get_string_from_utf8()) != OK or not json.data is Dictionary:
		return {}
	var data: Dictionary = json.data
	if data.get("m") != magic or not (data.get("v") is float or data.get("v") is int):
		return {}
	return data

static func parse_beacon(bytes: PackedByteArray) -> Dictionary:
	# {} = kein Draw2Race-Host. Sonst: name, port, players, max, game, physics, proto, sid, re, busy, compatible, note.
	var d := _parse_json(bytes, BEACON_MAGIC)
	if d.is_empty():
		return {}
	var port := int(d.get("port", 0)) if (d.get("port") is float or d.get("port") is int) else 0
	if port <= 0 or port > 65535:
		return {}
	var info := {"name": clean_name(str(d.get("name", "Host")), "Host"), "port": port, "players": clampi(int(d.get("players", 1)) if d.get("players") is float else 1, 0, 16),
		"max": clampi(int(d.get("max", MAX_PLAYERS)) if d.get("max") is float else MAX_PLAYERS, 1, 16), "game": str(d.get("game", "?")).left(16),
		"physics": str(d.get("physics", "?")).left(32), "proto": int(d.v), "sid": str(d.get("sid", "")).left(32), "re": str(d.get("re", "")).left(16),
		"n": int(d.get("n", 0)) if d.get("n") is float else 0, "q": int(d.get("q", -1)) if d.get("q") is float else -1,
		"busy": d.get("busy") is bool and bool(d.busy)}
	info["compatible"] = info.proto == VERSION and info.game == game_version() and info.physics == physics_version()
	info["note"] = "" if info.compatible else ("andere Version %s" % info.game if info.game != game_version() else "anderes Protokoll/Physik")
	return info

static func parse_query(bytes: PackedByteArray) -> Dictionary:
	var d := _parse_json(bytes, QUERY_MAGIC)
	if d.is_empty():
		return {}
	return {"proto": int(d.v), "game": str(d.get("game", "?")).left(16), "via": str(d.get("via", "")).left(16),
		"sid": str(d.get("sid", "")).left(32), "n": int(d.get("n", 0)) if d.get("n") is float else 0}

# --- Adressen ---

static func ipv4_to_int(ip: String) -> int:
	# -1 = keine IPv4-Adresse
	var parts := ip.split(".")
	if parts.size() != 4:
		return -1
	var value := 0
	for p in parts:
		if not p.is_valid_int() or int(p) < 0 or int(p) > 255:
			return -1
		value = (value << 8) | int(p)
	return value

static func int_to_ipv4(value: int) -> String:
	return "%d.%d.%d.%d" % [(value >> 24) & 255, (value >> 16) & 255, (value >> 8) & 255, value & 255]

static func directed_broadcast(ip: String, prefix := 24) -> String:
	# Gerichteter Rundruf eines Netzes, z. B. 192.168.43.17/24 → 192.168.43.255. "" bei ungültiger Eingabe.
	var value := ipv4_to_int(ip)
	if value < 0 or prefix < 8 or prefix > 30:
		return ""
	var host_bits := (1 << (32 - prefix)) - 1
	return int_to_ipv4(value | host_bits)

static func usable_ipv4(ip: String) -> bool:
	# Für die Suche brauchbare eigene Adresse: IPv4, nicht Loopback, nicht Link-local (169.254), nicht 0.0.0.0.
	var value := ipv4_to_int(ip)
	return value > 0 and (value >> 24) != 127 and (value >> 16) != 0xA9FE

static func parse_address(text: String, default_port := GAME_PORT) -> Dictionary:
	# "192.168.1.5" oder "192.168.1.5:24680" → {"address", "port"}; {} bei ungültiger Eingabe.
	var t := text.strip_edges().replace(",", ".")
	var port := default_port
	var cut := t.rfind(":")
	if cut > 0 and t.count(":") == 1:
		var p := t.substr(cut + 1)
		if not p.is_valid_int() or int(p) <= 0 or int(p) > 65535:
			return {}
		port = int(p)
		t = t.left(cut)
	if ipv4_to_int(t) < 0:
		return {}
	return {"address": t, "port": port}
