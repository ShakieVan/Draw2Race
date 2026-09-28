extends SceneTree

var failures := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ",message)
	else:
		print("PASS: ",message)

func simulate(track: Circuit, plan: Array[Dictionary]) -> RaceVehicle:
	var v := RaceVehicle.new(track,plan)
	for tick in range(10800):
		v.step(1.0/60.0,false,float(tick+1)/60.0)
		if v.finish_time>=0:
			break
	return v

func _init() -> void:
	var track := Circuit.new()
	check(not track.valid_segment(track.at(0.25),track.at(0.75)),"Innenfläche kann nicht abgekürzt werden")
	check(track.valid_segment(track.at(0.0),track.at(0.01)),"Kurzes Fahrbahnsegment gültig")
	var r := LineRecorder.new(track)
	check(not r.begin(Vector2.ZERO,0.0),"Zeichnen beginnt nur am Start")
	r.begin(track.at(0.0),0.0)
	check(not r.sample(track.at(-0.03),0.1),"Rückwärtszeichnen wird abgewiesen")
	r = LineRecorder.new(track)
	r.begin(track.at(0.0),0.0)
	for i in range(1,482):
		r.sample(track.at(float(i)/240.0),float(i)*0.045 if i<=240 else 240.0*0.045+(i-240)*0.11)
	check(r.complete,"Zwei vollständig gezeichnete Runden erkannt")
	check(float(r.route[100].speed)>float(r.route[-30].speed),"Zweite Runde besitzt eigenes Tempoprofil")
	# Wegpunkte: neben der Fahrbahn zeichnen ist erlaubt, Tore müssen aber (mit Toleranz) passiert werden.
	var offroad := LineRecorder.new(track)
	offroad.begin(track.at(0.0),0.0)
	for i in range(1,241):
		offroad.sample(track.at(float(i)/240.0, 4.6),float(i)*0.05)
	check(offroad.gates_passed==LineRecorder.GATES_PER_LAP,"Knapp neben der Fahrbahn zählen die Wegpunkte")
	var wide := LineRecorder.new(track)
	wide.begin(track.at(0.0),0.0)
	for i in range(1,40):
		wide.sample(track.at(float(i)/240.0, 7.5),float(i)*0.05)
	check(not wide.active and wide.gates_passed==0 and wide.hint.begins_with("Wegpunkt"),"Weit am Tor vorbei stoppt die Zeichnung")
	var cut := LineRecorder.new(track)
	cut.begin(track.at(0.0),0.0)
	for i in range(1,11):
		cut.sample(track.at(float(i)/240.0),float(i)*0.05)
	var before := cut.progress
	cut.sample(Vector2(0.0,4.0),1.0)
	cut.sample(Vector2(0.0,-4.0),1.2)
	cut.sample(track.at(0.55),1.4)
	check(cut.progress<=before+0.001 and not cut.active,"Querfeldein über die Innenfläche bringt keinen Fortschritt")
	# Alle Strecken: KI fährt zwei vollständige Runden; auf der Acht wechselt die Zählung an der Kreuzung nicht den Ast.
	for track_id in ["azure","city","forest"]:
		var other := Circuit.load_track(track_id)
		var run := simulate(other, other.ai_route(2.0))
		check(run.finish_time>10.0 and run.finish_time<90.0,"Strecke %s: zwei Runden in %.1f s" % [track_id,run.finish_time])
	var resumed := LineRecorder.new(track)
	resumed.begin(track.at(0),0)
	resumed.sample(track.at(0.01),0.1)
	resumed.end()
	resumed.begin(resumed.last_pos,100)
	resumed.sample(track.at(0.02),100.1)
	check(float(resumed.route[-1].speed)>8.0,"Abgehobene Pause zählt nicht zum Zeichentempo")
	resumed.sample(resumed.last_pos,100.8)
	check(float(resumed.route[-1].speed)==5.0,"Aktives Verweilen setzt langsame Vorgabe")
	var plan := track.ai_route()
	var v := simulate(track,plan)
	print("BALANCE ai: time=",v.finish_time," progress=",v.progress," slip=",v.max_slip)
	check(v.finish_time>5.0 and v.finish_time<70.0,"Regler absolviert zwei Runden")
	var repeat := simulate(track,plan)
	check(v.pos.is_equal_approx(repeat.pos) and v.finish_time==repeat.finish_time,"Gleiche Eingabe reproduziert Fahrt")
	var safe: Array[Dictionary] = []
	var reckless: Array[Dictionary] = []
	for point in plan:
		var a := point.duplicate()
		a.speed = 10.0
		safe.append(a)
		var b := point.duplicate()
		b.speed = 29.0
		reckless.append(b)
	var slow := simulate(track,safe)
	var fast := simulate(track,reckless)
	print("BALANCE safe=",slow.finish_time," reckless=",fast.finish_time," slips=",slow.max_slip," / ",fast.max_slip)
	check(fast.max_slip>slow.max_slip*1.3,"Überzogene Kurven erzeugen mehr Reifenschlupf")
	var brake := RaceVehicle.new(track,safe)
	brake.velocity = Vector2(20,0)
	var start := brake.pos
	brake.step(1.0/60.0,false,1.0/60.0)
	check(brake.velocity.length()>18 and brake.pos.distance_to(start)>0.2,"Bremsen teleportiert weder Tempo noch Position")
	var idle := RaceVehicle.new(track,safe)
	idle.route[0].speed = 0.0
	var charge := idle.turbo
	for i in range(60): idle.step(1.0/60.0,false,float(i+1)/60.0)
	check(idle.turbo<=charge,"Keine Turboaufladung im Stillstand")
	check(brake.turbo>0.35,"Wirksames Bremsen lädt Turbo")
	var blocked := LineRecorder.new(track)
	blocked.begin(track.at(0),0)
	check(not blocked.sample(track.at(0.25),0.1),"Große Eingabesprünge ungültig")
	var averages: Array[float] = []
	for hz in [30,60,144]:
		var sampled := LineRecorder.new(track)
		sampled.begin(track.at(0),0)
		for i in range(1,hz*16+1):
			var t: float = float(i)/hz
			sampled.sample(track.at(t/8.0),t)
		var total := 0.0
		var distance := 0.0
		for i in range(1,sampled.route.size()):
			var ds: float = Vector2(sampled.route[i].p).distance_to(sampled.route[i-1].p)
			total += ds*float(sampled.route[i].speed)
			distance += ds
		averages.append(total/distance)
		check(sampled.complete,"Zeitgestempelte Geste bei %d Hz vollständig" % hz)
	check(absf(averages[0]-averages[2])<0.15,"Tempo vergleichbar bei 30 und 144 Eingabeproben pro Sekunde")
	check(fast.finish_time>slow.finish_time,"Überziehen kostet messbar Rundenzeit")
	# Unterbrechen und Wiederansetzen (Malzeit mit festen Zeitstempeln, 60 Abtastungen je Sekunde).
	var pen := LineRecorder.new(track)
	pen.begin(track.at(0.0),0.0)
	for i in range(1,19):
		pen.sample(track.at(i/900.0),i/60.0)
	pen.end()
	check(pen.discarded and pen.route.size()==1 and pen.progress==0.0,"Erster Strich unter 0,5 s wird verworfen")
	pen.begin(track.at(0.0),10.0)
	for i in range(1,121):
		pen.sample(track.at(i/900.0),10.0+i/60.0)
	pen.end()
	check(not pen.discarded and pen.route.size()>20 and pen.progress>0.1,"Nach 0,5 s Weitermalen bleibt die Linie")
	var open_from: int = pen.open_route_index()
	check(open_from>0 and open_from<pen.route.size()-1,"Werte älter als 1 s Malzeit sind fest, jüngere offen")
	var tip_len := pen.route.size()
	var tip_pos := pen.last_pos
	check(not pen.begin(track.at(10/900.0),50.0,1.0),"Im festen Bereich kann nicht angesetzt werden")
	var resume_at: Vector2 = track.at(100/900.0)
	check(pen.begin(resume_at,50.0,1.0),"Im offenen Bereich darf neu angesetzt werden")
	var base_speed := float(pen.route[pen.trial_base_index].speed)
	for i in range(1,13):
		pen.sample(track.at((100+i*3)/900.0,1.5),50.0+i/60.0)
	pen.end()
	check(pen.discarded and pen.route.size()==tip_len and pen.last_pos==tip_pos,"Kurzer neuer Ansatz verworfen, alte Linie unverändert")
	pen.begin(resume_at,60.0,1.0)
	var base_index := pen.trial_base_index
	for i in range(1,61):
		pen.sample(track.at((100+i*3)/900.0,1.5),60.0+i/60.0)
	pen.end()
	check(not pen.discarded and absf(pen.lateral(pen.route[-1].p,pen.last_phase)-1.5)<0.6,"Nach 0,5 s ersetzt der neue Ansatz den alten Rest")
	check(absf(float(pen.route[base_index+1].speed)-base_speed)<1.5,"Tempo startet am Ansatzpunkt geglättet (%.1f / %.1f)" % [float(pen.route[base_index+1].speed),base_speed])
	var gates_now := pen.gates_passed
	check(gates_now==int(floor(float(pen.route[-1].s)*LineRecorder.GATES_PER_LAP)),"Wegpunkte nach Rücksetzen korrekt gezählt")
	var finisher := LineRecorder.new(track)
	finisher.begin(track.at(0.0),0.0)
	var step := 0
	while not finisher.complete and step<5000:
		step += 1
		finisher.sample(track.at(step/450.0),step/60.0)
		if step%240==0 and not finisher.complete:
			finisher.end()
			finisher.begin(finisher.last_pos,step/60.0+5.0,1.0)
	check(finisher.complete and not finisher.trial,"Zieldurchfahrt schreibt sofort fest, auch mitten in einer Probe")
	# Tempo-Regler: Mitte = Grundwert 0,38, links halb, rechts doppelt; höherer Faktor = schnellere Linie.
	check(is_equal_approx(LineRecorder.tempo_from_setting(0.5),0.38) and is_equal_approx(LineRecorder.tempo_from_setting(0.0),0.19) and is_equal_approx(LineRecorder.tempo_from_setting(1.0),0.76),"Tempo-Regler: -50 % / Standard / +100 %")
	var calm := LineRecorder.new(track)
	var eager := LineRecorder.new(track)
	eager.tempo_factor = LineRecorder.tempo_from_setting(1.0)
	for rec in [calm,eager]:
		rec.begin(track.at(0.0),0.0)
		for i in range(1,31):
			rec.sample(track.at(i/600.0),i/60.0)
	check(float(eager.route[-1].speed)>float(calm.route[-1].speed)+2.0,"Höherer Tempo-Faktor ergibt bei gleicher Geste schnellere Vorgabe")
	# Update-Funktion: Versionsvergleich und strenge Release-Prüfung.
	check(Updater.compare_versions("0.10.0","0.9.9")>0 and Updater.compare_versions("1.2.3","1.2.3")==0,"Update: Versionen numerisch verglichen")
	var digest := "sha256:" + "ab".repeat(32)
	var good := {"draft": false, "prerelease": false, "tag_name": "v0.3.0", "body": "Neu",
		"assets": [{"name": "Draw2Race-0.3.0.apk", "size": 1234, "digest": digest,
			"browser_download_url": "https://github.com/ShakieVan/Draw2Race/releases/download/v0.3.0/Draw2Race-0.3.0.apk"}]}
	var parsed := Updater.parse(JSON.stringify(good))
	check(parsed.get("version") == "0.3.0" and parsed.get("sha256") == "ab".repeat(32),"Update: gültiges Release erkannt")
	var bad_url := good.duplicate(true)
	bad_url.assets[0].browser_download_url = "https://evil.example/Draw2Race-0.3.0.apk"
	var draft := good.duplicate(true)
	draft.draft = true
	var no_digest := good.duplicate(true)
	no_digest.assets[0].erase("digest")
	check(Updater.parse(JSON.stringify(bad_url)).is_empty() and Updater.parse(JSON.stringify(draft)).is_empty() and Updater.parse(JSON.stringify(no_digest)).is_empty(),"Update: fremde URL, Entwurf oder fehlende Prüfsumme abgelehnt")
	# Beta-Kanal: Vorabversion nur mit allow_beta; aus einer Liste gewinnt die höchste gültige Version.
	var pre := good.duplicate(true)
	pre.prerelease = true
	pre.tag_name = "v0.3.1"
	pre.assets[0].name = "Draw2Race-0.3.1.apk"
	pre.assets[0].browser_download_url = "https://github.com/ShakieVan/Draw2Race/releases/download/v0.3.1/Draw2Race-0.3.1.apk"
	var listing := JSON.stringify([good, pre, draft])
	check(Updater.parse(JSON.stringify(pre)).is_empty() and Updater.parse(JSON.stringify(pre), true).get("beta") == true,"Update: Vorabversion nur im Beta-Kanal")
	check(Updater.parse(listing, true).get("version") == "0.3.1" and Updater.parse(listing, false).get("version") == "0.3.0","Update: Beta-Liste wählt höchste Version")
	# Wetter: feste Bedingungen je Herausforderung; Nässe senkt Haftung und damit das Tempo der KI.
	var coast := Circuit.load_track("azure")
	check(coast.conditions_for(2).weather=="rain" and coast.conditions_for(0).time=="day","Strecke liefert Bedingungen je Herausforderung")
	var dry_route := coast.ai_route(3.0)
	RaceVehicle.weather_grip = 0.85
	var wet_route := coast.ai_route(3.0)
	var wet_car := simulate(coast,wet_route)
	RaceVehicle.weather_grip = 1.0
	var dry_car := simulate(coast,dry_route)
	check(float(wet_route[40].speed)<=float(dry_route[40].speed) and wet_car.finish_time>dry_car.finish_time,"Nässe macht Kurven langsamer (Physik und KI)")
	print("RESULT: ",checks-failures,"/",checks," passed")
	quit(1 if failures else 0)
