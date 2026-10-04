extends FishingMasterLessonNPCBase
class_name FishingMasterStructureHunterNPC

const LessonPolicy = preload(
	"res://scripts/mastery/fishing_master_structure_hunter_policy.gd"
)

const TECHNIQUE_ID: StringName = &"read_structure"
const TEACHER_ID: StringName = &"master_structure_hunter"

enum LessonPhase {
	INACTIVE,
	WAITING_FOR_CAST,
	TRACING_STRUCTURE,
	COMPLETE,
}

var _phase: LessonPhase = LessonPhase.INACTIVE
var _caster: Node = null
var _observation_seconds: float = 0.0
var _horizontal_travel: float = 0.0
var _min_total_depth: float = -1.0
var _max_total_depth: float = -1.0
var _structure_contact: bool = false
var _has_previous_position: bool = false
var _previous_position: Vector3 = Vector3.ZERO
var _had_active_bait: bool = false
var _depth_break_announced: bool = false
var _cover_announced: bool = false
var _shallow_warning_shown: bool = false


func get_technique_id() -> StringName:
	return TECHNIQUE_ID


func get_teacher_id() -> StringName:
	return TEACHER_ID


func get_known_message() -> String:
	return "Structure Hunter: You know the difference now. Open water is empty space; edges and cover are places fish can use."


func get_unavailable_message() -> String:
	return "Structure Hunter: I need a live cast to teach this lesson."


func _process(delta: float) -> void:
	if _phase == LessonPhase.INACTIVE or _phase == LessonPhase.COMPLETE:
		return
	if is_technique_known():
		_phase = LessonPhase.COMPLETE
		return
	if not _bind_lesson_runtime():
		return

	if _phase == LessonPhase.WAITING_FOR_CAST:
		_try_begin_structure_trace()
		return
	if _phase == LessonPhase.TRACING_STRUCTURE:
		_update_structure_trace(delta)


func _on_lesson_interaction() -> void:
	if not _bind_lesson_runtime():
		_show_message(get_unavailable_message(), 2.4)
		return

	match _phase:
		LessonPhase.INACTIVE:
			_begin_lesson()
		LessonPhase.WAITING_FOR_CAST:
			_show_message(
				"Structure Hunter: Cast out, then bring the lure across different bottom contour. Watch the water beneath the lure, not only the lure itself.",
				4.4
			)
		LessonPhase.TRACING_STRUCTURE:
			_show_message(
				"Structure Hunter: Keep tracing the contour. %d%%"
				% int(round(LessonPolicy.get_progress_ratio(
					_observation_seconds,
					_horizontal_travel,
					LessonPolicy.get_depth_span(_min_total_depth, _max_total_depth),
					_structure_contact
				) * 100.0)),
				3.0
			)
		LessonPhase.COMPLETE:
			pass


func _begin_lesson() -> void:
	_reset_trace()
	_phase = LessonPhase.WAITING_FOR_CAST
	_play_animation(talk_animation)
	_show_message(
		"Structure Hunter: Fish don't see a flat pond. They see shelves, edges, rocks and cover. Cast out and trace the shape under your lure.",
		5.2
	)


func _try_begin_structure_trace() -> void:
	if _caster == null or not _caster.has_method("has_active_bait"):
		return
	if not bool(_caster.call("has_active_bait")):
		_had_active_bait = false
		return
	if not _caster.has_method("is_active_bait_in_water"):
		return
	if not bool(_caster.call("is_active_bait_in_water")):
		_had_active_bait = true
		return

	_reset_trace()
	_had_active_bait = true
	_phase = LessonPhase.TRACING_STRUCTURE
	_show_message(
		"Structure Hunter: Good. Move the lure across the water and watch how the bottom beneath it changes. A real edge or cover is the lesson.",
		4.1
	)


func _update_structure_trace(delta: float) -> void:
	if _caster == null or not _caster.has_method("has_active_bait"):
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
			_reset_trace()
			_show_message(
				"Structure Hunter: Again. One cast needs to trace enough water to reveal an edge or cover.",
				3.3
			)
		return

	if not _caster.has_method("get_active_bait_world_position"):
		return
	if not _caster.has_method("get_current_total_depth"):
		return

	var current_position: Vector3 = _caster.call("get_active_bait_world_position")
	var total_depth := float(_caster.call("get_current_total_depth"))
	var direct_structure := _has_direct_structure_contact()
	var result := LessonPolicy.advance_trace(
		_observation_seconds,
		_horizontal_travel,
		_min_total_depth,
		_max_total_depth,
		_structure_contact,
		_has_previous_position,
		_previous_position,
		current_position,
		total_depth,
		direct_structure,
		delta
	)
	_observation_seconds = float(result.get("observation_seconds", 0.0))
	_horizontal_travel = float(result.get("horizontal_travel", 0.0))
	_min_total_depth = float(result.get("min_total_depth", -1.0))
	_max_total_depth = float(result.get("max_total_depth", -1.0))
	_structure_contact = bool(result.get("structure_contact", false))
	_had_active_bait = true

	if bool(result.get("sample_accepted", false)):
		_previous_position = current_position
		_has_previous_position = true
	elif bool(result.get("valid_water", false)):
		# A recast/teleport sample earns no progress, but it becomes the new
		# anchor so the next normal movement sample can be observed again.
		_previous_position = current_position
		_has_previous_position = true
	else:
		_has_previous_position = false

	if not bool(result.get("valid_water", false)) and not _shallow_warning_shown:
		_shallow_warning_shown = true
		_show_message(
			"Structure Hunter: Too shallow to read cleanly here. Put the lure over a real water column.",
			2.8
		)
	elif bool(result.get("valid_water", false)):
		_shallow_warning_shown = false

	var depth_span := float(result.get("depth_span", 0.0))
	if depth_span >= LessonPolicy.REQUIRED_DEPTH_BREAK_METERS and not _depth_break_announced:
		_depth_break_announced = true
		_show_message(
			"Structure Hunter: There — the bottom changed under the lure. That's an edge. Fish use edges like roads.",
			3.3
		)
	if _structure_contact and not _cover_announced:
		_cover_announced = true
		_show_message(
			"Structure Hunter: Cover. Notice where it begins before your lure actually buries itself in it.",
			3.1
		)

	if bool(result.get("complete", false)):
		_complete_lesson()


func _has_direct_structure_contact() -> bool:
	if _caster == null:
		return false
	var raw_bait = _caster.get("active_bait")
	if not (raw_bait is Node) or not is_instance_valid(raw_bait):
		return false
	var bait := raw_bait as Node
	if bait.has_method("_get_obstacle_snag_multiplier"):
		return float(bait.call("_get_obstacle_snag_multiplier")) > 0.0
	return false


func _complete_lesson() -> void:
	var learned := try_learn_technique(true)
	if bool(learned.get("success", false)):
		_phase = LessonPhase.COMPLETE
		_play_animation(talk_animation)
		_show_message(
			"Technique learned — Read Structure. Shelves, drop-offs and cover are now part of how you read a fishing spot.",
			5.0
		)
		return
	_show_message(
		"Structure Hunter: You read the water correctly, but the lesson could not be saved yet.",
		3.2
	)


func _bind_lesson_runtime() -> bool:
	if not _bind_runtime():
		return false
	if _caster == null:
		var fishing := _find_fishing_root()
		if fishing != null:
			var raw_caster = fishing.get("caster")
			if raw_caster is Node:
				_caster = raw_caster
			if _caster == null:
				_caster = fishing.find_child("Caster", true, false)
	return _caster != null


func _reset_trace() -> void:
	_observation_seconds = 0.0
	_horizontal_travel = 0.0
	_min_total_depth = -1.0
	_max_total_depth = -1.0
	_structure_contact = false
	_has_previous_position = false
	_previous_position = Vector3.ZERO
	_had_active_bait = false
	_depth_break_announced = false
	_cover_announced = false
	_shallow_warning_shown = false
