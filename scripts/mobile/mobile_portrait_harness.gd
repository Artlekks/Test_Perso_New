extends Control

const TouchControls = preload("res://scripts/mobile/mobile_touch_controls.gd")
@export_file("*.tscn") var gameplay_scene: String = "res://actors/FishingTestScene_V2.tscn"
@export var reference_size := Vector2i(390, 844)
@export_range(0.35, 0.7, 0.01) var gameplay_region_ratio: float = 0.58
@export var fallback_safe_insets := Vector4(0, 47, 0, 34)
@export var isolated_playtest_save: bool = true
var gameplay_viewport: SubViewport
var game: Node
var controls: Control
var gameplay_image: TextureRect
var safe_rect := Rect2()
var _forwarding := false
var _bound_layers: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Runtime settings apply only while this optional shell is running.
	if isolated_playtest_save:
		ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
		ProjectSettings.set_setting("application/config/custom_user_dir_name", "FishingGame-MobilePortraitPlaytest")
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	if OS.get_name() not in ["iOS", "Android", "Web"] and DisplayServer.get_name() != "headless":
		get_window().size = reference_size
	get_window().content_scale_size = reference_size
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	if OS.get_name() in ["iOS", "Android"]:
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_PORTRAIT)
	var presentation := CanvasLayer.new()
	presentation.name = "PortraitShellPresentation"
	presentation.layer = 128
	add_child(presentation)
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	presentation.add_child(black)
	gameplay_viewport = SubViewport.new()
	gameplay_viewport.name = "GameplayViewport"
	gameplay_viewport.size = Vector2i(640, 480)
	gameplay_viewport.own_world_3d = true
	gameplay_viewport.world_2d = World2D.new()
	gameplay_viewport.handle_input_locally = true
	gameplay_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(gameplay_viewport)
	gameplay_image = TextureRect.new()
	gameplay_image.name = "GameplayImage"
	gameplay_image.texture = gameplay_viewport.get_texture()
	gameplay_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gameplay_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	gameplay_image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	gameplay_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	presentation.add_child(gameplay_image)
	controls = TouchControls.new()
	controls.name = "TouchControls"
	controls.key_requested.connect(_send_key)
	presentation.add_child(controls)
	resized.connect(_layout)
	get_window().focus_exited.connect(controls.release_all)
	get_tree().node_added.connect(_node_added)
	_layout()
	call_deferred("_mount_game")

func get_safe_rect(view_size: Vector2, device_safe: Rect2 = Rect2(), device_size: Vector2 = Vector2.ZERO) -> Rect2:
	if device_safe.has_area() and device_size.x > 0 and device_size.y > 0:
		var scale := view_size / device_size
		return Rect2(device_safe.position * scale, device_safe.size * scale).intersection(Rect2(Vector2.ZERO, view_size))
	return Rect2(Vector2(fallback_safe_insets.x, fallback_safe_insets.y), Vector2(maxf(view_size.x - fallback_safe_insets.x - fallback_safe_insets.z, 0), maxf(view_size.y - fallback_safe_insets.y - fallback_safe_insets.w, 0)))

func _layout() -> void:
	if not is_instance_valid(controls):
		return
	var device_safe := Rect2()
	var device_size := Vector2.ZERO
	if OS.get_name() in ["iOS", "Android"]:
		device_safe = Rect2(DisplayServer.get_display_safe_area())
		device_size = Vector2(DisplayServer.screen_get_size())
	elif OS.has_feature("web"):
		# Safari CSS env() values are in CSS pixels, matching innerWidth/Height.
		var result = JavaScriptBridge.eval("JSON.stringify((()=>{const e=document.createElement('div');e.style.cssText='position:fixed;padding:env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left)';document.body.appendChild(e);const s=getComputedStyle(e);const r=[parseFloat(s.paddingLeft)||0,parseFloat(s.paddingTop)||0,parseFloat(s.paddingRight)||0,parseFloat(s.paddingBottom)||0,innerWidth,innerHeight];e.remove();return r})())")
		var values = JSON.parse_string(str(result))
		if values is Array and values.size() == 6:
			device_size = Vector2(values[4], values[5])
			device_safe = Rect2(Vector2(values[0], values[1]), device_size - Vector2(values[0] + values[2], values[1] + values[3]))
	safe_rect = get_safe_rect(size, device_safe, device_size)
	# Keep a portrait column if a browser temporarily rotates to landscape.
	var reference_safe_height := maxf(float(reference_size.y) - fallback_safe_insets.y - fallback_safe_insets.w, 1.0)
	var column_width := minf(safe_rect.size.x, safe_rect.size.y * float(reference_size.x) / reference_safe_height)
	safe_rect.position.x += (safe_rect.size.x - column_width) * 0.5
	safe_rect.size.x = column_width
	gameplay_image.position = safe_rect.position
	gameplay_image.size = Vector2(safe_rect.size.x, safe_rect.size.y * gameplay_region_ratio)
	controls.position = safe_rect.position + Vector2(0, gameplay_image.size.y)
	controls.size = Vector2(safe_rect.size.x, safe_rect.size.y - gameplay_image.size.y)

func _mount_game() -> void:
	load_gameplay_scene(gameplay_scene)

func get_gameplay_scene() -> Node:
	return game

func load_gameplay_scene(path: String) -> Error:
	var packed = load(path)
	if not (packed is PackedScene):
		return ERR_CANT_OPEN
	_replace_game.call_deferred(packed)
	return OK

func _replace_game(packed: PackedScene) -> void:
	controls.release_all()
	if is_instance_valid(game):
		game.free()
	game = packed.instantiate()
	game.process_mode = Node.PROCESS_MODE_PAUSABLE
	gameplay_viewport.add_child(game)
	_bind_session_layers()

func _node_added(node: Node) -> void:
	if node is CanvasLayer:
		_bind_session_layers.call_deferred()

func _bind_session_layers() -> void:
	var session := get_tree().root.get_node_or_null("FishingSessionServices")
	if session == null:
		return
	for layer in session.find_children("*", "CanvasLayer", true, false):
		if not _bound_layers.has(layer.get_instance_id()):
			_bound_layers[layer.get_instance_id()] = {"node": weakref(layer), "parent": weakref(layer.get_parent())}
		# Actual parenting gives Controls the correct 640x480 layout/input space,
		# as well as rendering there. Data services remain at their existing root.
		layer.reparent(gameplay_viewport)

func _send_key(event: InputEventKey) -> void:
	if event.physical_keycode in [KEY_W, KEY_A, KEY_S, KEY_D]:
		# Stick analog actions are owned by the adapter. Dispatch their canonical
		# keys for legacy navigation without adding a full-strength digital source.
		get_viewport().push_input(event, true)
	else:
		Input.parse_input_event(event)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and not _forwarding:
		_forwarding = true
		gameplay_viewport.push_input(event, true)
		_forwarding = false
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		if is_instance_valid(controls):
			controls.release_all()

func _exit_tree() -> void:
	if is_instance_valid(controls):
		controls.release_all()
	for entry in _bound_layers.values():
		var layer = entry.node.get_ref()
		var original_parent = entry.parent.get_ref()
		if is_instance_valid(layer) and is_instance_valid(original_parent):
			layer.reparent(original_parent)
