extends SceneTree

# Zeichenansicht: Zoomen und Verschieben bis an den Kartenrand (Nutzerbefund 14.10.2026: „Das Zoomen beim Zeichnen ist an den
# Kartenrändern zu sehr eingeschränkt“). Je Strecke und Bildformat: Der Punkt unter den Fingern bleibt beim Hineinzoomen dort, das
# Herauszoomen endet ohne Sprung genau in der Übersicht, die Grenze hält ihre Zusagen (Leere hinter der Fahrbahnkante, senkrechter
# Spielraum wie bisher, waagerecht verschiebbar), Doppeltipp nur aus echten Tippern, zweiter Finger während der Probe zoomt.
# Gesten wie auf dem Handy: touch_down/touch_move/touch_up, danach je Bild die Kamera wie _process (apply_view).

const TRACKS := ["azure","city","kids","quarry","forest","serra"]
const FORMATS := [Vector2i(2340,1080), Vector2i(1600,900), Vector2i(2048,1536)]
const FRAMES := 30
var failures := 0
var checks := 0
var app: Node
var rng := RandomNumberGenerator.new()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ",message)
	else: print("PASS: ",message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	await process_frame
	var test_path := "user://test_view_%s.json" % Time.get_ticks_usec()
	app.store = ProgressStore.new(test_path)
	rng.seed = 20261014
	for id in TRACKS:
		app.select_track(id)
		for format in FORMATS:
			root.size = format
			await process_frame
			var tag := "%s %dx%d" % [id, format.x, format.y]
			overview_case(tag)
			limit_case(tag)
			pinch_case(tag)
			zoom_out_case(tag)
			drag_case(tag)
			pan_case(tag)
			wheel_case(tag)
	root.size = FORMATS[0]
	await process_frame
	app.select_track("azure")
	tap_case()
	trial_case()
	app.queue_free()
	await process_frame
	for suffix in ["",".bak",".tmp",".run"]:
		if FileAccess.file_exists(test_path+suffix): DirAccess.remove_absolute(test_path+suffix)
	print("RESULT: ",checks-failures,"/",checks," passed")
	quit(1 if failures else 0)

# ---------- Hilfen ----------

func begin_view() -> void:
	# Zeichnen beginnen und die Kamera wie im ersten Bild von _process stellen.
	app.start_drawing()
	app.apply_view()

func const_of(key: String) -> float:
	return float(app.get_script().get_script_constant_map()[key])

func screen_size() -> Vector2:
	return app.get_viewport().get_visible_rect().size

func reach() -> Vector2:
	var track: Circuit = app.track
	return track.bounds.size*0.5 + Vector2.ONE*(track.max_half_width + const_of("VIEW_MARGIN"))

func half_view(zoom: float) -> Vector2:
	# Halbe sichtbare Ausdehnung (x, z) des freien Bandes in der Bezugsebene (Draufsicht).
	var size := screen_size()
	var band: Vector2 = app.hud.free_band()
	return Vector2(size.x*0.5, (band.y-band.x)*0.5)*zoom/size.y

func anchor_of(p: Vector2) -> Vector3:
	return Vector3(p.x, 0.20 + app.road_height(p), p.y)

func in_band(screen: Vector2) -> bool:
	var band: Vector2 = app.hud.free_band()
	return screen.x >= 10.0 and screen.x <= screen_size().x-10.0 and screen.y >= band.x+10.0 and screen.y <= band.y-10.0

func frame() -> void:
	# Ein Bild der Zeichenphase: _process klemmt und stellt die Kamera.
	app.apply_view()

func error_px(w: Vector3, mid: Vector2) -> float:
	var camera: Camera3D = app.camera
	if camera.is_position_behind(w):
		return INF
	return camera.unproject_position(w).distance_to(mid)

func pinch(mid: Vector2, from_px: float, to_px: float, w: Vector3) -> float:
	# Zwei Finger symmetrisch um mid von from_px auf to_px Abstand, FRAMES Bilder, je Bild beide Finger und dann die Kamera.
	# Liefert die größte Abweichung des Punkts w von der Fingermitte während der ganzen Geste.
	app.touch_down(40,mid-Vector2(from_px*0.5,0))
	app.touch_down(41,mid+Vector2(from_px*0.5,0))
	var worst := 0.0
	for f in range(1,FRAMES+1):
		var d := from_px*pow(to_px/from_px,float(f)/FRAMES)
		app.touch_move(40,mid-Vector2(d*0.5,0))
		app.touch_move(41,mid+Vector2(d*0.5,0))
		frame()
		worst = maxf(worst,error_px(w,mid))
	app.touch_up(41)
	app.touch_up(40)
	return worst

# ---------- Fälle je Strecke und Format ----------

func overview_case(tag: String) -> void:
	begin_view()
	var widest: float = app.overview_size()
	var room: Vector2 = app.view_room()
	var center: Vector3 = app.track_center()
	var focus: Vector3 = app.view_focus
	check(is_equal_approx(app.view_zoom,widest) and room.is_zero_approx() and absf(focus.x-center.x)+absf(focus.z-center.z) < 1e-4 and is_equal_approx(app.cam_pitch,const_of("PITCH_DRAW")),
		"%s: Zeichnen beginnt genau in der Übersicht (Zoom %.1f m, Band %s)" % [tag,widest,app.hud.free_band()])

func limit_case(tag: String) -> void:
	# Grenze: zufällige Zustände klemmen. Fokus innerhalb von view_room, Leere hinter der Fahrbahnkante höchstens VIEW_MARGIN bzw. der
	# Randstreifen der Übersicht (je nach Zoom dazwischen); Hineinzoomen um einen sichtbaren Streckenpunkt verschiebt nie (Abgeschlossenheit);
	# senkrechter und waagerechter Spielraum bis 90 % Zoom mindestens wie bisher.
	begin_view()
	var track: Circuit = app.track
	var widest: float = app.overview_size()
	var lo: float = minf(app.road_fill_size()*1.2,widest)
	var center: Vector3 = app.track_center()
	var edge := track.bounds.size*0.5 + Vector2.ONE*track.max_half_width
	var strip := half_view(widest) - edge
	var margin: float = const_of("VIEW_MARGIN")
	var r := reach()
	var worst_room := 0.0
	var worst_over := -INF
	for n in range(400):
		app.view_zoom = rng.randf_range(lo,widest)
		app.view_focus = Vector3(center.x + rng.randf_range(-1.5,1.5)*r.x, app.view_focus.y, center.z + rng.randf_range(-1.5,1.5)*r.y)
		app.clamp_view_state()
		var zoom: float = app.view_zoom
		var room: Vector2 = app.view_room()
		var off := Vector2(absf(app.view_focus.x-center.x),absf(app.view_focus.z-center.z))
		worst_room = maxf(worst_room,maxf(off.x-room.x,off.y-room.y))
		var over := off + half_view(zoom) - edge
		var t := zoom/widest
		var allow := Vector2(maxf(margin,lerpf(margin,strip.x,t)),maxf(margin,lerpf(margin,strip.y,t)))
		worst_over = maxf(worst_over,maxf(over.x-allow.x,over.y-allow.y))
	check(worst_room <= 1e-4,"%s: Fokus bleibt in view_room (Überschreitung %.5f m)" % [tag,worst_room])
	check(worst_over <= 0.01,"%s: Leere hinter der Fahrbahnkante höchstens VIEW_MARGIN bzw. Randstreifen der Übersicht (%.3f m darüber, Randstreifen %s)" % [tag,worst_over,strip])
	var moved := 0
	var tries := 0
	var worst_move := 0.0
	for n in range(400):
		app.view_zoom = rng.randf_range(lo,widest)
		app.view_focus = Vector3(center.x + rng.randf_range(-1.0,1.0)*r.x, app.view_focus.y, center.z + rng.randf_range(-1.0,1.0)*r.y)
		app.clamp_view_state()
		var zoom: float = app.view_zoom
		var f: Vector3 = app.view_focus
		var p: Vector2 = track.points[rng.randi_range(0,track.points.size()-1)]
		var half := half_view(zoom)
		if absf(p.x-f.x) > half.x or absf(p.y-f.z) > half.y:
			continue
		var target := maxf(lo,zoom*rng.randf_range(0.3,0.99))
		var k := target/zoom
		app.view_zoom = target
		app.view_focus = Vector3(p.x+(f.x-p.x)*k, f.y, p.y+(f.z-p.y)*k)
		var before: Vector3 = app.view_focus
		app.clamp_view_state()
		tries += 1
		var shift: float = (app.view_focus-before).length()
		worst_move = maxf(worst_move,shift)
		if shift > 1e-4:
			moved += 1
	check(tries > 40 and moved == 0,"%s: Hineinzoomen um einen sichtbaren Streckenpunkt wird nie begrenzt (%d von %d verschoben, höchstens %.4f m)" % [tag,moved,tries,worst_move])
	var short := INF
	var old_reach := track.bounds.size*0.5 + Vector2.ONE*(Circuit.HALF_WIDTH + margin)
	for fraction in [0.9,0.75,0.6,0.45,0.3,0.15]:
		var zoom: float = widest*fraction
		if zoom < lo:
			continue
		app.view_zoom = zoom
		var room: Vector2 = app.view_room()
		var old := (old_reach - half_view(zoom)).max(Vector2.ZERO)
		short = minf(short,minf(room.x-old.x,room.y-old.y))
	check(short >= -1e-4,"%s: Spielraum bis 90 %% Zoom mindestens wie bisher (knappster Abstand %.3f m)" % [tag,short])

func pinch_case(tag: String) -> void:
	# Hineinzoomen mit zwei Fingern um Punkte am Kartenrand (äußerste Mittellinienpunkte, Start) und auf der Strecke: Der Punkt unter
	# der Fingermitte bleibt dort (< 2 px), der Zoom wird erreicht (4×), ein zweiter Pinch geht bis zum Anschlag.
	var track: Circuit = app.track
	var points: Array = []
	var ext := [track.points[0],track.points[0],track.points[0],track.points[0]]
	for p in track.points:
		if p.x < ext[0].x: ext[0] = p
		if p.x > ext[1].x: ext[1] = p
		if p.y < ext[2].y: ext[2] = p
		if p.y > ext[3].y: ext[3] = p
	points.append_array(ext)
	points.append(track.at(0.0))
	for k in range(8):
		points.append(track.at((k+0.5)/8.0))
	if track.id == "serra":
		# hoher Punkt (rund 30 m): Maßstab in der Höhe des Ankers
		var best := 0.0
		for k in range(200):
			if absf(track.surface_z(k/200.0)-30.0) < absf(track.surface_z(best)-30.0): best = k/200.0
		points.append(track.at(best))
	var worst1 := 0.0
	var worst2 := 0.0
	var worst_start := 0.0
	var zoom_off := 0.0
	var stop_off := 0.0
	var used := 0
	for p in points:
		begin_view()
		var widest: float = app.overview_size()
		var w := anchor_of(p)
		var camera: Camera3D = app.camera
		var mid := camera.unproject_position(w)
		if not in_band(mid):
			continue
		used += 1
		# Ankerpunkt beim Aufsetzen (ground_point) muss der Punkt unter der Fingermitte sein.
		app.touch_down(40,mid-Vector2(60,0))
		app.touch_down(41,mid+Vector2(60,0))
		worst_start = maxf(worst_start,error_px(app.pinch_anchor,mid))
		app.touch_up(41)
		app.touch_up(40)
		begin_view()
		worst1 = maxf(worst1,pinch(mid,120.0,480.0,w))
		zoom_off = maxf(zoom_off,absf(app.view_zoom/maxf(widest*0.25,app.zoom_floor(w))-1.0))
		var mid2 := camera.unproject_position(w)
		worst2 = maxf(worst2,pinch(mid2,100.0,1600.0,w))
		stop_off = maxf(stop_off,absf(app.view_zoom/app.zoom_floor(w)-1.0))
	check(used >= 6,"%s: genug Anker im freien Band (%d von %d)" % [tag,used,points.size()])
	check(worst_start < 2.0,"%s: Zoom-Anker liegt unter der Fingermitte (höchstens %.2f px)" % [tag,worst_start])
	check(worst1 < 2.0 and zoom_off < 0.01,"%s: 4×-Pinch hält den Punkt unter den Fingern (höchstens %.2f px, Zoom %.2f %% daneben)" % [tag,worst1,zoom_off*100.0])
	check(worst2 < 2.0 and stop_off < 0.01,"%s: zweiter Pinch bis zum Anschlag hält den Punkt (höchstens %.2f px, Anschlag %.2f %% daneben)" % [tag,worst2,stop_off*100.0])

func zoom_out_case(tag: String) -> void:
	# Hineinzoomen, weit an den Rand schieben, mit zwei Fingern in der Bandmitte in Schritten von 2 % herauszoomen: kein Sprung (je
	# Schritt höchstens so viel, wie die Grenze stetig nachzieht) und am Ende genau die Übersicht.
	var size := screen_size()
	var band: Vector2 = app.hud.free_band()
	var mid := Vector2(size.x*0.5,(band.x+band.y)*0.5)
	var r := reach()
	var worst := 0.0
	var end_ok := true
	for corner in [Vector2(1,1),Vector2(-1,1),Vector2(1,-1),Vector2(-1,-1)]:
		begin_view()
		var widest: float = app.overview_size()
		app.view_zoom = widest*0.25
		app.pan_view(corner*20000.0)
		frame()
		var z0: float = app.view_zoom
		app.touch_down(40,mid-Vector2(300,0))
		app.touch_down(41,mid+Vector2(300,0))
		var last: Vector3 = app.view_focus
		var last_zoom := z0
		var step := 0
		while app.view_zoom < widest and step < 100:
			step += 1
			var goal := minf(widest*1.001,z0+widest*0.02*step)
			var d := 600.0*z0/goal
			app.touch_move(40,mid-Vector2(d*0.5,0))
			app.touch_move(41,mid+Vector2(d*0.5,0))
			frame()
			var dz: float = app.view_zoom-last_zoom
			var jump: float = maxf(absf(app.view_focus.x-last.x)-3.0*r.x*dz/widest,absf(app.view_focus.z-last.z)-3.0*r.y*dz/widest)
			worst = maxf(worst,jump)
			last = app.view_focus
			last_zoom = app.view_zoom
		app.touch_up(41)
		app.touch_up(40)
		var center: Vector3 = app.track_center()
		end_ok = end_ok and is_equal_approx(app.view_zoom,widest) and absf(app.view_focus.x-center.x)+absf(app.view_focus.z-center.z) < 1e-3
	check(worst <= 0.01,"%s: Herauszoomen vom Rand ohne Sprung (je Schritt höchstens %.3f m über dem stetigen Nachziehen)" % [tag,worst])
	check(end_ok,"%s: Herauszoomen endet genau in der Übersicht" % tag)

func drag_case(tag: String) -> void:
	# Zwei Finger weit über den Rand hinaus ziehen und dann ein Stück zurück: Die Ansicht folgt sofort (keine Totzone, bis der gedachte
	# Fokus wieder innerhalb läge; höchstens PINCH_SLIP Bildpunkte).
	begin_view()
	var size := screen_size()
	var band: Vector2 = app.hud.free_band()
	var mid := Vector2(size.x*0.5,(band.x+band.y)*0.5)
	var worst := INF
	for dir in [Vector2(1,0),Vector2(-1,0),Vector2(0,1),Vector2(0,-1)]:
		# hineingezoomt, Ansicht schon am Rand (auf der Seite, zu der das Ziehen sie weiter schöbe)
		begin_view()
		app.view_zoom = app.overview_size()*0.5
		app.pan_view(dir*20000.0)
		frame()
		app.touch_down(40,mid-Vector2(200,0))
		app.touch_down(41,mid+Vector2(200,0))
		for n in range(1,16):
			app.touch_move(40,mid-Vector2(200,0)+dir*20.0*n)
			app.touch_move(41,mid+Vector2(200,0)+dir*20.0*n)
			frame()
		var before: Vector3 = app.view_focus
		app.touch_move(40,mid-Vector2(200,0)+dir*270.0)
		app.touch_move(41,mid+Vector2(200,0)+dir*270.0)
		frame()
		# Bildpunkte in der Höhe des Ankers (am Hang ist er der Kamera näher)
		var lift: float = app.pinch_anchor.y-app.view_focus.y
		var k: float = (app.view_zoom-2.0*tan(deg_to_rad(const_of("CAM_FOV"))*0.5)*lift)/screen_size().y
		var back := Vector2(app.view_focus.x-before.x,app.view_focus.z-before.z).dot(dir)/k
		worst = minf(worst,back)
		app.touch_up(41)
		app.touch_up(40)
	check(worst >= 30.0-const_of("PINCH_SLIP")-0.01,"%s: zwei Finger über den Rand und 30 px zurück – die Ansicht folgt sofort (mindestens %.1f px)" % [tag,worst])

func pan_case(tag: String) -> void:
	# Bei 60 % Zoom lässt sich die Ansicht waagerecht verschieben (vorher klebte sie im Querformat in der Mitte).
	begin_view()
	app.view_zoom = app.overview_size()*0.6
	app.apply_view()
	var before: float = app.view_focus.x
	app.pan_view(Vector2(-300,0))
	var moved: float = app.view_focus.x-before
	check(moved > 1.0,"%s: bei 60 %% Zoom waagerecht verschiebbar (%.1f m)" % [tag,moved])

func wheel_case(tag: String) -> void:
	# Mausrad zoomt um den Punkt unter dem Zeiger (hier der Start am Kartenrand).
	begin_view()
	var w := anchor_of(app.track.at(0.0))
	var camera: Camera3D = app.camera
	var at := camera.unproject_position(w)
	var worst := 0.0
	for n in range(12):
		app.zoom_view(0.85,at)
		worst = maxf(worst,error_px(w,at))
	check(worst < 2.0,"%s: Mausrad hält den Punkt unter dem Zeiger (höchstens %.2f px)" % [tag,worst])

# ---------- Doppeltipp und Probe (einmal) ----------

func tap_case() -> void:
	begin_view()
	var widest: float = app.overview_size()
	var size := screen_size()
	var band: Vector2 = app.hud.free_band()
	# Eine freie Stelle weit weg vom Startpunkt (sonst begänne ein Strich).
	var start: Vector2 = app.camera.unproject_position(anchor_of(app.track.at(0.0)))
	var spot := Vector2(size.x*0.3,(band.x+band.y)*0.5)
	if spot.distance_to(start) < 200.0:
		spot.x = size.x*0.7
	var zoomed := func():
		# Ausgangslage je Schritt: hineingezoomt, kein Tipper vom vorigen Schritt offen.
		app.view_zoom = widest*0.5
		app.apply_view()
		app.last_tap = -10.0
	zoomed.call()
	app.touch_down(9,spot)
	check(app.pointer == -99 and app.pan_index == 9,"Freie Stelle greift die Kamera")
	app.touch_move(9,spot+Vector2(80,0))
	app.touch_up(9)
	app.touch_down(9,spot+Vector2(10,0))
	app.touch_move(9,spot+Vector2(90,0))
	app.touch_up(9)
	check(app.view_zoom < widest*0.9,"Zweimal schnell wischen springt nicht in die Übersicht")
	zoomed.call()
	app.touch_down(9,spot)
	app.touch_down(10,spot+Vector2(150,0))
	app.touch_move(10,spot+Vector2(170,0))
	app.touch_up(10)
	app.touch_up(9)
	var after_pinch: float = app.view_zoom
	app.touch_down(9,spot)
	app.touch_up(9)
	check(is_equal_approx(app.view_zoom,after_pinch),"Zoomen und gleich danach tippen springt nicht in die Übersicht")
	zoomed.call()
	app.touch_down(9,spot)
	app.touch_up(9)
	app.touch_down(9,spot+Vector2(60,0))
	app.touch_move(9,spot+Vector2(140,0))
	app.touch_up(9)
	app.touch_down(9,spot)
	app.touch_up(9)
	check(app.view_zoom < widest*0.9,"Tippen, Wischen, Tippen ist kein Doppeltipp")
	zoomed.call()
	app.touch_down(9,spot)
	app.touch_up(9)
	app.touch_down(9,spot+Vector2(8,4))
	app.touch_up(9)
	check(is_equal_approx(app.view_zoom,widest),"Zwei echte Tipper zeigen die ganze Strecke")

func trial_case() -> void:
	# Zweiter Finger, solange der Strich noch Probe ist: Strich verworfen (Linie exakt wie vorher), Zwei-Finger-Zoom beginnt.
	begin_view()
	var track: Circuit = app.track
	var camera: Camera3D = app.camera
	var origin := camera.unproject_position(anchor_of(track.at(0.0)))
	app.touch_down(20,origin)
	check(app.pointer == 20 and app.recorder.trial,"Am Startpunkt beginnt eine Probe")
	var pos := origin
	for k in range(1,9):
		pos = camera.unproject_position(anchor_of(track.at(0.004*k)))
		app.touch_move(20,pos)
	check(pos.distance_to(origin) > 24.0 and app.recorder.trial and app.recorder.route.size() > 1,"Probe gemalt (%.0f px, %d Punkte)" % [pos.distance_to(origin),app.recorder.route.size()])
	app.touch_down(21,pos+Vector2(200,0))
	check(app.pointer == -99 and app.pinch_ids.size() == 2 and app.recorder.route.size() <= 1,"Zweiter Finger während der ersten Probe: Zoom, Strich verworfen (nur der Startpunkt bleibt)")
	app.touch_up(21)
	app.touch_up(20)
	# Mit einer schon gemalten Linie: Neuansatz im schimmernden Ende, zweiter Finger stellt die Linie exakt wieder her.
	begin_view()
	origin = camera.unproject_position(anchor_of(track.at(0.0)))
	app.touch_down(20,origin)
	for k in range(1,13):
		app.touch_move(20,camera.unproject_position(anchor_of(track.at(0.004*k))))
	app.recorder.confirm()
	app.touch_up(20)
	var kept: Array = app.recorder.route.duplicate(true)
	var kept_time: float = app.recorder.draw_time
	check(kept.size() > 2,"Linie steht (%d Punkte)" % kept.size())
	var tip := camera.unproject_position(Vector3(app.recorder.last_pos.x,0.2,app.recorder.last_pos.y))
	app.touch_down(22,tip)
	check(app.pointer == 22 and app.recorder.trial,"Neuansatz im schimmernden Ende ist eine Probe")
	for k in range(13,19):
		app.touch_move(22,camera.unproject_position(anchor_of(track.at(0.004*k))))
	var grown: int = app.recorder.route.size()
	app.touch_down(23,tip+Vector2(-200,0))
	var same: bool = app.recorder.route.size() == kept.size()
	if same:
		for i in range(kept.size()):
			same = same and app.recorder.route[i].p == kept[i].p and app.recorder.route[i].speed == kept[i].speed
	check(grown != kept.size() and same and app.recorder.draw_time == kept_time and app.pointer == -99 and app.pinch_ids.size() == 2,
		"Zweiter Finger während einer Probe: Linie und Malzeit exakt wie vorher, Zoom beginnt")
	app.touch_up(23)
	app.touch_up(22)
	# Bestätigter Strich: Der zweite Finger zoomt nicht, der erste malt weiter.
	app.touch_down(24,camera.unproject_position(Vector3(app.recorder.last_pos.x,0.2,app.recorder.last_pos.y)))
	app.recorder.confirm()
	app.touch_down(25,tip+Vector2(-200,0))
	check(app.pointer == 24 and app.pinch_ids.is_empty(),"Nach der Probezeit übernimmt der zweite Finger nichts")
	app.touch_up(25)
	app.touch_up(24)
