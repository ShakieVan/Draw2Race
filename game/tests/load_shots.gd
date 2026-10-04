extends SceneTree
# Kontrollbilder zum Laden im Hintergrund: Zeichenansicht (Übersicht) je Strecke und Tageszeit, als PNG nach OUT (absoluter Ordner).
# MODE=async (Menüwahl, Welt im Hintergrund – wie im Spiel) oder sync (select_track am Stück). ONLY=city,arena …, TIMES=day,night.
# Vergleich vorher/nachher: dieselben Bilder mit dem alten und dem neuen Stand rendern und pixelweise vergleichen.
# MENU=1: stattdessen das Menü während des Ladens der ersten Strecke aus ONLY und danach (menu_laedt.png, menu_fertig.png).
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var out := OS.get_environment("OUT")
	var ids: Array = Array(OS.get_environment("ONLY").split(",")) if OS.get_environment("ONLY") != "" else ["azure", "city", "harbor", "arena", "serra"]
	var times: Array = Array(OS.get_environment("TIMES").split(",")) if OS.get_environment("TIMES") != "" else ["day", "night"]
	var async := OS.get_environment("MODE") != "sync"
	var path := "user://load_shots_%s.json" % Time.get_ticks_usec()
	var app: Node = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.store = ProgressStore.new(path)
	for i in range(5):
		await process_frame
	if OS.get_environment("MENU") == "1":
		# Menü während des Ladens („Strecke lädt …“) und danach.
		while not app.track_ready():
			await process_frame
		app.show_menu()
		app.pick_track(str(ids[0]))
		app.hud.menu()
		for i in range(3):
			await process_frame
		root.get_texture().get_image().save_png(out.path_join("menu_laedt.png"))
		while not app.track_ready():
			await process_frame
		for i in range(3):
			await process_frame
		root.get_texture().get_image().save_png(out.path_join("menu_fertig.png"))
		ids = []
	for id in ids:
		for t in times:
			app.debug_data()["override"] = {"time": t, "weather": "dry", "fog": 0}
			if async and app.has_method("pick_track"):
				app.show_menu()
				app.pick_track(id)
				while not app.track_ready():
					await process_frame
			else:
				app.select_track(id)
			app.start_drawing()
			app.world.marker.visible = false
			for k in range(40):
				await process_frame
			var img := root.get_texture().get_image()
			img.save_png(out.path_join("%s_%s.png" % [id, t]))
			print("BILD %s %s" % [id, t])
			app.show_menu()
	for f in [path, path + ".bak"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	quit()
