extends FishingMasterLessonNPCBase
class_name FishingMasterCurrentReaderNPC

const LessonPolicy = preload(
	"res://scripts/mastery/fishing_master_current_reader_policy.gd"
)

const TECHNIQUE_ID: StringName = &"read_current"
const TEACHER_ID: StringName = &"master_current_reader"

enum LessonPhase {
	INACTIVE,
	WAITING_FOR_CAST,
	READING_CURRENT,
	COMPLETE,
}

var _phase: LessonPhase = LessonPhase.INACTIVE
var _current_service: FishingCurrentService = null
var _caster: Node = null
var _observation_seconds: float = 0.0
var _along_current_drift_meters: float = 0.0
var _last_bait_position: Vector3 = Vector3.ZERO
var _had_active_bait: bool = false
var _reeling_warning_shown: bool = false
var _still_water_warning_shown: bool = false


func get_technique_id() -> StringName:
	return TECHNIQUE_ID


func get_teacher_id() -> StringName:
	return TEACHER_ID


func get_known_message() -> String:
	return "Current Reader: Don't fight every movement. Watch the water first, then decide where the lure belongs."


func get_unavailable_message() -> String:
	return "Current Reader: The lesson needs live water. Try again from a fishing bank."


func _process(delta: float) -> void:
	if _phase == LessonPhase.INACTIVE or _phase == LessonPhase.COMPLETE:
		return
	if is_technique_known():
		_phase = LessonPhase.COMPLETE
		return
	if not _bind_lesson_runtime():
		return

	if _phase == LessonPhase.WAITING_FOR_CAST:
		_try_begin_drift_read()
		return
	if _phase == LessonPhase.READING_CURRENT:
		_update_drift_read(delta)


func _on_lesson_interaction() -> void:
	if not _bind_lesson_runtime():
		_show_message(get_unavailable_message(), 2.4)
		return

	match _phase:
		LessonPhase.INACTIVE:
			_begin_lesson()
		LessonPhase.WAITING_FOR_CAST:
			_show_message(
				"Current Reader: Cast into moving water. Once it lands, leave K alone and watch where the water takes the lure.",
				4.0
			)
		LessonPhase.READING_CURRENT:
			_show_message(
				"Current Reader: Don't pull against it. Let the lure travel with the water. %d%%"
				% int(round(LessonPolicy.get_progress_ratio(
					_observation_seconds,
					_along_current_drift_meters
				) * 100.0)),
				3.0
			)
		LessonPhase.COMPLETE:
			pass


func _begin_lesson() -> void:
	_reset_observation()
	_phase = LessonPhase.WAITING_FOR_CAST
	_play_animation(talk_animation)
	_show_message(
		"Current Reader: The water is already moving your lure before you touch the reel. Cast, then let it drift. Read the water instead of fighting it.",
		5.0
	)


func _try_begin_drift_read() -> void:
	if _caster == null:
		return
	if not _caster.has_method("has_active_bait"):
		return
	if not bool(_caster.call("has_active_bait")):
		_had_active_bait = false
		return
	if not _caster.has_method("is_active_bait_in_water"):
		return
	if not bool(_caster.call("is_active_bait_in_water")):
		_had_active_bait = true
		return
	if not _caster.has_method("get_active_bait_world_position"):
		return

	_last_bait_position = _caster.call("get_active_bait_world_position")
	_observation_seconds = 0.0
	_along_current_drift_meters = 0.0
	_reeling_warning_shown = false
	_still_water_warning_shown = false
	_had_active_bait = true
	_phase = LessonPhase.READING_CURRENT
	_show_message(
		"Current Reader: Good. Now leave the reel alone. Watch the lure's path.",
		3.0
	)


func _update_drift_read(delta: float) -> void:
	if _caster == null or _current_service == null:
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
				"Current Reader: Again. Cast where the water is moving and let it carry the lure.",
				3.2
			)
		return

	var bait_position: Vector3 = _caster.call("get_active_bait_world_position")
	var current_velocity := _current_service.sample_current_velocity(bait_position)
	var reeling := (
		_caster.has_method("is_active_bait_reeling")
		and bool(_caster.call("is_active_bait_reeling"))
	)
	var result := LessonPolicy.advance_observation(
		_observation_seconds,
		_along_current_drift_meters,
		current_velocity,
		_last_bait_position,
		bait_position,
		reeling,
		delta
	)
	_observation_seconds = float(result.get("observation_seconds", 0.0))
	_along_current_drift_meters = float(
		result.get("along_current_drift_meters", 0.0)
	)
	_last_bait_position = bait_position

	if reeling and not _reeling_warning_shown:
		_reeling_warning_shown = true
		_show_message(
			"Current Reader: You're moving it. Release K and let the water show you its direction.",
			2.8
		)
	elif not reeling:
		_reeling_warning_shown = false

	if not bool(result.get("active_water", false)) and not _still_water_warning_shown:
		_still_water_warning_shown = true
		_show_message(
			"Current Reader: Too sheltered. Find water with a stronger pull.",
			2.8
		)
	elif bool(result.get("active_water", false)):
		_still_water_warning_shown = false

	if bool(result.get("complete", false)):
		_complete_lesson()


func _complete_lesson() -> void:
	var learned := try_learn_technique(true)
	if bool(learned.get("success", false)):
		_phase = LessonPhase.COMPLETE
		_play_animation(talk_animation)
		_show_message(
			"Technique learned — Read the Current. You can now read current direction and strength before committing the cast.",
			4.8
		)
		return
	_show_message(
		"Current Reader: You read it correctly, but the lesson could not be saved yet.",
		3.2
	)


func _bind_lesson_runtime() -> bool:
	if not _bind_runtime():
		return false
	if _current_service == null:
		var tree := get_tree()
		if tree != null:
			var services := tree.root.get_node_or_null("FishingSessionServices")
			if services != null and services.has_method("get_fishing_current_service"):
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
	return _current_service != null and _caster != null


func _reset_observation() -> void:
	_observation_seconds = 0.0
	_along_current_drift_meters = 0.0
	_last_bait_position = Vector3.ZERO
	_had_active_bait = false
	_reeling_warning_shown = false
	_still_water_warning_shown = false
