extends SceneTree
# Misst die Dauer der Laternenlicht-Berechnung (Atmosphere.bake_rain_lights) für eine Strecke. TRACK (Standard city).
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var id := OS.get_environment("TRACK") if OS.get_environment("TRACK") != "" else "city"
	var app: Node = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.store = ProgressStore.new("user://shots_%s.json" % Time.get_ticks_usec())
	var t0 := Time.get_ticks_msec()
	app.select_track(id)
	print("LAMP select_track ms=", Time.get_ticks_msec() - t0)
	var atm = app.world.atmosphere
	print("LAMP lamps=", atm.lamps.size(), " occluders=", atm.occluders.size())
	var area: Rect2 = app.track.bounds.grow(15.5)
	t0 = Time.get_ticks_msec()
	atm.bake_rain_lights(area)
	print("LAMP bake ms=", Time.get_ticks_msec() - t0, " area=", area)
	quit()
