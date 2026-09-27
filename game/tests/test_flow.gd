extends SceneTree

var failures := 0
var checks := 0
var app: Node

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
	var test_path := "user://test_progress_%s.json" % Time.get_ticks_usec()
	app.store = ProgressStore.new(test_path)
	app.run_record_path = test_path+".run"
	check(app.phase=="menu","Start im Hauptmenü")
	app.start_drawing()
	var start: Vector2 = app.track.at(0)
	var screen: Vector2 = app.camera.unproject_position(Vector3(start.x,0.20,start.y))
	check(app.world_point(screen).distance_to(start)<0.001,"Touchprojektion trifft die Fahrbahnebene")
	var touch := InputEventScreenTouch.new()
	touch.index = 2
	touch.position = screen
	touch.pressed = true
	app._unhandled_input(touch)
	check(app.pointer==2,"Erster Finger übernimmt Zeichnung")
	app.stroke_started -= 1.0   # zweiter Finger kommt deutlich später (kein Zoom-Griff)
	touch = touch.duplicate()
	touch.index = 3
	app._unhandled_input(touch)
	check(app.pointer==2,"Zweiter Finger kann Zeichnung nicht übernehmen")
	app.pause_game()
	var clock: float = app.draw_clock
	app._physics_process(3.0)
	check(app.draw_clock==clock and app.pointer==-99,"Pause friert Eingabezeit ein und gibt Finger frei")
	app.resume_game()
	check(not app.paused and app.phase=="draw","Zeichnen nach Pause fortsetzbar")
	# Handkamera: Ziehen verschiebt, zwei Finger zoomen, Doppeltipp zeigt alles; Malen nur am Linienende.
	app.start_drawing()
	var widest: float = app.overview_size()
	check(is_equal_approx(app.view_zoom,widest),"Zeichnen beginnt mit der ganzen Strecke")
	var free_spot: Vector2 = root.get_visible_rect().size*0.5+Vector2(0,40)
	app.touch_down(7,free_spot)
	check(app.pointer==-99 and app.pan_index==7,"Freie Stelle greift die Kamera statt zu malen")
	app.touch_down(8,free_spot+Vector2(200,0))
	check(app.pinch_ids.size()==2,"Zweiter Finger startet Zwei-Finger-Zoom")
	app.touch_move(8,free_spot+Vector2(420,0))
	check(app.view_zoom<widest*0.6,"Finger auseinander zoomt hinein")
	app.touch_up(8)
	check(app.pan_index==7,"Nach dem Zoom verschiebt der verbleibende Finger")
	var before_pan: Vector3 = app.view_focus
	app.touch_move(7,free_spot+Vector2(-150,0))
	check(app.view_focus.x>before_pan.x,"Ziehen nach links verschiebt die Kamera nach rechts")
	app.touch_up(7)
	app.touch_down(9,free_spot)
	app.touch_up(9)
	app.touch_down(9,free_spot)
	app.touch_up(9)
	check(is_equal_approx(app.view_zoom,widest),"Doppeltipp zeigt wieder die ganze Strecke")
	var begin_at: Vector2 = app.track.at(0.0)
	var start_screen: Vector2 = app.camera.unproject_position(Vector3(begin_at.x,0.20,begin_at.y))
	app.touch_down(10,start_screen)
	check(app.pointer==10,"Am Startpunkt aufsetzen malt")
	app.touch_down(11,start_screen+Vector2(250,0))
	check(app.pointer==-99 and app.pinch_ids.size()==2 and app.recorder.route.size()<=1,"Zwei Finger fast gleichzeitig: Zoom statt Malbeginn")
	app.touch_up(11)
	app.touch_up(10)
	for challenge in range(3):
		app.stage = challenge
		app.start_drawing()
		app.recorder.route = app.track.ai_route(1.0)
		app.begin_race()
		for tick in range(10800):
			app._physics_process(1.0/60.0)
			if app.phase=="result": break
		check(app.phase=="result","Herausforderung %d erreicht Ergebnis mit %d Fahrzeugen" % [challenge+1,app.vehicles.size()])
		print("RACE ",challenge," player=",app.vehicles[0].finish_time," gold=",app.store.data.gold)
		var frozen: float = app.vehicles[0].finish_time
		for tick in range(6000): app._physics_process(1.0/60.0)
		check(app.vehicles.all(func(v: RaceVehicle): return v.finish_time>0),"Alle Rivalen erhalten eine Zielzeit")
		check(app.vehicles[0].finish_time==frozen,"Zielzeit bleibt nach Zieleinlauf konstant")
	var store := app.store as ProgressStore
	store.result("azure",0,0,24.0,true)
	var count: int = store.data.gold.size()
	store.result("azure",0,0,25.0,true)
	check(store.data.gold.size()==count,"Gold wird je Herausforderung nur einmal vergeben")
	var loaded := ProgressStore.new(test_path)
	check(loaded.data.gold.size()==count,"Fortschritt überlebt erneutes Laden")
	loaded.result("azure",0,0,23.0,true)
	check(loaded.data.gold.size()==count and loaded.gold_count("azure")<=3,"Nach dem Neuladen wird Gold nicht doppelt gezählt")
	for k in range(14):
		loaded.result("city",1,k%5,30.0+float((k*7)%13),false)
	var board: Array = loaded.board("city",1)
	var sorted_ok := true
	for k in range(1,board.size()):
		sorted_ok = sorted_ok and float(board[k-1].time) <= float(board[k].time)
	check(board.size()==10 and sorted_ok and float(loaded.best_time("city",1).time)==30.0,"Bestenliste: höchstens 10 Einträge, aufsteigend sortiert")
	var legacy := ProgressStore.new(test_path+".v1")
	legacy.data.gold = [0.0, 0.0, 1.0, 1]
	legacy.migrate()
	check(legacy.data.gold == ["azure/0","azure/1"],"Alter Spielstand (Version 1) wird ohne Doppelgold übernommen")
	var f := FileAccess.open(test_path,FileAccess.WRITE)
	f.store_string("{corrupt")
	f.close()
	loaded = ProgressStore.new(test_path)
	check(loaded.data.gold.size()==count,"Defekter Spielstand fällt auf Sicherung zurück")
	app.demo()
	app._physics_process(1.0)
	app.pause_game()
	var timer: float = app.countdown
	var charge: float = app.vehicles[0].turbo
	app._physics_process(10.0)
	check(app.countdown==timer and app.vehicles[0].turbo==charge,"Countdown und Turbo stehen in Pause still")
	app.start_drawing()
	check(app.vehicles.is_empty() and app.recorder.route.is_empty(),"Neustart stellt definierten Ausgangszustand her")
	app.stage = 2
	app.demo()
	for i in range(4): app.vehicles[i].finish_time = [20.0,22.0004,22.0001,22.0001][i]
	var rows: Array = app.sorted_results()
	check(rows[1].index==2 and rows[2].index==3 and rows[3].index==1,"Ergebnisse nach ungerundeten Zeiten sortiert")
	check(rows[1].rank==rows[2].rank and rows[3].rank==4,"Exakte Gleichstände erhalten dieselbe Platzierung")
	# Geisterauto: Nach einer Rekordfahrt (Stufe 0 oben gefahren) fährt beim nächsten Rennen der Geist mit.
	app.stage = 0
	app.start_drawing()
	check(FileAccess.file_exists(app.ghost_path()),"Geisterfahrt nach Rekord gespeichert")
	app.recorder.route = app.track.ai_route(1.0)
	app.begin_race()
	check(app.ghost != null and is_instance_valid(app.ghost_model),"Geisterauto fährt mit")
	var rivals_before: int = app.vehicles.size()
	for tick in range(10800):
		app._physics_process(1.0/60.0)
		if app.phase=="result": break
	for tick in range(1200): app._physics_process(1.0/60.0)
	check(app.vehicles.size()==rivals_before and app.ghost.finish_time > 0.0,"Geist zählt nicht als Rivale und erreicht das Ziel (%.2f s)" % app.ghost.finish_time)
	DirAccess.remove_absolute(app.ghost_path())
	for suffix in ["",".bak",".tmp",".run"]:
		if FileAccess.file_exists(test_path+suffix): DirAccess.remove_absolute(test_path+suffix)
	app.queue_free()
	await process_frame
	print("RESULT: ",checks-failures,"/",checks," passed")
	quit(1 if failures else 0)
