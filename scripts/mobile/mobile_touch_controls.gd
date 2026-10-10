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
const ART := {"A":preload("res://assets/ui/seaside_shell/a.png"),"B":preload("res://assets/ui/seaside_shell/b.png"),"C":preload("res://assets/ui/seaside_shell/c.png"),"L":preload("res://assets/ui/seaside_shell/l.png"),"R":preload("res://assets/ui/seaside_shell/r.png")}
const LANDSCAPE_SHOULDERS := {"L":preload("res://assets/ui/seaside_shell/landscape_l.png"),"R":preload("res://assets/ui/seaside_shell/landscape_r.png")}
var landscape := false
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
	if landscape:
		var layout := preload("res://scripts/ui/seaside_shell_layout.gd").mobile(Rect2(Vector2.ZERO,size))
		var right: Rect2 = layout.right
		stick_zone = layout.left
		var r := maxf(64,right.size.x*.4)
		var small := maxf(44,r*.7)
		buttons = {"A":Rect2(right.position+Vector2(right.size.x*.5,right.size.y*.12),Vector2(r,r)),"B":Rect2(right.position+Vector2(right.size.x*.06,right.size.y*.24),Vector2(small,small)),"C":Rect2(right.position+Vector2(right.size.x*.12,right.size.y*.02),Vector2(small,small)),"L":Rect2(6,6,w*.12,maxf(44,h*.13)),"R":Rect2(w*.88,6,w*.11,maxf(44,h*.13))}

	else:
		stick_zone = Rect2(0,h*.20,w*.49,h*.53)
		var a := minf(w*.21,maxf(44,h*.30))
		var b := minf(w*.18,maxf(44,h*.26))
		var c := minf(w*.16,maxf(44,h*.22))
		var cy := maxf(52,h*.22)
		buttons = {"A":Rect2(w*.75,h*.41,a,a),"B":Rect2(w*.54,maxf(cy+c+4,h*.47),b,b),"C":Rect2(w*(.65 if h>=340 else .54),cy,c,c),"L":Rect2(w*.05,h*.025,w*.23,maxf(44,h*.14)),"R":Rect2(w*.72,h*.025,w*.23,maxf(44,h*.14))}
	button_visuals = buttons.duplicate()
	if not landscape:
		for label in ["L","R"]:
			var hit: Rect2 = buttons[label]
			var visual_height := minf(hit.size.y,hit.size.x*60.0/153.0)
			button_visuals[label] = Rect2(hit.position+Vector2(0,(hit.size.y-visual_height)*.5),Vector2(hit.size.x,visual_height))
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
	for label in buttons:
		var rect: Rect2 = button_visuals[label]
		var texture: Texture2D = LANDSCAPE_SHOULDERS[label] if landscape and label in ["L","R"] else ART[label]
		draw_texture_rect(texture,rect,false,Color(.75,.75,.75) if touches.values().has(label) else Color.WHITE)
	var center := stick_origin if stick_touch != -1 else stick_zone.get_center()
	var radius := minf(stick_radius,stick_zone.size.x*.39)
	draw_circle(center,radius+4,Color("35202d"))
	draw_circle(center,radius,Color("2c2d36"))
	draw_arc(center,radius*.83,0,TAU,48,Color("dca76a"),3,true)
	draw_circle(center+stick_vector*radius,radius*.44,Color("ad966e"))
