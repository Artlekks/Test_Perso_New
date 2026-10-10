extends Control
## Window presentation and gameplay activity are deliberately independent.
enum Mode { ACTIVE, PASSIVE }
enum WindowState { FLOATING, DOCK_LEFT, DOCK_RIGHT, COLLAPSED }
const Surface = preload("res://scripts/ui/canonical_game_surface.gd")
const SURFACE := Surface.SIZE
const SHELL_SURFACE := Surface.MENU_SIZE
const CHROME_HEIGHT := 68
const KEYBOARD_HEIGHT := 60
@export_file("*.tscn") var gameplay_scene := "res://actors/FishingTestScene_V2.tscn"
@export var active_scale := 0.75
@export var min_dock_width := 320
@export var default_dock_width := 480
@export var max_dock_width := 900
@export var collapsed_width := 28
const WIDGET_HEIGHT := 96
const SHELL_COLOR := Color(0.16, 0.16, 0.18)
const PLATFORM_STATUS_INTERVAL := 0.05
var mode := Mode.ACTIVE
var window_state := WindowState.FLOATING
var dock_width := 480
var _expanded_state := WindowState.FLOATING
var _expanded_rect := Rect2i()
var _platform_poll := 0.0
var _request_pending := false
var _floating_restore_rect := Rect2i()
var _pending_shell_fullscreen := false
var _pending_float_decoration := false
var _float_client_rect := Rect2i()
var _dock_drag := false
var _drag_x := 0
var _drag_width := 0
var game: Node
var gameplay_viewport: SubViewport
var menu_viewport: SubViewport
var menu_image: TextureRect
var image: TextureRect
var shell: Control
var shell_fill: ColorRect
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
	get: return window_state in [WindowState.DOCK_LEFT,WindowState.DOCK_RIGHT]
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_window().content_scale_size = Vector2i.ZERO
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_window().unresizable = false
	get_window().min_size = Vector2i(min_dock_width,400)
	get_window().borderless = false
	shell_fill = ColorRect.new()
	shell_fill.color = SHELL_COLOR
	shell_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shell_fill)
	shell = preload("res://scripts/ui/seaside_shell_view.gd").new()
	shell.host = self
	add_child(shell)
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
	menu_viewport = SubViewport.new()
	menu_viewport.name = "MenuViewport"
	menu_viewport.size = Surface.MENU_SIZE
	menu_viewport.transparent_bg = true
	menu_viewport.disable_3d = true
	menu_viewport.world_2d = World2D.new()
	menu_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(menu_viewport)
	menu_image = TextureRect.new()
	menu_image.texture = menu_viewport.get_texture()
	menu_image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	menu_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	menu_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	menu_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(menu_image)
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
	divider.color = Color.TRANSPARENT
	divider.mouse_default_cursor_shape = Control.CURSOR_HSIZE
	divider.gui_input.connect(_divider_input)
	add_child(divider)
	resized.connect(_on_resize)
	get_window().close_requested.connect(func(): get_tree().quit())
	get_window().focus_exited.connect(func(): _dock_drag = false)
	get_tree().node_added.connect(_node_added)
	var usable := DisplayServer.screen_get_usable_rect(get_window().current_screen)
	if not usable.has_area(): usable = Rect2i(Vector2i.ZERO,Vector2i(1280,1024))
	get_window().size = Vector2i(Vector2(SHELL_SURFACE)*active_scale)+Vector2i(0,CHROME_HEIGHT+KEYBOARD_HEIGHT)
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
	_bind_menu_layers()
func _node_added(node: Node) -> void:
	if node is CanvasLayer:
		_bind_session_layers.call_deferred()
		_bind_menu_layers.call_deferred()
func _bind_session_layers() -> void:
	var session := get_node_or_null("/root/FishingSessionServices")
	if session == null: return
	for layer in session.find_children("*","CanvasLayer",true,false):
		if not _bound_layers.has(layer.get_instance_id()): _bound_layers[layer.get_instance_id()] = {"node":weakref(layer),"parent":weakref(layer.get_parent())}
		if layer.get_parent() != gameplay_viewport: layer.reparent(gameplay_viewport)
func _bind_menu_layers() -> void:
	if not is_instance_valid(game) or menu_viewport == null: return
	for layer in gameplay_viewport.find_children("*","CanvasLayer",true,false):
		if layer is DialogueView or layer.name == "FishingCatchView": continue
		if not layer.has_method("is_open"): continue
		if layer.custom_viewport == menu_viewport: continue
		var parent := layer.get_parent()
		var index := layer.get_index()
		var saved_owner := layer.owner
		parent.remove_child(layer)
		layer.custom_viewport = menu_viewport
		parent.add_child(layer)
		parent.move_child(layer,index)
		layer.owner = saved_owner
		if layer.has_method("_fit_menu_canvas"): layer._fit_menu_canvas()

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
	var current_rect := Rect2i(get_window().position,get_window().size)
	window_state = next
	_expanded_state = next
	_pending_float_decoration = false
	if docked: get_window().borderless = true
	# Decoration changes occur only on mode transitions. The native adapter
	# owns all dock/widget rectangles; resizing never toggles decoration.
	if docked: _apply_dock_size()
	else:
		_float_client_rect = current_rect
		_pending_float_decoration = true
		var error: Error = platform.request(false,get_window(),"right")
		if error != OK:
			status.text = error_string(error)
			_request_pending = true
		if not platform.supported() or platform.helper_pid <= 0: _restore_float_decoration()
	_layout()
func toggle_collapse() -> void:
	if window_state == WindowState.COLLAPSED:
		window_state = _expanded_state
		if docked: _request_pending = true
		else:
			if platform.supported():
				_floating_restore_rect = _expanded_rect
				_float_client_rect = _expanded_rect
				_pending_float_decoration = true
				_request_pending = true
			else:
				get_window().borderless = false
				get_window().size = _expanded_rect.size
				get_window().position = _expanded_rect.position
	else:
		_expanded_state = window_state
		_expanded_rect = Rect2i(get_window().position,get_window().size)
		window_state = WindowState.COLLAPSED
		_pending_float_decoration = false
		get_window().borderless = true
		get_window().min_size = Vector2i(collapsed_width,WIDGET_HEIGHT)
		_request_pending = platform.supported()
		if not platform.supported(): get_window().size = Vector2i(collapsed_width,WIDGET_HEIGHT)
	_layout()
func set_dock_width(value: int) -> void:
	dock_width = clampi(value,min_dock_width,max_dock_width)
	if docked and window_state != WindowState.COLLAPSED: _apply_dock_size()
func _desired_dock_size() -> Vector2i:
	var width := collapsed_width if window_state == WindowState.COLLAPSED else dock_width
	var height := 200 if window_state == WindowState.COLLAPSED else roundi(float(width)*SHELL_SURFACE.y/SHELL_SURFACE.x)+CHROME_HEIGHT+KEYBOARD_HEIGHT
	return Vector2i(width,mini(height,DisplayServer.screen_get_size(get_window().current_screen).y))
func _apply_dock_size() -> void:
	_request_pending = true
func _on_resize() -> void:
	_layout()
	# Native acknowledgements are outputs, never new width commands.
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
	# Publish a changed width every rendered drag frame. Status polling remains
	# bounded when idle; two serial 50 ms gates made physical dragging stepped.
	if not _request_pending and _platform_poll < PLATFORM_STATUS_INTERVAL: return
	_platform_poll = 0
	if _request_pending:
		_request_pending = false
		# Native acknowledgements can resize the client asynchronously. They must
		# never overwrite the user's desired width with an older acknowledged size.
		var error: Error = platform.request(docked,get_window(),"left" if effective_window_state() == WindowState.DOCK_LEFT else "right",Vector2i(collapsed_width,WIDGET_HEIGHT) if window_state == WindowState.COLLAPSED else (_desired_dock_size() if docked else Vector2i.ZERO), window_state == WindowState.COLLAPSED, _floating_restore_rect)
		if error != OK:
			status.text = error_string(error)
			_request_pending = true # Keep current edge; retry transport, never float.
		else: _floating_restore_rect = Rect2i()
	var state: Dictionary = platform.read_status()
	if _pending_float_decoration and state.get("sequence",-1) == platform.sequence and not state.get("registered",false):
		_restore_float_decoration()
	if docked and not str(state.get("error","")).is_empty():
		status.text = str(state.error)
		set_window_state(WindowState.FLOATING)
	_layout()
func _restore_float_decoration() -> void:
	# Release AppBar first: a normal decorated window inside the old reserved
	# work area can otherwise be relocated by Windows during the transition.
	_pending_float_decoration = false
	get_window().borderless = false
	get_window().min_size = Vector2i(min_dock_width,400)
	get_window().size = _float_client_rect.size
	get_window().position = _float_client_rect.position
	if _pending_shell_fullscreen:
		_pending_shell_fullscreen = false
		get_window().mode = Window.MODE_FULLSCREEN
func _layout() -> void:
	if image == null or keyboard_strip == null: return
	var collapsed := window_state == WindowState.COLLAPSED
	shell_fill.size = Vector2(get_window().size)
	var geometry := preload("res://scripts/ui/seaside_shell_layout.gd").desktop(Vector2(get_window().size))
	shell.size = Vector2(get_window().size)
	shell.visible = not collapsed
	shell.configure(geometry)
	image.position = geometry.world.position
	image.size = geometry.world.size
	image.visible = not collapsed
	menu_image.position = Vector2(0,CHROME_HEIGHT)
	menu_image.size = Vector2(get_window().size)-Vector2(0,CHROME_HEIGHT+KEYBOARD_HEIGHT)
	menu_image.visible = not collapsed
	keyboard_strip.position = geometry.controls.position+Vector2(12,30)
	keyboard_strip.size = geometry.controls.size-Vector2(24,40)
	keyboard_strip.visible = not collapsed
	var labels := ["Float","Dock Left","Dock Right","Collapse"]
	for i in range(labels.size()):
		var button: Button = buttons[labels[i]]
		button.visible = not collapsed or labels[i] == "Collapse"
		button.position = Vector2(i*float(get_window().size.x)/4,0) if not collapsed else Vector2.ZERO
		button.size = Vector2(float(get_window().size.x)/4,32) if not collapsed else Vector2(get_window().size.x,WIDGET_HEIGHT)
	buttons.Collapse.tooltip_text = "FISH READY - restore and switch Active" if passive != null and passive.is_ready() else "Restore companion"
	buttons.Collapse.text = (" > " if effective_window_state() == WindowState.DOCK_LEFT else " < ") if collapsed else "Collapse"
	buttons.Mode.visible = not collapsed
	buttons.X.visible = not collapsed
	buttons.Mode.text = "Active" if mode == Mode.ACTIVE else "Passive"
	buttons.Mode.tooltip_text = passive.reason if passive != null else ""
	buttons.Mode.position = Vector2(0,40 if collapsed else 34)
	buttons.Mode.size = Vector2(get_window().size.x-28,28)
	buttons.X.position = Vector2(get_window().size.x-28,40 if collapsed else 34)
	buttons.X.size = Vector2(28,28)
	status.position = Vector2(3,70 if collapsed else 50)
	status.visible = collapsed and passive != null and passive.is_ready()
	status.text = "!" if passive != null and passive.is_ready() else ("Focus" if mode == Mode.PASSIVE else "Active")
	for id in buttons:
		buttons[id].visible = collapsed and id == "Collapse"
	passive.layout_timer(gameplay_display_rect())
	if not collapsed and is_instance_valid(passive.timer_entry):
		passive.timer_entry.position = geometry.world.position + Vector2(geometry.world.size.x*.35,12)
		passive.timer_entry.size = Vector2(geometry.world.size.x*.3,44)
	divider.visible = docked and not collapsed
	divider.position = Vector2(0 if effective_window_state() == WindowState.DOCK_RIGHT else get_window().size.x-8,CHROME_HEIGHT)
	divider.size = Vector2(8,maxi(1,get_window().size.y-CHROME_HEIGHT))
func _input(event: InputEvent) -> void:
	if mode == Mode.PASSIVE and event.is_action_pressed("enter_fishing") and not event.is_echo() and not get_tree().paused:
		set_mode(Mode.ACTIVE)
		# Consume the shell event; forward this same intent exactly once.
		get_viewport().set_input_as_handled()
		_forwarding = true
		gameplay_viewport.push_input(event,true)
		_forwarding = false
		return
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
		if is_instance_valid(layer) and is_instance_valid(parent):
			var scene_parent: Node = layer.get_parent()
			scene_parent.remove_child(layer)
			layer.custom_viewport = parent.get_viewport()
			parent.add_child(layer)

func gameplay_display_rect() -> Rect2:
	var factor := minf(image.size.x / SURFACE.x, image.size.y / SURFACE.y)
	var footprint := Vector2(SURFACE) * factor
	return Rect2(image.position + (image.size-footprint)*0.5, footprint)

func request_shell_menu(id: String) -> void:
	preload("res://scripts/ui/seaside_shell_actions.gd").request(self,id)

func toggle_shell_fullscreen() -> void:
	if docked:
		_pending_shell_fullscreen = true
		set_window_state(WindowState.FLOATING)
	else:
		get_window().mode = Window.MODE_WINDOWED if get_window().mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN

func dock_from_shell(next: int) -> void:
	if get_window().mode == Window.MODE_FULLSCREEN:
		get_window().mode = Window.MODE_WINDOWED
		set_window_state.call_deferred(next)
	else:
		set_window_state(next)
