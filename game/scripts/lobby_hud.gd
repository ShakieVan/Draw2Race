class_name LobbyScreens
extends RefCounted

# Bildschirme des WLAN-Mehrspielers (M3/M4): Eröffnen/Beitreten mit Live-Liste der gefundenen Spiele und Adresseingabe, Netzhinweis
# (kein WLAN → Handy-Hotspot vorschlagen), Lobby (Spielerliste mit Name, Spielerfarbe, Auto, Bereit, Ping; Einstellungen des
# Gastgebers; eigener Name, eigenes Auto und eigene Farbe über die Garage wie im Einzelspieler; Bereit bzw. Start), der Startbildschirm (Strecke wird geladen) und das gemeinsame Zeichnen (3-2-1, Stand der
# anderen beim Zeichnen und Warten, Linie abgeben, Enthüllung), im Rennen (M5) Hinweise und Funkstille sowie die Wertung vom
# Gastgeber mit Revanche bzw. Lobby. Bausteine und Raster wie
# party_hud.gd (1440×900). Reine Oberfläche: Zustand und Regeln stehen in NetLobby (app.lobby), den Ablauf steuert main.gd.
# Aktualisiert wird an Ort und Stelle (Texte, Farben); neu aufgebaut werden nur Teile, deren Inhalt sich ändert – ein Neuaufbau je
# Sekunde (Ping) würde sonst Fingertipps verschlucken und dem Namensfeld den Fokus nehmen.

const INK := RaceHUD.INK
const MUTED := RaceHUD.MUTED
const PAPER := RaceHUD.PAPER
const ORANGE := RaceHUD.ORANGE
const GREEN := Color("2f8f5b")
const RED := Color("c2453a")
const ROWS := 4

var hud: RaceHUD
var app: Node
var screen := ""                  # "" | "wlan" | "lobby" | "round" | "draw" | "reveal" | "start" | "race" | "result" – was gerade aufgebaut ist
var status_label: Label
var games_box: Control
var games_title: Label
var search_hint: Label
var count_label: Label
var address_label: Label
var rows: Array = []              # je Platz {panel, chip, name, car, state, ping}
var settings_box: Control
var start_button: Button
var ready_button: Button
var problem_label: Label
var own_car_button: Button       # eigenes Auto: öffnet die Garage
var own_car_dot: Panel
var name_edit: LineEdit
var round_status: Label
var round_players: Label
var round_button: Button
var toast_label: Label
var draw_box: Panel               # Zeichnen: Stand der anderen (oben rechts)
var draw_rows: Array = []         # je anderem Spieler {id, state: Label}
var countdown_label: Label
var wait_title: Label
var redraw_button: Button
var reveal_label: Label
var stale_pill: Panel             # Rennen: „Verbindung zum Gastgeber hakt …“
var _draw_sig := "-"
var _toast_until := 0
var _games_sig := "-"
var _settings_sig := "-"
var _garage_sig := "-"

func _init(owner_hud: RaceHUD) -> void:
	hud = owner_hud
	app = owner_hud.app

func lobby() -> NetLobby:
	return app.lobby

static func player_color(p: Dictionary) -> Color:
	# Spielerfarbe eines Lobby- bzw. Rundeneintrags (Lack, Schild, Linie, Turbo-Knopf; PlayerColors).
	return PlayerColors.color(int(p.get("color", 0)))

static func on_color(c: Color) -> Color:
	return Color.WHITE if c.get_luminance() < 0.6 else INK

# ---------- Netzstatus ----------
func status_text() -> Array:
	# [Text, Hinweis?] zum Netz: WLAN verbunden (und gebunden), eigener Hotspot an, oder klarer Hinweis ohne WLAN.
	var st: Dictionary = lobby().status
	var hotspot: Array = st.get("hotspot", [])
	if not hotspot.is_empty():
		return ["Dein Handy-Hotspot ist an (%s). Eröffne hier das Spiel – die anderen verbinden sich mit deinem Hotspot und tippen „Beitreten“." % ", ".join(hotspot), false]
	if bool(st.get("wifi", false)):
		var ips: Array = st.get("addresses", [])
		var text := "Im WLAN%s." % (" als %s" % ips[0] if not ips.is_empty() else "")
		if bool(st.get("android", false)):
			text += " Das Spiel ist ans WLAN gebunden – mobile Daten stören nicht." if bool(st.get("bound", false)) else " WLAN-Bindung nicht möglich%s." % (": " + str(st.problem) if str(st.get("problem", "")) != "" else "")
		return [text, false]
	return ["Kein WLAN verbunden. Verbindet alle Handys mit demselben WLAN – oder schaltet auf einem Handy den mobilen Hotspot ein " +
		"(Einstellungen → Verbindungen → Mobiler Hotspot) und verbindet die anderen damit. Internet braucht ihr nicht.", true]

# ---------- Eröffnen / Beitreten ----------
func wlan_screen() -> void:
	hud.clear()
	hud.backdrop.visible = true
	screen = "wlan"
	_games_sig = "-"
	hud.header("MEHRSPIELER     /     IM WLAN")
	var left := hud.panel(hud.content, Rect2(40, 120, 560, 724))
	hud.label(left, "SPIEL ERÖFFNEN", Vector2(28, 20), 13, ORANGE)
	hud.label(left, "Gastgeber sein", Vector2(24, 44), 40)
	hud.label(left, "Du wählst Strecke, Herausforderung und KI-Gegner. Die anderen treten über „Beitreten“ bei – im selben WLAN oder in deinem Handy-Hotspot.",
		Vector2(28, 108), 17, MUTED, 504)
	var host := hud.button(left, "Spiel eröffnen  →", Rect2(28, 236, 504, 76), app.net_host, true)
	host.name = "HostButton"
	hud.label(left, "DEIN NAME", Vector2(28, 340), 13, MUTED)
	hud.label(left, app.store.player_name(), Vector2(28, 366), 26, INK, 340)
	hud.button(left, "Ändern", Rect2(392, 356, 140, 56), func(): hud.name_settings(func(): app.lobby.my_name = app.store.player_name(); wlan_screen()))
	hud.label(left, "NETZ", Vector2(28, 448), 13, MUTED)
	status_label = hud.label(left, "", Vector2(28, 474), 16, INK, 504)
	status_label.name = "NetStatus"
	var right := hud.panel(hud.content, Rect2(620, 120, 780, 724))
	hud.label(right, "BEITRETEN", Vector2(28, 20), 13, ORANGE)
	games_title = hud.label(right, "Gefundene Spiele", Vector2(24, 44), 40)
	search_hint = hud.label(right, "", Vector2(28, 108), 16, MUTED, 724)
	games_box = Control.new()
	games_box.name = "GamesBox"
	games_box.position = Vector2(28, 150)
	games_box.size = Vector2(724, 440)
	games_box.mouse_filter = Control.MOUSE_FILTER_PASS
	right.add_child(games_box)
	var manual := hud.button(right, "Adresse eingeben", Rect2(28, 620, 360, 72), address_dialog)
	manual.name = "AddressButton"
	hud.button(right, "Neu suchen", Rect2(404, 620, 348, 72), func(): app.lobby.search())
	_add_toast()
	refresh()

func _refresh_wlan() -> void:
	var lb := lobby()
	if is_instance_valid(status_label):
		var st := status_text()
		status_label.text = str(st[0])
		status_label.add_theme_color_override("font_color", ORANGE if st[1] else INK)
	if not is_instance_valid(games_box):
		return
	var list := lb.games()
	search_hint.text = ("Suche läuft … (Rundruf, Ankündigung%s)" % (", Gateway " + lb.discovery.gateway if lb.discovery.gateway != "" else "")) if lb.mode == "search" else "Suche angehalten."
	var sig := "|".join(list.map(func(g): return "%s %s:%d %d/%d %s %s %s" % [g.name, g.address, g.port, g.players, g.max, g.compatible, g.get("busy", false), lb.discovery.via_text(g)]))
	if sig == _games_sig:
		return
	_games_sig = sig
	games_title.text = "Gefundene Spiele (%d)" % list.size() if not list.is_empty() else "Gefundene Spiele"
	for child in games_box.get_children():
		games_box.remove_child(child)
		child.queue_free()
	if list.is_empty():
		hud.label(games_box, "Noch kein Spiel gefunden. Eröffnet auf einem Handy ein Spiel – es erscheint hier von selbst. " +
			"Klappt das nicht, gebt die Adresse ein, die der Gastgeber in seiner Lobby sieht.", Vector2(0, 8), 18, MUTED, 720)
		return
	for k in range(mini(list.size(), 4)):
		var g: Dictionary = list[k]
		var full: bool = int(g.players) >= int(g.max)
		var busy: bool = bool(g.get("busy", false))
		var note := str(g.note) if not g.compatible else ("Rennen läuft" if busy else ("voll" if full else "über " + lb.discovery.via_text(g)))
		var text := "%s   ·   %d/%d Spieler\n%s  ·  %s" % [g.name, int(g.players), int(g.max), note, g.address]
		var b := hud.button(games_box, text, Rect2(0, k * 106, 724, 96), app.net_join.bind(str(g.address), int(g.port), str(g.name)), g.compatible and not full and not busy)
		b.name = "Game%d" % k
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", RaceHUD.readable(19))
		b.disabled = not g.compatible or full or busy

func address_dialog() -> void:
	# Eigene Ebene mit dem Eingabefeld im oberen Bildteil (die Bildschirmtastatur verdeckt unten).
	var shade := ColorRect.new()
	shade.name = "AddressDialog"
	shade.color = Color(0.035, 0.12, 0.15, 0.78)
	shade.position = -hud.content.position
	shade.size = hud.get_viewport().get_visible_rect().size
	hud.content.add_child(shade)
	var p := hud.panel(shade, Rect2(Vector2(330, 40) + hud.content.position, Vector2(780, 400)))
	hud.label(p, "Adresse des Gastgebers", Vector2(32, 22), 32)
	var gateway: String = lobby().status.get("gateway", "")
	hud.label(p, "Der Gastgeber sieht sie in seiner Lobby, z. B. 192.168.1.20. Im Handy-Hotspot ist der Gastgeber meist das Gateway%s." % (" (%s)" % gateway if gateway != "" else ""),
		Vector2(34, 78), 16, MUTED, 712)
	var field := LineEdit.new()
	field.name = "AddressEdit"
	field.position = Vector2(34, 172)
	field.size = Vector2(712, 76)
	field.text = gateway
	field.placeholder_text = "192.168.x.y"
	field.virtual_keyboard_enabled = true
	field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL
	field.select_all_on_focus = true
	field.add_theme_font_size_override("font_size", RaceHUD.readable(30))
	field.add_theme_font_override("font", hud.bold_font)
	field.add_theme_color_override("font_color", INK)
	field.add_theme_color_override("font_placeholder_color", Color(MUTED, 0.75))
	field.add_theme_color_override("caret_color", ORANGE)
	field.add_theme_stylebox_override("normal", hud.style(Color("ffffff"), 14, Color("c9cfc4")))
	field.add_theme_stylebox_override("focus", hud.style(Color.TRANSPARENT, 14, ORANGE))
	p.add_child(field)
	var error := hud.label(p, "", Vector2(34, 254), 15, RED, 712)
	var go := func():
		var target := NetProtocol.parse_address(field.text, lobby().game_port)
		if target.is_empty():
			error.text = "Das ist keine gültige Adresse (vier Zahlen mit Punkt, z. B. 192.168.1.20)."
			return
		shade.queue_free()
		app.net_join(str(target.address), int(target.port), str(target.address))
	field.text_submitted.connect(func(_t): go.call())
	var connect := hud.button(p, "Verbinden", Rect2(34, 300, 460, 70), go, true)
	connect.name = "AddressConnect"
	hud.button(p, "Abbrechen", Rect2(510, 300, 236, 70), func(): shade.queue_free())
	field.grab_focus.call_deferred()

func connecting(target: String) -> void:
	var p := hud.overlay("Verbinde …", "mit „%s“. Das dauert meist unter einer Sekunde." % target, Vector2(640, 330))
	p.get_parent().name = "ConnectCard"
	hud.button(p, "Abbrechen", Rect2(34, 220, 572, 66), func(): app.net_cancel_join())

func message(title: String, text: String) -> void:
	var p := hud.overlay(title, text, Vector2(700, 340))
	p.get_parent().name = "NetMessage"
	var ok := hud.button(p, "OK", Rect2(34, 244, 632, 66), func(): p.get_parent().queue_free(), true)
	ok.name = "MessageOk"

func confirm(title: String, text: String, yes: String, action: Callable) -> void:
	var p := hud.overlay(title, text, Vector2(700, 440))
	p.get_parent().name = "NetConfirm"
	var b := hud.button(p, yes, Rect2(34, 250, 632, 66), func(): p.get_parent().queue_free(); action.call(), true)
	b.name = "ConfirmYes"
	hud.button(p, "Bleiben", Rect2(34, 336, 632, 66), func(): p.get_parent().queue_free())

func close_dialogs() -> void:
	hud.close_overlays()
	for c in hud.content.get_children():
		if c.name == "AddressDialog":
			c.queue_free()

func dialog_open() -> bool:
	return hud.overlay_open()

# ---------- Lobby ----------
func lobby_screen() -> void:
	var lb := lobby()
	hud.clear()
	hud.backdrop.visible = true
	screen = "lobby"
	_settings_sig = "-"
	hud.header("MEHRSPIELER     /     LOBBY VON %s" % lb.host_name().to_upper())
	var left := hud.panel(hud.content, Rect2(40, 120, 700, 724))
	hud.label(left, "FAHRER", Vector2(28, 20), 13, ORANGE)
	count_label = hud.label(left, "", Vector2(24, 44), 40)
	count_label.name = "PlayerCount"
	address_label = hud.label(left, "", Vector2(268, 48), 15, MUTED, 410)
	address_label.name = "HostAddress"
	rows.clear()
	for k in range(ROWS):
		rows.append(_player_row(left, k))
	hud.label(left, "DEIN NAME, AUTO UND FARBE", Vector2(28, 538), 13, MUTED)
	name_edit = _name_field(left, Rect2(28, 566, 300, 66))
	# Auto und Farbe: Tippen öffnet die Garage (wie im Einzelspieler, mit allen Autos, lackiert in der Spielerfarbe).
	own_car_button = hud.button(left, "", Rect2(344, 566, 336, 66), app.net_garage)
	own_car_button.name = "CarButton"
	own_car_button.add_theme_font_size_override("font_size", 20)
	own_car_button.clip_text = true
	own_car_dot = Panel.new()
	own_car_dot.position = Vector2(16, 19)
	own_car_dot.size = Vector2(28, 28)
	own_car_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	own_car_button.add_child(own_car_dot)
	hud.label(left, "Alle Strecken und Autos sind frei, Autos auch doppelt – jeder hat seine Farbe. Dein Fortschritt bleibt unberührt.",
		Vector2(28, 652), 12, MUTED, 644)
	var right := hud.panel(hud.content, Rect2(760, 120, 640, 724))
	settings_box = Control.new()
	settings_box.name = "SettingsBox"
	settings_box.size = Vector2(640, 560)
	settings_box.mouse_filter = Control.MOUSE_FILTER_PASS
	right.add_child(settings_box)
	problem_label = hud.label(right, "", Vector2(28, 568), 16, MUTED, 584)
	problem_label.name = "StartProblem"
	if lb.is_host():
		start_button = hud.button(right, "Rennen starten  →", Rect2(28, 624, 584, 76), app.net_start, true)
		start_button.name = "StartButton"
		ready_button = null
	else:
		ready_button = hud.button(right, "Ich bin bereit", Rect2(28, 624, 584, 76), func(): app.lobby.set_ready(not bool(app.lobby.me().get("ready", false))), true)
		ready_button.name = "ReadyButton"
		start_button = null
	_add_toast()
	refresh()

func _player_row(parent: Control, k: int) -> Dictionary:
	var row := hud.panel(parent, Rect2(20, 108 + k * 104, 660, 96), Color("ffffff"))
	row.name = "PlayerRow%d" % k
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chip := Panel.new()
	chip.position = Vector2(14, 14)
	chip.size = Vector2(14, 68)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(chip)
	var name := hud.label(row, "", Vector2(44, 10), 26, INK)
	var car := hud.label(row, "", Vector2(46, 52), 15, MUTED, 330)
	var state := hud.label(row, "", Vector2(392, 14), 18, INK, 250)
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var ping := hud.label(row, "", Vector2(392, 54), 11, MUTED, 250)
	ping.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return {"panel": row, "chip": chip, "name": name, "car": car, "state": state, "ping": ping}

func _name_field(parent: Control, rect: Rect2) -> LineEdit:
	var field := LineEdit.new()
	field.name = "LobbyName"
	field.position = rect.position
	field.size = rect.size
	field.max_length = ProgressStore.NAME_MAX
	field.text = app.store.player_name()
	field.placeholder_text = app.store.default_name()
	field.virtual_keyboard_enabled = true
	field.select_all_on_focus = true
	field.add_theme_font_size_override("font_size", RaceHUD.readable(22))
	field.add_theme_font_override("font", hud.bold_font)
	field.add_theme_color_override("font_color", INK)
	field.add_theme_color_override("font_placeholder_color", Color(MUTED, 0.75))
	field.add_theme_color_override("caret_color", ORANGE)
	field.add_theme_stylebox_override("normal", hud.style(Color("f4f0e5"), 12, Color("c9cfc4")))
	field.add_theme_stylebox_override("focus", hud.style(Color.TRANSPARENT, 12, ORANGE))
	parent.add_child(field)
	# Wie in den Optionen: unerlaubte Zeichen schon beim Tippen weglassen; übernommen beim Bestätigen oder Verlassen des Felds.
	field.text_changed.connect(func(text: String):
		var ok := ProgressStore.filter_name(text)
		if ok != text:
			var caret := field.caret_column
			field.text = ok
			field.caret_column = mini(caret, ok.length()))
	field.text_submitted.connect(func(_t: String): app.net_set_name(field.text); field.release_focus())
	field.focus_exited.connect(func(): if is_instance_valid(field): app.net_set_name(field.text))
	return field

func _refresh_lobby() -> void:
	var lb := lobby()
	if not is_instance_valid(count_label):
		return
	count_label.text = "%d von %d" % [lb.players.size(), NetProtocol.MAX_PLAYERS]
	if lb.is_host():
		var ips: Array = lb.status.get("hotspot", []) + lb.status.get("addresses", [])
		var unique: Array = []
		for ip in ips:
			if not ip in unique:
				unique.append(ip)
		address_label.text = "Adresse zum Eintippen: %s" % (", ".join(unique.slice(0, 2)) if not unique.is_empty() else "unbekannt")
	else:
		var ping := lb.ping_of(lb.me())
		address_label.text = "Gastgeber %s%s" % [lb.session.host_address, "  ·  Ping %d ms" % ping if ping >= 0 else ""]
	var my := lb.my_id()
	for k in range(ROWS):
		var r: Dictionary = rows[k]
		var panel: Panel = r.panel
		if k >= lb.players.size():
			panel.add_theme_stylebox_override("panel", hud.style(Color(1, 1, 1, 0.45), 22, Color("d8dccf")))
			(r.chip as Panel).add_theme_stylebox_override("panel", hud.style(Color("d8dccf"), 7))
			r.name.text = "Platz frei"
			r.name.add_theme_color_override("font_color", Color(MUTED, 0.7))
			r.car.text = "wartet auf einen Mitspieler"
			r.state.text = ""
			r.ping.text = ""
			continue
		var p: Dictionary = lb.players[k]
		var own := int(p.id) == my
		panel.add_theme_stylebox_override("panel", hud.style(Color("ffffff"), 22, ORANGE if own else Color.TRANSPARENT))
		(r.chip as Panel).add_theme_stylebox_override("panel", hud.style(player_color(p), 7, Color(0.02, 0.07, 0.09, 0.35)))
		r.name.text = str(p.name) + ("  (du)" if own else "")
		r.name.add_theme_color_override("font_color", INK)
		r.car.text = str(RaceVehicle.CARS[int(p.car)].name)
		var state_text := ""
		var state_color := MUTED
		if bool(p.away):
			state_text = "im Hintergrund"
			state_color = RED
		elif lb.phase != "lobby":
			state_text = "geladen ✓" if bool(p.loaded) else "lädt …"
			state_color = GREEN if bool(p.loaded) else MUTED
		elif bool(p.host):
			state_text = "Gastgeber"
			state_color = ORANGE
		elif bool(p.ready):
			state_text = "bereit ✓"
			state_color = GREEN
		else:
			state_text = "wählt noch …"
		r.state.text = state_text
		r.state.add_theme_color_override("font_color", state_color)
		var ping := lb.ping_of(p)
		r.ping.text = "" if bool(p.host) else ("Ping %d ms" % ping if ping >= 0 else "Ping …")
		r.ping.add_theme_color_override("font_color", MUTED if ping < 0 else (GREEN if ping < 80 else (ORANGE if ping < 160 else RED)))
	var mine := lb.me()
	if not mine.is_empty() and is_instance_valid(own_car_button):
		own_car_button.text = "%s  ›" % str(RaceVehicle.CARS[int(mine.car)].name)
		own_car_button.disabled = lb.phase != "lobby"
		own_car_dot.add_theme_stylebox_override("panel", hud.style(player_color(mine), 14, Color(0.02, 0.07, 0.09, 0.35)))
	_refresh_settings()
	if lb.is_host() and is_instance_valid(start_button):
		var problem := lb.start_problem()
		start_button.disabled = problem != ""
		problem_label.text = problem if problem != "" else "Alle bereit – los geht's!"
		problem_label.add_theme_color_override("font_color", MUTED if problem != "" else GREEN)
	elif is_instance_valid(ready_button):
		var ready := bool(mine.get("ready", false))
		ready_button.text = "Bereit ✓   (tippen zum Zurücknehmen)" if ready else "Ich bin bereit"
		for key in ["normal", "hover", "pressed"]:
			ready_button.add_theme_stylebox_override(key, hud.style(GREEN if ready else ORANGE, 14))
		problem_label.text = "Warte auf den Start durch %s …" % lb.host_name() if ready else "Wähle Auto und Namen, dann tippe „Ich bin bereit“."

func _refresh_settings() -> void:
	# Einstellungen: beim Gastgeber bedienbar (wie „Weitergeben“), bei Mitspielern nur zur Ansicht. Neu aufgebaut nur bei Änderung.
	var lb := lobby()
	var s: Dictionary = lb.settings
	var sig := "%s %s %d %d %s %d" % [lb.is_host(), s.track, int(s.stage), int(s.ai), s.contacts, lb.players.size()]
	if sig == _settings_sig or not is_instance_valid(settings_box):
		return
	_settings_sig = sig
	for child in settings_box.get_children():
		settings_box.remove_child(child)
		child.queue_free()
	var box := settings_box
	var circuit := Circuit.load_track(str(s.track))
	var drift := PassParty.track_is_drift(str(s.track))
	var humans := lb.players.size()
	if lb.is_host():
		hud.label(box, "STRECKE", Vector2(28, 20), 13, MUTED)
		var tracks: Array = lb.tracks
		var per_row: int = ceili(tracks.size() / 2.0)
		var slot: float = 584.0 / per_row
		for i in range(tracks.size()):
			var tid: String = tracks[i]
			var b := hud.button(box, RaceHUD.SHORT_NAMES.get(tid, tid), Rect2(28 + (i % per_row) * slot, 48 + (i / per_row) * 44, slot - 6, 40),
				func(): app.lobby.set_track(tid), str(s.track) == tid)
			b.add_theme_font_size_override("font_size", 16)
			b.clip_text = true
		hud.label(box, circuit.name, Vector2(28, 142), 22)
		hud.label(box, "HERAUSFORDERUNG", Vector2(28, 186), 13, MUTED)
		for i in range(3):
			var sb := hud.button(box, "Stufe %d" % (i + 1), Rect2(28 + i * 196, 214, 190, 52), func(): app.lobby.set_stage(i), int(s.stage) == i)
			sb.add_theme_font_size_override("font_size", 19)
		hud.label(box, Atmosphere.describe(circuit.conditions_for(int(s.stage))).to_upper() + "  ·  KI-STÄRKE WIE IN DER KARRIERE", Vector2(28, 274), 11, ORANGE, 590)
		hud.label(box, "KI-GEGNER", Vector2(28, 312), 13, MUTED)
		if drift:
			hud.label(box, "Drift-Arena: alle gleichzeitig, ohne KI und ohne Berührungen – gewertet wird nach Punkten.", Vector2(28, 340), 16, INK, 590)
		else:
			var most := NetLobby.max_ai(str(s.track), humans)
			for n in range(most + 1):
				var ab := hud.button(box, "%d" % n, Rect2(28 + n * 120, 340, 112, 52), func(): app.lobby.set_ai(n), int(s.ai) == n)
				ab.add_theme_font_size_override("font_size", 20)
		var contact := hud.toggle(box, "Berührungen zwischen Spielern", Vector2(24, 412), bool(s.contacts) and not drift, func(on: bool): app.lobby.set_contacts(on))
		contact.disabled = drift
	else:
		hud.label(box, "STRECKE", Vector2(28, 20), 13, MUTED)
		var title := hud.label(box, circuit.name, Vector2(24, 44), 40, INK, 590)
		title.name = "LobbyTrack"
		hud.label(box, circuit.subtitle, Vector2(28, 104), 16, MUTED, 584)
		hud.label(box, "HERAUSFORDERUNG", Vector2(28, 186), 13, MUTED)
		hud.label(box, "Stufe %d  ·  %s" % [int(s.stage) + 1, Atmosphere.describe(circuit.conditions_for(int(s.stage)))], Vector2(28, 212), 22, INK, 584)
		hud.label(box, "KI-GEGNER", Vector2(28, 270), 13, MUTED)
		hud.label(box, "Drift-Arena: ohne KI, nach Punkten" if drift else ("keine" if int(s.ai) == 0 else "%d, Stärke wie in der Karriere" % int(s.ai)), Vector2(28, 296), 22, INK, 584)
		hud.label(box, "BERÜHRUNGEN ZWISCHEN SPIELERN", Vector2(28, 354), 13, MUTED)
		hud.label(box, "an" if bool(s.contacts) else "aus", Vector2(28, 380), 22)
		hud.label(box, "Der Gastgeber stellt ein. Ändert er etwas, tippst du erneut „Bereit“.", Vector2(28, 440), 15, MUTED, 584)
	var total := humans + (0 if drift else int(s.ai))
	hud.label(box, "%d Spieler%s · %d Autos am Start" % [humans, "" if drift or int(s.ai) == 0 else " + %d KI" % int(s.ai), total], Vector2(28, 500), 18, MUTED, 590)

# ---------- Start (Übergabe an M4) ----------
func round_screen() -> void:
	var lb := lobby()
	hud.clear()
	hud.backdrop.visible = true
	screen = "round"
	var s: Dictionary = lb.current_round.get("settings", lb.settings)
	var circuit: Circuit = app.track
	hud.header("MEHRSPIELER     /     START")
	var p := hud.panel(hud.content, Rect2(270, 160, 900, 600))
	hud.label(p, "RUNDE %d  ·  STUFE %d" % [lb.round_id, int(s.stage) + 1], Vector2(34, 24), 13, ORANGE)
	hud.label(p, circuit.name, Vector2(30, 52), 44, INK, 840)
	hud.label(p, Atmosphere.describe(circuit.conditions_for(int(s.stage))) + ("  ·  ohne KI" if int(s.ai) == 0 else "  ·  %d KI" % int(s.ai)) + ("  ·  Berührungen an" if bool(s.contacts) else "  ·  ohne Berührungen"),
		Vector2(34, 118), 18, MUTED, 840)
	round_status = hud.label(p, "", Vector2(34, 180), 26, INK, 840)
	round_status.name = "RoundStatus"
	round_players = hud.label(p, "", Vector2(34, 236), 20, MUTED, 840)
	hud.label(p, "Sobald alle geladen haben, zählen alle gemeinsam 3-2-1 und zeichnen gleichzeitig. Die Linien der anderen bleiben verdeckt, bis alle fertig sind.",
		Vector2(34, 400), 16, MUTED, 840)
	if lb.is_host():
		round_button = hud.button(p, "Zurück zur Lobby", Rect2(34, 494, 832, 72), app.net_back_to_lobby, true)
	else:
		round_button = hud.button(p, "Verlassen", Rect2(34, 494, 832, 72), func(): app.go_back())
	round_button.name = "RoundButton"
	_add_toast()
	refresh()

func _refresh_round() -> void:
	var lb := lobby()
	if not is_instance_valid(round_status):
		return
	var loaded := lb.players.filter(func(q): return bool(q.loaded)).size()
	round_status.text = "Alle haben die Strecke geladen." if lb.phase == "ready" else "Strecke wird geladen … (%d von %d fertig)" % [loaded, lb.players.size()]
	round_status.add_theme_color_override("font_color", GREEN if lb.phase == "ready" else INK)
	round_players.text = "   ".join(lb.players.map(func(q): return "%s %s" % [q.name, "✓" if q.loaded or lb.phase == "ready" else "…"]))

# ---------- Allgemein ----------
func refresh() -> void:
	if app.lobby == null:
		return
	match screen:
		"wlan":
			if app.phase == "net_menu":
				_refresh_wlan()
		"lobby":
			if app.phase == "net_lobby":
				_refresh_lobby()
		"garage":
			if app.phase == "net_garage":
				_refresh_garage()
		"round":
			if app.phase == "net_round":
				_refresh_round()
		"draw", "reveal", "start":
			_refresh_draw()
	if is_instance_valid(toast_label) and Time.get_ticks_msec() > _toast_until:
		toast_label.get_parent().visible = false

func _add_toast(y := 856.0) -> void:
	var pill := hud.panel(hud.content, Rect2(420, y, 600, 40), Color(0.04, 0.16, 0.18, 0.86))
	pill.name = "Toast"
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_label = hud.label(pill, "", Vector2(0, 6), 16, PAPER, 600)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pill.visible = false

func toast(text: String) -> void:
	# Kurzer Hinweis unten („Ben ist beigetreten.“), verschwindet nach 3 s.
	if not is_instance_valid(toast_label):
		return
	toast_label.text = text
	toast_label.get_parent().visible = true
	_toast_until = Time.get_ticks_msec() + 3000

func go_back() -> void:
	# Zurück-Taste: Dialog schließen (Verbinden: abbrechen); sonst einen Schritt zurück – Lobby → Suche, Suche → Menü.
	var lb := lobby()
	if dialog_open() or hud.content.has_node("AddressDialog"):
		if lb.mode == "join" and not lb.is_joined:
			app.net_cancel_join()
		close_dialogs()
		return
	match app.phase:
		"net_menu":
			app.show_menu()
		"net_garage":
			app.close_garage()
		"net_round", "net_countdown", "draw", "net_drawn", "net_reveal", "net_start":
			if lb.is_host():
				confirm("Runde abbrechen?", "Alle kehren in die Lobby zurück.", "Zur Lobby", app.net_back_to_lobby)
			else:
				confirm("Runde verlassen?", "Du verlässt das Spiel. Hast du deine Linie schon abgegeben, fährt dein Auto sie ohne Turbo.", "Verlassen", app.net_leave_lobby)
		"countdown", "race":
			if lb.is_host():
				confirm("Rennen abbrechen?", "Alle kehren ohne Wertung in die Lobby zurück.", "Zur Lobby", app.net_back_to_lobby)
			else:
				confirm("Rennen verlassen?", "Du verlässt das Spiel. Dein Auto fährt seine Linie ohne Turbo zu Ende.", "Verlassen", app.net_leave_lobby)
		"result":
			if lb.is_host():
				confirm("Zurück in die Lobby?", "Alle kehren in die Lobby zurück – dort könnt ihr Strecke und Autos ändern.", "Zur Lobby", app.net_back_to_lobby)
			else:
				confirm("Spiel verlassen?", "Du kannst wieder beitreten, sobald ihr in der Lobby seid.", "Verlassen", app.net_leave_lobby)
		"net_lobby":
			if lb.is_host() and lb.client_count() > 0:
				confirm("Spiel beenden?", "Alle Mitspieler kehren dann ins Menü zurück.", "Spiel beenden", app.net_leave_lobby)
			elif lb.is_host():
				app.net_leave_lobby()
			else:
				confirm("Lobby verlassen?", "Du kannst danach wieder beitreten, solange das Rennen nicht läuft.", "Verlassen", app.net_leave_lobby)

# ---------- Garage (Autowahl im WLAN) ----------
func _garage_owners() -> Array:
	# Je Palettenfarbe der Name des Mitspielers, der sie hat ("" = frei oder eigene).
	var lb := lobby()
	var owners: Array = []
	for c in range(PlayerColors.count()):
		var owner := ""
		for p in lb.players:
			if int(p.id) != lb.my_id() and int(p.get("color", -1)) == c:
				owner = str(p.name)
		owners.append(owner)
	return owners

func _garage_signature() -> String:
	var mine := lobby().me()
	return JSON.stringify([mine.get("name", ""), mine.get("car", 0), mine.get("color", 0), _garage_owners()])

func garage_screen() -> void:
	# Eigenes Auto und eigene Farbe: Garage wie im Einzelspieler (RaceHUD.garage), jede Wahl geht sofort an den Gastgeber. Belegte
	# Farben sind gesperrt; kommt eine Wahl beim Gastgeber zu spät, vergibt er die nächste freie (die Garage zeigt sie dann).
	var lb := lobby()
	var mine := lb.me()
	if mine.is_empty():
		app.close_garage()
		return
	screen = "garage"
	_garage_sig = _garage_signature()
	hud.garage("MEHRSPIELER     /     GARAGE", "AUTO UND FARBE  ·  IM WLAN", str(mine.name), int(mine.car),
		int(mine.get("color", 0)), _garage_owners(),
		func(car: int): lb.set_car(car); _refresh_garage(),
		func(c: int): lb.set_color(c); _refresh_garage(),
		app.close_garage)
	_add_toast()

func _refresh_garage() -> void:
	# Neu aufbauen nur, wenn sich eigene Wahl oder die Farben der anderen geändert haben (Ping-Zustand jede Sekunde: nichts tun).
	if app.phase != "net_garage" or lobby().me().is_empty():
		return
	if _garage_signature() != _garage_sig:
		garage_screen()

# ---------- Gemeinsames Zeichnen (M4) ----------
func draw_state() -> NetDraw:
	return app.lobby.draw if app.lobby != null else null

func _own_chip() -> void:
	# Eigenes Schild in der Spielerfarbe neben der Rundenanzeige (wie beim Weitergeben).
	var d := draw_state()
	var e := d.entry(d.my_id)
	var c := player_color(e)
	var chip := hud.panel(hud.content, Rect2(345, 134, 330, 58), c)
	chip.name = "DrawChip"
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.label(chip, "Du: %s" % str(e.get("name", "")), Vector2(20, 12), 22, on_color(c), 300)

func _draw_box() -> void:
	# Stand der anderen oben rechts: „Anna  zeichnet … 60 %“, „Ben  fertig ✓“. Lässt Berührungen durch (Zeichnen bis an den Rand).
	var d := draw_state()
	var list := d.others()
	_draw_sig = ",".join(list.map(func(e): return str(e.id)))
	draw_rows.clear()
	draw_box = hud.panel(hud.content, Rect2(1060, 134, 340, 52 + maxi(1, list.size()) * 40))
	draw_box.name = "DrawStatus"
	draw_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.label(draw_box, "MITSPIELER", Vector2(20, 14), 13, ORANGE)
	for k in range(list.size()):
		var e: Dictionary = list[k]
		var dot := Panel.new()
		dot.position = Vector2(20, 50 + k * 40)
		dot.size = Vector2(18, 18)
		dot.add_theme_stylebox_override("panel", hud.style(player_color(e), 9, MUTED))   # Rand: helle Spielerfarben auf Papier
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		draw_box.add_child(dot)
		hud.label(draw_box, str(e.name), Vector2(48, 44 + k * 40), 18, INK, 120)
		var state := hud.label(draw_box, "", Vector2(172, 46 + k * 40), 15, MUTED, 156)
		state.name = "DrawState%d" % k
		draw_rows.append({"id": int(e.id), "state": state})
	if list.is_empty():
		hud.label(draw_box, "Alle anderen sind gegangen.", Vector2(20, 46), 15, MUTED, 300)

func _draw_extras() -> void:
	_own_chip()
	_draw_box()
	_add_toast(668)

func draw_countdown() -> void:
	# Gemeinsames 3-2-1 vor dem Zeichnen; die Strecke ist schon zu sehen (Übersicht).
	hud.clear()
	screen = "draw"
	wait_title = null
	redraw_button = null
	hud.header("%s     /     GLEICH ZEICHNEN ALLE" % app.track.name.to_upper())
	var pill := hud.panel(hud.content, Rect2(495, 300, 450, 250), Color(0.04, 0.16, 0.18, 0.86))
	pill.name = "DrawCountdown"
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := hud.label(pill, "ZEICHENSTART", Vector2(0, 22), 13, ORANGE, 450)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_label = hud.label(pill, "", Vector2(0, 46), 96, PAPER, 450)
	countdown_label.name = "CountdownNumber"
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub := hud.label(pill, "Alle zeichnen gleichzeitig – ohne Zeitlimit.", Vector2(0, 196), 16, PAPER, 450)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var footer := hud.panel(hud.content, Rect2(40, 764, 1360, 104))
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.label(footer, "DEINE LINIE BLEIBT VERDECKT", Vector2(24, 16), 13, ORANGE)
	hud.label(footer, "Die Linien der anderen siehst du erst, wenn alle fertig sind.", Vector2(24, 39), 24)
	hud.label(footer, "Langsam = breit & grün, schnell = schmal & rot. Bis alle fertig sind, darfst du neu zeichnen.", Vector2(24, 74), 14, MUTED)
	_draw_extras()
	update_countdown(draw_state().seconds_until(draw_state().draw_at))
	refresh()

func update_countdown(left: float) -> void:
	if is_instance_valid(countdown_label):
		countdown_label.text = str(ceili(left)) if left > 0.0 else "Los!"

func draw_overlay() -> void:
	# Zusätze der normalen Zeichenansicht (hud.drawing): eigenes Schild und Stand der anderen.
	screen = "draw"
	wait_title = null
	redraw_button = null
	_draw_extras()
	refresh()

func drawn_card() -> void:
	# Linie fertig: abgeben („Fertig“) oder neu zeichnen; nach dem Abgeben warten mit dem Stand der anderen.
	var d := draw_state()
	hud.clear()
	screen = "draw"
	wait_title = null
	redraw_button = null
	hud.header("%s     /     %s" % [app.track.name.to_upper(), "LINIE ABGEGEBEN" if d.submitted else "LINIE FERTIG"])
	var footer := hud.panel(hud.content, Rect2(40, 724, 1360, 144))
	footer.name = "DrawnCard"
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not d.submitted:
		hud.label(footer, "LINIE FERTIG", Vector2(24, 16), 13, ORANGE)
		hud.label(footer, "Gut gezeichnet, %s!" % str(d.entry(d.my_id).get("name", "")), Vector2(24, 40), 30, INK, 740)
		hud.label(footer, "„Fertig“ gibt sie ab – verdeckt, bis alle fertig sind.", Vector2(24, 92), 14, MUTED, 740)
		redraw_button = hud.button(footer, "Neu zeichnen", Rect2(800, 38, 220, 68), app.net_redraw)
		var go := hud.button(footer, "Fertig  ✓", Rect2(1036, 38, 300, 68), app.net_submit, true)
		go.name = "SubmitButton"
	else:
		hud.label(footer, "ABGEGEBEN", Vector2(24, 16), 13, ORANGE)
		wait_title = hud.label(footer, "", Vector2(24, 40), 30, INK, 980)
		wait_title.name = "WaitTitle"
		hud.label(footer, "Kein Zeitlimit – es wird auf alle gewartet. Bis dahin darfst du noch neu zeichnen.", Vector2(24, 92), 14, MUTED, 980)
		redraw_button = hud.button(footer, "Doch neu zeichnen", Rect2(1036, 38, 300, 68), app.net_redraw)
	redraw_button.name = "RedrawButton"
	_draw_extras()
	refresh()

func _lines_legend() -> void:
	# Wer welche Farbe hat (Enthüllung und danach).
	var d := draw_state()
	var box := hud.panel(hud.content, Rect2(40, 136, 360, 70 + d.roster.size() * 44))
	box.name = "LinesLegend"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.label(box, "ALLE LINIEN", Vector2(22, 14), 13, ORANGE)
	for k in range(d.roster.size()):
		var e: Dictionary = d.roster[k]
		var swatch := Panel.new()
		swatch.position = Vector2(22, 54 + k * 44)
		swatch.size = Vector2(40, 16)
		swatch.add_theme_stylebox_override("panel", hud.style(player_color(e), 8, MUTED))
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(swatch)
		var shown := str(e.name) + ("  (du)" if int(e.id) == d.my_id else "") + ("  (weg)" if bool(e.gone) else "")
		hud.label(box, shown, Vector2(76, 44 + k * 44), 20, INK, 270)

func reveal_screen() -> void:
	hud.clear()
	screen = "reveal"
	hud.header("%s     /     ALLE LINIEN" % app.track.name.to_upper())
	_lines_legend()
	var pill := hud.panel(hud.content, Rect2(470, 780, 500, 62), Color(0.04, 0.16, 0.18, 0.82))
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reveal_label = hud.label(pill, "", Vector2(0, 14), 22, PAPER, 500)
	reveal_label.name = "RevealCountdown"
	reveal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_add_toast(720)
	update_reveal(draw_state().seconds_until(draw_state().start_at))

func update_reveal(left: float) -> void:
	if is_instance_valid(reveal_label):
		reveal_label.text = "Gemeinsamer Start in %d …" % maxi(1, ceili(left))

func start_screen() -> void:
	# Übergabe an M5 (gemeinsames Rennen); bis dahin bleiben die Linien zu sehen.
	var lb := lobby()
	hud.clear()
	screen = "start"
	hud.header("%s     /     ALLE LINIEN" % app.track.name.to_upper())
	_lines_legend()
	var p := hud.panel(hud.content, Rect2(270, 700, 900, 168))
	p.name = "StartPlaceholder"
	hud.label(p, "ALLE LINIEN SIND DA", Vector2(30, 18), 13, ORANGE)
	hud.label(p, "Jetzt wäre die gemeinsame Ampel dran – das Rennen kommt mit dem nächsten Schritt.", Vector2(30, 42), 20, INK, 560)
	if lb.is_host():
		hud.button(p, "Zurück zur Lobby", Rect2(610, 46, 260, 76), app.net_back_to_lobby, true)
	else:
		hud.button(p, "Verlassen", Rect2(610, 46, 260, 76), func(): app.go_back())
	_add_toast(640)

# ---------- Rennen und Wertung (M5) ----------
func race_overlay() -> void:
	# Zusätze zur Renn-Anzeige (hud.race): Hinweise („Ben ist weg …“) und die Anzeige bei Funkstille vom Gastgeber.
	screen = "race"
	_add_toast(700)
	stale_pill = hud.panel(hud.content, Rect2(470, 226, 500, 52), Color(0.55, 0.16, 0.1, 0.88))
	stale_pill.name = "NetStale"
	stale_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := hud.label(stale_pill, "Verbindung zum Gastgeber hakt …", Vector2(0, 12), 19, PAPER, 500)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stale_pill.visible = false

func update_race(r: NetRace) -> void:
	if is_instance_valid(stale_pill):
		stale_pill.visible = r.stale()
	if is_instance_valid(toast_label) and Time.get_ticks_msec() > _toast_until:
		toast_label.get_parent().visible = false

func net_results(rows: Array) -> void:
	# Wertung vom Gastgeber: alle Autos mit Namen und Zeit (Drift: Punkte); kein Gold, keine Bestenliste. Gastgeber: Revanche oder
	# Lobby; Mitspieler warten auf seine Wahl oder gehen.
	var lb := lobby()
	var r: NetRace = lb.race
	var drift: bool = app.track.mode == "drift"
	hud.clear()
	screen = "result"
	stale_pill = null
	hud.header("%s     /     MEHRSPIELER-WERTUNG" % app.track.name.to_upper())
	var y0 := 168 + maxi(rows.size(), 4) * 62 + 12
	var p := hud.panel(hud.content, Rect2(370, 124, 700, y0 + 200))
	p.name = "NetResults"
	hud.label(p, ("DRIFT-WERTUNG" if drift else "ZIELEINLAUF") + ("" if r == null or r.final else "  ·  KI FÄHRT NOCH"), Vector2(34, 24), 15, ORANGE)
	var winner: Dictionary = rows[0] if not rows.is_empty() else {}
	var title := "Alle raus!"
	if not winner.is_empty() and not (bool(winner.crashed) and float(winner.time) < 0.0):
		var who := int(winner.index)
		if who == app.me and r != null and r.my_index >= 0:
			title = "Du gewinnst, %s!" % hud.driver_name(who)
		elif app.field != null and app.field.is_human(who):
			title = "Sieg für %s!" % hud.driver_name(who)
		else:
			title = "%s war schneller." % hud.driver_name(who)
	var t := hud.label(p, title, Vector2(30, 56), 38, INK, 640)
	t.name = "ResultTitle"
	hud.label(p, "PUNKTE" if drift else "ZEIT", Vector2(500, 120), 13, MUTED)
	hud.result_times.clear()
	for i in range(rows.size()):
		var row: Dictionary = rows[i]
		var idx := int(row.index)
		var y := 160 + i * 62
		var human: bool = app.field != null and app.field.is_human(idx)
		var dot := Panel.new()
		dot.position = Vector2(84, y + 8)
		dot.size = Vector2(22, 22)
		dot.add_theme_stylebox_override("panel", hud.style(app.models[idx].get_meta("tag_color", Color("6d7a7c")) if idx < app.models.size() else Color("6d7a7c"), 11, Color(0.02, 0.07, 0.09, 0.45)))
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(dot)
		hud.label(p, "%02d" % int(row.rank), Vector2(34, y), 22, ORANGE if int(row.rank) == 1 else MUTED)
		hud.label(p, hud.driver_name(idx) + ("  (du)" if idx == app.me and r != null and r.my_index >= 0 else ""), Vector2(120, y), 22, ORANGE if idx == app.me else (INK if human else MUTED), 240)
		hud.label(p, ("WEG" if bool(row.get("gone", false)) else "MENSCH") if human else "KI", Vector2(366, y + 6), 12, MUTED)
		var status_text: String
		if drift:
			status_text = "%d" % int(row.get("score", 0)) + ("" if bool(row.get("in_time", true)) else "  (nicht im Ziel)")
		elif float(row.time) >= 0.0:
			status_text = app.format_time(float(row.time))
		else:
			status_text = "Abgestürzt" if bool(row.get("crashed", false)) else "Im Rennen …"
		var cell := hud.label(p, status_text, Vector2(500, y), 22)
		cell.name = "ResultTime%d" % idx
		hud.result_times[idx] = cell
	if lb.is_host():
		var again := hud.button(p, "Revanche  →", Rect2(34, y0, 632, 72), app.net_rematch, true)
		again.name = "RematchButton"
		hud.label(p, "Neue Linien – der Sieger startet hinten.", Vector2(38, y0 + 80), 14, MUTED, 620)
		var back := hud.button(p, "Zur Lobby", Rect2(34, y0 + 112, 632, 62), app.net_back_to_lobby)
		back.name = "LobbyButton"
	else:
		hud.label(p, "Der Gastgeber „%s“ wählt: Revanche oder zurück in die Lobby." % lb.host_name(), Vector2(38, y0 + 10), 18, INK, 620)
		var leave := hud.button(p, "Verlassen", Rect2(34, y0 + 112, 632, 62), app.go_back)
		leave.name = "LeaveButton"
	_add_toast(mini(124 + y0 + 214, 850))

func _refresh_draw() -> void:
	var d := draw_state()
	if d == null:
		return
	if screen == "draw" and is_instance_valid(draw_box):
		var sig := ",".join(d.others().map(func(e): return str(e.id)))
		if sig != _draw_sig:
			draw_box.name = "DrawStatusOld"
			draw_box.queue_free()
			_draw_box()
		for row in draw_rows:
			var state_label: Label = row.state
			var st := d.status_of(int(row.id))
			state_label.text = d.state_text(int(row.id))
			var away := bool(lobby().player(int(row.id)).get("away", false))
			state_label.add_theme_color_override("font_color", GREEN if str(st.st) == "done" else (ORANGE if away else MUTED))
	if is_instance_valid(wait_title):
		wait_title.text = "Alle fertig – gleich siehst du alle Linien." if d.all_done() else "Warte auf %s …" % ", ".join(d.waiting_for())
	if is_instance_valid(redraw_button):
		redraw_button.disabled = d.phase != "draw"
