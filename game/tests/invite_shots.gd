extends SceneTree
# Kontrollbilder „Mitspieler einladen“ (Beta 1.0.2) im Handyformat: Gastgeber-Lobby mit dem Knopf, das Panel im WLAN (eigenes
# Spiel-WLAN anbieten), mit offenem Spiel-WLAN (WLAN-QR und Spiel-QR), nach dem ersten Seitenaufruf (② leuchtet), mit Mitspieler
# (beide Haken), ohne WLAN, bei verweigerter Erlaubnis, dazu der WLAN-Bildschirm mit „QR-Code scannen“ und der Meldung zu einem fremden
# Code sowie die Einladungsseite als Text (user://invite_page.html, im Browser ansehen).
# Netzstatus und Spiel-WLAN sind vorgegeben (Android-Ersatz, NetAndroid.wifi_stub, QrJoin.scan_stub); Testports 24830–24833.
# Aufruf (20:9):  tools/godot_run.ps1 -Script res://tests/invite_shots.gd -Resolution 1600x720 -Timeout 120
# Bilder: user://invite_<name>.png; der Spielstand der Aufnahme wird am Ende gelöscht.
const STORE := "user://invite_shots_store.json"
const OVERRIDES := {"game_port": 24830, "discovery_port": 24831, "beacon_port": 24832, "apk_port": 24833, "probe_local": true,
	"use_broadcast": false, "use_binding": false, "log_path": ""}
const TRACKS := ["azure", "city", "forest", "harbor", "serra", "fair", "quarry", "arena", "kids"]
const WIFI := {"android": true, "networks": [{"transport": "wifi", "handle": "100", "iface": "wlan0", "addresses": ["192.168.178.24/24"],
	"gateway": "192.168.178.1", "default": true, "internet": true}], "bound": {"transport": "wifi", "handle": "100"},
	"interfaces": [{"name": "wlan0", "address": "192.168.178.24", "prefix": 24}], "wifi_gateway": "192.168.178.1"}
const NO_WIFI := {"android": true, "networks": [{"transport": "mobile", "addresses": ["10.64.12.7/30"]}], "interfaces": [{"name": "rmnet_data0", "address": "10.64.12.7"}]}
var app: Node
var others: Array = []

func _initialize() -> void:
	call_deferred("run")

func frames(n: int) -> void:
	for i in range(n):
		await process_frame

func until(done: Callable, timeout_ms := 5000) -> void:
	var end := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < end and not done.call():
		await process_frame

func shot(name: String) -> void:
	if panel() != null:
		panel().refresh(true)        # das Panel zieht sonst nur alle 0,25 s nach
	await frames(4)
	var path := "user://invite_%s.png" % name
	root.get_texture().get_image().save_png(path)
	print("SHOT ", ProjectSettings.globalize_path(path))

func panel() -> InvitePanel:
	for n in app.hud.content.find_children("Invite", "", true, false):
		if not n.is_queued_for_deletion():
			return n as InvitePanel
	return null

func with_wifi(spot: bool) -> Dictionary:
	# Netzstatus des Gastgebers: Heim-WLAN, mit offenem Spiel-WLAN zusätzlich dessen Schnittstelle (wie Samsung swlan0).
	var s: Dictionary = WIFI.duplicate(true)
	if spot:
		s.interfaces.append({"name": "swlan0", "address": "10.94.17.1", "prefix": 24})
	return s

func run() -> void:
	NetLobby.overrides = OVERRIDES.merged({"forced_status": WIFI})
	NetAndroid.wifi_stub = {"ssid": "AndroidShare_7k2m", "password": "q9w3e7r2t5y8u4i", "security": "wpa2", "address": "10.94.17.1", "sdk": 34}
	QrJoin.scan_stub = {"available": true, "results": []}
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await frames(2)
	app.store = ProgressStore.new(STORE)
	app.store.data["ghost"] = false
	app.store.set_player_name("Shakie")
	app.select_track("azure")
	app.car_choice = 0
	app.show_menu()
	# Mitspieler: WLAN-Bildschirm mit „QR-Code scannen“, dann ein fremder Code
	app.open_wlan()
	await frames(2)
	await shot("wlan_scan")
	app.lobby.qr.handle("https://example.com/hallo")
	app.hud.lobby_ui.refresh()
	await shot("wlan_fremd")
	app.lobby.qr.handle(NetAndroid.wifi_qr_text("AndroidShare_7k2m", "q9w3e7r2t5y8u4i"))
	app.hud.lobby_ui.refresh()
	await shot("wlan_verbinde")
	app.lobby.qr.release()
	app.lobby.qr._say("")
	# Gastgeber
	app.net_host()
	await frames(2)
	await shot("lobby")
	(app.hud.lobby_ui.invite_button as Button).pressed.emit()
	await frames(2)
	await shot("panel_wlan")
	app.lobby.forced_status = with_wifi(true)
	app.lobby.invite.open_wifi()
	app.lobby.refresh_status()
	app.lobby.invite.refresh(true)
	await shot("panel_offen")
	# Einladungsseite als Datei (so, wie der Browser sie bekommt)
	var page := NetApk.page_html({"name": "Shakie", "version": NetProtocol.game_version(), "address": "10.94.17.1", "game_port": 24680, "apk": true,
		"size": 312638820, "prepare": ""}, "10.94.17.1", NetApk.PORT, true)
	var f := FileAccess.open("user://invite_page.html", FileAccess.WRITE)
	f.store_string(page)
	f.close()
	print("PAGE ", ProjectSettings.globalize_path("user://invite_page.html"))
	# Jemand ruft die Seite auf → ② leuchtet; dann tritt Ben bei → beide Haken
	var raw := StreamPeerTCP.new()
	raw.connect_to_host("127.0.0.1", 24833)
	var end := Time.get_ticks_msec() + 2000
	while raw.get_status() == StreamPeerTCP.STATUS_CONNECTING and Time.get_ticks_msec() < end:
		raw.poll()
		OS.delay_msec(5)
	raw.put_data("GET / HTTP/1.1\r\nHost: 10.94.17.1:24683\r\nConnection: close\r\n\r\n".to_ascii_buffer())
	await until(func(): return int(app.lobby.transfer.stats().pages) > 0, 3000)
	raw.disconnect_from_host()
	app.lobby.invite.refresh(true)
	await shot("panel_seite")
	NetLobby.overrides = OVERRIDES
	var ben := NetLobby.new()
	ben.tracks = TRACKS.duplicate()
	root.add_child(ben)
	ben.enter("Ben", 2)
	others.append(ben)
	ben.join("127.0.0.1", 24830)
	await until(func(): return app.lobby.client_count() == 1)
	app.lobby.invite.refresh(true)
	await shot("panel_haken")
	# Spiel-WLAN zu, ohne WLAN; dann Erlaubnis verweigert
	app.lobby.invite.close_wifi()
	app.lobby.forced_status = NO_WIFI
	app.lobby.refresh_status()
	app.lobby.invite.refresh(true)
	await shot("panel_ohne_wlan")
	NetAndroid.wifi_stub.granted = false
	app.lobby.invite.open_wifi()
	await shot("panel_erlaubnis")
	NetAndroid.wifi_stub.granted = true
	app.lobby.invite.dismiss_problem()
	var p := panel()
	if p != null:
		p.close_panel()
	await frames(2)
	app.lobby.forced_status = with_wifi(true)
	app.lobby.invite.open_wifi()
	app.lobby.refresh_status()
	app.hud.lobby_ui.refresh()
	await shot("lobby_spielwlan")
	for lb in others:
		if is_instance_valid(lb):
			lb.exit()
			lb.free()
	app.leave_wlan()
	await frames(2)
	for suffix in ["", ".bak", ".tmp", ".run"]:
		if FileAccess.file_exists(STORE + suffix):
			DirAccess.remove_absolute(STORE + suffix)
	quit(0)
