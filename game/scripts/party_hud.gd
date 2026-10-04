class_name PartyScreens
extends RefCounted

# Bildschirme des Mehrspielers „Weitergeben“ (M2b): Auswahl im Menü, Einstellungen, Garage (Auto und Spielerfarbe je Spieler,
# RaceHUD.garage), Übergabekarte, fertige Linie, Enthüllung, Rennanzeige mit Turboknöpfen, Wertung und Pause. Baut mit den Bausteinen von RaceHUD (panel, label, button) im selben 1440×900-
# Raster wie die übrigen Bildschirme; die Turboknöpfe (TurboPads) liegen in Bildschirmkoordinaten an den echten Ecken.
# Reine Oberfläche: alles Weitere (Phasen, Linien, Rennen) steuert main.gd, die Einstellungen stehen in PassParty.

const INK := RaceHUD.INK
const MUTED := RaceHUD.MUTED
const PAPER := RaceHUD.PAPER
const ORANGE := RaceHUD.ORANGE
const CARD_GUARD_MS := 350        # so lange nach dem Erscheinen zählt ein Tipp auf die Übergabekarte nicht (Finger des Vorgängers)

var hud: RaceHUD
var app: Node
var card_shown_at := 0
var hint: Label                   # Turbo-Hinweis im Rennen (nur am Anfang)
const HINT_TIME := 6.0

func _init(owner_hud: RaceHUD) -> void:
	hud = owner_hud
	app = owner_hud.app

func party() -> PassParty:
	return app.party

# ---------- Menü: Auswahl der Art ----------
func mode_dialog() -> void:
	var p := hud.overlay("Mehrspieler.", "Zu zweit bis zu viert gegeneinander – jeder mit seiner eigenen Linie.", Vector2(700, 600))
	hud.button(p, "Auf einem Handy (Weitergeben)", Rect2(34, 190, 632, 76), func(): p.get_parent().queue_free(); app.open_party(), true)
	hud.label(p, "Ihr zeichnet nacheinander, dann fahren alle gleichzeitig. Kein Netz nötig.", Vector2(38, 274), 15, MUTED, 620)
	var wlan := hud.button(p, "Im WLAN (jeder mit seinem Handy)", Rect2(34, 336, 632, 66), func(): p.get_parent().queue_free(); app.open_wlan())
	wlan.name = "WlanButton"
	hud.label(p, "Alle im selben WLAN oder im Hotspot eines Handys – Internet braucht ihr nicht.", Vector2(38, 410), 15, MUTED, 620)
	hud.button(p, "Zurück", Rect2(34, 494, 632, 66), func(): p.get_parent().queue_free())

# ---------- Einstellungen ----------
func setup_screen() -> void:
	var pt := party()
	hud.clear()
	hud.backdrop.visible = true
	hud.header("MEHRSPIELER     /     AUF EINEM HANDY")
	# Links: Spieler mit Name und Auto.
	var left := hud.panel(hud.content, Rect2(40, 120, 700, 724))
	hud.label(left, "WER FÄHRT MIT?", Vector2(28, 20), 13, ORANGE)
	hud.label(left, "%d Spieler" % pt.count(), Vector2(24, 44), 40)
	for k in range(pt.count()):
		player_row(left, k, Vector2(20, 112 + k * 124))
	if pt.count() < PassParty.MAX_PLAYERS:
		hud.button(left, "+  Spieler hinzufügen", Rect2(20, 112 + pt.count() * 124, 660, 60), func(): pt.add_player(); setup_screen())
	hud.label(left, "Alle Strecken und Autos sind frei, Autos auch doppelt – dein Fortschritt bleibt unberührt.",
		Vector2(28, 640), 14, MUTED, 640)
	# Rechts: Strecke, Herausforderung, KI, Berührungen, Start.
	var right := hud.panel(hud.content, Rect2(760, 120, 640, 724))
	hud.label(right, "STRECKE", Vector2(28, 20), 13, MUTED)
	var tracks: Array = app.TRACKS
	var per_row: int = ceili(tracks.size() / 2.0)
	var slot: float = 584.0 / per_row
	for i in range(tracks.size()):
		var tid: String = tracks[i]
		var b := hud.button(right, RaceHUD.SHORT_NAMES.get(tid, tid), Rect2(28 + (i % per_row) * slot, 48 + (i / per_row) * 44, slot - 6, 40),
			func(): pt.set_track(tid); setup_screen(), pt.track_id == tid)
		b.add_theme_font_size_override("font_size", 16)
		b.clip_text = true
	var circuit := Circuit.load_track(pt.track_id)
	hud.label(right, circuit.name, Vector2(28, 142), 22)
	hud.label(right, "HERAUSFORDERUNG", Vector2(28, 186), 13, MUTED)
	for i in range(3):
		var sb := hud.button(right, "Stufe %d" % (i + 1), Rect2(28 + i * 196, 214, 190, 52), func(): pt.set_stage(i); setup_screen(), pt.stage == i)
		sb.add_theme_font_size_override("font_size", 19)
	hud.label(right, Atmosphere.describe(circuit.conditions_for(pt.stage)).to_upper() + "  ·  KI-STÄRKE WIE IN DER KARRIERE", Vector2(28, 274), 11, ORANGE, 590)
	hud.label(right, "KI-GEGNER", Vector2(28, 312), 13, MUTED)
	if pt.is_drift():
		hud.label(right, "Drift-Arena: alle gleichzeitig, ohne KI und ohne Berührungen – gewertet wird nach Punkten.", Vector2(28, 340), 16, INK, 590)
	else:
		for n in range(pt.max_ai() + 1):
			var ab := hud.button(right, "%d" % n, Rect2(28 + n * 120, 340, 112, 52), func(): pt.ai = n; setup_screen(), pt.ai == n)
			ab.add_theme_font_size_override("font_size", 20)
	var contact := hud.toggle(right, "Berührungen zwischen Spielern", Vector2(24, 412), pt.contacts and not pt.is_drift(), func(on: bool): pt.contacts = on)
	contact.disabled = pt.is_drift()
	var cars_total := pt.count() + (0 if pt.is_drift() else pt.ai)
	var summary := "%d Spieler%s · %d Autos am Start" % [pt.count(), "" if pt.is_drift() or pt.ai == 0 else " + %d KI" % pt.ai, cars_total]
	hud.label(right, summary, Vector2(28, 486), 18, MUTED, 590)
	var first: String = pt.names()[0]
	hud.button(right, "Los – %s zeichnet zuerst  →" % first, Rect2(28, 620, 584, 76), app.party_start, true)

func player_row(parent: Control, k: int, pos: Vector2) -> void:
	var pt := party()
	var row := hud.panel(parent, Rect2(pos, Vector2(660, 112)), Color("ffffff"))
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var chip := Panel.new()
	chip.position = Vector2(14, 16)
	chip.size = Vector2(14, 80)
	chip.add_theme_stylebox_override("panel", hud.style(pt.color(k), 7))
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(chip)
	hud.label(row, "SPIELER %d" % (k + 1), Vector2(44, 8), 12, MUTED)
	var field := LineEdit.new()
	field.name = "PlayerName%d" % (k + 1)
	field.position = Vector2(42, 38)
	field.size = Vector2(290, 62)
	field.max_length = ProgressStore.NAME_MAX
	field.text = str(pt.players[k].name)
	field.placeholder_text = "Spieler %d" % (k + 1)
	field.virtual_keyboard_enabled = true
	field.select_all_on_focus = true
	field.add_theme_font_size_override("font_size", RaceHUD.readable(22))
	field.add_theme_font_override("font", hud.bold_font)
	field.add_theme_color_override("font_color", INK)
	field.add_theme_color_override("font_placeholder_color", Color(MUTED, 0.75))
	field.add_theme_color_override("caret_color", ORANGE)
	field.add_theme_stylebox_override("normal", hud.style(Color("f4f0e5"), 12, Color("c9cfc4")))
	field.add_theme_stylebox_override("focus", hud.style(Color.TRANSPARENT, 12, ORANGE))
	row.add_child(field)
	# Wie beim eigenen Namen: unerlaubte Zeichen schon beim Tippen weglassen; gespeichert wird nur in der Runde (nicht im Spielstand).
	field.text_changed.connect(func(text: String):
		var ok := ProgressStore.filter_name(text)
		if ok != text:
			var caret := field.caret_column
			field.text = ok
			field.caret_column = mini(caret, ok.length())
		pt.players[k].name = ok)
	field.text_submitted.connect(func(_t: String): pt.set_name(k, field.text); field.release_focus())
	field.focus_exited.connect(func(): if k < pt.count(): pt.set_name(k, field.text))
	# Auto und Farbe: Tippen öffnet die Garage (wie im Einzelspieler, mit allen Autos, lackiert in der Spielerfarbe).
	var car: Dictionary = RaceVehicle.CARS[int(pt.players[k].car)]
	var pick := hud.button(row, "%s  ›" % str(car.name), Rect2(346, 38, 288, 62), func(): app.party_garage(k))
	pick.name = "PlayerCar%d" % (k + 1)
	pick.add_theme_font_size_override("font_size", 20)
	pick.clip_text = true
	var dot := Panel.new()
	dot.position = Vector2(14, 17)
	dot.size = Vector2(28, 28)
	dot.add_theme_stylebox_override("panel", hud.style(pt.color(k), 14, Color(0.02, 0.07, 0.09, 0.35)))
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pick.add_child(dot)
	if pt.count() > PassParty.MIN_PLAYERS:
		var del := hud.button(row, "✕", Rect2(600, 4, 50, 30), func(): pt.remove_player(k); setup_screen())
		del.add_theme_font_size_override("font_size", 16)
		del.tooltip_text = "Spieler entfernen"

# ---------- Garage ----------
func garage_screen(k: int) -> void:
	# Auto und Farbe von Spieler k: Garage wie im Einzelspieler (RaceHUD.garage). Nichts wird gespeichert.
	var pt := party()
	if k < 0 or k >= pt.count():
		app.close_garage()
		return
	var shown := pt.names()
	var owners: Array = []
	for c in range(PlayerColors.count()):
		var owner := pt.color_owner(c)
		owners.append(shown[owner] if owner >= 0 and owner != k else "")
	hud.garage("MEHRSPIELER     /     GARAGE", "AUTO UND FARBE  ·  SPIELER %d" % (k + 1), shown[k], int(pt.players[k].car), pt.color_index(k), owners,
		func(car: int): pt.set_car(k, car); garage_screen(k),
		func(c: int): pt.set_color(k, c); garage_screen(k),
		app.close_garage)

# ---------- Übergabekarte ----------
func handover() -> void:
	# Deckt alles ab (auch die Linien der Vorgänger); ein Tipp irgendwo startet das Zeichnen des Spielers.
	var pt := party()
	var k := pt.turn
	var shown := pt.names()
	hud.clear()
	var shade := ColorRect.new()
	shade.name = "HandoverCard"
	shade.color = Color("0c3239")
	shade.position = -hud.content.position
	shade.size = hud.get_viewport().get_visible_rect().size
	hud.content.add_child(shade)
	var tap := Button.new()
	tap.name = "HandoverTap"
	tap.flat = true
	tap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for key in ["normal", "hover", "pressed", "focus", "disabled"]:
		tap.add_theme_stylebox_override(key, StyleBoxEmpty.new())
	tap.pressed.connect(func():
		if Time.get_ticks_msec() - card_shown_at < CARD_GUARD_MS:
			return
		app.sound.click()
		app.party_draw())
	shade.add_child(tap)
	var card := hud.panel(shade, Rect2((Vector2(1440, 900) - Vector2(640, 600)) * 0.5 + hud.content.position, Vector2(640, 600)))
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var stripe := Panel.new()
	stripe.position = Vector2(0, 0)
	stripe.size = Vector2(640, 18)
	stripe.add_theme_stylebox_override("panel", hud.style(pt.color(k), 9))
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(stripe)
	hud.label(card, "LINIE %d VON %d  ·  %s" % [k + 1, pt.count(), app.track.name.to_upper()], Vector2(34, 40), 13, ORANGE)
	var title := hud.label(card, "Spieler %d: %s" % [k + 1, shown[k]], Vector2(30, 74), 46, INK, 580)
	title.name = "HandoverTitle"
	var sub := hud.label(card, "Handy nehmen, dann tippen" if k == 0 else "Handy weitergeben, dann tippen", Vector2(34, 148), 24, MUTED, 572)
	sub.name = "HandoverHint"
	for j in range(pt.count()):
		var y := 222 + j * 46
		var dot := Panel.new()
		dot.position = Vector2(34, y + 6)
		dot.size = Vector2(22, 22)
		dot.add_theme_stylebox_override("panel", hud.style(pt.color(j), 11))
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(dot)
		var state := "fertig ✓" if j < k else ("ist dran" if j == k else "wartet")
		hud.label(card, shown[j], Vector2(70, y), 20, INK if j == k else MUTED)
		hud.label(card, state, Vector2(420, y), 18, ORANGE if j == k else MUTED)
	# Sichtbarer Hinweis, dass die ganze Karte ein Knopf ist (der Tipp zählt überall).
	var go := hud.panel(card, Rect2(34, 418, 572, 70), pt.color(k))
	go.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var go_text := hud.label(go, "Tippen, wenn du das Handy hast", Vector2(0, 16), 24, Color.WHITE if pt.color(k).get_luminance() < 0.6 else INK, 572)
	go_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.label(card, "Die Linien der anderen bleiben verdeckt, bis alle gezeichnet haben.", Vector2(34, 520), 15, MUTED, 572)
	card_shown_at = Time.get_ticks_msec()

# ---------- Zeichnen: Spielerkennung, fertige Linie ----------
func draw_chip() -> void:
	# Kleines Schild in der Spielerfarbe neben der Rundenanzeige: wer zeichnet gerade?
	var pt := party()
	var k := pt.turn
	var text := "Spieler %d: %s" % [k + 1, pt.names()[k]]
	var chip := hud.panel(hud.content, Rect2(345, 134, 360, 58), pt.color(k))
	chip.name = "DrawChip"
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var light := pt.color(k).get_luminance() < 0.6
	hud.label(chip, text, Vector2(20, 12), 22, Color.WHITE if light else INK, 330)

func drawn_card() -> void:
	var pt := party()
	var k := pt.turn
	var shown := pt.names()
	var last := k == pt.count() - 1
	hud.clear()
	hud.header("%s     /     LINIE FERTIG" % app.track.name.to_upper())
	var footer := hud.panel(hud.content, Rect2(40, 724, 1360, 144))
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.label(footer, "LINIE FERTIG", Vector2(24, 16), 13, ORANGE)
	hud.label(footer, "Gut gezeichnet, %s!" % shown[k], Vector2(24, 40), 30)
	var next_text := "Gleich sind alle Linien zu sehen – dann geht's los." if last else "Weitergeben verdeckt deine Linie. Dann ist %s dran." % shown[k + 1]
	hud.label(footer, next_text, Vector2(24, 92), 14, MUTED, 760)
	hud.button(footer, "Neu zeichnen", Rect2(800, 38, 220, 68), app.party_redraw)
	var go := hud.button(footer, "Alle Linien zeigen  →" if last else "Weitergeben  →", Rect2(1036, 38, 300, 68), app.party_pass, true)
	go.name = "PassButton"

# ---------- Enthüllung ----------
func reveal() -> void:
	var pt := party()
	var shown := pt.names()
	hud.clear()
	hud.header("%s     /     ALLE LINIEN" % app.track.name.to_upper())
	var tap := Button.new()
	tap.name = "RevealTap"
	tap.flat = true
	tap.position = -hud.content.position
	tap.size = hud.get_viewport().get_visible_rect().size
	for key in ["normal", "hover", "pressed", "focus", "disabled"]:
		tap.add_theme_stylebox_override(key, StyleBoxEmpty.new())
	tap.pressed.connect(func(): app.party_begin_race())
	hud.content.add_child(tap)
	var box := hud.panel(hud.content, Rect2(40, 136, 330, 70 + pt.count() * 44))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.label(box, "ALLE LINIEN", Vector2(22, 14), 13, ORANGE)
	for k in range(pt.count()):
		var swatch := Panel.new()
		swatch.position = Vector2(22, 54 + k * 44)
		swatch.size = Vector2(40, 16)
		swatch.add_theme_stylebox_override("panel", hud.style(pt.color(k), 8))
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(swatch)
		hud.label(box, shown[k], Vector2(76, 44 + k * 44), 20)
	var pill := hud.panel(hud.content, Rect2(470, 780, 500, 62), Color(0.04, 0.16, 0.18, 0.82))
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.center = hud.label(pill, "", Vector2(0, 14), 22, PAPER, 500)
	hud.center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func update_reveal(left: float) -> void:
	if hud.center != null:
		hud.center.text = "Start in %d …   (tippen = sofort)" % maxi(1, ceili(left))

# ---------- Rennen ----------
func race() -> void:
	var pt := party()
	hud.clear()
	hud.header("%s     /     MEHRSPIELER" % app.track.name.to_upper())
	var info := hud.panel(hud.content, Rect2(520, 124, 400, 64))
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.status = hud.label(info, "RUNDE 1 / 2", Vector2(20, 18), 17, MUTED)
	hud.time_label = hud.label(info, "00:00.000", Vector2(214, 8), 30)
	hud.center = hud.label(hud.content, "3", Vector2(590, 300), 130, PAPER, 260)
	hud.center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint = hud.label(hud.content, "Jeder hält seinen Turbo-Knopf. Bremsen lädt ihn auf.", Vector2(420, 852), 17, PAPER, 600)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Turboknöpfe: je Mensch (Startplatz = Autoindex), Ecke nach Spielerindex.
	var cars: Array[int] = []
	var players: Array[int] = []
	var colors: Array[Color] = []
	var names: Array[String] = []
	var shown := pt.names()
	for k in range(pt.count()):
		cars.append(pt.slot_of(k))
		players.append(k)
		colors.append(pt.color(k))
		names.append(shown[k])
	hud.pads.show_pads(cars, players, colors, names)

func update_race() -> void:
	# Je Bild: Runde und Zeit des führenden Menschen (Drift: Restzeit); Platz und Ladung zeigen die Knöpfe selbst.
	var lead: int = app.leading_human()
	if lead < 0 or hud.status == null:
		return
	var v: RaceVehicle = app.vehicles[lead]
	hud.status.text = app.lap_text(v.progress)
	if app.track.mode == "drift":
		hud.status.text = "noch %d s" % maxi(0, int(ceil(app.drift_limit() - app.race_time)))
	hud.time_label.text = app.format_time(app.race_time)
	if app.phase == "race" and hud.center != null:
		hud.center.text = "LOS" if app.race_time < 0.65 else ""
	if is_instance_valid(hint):
		hint.visible = app.phase == "countdown" or app.race_time < HINT_TIME   # danach verdeckt er keine Schilder mehr

# ---------- Wertung ----------
func results(rows: Array) -> void:
	# Alle Autos mit Namen und Zeit (Drift: Punkte); kein Gold, keine Bestenliste.
	var pt := party()
	var drift: bool = app.track.mode == "drift"
	hud.clear()
	hud.header("%s     /     MEHRSPIELER-WERTUNG" % app.track.name.to_upper())
	var y0 := 168 + maxi(rows.size(), 4) * 62 + 12
	var p := hud.panel(hud.content, Rect2(370, 124, 700, y0 + 214))
	hud.label(p, ("DRIFT-WERTUNG" if drift else "ZIELEINLAUF") + ("  ·  RENNEN %d" % pt.races if pt != null else ""), Vector2(34, 24), 15, ORANGE)
	var winner: Dictionary = rows[0] if not rows.is_empty() else {}
	var title := "Alle raus!"
	if not winner.is_empty() and not bool(winner.get("out", false)):
		title = ("Sieg für %s!" % hud.driver_name(int(winner.index))) if app.field.is_human(int(winner.index)) else "%s war schneller." % hud.driver_name(int(winner.index))
	var t := hud.label(p, title, Vector2(30, 56), 38, INK, 640)
	t.name = "ResultTitle"
	hud.label(p, "PUNKTE" if drift else "ZEIT", Vector2(500, 120), 13, MUTED)
	hud.result_times.clear()
	for i in range(rows.size()):
		var row: Dictionary = rows[i]
		var idx := int(row.index)
		var y := 160 + i * 62
		var human: bool = app.field.is_human(idx)
		var dot := Panel.new()
		dot.position = Vector2(84, y + 8)
		dot.size = Vector2(22, 22)
		dot.add_theme_stylebox_override("panel", hud.style(app.models[idx].get_meta("tag_color", Color("6d7a7c")) if idx < app.models.size() else Color("6d7a7c"), 11, Color(0.02, 0.07, 0.09, 0.45)))
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(dot)
		hud.label(p, "%02d" % int(row.rank), Vector2(34, y), 22, ORANGE if int(row.rank) == 1 else MUTED)
		hud.label(p, hud.driver_name(idx), Vector2(120, y), 22, INK if human else MUTED)
		hud.label(p, "MENSCH" if human else "KI", Vector2(330, y + 6), 12, MUTED)
		var status_text: String
		if drift:
			status_text = "%d" % int(row.score) + ("" if bool(row.get("in_time", true)) else "  (nicht im Ziel)")
		elif float(row.time) >= 0.0:
			status_text = app.format_time(float(row.time))
		else:
			status_text = "Abgestürzt" if bool(row.get("crashed", false)) else "Im Rennen …"
		hud.result_times[idx] = hud.label(p, status_text, Vector2(500, y), 22)
	var again := hud.button(p, "Revanche  →", Rect2(34, y0, 632, 72), app.party_rematch, true)
	again.name = "RematchButton"
	hud.label(p, "Neue Linien – der Sieger startet hinten.", Vector2(38, y0 + 80), 14, MUTED, 620)
	var change := hud.button(p, "Einstellungen ändern", Rect2(34, y0 + 120, 310, 62), app.open_party)
	change.name = "SetupButton"
	var menu := hud.button(p, "Zurück zum Menü", Rect2(356, y0 + 120, 310, 62), app.show_menu)
	menu.name = "MenuButton"

# ---------- Pause ----------
func paused() -> void:
	var p := hud.overlay("Kurze Pause.", "Alle Linien warten – nichts geht verloren.", Vector2(640, 640))
	hud.button(p, "Weiter", Rect2(34, 160, 572, 66), app.resume_game, true)
	var y := 246
	if app.phase in ["draw", "drawn"]:
		hud.button(p, "Meine Linie neu zeichnen", Rect2(34, y, 572, 62), app.party_redraw)
		y += 80
	hud.button(p, "Runde abbrechen (Einstellungen)", Rect2(34, y, 572, 62), app.open_party)
	hud.button(p, "Zum Menü", Rect2(34, y + 80, 572, 62), app.show_menu)
	hud.button(p, "Sound & Musik  ♪", Rect2(34, y + 160, 572, 62), func(): p.get_parent().queue_free(); hud.sound_settings())
