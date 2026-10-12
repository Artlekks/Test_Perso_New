extends PanelContainer
## Scene-local editor for the global InputMap preference service.
var service: UniversalInput
var rows: Dictionary = {}
var message: Label
var index := 0
var scroller: ScrollContainer
var pointer_touch := -1
var pointer_mouse := false
var pointer_start := Vector2.ZERO
var pointer_last_y := 0.0
var pointer_scrolling := false
func _ready() -> void:
	service=get_node("/root/InputBindings")
	add_to_group("controls_settings_editors")
	var skin := StyleBoxTexture.new(); skin.texture=preload("res://assets/ui/seaside_shell/panel.png")
	for side in range(4): skin.set_texture_margin(side,8)
	add_theme_stylebox_override("panel",skin)
	var column := VBoxContainer.new(); add_child(column)
	message=Label.new(); message.text="Controls / Keybindings"
	message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	message.add_theme_font_size_override("font_size",24)
	message.add_theme_color_override("font_color",Color("35202d")); column.add_child(message)
	scroller=ScrollContainer.new(); scroller.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroller.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; column.add_child(scroller)
	var list := VBoxContainer.new(); list.size_flags_horizontal=Control.SIZE_EXPAND_FILL; scroller.add_child(list)
	for action in service.DEFINITIONS:
		var button := Button.new(); button.custom_minimum_size.y=96
		button.focus_mode=Control.FOCUS_NONE; button.add_theme_font_size_override("font_size",24)
		var button_skin := StyleBoxTexture.new(); button_skin.texture=preload("res://assets/ui/seaside_shell/button.png")
		for side in range(4): button_skin.set_texture_margin(side,8)
		for style in ["normal","hover","pressed"]: button.add_theme_stylebox_override(style,button_skin)
		button.add_theme_color_override("font_color",Color("fff0bd"))
		button.text=service.DEFINITIONS[action].label
		button.pressed.connect(func():
			if pointer_scrolling: return
			index=rows.keys().find(action)
			service.begin_capture(action,self))
		list.add_child(button); rows[action]=button
	var footer := HBoxContainer.new(); column.add_child(footer)
	for caption in ["Defaults","Cancel capture"]:
		var button := Button.new(); button.text=caption; button.focus_mode=Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size",24)
		var footer_skin := StyleBoxTexture.new(); footer_skin.texture=preload("res://assets/ui/seaside_shell/button.png")
		for side in range(4): footer_skin.set_texture_margin(side,8)
		for style in ["normal","hover","pressed"]: button.add_theme_stylebox_override(style,footer_skin)
		button.add_theme_color_override("font_color",Color("fff0bd"))
		button.custom_minimum_size.y=96; button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		footer.add_child(button)
		if caption == "Defaults": button.pressed.connect(func(): service.reset_defaults())
		else: button.pressed.connect(service.cancel_capture)
	service.bindings_changed.connect(refresh); service.capture_changed.connect(refresh)
	get_window().focus_exited.connect(_reset_pointer)
	visibility_changed.connect(func():
		if is_visible_in_tree(): scroller.scroll_vertical=0; index=0
		else: _reset_pointer()
		if not is_visible_in_tree() and service.capture_owner != null and service.capture_owner.get_ref() == self: service.cancel_capture())
	refresh()
func refresh() -> void:
	message.text="Controls: "+service.status
	for action in rows:
		rows[action].text=("> " if rows.keys()[index] == action else "")+"%s : %s" % [service.DEFINITIONS[action].label,service.key_name(action)]
		rows[action].modulate=Color(1,.8,.65) if service.capture_action == action else Color.WHITE
func handle(event: InputEvent) -> void:
	if service.capture_action != &"": return
	var actions := rows.keys()
	if event.is_action_pressed("move_forward"): index=posmod(index-1,actions.size())
	elif event.is_action_pressed("move_back"): index=posmod(index+1,actions.size())
	elif event.is_action_pressed("enter_fishing"):
		service.begin_capture(actions[index],self); return
	else: return
	refresh()
	scroller.ensure_control_visible(rows[actions[index]])
func _exit_tree() -> void:
	if is_instance_valid(service) and service.capture_owner != null and service.capture_owner.get_ref() == self: service.cancel_capture()

static func route_pointer(host: Node, event: InputEvent, display: Rect2, clip: Rect2) -> bool:
	if not display.has_area(): return false
	if not (event is InputEventMouseButton or event is InputEventMouseMotion or event is InputEventScreenTouch or event is InputEventScreenDrag): return false
	for pane in host.get_tree().get_nodes_in_group("controls_settings_editors"):
		if pane.is_visible_in_tree() and pane.get_viewport() == host.gameplay_viewport:
			if pane._pointer(event,display,clip):
				host.get_viewport().set_input_as_handled(); return true
	return false

func _pointer(event: InputEvent, display: Rect2, clip: Rect2) -> bool:
	var point: Vector2 = event.position
	var owned := pointer_touch >= 0 or pointer_mouse
	if not owned and not clip.has_point(point): return false
	# Preserve the approved outer-menu scroll gutter on mobile.
	if event is InputEventScreenTouch and pointer_touch < 0 and point.x >= display.end.x-20: return false
	if event is InputEventScreenDrag and pointer_touch < 0: return false
	if (event is InputEventMouseButton or event is InputEventMouseMotion) and event.device == InputEvent.DEVICE_ID_EMULATION:
		return true # Original touch is emulated once in the owning GUI viewport.
	var layer: CanvasLayer = get_parent().controller
	var canvas: Viewport = layer.custom_viewport if layer.custom_viewport != null else get_viewport()
	var units := canvas.get_visible_rect().size
	var logical: Vector2 = (point-display.position)*units/display.size
	var forwarded: InputEvent
	if event is InputEventScreenTouch:
		if pointer_touch >= 0 and pointer_touch != event.index: return true
		if event.pressed:
			pointer_touch=event.index; pointer_start=logical; pointer_last_y=logical.y; pointer_scrolling=false
		elif pointer_touch != event.index: return true
		if not event.pressed and pointer_scrolling:
			pointer_touch=-1; pointer_scrolling=false; return true
		var mouse := InputEventMouseButton.new()
		mouse.device=InputEvent.DEVICE_ID_EMULATION; mouse.position=logical
		mouse.button_index=MOUSE_BUTTON_LEFT; mouse.pressed=event.pressed
		mouse.button_mask=MOUSE_BUTTON_MASK_LEFT if event.pressed else 0
		forwarded=mouse
		if not event.pressed: pointer_touch=-1
	elif event is InputEventScreenDrag:
		if event.index != pointer_touch: return true
		if not pointer_scrolling and scroller.get_global_rect().has_point(pointer_start) and absf(logical.y-pointer_start.y)>12:
			# Cancel the pending native button click, then give this gesture to
			# the list. This works equally on mouse-only QA hosts and phones.
			pointer_scrolling=true
			var outside := InputEventMouseMotion.new(); outside.position=Vector2(-1,-1); outside.button_mask=MOUSE_BUTTON_MASK_LEFT
			get_viewport().push_input(outside,true)
			var cancel := InputEventMouseButton.new(); cancel.button_index=MOUSE_BUTTON_LEFT; cancel.position=Vector2(-1,-1)
			get_viewport().push_input(cancel,true)
		if pointer_scrolling:
			scroller.scroll_vertical += roundi(pointer_last_y-logical.y)
			pointer_last_y=logical.y; return true
		pointer_last_y=logical.y
		var mouse := InputEventMouseMotion.new()
		mouse.device=InputEvent.DEVICE_ID_EMULATION; mouse.position=logical
		mouse.relative=event.relative*units/display.size
		mouse.button_mask=MOUSE_BUTTON_MASK_LEFT; forwarded=mouse
	else:
		forwarded=event.duplicate(); forwarded.position=logical
		if event is InputEventMouseMotion: forwarded.relative=event.relative*units/display.size
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT: pointer_mouse=event.pressed
	# custom_viewport changes rendering, not the Node's GUI input owner.
	get_viewport().push_input(forwarded,true)
	return true


func _reset_pointer() -> void:
	if pointer_touch < 0 and not pointer_mouse: return
	var release_needed := pointer_mouse or not pointer_scrolling
	pointer_touch=-1; pointer_mouse=false; pointer_scrolling=false
	if is_inside_tree() and release_needed and is_instance_valid(get_viewport()) and not get_viewport().is_queued_for_deletion():
		var release := InputEventMouseButton.new()
		release.button_index=MOUSE_BUTTON_LEFT; release.position=Vector2(-1,-1)
		get_viewport().push_input(release,true)

