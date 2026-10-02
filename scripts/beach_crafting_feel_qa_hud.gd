extends CanvasLayer
class_name BeachCraftingFeelQAHUD

@onready var root: Control = $Root
@onready var lure_label: Label = $Root/Panel/LureLabel
@onready var properties_label: Label = $Root/Panel/PropertiesLabel
@onready var water_label: Label = $Root/Panel/WaterLabel
@onready var fish_label: Label = $Root/Panel/FishLabel
@onready var status_label: Label = $Root/Panel/StatusLabel

var _service: BeachCraftingService = null
var _loadout = null
var _refresh_remaining: float = 0.0
var _status: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	root.hide()
	set_process(true)
	set_process_unhandled_input(true)


func configure(
	service: BeachCraftingService,
	loadout
) -> void:
	_service = service
	_loadout = loadout
	_refresh()


func set_loadout(loadout) -> void:
	_loadout = loadout
	_refresh()


func _process(delta: float) -> void:
	if not root.visible:
		return
	_refresh_remaining -= delta
	if _refresh_remaining > 0.0:
		return
	_refresh_remaining = 0.10
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if not _is_key_press(event):
		return

	if _is_key(event, KEY_F8):
		root.visible = not root.visible
		_status = ""
		_refresh_remaining = 0.0
		_refresh()
		get_viewport().set_input_as_handled()
		return

	if not root.visible:
		return

	var pair_id: StringName = &""
	if _is_key(event, KEY_1):
		pair_id = &"buoyancy"
	elif _is_key(event, KEY_2):
		pair_id = &"handling"
	elif _is_key(event, KEY_3):
		pair_id = &"attraction"

	if pair_id == &"":
		return

	if _service == null:
		_status = "Crafting service unavailable."
	else:
		var result: Dictionary = _service.toggle_qa_feel_pair(
			pair_id
		)
		_status = (
			"%s -> %s   RECAST"
			% [
				str(result.get("pair_label", String(pair_id))),
				str(result.get("display_name", "FAILED")),
			]
			if bool(result.get("success", false))
			else "PAIR FAILED: %s"
			% str(result.get("reason", "unknown"))
		)

	_refresh_remaining = 0.0
	_refresh()
	get_viewport().set_input_as_handled()


func _refresh() -> void:
	if not is_instance_valid(root):
		return
	if not root.visible:
		return

	var lure: BaitData = _get_equipped_lure()
	if lure == null:
		lure_label.text = "LURE   none"
		properties_label.text = "CRAFT   --"
		water_label.text = "WATER   cast a lure to inspect depth"
		fish_label.text = "FISH    --"
	else:
		lure_label.text = "LURE   %s" % lure.display_name
		var scores: Dictionary = (
			_service.get_lure_craft_scores(lure)
			if _service != null
			else {}
		)
		properties_label.text = _property_line(
			scores,
			lure
		)
		water_label.text = _water_line(lure)
		fish_label.text = _fish_line()

	status_label.text = (
		_status
		if not _status.is_empty()
		else "1 FLOAT/SINK   2 HEAVY/RESP   3 SUBTLE/FLASH   F8 CLOSE"
	)


func _property_line(
	scores: Dictionary,
	lure: BaitData
) -> String:
	var score_text: String = "B --   H --   A --"
	if not scores.is_empty():
		score_text = "B %s   H %s   A %s" % [
			_signed(int(scores.get("buoyancy", 0))),
			_signed(int(scores.get("handling", 0))),
			_signed(int(scores.get("attraction", 0))),
		]

	var attraction: float = (
		_service.get_lure_attraction_reference(lure)
		if _service != null
		else 1.0
	)
	return "CRAFT   %s    STEER %.3f    ATTR %.3f" % [
		score_text,
		lure.reel_steer_strength,
		attraction,
	]


func _water_line(lure: BaitData) -> String:
	var bait := _get_active_bait()
	if bait == null or not bait.has_method("get_lure_debug_snapshot"):
		return "WATER   target depth %.2f    RECAST AFTER SWAP" % lure.sink_depth

	var snapshot = bait.call("get_lure_debug_snapshot")
	if not (snapshot is Dictionary):
		return "WATER   target depth %.2f" % lure.sink_depth

	var current_depth: float = float(snapshot.get("depth_m", 0.0))
	var total_depth: float = float(snapshot.get("total_depth_m", 0.0))
	var ratio: float = (
		current_depth / total_depth
		if total_depth > 0.001
		else 0.0
	)
	return (
		"WATER   depth %.2fm / %.2fm  (%.0f%%)    TARGET %.0f%%"
		% [
			current_depth,
			total_depth,
			ratio * 100.0,
			lure.sink_depth * 100.0,
		]
	)


func _fish_line() -> String:
	var bait := _get_active_bait()
	if bait == null:
		return "FISH    cast first"

	var scene := get_tree().current_scene
	if scene == null:
		return "FISH    --"

	var nearest: FishShadowActor = null
	var nearest_distance: float = INF
	for raw_node in scene.find_children(
		"*",
		"FishShadowActor",
		true,
		false
	):
		if not (raw_node is FishShadowActor):
			continue
		var fish := raw_node as FishShadowActor
		var offset: Vector3 = fish.global_position - bait.global_position
		offset.y = 0.0
		var distance: float = offset.length()
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = fish

	if nearest == null:
		return "FISH    no visible shadow"

	var state: String = (
		nearest.get_pre_bite_state_name()
		if nearest.has_method("get_pre_bite_state_name")
		else "?"
	)
	var interested: bool = (
		nearest.is_interested_in_bait()
		if nearest.has_method("is_interested_in_bait")
		else false
	)
	return "FISH    nearest %.2fm    %s    INTEREST %s" % [
		nearest_distance,
		state,
		"YES" if interested else "NO",
	]


func _get_equipped_lure() -> BaitData:
	if _loadout == null:
		return null
	if not _loadout.has_method("get_selected_lure"):
		return null
	return _loadout.get_selected_lure() as BaitData


func _get_active_bait() -> Node3D:
	var scene := get_tree().current_scene
	if scene == null:
		return null

	var caster := scene.get_node_or_null(
		"Game/Fishing/Caster"
	)
	if caster == null:
		caster = scene.find_child(
			"Caster",
			true,
			false
		)
	if caster == null:
		return null

	var candidate = caster.get("active_bait")
	return candidate as Node3D if candidate is Node3D else null


func _signed(value: int) -> String:
	return "+%d" % value if value > 0 else str(value)


func _is_key_press(event: InputEvent) -> bool:
	return (
		event is InputEventKey
		and (event as InputEventKey).pressed
		and not (event as InputEventKey).echo
	)


func _is_key(
	event: InputEvent,
	key: Key
) -> bool:
	if not (event is InputEventKey):
		return false
	var key_event := event as InputEventKey
	return (
		key_event.keycode == key
		or key_event.physical_keycode == key
	)
