extends HBoxContainer
## Compact, rearrangeable gameplay controls. One press/release through the same
## bound-key/InputMap route as hardware; no gameplay commands live here.
var host: Node
var held: Dictionary = {}
var buttons: Dictionary = {}
var _modal := false
const KEYS := [KEY_I,KEY_J,KEY_K,KEY_C,KEY_Q,KEY_E]
func _ready() -> void:
	z_index=22; process_mode=Node.PROCESS_MODE_ALWAYS
	add_theme_constant_override("separation",3)
	for key in KEYS:
		var button := Button.new(); button.focus_mode=Control.FOCUS_NONE
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size",14)
		var skin := StyleBoxTexture.new(); skin.texture=preload("res://assets/ui/seaside_shell/button.png")
		for side in range(4): skin.set_texture_margin(side,6)
		for style in ["normal","hover","pressed"]: button.add_theme_stylebox_override(style,skin)
		button.add_theme_color_override("font_color",Color("fff0bd"))
		button.tooltip_text={KEY_I:"Back",KEY_J:"Main menu",KEY_K:"Confirm / Cast / Hold to reel",KEY_C:"Cards",KEY_Q:"Left shoulder",KEY_E:"Right shoulder"}[key]
		button.button_down.connect(press.bind(key)); button.button_up.connect(release.bind(key))
		add_child(button); buttons[key]=button
	get_node("/root/InputBindings").bindings_changed.connect(_bindings_changed)
	get_node("/root/InputBindings").capture_changed.connect(_capture_changed)
	get_window().focus_exited.connect(release_all)
	_bindings_changed()
func _bindings_changed() -> void:
	release_all()
	var service: UniversalInput = get_node("/root/InputBindings")
	for key in buttons: buttons[key].text=service.key_name(UniversalInput.action_for_default(key))
func press(key: int) -> void:
	if held.has(key): return
	var event := UniversalInput.event_for_key(key,true); held[key]=event
	Input.parse_input_event(event)
func release(key: int) -> void:
	if not held.has(key): return
	var event: InputEventKey = held[key].duplicate(); held.erase(key)
	event.pressed=false; Input.parse_input_event(event)
func release_all() -> void:
	for key in held.keys(): release(key)
func _process(_delta: float) -> void:
	if not is_visible_in_tree(): release_all(); return
	var modal: bool = host._has_surface_modal()
	if modal != _modal: release_all(); _modal=modal
func _exit_tree() -> void:
	release_all()

func _capture_changed() -> void:
	if get_node("/root/InputBindings").capture_action != &"": release_all()
