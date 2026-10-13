class_name InvitePanel
extends Control

# „Mitspieler einladen“ in der Lobby des Gastgebers (Beta 1.0.2, Nutzerwunsch 13.10.2026, nach dem Vorbild von Mau-Mau Flip): zwei
# Schritte nebeneinander – ① WLAN (eigenes Spiel-WLAN öffnen, WLAN-QR mit Name und Passwort) und ② Spiel (QR-Code zur Einladungsseite:
# Draw2Race öffnen oder herunterladen, ohne Internet). Der nächste offene Schritt leuchtet, ein geschaffter trägt einen Haken.
# „Fertig“ (und die Zurück-Taste) schließt nur das Panel, das Spiel-WLAN bleibt offen; „Spiel-WLAN schließen“ beendet es.
# Reine Anzeige: Zustand und Regeln stehen in NetInvite (app.lobby.invite). Raster 1440×900 wie alle Bildschirme (RaceHUD.overlay).

const INK := RaceHUD.INK
const MUTED := RaceHUD.MUTED
const ORANGE := RaceHUD.ORANGE
const GREEN := Color("2f8f5b")
const LINE := Color("d8dccf")
const BOX := Vector2(1360, 830)
const CARD := Vector2(640, 586)
const QR_PX := 296.0
const REFRESH_MS := 250

var hud: RaceHUD
var invite: NetInvite
var cards: Array = []            # je Schritt {panel, style, badge, check, frame, qr, column, text, small, values, foot}
var open_button: Button
var own_button: Button
var retry_button: Button
var back_button: Button
var close_button: Button
var done_button: Button
var _qr_texts := ["", ""]
var _sig := "-"
var _next_ms := 0
var _pulse := 0.0

static func open_on(owner_hud: RaceHUD) -> InvitePanel:
	# Panel über der Lobby öffnen (Knopf „Mitspieler einladen“).
	var lb: NetLobby = owner_hud.app.lobby
	if lb == null or not lb.is_host():
		return null
	var p := owner_hud.overlay("Mitspieler einladen", "", BOX)
	p.get_parent().name = "InviteDialog"
	var panel := InvitePanel.new()
	panel.name = "Invite"
	panel.hud = owner_hud
	panel.invite = lb.invite
	panel.size = BOX
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(panel)
	panel._build()
	lb.invite.open()
	panel.refresh(true)
	return panel

func _build() -> void:
	hud.label(self, "Zwei Schritte: erst ins gleiche WLAN, dann ins Spiel. Mit der Handykamera scannen – ganz ohne Internet.",
		Vector2(34, 80), 16, MUTED, 1290)
	for k in range(2):
		cards.append(_card(k))
	var c0: Dictionary = cards[0]
	open_button = hud.button(c0.panel, "Spiel-WLAN öffnen", Rect2(24, 500, 592, 66), invite.open_wifi, true)
	open_button.name = "OpenWifi"
	own_button = hud.button(c0.panel, "Eigenes Spiel-WLAN öffnen", Rect2(24, 500, 592, 66), invite.open_wifi)
	own_button.name = "OwnWifi"
	retry_button = hud.button(c0.panel, "Neu öffnen", Rect2(24, 500, 288, 66), invite.open_wifi, true)
	retry_button.name = "RetryWifi"
	back_button = hud.button(c0.panel, "Zurück", Rect2(328, 500, 288, 66), invite.dismiss_problem)
	back_button.name = "DismissProblem"
	close_button = hud.button(self, "Spiel-WLAN schließen", Rect2(28, 732, 380, 72), invite.close_wifi)
	close_button.name = "CloseWifi"
	done_button = hud.button(self, "Fertig", Rect2(1032, 732, 300, 72), close_panel, true)
	done_button.name = "InviteDone"

func _card(k: int) -> Dictionary:
	var panel := hud.panel(self, Rect2(Vector2(28 + k * 664, 118), CARD), Color("ffffff"))
	panel.name = "Step%d" % (k + 1)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := hud.style(Color("ffffff"), 22, LINE)
	panel.add_theme_stylebox_override("panel", style)
	var badge := hud.panel(panel, Rect2(22, 20, 52, 52), ORANGE)
	badge.add_theme_stylebox_override("panel", hud.style(ORANGE, 26))
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var num := hud.label(badge, str(k + 1), Vector2(0, 2), 28, Color.WHITE, 52)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.label(panel, ["WLAN", "Spiel"][k], Vector2(90, 20), 32, INK)
	var check := hud.label(panel, "✓ geschafft", Vector2(380, 30), 18, GREEN, 236)
	check.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	check.name = "Check"
	var frame := hud.panel(panel, Rect2(20, 88, QR_PX + 8, QR_PX + 8), Color("ffffff"))
	frame.add_theme_stylebox_override("panel", hud.style(Color("ffffff"), 12, LINE))
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var qr := TextureRect.new()
	qr.name = "QR"
	qr.position = Vector2(4, 4)
	qr.size = Vector2(QR_PX, QR_PX)
	qr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	qr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	qr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	qr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(qr)
	var column := VBoxContainer.new()
	column.name = "Text"
	column.add_theme_constant_override("separation", 10)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(column)
	var text := hud.label(column, "", Vector2.ZERO, 20, INK, 272)
	text.name = "Main"
	var small := hud.label(column, "", Vector2.ZERO, 15, MUTED, 272)
	small.name = "Small"
	var values := VBoxContainer.new()
	values.name = "Values"
	values.position = Vector2(24, 404)
	values.size = Vector2(592, 90)
	values.add_theme_constant_override("separation", 2)
	values.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(values)
	var foot := hud.label(panel, "", Vector2(24, 462), 15, MUTED, 592)     # unter den Werten über die ganze Breite (Hinweise zu ②)
	foot.name = "Foot"
	return {"panel": panel, "style": style, "badge": badge, "check": check, "frame": frame, "qr": qr, "column": column, "text": text,
		"small": small, "values": values, "foot": foot}

func close_panel() -> void:
	# „Fertig“: nur das Panel schließen – Spiel-WLAN und Einladungsseite bleiben.
	var shade := get_parent().get_parent() if get_parent() != null else null
	if shade != null and is_instance_valid(shade):
		shade.queue_free()

func _process(dt: float) -> void:
	_pulse += dt
	var now := Time.get_ticks_msec()
	if now >= _next_ms:
		_next_ms = now + REFRESH_MS
		refresh()
	var g := invite.glow()
	if g > 0 and g <= cards.size():
		var style: StyleBoxFlat = cards[g - 1].style
		style.border_color = Color(ORANGE, 0.55 + 0.45 * sin(_pulse * 4.0))

# ---------- Anzeige ----------
func refresh(force := false) -> void:
	var lb := invite.lobby
	var sig := "%s|%s|%s|%s|%s|%d|%d|%d|%s|%s|%s|%s" % [invite.mode, invite.address, invite.problem, invite.wifi.get("ssid", ""),
		invite.page_url(), invite.glow(), invite.pages(), invite.downloads(), invite.address_late(), invite.prepare_text(),
		lb.status.get("hint", ""), invite.preparing()]
	if not force and sig == _sig:
		return
	_sig = sig
	_show_wifi(cards[0])
	_show_game(cards[1])
	for k in range(2):
		_show_step(k)
	var can := invite.available()
	open_button.visible = invite.mode == "none" and can
	own_button.visible = invite.mode == "wlan" and can
	back_button.visible = invite.mode == "problem"
	retry_button.visible = invite.mode == "problem" and (invite.problem == "stopped" or bool(invite.message().get("retry", false)))
	close_button.visible = invite.mode in ["game_wifi", "starting"]

func _show_step(k: int) -> void:
	var c: Dictionary = cards[k]
	var done := invite.step1_done() if k == 0 else invite.step2_done()
	var glowing := invite.glow() == k + 1
	var style: StyleBoxFlat = c.style
	style.set_border_width_all(4 if glowing or done else 1)
	style.border_color = GREEN if done else (ORANGE if glowing else LINE)
	(c.badge as Panel).add_theme_stylebox_override("panel", hud.style(GREEN if done else (ORANGE if glowing else Color("b9c3bd")), 26))
	(c.check as Label).visible = done

func _set_qr(k: int, text: String) -> void:
	var c: Dictionary = cards[k]
	var qr: TextureRect = c.qr
	if text != _qr_texts[k]:
		_qr_texts[k] = text
		qr.texture = null
		if text != "":
			var code := QrCode.encode(text)
			if code != null:
				qr.texture = code.to_texture(8, 2, INK, Color.WHITE)
	var has := qr.texture != null
	(c.frame as Control).visible = has
	var column: VBoxContainer = c.column
	column.position = Vector2(344, 92) if has else Vector2(24, 92)
	var width := 272.0 if has else 592.0
	for l in [c.text, c.small]:
		(l as Label).custom_minimum_size.x = width
		(l as Label).size.x = width
	column.size = Vector2(width, 300)

func _set_texts(c: Dictionary, main: String, small: String, main_color := INK) -> void:
	var t: Label = c.text
	t.text = main
	t.add_theme_color_override("font_color", main_color)
	var s: Label = c.small
	s.text = small
	s.visible = small != ""

func _values(c: Dictionary, rows: Array) -> void:
	# Werte unter dem QR-Code über die ganze Breite (Name, Passwort, Adresse) – große, fette Schrift zum Abtippen.
	var box: VBoxContainer = c.values
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	for row in rows:
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 14)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(r)
		var cap := hud.label(r, str(row[0]), Vector2.ZERO, 15, MUTED, 120)
		cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var val := hud.label(r, str(row[1]), Vector2.ZERO, 30, INK, 452)
		val.name = str(row[0])
		val.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY

func _show_wifi(c: Dictionary) -> void:
	var main := ""
	var small := ""
	var color := INK
	var rows: Array = []
	var lb := invite.lobby
	match invite.mode:
		"game_wifi":
			main = "Spiel-WLAN ist offen. Mit der Kamera scannen oder in den WLAN-Einstellungen eintragen:"
			small = "Meldet das Handy „Kein Internet“: verbunden bleiben. Kein Internet ist hier normal."
			rows.append(["Name", str(invite.wifi.get("ssid", ""))])
			if str(invite.wifi.get("password", "")) != "":
				rows.append(["Passwort", str(invite.wifi.get("password", ""))])
			if invite.address_late():
				small = "Die eigene Adresse im Spiel-WLAN bleibt unbekannt. Schließe es und öffne es neu."
				color = ORANGE
		"starting":
			main = "Spiel-WLAN wird geöffnet …"
			small = "Fragt Android nach „Geräte in der Nähe“ (bzw. Standort): bitte erlauben – den Standort nutzt die App nicht."
		"wlan":
			main = "Mitspieler verbinden sich mit demselben WLAN wie du."
			small = "Seid ihr unterwegs oder sehen sich die Handys im Hotel- oder Gäste-WLAN nicht? Dann öffne ein eigenes WLAN – ohne Internet." \
				if invite.available() else ""
		"hotspot":
			main = "Dein Hotspot läuft: Verbinde die anderen Handys damit."
			small = "Die App ändert deinen Hotspot nie. Ein eigenes Spiel-WLAN geht erst, wenn er aus ist."
		"problem":
			var msg := invite.message()
			main = str(msg.title)
			small = str(msg.text)
			color = ORANGE
		_:
			main = "Noch kein WLAN da. Öffne ein eigenes Spiel-WLAN – ganz ohne Internet." if invite.available() \
				else "Noch kein WLAN da. Verbinde dich mit einem WLAN oder schalte deinen Hotspot ein."
	if bool(lb.status.get("warn", false)) and str(lb.status.get("hint", "")) != "" and invite.mode in ["game_wifi", "hotspot", "wlan"]:
		small = LobbyScreens.net_hint(str(lb.status.hint), invite.mode == "game_wifi")
		color = ORANGE if invite.mode != "game_wifi" else color
	_set_qr(0, invite.qr_text())
	_set_texts(c, main, small, color)
	_values(c, rows)

func _show_game(c: Dictionary) -> void:
	var url := invite.page_url()
	var rows: Array = []
	var main := ""
	var small := ""
	var foot: Label = c.foot
	if url == "":
		main = "Erst ins WLAN – dann gibt es hier den Code zum Spiel."
		_set_qr(1, "")
		_set_texts(c, main, "", MUTED)
		_values(c, rows)
		foot.text = ""
		return
	main = "Mit der Kamera scannen: Seite zum Öffnen oder Herunterladen von Draw2Race."
	var notes: Array = []
	if invite.mode == "game_wifi":
		notes.append("Lädt die Seite nicht? Mobile Daten kurz ausschalten.")
	if invite.preparing():
		var pct := invite.prepare_text()
		notes.append("App wird vorbereitet%s …" % (" (%s)" % pct if pct != "" else ""))
	small = "\n".join(notes)
	var below: Array = ["Mit App geht's auch so: Mehrspieler → Im WLAN – das Spiel erscheint von selbst, oder dort „QR-Code scannen“."]
	if invite.pages() > 0:
		below.append("Seite %d× aufgerufen%s." % [invite.pages(), " · %d× heruntergeladen" % invite.downloads() if invite.downloads() > 0 else ""])
	foot.text = "\n".join(below)
	rows.append(["Adresse", url.trim_prefix("http://").trim_suffix("/")])
	_set_qr(1, url)
	_set_texts(c, main, small)
	_values(c, rows)
