extends SceneTree

var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if ok: print("PASS: ",message)
	else:
		failures += 1
		printerr("FAIL: ",message)

func _init() -> void:
	var track := Circuit.new()
	check(track.surface_at(track.at(0)).kind=="asphalt","Fahrbahn als Asphalt erkannt")
	check(track.surface_at(track.at(0,4.5)).kind=="dirt","Unbefestigtes Bankett erkannt")
	check(track.surface_at(track.at(0.25,4.5)).kind=="mud","Sichtbare Matschzone erkannt")
	var marks := TyreTracks.new()
	for i in range(12): marks.sample(0,Vector2(i*0.2,15),0,10,0,0,track,i/60.0)
	check(marks.segments.is_empty(),"Sauberes Rollen auf Asphalt hinterlässt keinen Abrieb")
	for i in range(12): marks.sample(0,Vector2(2.2,15),0,0,12,1,track,i/60.0)
	check(marks.segments.is_empty(),"Stillstand erzeugt auch mit Bremse keine Spur")
	marks.clear()
	for i in range(12): marks.sample(0,Vector2(i*0.2,15),0,10,10,0,track,i/60.0)
	check(not marks.segments.is_empty() and marks.segments.all(func(s: Dictionary): return s.kind=="rubber"),"Starkes gerades Bremsen erzeugt dunklen Abrieb")
	marks.clear()
	for i in range(12): marks.sample(0,Vector2(i*0.2,15),0,10,0,0.6,track,i/60.0)
	check(not marks.segments.is_empty(),"Seitlicher Schlupf erzeugt Reifenspuren")
	marks.clear()
	for i in range(12): marks.sample(0,Vector2(i*0.2,19.5),0,10,0,0,track,i/60.0)
	check(not marks.segments.is_empty() and marks.segments.all(func(s: Dictionary): return s.kind=="soil"),"Schmutzspuren entstehen ohne Bremsen oder Rutschen")
	var count := marks.segments.size()
	for i in range(1,24): marks.sample(0,Vector2(2.2,19.5-i*0.2),0,10,0,0,track,1+i/60.0)
	var carried := marks.segments.slice(count).any(func(s: Dictionary): return s.kind=="soil" and s.height_b<0.21 and s.height_b>0.20)
	check(carried,"Reifen tragen Schmutz auf Asphalt weiter")
	for i in range(1,66): marks.sample(0,Vector2(2.2+i*0.2,14.9),0,10,0,0,track,2+i/60.0)
	check(marks.cars[0].all(func(w: Dictionary): return w.load==0.0),"Verschmutzung nimmt mit gefahrenem Weg vollständig ab")
	marks.clear()
	marks.sample(0,Vector2(0,15),0,10,12,1,track,0)
	marks.sample(0,Vector2(15,15),0,10,12,1,track,1)
	check(marks.segments.is_empty(),"Positionssprünge erzeugen keine langen Verbindungsstriche")
	for i in range(TyreTracks.MAX_SEGMENTS+200):
		marks.add_segment(Vector2.ZERO,Vector2.ONE,0.14,Color.BLACK,0.2,0.2,0,"rubber")
	check(marks.segments.size()<=TyreTracks.MAX_SEGMENTS,"Spurenbudget bleibt begrenzt")
	marks.prune(TyreTracks.LIFETIME+1)
	check(marks.segments.is_empty(),"Alte Spuren werden entfernt")
	marks.clear()
	check(marks.cars.is_empty(),"Neustart entfernt auch Reifenverschmutzung")
	print("RESULT: ",checks-failures,"/",checks," passed")
	quit(1 if failures else 0)
