extends Control

## Input adapter only: the canonical keyboard event also activates InputMap
## actions and reaches existing raw-key menus/dialogue. Never send both events.
signal key_requested(event: InputEventKey)
signal action_requested(event: InputEventAction)
@export var stick_radius: float = 56.0
@export_range(0.05, 0.5, 0.01) var stick_deadzone: float = 0.18
@export var mouse_testing: bool = true
const BUTTON_KEYS := {"A": KEY_K, "B": KEY_I, "C": KEY_C, "MENU": KEY_J, "SELECT": KEY_F10, "START": KEY_SPACE, "L": KEY_Q, "R": KEY_E}
const MOVEMENT := {KEY_A: &"move_left", KEY_D: &"move_right", KEY_W: &"move_forward", KEY_S: &"move_back"}
const STEERING := {KEY_A: &"ds_left", KEY_D: &"ds_right"}
var buttons: Dictionary = {}
var button_visuals: Dictionary = {}
var stick_zone := Rect2()
var stick_touch := -1
var stick_origin := Vector2.ZERO
var stick_vector := Vector2.ZERO
var touches: Dictionary = {}
var _held_keys: Dictionary = {}
var _stick_keys: Dictionary = {}
var _font: Font = ThemeDB.fallback_font

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	release_all()
	var w := size.x
	var h := size.y
	stick_zone = Rect2(Vector2(0, h * 0.24), Vector2(w * 0.51, h * 0.56))
	buttons = {
		"A": Rect2(Vector2(w * 0.80, h * 0.305), Vector2(w * 0.19, w * 0.19)),
		"B": Rect2(Vector2(w * 0.57, h * 0.49), Vector2(w * 0.19, w * 0.19)),
		"C": Rect2(Vector2(w * 0.53, maxf(h * 0.203, w * 48.0 / 390.0)), Vector2(w * 0.15, w * 0.15)),
		"MENU": Rect2(Vector2(w * 0.015, h - maxf(h * 0.13, w * 44.0 / 390.0)), Vector2(w * 0.19, maxf(h * 0.13, w * 44.0 / 390.0))),
		"SELECT": Rect2(Vector2(w * 0.56, h - maxf(h * 0.13, w * 44.0 / 390.0)), Vector2(w * 0.20, maxf(h * 0.13, w * 44.0 / 390.0))),
		"START": Rect2(Vector2(w * 0.78, h - maxf(h * 0.13, w * 44.0 / 390.0)), Vector2(w * 0.20, maxf(h * 0.13, w * 44.0 / 390.0))),
		"L": Rect2(Vector2.ZERO, Vector2(w * 0.29, maxf(h * 0.12, w * 44.0 / 390.0))),
		"R": Rect2(Vector2(w * 0.71, 0), Vector2(w * 0.29, maxf(h * 0.12, w * 44.0 / 390.0))),
	}
	button_visuals = buttons.duplicate()
	for label in ["L", "R", "MENU", "SELECT", "START"]:
		var hit: Rect2 = buttons[label]
		var height := w * 22.0 / 390.0
		button_visuals[label] = Rect2(hit.position + Vector2(0, (hit.size.y - height) * 0.5), Vector2(hit.size.x, height))
	queue_redraw()

func _process(_delta: float) -> void:
	if get_tree().paused:
		queue_redraw()
	# Forwarding the canonical key into the gameplay viewport can refresh its
	# digital action state. Reapply only the stick's analog strengths afterward.
	for key in _stick_keys:
		var strength := absf(stick_vector.x) if key in [KEY_A, KEY_D] else absf(stick_vector.y)
		Input.action_press(MOVEMENT[key], strength)
		if STEERING.has(key):
			Input.action_press(STEERING[key], strength)

func _emit_key(key: int, pressed: bool) -> void:
	if key == KEY_C:
		var action := InputEventAction.new()
		action.action = &"world_card_challenge"
		action.pressed = pressed
		action.strength = 1.0 if pressed else 0.0
		action_requested.emit(action)
		return
	if not pressed and MOVEMENT.has(key):
		Input.action_release(MOVEMENT[key])
		if STEERING.has(key):
			Input.action_release(STEERING[key])
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = pressed
	key_requested.emit(event)

func _hold(key: int) -> void:
	var count: int = _held_keys.get(key, 0)
	_held_keys[key] = count + 1
	if count == 0:
		_emit_key(key, true)

func _release(key: int) -> void:
	var count: int = _held_keys.get(key, 0)
	if count <= 1:
		_held_keys.erase(key)
		_emit_key(key, false)
	else:
		_held_keys[key] = count - 1

func touch_begin(index: int, point: Vector2) -> bool:
	if touches.has(index):
		return true
	for label in buttons:
		if buttons[label].has_point(point):
			touches[index] = label
			if BUTTON_KEYS.has(label):
				_hold(BUTTON_KEYS[label])
			queue_redraw()
			return true
	if stick_touch == -1 and stick_zone.has_point(point):
		stick_touch = index
		stick_origin = point
		stick_vector = Vector2.ZERO
		touches[index] = "stick"
		queue_redraw()
		return true
	return false

func touch_drag(index: int, point: Vector2) -> void:
	if index != stick_touch:
		return
	stick_vector = (point - stick_origin).limit_length(stick_radius) / stick_radius
	var strengths := {
		KEY_A: maxf(-stick_vector.x, 0), KEY_D: maxf(stick_vector.x, 0),
		KEY_W: maxf(-stick_vector.y, 0), KEY_S: maxf(stick_vector.y, 0),
	}
	for key in strengths:
		var strength: float = strengths[key]
		var active := strength > stick_deadzone
		if active and not _stick_keys.has(key):
			_stick_keys[key] = true
			_hold(key)
		elif not active and _stick_keys.has(key):
			_stick_keys.erase(key)
			_release(key)
		if active:
			Input.action_press(MOVEMENT[key], strength)
			if STEERING.has(key):
				Input.action_press(STEERING[key], strength)
	queue_redraw()

func touch_end(index: int) -> void:
	if not touches.has(index):
		return
	var label: String = touches[index]
	touches.erase(index)
	if index == stick_touch:
		for key in _stick_keys.keys():
			_release(key)
		_stick_keys.clear()
		stick_touch = -1
		stick_vector = Vector2.ZERO
	elif BUTTON_KEYS.has(label):
		_release(BUTTON_KEYS[label])
	queue_redraw()

func release_all() -> void:
	for key in _held_keys.keys():
		_emit_key(key, false)
	_held_keys.clear()
	_stick_keys.clear()
	touches.clear()
	stick_touch = -1
	stick_vector = Vector2.ZERO
	queue_redraw()

func _input(event: InputEvent) -> void:
	var point := Vector2.ZERO
	if event is InputEventScreenTouch:
		point = get_global_transform_with_canvas().affine_inverse() * event.position
		if event.pressed and not event.canceled:
			if touch_begin(event.index, point):
				get_viewport().set_input_as_handled()
		else:
			var owned := touches.has(event.index)
			touch_end(event.index)
			if owned:
				get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		point = get_global_transform_with_canvas().affine_inverse() * event.position
		touch_drag(event.index, point)
		if touches.has(event.index):
			get_viewport().set_input_as_handled()
	elif mouse_testing and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			point = get_global_transform_with_canvas().affine_inverse() * event.position
			if event.pressed:
				touch_begin(-2, point)
			else:
				touch_end(-2)
		elif event is InputEventMouseMotion:
			point = get_global_transform_with_canvas().affine_inverse() * event.position
			touch_drag(-2, point)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("c5c5c5"))
	for label in buttons:
		var rect: Rect2 = button_visuals[label]
		var pressed := touches.values().has(label)
		var color := Color("666666") if pressed else Color("343434")
		if label in ["A", "B", "C"]:
			draw_circle(rect.get_center(), rect.size.x * 0.5, Color.BLACK)
			draw_circle(rect.get_center(), rect.size.x * 0.44, color)
		else:
			draw_style_box(_button_style(color), rect)
		var text: String = label
		var font_size := 24 if label in ["A", "B"] else (20 if label == "C" else 13)
		var text_size := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		draw_string(_font, rect.get_center() + Vector2(-text_size.x * 0.5, font_size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
	var title := "TOUCH PLAYTEST"
	draw_string(_font, Vector2(size.x * 0.33, 20 * size.x / 390.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("292929"))
	if stick_touch != -1:
		draw_circle(stick_origin, stick_radius, Color(0.12, 0.12, 0.12, 0.6))
		draw_arc(stick_origin, stick_radius, 0, TAU, 48, Color.BLACK, 2, true)
		draw_circle(stick_origin + stick_vector * stick_radius, stick_radius * 0.4, Color("777777"))
	else:
		draw_string(_font, stick_zone.get_center() + Vector2(-45, 0), "TOUCH + DRAG", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("666666"))

func _button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(12)
	return style
