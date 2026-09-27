extends SceneTree

# Bildschirmfotos aller Bedingungen (Tageszeit, Wetter, Nebel) im Rennen, per Debug-Override.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var app: Node = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.store = ProgressStore.new("user://shots_%s.json" % Time.get_ticks_usec())
	var cases := [["azure","day","dry",0],["azure","night","rain",0],["city","dusk","dry",0],["city","night","rain",1],
		["forest","day","dry",0],["forest","day","dry",2],["forest","dusk","snow",1],["forest","night","dry",1]]
	for c in cases:
		app.select_track(c[0])
		app.debug_data()["override"] = {"time": c[1], "weather": c[2], "fog": c[3]}
		app.demo()
		for i in range(260):
			await process_frame
		root.get_texture().get_image().save_png("user://wx_%s_%s_%s_%d.png" % c)
		print("SHOT ", c)
	quit()
