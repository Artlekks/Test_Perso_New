extends Control
## Window presentation and gameplay activity are deliberately independent.
enum Mode { ACTIVE, PASSIVE }
enum WindowState { FLOATING, DOCK_LEFT, DOCK_RIGHT, COLLAPSED }
const SURFACE := Vector2i(640,864)
const CHROME_HEIGHT := 68
const KEYBOARD_HEIGHT := 60
@export_file("*.tscn") var gameplay_scene := "res://actors/FishingTestScene_V2.tscn"
@export var active_scale := 0.75
@export var min_dock_width := 320
@export var default_dock_width := 480
@export var max_dock_width := 900
@export var collapsed_width := 80
var mode := Mode.ACTIVE
var window_state := WindowState.FLOATING
var dock_width := 480
var _expanded_state := WindowState.FLOATING
var _expanded_rect := Rect2i()
var _floating_rect := Rect2i()
var _pending_float_restore := false
var _platform_poll := 0.0
var _request_pending := false
var _dock_drag := false
var _drag_x := 0
var _drag_width := 0
var game: Node
var gameplay_viewport: SubViewport
var image: TextureRect
var status: Label
var toggle: Button
var keyboard_strip: Control
var divider: ColorRect
var buttons: Dictionary = {}
var platform = preload("res://scripts/desktop/companion_window_platform.gd").new()
var passive: Node
var _forwarding := false
var _bound_layers: Dictionary = {}
var docked: bool:
	get: return effective_window_state() in [WindowState.DOCK_LEFT,WindowState.DOCK_RIGHT]
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_window().content_scale_size = Vector2i.ZERO
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_window().unresizable = false
	get_window().min_size = Vector2i(min_dock_width,400)
	dock_width = clampi(default_dock_width,min_dock_width,max_dock_width)
	gameplay_viewport = SubViewport.new()
	gameplay_viewport.name = "GameplayViewport"
	gameplay_viewport.set_meta("input_hint_device","keyboard")
	gameplay_viewport.size = SURFACE
	gameplay_viewport.own_world_3d = true
	gameplay_viewport.world_2d = World2D.new()
	gameplay_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(gameplay_viewport)
	image = TextureRect.new()
	image.texture = gameplay_viewport.get_texture()
	image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(image)
	for label in ["Float","Dock Left","Dock Right","Collapse","Mode","X"]:
		var button := Button.new()
		button.text = label
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size",14)
		buttons[label] = button
		add_child(button)
	buttons.Float.pressed.connect(func(): set_window_state(WindowState.FLOATING))
	buttons["Dock Left"].pressed.connect(func(): set_window_state(WindowState.DOCK_LEFT))
	buttons["Dock Right"].pressed.connect(func(): set_window_state(WindowState.DOCK_RIGHT))
	buttons.Collapse.pressed.connect(toggle_collapse)
	buttons.Mode.pressed.connect(cycle_mode)
	buttons.X.pressed.connect(func(): get_tree().quit())
	buttons["Dock Left"].disabled = not platform.supported()
	buttons["Dock Right"].disabled = not platform.supported()
	toggle = buttons.Mode
	status = Label.new()
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.add_theme_font_size_override("font_size",13)
	add_child(status)
	keyboard_strip = preload("res://scripts/desktop/companion_keyboard_strip.gd").new()
	keyboard_strip.host = self
	add_child(keyboard_strip)
	passive = preload("res://scripts/gameplay/passive_fishing_controller.gd").new()
	passive.name = "PassiveFishingController"
	passive.host = self
	add_child(passive)
	passive.cancelled.connect(func(_reason): mode = Mode.ACTIVE; _layout())
	passive.opportunity_ready.connect(_layout)
	divider = ColorRect.new()
	divider.color = Color(0.55,0.55,0.55,0.8)
	divider.mouse_default_cursor_shape = Control.CURSOR_HSIZE
	divider.gui_input.connect(_divider_input)
	add_child(divider)
	resized.connect(_on_resize)
	get_window().close_requested.connect(func(): get_tree().quit())
	get_window().focus_exited.connect(func(): _dock_drag = false)
	get_tree().node_added.connect(_node_added)
	var usable := DisplayServer.screen_get_usable_rect(get_window().current_screen)
	if not usable.has_area(): usable = Rect2i(Vector2i.ZERO,Vector2i(1280,1024))
	get_window().size = Vector2i(Vector2(SURFACE)*active_scale)+Vector2i(0,CHROME_HEIGHT+KEYBOARD_HEIGHT)
	get_window().position = usable.position+Vector2i(maxi(0,usable.size.x-get_window().size.x),maxi(0,(usable.size.y-get_window().size.y)/2))
	_layout()
	load_gameplay_scene(gameplay_scene)
func get_gameplay_scene() -> Node: return game
func load_gameplay_scene(path: String) -> Error:
	var packed = load(path)
	if not packed is PackedScene: return ERR_CANT_OPEN
	_replace_game.call_deferred(packed)
	return OK
func _replace_game(packed: PackedScene) -> void:
	passive.cancel("travel",true)
	if is_instance_valid(game): game.free()
	game = packed.instantiate()
	preload("res://scripts/ui/canonical_game_surface.gd").prepare(game)
	gameplay_viewport.add_child(game)
	_bind_session_layers()
func _node_added(node: Node) -> void:
	if node is CanvasLayer: _bind_session_layers.call_deferred()
func _bind_session_layers() -> void:
	var session := get_node_or_null("/root/FishingSessionServices")
	if session == null: return
	for layer in session.find_children("*","CanvasLayer",true,false):
		if not _bound_layers.has(layer.get_instance_id()): _bound_layers[layer.get_instance_id()] = {"node":weakref(layer),"parent":weakref(layer.get_parent())}
		if layer.get_parent() != gameplay_viewport: layer.reparent(gameplay_viewport)
func cycle_mode() -> void: set_mode(Mode.PASSIVE if mode == Mode.ACTIVE else Mode.ACTIVE)
func set_mode(next: int) -> void:
	# Invalid legacy COLLAPSED mode values recover to Active without geometry.
	next = next if next in [Mode.ACTIVE,Mode.PASSIVE] else Mode.ACTIVE
	if next == mode: return
	if next == Mode.PASSIVE:
		if not passive.begin(): _layout(); return
	else: passive.activate()
	mode = next
	_layout()
func effective_window_state() -> int:
	return _expanded_state if window_state == WindowState.COLLAPSED else window_state
func set_docked(value: bool) -> void: set_window_state(WindowState.DOCK_RIGHT if value else WindowState.FLOATING)
func set_window_state(next: int) -> void:
	if next == WindowState.COLLAPSED: toggle_collapse(); return
	if next not in [WindowState.FLOATING,WindowState.DOCK_LEFT,WindowState.DOCK_RIGHT]: next = WindowState.FLOATING
	if next != WindowState.FLOATING and not platform.supported(): return
	if window_state == next: return
	if window_state == WindowState.FLOATING: _floating_rect = Rect2i(get_window().position,get_window().size)
	window_state = next
	_expanded_state = next
	get_window().min_size = Vector2i(min_dock_width,400)
	get_window().borderless = docked
	if docked: _apply_dock_size()
	else:
		_pending_float_restore = true
		var error: Error = platform.request(false,get_window(),"right")
		if error != OK or platform.helper_pid <= 0 or not OS.is_process_running(platform.helper_pid): _restore_floating()
	_layout()
func toggle_collapse() -> void:
	if window_state == WindowState.COLLAPSED:
		window_state = _expanded_state
		get_window().min_size = Vector2i(min_dock_width,400)
		if docked: _apply_dock_size()
		else:
			get_window().size = _expanded_rect.size
			get_window().position = _expanded_rect.position
	else:
		_expanded_state = window_state
		_expanded_rect = Rect2i(get_window().position,get_window().size)
		window_state = WindowState.COLLAPSED
		get_window().min_size = Vector2i(collapsed_width,180)
		get_window().size = Vector2i(collapsed_width,200)
		if docked: _request_pending = true
	_layout()
func set_dock_width(value: int) -> void:
	dock_width = clampi(value,min_dock_width,max_dock_width)
	if docked and window_state != WindowState.COLLAPSED: _apply_dock_size()
func _desired_dock_size() -> Vector2i:
	var width := collapsed_width if window_state == WindowState.COLLAPSED else dock_width
	var height := 200 if window_state == WindowState.COLLAPSED else roundi(float(width)*SURFACE.y/SURFACE.x)+CHROME_HEIGHT+KEYBOARD_HEIGHT
	return Vector2i(width,mini(height,DisplayServer.screen_get_size(get_window().current_screen).y))
func _apply_dock_size() -> void:
	get_window().size = _desired_dock_size()
	_request_pending = true
func _restore_floating() -> void:
	_pending_float_restore = false
	if _floating_rect.has_area():
		get_window().size = _floating_rect.size
		get_window().position = _floating_rect.position
	_layout()
func _on_resize() -> void:
	_layout()
	if docked: _request_pending = true
func _divider_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dock_drag = event.pressed
		_drag_x = DisplayServer.mouse_get_position().x
		_drag_width = dock_width
func _process(delta: float) -> void:
	if _dock_drag:
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): _dock_drag = false
		else:
			var dx := DisplayServer.mouse_get_position().x-_drag_x
			set_dock_width(_drag_width + (dx if effective_window_state() == WindowState.DOCK_LEFT else -dx))
	_platform_poll += delta
	if _platform_poll < 0.05: return
	_platform_poll = 0
	if _request_pending:
		_request_pending = false
		# Native acknowledgements can resize the client asynchronously. They must
		# never overwrite the user's desired width with an older acknowledged size.
		var error: Error = platform.request(docked,get_window(),"left" if effective_window_state() == WindowState.DOCK_LEFT else "right",_desired_dock_size() if docked else Vector2i.ZERO)
		if error != OK: status.text = error_string(error); set_window_state(WindowState.FLOATING)
	var state: Dictionary = platform.read_status()
	if _pending_float_restore and state.get("sequence",-1) == platform.sequence and not state.get("registered",true): _restore_floating()
	if docked and not str(state.get("error","")).is_empty():
		status.text = str(state.error)
		set_window_state(WindowState.FLOATING)
	_layout()
func _layout() -> void:
	if image == null or keyboard_strip == null: return
	var collapsed := window_state == WindowState.COLLAPSED
	image.position = Vector2(0,CHROME_HEIGHT)
	image.size = Vector2(get_window().size)-Vector2(0,CHROME_HEIGHT+KEYBOARD_HEIGHT)
	image.visible = not collapsed
	keyboard_strip.position = Vector2(4,get_window().size.y-KEYBOARD_HEIGHT)
	keyboard_strip.size = Vector2(get_window().size.x-8,KEYBOARD_HEIGHT)
	keyboard_strip.visible = not collapsed
	var labels := ["Float","Dock Left","Dock Right","Collapse"]
	for i in range(labels.size()):
		var button: Button = buttons[labels[i]]
		button.visible = not collapsed or labels[i] == "Collapse"
		button.position = Vector2(i*float(get_window().size.x)/4,0) if not collapsed else Vector2.ZERO
		button.size = Vector2(float(get_window().size.x)/4,32) if not collapsed else Vector2(get_window().size.x,40)
	buttons.Collapse.text = "Expand" if collapsed else "Collapse"
	buttons.Mode.text = "Active" if mode == Mode.ACTIVE else "Passive"
	buttons.Mode.tooltip_text = passive.reason if passive != null else ""
	buttons.Mode.position = Vector2(0,40 if collapsed else 34)
	buttons.Mode.size = Vector2(get_window().size.x-28,28)
	buttons.X.position = Vector2(get_window().size.x-28,40 if collapsed else 34)
	buttons.X.size = Vector2(28,28)
	status.position = Vector2(3,80 if collapsed else 50)
	status.visible = collapsed
	status.text = "!\nFISH" if passive != null and passive.is_ready() else ("Focus" if mode == Mode.PASSIVE else "Active")
	divider.visible = docked and not collapsed
	divider.position = Vector2(0 if effective_window_state() == WindowState.DOCK_RIGHT else get_window().size.x-6,CHROME_HEIGHT)
	divider.size = Vector2(6,maxi(1,get_window().size.y-CHROME_HEIGHT))
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F12 and event.ctrl_pressed and event.shift_pressed:
		cycle_mode()
		get_viewport().set_input_as_handled()
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel_fishing") and (mode == Mode.PASSIVE or passive.is_ready()):
		passive.cancel("cancelled",true)
		mode = Mode.ACTIVE
		_layout()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and not _forwarding and mode == Mode.ACTIVE:
		_forwarding = true
		gameplay_viewport.push_input(event,true)
		_forwarding = false
		get_viewport().set_input_as_handled()
func _exit_tree() -> void:
	if passive != null: passive.cancel("shutdown",true)
	platform.close()
	for entry in _bound_layers.values():
		var layer = entry.node.get_ref()
		var parent = entry.parent.get_ref()
		if is_instance_valid(layer) and is_instance_valid(parent): layer.reparent(parent)
