extends Control
## Presentation host only. Mode changes never replace the game or its services.
enum Mode { ACTIVE, PASSIVE, COLLAPSED }
const SURFACE := Vector2i(640, 864)
@export_file("*.tscn") var gameplay_scene := "res://actors/FishingTestScene_V2.tscn"
@export var active_scale := 0.75
@export var passive_size := Vector2i(240, 220)
@export var collapsed_size := Vector2i(96, 160)
const CHROME_HEIGHT := 28
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
	var scale := minf(active_scale, minf(float(usable.size.x) / SURFACE.x, float(usable.size.y - CHROME_HEIGHT) / SURFACE.y))
	var desired := Vector2i(Vector2(SURFACE) * scale) + Vector2i(0, CHROME_HEIGHT)
	if mode == Mode.PASSIVE: desired = passive_size
	if mode == Mode.COLLAPSED: desired = collapsed_size
	window.size = desired.min(usable.size)
	window.position = usable.position + Vector2i(usable.size.x - window.size.x, maxi(0, (usable.size.y - window.size.y) / 2))
	window.unfocusable = mode != Mode.ACTIVE
	if mode == Mode.ACTIVE and DisplayServer.get_name() != "headless": window.grab_focus()
	_layout()
func _layout() -> void:
	if image == null: return
	image.position = Vector2(0,CHROME_HEIGHT)
	image.size = Vector2(get_window().size) - Vector2(0,CHROME_HEIGHT)
	image.visible = mode != Mode.COLLAPSED
	status.text = ["ACTIVE", "PASSIVE", "COLLAPSED"][mode]
	status.position = Vector2(4,4 if mode != Mode.COLLAPSED else 38)
	toggle.position = Vector2(maxf(0,get_window().size.x - 68),0)
	toggle.size = Vector2(68,CHROME_HEIGHT)
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
	for entry in _bound_layers.values():
		var layer = entry.node.get_ref()
		var parent = entry.parent.get_ref()
		if is_instance_valid(layer) and is_instance_valid(parent): layer.reparent(parent)
