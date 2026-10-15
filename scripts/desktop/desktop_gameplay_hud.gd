extends Control
## Desktop-only presentation over the gameplay image. All data comes from the
## existing shell adapter and Exploration eligibility signal.

const ICON_SHEET: Texture2D = preload("res://assets/ui/desktop_hud_v1/reference_icons.png")
const PLAQUE_SHEET: Texture2D = preload("res://assets/ui/desktop_hud_v1/caption_plaque.png")
const RAIN: Texture2D = preload("res://assets/ui/desktop_hud_v1/weather_rain.png")
const TEMPEST: Texture2D = preload("res://assets/ui/desktop_hud_v1/weather_tempest.png")
const FONT: Font = preload("res://assets/fonts/BOF_Font_Refined.fnt")
const PIXEL_SHADER: Shader = preload("res://assets/shaders/desktop_hud_pixel.gdshader")
const ICON_RECTS := [
	Rect2(16, 242, 343, 242), Rect2(369, 257, 222, 221),
	Rect2(612, 238, 209, 240), Rect2(848, 163, 385, 389),
	Rect2(1241, 245, 321, 237), Rect2(1581, 287, 280, 195),
	Rect2(1879, 259, 278, 223)
]
enum HudMode { MINIMAL, COMPACT, WIDE }
const WIDE_AT := 1100.0
const COMPACT_AT := 680.0
const MODE_MARGIN := 12.0
const SLOT_NAMES := ["Location", "Weather", "Clock", "Fishing", "Wind", "Current", "Tide"]

var host: Node
var state: Dictionary = {}
var _exploration: Node
var _eligible := false
var _slots: Array[Control] = []
var _icons: Array[TextureRect] = []
var _plaques: Array[Panel] = []
var _wind_arrow: Polygon2D
var _heading_background: Panel
var _labels: Array[Label] = []
var _heading: Label
var _weather_textures: Dictionary = {}
var _hud_mode := -1

func _atlas(source: Texture2D, region: Rect2) -> AtlasTexture:
	var result := AtlasTexture.new()
	result.atlas = source
	result.region = region
	return result

func _pixel_material() -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.shader = PIXEL_SHADER
	return result

func _ready() -> void:
	name = "DesktopGameplayHud"
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Keep the extracted artwork as a temporary icon set, but do not stretch
	# its dark caption strip. Use a fixed-height parchment caption instead.
	_weather_textures = {
		"clear": _atlas(ICON_SHEET, ICON_RECTS[1]),
		"rain": _atlas(RAIN, Rect2(288, 207, 827, 740)),
		"tempest": _atlas(TEMPEST, Rect2(127, 99, 1145, 935))
	}
	for index in range(7):
		var slot := Control.new()
		slot.name = ["Location", "Weather", "Clock", "Fishing", "Wind", "Current", "Tide"][index]
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(slot)
		_slots.append(slot)
		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.texture = _atlas(ICON_SHEET, ICON_RECTS[index])
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.material = _pixel_material()
		slot.add_child(icon)
		_icons.append(icon)
		var plaque := Panel.new()
		plaque.name = "Plaque"
		var parchment := StyleBoxFlat.new()
		parchment.bg_color = Color("ead7ae")
		parchment.border_color = Color("634a5a")
		parchment.set_border_width_all(2)
		parchment.set_corner_radius_all(0)
		plaque.add_theme_stylebox_override("panel", parchment)
		plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(plaque)
		_plaques.append(plaque)
		var label := Label.new()
		label.name = "Value"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_override("font", FONT)
		label.add_theme_color_override("font_color", Color("563047"))
		label.add_theme_color_override("font_outline_color", Color.TRANSPARENT)
		label.add_theme_constant_override("outline_size", 0)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.clip_text = true
		slot.add_child(label)
		_labels.append(label)
	_plaques[3].hide()
	# The wind direction is explicit even with the temporary windsock icon.
	_wind_arrow = Polygon2D.new()
	_wind_arrow.name = "DirectionArrow"
	_wind_arrow.polygon = PackedVector2Array([
		Vector2(0,-9), Vector2(5,-1), Vector2(2,-1),
		Vector2(2,8), Vector2(-2,8), Vector2(-2,-1), Vector2(-5,-1)
	])
	_wind_arrow.color = Color("563047")
	_slots[4].add_child(_wind_arrow)
	_heading_background = Panel.new()
	_heading_background.name = "HeadingBackground"
	var heading_style := StyleBoxFlat.new()
	heading_style.bg_color = Color("ead7ae")
	heading_style.border_color = Color("634a5a")
	heading_style.set_border_width_all(1)
	_heading_background.add_theme_stylebox_override("panel", heading_style)
	_heading_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slots[3].add_child(_heading_background)
	_heading = Label.new()
	_heading.name = "HeadingAndAction"
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_heading.add_theme_font_override("font", FONT)
	_heading.add_theme_font_size_override("font_size", 13)
	_heading.add_theme_color_override("font_color", Color("563047"))
	_heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slots[3].add_child(_heading)
	resized.connect(_layout_slots)
	_layout_slots()
	set_process(true)

func bind_game(game: Node) -> void:
	if is_instance_valid(_exploration):
		var callback := Callable(self, "_on_eligibility_changed")
		if _exploration.cast_availability_changed.is_connected(callback):
			_exploration.cast_availability_changed.disconnect(callback)
	_exploration = game.get_node_or_null("Game/Exploration") if is_instance_valid(game) else null
	if is_instance_valid(_exploration):
		_exploration.cast_availability_changed.connect(_on_eligibility_changed)
		_on_eligibility_changed(bool(_exploration.get("cast_available")))
	else:
		_on_eligibility_changed(false)

func _on_eligibility_changed(available: bool) -> void:
	_eligible = available
	var material := _icons[3].material as ShaderMaterial
	if material != null:
		material.set_shader_parameter("grayscale", not available)
	_update_heading()

func refresh(next: Dictionary) -> void:
	state = next
	_update_wind_arrow(str(next.get("wind", "N/A")))
	var weather_id := str(next.get("weather_id", "calm"))
	_icons[1].texture = _weather_textures.get(weather_id, _weather_textures["clear"])
	_update_captions()
	_update_heading()

func _caption_value(index: int) -> String:
	var clock := get_node_or_null("/root/GameClock")
	var clock_text := str(state.get("clock_short", "N/A"))
	if clock != null:
		clock_text = "%02d:%02d" % [clock.get_hour(), clock.get_minute()]
	var value := str(state.get(["spot", "weather", "clock_short", "", "wind", "current", "tide"][index], "N/A"))
	if index == 2: value = clock_text
	if _hud_mode == HudMode.COMPACT:
		match index:
			0: value = value.replace(" Spot ", " ")
			4, 5: value = value.replace(" m/s", "m/s")
			6: value = "None" if value == "No Tide" else value.trim_suffix(" Tide")
	return value

func _fit_caption(label: Label, preferred: int, minimum: int) -> void:
	var font_size := preferred
	while font_size > minimum and FONT.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > label.size.x:
		font_size -= 1
	label.add_theme_font_size_override("font_size", font_size)
	# A deliberate ellipsis is the last resort for unexpected future authored
	# names. Normal catalogue values fit in full at the selected bitmap size.
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

func _update_captions() -> void:
	if _hud_mode == HudMode.MINIMAL:
		return
	for index in [0, 1, 2, 4, 5, 6]:
		_labels[index].text = _caption_value(index)
		_fit_caption(_labels[index], 12 if _hud_mode == HudMode.WIDE else 10, 8)

func _update_wind_arrow(value: String) -> void:
	if _wind_arrow == null:
		return
	var direction: String = value.get_slice(" ", 0).to_upper()
	var compass_points := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	var index: int = compass_points.find(direction)
	_wind_arrow.visible = index >= 0 and _hud_mode == HudMode.WIDE
	if index >= 0:
		_wind_arrow.rotation = float(index) * TAU / 8.0

func _process(_delta: float) -> void:
	_update_heading()

func _update_heading() -> void:
	if _heading == null:
		return
	var degrees := 0
	if is_instance_valid(host) and is_instance_valid(host.game):
		var camera_rig: Node3D = host.game.get_node_or_null("CameraRig") as Node3D
		if camera_rig != null:
			# Match the original compass needle's -yaw convention.
			degrees = posmod(roundi(-rad_to_deg(camera_rig.rotation.y)), 360)
	_heading.text = ("K FISH  " if _eligible else "") + "%03d°" % degrees

func _mode_for_width(width: float) -> int:
	# The 12px retention band prevents repeated mode changes while a dock edge
	# is being dragged around a breakpoint.
	if _hud_mode == HudMode.WIDE and width >= WIDE_AT - MODE_MARGIN:
		return HudMode.WIDE
	if _hud_mode == HudMode.MINIMAL and width < COMPACT_AT + MODE_MARGIN:
		return HudMode.MINIMAL
	if _hud_mode == HudMode.COMPACT:
		if width >= WIDE_AT + MODE_MARGIN: return HudMode.WIDE
		if width < COMPACT_AT - MODE_MARGIN: return HudMode.MINIMAL
		return HudMode.COMPACT
	if width >= WIDE_AT: return HudMode.WIDE
	if width >= COMPACT_AT: return HudMode.COMPACT
	return HudMode.MINIMAL

func _layout_slots() -> void:
	if _slots.size() != 7 or size.x <= 0.0:
		return
	_hud_mode = _mode_for_width(size.x)
	var side_width := 142.0
	var center_width := 112.0
	var gap := 14.0
	var side_icon := 64.0
	var center_icon := 90.0
	var caption_y := 66.0
	var caption_height := 30.0
	var stacked := false
	match _hud_mode:
		HudMode.COMPACT:
			side_width = 84.0; center_width = 94.0; gap = 9.0
			side_icon = 46.0; center_icon = 72.0
			caption_y = 49.0; caption_height = 24.0
		HudMode.MINIMAL:
			# Odd-width dock viewports keep the centered medallion and every
			# sibling on whole local pixels.
			side_width = 41.0; center_width = 65.0; gap = 10.0
			if size.x < 400.0:
				side_width = 30.0; center_width = 48.0; gap = 7.0
			if size.x < 300.0:
				side_width = 24.0; center_width = 40.0; gap = 5.0
			stacked = size.x < 214.0
			side_icon = side_width; center_icon = center_width
	var bounds: Array[Rect2] = []
	bounds.resize(7)
	var center_left := (size.x - center_width) * 0.5
	if stacked:
		# Extreme-width fallback: three icons, centered medallion, three icons.
		# Reading order remains Location through Tide without clipping a row.
		var trio_width := side_width * 3.0 + gap * 2.0
		var trio_left := (size.x - trio_width) * 0.5
		for index in range(3):
			bounds[index] = Rect2(trio_left + float(index) * (side_width + gap), 0, side_width, side_width)
			bounds[index + 4] = Rect2(trio_left + float(index) * (side_width + gap),
				side_width + center_width + gap * 2.0, side_width, side_width)
		bounds[3] = Rect2(center_left, side_width + gap, center_width, center_width)
	else:
		for index in range(3):
			bounds[index] = Rect2(center_left - gap - side_width - float(2 - index) * (side_width + gap),
				0, side_width, side_width)
			bounds[index + 4] = Rect2(center_left + center_width + gap + float(index) * (side_width + gap),
				0, side_width, side_width)
		bounds[3] = Rect2(center_left, 0, center_width, center_width)
	var show_captions := _hud_mode != HudMode.MINIMAL
	for index in range(7):
		var box: Rect2 = bounds[index]
		var slot := _slots[index]
		slot.position = box.position
		slot.size = box.size
		if index == 3:
			_icons[index].position = Vector2((center_width - center_icon) * 0.5, 0)
			_icons[index].size = Vector2.ONE * center_icon
			_heading_background.position = Vector2(0, center_icon + 3.0)
			_heading_background.size = Vector2(center_width, 22.0 if _hud_mode == HudMode.WIDE else 20.0)
			_heading.position = _heading_background.position + Vector2(3, 1)
			_heading.size = _heading_background.size - Vector2(6, 2)
			_heading.add_theme_font_size_override("font_size", 10 if _hud_mode == HudMode.WIDE else 8)
			_heading_background.visible = show_captions
			_heading.visible = show_captions
			_plaques[index].hide()
			_labels[index].hide()
			continue
		_icons[index].position = Vector2((side_width - side_icon) * 0.5, 0)
		_icons[index].size = Vector2.ONE * side_icon
		_plaques[index].position = Vector2(0, caption_y)
		_plaques[index].size = Vector2(side_width, caption_height)
		_labels[index].position = Vector2(5, caption_y + 2)
		_labels[index].size = Vector2(side_width - 10, caption_height - 4)
		_plaques[index].visible = show_captions
		_labels[index].visible = show_captions
	_wind_arrow.position = Vector2(14, caption_y + caption_height * 0.5)
	if _hud_mode == HudMode.WIDE:
		_labels[4].position.x += 18
		_labels[4].size.x -= 18
	_update_captions()
	_update_wind_arrow(str(state.get("wind", "N/A")))
