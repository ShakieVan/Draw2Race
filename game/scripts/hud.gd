class_name RaceHUD
extends CanvasLayer

const INK := Color("173a40")
const MUTED := Color("617578")
const PAPER := Color("f4f0e5")
const ORANGE := Color("ed6948")
var root: Control
var content: Control
var top: Control
var status: Label
var detail: Label
var time_label: Label
var speed_label: Label
var rank_label: Label
var turbo_button: Button
var center: Label
var progress_bar: ProgressBar
var app: Node
var result_times: Dictionary = {}
var bold_font: FontVariation
var instruction_label: Label
var backdrop: Control
var showcase_car: Node3D
var showcase_angle := 0.6
var fps_label: Label
var logo_taps := 0
var logo_tap_time := 0
var tags: NameTags
var pads: TurboPads             # Mehrspieler: Turboknöpfe der Menschen an den Bildschirmecken
var party_ui: PartyScreens      # Mehrspieler-Bildschirme (Weitergeben)
var lobby_ui: LobbyScreens      # Mehrspieler-Bildschirme (im WLAN)

func setup(owner_node: Node) -> void:
	app = owner_node
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var theme := Theme.new()
	var regular := FontVariation.new()
	regular.base_font = load("res://assets/Outfit.ttf")
	regular.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"):500.0}
	theme.default_font = regular
	bold_font = FontVariation.new()
	bold_font.base_font = regular.base_font
	bold_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"):700.0}
	theme.default_font_size = 20
	root.theme = theme
	# Eigener Menühintergrund; die 3D-Strecke ist im Menü ausgeblendet.
	backdrop = Control.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.draw.connect(draw_backdrop)
	backdrop.visible = false
	root.add_child(backdrop)
	# Namensschilder und Sprechblasen über den Autos: unter den Leisten und Knöpfen, über der 3D-Strecke (nur Darstellung).
	tags = NameTags.new()
	tags.setup(app, bold_font)
	root.add_child(tags)
	content = Control.new()
	content.size = Vector2(1440,900)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(content)
	# Turboknöpfe des Mehrspielers über allem Übrigen (Ecken in Bildschirmkoordinaten, mehrere Finger: main.gd).
	pads = TurboPads.new()
	pads.setup(app, bold_font)
	root.add_child(pads)
	party_ui = PartyScreens.new(self)
	lobby_ui = LobbyScreens.new(self)
	# FPS-Anzeige (nur über das versteckte Debug-Menü einschaltbar), liegt über allen Menüs.
	fps_label = Label.new()
	fps_label.position = Vector2(12,8)
	fps_label.add_theme_font_size_override("font_size",22)
	fps_label.add_theme_color_override("font_color",Color("ffe28a"))
	fps_label.add_theme_constant_override("outline_size",8)
	fps_label.add_theme_color_override("font_outline_color",Color(0,0,0,0.85))
	fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fps_label.visible = false
	root.add_child(fps_label)
	get_viewport().size_changed.connect(layout)
	layout()

func update_fps() -> void:
	if app == null or fps_label == null:
		return
	fps_label.visible = app.debug_flag("fps")
	if fps_label.visible:
		fps_label.text = "%d FPS · %s" % [Engine.get_frames_per_second(),Atmosphere.QUALITY_NAMES[app.world.atmosphere.quality]]

func layout() -> void:
	content.position = (get_viewport().get_visible_rect().size-Vector2(1440,900))*0.5 - Vector2(0,keyboard_lift)

# Bildschirmtastatur (Android): Sie legt sich über die untere Bildhälfte. Hat ein Eingabefeld den Fokus und läge es darunter, rückt die
# ganze Oberfläche so weit nach oben, dass das Feld knapp über der Tastatur steht (Nutzerbefund 03.10.2026: Namen ab Spieler 2 waren
# verdeckt). Gilt für alle Eingabefelder unter content (Weitergeben, Lobby, Namensdialog).
var keyboard_lift := 0.0

func update_keyboard_lift(dt: float) -> void:
	var goal := 0.0
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit and DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		var keyboard := float(DisplayServer.virtual_keyboard_get_height())
		if keyboard > 0.0:
			var view := get_viewport().get_visible_rect().size
			var window := float(DisplayServer.window_get_size().y)
			var covered := keyboard*view.y/maxf(1.0,window)      # Tastaturhöhe in Oberflächeneinheiten
			var bottom: float = (focus as Control).get_global_rect().end.y + keyboard_lift   # Unterkante ohne Verschiebung
			goal = clampf(bottom - (view.y - covered - 24.0), 0.0, view.y*0.65)
	if absf(goal - keyboard_lift) > 0.5:
		keyboard_lift = goal if goal > keyboard_lift else lerpf(keyboard_lift,goal,1.0-exp(-dt*12.0))
		layout()
	elif keyboard_lift != goal:
		keyboard_lift = goal
		layout()

func draw_backdrop() -> void:
	var size := backdrop.size
	var steps := 48
	for i in range(steps):
		var t := float(i) / steps
		backdrop.draw_rect(Rect2(0, size.y*t, size.x, size.y/steps + 1), Color("0c3239").lerp(Color("1d6b70"), t))
	# Abendsonne und warmer Schein
	var sun := Vector2(size.x*0.78, size.y*0.34)
	for k in range(10):
		backdrop.draw_circle(sun, 60.0 + k*42.0, Color(1.0, 0.78, 0.5, 0.035))
	# Diagonale Rennstreifen (Koralle, Creme, Petrol)
	var stripes := [[ORANGE, 0.0], [Color("f4e6c8"), 70.0], [Color("2a8c8c"), 118.0]]
	for s in stripes:
		var o: float = s[1]
		var band := PackedVector2Array([Vector2(size.x*0.30+o, size.y), Vector2(size.x*0.30+o+46, size.y),
			Vector2(size.x+o+46, size.y*0.18), Vector2(size.x+o, size.y*0.18)])
		backdrop.draw_colored_polygon(band, Color(s[0], 0.85))
	# Schräges Zielflaggen-Band
	var cell := 22.0
	for row in range(3):
		for col in range(40):
			if (row + col) % 2 == 0:
				var base := Vector2(size.x*0.44 + col*cell, size.y*0.93 - col*cell*0.55 + row*cell)
				backdrop.draw_colored_polygon(PackedVector2Array([base, base+Vector2(cell,-cell*0.55),
					base+Vector2(cell,cell*0.45), base+Vector2(0,cell)]), Color(0.95,0.93,0.87,0.28))
	# Tempolinien
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in range(26):
		var y := rng.randf_range(0.08, 0.95)*size.y
		var x := rng.randf_range(0.35, 1.0)*size.x
		backdrop.draw_line(Vector2(x, y), Vector2(x + rng.randf_range(60, 220), y), Color(1,1,1,0.10), 2.0)
	# Silhouette des Stadion-Ovals mit einem umlaufenden Leuchtpunkt
	var track: Circuit = app.track
	var box := Vector2(size.x*0.40, size.y*0.32)
	var scale := minf(box.x/maxf(1.0,track.bounds.size.x), box.y/maxf(1.0,track.bounds.size.y))
	var center := Vector2(size.x*0.70, size.y*0.30) - track.bounds.get_center()*scale
	var outline := PackedVector2Array()
	for i in range(241):
		outline.append(center + track.at(float(i)/240.0)*scale)
	backdrop.draw_polyline(outline, Color(0.95,0.93,0.87,0.22), 7.0*scale, true)
	backdrop.draw_polyline(outline, Color(0.95,0.93,0.87,0.55), 2.0, true)
	var lap := fposmod(Time.get_ticks_msec()/9000.0, 1.0)
	var car := center + track.at(lap)*scale
	backdrop.draw_circle(car, 14.0, Color(1.0,0.85,0.45,0.25))
	backdrop.draw_circle(car, 6.0, ORANGE)

func clear() -> void:
	backdrop.visible = false
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	status = null
	detail = null
	center = null
	progress_bar = null
	turbo_button = null
	instruction_label = null
	time_label = null
	speed_label = null
	rank_label = null
	result_times.clear()
	if pads != null:
		pads.hide_pads()

func style(color: Color, radius := 18, border := Color.TRANSPARENT) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.corner_radius_top_left = radius
	s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius
	s.corner_radius_bottom_right = radius
	s.border_color = border
	s.set_border_width_all(1 if border.a > 0 else 0)
	s.content_margin_left = 20
	s.content_margin_right = 20
	return s

func panel(parent: Node, rect: Rect2, color := PAPER) -> Panel:
	var p := Panel.new()
	p.position = rect.position
	p.size = rect.size
	p.add_theme_stylebox_override("panel",style(color,22))
	parent.add_child(p)
	return p

static func readable(font_size: int) -> int:
	# Auf dem Handy waren kleine Schriften unlesbar: kleine Größen ~1,75x, mittlere +4.
	if font_size <= 14:
		return int(round(font_size * 1.75))
	if font_size <= 21:
		return font_size + 4
	return font_size

func label(parent: Node, text: String, pos: Vector2, font_size := 20, color := INK, width := 0.0) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size",readable(font_size))
	if font_size>=28:
		l.add_theme_font_override("font",bold_font)
	l.add_theme_color_override("font_color",color)
	if color.get_luminance() > 0.6 and parent == content:
		# Heller Text direkt über dem Spielfeld: dunkle Kontur für Lesbarkeit auf hellem Grund.
		l.add_theme_constant_override("outline_size",9)
		l.add_theme_color_override("font_outline_color",Color(0.04,0.16,0.18,0.9))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if width > 0:
		# Umbruch zuerst setzen, sonst dehnt sich das Label auf die volle Textbreite.
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(width,0)
		l.size.x = width
	# Text erst nach Schrift- und Umbrucheinstellung setzen (sonst wächst das Label auf volle Breite).
	l.text = text
	parent.add_child(l)
	return l

func button(parent: Node, text: String, rect: Rect2, action: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.position = rect.position
	b.size = rect.size
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_stylebox_override("normal",style(ORANGE if primary else Color("e6e6dc"),14))
	b.add_theme_stylebox_override("hover",style(Color("f6805e") if primary else Color("d6dfd6"),14))
	b.add_theme_stylebox_override("pressed",style(Color("d65538") if primary else Color("bfd0c7"),14))
	b.add_theme_stylebox_override("disabled",style(Color("dedfd6"),14))
	b.add_theme_stylebox_override("focus",style(Color.TRANSPARENT,14,Color("d6ac63")))
	b.add_theme_color_override("font_color",Color.WHITE if primary else INK)
	b.add_theme_color_override("font_hover_color",Color.WHITE if primary else INK)
	b.add_theme_color_override("font_pressed_color",Color.WHITE if primary else INK)
	b.add_theme_color_override("font_disabled_color",Color("84928d"))
	b.add_theme_font_size_override("font_size",24)
	b.pressed.connect(func(): app.sound.click(); action.call())
	parent.add_child(b)
	return b

func header(tag: String) -> void:
	var bar := panel(content,Rect2(32,26,1376,84))
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label(bar,"DRAW",Vector2(25,12),32)
	label(bar,"2",Vector2(124,12),32,ORANGE)
	label(bar,"RACE",Vector2(144,12),32)
	label(bar,"THE RACING LINE IS YOURS",Vector2(27,53),10,MUTED)
	label(bar,tag,Vector2(320,29),18,MUTED)
	# Unsichtbare Fläche über dem Logo: 5 schnelle Tipper öffnen das Entwickler-Menü.
	var secret := Button.new()
	secret.flat = true
	secret.position = Vector2(8,4)
	secret.size = Vector2(290,76)
	for key in ["normal","hover","pressed","focus","disabled"]:
		secret.add_theme_stylebox_override(key,StyleBoxEmpty.new())
	secret.pressed.connect(logo_tapped)
	bar.add_child(secret)
	if app.phase == "party_setup":
		button(bar,"Zurück",Rect2(1221,15,130,54),app.show_menu)
		return
	if app.phase in ["party_garage","net_garage"]:
		# Mehrspieler-Garage: zurück zu den Einstellungen bzw. in die Lobby (die Wahl gilt schon).
		var back := button(bar,"Zurück",Rect2(1221,15,130,54),app.close_garage)
		back.name = "GarageBack"
		return
	if app.phase.begins_with("net_") or app.lobby != null:
		# WLAN-Mehrspieler (auch beim Zeichnen): kein Pausemenü, sondern Zurück mit Nachfrage (LobbyScreens.go_back).
		var in_round: bool = app.phase not in ["net_menu", "net_lobby"]
		var host: bool = app.lobby != null and app.lobby.is_host()
		var shown := "Zurück" if app.phase == "net_menu" else ("Lobby" if app.phase == "result" and host else ("Abbrechen" if in_round and host else "Verlassen"))
		var leave := button(bar,shown,Rect2(1191,15,160,54),app.go_back)
		leave.name = "NetBack"
		return
	if app.party != null and app.phase == "result":
		# Mehrspieler-Wertung: pause_game() hält hier absichtlich nichts an (auch bei Fokusverlust), der Knopf führt direkt ins Menü.
		button(bar,"Menü",Rect2(1221,15,130,54),app.show_menu)
		return
	button(bar,"Menü" if app.phase != "menu" else "Optionen",Rect2(1221,15,130,54),app.pause_game if app.phase != "menu" else settings)
	if app.phase == "menu":
		button(bar,"Bestenliste",Rect2(1041,15,168,54),func(): leaderboard(app.track_id,app.stage))
		if app.updater.available():
			# Hinweis im Menü, sobald eine neuere Version auf GitHub liegt.
			button(bar,"Update  ↓",Rect2(861,15,168,54),update_dialog,true)

func menu() -> void:
	clear()
	backdrop.visible = true
	var track: Circuit = app.track
	header("KARRIERE     /     %s" % track.name.to_upper())
	var card := panel(content,Rect2(40,120,470,720))
	label(card,"DEINE LINIE. DEIN RENNEN.",Vector2(28,20),13,ORANGE)
	label(card,track.name,Vector2(24,50),50)
	label(card,track.subtitle,Vector2(28,118),18,MUTED,414)
	label(card,"STRECKE",Vector2(28,184),13,MUTED)
	var short_names := SHORT_NAMES
	var per_row: int = ceili(app.TRACKS.size() / 2.0)
	var slot: float = 424.0 / per_row
	for i in range(app.TRACKS.size()):
		var tid: String = app.TRACKS[i]
		var unlocked: bool = app.track_unlocked(i)
		var text: String = short_names.get(tid,tid)
		if not unlocked and app.BONUS_TRACKS.has(tid):
			text += " ★%d" % int(app.BONUS_TRACKS[tid])
		var b := button(card,text,Rect2(28+(i%per_row)*slot,212+(i/per_row)*40,slot-6,36),func(): app.select_track(tid); app.stage=0; menu(),app.track_id==tid)
		b.add_theme_font_size_override("font_size",15)
		b.add_theme_constant_override("h_separation",0)
		for key in ["normal","hover","pressed","disabled","focus"]:
			var box := b.get_theme_stylebox(key).duplicate() as StyleBoxFlat
			box.content_margin_left = 4
			box.content_margin_right = 4
			b.add_theme_stylebox_override(key,box)
		b.clip_text = true
		b.disabled = not unlocked
	label(card,"HERAUSFORDERUNG",Vector2(28,298),13,MUTED)
	# Tageszeit/Wetter sind Teil der Herausforderung und nicht wählbar – nur angezeigt.
	for i in range(3):
		var won: bool = app.store.has_gold(app.track_id,i)
		var text := ("★ " if won else "") + "%d %s" % [i+1,"Rivale" if i==0 else "Rivalen"]
		var b := button(card,text,Rect2(28+i*140,326,132,56),func(): app.stage=i; menu(),app.stage==i)
		b.add_theme_font_size_override("font_size",18)
		b.clip_text = true
		b.disabled = i>0 and not app.store.has_gold(app.track_id,i-1)
	# Eigene Zeile, damit auch lange Bedingungen („Dämmerung · Schnee · Nebelschwaden“) passen.
	label(card,Atmosphere.describe(app.current_conditions()).to_upper(),Vector2(28,390),11,ORANGE,420)
	label(card,"DEIN FAHRZEUG",Vector2(28,428),13,MUTED)
	var spec: Dictionary = RaceVehicle.CARS[app.car_choice]
	var unlocked: bool = app.car_unlocked(app.car_choice)
	car_picker(card,428,app.car_choice,unlocked,func(step: int): app.select_car(app.car_choice+step); menu())
	var go := button(card,"Linie zeichnen     →" if unlocked else "Auto gesperrt",Rect2(28,604,418,64),app.start_drawing,true)
	go.disabled = not unlocked
	var best: Dictionary = app.store.best_time(app.track_id,app.stage)
	var best_text: String = app.format_time(float(best.time)) if not best.is_empty() else "–"
	label(card,"BESTZEIT %s · %d/3 GOLD HIER" % [best_text,app.store.gold_count(app.track_id)],Vector2(28,680),12,MUTED,414)
	car_showcase(spec,unlocked)
	# Mehrspieler: Auswahl „Auf einem Handy“ / „Im WLAN“ (bald).
	var multi := button(content,"Mehrspieler  ·  2–4 Spieler",Rect2(900,772,480,52),party_ui.mode_dialog)
	multi.name = "MultiplayerButton"
	label(content,"Mit dem Finger zeichnen",Vector2(48,852),17,Color("d6ebe1"))
	button(content,"Vorführfahrt  ↗",Rect2(1160,833,212,48),app.demo)

const SHORT_NAMES := {"azure":"Küste","city":"Stadt","forest":"Wald","harbor":"Hafen","serra":"Pass","fair":"Rummel","quarry":"Bruch","arena":"Drift","kids":"Kinder"}

func leaderboard(track_id: String, stage: int) -> void:
	# Persönliche Bestenliste: Strecke und Herausforderung wählbar, 10 schnellste Fahrten.
	var p := overlay("Bestenliste.","Deine 10 schnellsten Fahrten.",Vector2(900,800))
	var short_names := SHORT_NAMES
	for i in range(app.TRACKS.size()):
		var tid: String = app.TRACKS[i]
		var bw: float = 838.0 / app.TRACKS.size()
		var lb := button(p,short_names.get(tid,tid),Rect2(34+i*bw,132,bw-6,48),func(): p.get_parent().queue_free(); leaderboard(tid,stage),tid==track_id)
		lb.add_theme_font_size_override("font_size",16)
		lb.clip_text = true
	for i in range(3):
		var sb := button(p,"%d %s" % [i+1,"Rivale" if i==0 else "Rivalen"],Rect2(34+i*280,188,272,44),func(): p.get_parent().queue_free(); leaderboard(track_id,i),i==stage)
		sb.add_theme_font_size_override("font_size",19)
		sb.clip_text = true
	var list: Array = app.store.board(track_id,stage)
	if list.is_empty():
		label(p,"Noch keine Fahrt – zeichne deine erste Linie!",Vector2(34,260),20,MUTED)
	for i in range(list.size()):
		var e: Dictionary = list[i]
		var y := 248+i*40
		var car: Dictionary = RaceVehicle.CARS[clampi(int(e.car),0,RaceVehicle.CARS.size()-1)]
		label(p,"%02d" % (i+1),Vector2(38,y),20,ORANGE if i==0 else MUTED)
		label(p,("%d Pkt." % int(e.score)) if e.has("score") else app.format_time(float(e.time)),Vector2(110,y),20)
		label(p,str(car.name),Vector2(330,y),20,MUTED)
		label(p,str(e.get("date","")),Vector2(620,y),18,MUTED)
	button(p,"Zurück",Rect2(34,660,832,66),func(): p.get_parent().queue_free(),true)

func car_picker(card: Control, y: float, car: int, unlocked: bool, step: Callable) -> void:
	# Autowahl der Garage (Karriere-Menü und Mehrspieler): ← Name →, darunter der Text des Autos bzw. die Bedingung zum Freischalten.
	# step(−1 / +1) wechselt das Auto (Speichern, Probehören und Neuaufbau macht der Aufrufer).
	var spec: Dictionary = RaceVehicle.CARS[car]
	var prev := button(card,"←",Rect2(28,y+34,64,56),func(): step.call(-1))
	prev.name = "CarPrev"
	var car_name := label(card,spec.name,Vector2(100,y+42),22,INK if unlocked else MUTED,270)
	car_name.name = "CarName"
	car_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var next := button(card,"→",Rect2(382,y+34,64,56),func(): step.call(1))
	next.name = "CarNext"
	var info: String = spec.text if unlocked else "Gesperrt – freischalten mit %d Gold (du hast %d)." % [int(spec.unlock),app.store.data.gold.size()]
	label(card,info,Vector2(30,y+98),14,MUTED if unlocked else ORANGE,414)

func garage(title: String, tag: String, who: String, car: int, paint: int, swatches: Array, choose_car: Callable, choose_color: Callable, done: Callable) -> void:
	# Garage im Mehrspieler (Nutzerentscheidung „Autowahl“, 03.10.2026): dieselbe Autowahl wie im Karriere-Menü (car_picker, drehendes
	# Auto mit Fahrwerten im Schaufenster, Probehören des Motors), aber mit allen Autos – nichts gesperrt, nichts gespeichert – und
	# lackiert in der Spielerfarbe; dazu die Wahl der Spielerfarbe. tag/who: Zeile über dem Namen bzw. der Name. paint = eigene Farbe (Index in PlayerColors), swatches = je
	# Palettenfarbe der Name dessen, der sie schon hat ("" = frei oder eigene). choose_car(Auto), choose_color(Farbe) übernehmen die
	# Wahl (und bauen neu auf), done() führt zurück zu den Einstellungen bzw. in die Lobby.
	clear()
	backdrop.visible = true
	header(title)
	var card := panel(content,Rect2(40,120,470,720))
	card.name = "GarageCard"
	label(card,tag,Vector2(28,20),13,ORANGE)
	var who_label := label(card,who,Vector2(24,50),40)
	who_label.name = "GarageWho"
	label(card,"Alle Autos sind frei. Mehrere dürfen dasselbe fahren – jeder hat seine eigene Farbe.",Vector2(28,108),15,MUTED,414)
	label(card,"SPIELERFARBE",Vector2(28,184),13,MUTED)
	for c in range(PlayerColors.count()):
		var owner: String = str(swatches[c]) if c < swatches.size() else ""
		var tone := PlayerColors.color(c)
		var swatch := Button.new()
		swatch.name = "Swatch%d" % c
		swatch.position = Vector2(28+c*70,214)
		swatch.size = Vector2(60,60)
		swatch.tooltip_text = PlayerColors.color_name(c) + ("" if owner == "" else " (%s)" % owner)
		var own := c == paint
		for key in ["normal","hover","pressed","focus","disabled"]:
			var box := style(Color(tone,0.35) if owner != "" else tone,30,INK if own else Color(0.02,0.07,0.09,0.35))
			box.set_border_width_all(5 if own else 1)
			swatch.add_theme_stylebox_override(key,box)
		swatch.disabled = owner != ""
		swatch.pressed.connect(func(): app.sound.click(); choose_color.call(c))
		card.add_child(swatch)
		if owner != "":
			# Belegt: Anfangsbuchstabe dessen, der sie hat.
			var mark := label(swatch,owner.left(1).to_upper(),Vector2(0,12),22,INK,60)
			mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var colour_text := label(card,"%s – Lack, Schild, Lichtkranz, Turbo-Knopf und Linie." % PlayerColors.color_name(paint),Vector2(28,288),14,MUTED,414)
	colour_text.name = "ColorName"
	label(card,"FAHRZEUG",Vector2(28,428),13,MUTED)
	var n := RaceVehicle.CARS.size()
	car_picker(card,428,car,true,func(step: int):
		var next := posmod(car+step,n)
		app.sound.preview_engine(str(RaceVehicle.CARS[next].id))
		choose_car.call(next))
	var go := button(card,"Fertig  ✓",Rect2(28,604,418,64),done,true)
	go.name = "GarageDone"
	label(card,"Die Pfeile spielen den Motor zur Probe.",Vector2(28,680),12,MUTED,414)
	car_showcase(RaceVehicle.CARS[car],true,PlayerColors.color(paint))

func car_showcase(spec: Dictionary, unlocked: bool, paint := Color(0,0,0,0)) -> void:
	# Schaufenster: drehendes 3D-Modell in eigener kleiner Welt plus Werte-Balken. paint: Lack (Mehrspieler: Spielerfarbe), sonst die
	# Farbe des Autos.
	var box := panel(content,Rect2(900,430,480,330),Color("173a40"))
	var holder := SubViewportContainer.new()
	holder.position = Vector2(10,10)
	holder.size = Vector2(460,200)
	holder.stretch = true
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(holder)
	var view := SubViewport.new()
	view.own_world_3d = true
	view.transparent_bg = true
	view.msaa_3d = Viewport.MSAA_4X
	holder.add_child(view)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.9
	cam.position = Vector3(0,2.2,3.2)
	view.add_child(cam)
	cam.look_at(Vector3(0,0.45,0),Vector3.UP)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50,-35,0)
	sun.light_energy = 1.1
	view.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("c8e4ed")
	env.environment.ambient_light_energy = 0.5
	view.add_child(env)
	var studio := Diorama.new()
	view.add_child(studio)
	studio.shape("disc",Vector3(0,0.0,0),Vector3(3.4,0.08,3.4),Color("24525a"))
	var color := (paint if paint.a > 0.0 else Color(spec.color)) if unlocked else Color("6d7a7c")
	showcase_car = studio.car_model(color,false,str(spec.style))
	showcase_car.rotation.y = showcase_angle
	var stats := [["TEMPO",float(spec.power),7.8,11.2],["GRIP",float(spec.grip),11.4,14.2],
		["GELÄNDE",float(spec.offroad),0.9,2.2],["TURBO",float(spec.turbo),0.85,1.3]]
	for i in range(stats.size()):
		var col := i % 2
		var row := i / 2
		var pos := Vector2(22+col*232,222+row*52)
		label(box,stats[i][0],pos,11,Color("9fc5bd"))
		var bar := Control.new()
		bar.position = pos + Vector2(0,28)
		bar.size = Vector2(206,10)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var share := clampf((stats[i][1]-stats[i][2])/(stats[i][3]-stats[i][2]),0.0,1.0)*0.85+0.15
		bar.draw.connect(func():
			bar.draw_style_box(style(Color("2c5f66"),5),Rect2(Vector2.ZERO,bar.size))
			bar.draw_style_box(style(ORANGE if unlocked else Color("8a9a9c"),5),Rect2(Vector2.ZERO,Vector2(bar.size.x*share,bar.size.y))))
		box.add_child(bar)

func _process(dt: float) -> void:
	if is_instance_valid(showcase_car):
		showcase_angle += dt*0.6
		showcase_car.rotation.y = showcase_angle
	update_fps()
	update_keyboard_lift(dt)

func drawing() -> void:
	clear()
	if app.party != null:
		var k: int = app.party.turn
		header("%s     /     SPIELER %d ZEICHNET" % [app.track.name.to_upper(),k+1])
	elif app.lobby != null and app.lobby.draw != null:
		header("%s     /     ALLE ZEICHNEN" % app.track.name.to_upper())
	else:
		header("%s     /     LINIE PLANEN" % app.track.name.to_upper())
	var p := panel(content,Rect2(40,134,295,105))
	status = label(p,"RUNDE 1 / 2",Vector2(22,14),26)
	detail = label(p,"Zeichne in Pfeilrichtung",Vector2(22,52),16,MUTED)
	progress_bar = ProgressBar.new()
	progress_bar.position = Vector2(22,82)
	progress_bar.size = Vector2(251,5)
	progress_bar.show_percentage = false
	progress_bar.add_theme_stylebox_override("background",style(Color("dadfd3"),3))
	progress_bar.add_theme_stylebox_override("fill",style(ORANGE,3))
	progress_bar.size.y = 5
	p.add_child(progress_bar)
	# Leisten lassen Berührungen durch (nur ihre Knöpfe reagieren), damit man bis an ihren Rand zeichnen kann.
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var footer := panel(content,Rect2(40,764,1360,104))
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label(footer,"ZEICHNE DEIN TEMPO",Vector2(24,16),13,ORANGE)
	label(footer,"Zu schnell in die Kurve = Drift. Nadelöhre ohne Wand!" if app.track.mode == "drift" else "Langsam in Kurven. Schnell auf Geraden.",Vector2(24,39),24)
	instruction_label = label(footer,"Ziehen = Kamera · Zwei Finger = Zoom · Im schimmernden Ende weitermalen",Vector2(24,74),14,MUTED)
	speed_legend(footer,Vector2(610,14))
	button(footer,"Neu zeichnen",Rect2(944,25,185,55),app.start_drawing)
	button(footer,"Fahrhilfe",Rect2(1142,25,193,55),help_overlay)
	if app.party != null:
		party_ui.draw_chip()
	elif app.lobby != null and app.lobby.draw != null:
		lobby_ui.draw_overlay()   # WLAN: eigenes Schild und Stand der anderen

func free_band() -> Vector2:
	# Freier Sichtbereich (Bildschirm-y von/bis) zwischen Kopfleiste und Fußleiste der Zeichenansicht.
	return Vector2(content.position.y+118.0, content.position.y+756.0)

func speed_legend(parent: Control, pos: Vector2) -> void:
	var legend := Control.new()
	legend.position = pos
	legend.size = Vector2(240,76)
	legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(legend)
	label(legend,"LANGSAM",Vector2.ZERO,13,MUTED)
	label(legend,"SCHNELL",Vector2(152,0),13,MUTED)
	label(legend,"breit & grün",Vector2(0,54),14,MUTED)
	label(legend,"schmal & rot",Vector2(152,54),14,MUTED)
	legend.draw.connect(func():
		# Dark road swatch keeps the pale end readable on the cream HUD.
		legend.draw_style_box(style(Color("394950"),9),Rect2(-7,31,254,20))
		for i in range(48):
			var speed := lerpf(5.0,29.0,float(i)/47.0)
			legend.draw_line(Vector2(i*5.0,41),Vector2((i+1)*5.0,41),Diorama.line_color(speed),Diorama.line_half_width(speed)*32.0,true))

func race() -> void:
	if app.party != null:
		party_ui.race()
		return
	clear()
	header("%s     /     %s" % [app.track.name.to_upper(),"VORFÜHRFAHRT" if app.demonstration else "RENNEN"])
	var p := panel(content,Rect2(40,136,247,180))
	status = label(p,"RUNDE 1 / 2",Vector2(22,15),17,MUTED)
	time_label = label(p,"00:00.000",Vector2(20,46),36)
	rank_label = label(p,"1 / 2",Vector2(22,105),36)
	label(p,"PUNKTE" if app.track.mode == "drift" else "PLATZ",Vector2(122,125),14,MUTED)
	var speed := panel(content,Rect2(40,783,242,78))
	speed_label = label(speed,"0",Vector2(22,6),43)
	label(speed,"km/h",Vector2(160,37),17,MUTED)
	center = label(content,"3",Vector2(590,300),130,PAPER,260)
	center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Der Knopf ist zugleich die Turbo-Anzeige (TurboGauge): dunkel = leerer Tank, von unten orange gefüllt, Prozent und „+“ beim Laden.
	turbo_button = button(content,"",Rect2(1180,698,214,164),func(): pass,true)
	turbo_button.add_theme_stylebox_override("normal",style(Color(0.09,0.2,0.22,0.92),14))
	turbo_button.add_theme_stylebox_override("hover",style(Color(0.12,0.25,0.27,0.92),14))
	turbo_button.add_theme_stylebox_override("pressed",style(Color(0.18,0.33,0.35,0.95),14,Color.WHITE))
	turbo_button.button_down.connect(func(): app.turbo_held = true)
	turbo_button.button_up.connect(func(): app.turbo_held = false)
	var gauge := TurboGauge.new()
	gauge.setup(app,bold_font)
	if app.lobby != null and app.me < app.models.size():
		gauge.tint = app.models[app.me].get_meta("tag_color", ORANGE)   # WLAN-Mehrspieler: Knopf in der Spielerfarbe
	turbo_button.add_child(gauge)
	# Hinweis links neben dem Knopf, rechtsbündig mit 24 px Abstand (vorher ragte der längere Satz in den Knopf hinein); das Feld
	# ist fest 330 px breit und bricht notfalls um, statt nach rechts zu wachsen.
	var hint := label(content,"Bremsen lädt den Turbo.",Vector2(turbo_button.position.x-24-330,826),17,PAPER,330)
	hint.name = "TurboHint"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

func drift_results(score: int, target: int, in_time: bool, record: bool) -> void:
	clear()
	header("%s     /     DRIFT-WERTUNG" % app.track.name.to_upper())
	var p := panel(content,Rect2(427,140,586,700))
	var won := in_time and score >= target
	label(p,"VORFÜHRFAHRT" if app.demonstration else ("NEUER PUNKTEREKORD" if record else "DEIN DRIFT-ERGEBNIS"),Vector2(34,28),15,ORANGE)
	label(p,"Quer ist mehr." if won else ("Zu langsam." if not in_time else "Mehr Winkel, mehr Punkte."),Vector2(30,68),38)
	label(p,"PUNKTE",Vector2(34,128),21,MUTED)
	label(p,"%d" % score,Vector2(32,162),60)
	label(p,"Ziel: %d Punkte im Zeitlimit" % target,Vector2(34,253),20,MUTED,515)
	var solo: bool = app.solo()
	label(p,("★  Gold für Herausforderung %d" % (app.stage+1)) if won and not app.demonstration and solo else ("Das Zeitlimit war vorbei." if not in_time else ("Punkteziel erreicht." if won and not solo else "Plane die Kurven schneller – das Heck soll kommen.")),Vector2(34,300),20,ORANGE,515)
	label(p,"Wandberührungen: %d" % app.vehicles[app.me].wall_hits,Vector2(34,380),18,MUTED)
	if solo and not app.demonstration and app.store.last_place > 0 and in_time:
		label(p,"Platz %d deiner Bestenliste" % app.store.last_place,Vector2(34,494),18,ORANGE if app.store.last_place==1 else MUTED)
	button(p,"Neue Linie     →",Rect2(34,548,518,62),app.start_drawing,true)
	button(p,"Zum Menü",Rect2(34,622,518,56),app.show_menu)

func results(rows: Array, rank: int, record: bool) -> void:
	clear()
	header("%s     /     ZIELEINLAUF" % app.track.name.to_upper())
	var p := panel(content,Rect2(427,140,586,700))
	label(p,"VORFÜHRFAHRT" if app.demonstration else ("NEUE BESTZEIT" if record else "DEIN RENNERGEBNIS"),Vector2(34,28),15,ORANGE)
	var crashed: bool = app.vehicles[app.me].crashed
	var rolled: bool = app.vehicles[app.me].rolled_back
	label(p,("Zurückgerollt!" if rolled else "Abgestürzt!") if crashed else ("Linie mit Klasse." if rank==1 else "Die nächste Linie zählt."),Vector2(30,68),38)
	label(p,"AUSGESCHIEDEN" if crashed else "PLATZ %d" % rank,Vector2(34,128),21,MUTED)
	label(p,"—" if crashed else app.format_time(app.vehicles[app.me].finish_time),Vector2(32,162),60)
	var tip := "Mehr Schwung vor Sprung und Looping – oder weniger Tempo an der Kante." if crashed else "Früher bremsen. Am Ausgang Turbo halten."
	if rolled:
		tip = "Zu wenig Schwung für den Looping – plane davor mehr Tempo."
	var solo: bool = app.solo()
	label(p,("★  Gold für Herausforderung %d" % (app.stage+1)) if rank==1 and not crashed and not app.demonstration and solo else tip,Vector2(34,253),20,ORANGE,515)
	for i in range(rows.size()):
		var row: Dictionary = rows[i]
		label(p,"%02d" % row.rank,Vector2(34,310+i*45),20,MUTED)
		label(p,driver_name(row.index),Vector2(94,310+i*45),20,ORANGE if row.index==app.me else INK)
		var status_text: String = app.format_time(row.time) if row.time>=0 else ("Abgestürzt" if row.get("crashed", false) else "Im Rennen …")
		result_times[row.index] = label(p,status_text,Vector2(362,310+i*45),20)
	if solo and not app.demonstration and app.store.last_place > 0:
		label(p,"Platz %d deiner Bestenliste" % app.store.last_place,Vector2(34,494),18,ORANGE if app.store.last_place==1 else MUTED)
	button(p,"Neue Linie     →",Rect2(34,548,518,62),app.start_drawing,true)
	button(p,"Zum Menü",Rect2(34,622,518,56),app.show_menu)

func driver_name(index: int) -> String:
	# Name statt „DU“ / „RIVALE n“ (main.car_names); ohne Namen die bisherige Beschriftung.
	var names: Array = app.car_names
	if index >= 0 and index < names.size() and str(names[index]) != "":
		return str(names[index])
	return "DU" if index==app.me else "RIVALE %d" % (index + (1 if index < app.me else 0))

func overlay(title: String, text: String, box := Vector2(640,560)) -> Panel:
	var shade := ColorRect.new()
	shade.color = Color(0.035,0.12,0.15,0.68)
	shade.position = -content.position
	shade.size = get_viewport().get_visible_rect().size
	content.add_child(shade)
	var p := panel(shade,Rect2((Vector2(1440,900)-box)*0.5+content.position,box))
	label(p,title,Vector2(32,26),36)
	label(p,text,Vector2(34,86),21,MUTED,box.x-68)
	return p

func toggle(parent: Control, text: String, pos: Vector2, on: bool, changed: Callable) -> CheckButton:
	# Dunkle Schrift in allen Zuständen (vorher weiß auf Creme, kaum lesbar).
	var check := CheckButton.new()
	check.text = text
	check.position = pos
	check.size = Vector2(572,52)
	check.button_pressed = on
	check.add_theme_font_size_override("font_size",readable(20))
	for key in ["font_color","font_pressed_color","font_hover_color","font_hover_pressed_color","font_focus_color"]:
		check.add_theme_color_override(key,INK)
	check.toggled.connect(changed)
	parent.add_child(check)
	return check

func paused() -> void:
	if app.party != null:
		pads.visible = false
		party_ui.paused()
		return
	var p := overlay("Kurze Boxenpause.","Deine Linie wartet auf dich.")
	button(p,"Weiterfahren",Rect2(34,190,572,66),app.resume_game,true)
	button(p,"Neu zeichnen",Rect2(34,278,572,62),app.start_drawing)
	button(p,"Zum Menü",Rect2(34,362,572,62),app.show_menu)
	button(p,"Sound & Musik  ♪",Rect2(34,446,572,62),func(): p.get_parent().queue_free(); sound_settings())

func help_overlay() -> void:
	app.recorder.end()
	var p := overlay("Dein Finger gibt das Tempo vor.","Zeichne zwei volle Runden ab dem Startpunkt.\n\nLangsam = breit & grün. Schnell = schmal & rot.\nWird die Linie schmaler und röter, gibst du Gas. Wird sie breiter und grüner, bremst du. Plane den Bremsweg vor der Kurve ein.\n\nAbheben pausiert. Im schimmernden Ende der Linie darfst du neu ansetzen – nach 0,5 s Weitermalen ersetzt der neue Ansatz den alten Rest. Ziehen verschiebt die Kamera, zwei Finger zoomen, Doppeltipp zeigt die ganze Strecke.
Neben der Fahrbahn darfst du zeichnen – der Untergrund bremst. Die Wegpunkt-Tore musst du aber durchfahren.",Vector2(820,800))
	button(p,"Verstanden",Rect2(34,706,752,66),func(): p.get_parent().queue_free(),true)

func settings() -> void:
	var p := overlay("Deine Boxeneinstellungen.","Wird auf diesem Gerät gespeichert.",Vector2(640,840))
	toggle(p,"Rennkamera folgt dem Auto",Vector2(34,140),bool(app.store.data.camera),
		func(on: bool): app.store.data["camera"]=on; app.store.save())
	# Kamera-Zoom: 0 % = Übersicht wie bisher, 100 % = Fahrbahnbreite füllt die kürzere Bildschirmseite.
	slider_row(p,"Kamera-Zoom beim Folgen",200,"camera_zoom",0.4)
	# Beim Zeichnen gibt es keinen Zoom-Regler: Kamera per Ziehen und Zwei-Finger-Zoom.
	# Zeichen-Tempo: wie schnell die Linie bei gleicher Fingerbewegung wird (Mitte = Grundwert).
	slider_row(p,"Tempo der Linie",310,"draw_tempo",0.5,Callable(),func(v: float) -> String:
		var change := int(round((pow(2.0,(v-0.5)*2.0)-1.0)*100.0))
		return "Standard" if change == 0 else "%+d %%" % change)
	toggle(p,"Geisterauto (deine beste Fahrt)",Vector2(34,412),bool(app.store.data.get("ghost",true)),
		func(on: bool): app.store.data["ghost"]=on; app.store.save())
	# Grafikqualität: Schatten, Kantenglättung, Partikel- und Nebelmenge.
	label(p,"Grafikqualität",Vector2(38,470),20)
	var gfx := int(app.store.data.get("gfx",2))
	for i in range(3):
		button(p,Atmosphere.QUALITY_NAMES[i],Rect2(34+i*194,508,184,56),func():
			app.store.data["gfx"]=i; app.store.save(); app.apply_atmosphere()
			p.get_parent().queue_free(); settings(),i==gfx)
	button(p,"Name, Schilder & Sprechblasen",Rect2(34,588,572,62),func(): p.get_parent().queue_free(); name_settings(settings))
	button(p,"Sound & Musik  ♪",Rect2(34,664,278,62),func(): p.get_parent().queue_free(); sound_settings())
	button(p,"Updates",Rect2(328,664,278,62),func(): p.get_parent().queue_free(); update_dialog())
	button(p,"Zurück",Rect2(34,744,572,66),func(): p.get_parent().queue_free(),true)

func name_settings(back := Callable()) -> void:
	# Spielername (höchstens 12 Zeichen, Umlaute erlaubt; leer = Vorschlag) und Anzeige von Namensschildern und Sprechblasen.
	# Auch als Namensabfrage beim ersten Mehrspielerstart nutzbar (back = weiter danach).
	var p := overlay("Dein Fahrername.","Steht über deinem Auto und in der Wertung. Höchstens %d Zeichen." % ProgressStore.NAME_MAX,Vector2(640,600))
	var field := LineEdit.new()
	field.name = "NameEdit"
	field.position = Vector2(34,176)
	field.size = Vector2(572,64)
	field.max_length = ProgressStore.NAME_MAX
	field.text = ProgressStore.clean_name(str(app.store.data.get("name","")))
	field.placeholder_text = app.store.default_name()
	field.virtual_keyboard_enabled = true
	field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	field.select_all_on_focus = true
	field.clear_button_enabled = true
	field.caret_blink = true
	field.add_theme_font_size_override("font_size",readable(24))
	field.add_theme_font_override("font",bold_font)
	field.add_theme_color_override("font_color",INK)
	field.add_theme_color_override("font_placeholder_color",Color(MUTED,0.75))
	field.add_theme_color_override("caret_color",ORANGE)
	field.add_theme_stylebox_override("normal",style(Color("ffffff"),14,Color("c9cfc4")))
	field.add_theme_stylebox_override("focus",style(Color.TRANSPARENT,14,ORANGE))
	field.add_theme_stylebox_override("read_only",style(Color("eeeeea"),14))
	p.add_child(field)
	# Unerlaubte Zeichen schon beim Tippen weglassen (auch über die Bildschirmtastatur).
	field.text_changed.connect(func(text: String):
		var ok := ProgressStore.filter_name(text)
		if ok != text:
			var caret := field.caret_column
			field.text = ok
			field.caret_column = mini(caret, ok.length()))
	var commit := func():
		app.store.set_player_name(field.text)
		field.text = ProgressStore.clean_name(field.text)
	field.text_submitted.connect(func(_t: String): commit.call(); field.release_focus())
	field.focus_exited.connect(commit)
	toggle(p,"Namen über den Autos anzeigen",Vector2(34,268),bool(app.store.data.get("show_names",true)),
		func(on: bool): app.store.data["show_names"]=on; app.store.save())
	toggle(p,"Sprechblasen (Überholt!, Dreher! …)",Vector2(34,326),bool(app.store.data.get("bubbles",true)),
		func(on: bool): app.store.data["bubbles"]=on; app.store.save())
	label(p,"Gegner haben feste Namen je Auto. Nur Anzeige – die Rennen ändern sich dadurch nicht.",Vector2(38,396),15,MUTED,560)
	button(p,"Fertig",Rect2(34,500,572,66),func():
		commit.call()
		p.get_parent().queue_free()
		if back.is_valid():
			back.call(),true)

func overlay_open() -> bool:
	return content.get_children().any(func(c): return c is ColorRect and c.name != "HandoverCard")

func close_overlays() -> void:
	# Offene Dialoge schließen (Zurück-Taste im Menü und in den Mehrspieler-Einstellungen).
	for c in content.get_children():
		if c is ColorRect and c.name != "HandoverCard":
			c.queue_free()

func update_dialog() -> void:
	var up: Updater = app.updater
	var p := overlay("Updates.","Installiert: Version %s" % Updater.current_version(),Vector2(760,760))
	var y := 132.0
	if up.available():
		label(p,"Neu auf GitHub: Version %s%s  (%d MB)" % [up.release.version," · Beta" if up.release.get("beta",false) else "",int(up.release.size/1048576)],Vector2(34,y),20,ORANGE)
		y += 44
	var state := label(p,up.status + (" %d %%" % up.percent if up.busy and up.percent >= 0 else ""),Vector2(34,y),20,INK,690)
	if up.available() and str(up.release.notes) != "":
		var notes := RichTextLabel.new()
		notes.position = Vector2(34,y+56)
		notes.size = Vector2(692,200)
		notes.bbcode_enabled = false
		notes.text = str(up.release.notes)
		notes.add_theme_color_override("default_color",MUTED)
		notes.add_theme_font_size_override("normal_font_size",readable(16))
		p.add_child(notes)
	if OS.get_name() == "Android" and not up.can_install():
		button(p,"Installation erlauben (Android-Einstellung)",Rect2(34,500,692,56),func(): up.open_permission())
	var action_text := "Suchen"
	var action := func(): up.check(true)
	if up.busy:
		action_text = "Bitte warten …"
	elif up.apk_ready:
		action_text = "Installieren"
		action = func(): up.install()
	elif up.available():
		action_text = "Herunterladen"
		action = func(): up.download()
	# Beta-Kanal: auch Vorabversionen (GitHub „Pre-release“) anbieten – zum Testen unterwegs.
	toggle(p,"Beta-Versionen erhalten (Vorabversionen zum Testen)",Vector2(30,506 if not (OS.get_name() == "Android" and not up.can_install()) else 450),up.beta(),
		func(on: bool): up.set_beta(on))
	var go := button(p,action_text,Rect2(34,580,440,66),action,true)
	go.disabled = up.busy
	button(p,"Schließen",Rect2(488,580,238,66),func(): p.get_parent().queue_free())
	# Live aktualisieren, solange der Dialog offen ist.
	var refresh := func():
		if is_instance_valid(p):
			p.get_parent().queue_free()
			update_dialog()
	up.changed.connect(refresh, CONNECT_ONE_SHOT)
	p.tree_exiting.connect(func(): if up.changed.is_connected(refresh): up.changed.disconnect(refresh))

func logo_tapped() -> void:
	var now := Time.get_ticks_msec()
	logo_taps = logo_taps+1 if now-logo_tap_time < 600 else 1
	logo_tap_time = now
	if logo_taps >= 5:
		logo_taps = 0
		debug_menu()

func debug_menu() -> void:
	# Entwickler-Menü: Bedingungen und Qualität sofort umschalten, ohne die Karriere zu spielen.
	var debug: Dictionary = app.debug_data()
	var current: Dictionary = app.current_conditions()
	var p := overlay("Entwickler.","Challenge: %s" % Atmosphere.describe(app.track.conditions_for(app.stage)),Vector2(820,860))
	var refresh := func():
		app.store.save()
		app.apply_atmosphere()
		p.get_parent().queue_free()
		if app.phase == "menu":
			menu()
		debug_menu()
	var set_value := func(key: String, value):
		var o = debug.get("override")
		if not o is Dictionary:
			o = current.duplicate()
		o[key] = value
		debug["override"] = o
		refresh.call()
	var rows := [["Tageszeit","time",["day","dusk","night"],Atmosphere.TIME_NAMES.values()],
		["Wetter","weather",["dry","rain","snow"],Atmosphere.WEATHER_NAMES.values()],
		["Nebel","fog",[0,1,2],["Aus","Schwaden","Dicht"]]]
	for r in range(rows.size()):
		var row: Array = rows[r]
		label(p,row[0],Vector2(38,152+r*84),20)
		for i in range(3):
			var value = row[2][i]
			var b := button(p,row[3][i],Rect2(200+i*196,140+r*84,186,56),func(): set_value.call(row[1],value),str(current[row[1]])==str(value))
			b.clip_text = true
	label(p,"Grafik",Vector2(38,404),20)
	for i in range(3):
		button(p,Atmosphere.QUALITY_NAMES[i],Rect2(200+i*196,392,186,56),func(): app.store.data["gfx"]=i; refresh.call(),
			i==int(app.store.data.get("gfx",2)))
	var reset := button(p,"Original-Bedingungen der Challenge",Rect2(34,476,752,56),func(): debug.erase("override"); refresh.call())
	reset.disabled = not debug.get("override") is Dictionary
	toggle(p,"Alle Strecken & Autos freischalten",Vector2(34,548),bool(debug.get("unlock",false)),func(on: bool): debug["unlock"]=on; refresh.call())
	toggle(p,"FPS anzeigen",Vector2(34,604),bool(debug.get("fps",false)),func(on: bool): debug["fps"]=on; app.store.save())
	button(p,"Vorführfahrt starten",Rect2(34,676,368,66),func(): p.get_parent().queue_free(); app.demo(),true)
	button(p,"Netztest (Mehrspieler)",Rect2(418,676,368,66),func(): p.get_parent().queue_free(); net_test())
	button(p,"Schließen",Rect2(34,756,752,66),func(): p.get_parent().queue_free())

func net_test() -> NetTestScreen:
	# Versteckter Netztest für den Gerätetest M0 (docs/MULTIPLAYER_RECHERCHE.md): Host / Mitspielen / Adresse, Ping, WLAN-Bindung.
	# Nur aus dem Menü: ein laufendes Zeichnen oder Rennen wird vorher beendet, damit darunter nichts weiterläuft.
	# Der Bildschirm (CanvasLayer 90) deckt alles ab und löst beim Schließen Verbindung, WLAN-Bindung und Multicast-Sperre.
	# Protokoll: user://netztest.log (adb shell run-as de.draw2race.game cat files/netztest.log).
	for child in app.get_children():
		if child is NetTestScreen and not child.is_queued_for_deletion():
			return child
	if app.phase != "menu":
		app.show_menu()
	return NetTestScreen.open(app)

func sound_settings() -> void:
	var p := overlay("Sound & Musik.","Musik und Geräusche getrennt einstellen.",Vector2(640,760))
	toggle(p,"Musik",Vector2(34,136),bool(app.store.data.music),
		func(on: bool): app.store.data["music"]=on; app.store.save())
	# Musikstil: "energie" = Songs mit Gesang, "ruhig" = Instrumentalstücke.
	toggle(p,"Musik energiegeladen (aus = ruhig)",Vector2(34,190),
		str(app.store.data.get("music_style","energie"))=="energie",
		func(on: bool): app.store.data["music_style"]="energie" if on else "ruhig"; app.store.save())
	slider_row(p,"Lautstärke Musik",256,"music_volume",0.8)
	toggle(p,"Motor, Reifen & Effekte",Vector2(34,376),bool(app.store.data.sound),
		func(on: bool): app.store.data["sound"]=on; app.store.save())
	slider_row(p,"Lautstärke Geräusche",440,"sfx_volume",1.0,func(): app.sound.start_signal(false))
	button(p,"Zurück",Rect2(34,640,572,66),func(): p.get_parent().queue_free(),true)

func slider_row(parent: Control, title: String, y: float, key: String, fallback: float, preview := Callable(), shown := Callable()) -> HSlider:
	# Beschriftung mit Prozentwert und Regler 0-100 %; speichert als 0..1 unter key.
	# shown: optionale Anzeige des Werts (0..1 -> Text), sonst Prozent.
	var value := float(app.store.data.get(key,fallback))
	var describe := shown if shown.is_valid() else func(v: float) -> String: return "%d %%" % int(round(v*100))
	var caption := label(parent,"%s: %s" % [title,describe.call(value)],Vector2(38,y),20)
	var slider := HSlider.new()
	slider.position = Vector2(38,y+46)
	slider.size = Vector2(564,44)
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 5
	slider.value = value*100
	slider.add_theme_icon_override("grabber",make_grabber())
	slider.add_theme_icon_override("grabber_highlight",make_grabber())
	var rail := style(Color("d8dccf"),6)
	rail.content_margin_top = 7
	rail.content_margin_bottom = 7
	slider.add_theme_stylebox_override("slider",rail)
	slider.add_theme_stylebox_override("grabber_area",style(ORANGE,6))
	slider.add_theme_stylebox_override("grabber_area_highlight",style(ORANGE,6))
	slider.value_changed.connect(func(v: float):
		caption.text = "%s: %s" % [title,describe.call(v/100.0)]
		app.store.data[key] = v/100.0
		app.store.save())
	if preview.is_valid():
		# Hörprobe beim Loslassen, damit man die neue Lautstärke sofort einschätzen kann.
		slider.drag_ended.connect(func(_changed: bool): preview.call())
	parent.add_child(slider)
	return slider

func make_grabber() -> Texture2D:
	var img := Image.create(40,40,false,Image.FORMAT_RGBA8)
	for y in range(40):
		for x in range(40):
			var d := Vector2(x-19.5,y-19.5).length()
			img.set_pixel(x,y,ORANGE if d<17 else (Color.WHITE if d<19.5 else Color(0,0,0,0)))
	return ImageTexture.create_from_image(img)
