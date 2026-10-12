extends Node
class_name UniversalInput
## InputMap owns gameplay bindings. This service owns only keyboard preferences
## and capture; aliases are explicit mutually-exclusive gameplay/UI contexts.
signal bindings_changed
signal capture_changed
const PATH := "user://input_bindings.json"
const DEFINITIONS := {
	&"move_forward":{"label":"Move up / Navigate up","key":KEY_W,"aliases":[&"move_forward",&"ui_up"]},
	&"move_left":{"label":"Move / Steer left","key":KEY_A,"aliases":[&"move_left",&"ds_left",&"ui_left"]},
	&"move_back":{"label":"Move down / Navigate down","key":KEY_S,"aliases":[&"move_back",&"ui_down"]},
	&"move_right":{"label":"Move / Steer right","key":KEY_D,"aliases":[&"move_right",&"ds_right",&"ui_right"]},
	&"enter_fishing":{"label":"Confirm / Primary","key":KEY_K,"aliases":[&"enter_fishing"]},
	&"cancel_fishing":{"label":"Cancel / Back","key":KEY_I,"aliases":[&"cancel_fishing"]},
	&"main_menu":{"label":"Main menu / Card details","key":KEY_J,"aliases":[&"main_menu"]},
	&"world_card_challenge":{"label":"Cards / Contextual","key":KEY_C,"aliases":[&"world_card_challenge"]},
	&"cam_right":{"label":"Left shoulder / Camera-page","key":KEY_Q,"aliases":[&"cam_right",&"shoulder_left"]},
	&"cam_left":{"label":"Right shoulder / Camera-page","key":KEY_E,"aliases":[&"cam_left",&"shoulder_right"]},
	&"lure_menu":{"label":"Lure menu / Save deck","key":KEY_L,"aliases":[&"lure_menu"]}
}
static var _hint_pattern: RegEx
var bindings: Dictionary = {}
var capture_action: StringName = &""
var status := "Select an action. Escape cancels capture."
var store_path := PATH
var capture_owner: WeakRef
var _blocked: Dictionary = {}

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	for definition in DEFINITIONS.values():
		for action in definition.aliases:
			if not InputMap.has_action(action): InputMap.add_action(action)
	load_preferences()

static func action_for_default(key: int) -> StringName:
	for action in DEFINITIONS:
		if DEFINITIONS[action].key == key: return action
	return &""

static func matches_key(event: InputEvent, key: int) -> bool:
	var action := action_for_default(key)
	if action != &"": return event.is_action(action)
	return event is InputEventKey and (event.keycode == key or event.physical_keycode == key)

static func event_for_key(key: int, pressed: bool) -> InputEventKey:
	var action := action_for_default(key)
	var physical := key
	if action != &"":
		for binding in InputMap.action_get_events(action):
			if binding is InputEventKey:
				physical=binding.physical_keycode if binding.physical_keycode else binding.keycode
				break
	var event := InputEventKey.new()
	event.physical_keycode=physical; event.keycode=physical; event.pressed=pressed
	event.set_meta("canonical_key",key)
	return event

func key_name(action: StringName) -> String:
	return OS.get_keycode_string(int(bindings.get(action,DEFINITIONS[action].key)))

func defaults() -> Dictionary:
	var result := {}
	for action in DEFINITIONS: result[action]=DEFINITIONS[action].key
	return result

func conflict(action: StringName, key: int, candidate: Dictionary = {}) -> String:
	if candidate.is_empty(): candidate=bindings
	if not DEFINITIONS.has(action): return "Unknown action"
	# Fixed deck/debug/pause/navigation commands are not silently reassigned.
	if key < KEY_A or key > KEY_Z or key in [KEY_R,KEY_T]: return "Use a letter key; R/T and fixed navigation/debug keys are reserved."
	for other in candidate:
		if other != action and candidate[other] == key: return "Already assigned to "+DEFINITIONS[other].label
	return ""

func _apply() -> void:
	for action in DEFINITIONS:
		for alias in DEFINITIONS[action].aliases:
			Input.action_release(alias)
			var retained := _retained_events(alias)
			InputMap.action_erase_events(alias)
			for event in retained: InputMap.action_add_event(alias,event)
			var event := InputEventKey.new(); event.physical_keycode=bindings[action]
			InputMap.action_add_event(alias,event)
	bindings_changed.emit()

func rebind(action: StringName, key: int, persist := true) -> bool:
	status=conflict(action,key)
	if not status.is_empty(): capture_changed.emit(); return false
	var next := bindings.duplicate(); next[action]=key
	if persist and not _commit(next):
		status="Could not save bindings; previous mapping kept."; capture_changed.emit(); return false
	bindings=next; _apply(); status="Binding saved."; capture_changed.emit(); return true

func reset_defaults(persist := true) -> bool:
	var next := defaults()
	if persist and not _commit(next):
		status="Could not save defaults; previous mappings kept."; capture_changed.emit(); return false
	bindings=next; cancel_capture(); _apply(); return true

func _commit(next: Dictionary) -> bool:
	var file := FileAccess.open(store_path+".tmp",FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify({"version":1,"bindings":next})); file.flush(); file.close()
	if _read(store_path+".tmp").is_empty(): return false
	if FileAccess.file_exists(store_path):
		if _read(store_path).is_empty():
			if DirAccess.remove_absolute(store_path) != OK: return false
		else:
			if FileAccess.file_exists(store_path+".bak") and DirAccess.remove_absolute(store_path+".bak") != OK: return false
			if DirAccess.rename_absolute(store_path,store_path+".bak") != OK: return false
	if DirAccess.rename_absolute(store_path+".tmp",store_path) == OK: return true
	if FileAccess.file_exists(store_path+".bak"): DirAccess.rename_absolute(store_path+".bak",store_path)
	return false

func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK: return {}
	var payload = parser.data
	if not payload is Dictionary or payload.get("version",0) != 1 or not payload.get("bindings") is Dictionary: return {}
	var next := defaults()
	for action in DEFINITIONS:
		var value = payload.bindings.get(String(action),next[action])
		if not value is int and not value is float: return {}
		if float(value) != int(value): return {}
		next[action]=int(value)
	for action in next:
		if not conflict(action,next[action],next).is_empty(): return {}
	return next

func load_preferences() -> void:
	var loaded := _read(store_path)
	if loaded.is_empty(): loaded=_read(store_path+".bak")
	bindings=defaults() if loaded.is_empty() else loaded
	if FileAccess.file_exists(store_path) and _read(store_path).is_empty(): push_warning("Input bindings invalid; using validated backup or defaults.")
	_apply()

func begin_capture(action: StringName, owner_node: Node = null) -> void:
	if not DEFINITIONS.has(action): return
	for bound_action in bindings:
		if Input.is_physical_key_pressed(bindings[bound_action]): _blocked[bindings[bound_action]]=true
		for alias in DEFINITIONS[bound_action].aliases: Input.action_release(alias)
	capture_owner=weakref(owner_node) if owner_node != null else null
	capture_action=action; status="Waiting for a letter key for "+DEFINITIONS[action].label+". Escape cancels."
	capture_changed.emit()

func cancel_capture() -> void:
	capture_owner=null
	capture_action=&""; status="Capture cancelled."; capture_changed.emit()

func _process(_delta: float) -> void:
	if capture_action != &"" and capture_owner != null and not is_instance_valid(capture_owner.get_ref()): cancel_capture()

func _input(event: InputEvent) -> void:
	if capture_action != &"" and (event is InputEventAction or event is InputEventJoypadButton or event is InputEventJoypadMotion):
		_release_event_actions(event)
		if event.is_pressed() and event.is_action("cancel_fishing"): cancel_capture()
		get_viewport().set_input_as_handled(); return
	if event is InputEventKey:
		var key: int = event.physical_keycode if event.physical_keycode else event.keycode
		if _blocked.has(key):
			_release_event_actions(event)
			if not event.pressed: _blocked.erase(key)
			get_viewport().set_input_as_handled(); return
		if capture_action != &"":
			_release_event_actions(event)
			get_viewport().set_input_as_handled()
			if not event.pressed or event.echo: return
			_blocked[key]=true
			if key == KEY_ESCAPE or event.get_meta("canonical_key",0) == KEY_I: cancel_capture(); return
			if event.has_meta("canonical_key"):
				status="Choose with a keyboard; touch can cancel capture or restore defaults."; capture_changed.emit(); return
			if event.ctrl_pressed or event.alt_pressed or event.meta_pressed or event.shift_pressed:
				status="Use an unmodified letter key."; capture_changed.emit(); return
			if rebind(capture_action,key):
				capture_action=&""; capture_owner=null
			capture_changed.emit()

func _release_event_actions(event: InputEvent) -> void:
	# Consuming dispatch alone does not clear Input's polling state. A captured
	# key must not remain held when the modal owner subsequently closes.
	for definition in DEFINITIONS.values():
		for action in definition.aliases:
			if event.is_action(action): Input.action_release(action)

func consume_virtual_action(event: InputEventAction) -> bool:
	if capture_action == &"": return false
	_release_event_actions(event)
	if event.pressed and event.action == &"cancel_fishing": cancel_capture()
	return true

func _retained_events(action: StringName) -> Array[InputEvent]:
	var result: Array[InputEvent] = []
	var navigation := {&"ui_up":KEY_UP,&"ui_down":KEY_DOWN,&"ui_left":KEY_LEFT,&"ui_right":KEY_RIGHT}
	for event in InputMap.action_get_events(action):
		if not event is InputEventKey: result.append(event)
		elif navigation.has(action) and (event.physical_keycode == navigation[action] or event.keycode == navigation[action]): result.append(event)
	return result

static func format_action_hints(text: String) -> String:
	# Only explicit action captions; never reinterpret card stats or prose.
	if not (text.begins_with("K:") or text.begins_with("I:") or text.begins_with("J:") or text.begins_with("C:")): return text
	if _hint_pattern == null:
		_hint_pattern=RegEx.new(); _hint_pattern.compile("[KIJC]:|Q/E|WASD")
	var matches := _hint_pattern.search_all(text); matches.reverse()
	for match_result in matches:
		var token: String = match_result.get_string()
		var codes: Array = [KEY_Q,KEY_E] if token == "Q/E" else [KEY_W,KEY_A,KEY_S,KEY_D] if token == "WASD" else [token.unicode_at(0)]
		var names: PackedStringArray = []
		for code in codes: names.append(OS.get_keycode_string(event_for_key(code,false).physical_keycode))
		var replacement := "/".join(names) if token == "Q/E" else "".join(names)
		if token.ends_with(":"): replacement += ":"
		text=text.left(match_result.get_start())+replacement+text.substr(match_result.get_end())
	return text
