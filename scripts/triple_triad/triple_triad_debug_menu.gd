extends CanvasLayer

signal apply_requested(selected_profile: Resource)

const QA_PROFILE_DIRECTORY := "res://data/debug/triple_triad_profiles"

@onready var root: Control = $Root
@onready var profile_label: Label = $Root/Panel/ProfileLabel
@onready var region_label: Label = $Root/Panel/RegionLabel
@onready var ai_label: Label = $Root/Panel/AILabel
@onready var budget_label: Label = $Root/Panel/BudgetLabel
@onready var levels_label: Label = $Root/Panel/LevelsLabel
@onready var rules_label: Label = $Root/Panel/RulesLabel
@onready var start_label: Label = $Root/Panel/StartLabel
@onready var purpose_label: Label = $Root/Panel/PurposeLabel
@onready var status_label: Label = $Root/Panel/StatusLabel

var _profiles: Array[Resource] = []
var _profile_index: int = 0
var _current_summary: Dictionary = {}
var _current_override: Resource = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	root.hide()
	_load_profiles()


func open_menu(current_summary: Dictionary, current_override: Resource = null) -> bool:
	if _profiles.is_empty():
		_load_profiles()
	_current_summary = current_summary.duplicate(true)
	_current_override = current_override
	_sync_index_to_override()
	_refresh()
	root.show()
	return true


func close_menu() -> void:
	root.hide()


func is_open() -> bool:
	return root.visible


## Returns true when the overlay should close.
func handle_input(event: InputEvent) -> bool:
	if not is_open() or not _pressed(event):
		return false

	if _is_key(event, KEY_F10) or _is_key(event, KEY_I) or _is_key(event, KEY_ESCAPE):
		return true

	if _is_left(event) or _is_up(event):
		_change_profile(-1)
		return false
	if _is_right(event) or _is_down(event):
		_change_profile(1)
		return false

	if _is_confirm(event):
		apply_requested.emit(_selected_profile())
		return true

	return false


func _load_profiles() -> void:
	_profiles.clear()
	var directory := DirAccess.open(QA_PROFILE_DIRECTORY)
	if directory == null:
		push_warning("TripleTriadDebugMenu: QA profile directory could not be opened.")
		return

	for file_name in directory.get_files():
		if not file_name.ends_with(".tres") and not file_name.ends_with(".res"):
			continue
		var resource = load(QA_PROFILE_DIRECTORY.path_join(file_name))
		if resource is Resource:
			_profiles.append(resource)

	_profiles.sort_custom(_profile_less)
	_profile_index = clampi(_profile_index, 0, _profiles.size())


func _profile_less(a: Resource, b: Resource) -> bool:
	var a_order: int = int(a.get("sort_order"))
	var b_order: int = int(b.get("sort_order"))
	if a_order == b_order:
		return str(a.get("profile_name")).naturalnocasecmp_to(str(b.get("profile_name"))) < 0
	return a_order < b_order


func _change_profile(step: int) -> void:
	_profile_index = posmod(_profile_index + step, _profiles.size() + 1)
	_refresh()


func _selected_profile() -> Resource:
	if _profile_index <= 0 or _profile_index > _profiles.size():
		return null
	return _profiles[_profile_index - 1]


func _sync_index_to_override() -> void:
	_profile_index = 0
	if _current_override == null:
		return
	var override_path: String = _current_override.resource_path
	for index in range(_profiles.size()):
		if _profiles[index] == _current_override or _profiles[index].resource_path == override_path:
			_profile_index = index + 1
			return


func _refresh() -> void:
	var selected_profile: Resource = _selected_profile()
	if selected_profile == null:
		profile_label.text = "> PROFILE   < CURRENT / NPC >"
		region_label.text = "  REGION    %s" % str(_current_summary.get("region", "Default"))
		ai_label.text = "  AI        %s" % str(_current_summary.get("ai", "Default"))
		budget_label.text = "  BUDGET    %d" % int(_current_summary.get("budget", 30))
		levels_label.text = "  LEVELS    %d - %d" % [
			int(_current_summary.get("min_level", 1)),
			int(_current_summary.get("max_level", 3)),
		]
		rules_label.text = "  RULES     %s" % str(_current_summary.get("rules", "Normal"))
		start_label.text = "  START     RANDOM"
		purpose_label.text = "Clears any QA override and uses the NPC/region configuration."
	else:
		profile_label.text = "> PROFILE   < %s >" % str(selected_profile.get("profile_name"))
		var region: Resource = selected_profile.get("region_profile")
		var ai: Resource = selected_profile.get("ai_profile")
		var selected_rules: Resource = selected_profile.get("rule_set_override")
		if selected_rules == null and region != null:
			selected_rules = region.get("rule_set")
		region_label.text = "  REGION    %s" % _resource_display_name(region, "Default")
		ai_label.text = "  AI        %s" % _resource_display_name(ai, "Default")
		budget_label.text = "  BUDGET    %d" % _profile_budget(selected_profile, region)
		levels_label.text = "  LEVELS    %d - %d" % [
			int(selected_profile.get("min_card_level")),
			int(selected_profile.get("max_card_level")),
		]
		rules_label.text = "  RULES     %s" % _rules_summary(selected_rules, region)
		start_label.text = "  START     %s" % _starting_owner_text(int(selected_profile.get("starting_owner")))
		purpose_label.text = str(selected_profile.get("purpose"))

	status_label.text = "A/D or W/S: profile    K: apply + restart    F10/I: close"


func _profile_budget(selected_profile: Resource, region: Resource) -> int:
	var override_value: int = int(selected_profile.get("deck_budget_override"))
	if override_value > 0:
		return override_value
	if region != null:
		var region_budget = region.get("deck_budget")
		if region_budget != null:
			return int(region_budget)
	return int(_current_summary.get("budget", 30))


func _rules_summary(selected_rules: Resource, region: Resource) -> String:
	var labels: PackedStringArray = PackedStringArray()
	if selected_rules != null:
		if bool(selected_rules.get("same_rule")):
			labels.append("Same")
		if bool(selected_rules.get("combo_rule")):
			labels.append("Combo")
	if region != null and bool(region.get("allow_rotate")):
		labels.append("Rotate x1")
	if labels.is_empty():
		return "Normal capture"
	return " + ".join(labels)


func _resource_display_name(resource: Resource, fallback: String) -> String:
	if resource == null:
		return fallback
	var display_name = resource.get("display_name")
	if display_name != null and not str(display_name).is_empty():
		return str(display_name)
	return resource.resource_path.get_file().get_basename()


func _starting_owner_text(value: int) -> String:
	match value:
		1:
			return "PLAYER"
		2:
			return "OPPONENT"
		_:
			return "RANDOM"


func _pressed(event: InputEvent) -> bool:
	return event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo


func _is_confirm(event: InputEvent) -> bool:
	return _is_key(event, KEY_K) or _is_key(event, KEY_ENTER)


func _is_left(event: InputEvent) -> bool:
	return _is_key(event, KEY_A) or _is_key(event, KEY_LEFT)


func _is_right(event: InputEvent) -> bool:
	return _is_key(event, KEY_D) or _is_key(event, KEY_RIGHT)


func _is_up(event: InputEvent) -> bool:
	return _is_key(event, KEY_W) or _is_key(event, KEY_UP)


func _is_down(event: InputEvent) -> bool:
	return _is_key(event, KEY_S) or _is_key(event, KEY_DOWN)


func _is_key(event: InputEvent, key: Key) -> bool:
	if not (event is InputEventKey):
		return false
	var key_event := event as InputEventKey
	return key_event.keycode == key or key_event.physical_keycode == key
