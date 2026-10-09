extends Control

const TouchControls = preload("res://scripts/mobile/mobile_touch_controls.gd")
@export_file("*.tscn") var gameplay_scene: String = "res://actors/FishingTestScene_V2.tscn"
@export var reference_size := Vector2i(390, 844)
@export var fallback_safe_insets := Vector4(0, 47, 0, 34)
@export var minimum_controls_height: float = 236.0
@export var isolated_playtest_save: bool = true
@export var developer_playtest_default_enabled: bool = true
var _developer_mode_initialized := false
var gameplay_viewport: SubViewport
var game: Node
var controls: Control
var gameplay_image: TextureRect
var gameplay_window: Control
var _surface_scroll := 0.0
var _surface_scroll_max := 0.0
var _surface_drag := -1
var _surface_drag_y := 0.0
var _surface_was_modal := false
var _surface_modal_layers: Array[WeakRef] = []
var safe_rect := Rect2()
var _forwarding := false
var _bound_layers: Dictionary = {}
var _window_touches := {}

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
	gameplay_viewport.size = Vector2i(640, 864)
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
	gameplay_window = Control.new()
	gameplay_window.name = "GameplayDisplayWindow"
	gameplay_window.clip_contents = true
	gameplay_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	presentation.add_child(gameplay_window)
	gameplay_window.add_child(gameplay_image)
	controls = TouchControls.new()
	controls.name = "TouchControls"
	controls.key_requested.connect(_send_key)
	controls.action_requested.connect(_queue_action)
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

func get_layout_rects(available: Rect2) -> Dictionary:
	var column := available
	# Retain the existing narrow control column only for landscape windows.
	# Portrait uses all safe width, including when Safari chrome reduces height.
	if column.size.x > column.size.y:
		var reference_safe_height := maxf(float(reference_size.y) - fallback_safe_insets.y - fallback_safe_insets.w, 1.0)
		var column_width := minf(column.size.x, column.size.y * float(reference_size.x) / reference_safe_height)
		column.position.x += (column.size.x - column_width) * 0.5
		column.size.x = column_width
	# Width is authoritative. Short Safari windows clip spare world sky rather
	# than shrink the canonical surface; menus can scroll the display vertically.
	var controls_min := minimum_controls_height * column.size.x / float(reference_size.x)
	var scale := column.size.x / 640.0
	var width := 640.0 * scale
	var image := Rect2(column.position, Vector2(width, 864.0 * scale))
	var display := Rect2(column.position, Vector2(width, minf(image.size.y, maxf(1.0,column.size.y-controls_min))))
	var panel := Rect2(column.position + Vector2(0, display.size.y), Vector2(column.size.x, column.size.y - display.size.y))
	return {"safe": column, "gameplay": image, "display": display, "controls": panel, "resolution": Vector2i(640, 864)}

func _layout() -> void:
	if not is_instance_valid(controls):
		return
	_surface_drag = -1
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
	var layout := get_layout_rects(get_safe_rect(size, device_safe, device_size))
	safe_rect = layout.safe
	gameplay_window.position = layout.display.position
	gameplay_window.size = layout.display.size
	gameplay_image.size = layout.gameplay.size
	_surface_scroll_max = maxf(0,layout.gameplay.size.y-layout.display.size.y)
	_surface_scroll = clampf(_surface_scroll,0,_surface_scroll_max) if _has_surface_modal() else _surface_scroll_max
	gameplay_image.position = Vector2(0,-_surface_scroll)
	controls.position = layout.controls.position
	controls.size = layout.controls.size
	gameplay_viewport.size = layout.resolution
	_adapt_mobile_presentation()

func _process(_delta: float) -> void:
	# World play keeps bottom HUD visible; modal content starts at the top.
	var modal := _has_surface_modal()
	if modal != _surface_was_modal:
		_surface_was_modal = modal
		_surface_scroll = 0.0 if modal else _surface_scroll_max
		if gameplay_image != null: gameplay_image.position.y = -_surface_scroll

func _input(event: InputEvent) -> void:
	# A narrow right-edge gutter scrolls the display window, independently of
	# each canonical menu's own content scrolling. No gameplay state is changed.
	if _surface_scroll_max <= 0 or not _has_surface_modal(): return
	if event is InputEventScreenTouch:
		var box := gameplay_window.get_global_rect()
		if event.pressed and box.has_point(event.position) and event.position.x >= box.end.x - 20:
			_surface_drag = event.index
			_surface_drag_y = event.position.y
			get_viewport().set_input_as_handled()
		elif not event.pressed and event.index == _surface_drag:
			_surface_drag = -1
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == _surface_drag:
		_surface_scroll = clampf(_surface_scroll + _surface_drag_y - event.position.y,0,_surface_scroll_max)
		_surface_drag_y = event.position.y
		gameplay_image.position.y = -_surface_scroll
		get_viewport().set_input_as_handled()

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
	_surface_modal_layers = _surface_modal_layers.filter(func(binding): return binding.get_ref() != null)
	game = packed.instantiate()
	game.process_mode = Node.PROCESS_MODE_PAUSABLE
	# HUD scripts cache their tween destinations in _ready. Establish host
	# anchors first, rather than moving those destinations after initialization.
	_adapt_mobile_presentation()
	gameplay_viewport.add_child(game)
	_initialize_developer_mode.call_deferred()
	_bind_session_layers()
	_adapt_mobile_presentation()

func _initialize_developer_mode() -> void:
	if _developer_mode_initialized: return
	var developer := DeveloperPlaytestService.current()
	if developer == null:
		get_tree().process_frame.connect(_initialize_developer_mode, CONNECT_ONE_SHOT)
		return
	_developer_mode_initialized = true
	developer.authorize_isolated_mobile_save(isolated_playtest_save)
	developer.set_enabled(developer_playtest_default_enabled)
	_bind_session_layers()
	_adapt_mobile_presentation()

func _node_added(node: Node) -> void:
	if node is CanvasLayer:
		if not node is DialogueView and (node.has_method("is_open") or node.name in ["FishingCatchView", "FishingLureSelectorView"]):
			if not _surface_modal_layers.any(func(binding): return binding.get_ref() == node):
				_surface_modal_layers.append(weakref(node))
		_bind_session_layers.call_deferred()
	if node is CanvasLayer or node is Camera3D:
		_adapt_mobile_presentation.call_deferred()

func _has_surface_modal() -> bool:
	# Read published presentation visibility, not SceneTree.paused: manual pause
	# must retain the world HUD, and catch results need their header while unpaused.
	for binding in _surface_modal_layers:
		var layer = binding.get_ref()
		if not is_instance_valid(layer) or not layer.is_node_ready(): continue
		# Dialogue is a bottom-anchored overlay, never a shell scroll owner.
		if layer is DialogueView: continue
		if layer.has_method("is_open") and layer.is_open(): return true
		if layer.name in ["FishingCatchView", "FishingLureSelectorView"]:
			var surface := layer.get_node_or_null("Root") as Control
			if surface != null and surface.is_visible_in_tree(): return true
	return false

func _adapt_mobile_presentation() -> void:
	if not is_instance_valid(game): return
	preload("res://scripts/ui/canonical_game_surface.gd").prepare(game)
	for entry in _bound_layers.values():
		var layer = entry.node.get_ref()
		if not is_instance_valid(layer): continue
		if layer.has_meta("development_status"):
			if layer.get_parent() != controls: layer.reparent(controls)
			layer.custom_viewport = get_viewport()
			layer.offset = controls.global_position + Vector2(controls.size.x * 0.78, controls.size.y * 0.60)
		elif layer.name == "DeveloperIndicator": layer.offset = Vector2(0, 840)

func _bind_session_layers() -> void:
	var session := get_tree().root.get_node_or_null("FishingSessionServices")
	if session == null:
		return
	for layer in session.find_children("*", "CanvasLayer", true, false):
		if not _bound_layers.has(layer.get_instance_id()):
			_bound_layers[layer.get_instance_id()] = {"node": weakref(layer), "parent": weakref(layer.get_parent())}
		# Session data stays at its original root; presentation joins this viewport.
		if not layer.has_meta("development_status"): layer.reparent(gameplay_viewport)

func _send_key(event: InputEventKey) -> void:
	if event.physical_keycode in [KEY_W, KEY_A, KEY_S, KEY_D]:
		# Stick analog actions are owned by the adapter. Dispatch their canonical
		# keys for legacy navigation without adding a full-strength digital source.
		get_viewport().push_input(event, true)
	else:
		Input.parse_input_event(event)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		var scrolling := false
		for window in gameplay_viewport.find_children("MobilePlaytestWindow", "Node", true, false):
			if window.bar != null and window.bar.visible: scrolling = true
		for menu in gameplay_viewport.find_children("ResponsiveMenuSurface", "Control", true, false):
			if menu.is_visible_in_tree(): scrolling = true
		for detail in gameplay_viewport.find_children("PortraitDetails", "ScrollContainer", true, false):
			if detail.is_visible_in_tree(): scrolling = true
		if event is InputEventScreenTouch and event.pressed and scrolling and gameplay_window.get_global_rect().has_point(event.position):
			_window_touches[event.index] = true
		if _window_touches.has(event.index):
			var local_event = event.duplicate()
			local_event.position = (event.position - gameplay_image.global_position) * Vector2(gameplay_viewport.size) / gameplay_image.size
			gameplay_viewport.push_input(local_event, true)
			if event is InputEventScreenTouch and not event.pressed: _window_touches.erase(event.index)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and not _forwarding:
		_forwarding = true
		gameplay_viewport.push_input(event, true)
		_forwarding = false
		get_viewport().set_input_as_handled()

func _queue_action(event: InputEventAction) -> void:
	# Deliver after ScreenTouch handling finishes, rather than nesting a raw key.
	_dispatch_action.call_deferred(event)

func _dispatch_action(event: InputEventAction) -> void:
	if event.pressed:
		Input.action_press(event.action, event.strength)
	else:
		Input.action_release(event.action)
	if is_instance_valid(gameplay_viewport):
		gameplay_viewport.push_input(event, true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		_surface_drag = -1
		if is_instance_valid(controls):
			controls.release_all()

func _exit_tree() -> void:
	if is_instance_valid(controls):
		controls.release_all()
	if Input.is_action_pressed(&"world_card_challenge"):
		Input.action_release(&"world_card_challenge")
	for entry in _bound_layers.values():
		var layer = entry.node.get_ref()
		var original_parent = entry.parent.get_ref()
		if is_instance_valid(layer) and is_instance_valid(original_parent):
			var fitter: Node = layer.get_node_or_null("MobilePlaytestWindow")
			if fitter != null:
				fitter.surface.position = fitter.original_position
				fitter.bar.free()
				fitter.free()
			if layer.has_meta("development_status"):
				# The persistent layer outlives this SubViewport. Godot rejects
				# nullptr here; restore the original owner's live viewport.
				layer.custom_viewport = original_parent.get_viewport()
			if layer.has_meta("mobile_original_offset"):
				layer.offset = layer.get_meta("mobile_original_offset")
				layer.remove_meta("mobile_original_offset")
				for child in layer.get_children():
					if child is Control and child.has_meta("mobile_original_vertical_layout"):
						var old: Vector4 = child.get_meta("mobile_original_vertical_layout")
						child.anchor_top = old.x
						child.anchor_bottom = old.y
						child.offset_top = old.z
						child.offset_bottom = old.w
						child.remove_meta("mobile_original_vertical_layout")
			layer.reparent(original_parent)
