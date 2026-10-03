extends Node
class_name PlayableCampaignQAController

const GuideScene = preload("res://actors/PlayableCampaignQAGuide.tscn")
const PresetServiceScript = preload(
	"res://scripts/progression/playable_campaign_qa_preset_service.gd"
)

var _services = null
var _director = null
var _guide: CanvasLayer = null
var _preset_service = PresetServiceScript.new()
var _previous_pause: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_unhandled_input(true)


func configure(session_services, progression_director) -> void:
	_services = session_services
	_director = progression_director
	_preset_service.configure(session_services)
	_build_guide()


func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build() or _guide == null:
		return
	if _is_shift_f10(event):
		_toggle()
		_accept_input()
		return
	if bool(_guide.call("is_open")):
		var close_requested: bool = bool(_guide.call("handle_input", event))
		if close_requested:
			_close_guide()
		_accept_input()


func _toggle() -> void:
	if bool(_guide.call("is_open")):
		_close_guide()
		return
	var tree: SceneTree = get_tree()
	_previous_pause = tree.paused if tree != null else false
	_guide.call(
		"open_menu",
		_current_snapshot(),
		_preset_service.get_presets()
	)
	if tree != null:
		tree.paused = true


func _close_guide() -> void:
	if _guide != null:
		_guide.call("close_menu")
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.paused = _previous_pause


func _build_guide() -> void:
	if _guide != null:
		return
	var instance = GuideScene.instantiate()
	if not (instance is CanvasLayer):
		return
	_guide = instance as CanvasLayer
	add_child(_guide)
	_guide.connect("preset_requested", Callable(self, "_on_preset_requested"))
	_guide.connect("refresh_requested", Callable(self, "_on_refresh_requested"))


func _on_refresh_requested() -> void:
	if _guide != null:
		_guide.call("update_snapshot", _current_snapshot())


func _on_preset_requested(preset_id: StringName) -> void:
	var result: Dictionary = _preset_service.apply_preset(preset_id)
	if not bool(result.get("success", false)):
		_guide.call(
			"set_status",
			"Preset FAILED: %s" % str(result.get("reason", "unknown"))
		)
		return
	_guide.call("set_status", "Preset applied. Reloading scene...")
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.paused = false
		tree.reload_current_scene()


func _current_snapshot() -> Dictionary:
	if _director == null or not _director.has_method("get_snapshot"):
		return {}
	return _director.get_snapshot()


func _accept_input() -> void:
	var viewport: Viewport = get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func _is_shift_f10(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false
	var key_event := event as InputEventKey
	return (
		key_event.pressed
		and not key_event.echo
		and key_event.shift_pressed
		and (key_event.keycode == KEY_F10 or key_event.physical_keycode == KEY_F10)
	)
