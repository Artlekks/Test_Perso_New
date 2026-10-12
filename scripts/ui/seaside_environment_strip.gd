extends Control
## Shared read-only environmental header (desktop and mobile).
## Location | Day/Time | Weather | Wind | Current | Tide on landscape/desktop.
const FONT = preload("res://assets/fonts/BOF_Font_Refined.fnt")
const CATALOG = preload("res://data/bof4/environment/all_environment_conditions.tres")
var host: Node
var state := {}
var portrait := false
var desktop_compact := false
var desktop_mode := false
var readable_font: FontFile = FONT.duplicate()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents = true
	# Enable bitmap font sizing on this view only, not the shared font resource.
	readable_font.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED

func read_state(shell_state: Dictionary) -> Dictionary:
	var result := {"spot":shell_state.get("spot",""),"location":shell_state.get("location","No location"),"preview":shell_state.get("preview"),"weather":"N/A","period":"N/A","clock":"N/A","clock_short":"N/A","wind":"N/A","current":"N/A","tide":"N/A"}
	var clock: Node = get_node_or_null("/root/GameClock")
	if clock != null and clock.has_method("get_clock_text"):
		result.clock = str(clock.call("get_clock_text"))
		result.clock_short = str(clock.call("get_short_clock_text"))
		result.period = result.clock_short
	var wind_service: Node = get_node_or_null("/root/GameWind")
	if wind_service != null and wind_service.has_method("get_snapshot"):
		var wind_data: Dictionary = wind_service.call("get_snapshot") as Dictionary
		if bool(wind_data.get("available", false)):
			result.wind = str(wind_data.get("display", "N/A"))
			result.wind_short = str(wind_data.get("compact", "N/A"))
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
			if condition.stacking_group == &"time": result.time_condition = condition.display_name
	# During an active fishing session, use the live fishing services.
	# Outside fishing, preview the actual current location without calling
	# set_spot() or overwriting lure/encounter physics.
	var current: Node = fishing.fishing_current_service
	var active_spot: FishingSpotData = null
	if is_instance_valid(current):
		active_spot = current.get_spot()
	var tide_service: Node = null
	var services: Node = get_node_or_null("/root/FishingSessionServices")
	if services != null and services.has_method("get_fishing_tide_service"):
		tide_service = services.call("get_fishing_tide_service") as Node
	var location_spot: FishingSpotData = null
	if active_spot == null:
		var locations: Node = get_node_or_null("/root/WorldLocations")
		if locations != null and locations.current_location != null:
			location_spot = locations.current_location.fishing_spot
	var relevant_spot: FishingSpotData = active_spot if active_spot != null else location_spot
	if is_instance_valid(tide_service):
		var tide_data: Dictionary = {}
		if active_spot != null:
			tide_data = tide_service.get_snapshot()
		elif tide_service.has_method("get_preview_snapshot"):
			tide_data = tide_service.get_preview_snapshot(location_spot)
		if bool(tide_data.get("active", false)):
			result.tide = str(tide_data.get("phase_name", "N/A"))
		elif relevant_spot != null:
			result.tide = "No Tide"
	if is_instance_valid(current) and relevant_spot != null:
		var flat := Vector2.ZERO
		if active_spot != null:
			var sample: Vector3 = current.sample_current_velocity(fishing.player.global_position)
			if is_instance_valid(fishing.caster.active_bait):
				sample = current.sample_current_velocity(fishing.caster.active_bait.global_position)
			flat = Vector2(sample.x, sample.z)
		else:
			flat = current.sample_spot_at_uv(location_spot)
		result.current = "%s %.2f m/s" % [compass(flat), flat.length()]
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
	if desktop_compact:
		var widths := [size.x*.50-8,size.x*.25,size.x*.25-8]
		var x := 8.0
		for width in widths:
			result.append(Rect2(x,6,width,30)); x += width
		for i in range(3): result.append(Rect2(8+(size.x-16)*i/3,46,(size.x-16)/3,30))
	elif portrait:
		var width := size.x-16
		result.append(Rect2(8,8,width*.57,42))
		result.append(Rect2(8+width*.57,8,width*.43,42))
		for i in range(3): result.append(Rect2(8+width*i/3,56,width/3,40))
	else:
		var weather_width := readable_font.get_string_size(str(state.get("weather","N/A")),HORIZONTAL_ALIGNMENT_LEFT,-1,14).x+27
		var widths := [112.0,90.0,maxf(60,weather_width),56.0,85.0,56.0]
		var remaining: float = size.x-16
		for width in widths: remaining -= width
		var weights := [.50,.18,.10,.05,.12,.05]
		var x := 8.0
		var shrink: float = minf(1.0, (size.x - 16.0) / maxf(1.0, (size.x - 16.0) - remaining))
		for i in range(6):
			var width: float = widths[i] * shrink + maxf(0,remaining)*weights[i]
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
	if desktop_mode:
		_draw_desktop()
		return
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
				line(str(state.get("clock", "N/A")),box,38,14)
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
		if i == 1:
			draw_arc(center,7,0,TAU,20,Color("873548"),1.0)
			draw_line(center,center+Vector2(0,-5),Color("873548"),1)
			draw_line(center,center+Vector2(4,0),Color("873548"),1)
		else: icon({2:1,3:2,4:3,5:4}[i],center)
		var value := str(state.get({1:"clock_short",2:"weather",3:"wind",4:"current",5:"tide"}[i],"N/A"))
		if i == 3 and box.size.x < 84.0:
			value = str(state.get("wind_short", value))
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

func _desktop_caption(message: String, area: Rect2, font_size := 14, secondary := false) -> void:
	var ink := Color("563047") if not secondary else Color("76604e")
	var font: Font = ThemeDB.fallback_font
	if font == null: return
	draw_string(font, area.position, message, HORIZONTAL_ALIGNMENT_LEFT, maxf(1.0, area.size.x), font_size, ink)

func _desktop_item(index: int, area: Rect2, is_compact := false, icons_only := false) -> void:
	var ink := Color("563047")
	var h := area.size.y
	var fs := 12 if is_compact else 14
	if index == 0:
		var place := str(state.get("spot", "Ocean Spot 2"))
		var zone := str(state.get("location", "Beach"))
		if icons_only:
			# Even a 320px dock retains two readable location lines.
			place = place.replace(" Spot ", " ")
			_desktop_caption(place, Rect2(area.position + Vector2(3, 15), Vector2(area.size.x - 4, 14)), 11)
			_desktop_caption(zone, Rect2(area.position + Vector2(3, 29), Vector2(area.size.x - 4, 12)), 10, true)
			return
		if h > 32.0:
			_desktop_caption(place, Rect2(area.position + Vector2(4, 17), Vector2(area.size.x - 8, 16)), fs)
			_desktop_caption(zone, Rect2(area.position + Vector2(4, 34), Vector2(area.size.x - 8, 14)), fs - 1, true)
		else:
			_desktop_caption("%s / %s" % [place, zone], Rect2(area.position + Vector2(4, 23), Vector2(area.size.x - 8, 16)), fs)
		return
	var center := area.position + Vector2(area.size.x * 0.5 if icons_only else 15.0, h * 0.5)
	if index == 1:
		draw_arc(center, 6, 0, TAU, 20, ink, 1.3)
		draw_line(center, center + Vector2(0, -4), ink, 1.3)
		draw_line(center, center + Vector2(3, 0), ink, 1.3)
	else:
		icon({2:1, 3:2, 4:3, 5:4}[index], center)
	if icons_only and index != 1:
		# On minimum docks other details become icons, but time remains readable.
		return
	var key: String = {1:"clock_short", 2:"weather", 3:"wind", 4:"current", 5:"tide"}[index]
	var value := str(state.get(key,"N/A"))
	if index == 1 and area.size.x >= 140.0 and not is_compact:
		value = str(state.get("clock", value))
	if index == 3 and area.size.x < 114.0:
		value = str(state.get("wind_short", value))
	if index == 4:
		value = value.replace(" m/s", "m/s")
		if area.size.x < 114.0: value = value.replace("m/s", "")
	if index == 5:
		value = "None" if value == "No Tide" else value.trim_suffix(" Tide")
		if area.size.x < 90.0: value = {"Incoming":"In", "Outgoing":"Out"}.get(value, value)
	if icons_only and index == 1:
		_desktop_caption(value, Rect2(area.position + Vector2(2, h * 0.5 + 14), Vector2(maxf(1.0, area.size.x - 4), 14)), 10)
		return
	_desktop_caption(value, Rect2(area.position + Vector2(29, h * 0.5 + 5), Vector2(maxf(1.0, area.size.x - 34), 20)), fs)

func _draw_desktop() -> void:
	# Separate informational CELLS, not ornamental frames. Header is a single
	# visual band on wide desktop, two data rows only on narrow docks.
	var ink_line := Color("aa9274")
	var area_width := maxf(1.0, size.x - 16.0)
	if desktop_compact:
		var icon_only: bool = size.x < 345.0
		var one := [0.50, 0.25, 0.25]
		var x := 8.0
		var first_height := size.y * 0.56
		for i in range(3):
			var first_width: float = area_width * float(one[i])
			if i > 0: draw_line(Vector2(x, 5), Vector2(x, first_height - 5), ink_line, 1.0)
			_desktop_item(i, Rect2(x, 0, first_width, first_height), true, icon_only)
			x += first_width
		draw_line(Vector2(8, first_height), Vector2(size.x - 8, first_height), ink_line, 1.0)
		x = 8.0
		for i in range(3, 6):
			var second_width: float = area_width / 3.0
			if i > 3: draw_line(Vector2(x, first_height + 5), Vector2(x, size.y - 5), ink_line, 1.0)
			_desktop_item(i, Rect2(x, first_height, second_width, size.y - first_height), true, icon_only)
			x += second_width
		return
	var weights := [0.26, 0.18, 0.125, 0.125, 0.17, 0.14]
	var start_x := 8.0
	for i in range(6):
		var width: float = area_width * weights[i]
		if i > 0:
			draw_line(Vector2(start_x, 7), Vector2(start_x, size.y - 7), ink_line, 1.0)
		_desktop_item(i, Rect2(start_x, 0, width, size.y))
		start_x += width
