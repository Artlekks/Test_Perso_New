extends Control

const TouchControls = preload("res://scripts/mobile/mobile_touch_controls.gd")
const ResponsiveSurface = preload("res://scripts/mobile/responsive_menu_surface.gd")
const PlaytestWindow = preload("res://scripts/mobile/mobile_playtest_window.gd")
const RESPONSIVE_WINDOWS := ["FishingDebugMenu", "TripleTriadDebugMenu", "FishingEconomyMenu", "BeachCraftingMenu", "FishingCardMakerMenu", "TripleTriadGame", "PlayableCampaignQAGuide"]
@export_file("*.tscn") var gameplay_scene: String = "res://actors/FishingTestScene_V2.tscn"
@export var reference_size := Vector2i(390, 844)
@export var fallback_safe_insets := Vector4(0, 47, 0, 34)
@export_range(0.45, 0.72, 0.01) var gameplay_height_share: float = 0.69
@export var minimum_controls_height: float = 236.0
@export var economy_body_font_size: int = 12
@export var economy_small_font_size: int = 10
@export var isolated_playtest_save: bool = true
@export var developer_playtest_default_enabled: bool = true
var _developer_mode_initialized := false
var gameplay_viewport: SubViewport
var game: Node
var controls: Control
var gameplay_image: TextureRect
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
	var controls_min := minimum_controls_height * column.size.x / float(reference_size.x)
	var desired_height := minf(column.size.y * gameplay_height_share, column.size.y - controls_min)
	var logical_height := maxi(1, floori(desired_height * 640.0 / maxf(column.size.x, 1.0)))
	var image := Rect2(column.position, Vector2(column.size.x, logical_height * column.size.x / 640.0))
	var panel := Rect2(column.position + Vector2(0, image.size.y), Vector2(column.size.x, column.size.y - image.size.y))
	return {"safe": column, "gameplay": image, "controls": panel, "resolution": Vector2i(640, logical_height)}

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
	var layout := get_layout_rects(get_safe_rect(size, device_safe, device_size))
	safe_rect = layout.safe
	gameplay_image.position = layout.gameplay.position
	gameplay_image.size = layout.gameplay.size
	controls.position = layout.controls.position
	controls.size = layout.controls.size
	gameplay_viewport.size = layout.resolution
	_adapt_mobile_presentation()

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
		_bind_session_layers.call_deferred()
	if node is CanvasLayer or node is Camera3D:
		_adapt_mobile_presentation.call_deferred()

func _adapt_mobile_presentation() -> void:
	if not is_instance_valid(game):
		return
	var extra_height := float(gameplay_viewport.size.y - 480)
	_adapt_gameplay_hud(extra_height)
	for camera in game.find_children("*", "Camera3D", true, false):
		if not camera.has_meta("mobile_original_projection"):
			camera.set_meta("mobile_original_projection", {"aspect": camera.keep_aspect, "fov": camera.fov, "size": camera.size})
		var original: Dictionary = camera.get_meta("mobile_original_projection")
		if original.aspect == Camera3D.KEEP_HEIGHT:
			# Equivalent horizontal FOV of the authored desktop 640x480 shot.
			camera.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(original.fov) * 0.5) * 640.0 / 480.0))
			camera.size = original.size * 640.0 / 480.0
		camera.keep_aspect = Camera3D.KEEP_WIDTH
	# Keep authored UI art/coordinates in a centered 640x480 band, without
	# stretching menu backgrounds to the taller 3D viewport. Dialogue reflows
	# independently using its real viewport height and larger shared typography.
	var layers: Array = game.find_children("*", "CanvasLayer", true, false)
	for entry in _bound_layers.values():
		var layer = entry.node.get_ref()
		if is_instance_valid(layer):
			layers.append(layer)
	for layer in layers:
		if layer.has_meta("development_status"):
			# Diagnostic layers alone join the shell's control canvas. Gameplay
			# HUD and location-name artwork retain their established ownership.
			if layer.get_parent() != controls: layer.reparent(controls)
			layer.custom_viewport = get_viewport()
			layer.offset = controls.global_position + Vector2(controls.size.x * 0.78, controls.size.y * 0.60)
			for label in layer.get_children():
				if label is Label:
					label.position = Vector2.ZERO
					label.size = Vector2(controls.size.x * 0.21, controls.size.y * 0.21)
					label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
					label.add_theme_font_size_override("font_size", 10)
			continue
		if layer.name == "DeveloperIndicator":
			layer.offset = Vector2(0, gameplay_viewport.size.y - 24)
			continue
		if layer is DialogueView or layer.name in ["ExplorationHud", "FishingHud", "PowerMeter", "FishingInfoView"]:
			continue
		if not layer.has_meta("mobile_original_offset"):
			layer.set_meta("mobile_original_offset", layer.offset)
			for child in layer.get_children():
				if child is Control:
					child.set_meta("mobile_original_vertical_layout", Vector4(child.anchor_top, child.anchor_bottom, child.offset_top, child.offset_bottom))
					var old: Vector4 = child.get_meta("mobile_original_vertical_layout")
					child.anchor_top = 0.0
					child.anchor_bottom = 0.0
					child.offset_top = old.x * 480.0 + old.z
					child.offset_bottom = old.y * 480.0 + old.w
		layer.offset = layer.get_meta("mobile_original_offset") + Vector2(0, extra_height * 0.5)
		if layer.name in RESPONSIVE_WINDOWS and layer.is_inside_tree():
			layer.offset = Vector2.ZERO
			var window_root := layer.get_node_or_null("Root") as Control
			if window_root != null and not layer.has_node("MobilePlaytestWindow"):
				var fitter := PlaytestWindow.new()
				fitter.name = "MobilePlaytestWindow"
				layer.add_child(fitter)
				fitter.configure(window_root)
		var kind: String = {"FishingEconomyMenu":"economy", "BeachCraftingMenu":"crafting", "FishingCardMakerMenu":"card_maker"}.get(String(layer.name), "")
		if not kind.is_empty() and layer.is_inside_tree():
			ResponsiveSurface.attach(layer, layer.get_node("Root"), kind)
		if layer.name == "TripleTriadGame" and layer.is_inside_tree():
			var deck := layer.get_node_or_null("Root/TripleTriadDeckSetup") as Control
			if deck != null: ResponsiveSurface.attach(deck, deck, "deck")
	var rig := game.get_node_or_null("CameraRig")
	if rig != null:
		_adapt_fishing_composition(rig, extra_height)
		for property in ["fight_safe_top", "fight_safe_bottom", "fishing_follow_top_y_ratio", "fishing_follow_bottom_y_ratio", "fishing_follow_trigger_y_ratio"]:
			var key: String = "mobile_original_" + property
			if not rig.has_meta(key):
				rig.set_meta(key, rig.get(property))
			rig.set(property, (float(rig.get_meta(key)) * 480.0 + extra_height * 0.5) / float(gameplay_viewport.size.y))

func _bottom_anchor(control: Control) -> void:
	if control == null or control.has_meta("mobile_grounded_hud"):
		return
	control.set_meta("mobile_grounded_hud", true)
	var top := control.anchor_top * 480.0 + control.offset_top
	var bottom := control.anchor_bottom * 480.0 + control.offset_bottom
	control.anchor_top = 1.0
	control.anchor_bottom = 1.0
	control.offset_top = top - 480.0
	control.offset_bottom = bottom - 480.0

func _adapt_gameplay_hud(extra_height: float) -> void:
	# These are the production HUDs, with their production visibility/tweens.
	# Only menus retain the centered legacy band.
	for path in ["UI/ExplorationHud/Root/HelpPanel", "UI/FishingHud/CharacterView", "UI/FishingHud/PowerMeter/Root", "UI/FishingHud/PowerMeter/DepthMeter"]:
		_bottom_anchor(game.get_node_or_null(path) as Control)
	var info := game.get_node_or_null("UI/FishingHud/FishingInfoView")
	if info != null:
		if not info.has_meta("mobile_notice_home"):
			info.set_meta("mobile_notice_home", info.exploration_position)
		info.exploration_position = info.get_meta("mobile_notice_home") + Vector2(0, extra_height)

func _adapt_fishing_composition(rig: Node, extra_height: float) -> void:
	var camera := rig.get_node_or_null("Camera3D") as Camera3D
	var pose := rig.get_node_or_null("FishingCameraPose") as Camera3D
	if camera == null or pose == null:
		return
	if not rig.has_meta("mobile_desktop_camera_distance"):
		rig.set_meta("mobile_desktop_camera_distance", camera.position.length())
	var original: Dictionary = camera.get_meta("mobile_original_projection")
	var desktop := Projection.create_perspective(original.fov, 640.0 / 480.0, camera.near, camera.far, original.aspect == Camera3D.KEEP_WIDTH)
	var view := pose.transform
	view.origin *= float(rig.get_meta("mobile_desktop_camera_distance")) * rig.fishing_distance_scale / view.origin.length()
	view.origin += view.basis.x * rig.fishing_h_offset + view.basis.y * rig.fishing_v_offset
	var feet := view.affine_inverse() * Vector3.ZERO
	var clip := desktop * Vector4(feet.x, feet.y, feet.z, 1)
	var desktop_y := (1.0 - clip.y / clip.w) * 0.5
	# KEEP_WIDTH adds equal vertical space above/below. Shift composition by
	# the additional pixels needed to retain the authored normalized foot Y.
	rig.mobile_fishing_vertical_offset = extra_height * (desktop_y - 0.5) * 2.0 * (-feet.z) / (480.0 * desktop.y.y)
	rig.set_meta("mobile_desktop_foot_y", desktop_y)

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
		if event is InputEventScreenTouch and event.pressed and scrolling and Rect2(gameplay_image.position, gameplay_image.size).has_point(event.position):
			_window_touches[event.index] = true
		if _window_touches.has(event.index):
			var local_event = event.duplicate()
			local_event.position = (event.position - gameplay_image.position) * Vector2(gameplay_viewport.size) / gameplay_image.size
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
			for view in layer.find_children("ResponsiveMenuSurface", "Control", true, false):
				view.restore_authored()
				view.free()
			var fitter: Node = layer.get_node_or_null("MobilePlaytestWindow")
			if fitter != null:
				fitter.surface.position = fitter.original_position
				fitter.bar.free()
				fitter.free()
			if layer.has_meta("development_status"): layer.custom_viewport = null
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
