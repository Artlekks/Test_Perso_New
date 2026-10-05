extends FishingMasterLessonNPCBase
class_name FishingMasterTideReaderNPC

const LessonPolicy = preload(
	"res://scripts/mastery/fishing_master_tide_reader_policy.gd"
)

const TECHNIQUE_ID: StringName = &"tide_sense"
const TEACHER_ID: StringName = &"master_tide_reader"

enum LessonPhase {
	INACTIVE,
	WAITING_FOR_MOVING_TIDE,
	WAITING_FOR_CAST,
	READING_TIDE,
	COMPLETE,
}

var _phase: LessonPhase = LessonPhase.INACTIVE
var _tide_service: FishingTideService = null
var _current_service: FishingCurrentService = null
var _caster: Node = null

var _movement: StringName = &"none"
var _flow_strength_ratio: float = 0.0
var _observation_seconds: float = 0.0
var _along_current_drift_meters: float = 0.0
var _last_bait_position: Vector3 = Vector3.ZERO
var _had_active_bait: bool = false

var _reeling_warning_shown: bool = false
var _depth_warning_shown: bool = false
var _current_warning_shown: bool = false
var _shallow_water_warning_shown: bool = false


func get_technique_id() -> StringName:
	return TECHNIQUE_ID


func get_teacher_id() -> StringName:
	return TEACHER_ID


func get_known_message() -> String:
	return "Tide Reader: Good. You no longer see the coast as one fixed fishing spot. The water is always arriving or leaving."


func get_unavailable_message() -> String:
	return "Tide Reader: This lesson needs live coastal water, current and a fishing cast."


func _process(delta: float) -> void:
	if _phase == LessonPhase.INACTIVE or _phase == LessonPhase.COMPLETE:
		return
	if is_technique_known():
		_phase = LessonPhase.COMPLETE
		return
	if not _bind_lesson_runtime():
		return

	var movement_changed := _refresh_tide_state()
	if movement_changed:
		_reset_observation()
		if _is_current_tide_teachable():
			_phase = LessonPhase.WAITING_FOR_CAST
			_show_message(
				"Tide Reader: The water changed. %s — follow the lesson into %s."
				% [
					LessonPolicy.get_movement_label(_movement),
					LessonPolicy.get_target_label(_movement),
				],
				4.2
			)
		else:
			_phase = LessonPhase.WAITING_FOR_MOVING_TIDE
			_show_message(
				"Tide Reader: Slack water. Don't invent a read. Wait until the coast starts moving again.",
				3.8
			)

	match _phase:
		LessonPhase.WAITING_FOR_MOVING_TIDE:
			if _is_current_tide_teachable():
				_phase = LessonPhase.WAITING_FOR_CAST
				_show_tide_instruction()
		LessonPhase.WAITING_FOR_CAST:
			_try_begin_tide_read()
		LessonPhase.READING_TIDE:
			_update_tide_read(delta)
		LessonPhase.COMPLETE:
			pass
		LessonPhase.INACTIVE:
			pass


func _on_lesson_interaction() -> void:
	if not _bind_lesson_runtime():
		_show_message(get_unavailable_message(), 2.4)
		return

	match _phase:
		LessonPhase.INACTIVE:
			_begin_lesson()
		LessonPhase.WAITING_FOR_MOVING_TIDE:
			_show_message(
				"Tide Reader: This is slack water. Wait for a real flood or ebb before you try to read it.",
				3.8
			)
		LessonPhase.WAITING_FOR_CAST:
			_show_tide_instruction()
		LessonPhase.READING_TIDE:
			_show_message(
				"Tide Reader: %s. Keep the lure in %s and let the current carry it. %d%%"
				% [
					LessonPolicy.get_movement_label(_movement),
					LessonPolicy.get_target_label(_movement),
					int(round(LessonPolicy.get_progress_ratio(
						_observation_seconds,
						_along_current_drift_meters
					) * 100.0)),
				],
				3.5
			)
		LessonPhase.COMPLETE:
			pass


func _begin_lesson() -> void:
	if _mastery_service == null:
		_show_message(get_unavailable_message(), 2.4)
		return

	var quote := _mastery_service.can_learn(TECHNIQUE_ID, TEACHER_ID)
	if not bool(quote.get("can_learn", false)):
		var reason := str(quote.get("reason", ""))
		if reason == "missing_prerequisite":
			_show_message(
				"Tide Reader: First learn to Read the Current and read Weather. Tide is both movement and changing water.",
				4.8
			)
		else:
			_show_message(
				"Tide Reader: The lesson isn't available yet.",
				3.0
			)
		return

	if _tide_service == null or not _tide_service.is_active():
		_show_message(
			"Tide Reader: Tides belong to the coast. Bring me live ocean water and we'll begin.",
			4.0
		)
		return

	_reset_observation()
	_refresh_tide_state()
	_play_animation(talk_animation)
	if _is_current_tide_teachable():
		_phase = LessonPhase.WAITING_FOR_CAST
		_show_message(
			"Tide Reader: Current tells you that water moves. Weather tells you where life favors the column. Tide joins them. %s now favors %s — cast there, leave K alone, and let the water prove it."
			% [
				LessonPolicy.get_movement_label(_movement),
				LessonPolicy.get_target_label(_movement),
			],
			7.0
		)
	else:
		_phase = LessonPhase.WAITING_FOR_MOVING_TIDE
		_show_message(
			"Tide Reader: This is slack water. The lesson starts when the coast begins to flood or ebb. Watch first.",
			5.0
		)


func _show_tide_instruction() -> void:
	_show_message(
		"Tide Reader: %s. Cast into moving water, keep the lure in %s, and do not reel. Let the current carry it."
		% [
			LessonPolicy.get_movement_label(_movement),
			LessonPolicy.get_target_label(_movement),
		],
		5.2
	)


func _try_begin_tide_read() -> void:
	if not _is_current_tide_teachable():
		_phase = LessonPhase.WAITING_FOR_MOVING_TIDE
		return
	if _caster == null or not _caster.has_method("has_active_bait"):
		return
	if not bool(_caster.call("has_active_bait")):
		_had_active_bait = false
		return
	if (
		not _caster.has_method("is_active_bait_in_water")
		or not bool(_caster.call("is_active_bait_in_water"))
	):
		_had_active_bait = true
		return
	if not _caster.has_method("get_active_bait_world_position"):
		return

	_last_bait_position = _caster.call("get_active_bait_world_position")
	_reset_observation(false)
	_had_active_bait = true
	_phase = LessonPhase.READING_TIDE
	_show_message(
		"Tide Reader: Good. %s — hold %s and let the moving water carry the lure."
		% [
			LessonPolicy.get_movement_label(_movement),
			LessonPolicy.get_target_label(_movement),
		],
		4.0
	)


func _update_tide_read(delta: float) -> void:
	if _caster == null or _current_service == null or _tide_service == null:
		return
	if not _caster.has_method("has_active_bait"):
		return

	var has_bait := bool(_caster.call("has_active_bait"))
	var in_water := (
		has_bait
		and _caster.has_method("is_active_bait_in_water")
		and bool(_caster.call("is_active_bait_in_water"))
	)
	if not in_water:
		if _had_active_bait:
			_phase = LessonPhase.WAITING_FOR_CAST
			_reset_observation()
			_show_message(
				"Tide Reader: Again. Read the same moving tide with the next cast.",
				3.2
			)
		return

	if (
		not _caster.has_method("get_active_bait_world_position")
		or not _caster.has_method("get_current_bait_depth")
		or not _caster.has_method("get_current_total_depth")
	):
		return

	var bait_position: Vector3 = _caster.call("get_active_bait_world_position")
	var current_velocity := _current_service.sample_current_velocity(bait_position)
	var current_depth := float(_caster.call("get_current_bait_depth"))
	var total_depth := float(_caster.call("get_current_total_depth"))
	var reeling := (
		_caster.has_method("is_active_bait_reeling")
		and bool(_caster.call("is_active_bait_reeling"))
	)

	var result := LessonPolicy.advance_observation(
		_observation_seconds,
		_along_current_drift_meters,
		_movement,
		_flow_strength_ratio,
		current_velocity,
		_last_bait_position,
		bait_position,
		current_depth,
		total_depth,
		reeling,
		delta
	)
	_observation_seconds = float(result.get("observation_seconds", 0.0))
	_along_current_drift_meters = float(
		result.get("along_current_drift_meters", 0.0)
	)
	_last_bait_position = bait_position
	_had_active_bait = true

	if reeling and not _reeling_warning_shown:
		_reeling_warning_shown = true
		_show_message(
			"Tide Reader: Leave K alone. I need the tide moving the lure, not you.",
			2.9
		)
	elif not reeling:
		_reeling_warning_shown = false

	var valid_water := bool(result.get("valid_water", false))
	if not valid_water and not _shallow_water_warning_shown:
		_shallow_water_warning_shown = true
		_show_message(
			"Tide Reader: Too little water here to read the tidal column. Cast into a deeper pocket.",
			3.2
		)
	elif valid_water:
		_shallow_water_warning_shown = false

	var correct_depth := bool(result.get("correct_depth", false))
	if valid_water and not correct_depth and not _depth_warning_shown:
		_depth_warning_shown = true
		_show_message(
			"Tide Reader: Wrong part of the column. %s wants %s."
			% [
				LessonPolicy.get_movement_label(_movement),
				LessonPolicy.get_target_label(_movement),
			],
			3.2
		)
	elif correct_depth:
		_depth_warning_shown = false

	var active_current := bool(result.get("active_current", false))
	if not active_current and not _current_warning_shown:
		_current_warning_shown = true
		_show_message(
			"Tide Reader: Too sheltered. Find water where the current can actually carry the lure.",
			3.2
		)
	elif active_current:
		_current_warning_shown = false

	if bool(result.get("complete", false)):
		_complete_lesson()


func _complete_lesson() -> void:
	var learned := try_learn_technique(true)
	if bool(learned.get("success", false)):
		_phase = LessonPhase.COMPLETE
		_play_animation(talk_animation)
		_show_message(
			"Technique learned — Tide Sense. You can now read coastal water level, tidal movement, productive water and the depth shift it creates.",
			6.2
		)
		return
	_show_message(
		"Tide Reader: You read the tide correctly, but the lesson could not be saved yet.",
		3.4
	)


func _bind_lesson_runtime() -> bool:
	if not _bind_runtime():
		return false

	var tree := get_tree()
	var services: Node = null
	if tree != null:
		services = tree.root.get_node_or_null("FishingSessionServices")

	if services != null:
		if _tide_service == null and services.has_method("get_fishing_tide_service"):
			var raw_tide = services.call("get_fishing_tide_service")
			if raw_tide is FishingTideService:
				_tide_service = raw_tide
		if _current_service == null and services.has_method("get_fishing_current_service"):
			var raw_current = services.call("get_fishing_current_service")
			if raw_current is FishingCurrentService:
				_current_service = raw_current

	if _caster == null:
		var fishing := _find_fishing_root()
		if fishing != null:
			var raw_caster = fishing.get("caster")
			if raw_caster is Node:
				_caster = raw_caster
			if _caster == null:
				_caster = fishing.find_child("Caster", true, false)

	return (
		_tide_service != null
		and _current_service != null
		and _caster != null
	)


func _refresh_tide_state() -> bool:
	if _tide_service == null:
		return false
	var snapshot := _tide_service.get_snapshot()
	var new_movement := StringName(str(snapshot.get("movement", "none")))
	var new_flow := float(snapshot.get("flow_strength_ratio", 0.0))
	var changed := new_movement != _movement
	_movement = new_movement
	_flow_strength_ratio = new_flow
	return changed


func _is_current_tide_teachable() -> bool:
	return (
		_tide_service != null
		and _tide_service.is_active()
		and LessonPolicy.is_moving_tide(_movement, _flow_strength_ratio)
	)


func _reset_observation(reset_bait_state: bool = true) -> void:
	_observation_seconds = 0.0
	_along_current_drift_meters = 0.0
	_last_bait_position = Vector3.ZERO
	if reset_bait_state:
		_had_active_bait = false
	_reeling_warning_shown = false
	_depth_warning_shown = false
	_current_warning_shown = false
	_shallow_water_warning_shown = false
