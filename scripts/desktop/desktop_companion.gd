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
const SHELL_COLOR := Color("1f1f1f") # only empty desktop space; parchment belongs to bands
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
var _float_release_requested_ms := 0
const FLOAT_ACK_TIMEOUT_MS := 5000
var _dock_drag := false
var _drag_x := 0
var _drag_width := 0
var game: Node
var gameplay_viewport: SubViewport
var menu_viewport: SubViewport
var menu_image: TextureRect
var menu_backdrop: TextureRect
var image: TextureRect
var desktop_hud: Control
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
# Tracks only the placement of an already-owned FishingMenu surface; no menu
# controller or gameplay state is duplicated here.
var _lower_menu_active := false
var _last_menu_state := false
var _last_menu_page := -1
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
	desktop_hud = preload("res://scripts/desktop/desktop_gameplay_hud.gd").new()
	desktop_hud.host = self
	add_child(desktop_hud)
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
	menu_backdrop = TextureRect.new()
	menu_backdrop.name = "AuthoredMenuBackground"
	menu_backdrop.texture = preload("res://assets/ui/fishing_menu/Menu_Background_Solo.png")
	menu_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	menu_backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	menu_backdrop.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	menu_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(menu_backdrop)
	add_child(menu_image)
	menu_backdrop.hide()
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
	get_window().size = Vector2i(800,560)
	get_window().position = usable.position+Vector2i(maxi(0,usable.size.x-get_window().size.x),maxi(0,(usable.size.y-get_window().size.y)/2))
	_float_client_rect = Rect2i(get_window().position,get_window().size)
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
	if is_instance_valid(game):
		# Do not change CanvasLayer.custom_viewport while the old scene is in
		# the tree. Godot connects child_order_changed on ENTER_TREE and
		# disconnects it on EXIT_TREE; changing the viewport in between leaves
		# the old connection behind and produces disconnect errors on free.
		# The layers already own their desired viewports: free them as-is.
		game.free()
	game = packed.instantiate()
	preload("res://scripts/ui/canonical_game_surface.gd").prepare(game)
	gameplay_viewport.add_child(game)
	var exploration_hud: Node = game.get_node_or_null("UI/ExplorationHud")
	if exploration_hud != null: exploration_hud.call("set_desktop_replacement_enabled", true)
	desktop_hud.call("bind_game", game)
	_bind_session_layers()
	_bind_menu_layers()
	_fit_desktop_debug_overlays()
	# Match the projection to the initial world canvas once the game exists.
	_layout()
func _node_added(node: Node) -> void:
	if node is CanvasLayer:
		_bind_session_layers.call_deferred()
		_bind_menu_layers.call_deferred()
		_fit_desktop_debug_overlays.call_deferred()
func _bind_canvas_layer_to_viewport(layer: CanvasLayer, target: Viewport) -> void:
	# set_custom_viewport() changes the active viewport immediately, but does
	# not reconnect the parent's child_order_changed callback. Assign only
	# while the layer is outside SceneTree; ENTER_TREE then binds correctly.
	if not is_instance_valid(layer) or not is_instance_valid(target): return
	if layer.custom_viewport == target: return
	var parent := layer.get_parent()
	if parent == null or not layer.is_inside_tree():
		layer.custom_viewport = target
		return
	var old_index := layer.get_index()
	var old_owner := layer.owner
	parent.remove_child(layer)
	layer.custom_viewport = target
	parent.add_child(layer)
	parent.move_child(layer, old_index)
	layer.owner = old_owner
func _bind_session_layers() -> void:
	var session := get_node_or_null("/root/FishingSessionServices")
	if session == null: return
	for layer in session.find_children("*","CanvasLayer",true,false):
		# The Shift+F10 guide is owned by the persistent session's QA
		# controller. Never reparent it: replacing a desktop gameplay scene
		# would orphan or destroy the controller's modal. Render it into the
		# desktop window without changing its owner in the scene tree.
		if layer.name == "PlayableCampaignQAGuide":
			# Session-owned guide must stay in the session tree, but draw over
			# the real desktop window, not the rescaled gameplay SubViewport.
			_bind_canvas_layer_to_viewport(layer, get_viewport())
			continue
		if not _bound_layers.has(layer.get_instance_id()): _bound_layers[layer.get_instance_id()] = {"node":weakref(layer),"parent":weakref(layer.get_parent())}
		if layer.get_parent() != gameplay_viewport: layer.reparent(gameplay_viewport)
func _bind_menu_layers() -> void:
	if not is_instance_valid(game) or menu_viewport == null: return
	var fishing_menu := _fishing_menu()
	if fishing_menu != null: fishing_menu.set_meta("desktop_companion_mode",true)
	for layer in gameplay_viewport.find_children("*","CanvasLayer",true,false):
		# Shift+F10 is a gameplay-view modal, NOT an authored J-menu.
		# Sending it to the 640x864 menu SubViewport clips/offsets it and
		# separates its display from the viewport that owns its input.
		if layer.name in ["PlayableCampaignQAGuide", "FishingDebugMenu"]:
			# QA menus are window-level modals; the J-menu alone is rendered
			# through MenuViewport. Otherwise F10 clips in 640x864 and
			# Shift+F10 vanishes on some desktop window sizes.
			_bind_canvas_layer_to_viewport(layer, get_viewport())
			continue
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

func _fit_desktop_debug_overlays() -> void:
	# Both debug menus own authored ~620 px panels. Keep their CanvasLayers
	# on the actual desktop window and fit only their panels; the gameplay
	# and J-menu SubViewports retain their existing independent sizes.
	var canvas_size := Vector2(get_window().size)
	if is_instance_valid(game):
		for layer in gameplay_viewport.find_children("*", "CanvasLayer", true, false):
			if layer.name == "FishingDebugMenu":
				_bind_canvas_layer_to_viewport(layer, get_viewport())
				if layer.has_method("fit_desktop_overlay"):
					layer.call("fit_desktop_overlay", canvas_size)
	var session := get_node_or_null("/root/FishingSessionServices")
	if session != null:
		for layer in session.find_children("*", "CanvasLayer", true, false):
			if layer.name == "PlayableCampaignQAGuide":
				_bind_canvas_layer_to_viewport(layer, get_viewport())
				if layer.has_method("fit_desktop_overlay"):
					layer.call("fit_desktop_overlay", canvas_size)

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
	# Save a real floating rectangle BEFORE the native AppBar changes it.
	# Dock/widget geometry must never overwrite the remembered float size.
	if window_state == WindowState.FLOATING and current_rect.has_area() and not get_window().borderless:
		_float_client_rect = current_rect
	window_state = next
	_expanded_state = next
	_pending_float_decoration = false
	_float_release_requested_ms = 0
	if docked: get_window().borderless = true
	# Decoration changes occur only on mode transitions. The native adapter
	# owns all dock/widget rectangles; resizing never toggles decoration.
	if docked:
		_apply_dock_size()
	else:
		if not _float_client_rect.has_area():
			_float_client_rect = Rect2i(current_rect.position,Vector2i(800,560))
		_floating_restore_rect = _float_client_rect
		_pending_float_decoration = true
		_float_release_requested_ms = Time.get_ticks_msec()
		# Request release *with* the pre-dock float rectangle so the helper and
		# Godot restore the same geometry, never the present dock rectangle.
		var error: Error = platform.request(false,get_window(),"right",Vector2i.ZERO,false,_floating_restore_rect)
		if error != OK:
			status.text = error_string(error)
			_request_pending = true
		else:
			_request_pending = false
			_floating_restore_rect = Rect2i()
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
				_float_release_requested_ms = Time.get_ticks_msec()
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
	if window_state == WindowState.COLLAPSED: return Vector2i(collapsed_width,WIDGET_HEIGHT)
	# Native AppBar negotiation owns the final rectangle. Never reserve a full
	# edge while requesting a content-height window within that reservation.
	var usable := DisplayServer.screen_get_usable_rect(get_window().current_screen)
	return Vector2i(dock_width,maxi(1,usable.size.y))
func _apply_dock_size() -> void:
	_request_pending = true
func _on_resize() -> void:
	# An ordinary floating-window resize becomes the next dock -> float target.
	if window_state == WindowState.FLOATING and not _pending_float_decoration and not get_window().borderless and get_window().mode == Window.MODE_WINDOWED:
		var rect := Rect2i(get_window().position,get_window().size)
		if rect.has_area(): _float_client_rect = rect
	_layout()
	# Native acknowledgements are outputs, never new width commands.
func _divider_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dock_drag = event.pressed
		_drag_x = DisplayServer.mouse_get_position().x
		_drag_width = dock_width
func _process(delta: float) -> void:
	# The menu's own controller emits/owns its navigation. Reconfigure only
	# when its visibility changes; do not resize or move the world every frame.
	var fishing_menu := _fishing_menu()
	var menu_open := fishing_menu != null and fishing_menu.is_open()
	var menu_page := int(fishing_menu._page) if menu_open else -1
	# Changing Equip/Data/Options also changes the right-sized presentation;
	# no world camera or gameplay state is recomputed except at real resize.
	if menu_open != _last_menu_state or menu_page != _last_menu_page:
		_last_menu_state = menu_open
		_last_menu_page = menu_page
		_layout()
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
	if _pending_float_decoration:
		if state.get("sequence",-1) == platform.sequence and not state.get("registered",false):
			_restore_float_decoration()
		elif _float_release_requested_ms > 0 and Time.get_ticks_msec()-_float_release_requested_ms > FLOAT_ACK_TIMEOUT_MS:
			push_warning("Floating AppBar release acknowledgement timed out; restoring title bar locally. Check Windows reservation.")
			_restore_float_decoration()
	if docked and not str(state.get("error","")).is_empty():
		status.text = str(state.error)
		set_window_state(WindowState.FLOATING)
	_layout()
func _restore_float_decoration() -> void:
	# Release AppBar first: a normal decorated window inside the old reserved
	# work area can otherwise be relocated by Windows during the transition.
	_pending_float_decoration = false
	_float_release_requested_ms = 0
	get_window().borderless = false
	get_window().unresizable = false
	get_window().min_size = Vector2i(min_dock_width,400)
	if _float_client_rect.has_area():
		get_window().size = _float_client_rect.size
		get_window().position = _float_client_rect.position
	if _pending_shell_fullscreen:
		_pending_shell_fullscreen = false
		get_window().mode = Window.MODE_MAXIMIZED
func _layout() -> void:
	if image == null or keyboard_strip == null: return
	var collapsed := window_state == WindowState.COLLAPSED
	shell_fill.size = Vector2(get_window().size)
	var geometry := preload("res://scripts/ui/seaside_shell_layout.gd").desktop(Vector2(get_window().size),gameplay_viewport.size,docked,_world_shape_locked() or collapsed)
	shell.size = Vector2(get_window().size)
	shell.visible = not collapsed
	Surface.resize_mobile_world(game,gameplay_viewport,geometry.resolution)
	_sync_extended_camera_projection(geometry.resolution)
	if is_instance_valid(game): preload("res://scripts/mobile/mobile_world_ground_extension.gd").ensure(game,geometry.resolution.x == 960)
	# A lower contextual menu is possible only when both its width and its
	# height are useful. Short/small windows retain the established overlay.
	_lower_menu_active = _is_fishing_menu_open() and bool(geometry.lower_menu_available) and not collapsed
	geometry["context_menu"] = _lower_menu_active
	shell.configure(geometry)
	image.position = geometry.world.position
	image.size = geometry.world.size
	image.visible = not collapsed
	desktop_hud.position = geometry.world.position
	desktop_hud.size = geometry.world.size
	desktop_hud.visible = not collapsed and not _is_fishing_menu_open()
	if _is_fishing_menu_open() and not collapsed:
		var menu_rect: Rect2 = geometry.menu if _lower_menu_active else geometry.world
		var active_menu := _fishing_menu()
		var authored := active_menu != null and active_menu._page != FishingMenu.Page.OPTIONS
		var target_size := Vector2i(640,480) if authored else Surface.MENU_SIZE
		if menu_viewport.size != target_size: menu_viewport.size = target_size
		# The real J-menu Background is separately stretched to cover the host.
		# Individual authored subpanels stay at their original proportions.
		if active_menu != null:
			var native_background := active_menu.get_node_or_null("Root/Background") as CanvasItem
			if native_background != null: native_background.hide()
		menu_backdrop.visible = authored
		menu_backdrop.position = menu_rect.position
		menu_backdrop.size = menu_rect.size
		menu_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		menu_image.position = menu_rect.position
		menu_image.size = menu_rect.size
	else:
		var closed_menu := _fishing_menu()
		if closed_menu != null:
			var background := closed_menu.get_node_or_null("Root/Background") as CanvasItem
			if background != null: background.show()
		menu_backdrop.hide()
		if menu_viewport.size != Surface.MENU_SIZE: menu_viewport.size = Surface.MENU_SIZE
		menu_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		menu_image.position = Vector2.ZERO
		menu_image.size = Vector2(get_window().size)
	menu_image.visible = not collapsed
	keyboard_strip.hide()
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
	_fit_desktop_debug_overlays()
	divider.visible = docked and not collapsed
	divider.position = Vector2(0 if effective_window_state() == WindowState.DOCK_RIGHT else get_window().size.x-8,geometry.toolbar.size.y)
	divider.size = Vector2(8,maxi(1,get_window().size.y-geometry.toolbar.size.y))
# Every floating size uses one consistent horizontal world-density rule.
# Gradually increase/decrease vertical camera coverage with the actual
# SubViewport height rather than flipping between 960x480 and 960x720.
# The standard 640x480 dock remains at its original authored camera lens.
func _sync_extended_camera_projection(resolution: Vector2i) -> void:
	if not is_instance_valid(game): return
	for item in game.find_children("*", "Camera3D", true, false):
		var camera := item as Camera3D
		if camera == null: continue
		if not camera.has_meta("desktop_base_projection"):
			camera.set_meta("desktop_base_projection", {"fov": camera.fov, "aspect": camera.keep_aspect})
		var baseline: Dictionary = camera.get_meta("desktop_base_projection")
		if camera.keep_aspect != baseline.aspect:
			camera.keep_aspect = baseline.aspect
		var target_fov: float = float(baseline.fov)
		if resolution.x == 960 and int(baseline.aspect) == Camera3D.KEEP_HEIGHT:
			var half_angle: float = deg_to_rad(target_fov) * 0.5
			target_fov = rad_to_deg(2.0*atan(tan(half_angle)*float(resolution.y)/480.0))
		if not is_equal_approx(camera.fov, target_fov):
			camera.fov = target_fov
		# World rendering can grow vertically, but home-camera composition is
		# bottom-anchored rather than centered inside the extra world height.
		# Only the active rig camera may own this; reference/pose cameras don't.
		if camera.current and camera.get_parent().has_method("set_desktop_vertical_composition_height"):
			camera.get_parent().call("set_desktop_vertical_composition_height", resolution.y)

func _input(event: InputEvent) -> void:
	if menu_image != null and menu_image.is_visible_in_tree():
		var display := Rect2(menu_image.global_position,menu_image.size)
		if menu_image.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED:
			var factor := minf(menu_image.size.x/menu_viewport.size.x,menu_image.size.y/menu_viewport.size.y)
			var footprint := Vector2(menu_viewport.size)*factor
			display = Rect2(menu_image.global_position+(menu_image.size-footprint)*.5,footprint)
		if preload("res://scripts/input/controls_settings.gd").route_pointer(self,event,display,display): return
	if get_node("/root/InputBindings").capture_action != &"": return
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
	if (event is InputEventKey or event is InputEventAction or event is InputEventJoypadButton or event is InputEventJoypadMotion) and not _forwarding and mode == Mode.ACTIVE:
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
	var factor := minf(image.size.x / gameplay_viewport.size.x, image.size.y / gameplay_viewport.size.y)
	var footprint := Vector2(gameplay_viewport.size) * factor
	return Rect2(image.position + (image.size-footprint)*0.5, footprint)

func request_shell_menu(id: String) -> void:
	preload("res://scripts/ui/seaside_shell_actions.gd").request(self,id)

func toggle_shell_fullscreen() -> void:
	if docked:
		_pending_shell_fullscreen = true
		set_window_state(WindowState.FLOATING)
	else:
		get_window().mode = Window.MODE_WINDOWED if get_window().mode in [Window.MODE_MAXIMIZED,Window.MODE_FULLSCREEN] else Window.MODE_MAXIMIZED

func dock_from_shell(next: int) -> void:
	if get_window().mode in [Window.MODE_FULLSCREEN,Window.MODE_MAXIMIZED]:
		get_window().mode = Window.MODE_WINDOWED
		set_window_state.call_deferred(next)
	else:
		set_window_state(next)

func _world_shape_locked() -> bool:
	var fishing := game.get_node_or_null("Game/Fishing") if is_instance_valid(game) else null
	return fishing != null and fishing.game_mode != null and fishing.game_mode.is_fishing()

func _fishing_menu() -> FishingMenu:
	if not is_instance_valid(game): return null
	return game.find_child("FishingMenu",true,false) as FishingMenu

func _is_fishing_menu_open() -> bool:
	var fishing_menu := _fishing_menu()
	return fishing_menu != null and fishing_menu.is_open()

func _has_surface_modal() -> bool:
	if not is_instance_valid(game): return false
	for layer in gameplay_viewport.find_children("*","CanvasLayer",true,false):
		if layer.has_method("is_open") and layer.is_open(): return true
	return get_tree().paused
