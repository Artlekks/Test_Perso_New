extends Control
## Presentation host only. Mode changes never replace the game or its services.
enum Mode { ACTIVE, PASSIVE, COLLAPSED }
const SURFACE := Vector2i(640, 864)
@export_file("*.tscn") var gameplay_scene := "res://actors/FishingTestScene_V2.tscn"
@export var active_scale := 0.75
@export var passive_size := Vector2i(240, 220)
@export var collapsed_size := Vector2i(96, 160)
const CHROME_HEIGHT := 28
const KEYBOARD_HEIGHT := 42
@export var dock_active_width := 480
@export var dock_passive_width := 240
@export var dock_collapsed_width := 96
var docked := false
var platform = preload("res://scripts/desktop/companion_window_platform.gd").new()
var dock_toggle: Button
var keyboard_strip: Label
var _floating_rect := Rect2i()
var _pending_float_restore := false
var _platform_poll := 0.0
var mode := Mode.ACTIVE
var game: Node
var gameplay_viewport: SubViewport
var image: TextureRect
var status: Label
var toggle: Button
var _forwarding := false
var _bound_layers: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_window().content_scale_size = Vector2i.ZERO
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	gameplay_viewport = SubViewport.new()
	gameplay_viewport.name = "GameplayViewport"
	gameplay_viewport.set_meta("input_hint_device", "keyboard")
	gameplay_viewport.size = SURFACE
	gameplay_viewport.own_world_3d = true
	gameplay_viewport.world_2d = World2D.new()
	gameplay_viewport.handle_input_locally = true
	gameplay_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(gameplay_viewport)
	image = TextureRect.new()
	image.texture = gameplay_viewport.get_texture()
	image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(image)
	status = Label.new()
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(status)
	toggle = Button.new()
	toggle.text = "Mode"
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.pressed.connect(cycle_mode)
	add_child(toggle)
	dock_toggle = Button.new()
	dock_toggle.text = "Dock Right"
	dock_toggle.focus_mode = Control.FOCUS_NONE
	dock_toggle.disabled = not platform.supported()
	dock_toggle.pressed.connect(func(): set_docked(not docked))
	add_child(dock_toggle)
	keyboard_strip = preload("res://scripts/desktop/companion_keyboard_strip.gd").new()
	keyboard_strip.host = self
	add_child(keyboard_strip)
	resized.connect(_layout)
	get_tree().node_added.connect(_node_added)
	set_mode(Mode.ACTIVE)
	load_gameplay_scene(gameplay_scene)

func get_gameplay_scene() -> Node: return game
func load_gameplay_scene(path: String) -> Error:
	var packed = load(path)
	if not packed is PackedScene: return ERR_CANT_OPEN
	_replace_game.call_deferred(packed)
	return OK
func _replace_game(packed: PackedScene) -> void:
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
	for layer in session.find_children("*", "CanvasLayer", true, false):
		if not _bound_layers.has(layer.get_instance_id()):
			_bound_layers[layer.get_instance_id()] = {"node": weakref(layer), "parent": weakref(layer.get_parent())}
		if layer.get_parent() != gameplay_viewport: layer.reparent(gameplay_viewport)

func cycle_mode() -> void: set_mode((mode + 1) % 3)
func set_mode(next: int) -> void:
	mode = next
	var window := get_window()
	var usable := DisplayServer.screen_get_usable_rect(window.current_screen)
	if not usable.has_area(): usable = Rect2i(Vector2i.ZERO, SURFACE + Vector2i(0,CHROME_HEIGHT)) # headless fixture only
	var chrome := CHROME_HEIGHT + KEYBOARD_HEIGHT
	var scale := minf(active_scale, minf(float(usable.size.x) / SURFACE.x, float(usable.size.y - chrome) / SURFACE.y))
	var desired := Vector2i(Vector2(SURFACE) * scale) + Vector2i(0, chrome)
	if mode == Mode.PASSIVE: desired = passive_size
	if mode == Mode.COLLAPSED: desired = collapsed_size
	if docked:
		# Native adapter negotiates against the full monitor/taskbar, avoiding
		# feedback from the work area already reduced by our own reservation.
		var width: int = [dock_active_width,dock_passive_width,dock_collapsed_width][mode]
		desired.x = width
		if mode == Mode.ACTIVE: desired.y = roundi(float(width) * SURFACE.y / SURFACE.x) + chrome
	window.size = desired.min(DisplayServer.screen_get_size(window.current_screen) if docked else usable.size)
	if not docked: window.position = usable.position + Vector2i(usable.size.x - window.size.x, maxi(0, (usable.size.y - window.size.y) / 2))
	window.unfocusable = mode != Mode.ACTIVE
	if mode == Mode.ACTIVE and DisplayServer.get_name() != "headless": window.grab_focus()
	_layout()
	if docked:
		var error: Error = platform.request(true,window)
		if error != OK:
			dock_toggle.tooltip_text = "Dock unavailable: " + error_string(error)
			set_docked(false)

func set_docked(value: bool) -> void:
	if value == docked: return
	if value and not platform.supported(): return
	var window := get_window()
	if value: _floating_rect = Rect2i(window.position,window.size)
	docked = value
	_pending_float_restore = not value
	window.borderless = value
	dock_toggle.text = "Float" if value else "Dock Right"
	if value:
		set_mode(mode)
	else:
		var error: Error = platform.request(false,window)
		if error != OK or platform.helper_pid <= 0 or not OS.is_process_running(platform.helper_pid): _restore_floating()

func _restore_floating() -> void:
	_pending_float_restore = false
	get_window().size = _floating_rect.size
	get_window().position = _floating_rect.position
	_layout()

func _process(delta: float) -> void:
	_platform_poll += delta
	if _platform_poll < 0.1: return
	_platform_poll = 0.0
	var state: Dictionary = platform.read_status()
	if _pending_float_restore and state.get("sequence",-1) == platform.sequence and not state.get("registered",true):
		# Restore after the shell releases its work area, so Windows does not
		# clamp the floating window against our still-active reservation.
		_restore_floating()
	if not str(state.get("error", "")).is_empty():
		dock_toggle.tooltip_text = "Dock failed: " + str(state.error)
		if docked: set_docked(false)
func _layout() -> void:
	if image == null: return
	image.position = Vector2(0,CHROME_HEIGHT)
	image.size = Vector2(get_window().size) - Vector2(0,CHROME_HEIGHT + KEYBOARD_HEIGHT)
	image.visible = mode != Mode.COLLAPSED
	status.text = ["ACTIVE", "PASSIVE", "COLLAPSED"][mode]
	status.position = Vector2(4,4 if mode != Mode.COLLAPSED else 38)
	toggle.position = Vector2(maxf(0,get_window().size.x - 68),0)
	toggle.size = Vector2(68,CHROME_HEIGHT)
	dock_toggle.position = Vector2(maxf(0,get_window().size.x - 172),0)
	dock_toggle.size = Vector2(104,CHROME_HEIGHT)
	dock_toggle.visible = mode != Mode.COLLAPSED
	keyboard_strip.position = Vector2(4,get_window().size.y-KEYBOARD_HEIGHT)
	keyboard_strip.size = Vector2(get_window().size.x-8,KEYBOARD_HEIGHT)
	keyboard_strip.visible = mode == Mode.ACTIVE
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F12 and event.ctrl_pressed and event.shift_pressed:
		cycle_mode()
		get_viewport().set_input_as_handled()
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and not _forwarding and mode == Mode.ACTIVE:
		_forwarding = true
		gameplay_viewport.push_input(event, true)
		_forwarding = false
		get_viewport().set_input_as_handled()
func _exit_tree() -> void:
	platform.close()
	for entry in _bound_layers.values():
		var layer = entry.node.get_ref()
		var parent = entry.parent.get_ref()
		if is_instance_valid(layer) and is_instance_valid(parent): layer.reparent(parent)
