class_name NetTestScreen
extends CanvasLayer

# Versteckter „Netztest“ (docs/MULTIPLAYER_RECHERCHE.md, Meilenstein M0 Gerätetest): Host / Mitspielen / Adresse eingeben, Liste der
# gefundenen Spiele mit Fundweg, laufende RTT/Jitter/Verlust/Uhrversatz, Netzwerkstatus und der Schalter „an WLAN binden“.
# Alles Wichtige landet mit Zeitstempel in user://netztest.log (Fundwege, Sendefehler, Bindung, Netzwechsel, Ping-Zusammenfassungen),
# damit sich nach einem Hotspot-Test ohne adb auswerten lässt, welche Suche klappt und ob die Bindung das Mobilnetz-Problem löst.
#
# Öffnen:   NetTestScreen.open(parent)            → Bildschirm über allem (CanvasLayer 90), Signal closed beim Schließen.
# Automatik: NetTestScreen.open(root, NetTestScreen.cli_options()) – für PC-Läufe (scripts/net/net_cli.gd, tools/net_test.ps1):
#   --nettest=host | join | join:ADRESSE[:PORT] | search      --nettest-timeout=s  --nettest-expect=n (Host)  --nettest-duration=s
#   --nettest-name=NAME  --nettest-log=user://datei.log  --nettest-port=n  --nettest-local (Suche fragt auch 127.0.0.1)
#   --nettest-fake-version=X (Mitspieler meldet sich mit falscher Spielversion an; Ablehnung ist dann das erwartete Ergebnis)
# Am Ende eine Zeile „NETTEST-ERGEBNIS: OK|FEHLER …“, Exitcode 0/1.

const Proto := preload("res://scripts/net/net_protocol.gd")
const Session := preload("res://scripts/net/net_session.gd")
const Discovery := preload("res://scripts/net/net_discovery.gd")
const Android := preload("res://scripts/net/net_android.gd")
const Log := preload("res://scripts/net/net_log.gd")

signal closed

const INK := Color("173a40")
const MUTED := Color("617578")
const PAPER := Color("f4f0e5")
const ORANGE := Color("ed6948")
const GREEN := Color("2f8f5b")
const RED := Color("c2453a")
const BACK := Color("0c3239")

var session: Session
var discovery: Discovery
var netlog: Log
var cli := {}                       # Automatik-Optionen ({} = Bedienung per Hand)
var player_name := "Fahrer"
var game_port := Proto.GAME_PORT
var activity := ""                  # "" | "host" | "search" | "join"
var join_target := {}               # {address, port} des letzten Beitritts
var bound := false
var net_state := {}
var _net_lines: Array = []
var _next_net_ms := 0
var _next_ui_ms := 0
var _next_ping_log_ms := 0
var _cli_start_ms := 0
var _cli_connected_ms := 0
var _cli_max_clients := 0
var _cli_done := false
var _cli_found_ms := -1
var _cli_found_via := ""
var _games_signature := "-"

# Oberfläche
var bold: FontVariation
var status_label: Label
var conn_label: Label
var net_label: Label
var log_label: Label
var games_box: VBoxContainer
var games_title: Label
var bind_button: Button
var host_button: Button
var search_button: Button
var address_panel: Control          # abgedunkelte Ebene mit dem Eingabefeld
var address_edit: LineEdit

static func open(parent: Node, options := {}) -> NetTestScreen:
	var screen := NetTestScreen.new()
	screen.cli = options
	parent.add_child(screen)
	return screen

static func cli_options(args: PackedStringArray = OS.get_cmdline_user_args()) -> Dictionary:
	# {} wenn kein --nettest=… angegeben ist.
	var out := {}
	for arg: String in args:
		var key := arg.get_slice("=", 0)
		var value := arg.substr(key.length() + 1) if "=" in arg else ""
		match key:
			"--nettest":
				var mode := value.get_slice(":", 0)
				out["mode"] = mode
				if mode == "join" and ":" in value:
					var target := Proto.parse_address(value.substr(5))
					if target.is_empty():
						out["error"] = "Ungültige Adresse: " + value.substr(5)
					else:
						out["address"] = target.address
						out["port"] = target.port
			"--nettest-timeout": out["timeout"] = maxf(1.0, value.to_float())
			"--nettest-expect": out["expect"] = clampi(value.to_int(), 0, Proto.MAX_CLIENTS)
			"--nettest-duration": out["duration"] = maxf(0.5, value.to_float())
			"--nettest-name": out["name"] = value
			"--nettest-log": out["log"] = value
			"--nettest-port": out["game_port"] = clampi(value.to_int(), 1, 65535)
			"--nettest-local": out["local"] = true
			"--nettest-fake-version": out["fake_version"] = value
	if not out.has("mode"):
		return {}
	if not out.mode in ["host", "join", "search"]:
		out["error"] = "Unbekannter Modus: " + str(out.mode)
	return out

func _ready() -> void:
	layer = 90
	netlog = Log.new(str(cli.get("log", Log.DEFAULT_PATH)), not cli.is_empty())
	game_port = int(cli.get("game_port", Proto.GAME_PORT))
	player_name = Proto.clean_name(str(cli.get("name", "")), _default_name())
	session = Session.new()
	session.name = "NetSession"
	add_child(session)
	discovery = Discovery.new()
	discovery.name = "NetDiscovery"
	discovery.probe_local = bool(cli.get("local", false))
	add_child(discovery)
	session.log_line.connect(func(t): netlog.write("ENet: " + t))
	session.state_changed.connect(_on_state)
	session.players_changed.connect(_on_players)
	discovery.log_line.connect(func(t): netlog.write("Suche: " + t))
	discovery.games_changed.connect(_rebuild_games)
	netlog.line_added.connect(func(_t): _update_log())
	_build_ui()
	netlog.write("=== Netztest gestartet: Draw2Race %s, Protokoll %d, Physik %s, %s %s, Gerät „%s“, Name „%s“%s ===" % [Proto.game_version(),
		Proto.VERSION, Proto.physics_version(), OS.get_name(), OS.get_version(), OS.get_model_name(), player_name,
		(", Automatik " + JSON.stringify(cli)) if not cli.is_empty() else ""])
	netlog.write("Protokolldatei: " + netlog.global_path())
	_refresh_net(true)
	if not cli.is_empty():
		_cli_begin()

func _default_name() -> String:
	if OS.get_name() == "Android":
		return Proto.clean_name(OS.get_model_name(), "Handy")
	return "PC"

func _exit_tree() -> void:
	_shutdown()

func _notification(what: int) -> void:
	# Android-Zurück-Taste: erst die Adresseingabe schließen, dann den Netztest (das Spiel selbst ignoriert sie im Menü).
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and cli.is_empty() and is_inside_tree() and not is_queued_for_deletion():
		if address_panel != null and address_panel.visible:
			address_panel.visible = false
		else:
			close()

func close() -> void:
	netlog.write("Netztest geschlossen")
	_shutdown()
	closed.emit()
	queue_free()

func _shutdown() -> void:
	if session != null:
		session.close("Netztest beendet")
	if discovery != null:
		discovery.stop()
	if bound:
		var ok := Android.unbind()
		netlog.write("WLAN-Bindung gelöst: %s" % ("ja" if ok else "FEHLER"))
		bound = false
	if Android.available():
		Android.multicast(false)

# --- Aktionen ---

func start_host() -> void:
	_stop_all()
	activity = "host"
	_multicast()
	if session.host(player_name, game_port) != OK:
		activity = ""
		return
	discovery.start_host({"name": player_name, "port": game_port, "players": 1, "max": Proto.MAX_PLAYERS})
	_log_addresses()

func start_search() -> void:
	_stop_all()
	activity = "search"
	_multicast()
	discovery.gateway = Android.wifi_gateway(net_state)
	netlog.write("Gateway-Probe: " + (discovery.gateway if discovery.gateway != "" else "kein Gateway bekannt"))
	discovery.clear_games()
	discovery.start_search()

func join(address: String, port: int) -> void:
	discovery.stop()
	session.close()
	activity = "join"
	join_target = {"address": address, "port": port}
	if cli.has("fake_version"):
		session.hello_override = {"game": str(cli.fake_version)}
	session.join(address, port, player_name)

func stop() -> void:
	_stop_all()
	netlog.write("Getrennt (Hand)")

func _stop_all() -> void:
	session.close()
	discovery.stop()
	activity = ""

func toggle_bind() -> void:
	if not Android.available():
		netlog.write("„An WLAN binden“ gibt es nur auf Android.")
		return
	if bound:
		var ok := Android.unbind()
		bound = false
		netlog.write("WLAN-Bindung gelöst: %s" % ("ja" if ok else "FEHLER"))
	else:
		var problem := Android.bind_wifi()
		bound = problem == ""
		netlog.write("An WLAN binden: %s" % ("gebunden" if bound else "FEHLER – " + problem))
	_refresh_net(true)
	# Die Bindung gilt nur für neue Sockets: laufende Sitzung/Suche neu aufbauen.
	match activity:
		"host":
			netlog.write("Host wird mit neuer Bindung neu gestartet")
			start_host()
		"search":
			netlog.write("Suche wird mit neuer Bindung neu gestartet")
			start_search()
		"join":
			netlog.write("Verbindung wird mit neuer Bindung neu aufgebaut")
			join(str(join_target.address), int(join_target.port))
	_update_ui()

func _multicast() -> void:
	if Android.available():
		netlog.write("Multicast-Sperre: %s" % ("gehalten" if Android.multicast(true) else "FEHLER (Berechtigung?)"))

func _log_addresses() -> void:
	var ips := []
	for i in Android.interfaces():
		ips.append("%s/%d" % [i.address, i.prefix])
	netlog.write("Eigene Adressen: " + (", ".join(ips) if ips.size() > 0 else "keine"))

# --- Ereignisse ---

func _on_state(state: String, text: String) -> void:
	netlog.write("Zustand: %s – %s" % [state, text])
	_update_ui()

func _on_players(list: Array) -> void:
	netlog.write("Spieler: " + ", ".join(list.map(func(p): return "%d %s%s" % [p.id, p.name, " (Host)" if p.host else ""])))
	if session.is_host:
		discovery.update_host_info({"players": list.size()})
	_update_ui()

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if now >= _next_net_ms:
		_refresh_net(false)
	if now >= _next_ping_log_ms:
		_next_ping_log_ms = now + 5000
		_log_pings()
	if now >= _next_ui_ms:
		_next_ui_ms = now + 250
		_update_ui()
		_rebuild_games()
	if not cli.is_empty() and not _cli_done:
		_cli_tick(now)

func _refresh_net(force: bool) -> void:
	_next_net_ms = Time.get_ticks_msec() + 2000
	net_state = Android.state()
	var lines := Android.summary(net_state)
	if force or lines != _net_lines:
		_net_lines = lines
		netlog.write("Netz: " + " | ".join(lines))
		if net_state.get("android", false) and force:
			netlog.write("Netz (roh): " + JSON.stringify(net_state))
	if net_state.get("android", false):
		bound = net_state.get("bound") is Dictionary
	if net_label != null:
		net_label.text = "\n".join(lines)

func _log_pings() -> void:
	if not session.is_ready():
		return
	for id in (session.accepted_ids() if session.is_host else [1]):
		var s := session.stats(id)
		if not s.is_empty():
			netlog.write("Ping %d „%s“: %s" % [id, session.peers[id].name, _stats_text(s)])

static func _stats_text(s: Dictionary) -> String:
	if int(s.get("received", 0)) == 0:
		return "noch keine Antwort (%d gesendet)" % int(s.get("sent", 0))
	return "RTT %.1f ms (min %.1f / Ø %.1f / max %.1f), Jitter %.1f ms, Verlust %.1f %% (zuletzt %.0f %%, Anlauf %d), %d/%d (offen %d), Uhrversatz %+.1f ms, ENet-RTT %d ms, Drossel %d/32" % [
		s.rtt_ms, s.min_ms, s.avg_ms, s.max_ms, s.jitter_ms, s.loss_pct, s.recent_loss_pct, int(s.get("early_lost", 0)), s.received, s.sent, int(s.get("pending", 0)), s.offset_ms, int(s.get("enet_rtt_ms", -1)), int(s.get("enet_throttle", -1))]

# --- Automatik (PC-Tests) ---

func _cli_begin() -> void:
	Engine.max_fps = 60
	_cli_start_ms = Time.get_ticks_msec()
	if cli.has("error"):
		_cli_finish(false, str(cli.error))
		return
	match str(cli.mode):
		"host":
			start_host()
		"search":
			start_search()
		"join":
			if cli.has("address"):
				join(str(cli.address), int(cli.port))
			else:
				start_search()

func _cli_tick(now: int) -> void:
	var elapsed := (now - _cli_start_ms) / 1000.0
	var timeout := float(cli.get("timeout", 30.0))
	var mode := str(cli.mode)
	if mode == "host":
		if session.state == "closed":
			_cli_finish(false, "Host beendet: " + session.detail)
			return
		var clients := session.accepted_ids().size()
		_cli_max_clients = maxi(_cli_max_clients, clients)
		var expect := int(cli.get("expect", 0))
		if expect > 0 and _cli_max_clients >= expect and clients == 0:
			_cli_finish(true, "host mitspieler=%d abgelehnt=%d" % [_cli_max_clients, session.rejected_count])
		elif elapsed > timeout:
			_cli_finish(expect == 0 or _cli_max_clients >= expect, "host Zeitgrenze, mitspieler=%d von %d, abgelehnt=%d" % [_cli_max_clients, expect, session.rejected_count])
		return
	if mode == "search" or (mode == "join" and activity == "search"):
		var games := discovery.sorted_games()
		if games.size() > 0 and _cli_found_ms < 0:
			_cli_found_ms = discovery.elapsed_ms()
		if mode == "join" and games.size() > 0 and games[0].compatible:
			var g: Dictionary = games[0]
			_cli_found_via = discovery.via_text(g)
			netlog.write("Automatik: trete „%s“ %s:%d bei (gefunden über %s nach %d ms)" % [g.name, g.address, g.port, _cli_found_via, _cli_found_ms])
			join(str(g.address), int(g.port))
		elif mode == "search" and _cli_found_ms >= 0 and discovery.elapsed_ms() - _cli_found_ms > 3000:
			_cli_finish(true, "search gefunden=" + "; ".join(games.map(func(g): return "%s %s:%d über %s" % [g.name, g.address, g.port, discovery.via_text(g)])))
		elif elapsed > timeout:
			_cli_finish(false, "%s kein Host gefunden (Zähler: %s)" % [mode, discovery.stats_text()])
		return
	# join: verbinden, dann eine Weile pingen
	match session.state:
		"rejected":
			var expected := cli.has("fake_version")
			_cli_finish(expected, "join abgelehnt%s: %s" % [" (erwartet)" if expected else "", session.detail])
		"closed":
			_cli_finish(false, "join getrennt: " + session.detail)
		"connected":
			if _cli_connected_ms == 0:
				_cli_connected_ms = now
			if now - _cli_connected_ms > int(float(cli.get("duration", 4.0)) * 1000.0):
				var s := session.stats(1)
				var ok := int(s.get("received", 0)) > 0 and not cli.has("fake_version")
				session.send(1, {"t": "bye"})
				_cli_finish(ok, "join %s:%d als „%s“ (id %d)%s, spieler=%d, %s" % [join_target.address, join_target.port, session.my_name,
					session.my_id, (", gefunden über " + _cli_found_via + " nach %d ms" % _cli_found_ms) if _cli_found_via != "" else "",
					session.players.size(), _stats_text(s)])
	if not _cli_done and elapsed > timeout:
		_cli_finish(false, "join Zeitgrenze im Zustand %s: %s" % [session.state, session.detail])

func _cli_finish(ok: bool, text: String) -> void:
	_cli_done = true
	var line := "NETTEST-ERGEBNIS: %s %s" % ["OK" if ok else "FEHLER", text]
	netlog.write(line)
	if not netlog.echo:
		print(line)
	_shutdown()
	# kurz warten, damit Abmeldung/Trennung noch hinausgeht
	await get_tree().create_timer(0.3).timeout
	get_tree().quit(0 if ok else 1)

# --- Oberfläche ---

func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var theme := Theme.new()
	var regular := FontVariation.new()
	regular.base_font = load("res://assets/Outfit.ttf")
	regular.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 500.0}
	theme.default_font = regular
	theme.default_font_size = 24
	bold = FontVariation.new()
	bold.base_font = regular.base_font
	bold.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 700.0}
	root.theme = theme
	add_child(root)
	var back := ColorRect.new()
	back.color = BACK
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(back)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	root.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)
	# Kopfzeile
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	column.add_child(head)
	var title := _label(head, "NETZTEST", 44, PAPER)
	title.add_theme_font_override("font", bold)
	var info := _label(head, "Draw2Race %s · Protokoll %d · %s · Name „%s“" % [Proto.game_version(), Proto.VERSION, OS.get_model_name(), player_name], 22, Color("a9c4c2"))
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_button(head, "Schließen", close, 200)
	# Bedienleiste
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 14)
	column.add_child(bar)
	host_button = _button(bar, "Host starten", start_host, 0, true)
	search_button = _button(bar, "Mitspielen", start_search, 0, true)
	_button(bar, "Adresse eingeben", _show_address, 0)
	bind_button = _button(bar, "An WLAN binden: aus", toggle_bind, 0)
	_button(bar, "Trennen", stop, 0)
	for b in bar.get_children():
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Mitte: Spiele links, Verbindung und Netz rechts
	var middle := HBoxContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", 16)
	column.add_child(middle)
	var left := _panel(middle)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.9
	var left_box := VBoxContainer.new()
	left_box.add_theme_constant_override("separation", 10)
	left.add_child(left_box)
	games_title = _label(left_box, "Gefundene Spiele", 28, INK)
	games_title.add_theme_font_override("font", bold)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_box.add_child(scroll)
	games_box = VBoxContainer.new()
	games_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	games_box.add_theme_constant_override("separation", 10)
	scroll.add_child(games_box)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.1
	right.add_theme_constant_override("separation", 16)
	middle.add_child(right)
	var conn_panel := _panel(right)
	conn_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var conn_box := VBoxContainer.new()
	conn_panel.add_child(conn_box)
	status_label = _label(conn_box, "Bereit.", 28, INK)
	status_label.add_theme_font_override("font", bold)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	conn_label = _label(conn_box, "", 21, INK)
	conn_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var net_panel := _panel(right)
	net_label = _label(net_panel, "", 19, MUTED)
	net_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Protokoll
	var log_panel := _panel(column, Color("08262b"))
	log_panel.custom_minimum_size = Vector2(0, 190)
	log_label = _label(log_panel, "", 17, Color("cfe0dc"))
	log_label.clip_text = true
	log_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_build_address_panel(root)
	_rebuild_games()
	_update_ui()
	_update_log()

func _build_address_panel(root: Control) -> void:
	# Abgedunkelte Ebene mit dem Eingabefeld im oberen Bildteil (die Bildschirmtastatur verdeckt unten).
	address_panel = Control.new()
	address_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	address_panel.visible = false
	root.add_child(address_panel)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.08, 0.09, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	address_panel.add_child(dim)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_top = 40
	address_panel.add_child(column)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _style(PAPER, 24, 30))
	card.custom_minimum_size = Vector2(820, 0)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	card.add_child(box)
	var t := _label(box, "Adresse des Hosts", 32, INK)
	t.add_theme_font_override("font", bold)
	var hint := _label(box, "z. B. 192.168.43.1 oder 192.168.43.1:%d – im Handy-Hotspot ist der Host das Gateway." % Proto.GAME_PORT, 20, MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	address_edit = LineEdit.new()
	address_edit.custom_minimum_size = Vector2(0, 84)
	address_edit.add_theme_font_size_override("font_size", 36)
	address_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL
	address_edit.placeholder_text = "192.168.x.y"
	var field := _style(Color.WHITE, 14, 18)
	field.border_color = Color("9fb3b0")
	field.set_border_width_all(2)
	address_edit.add_theme_stylebox_override("normal", field)
	var focus := field.duplicate() as StyleBoxFlat
	focus.border_color = ORANGE
	address_edit.add_theme_stylebox_override("focus", focus)
	address_edit.add_theme_color_override("font_color", INK)
	address_edit.add_theme_color_override("font_placeholder_color", Color("9aa7a4"))
	address_edit.add_theme_color_override("caret_color", ORANGE)
	address_edit.text_submitted.connect(func(_t): _connect_address())
	box.add_child(address_edit)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	var go := _button(row, "Verbinden", _connect_address, 0, true)
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var probe := _button(row, "Nur anfragen", _probe_address, 0)
	probe.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cancel := _button(row, "Abbrechen", func(): address_panel.visible = false, 0)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _show_address() -> void:
	if address_edit.text.strip_edges() == "":
		address_edit.text = Android.wifi_gateway(net_state)
	address_panel.visible = true
	address_edit.grab_focus()

func _read_address() -> Dictionary:
	var target := Proto.parse_address(address_edit.text, game_port)
	if target.is_empty():
		netlog.write("Ungültige Adresse: „%s“" % address_edit.text)
	return target

func _connect_address() -> void:
	var target := _read_address()
	if target.is_empty():
		return
	address_panel.visible = false
	netlog.write("Adresse eingegeben: %s:%d – verbinde direkt" % [target.address, target.port])
	join(target.address, target.port)

func _probe_address() -> void:
	# Suchanfrage nur an diese Adresse (Unicast), ohne zu verbinden – zeigt, ob der Weg dorthin offen ist.
	var target := _read_address()
	if target.is_empty():
		return
	address_panel.visible = false
	discovery.add_manual(target.address)
	netlog.write("Adresse eingegeben: %s – frage per Suchanfrage an" % target.address)
	if activity != "search":
		start_search()

func _rebuild_games() -> void:
	if games_box == null:
		return
	var list := discovery.sorted_games()
	# Nur neu aufbauen, wenn sich Inhalt oder Zustand geändert hat (sonst verschluckt der Neuaufbau Fingertipps).
	var signature := "%s|%s|%d" % [activity, discovery.mode, discovery.manual.size()] + "|".join(list.map(func(g): return "%s:%d %s %d %s" % [g.address, g.port, g.name, g.players, discovery.via_text(g)]))
	if signature == _games_signature:
		return
	_games_signature = signature
	for child in games_box.get_children():
		child.queue_free()
	games_title.text = "Gefundene Spiele (%d)" % list.size()
	if list.is_empty():
		var hint := "Tippe „Mitspielen“, um zu suchen." if discovery.mode != "search" else "Suche läuft … (Rundruf, Gateway%s)" % (", Adresse" if discovery.manual.size() > 0 else "")
		if activity == "host":
			var ips := []
			for i in net_state.get("interfaces", []):
				if i is Dictionary:
					ips.append(str(i.get("address", "")))
			hint = "Du bist Host. Mitspieler tippen „Mitspielen“ oder geben eine dieser Adressen ein:\n%s" % ("\n".join(ips) if ips.size() > 0 else "keine Adresse gefunden")
		var l := _label(games_box, hint, 22, MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		return
	for g in list:
		var text := "%s – %s:%d\n%d/%d Spieler · über %s%s%s" % [g.name, g.address, g.port, g.players, g.max, discovery.via_text(g),
			" · Antwort %.0f ms" % g.reply_ms if g.has("reply_ms") else "", " · " + g.note if g.note != "" else ""]
		var b := _button(games_box, text, join.bind(str(g.address), int(g.port)), 0, g.compatible)
		b.custom_minimum_size = Vector2(0, 96)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 22)
		b.disabled = not g.compatible

func _update_ui() -> void:
	if status_label == null:
		return
	bind_button.text = "An WLAN binden: " + ("AN" if bound else "aus")
	bind_button.disabled = not Android.available()
	var state_text := {"idle": "Bereit.", "hosting": "Host läuft", "connecting": "Verbinde …", "handshake": "Anmeldung …",
		"connected": "Verbunden", "rejected": "Abgelehnt", "closed": "Getrennt"}
	var head: String = state_text.get(session.state, session.state)
	if activity == "search" and not session.is_active():
		head = "Suche läuft … %.0f s" % (discovery.elapsed_ms() / 1000.0)
	status_label.text = head
	status_label.add_theme_color_override("font_color", RED if session.state in ["rejected", "closed"] and activity != "search" else (GREEN if session.is_ready() else INK))
	var lines := []
	if session.detail != "" and activity != "search":
		lines.append(session.detail)
	if session.is_ready():
		if session.is_host:
			lines.append("Mitspieler: %d von %d" % [session.accepted_ids().size(), Proto.MAX_CLIENTS])
			for id in session.accepted_ids():
				lines.append("• %s (%s): %s" % [session.peers[id].name, session.peers[id].address, _stats_text(session.stats(id))])
		else:
			lines.append("Host: %s:%d" % [session.host_address, session.port])
			lines.append(_stats_text(session.stats(1)))
			lines.append("Spieler: " + ", ".join(session.players.map(func(p): return p.name)))
	if activity == "search":
		lines.append("Zähler: " + (discovery.stats_text() if discovery.stats_text() != "" else "–"))
	conn_label.text = "\n".join(lines)

func _update_log() -> void:
	if log_label == null:
		return
	var tail := netlog.lines.slice(maxi(0, netlog.lines.size() - 6))
	log_label.text = "\n".join(tail.map(func(l): return str(l).substr(11)))

func _style(color: Color, radius := 18, pad := 20) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.6
	s.content_margin_bottom = pad * 0.6
	return s

func _panel(parent: Node, color := PAPER) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _style(color, 22, 22))
	parent.add_child(p)
	return p

func _label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.text = text
	parent.add_child(l)
	return l

func _button(parent: Node, text: String, action: Callable, width := 0, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 84)
	b.add_theme_stylebox_override("normal", _style(ORANGE if primary else Color("e6e6dc"), 14))
	b.add_theme_stylebox_override("hover", _style(Color("f6805e") if primary else Color("d6dfd6"), 14))
	b.add_theme_stylebox_override("pressed", _style(Color("d65538") if primary else Color("bfd0c7"), 14))
	b.add_theme_stylebox_override("disabled", _style(Color("aab5b0"), 14))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(key, Color.WHITE if primary else INK)
	b.add_theme_color_override("font_disabled_color", Color("5d6b68"))
	b.add_theme_font_size_override("font_size", 26)
	b.pressed.connect(action)
	parent.add_child(b)
	return b
