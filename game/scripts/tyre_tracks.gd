class_name TyreTracks
extends RefCounted

# Presentation only: reads vehicle motion, never changes simulation state.
const MAX_SEGMENTS := 4096
const LIFETIME := 45.0
const SAMPLE_DISTANCE := 0.18
const WHEELS := [Vector2(0.63,0.5),Vector2(0.63,-0.5),Vector2(-0.63,0.5),Vector2(-0.63,-0.5)]
var segments: Array[Dictionary] = []
var cars: Dictionary = {}

func clear() -> void:
	segments.clear()
	cars.clear()

func sample(id: int, pos: Vector2, heading: float, speed: float, brake: float, slip: float, track: Circuit, time: float) -> void:
	var forward := Vector2.from_angle(heading)
	var side := forward.orthogonal()
	if not cars.has(id):
		cars[id] = []
		for wheel in WHEELS:
			var p: Vector2 = pos+forward*wheel.x+side*wheel.y
			cars[id].append({"previous":p,"anchor":p,"load":0.0,"dirt_color":Color("a88c61")})
	for i in range(4):
		var wheel: Vector2 = WHEELS[i]
		var p := pos+forward*wheel.x+side*wheel.y
		var state: Dictionary = cars[id][i]
		var distance: float = p.distance_to(state.previous)
		state.previous = p
		# Stationary tyres and teleports must never draw connecting streaks.
		if speed<0.4 or distance>3.0:
			state.anchor = p
			continue
		var surface := track.surface_at(p)
		var dirty: bool = surface.kind in ["dirt","mud","gravel"]
		if dirty and distance>0.001:
			state.load = minf(1.0,float(state.load)+distance*2.0)
			state.dirt_color = Color("71543c") if surface.kind=="mud" else (Color("c2a57a") if surface.kind=="gravel" else Color("a88c61"))
		else:
			state.load = maxf(0.0,float(state.load)-distance/8.0)
		if p.distance_to(state.anchor)<SAMPLE_DISTANCE:
			continue
		var a: Vector2 = state.anchor
		state.anchor = p
		var start_surface := track.surface_at(a)
		var rubber := maxf(clampf((slip-0.14)/0.45,0,1),clampf((brake-4.0)/8.0,0,1))
		if dirty or float(state.load)>0.02:
			var color: Color = state.dirt_color
			color.a = 0.65 if dirty else float(state.load)*0.65
			add_segment(a,p,0.24 if surface.kind=="mud" else 0.20,color,start_surface.height,surface.height,time,"soil")
		if surface.kind=="asphalt" and rubber>0.03 and speed>2.0:
			add_segment(a,p,0.14,Color(0.065,0.085,0.09,rubber*0.68),start_surface.height,surface.height,time,"rubber")

func add_segment(a: Vector2, b: Vector2, width: float, color: Color, height_a: float, height_b: float, time: float, kind: String) -> void:
	segments.append({"a":a,"b":b,"width":width,"color":color,"height_a":height_a,"height_b":height_b,"time":time,"kind":kind})
	if segments.size()>MAX_SEGMENTS:
		segments = segments.slice(128)

func prune(time: float) -> void:
	while not segments.is_empty() and time-float(segments[0].time)>=LIFETIME:
		segments.pop_front()
