extends Control
## Read-only projection of existing services. No clock, weather or wind simulation.
const FONT = preload("res://assets/fonts/BOF_Font_Refined.fnt")
const CATALOG = preload("res://data/bof4/environment/all_environment_conditions.tres")
var host: Node
var state := {}
var portrait := false
var readable_font: FontFile = FONT.duplicate()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents = true
	# Enable bitmap font sizing on this view only, not the shared font resource.
	readable_font.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED

func read_state(shell_state: Dictionary) -> Dictionary:
	var result := {"spot":shell_state.get("spot",""),"location":shell_state.get("location","No location"),"preview":shell_state.get("preview"),"weather":"N/A","period":"N/A","wind":"N/A","current":"N/A","tide":"N/A"}
	if not is_instance_valid(host) or not is_instance_valid(host.game): return result
	var fishing: Node = host.game.get_node_or_null("Game/Fishing")
	if fishing == null: return result
	var environment: Node = fishing.fishing_environment_service
	if is_instance_valid(environment):
		for id in environment.get_active_condition_ids():
			var condition = CATALOG.get_condition_by_id(StringName(id))
			if condition == null: continue
			if condition.stacking_group == &"weather":
				result.weather = condition.display_name
				result.weather_id = condition.condition_id
			if condition.stacking_group == &"time": result.period = condition.display_name
		var tide: Dictionary = environment.get_debug_snapshot().get("tide",{})
		if not tide.is_empty(): result.tide = tide.get("phase_name","N/A")
	var current: Node = fishing.fishing_current_service
	if is_instance_valid(current) and current.get_spot() != null:
		var sample: Vector3 = current.sample_current_velocity(fishing.player.global_position)
		if is_instance_valid(fishing.caster.active_bait): sample = current.sample_current_velocity(fishing.caster.active_bait.global_position)
		result.current = "%s %.2f m/s" % [compass(Vector2(sample.x,sample.z)),sample.length()]
	return result

static func compass(direction: Vector2) -> String:
	if direction.length_squared() < 0.000001: return "Still"
	var index := posmod(int(round(atan2(direction.x,-direction.y)/ (PI/4.0))),8)
	return ["N","NE","E","SE","S","SW","W","NW"][index]

func refresh(shell_state: Dictionary) -> void:
	state = read_state(shell_state)
	queue_redraw()

func cells() -> Array[Rect2]:
	var result: Array[Rect2] = []
	if portrait:
		var width := size.x-16
		result.append(Rect2(8,8,width*.57,42))
		result.append(Rect2(8+width*.57,8,width*.43,42))
		for i in range(3): result.append(Rect2(8+width*i/3,56,width/3,40))
	else:
		var weather_width := readable_font.get_string_size(str(state.get("weather","N/A")),HORIZONTAL_ALIGNMENT_LEFT,-1,14).x+27
		var widths := [112.0,maxf(60,weather_width),56.0,56.0,85.0,56.0]
		var remaining: float = size.x-16
		for width in widths: remaining -= width
		var weights := [.55,.10,.05,.05,.15,.10]
		var x := 8.0
		for i in range(6):
			var width: float = widths[i]+maxf(0,remaining)*weights[i]
			result.append(Rect2(x,6,width,size.y-12))
			x += width
	return result

func line(text: String, box: Rect2, y: float, fs := 16) -> void:
	draw_string(readable_font,box.position+Vector2(3,y),text,HORIZONTAL_ALIGNMENT_LEFT,maxf(1,box.size.x-6),fs,Color("35202d"))

func icon(index: int, center: Vector2) -> void:
	var ink := Color("873548")
	match index:
		1:
			if state.get("weather_id",&"") in [&"rain",&"tempest"]:
				draw_circle(center+Vector2(-4,-2),4,ink)
				draw_circle(center+Vector2(2,-4),5,ink)
				draw_circle(center+Vector2(7,0),3,ink)
				for x in [-5,0,5]: draw_line(center+Vector2(x,5),center+Vector2(x-2,9),ink,1)
			else:
				draw_circle(center,5,ink)
				for i in range(8):
					var ray := Vector2.from_angle(i*TAU/8)
					draw_line(center+ray*7,center+ray*10,ink,1)
		2:
			draw_line(center+Vector2(-7,9),center+Vector2(-7,-9),ink,2)
			draw_colored_polygon(PackedVector2Array([center+Vector2(-6,-8),center+Vector2(9,-4),center+Vector2(-6,1)]),ink)
		3,4:
			for row in range(2):
				var points := PackedVector2Array()
				for i in range(17): points.append(center+Vector2(i-8,sin(i*.7)*2+row*6-3))
				draw_polyline(points,ink,1)

func _draw() -> void:
	if state.is_empty(): return
	if not portrait:
		_draw_landscape()
		return
	var boxes := cells()
	for i in range(1,5): draw_line(boxes[i].position,boxes[i].position+Vector2(0,boxes[i].size.y),Color("c99d69"),1)
	if portrait: draw_line(Vector2(8,52),Vector2(size.x-8,52),Color("c99d69"),1)
	var location := boxes[0]
	var image: Texture2D = state.preview
	if image != null:
		draw_texture_rect(image,Rect2(location.position,Vector2(36,40)),false)
		location.position.x += 40
		location.size.x -= 40
	line(str(state.spot),location,18,18 if location.size.x >= 130 else 16)
	line(str(state.location),location,38,16)
	for i in range(1,5):
		var box := boxes[i]
		icon(i,box.position+Vector2(11,12))
		var text_box := Rect2(box.position+Vector2(25,0),box.size-Vector2(25,0))
		var title: String = ["","Weather","Wind","Current","Tide"][i]
		match i:
			1:
				line(str(state.weather),text_box,18,16)
				line("Day/time N/A",box,38,14)
			2,3,4:
				var value := str(state.get(["","","wind","current","tide"][i],"N/A"))
				if i == 3: value = value.replace(" m/s","m/s")
				if i == 4:
					value = "None" if value == "No Tide" else value.trim_suffix(" Tide")
					if box.size.x < 90: value = {"Incoming":"In","Outgoing":"Out"}.get(value,value)
				line(title if text_box.size.x >= 65 else title.left(1),text_box,18,14)
				line(value,box,38,14)

func _draw_landscape() -> void:
	var boxes := cells()
	for i in range(1,6): draw_line(boxes[i].position,boxes[i].position+Vector2(0,boxes[i].size.y),Color("c99d69"),1)
	var location := boxes[0]
	if state.preview != null:
		draw_texture_rect(state.preview,Rect2(location.position,Vector2(28,28)),false)
		location.position.x += 32
		location.size.x -= 32
	var caption := "%s / %s" % [state.spot,state.location]
	if readable_font.get_string_size(caption,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x > location.size.x-6:
		# Controlled narrow fallback: location alone uses two readable lines.
		# Environmental values remain one row, not a scaled-down old header.
		line(str(state.spot).replace(" Spot "," "),location,12,14)
		line(str(state.location),location,27,14)
	else: line(caption,location,19,14)
	for i in range(1,6):
		var box := boxes[i]
		var center := box.position+Vector2(10,14)
		if i == 2:
			draw_circle(center,7,Color("873548"),false,1)
			draw_line(center,center+Vector2(0,-5),Color("873548"),1)
			draw_line(center,center+Vector2(4,0),Color("873548"),1)
		else: icon({1:1,3:2,4:3,5:4}[i],center)
		var value := str(state.get({1:"weather",2:"clock",3:"wind",4:"current",5:"tide"}[i],"N/A"))
		if i == 4: value = value.replace(" m/s","m/s")
		if i == 5:
			value = "None" if value == "No Tide" else value.trim_suffix(" Tide")
			if box.size.x < 100: value = {"Incoming":"In","Outgoing":"Out"}.get(value,value)
			if box.size.x < 75 and value == "None": value = "No"
		var text_box := Rect2(box.position+Vector2(21,0),box.size-Vector2(21,0))
		# Explicit units stay on normal widths; narrow rows retain direction and
		# numeric speed beside the current icon, rather than clipping the value.
		if i == 4 and readable_font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x > text_box.size.x-6:
			value = value.replace("m/s","")
		line(value,text_box,19,14)
