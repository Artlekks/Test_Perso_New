extends FishingMasterLessonNPCBase
class_name FishingMasterDriftAnglerNPC

const LessonPolicy = preload(
	"res://scripts/mastery/fishing_master_drift_angler_policy.gd"
)

const TECHNIQUE_ID: StringName = &"drift_casting"
const TEACHER_ID: StringName = &"master_drift_angler"

enum LessonPhase {
	INACTIVE,
	WAITING_FOR_CAST,
	OBSERVING_DRIFT,
	WAITING_FOR_RECAST,
	COMPLETE,
}

var _phase: LessonPhase = LessonPhase.INACTIVE
var _current_service: FishingCurrentService = null
var _caster: Node = null
var _observed_bait_instance_id: int = -1
var _player_position_at_cast: Vector3 = Vector3.ZERO
var _landing_position: Vector3 = Vector3.ZERO
var _last_bait_position: Vector3 = Vector3.ZERO
var _cast_alignment: float = 1.0
var _observation_seconds: float = 0.0
var _along_current_drift_meters: float = 0.0
var _max_cross_track_drift_meters: float = 0.0
var _reeling_warning_shown: bool = false
var _weak_current_warning_shown: bool = false


func get_technique_id() -> StringName:
	return TECHNIQUE_ID


func get_teacher_id() -> StringName:
	return TEACHER_ID


func get_known_message() -> String:
	return "Drift Angler: Good. Stop placing the lure where the fish is. Place it where the water will take it."


func get_unavailable_message() -> String:
	return "Drift Angler: I need live moving water and a working cast before I can teach this."


func _process(delta: float) -> void:
	if _phase == LessonPhase.INACTIVE or _phase == LessonPhase.COMPLETE:
		return
	if is_technique_known():
		_phase = LessonPhase.COMPLETE
		return
	if not _bind_lesson_runtime():
		return

	match _phase:
		LessonPhase.WAITING_FOR_CAST:
			_try_begin_cast_read()
		LessonPhase.OBSERVING_DRIFT:
			_update_drift_lesson(delta)
		LessonPhase.WAITING_FOR_RECAST:
			_wait_for_recast()
		_:
			pass


func _on_lesson_interaction() -> void:
	if not _bind_lesson_runtime():
		_show_message(get_unavailable_message(), 2.6)
		return

	match _phase:
		LessonPhase.INACTIVE:
			_begin_lesson()
		LessonPhase.WAITING_FOR_CAST:
			_show_message(
				"Drift Angler: Read the flow. Cast ACROSS it or slightly UPSTREAM — not straight downstream — then leave K alone.",
				4.4
			)
		LessonPhase.OBSERVING_DRIFT:
			var upstream_cast: bool = _cast_alignment <= LessonPolicy.UPSTREAM_ALIGNMENT_THRESHOLD
			_show_message(
				"Drift Angler: Let the water finish the cast. %d%%"
				% int(round(LessonPolicy.get_progress_ratio(
					_observation_seconds,
					_along_current_drift_meters,
					_max_cross_track_drift_meters,
					upstream_cast
				) * 100.0)),
				3.0
			)
		LessonPhase.WAITING_FOR_RECAST:
			_show_message(
				"Drift Angler: Reel that one in and try again. Across the flow or upstream, then let the current work.",
				4.0
			)
		LessonPhase.COMPLETE:
			pass


func _begin_lesson() -> void:
	_reset_attempt()
	_phase = LessonPhase.WAITING_FOR_CAST
	_play_animation(talk_animation)
	_show_message(
		"Drift Angler: A good cast does not end where the lure lands. Read the current, place the lure across or upstream of it, then let the water carry it into position.",
		5.6
	)


func _try_begin_cast_read() -> void:
	if _caster == null or not _caster.has_method("has_active_bait"):
		return
	if not bool(_caster.call("has_active_bait")):
		_observed_bait_instance_id = -1
		return
	if not _caster.has_method("is_active_bait_in_water"):
		return
	if not bool(_caster.call("is_active_bait_in_water")):
		return
	if not _caster.has_method("get_active_bait_world_position"):
		return

	var active_bait: Node = _caster.get("active_bait") as Node
	if active_bait == null:
		return
	var bait_instance_id: int = active_bait.get_instance_id()
	if bait_instance_id == _observed_bait_instance_id:
		return
	_observed_bait_instance_id = bait_instance_id

	var landing_position: Vector3 = _caster.call("get_active_bait_world_position")
	var player_position: Vector3 = global_position
	if is_instance_valid(_player) and _player is Node3D:
		player_position = (_player as Node3D).global_position
	var current_velocity: Vector3 = _current_service.sample_current_velocity(landing_position)
	var cast_read: Dictionary = LessonPolicy.evaluate_cast(
		player_position,
		landing_position,
		current_velocity
	)

	if not bool(cast_read.get("active_water", false)):
		_phase = LessonPhase.WAITING_FOR_RECAST
		_show_message(
			"Drift Angler: That water is too sheltered. Find a visible pull, reel in, and cast again.",
			3.8
		)
		return
	if not bool(cast_read.get("long_enough", false)):
		_phase = LessonPhase.WAITING_FOR_RECAST
		_show_message(
			"Drift Angler: Give the water room to work. Make a real cast, not a drop at your feet.",
			3.8
		)
		return
	if not bool(cast_read.get("compensated_cast", false)):
		_phase = LessonPhase.WAITING_FOR_RECAST
		_show_message(
			"Drift Angler: You threw WITH the current. Reel in. Cast across it or upstream so the water can finish the placement.",
			4.4
		)
		return

	_player_position_at_cast = player_position
	_landing_position = landing_position
	_last_bait_position = landing_position
	_cast_alignment = float(cast_read.get("alignment", 1.0))
	_observation_seconds = 0.0
	_along_current_drift_meters = 0.0
	_max_cross_track_drift_meters = 0.0
	_reeling_warning_shown = false
	_weak_current_warning_shown = false
	_phase = LessonPhase.OBSERVING_DRIFT
	_show_message(
		"Drift Angler: That's the placement. Now leave K alone and watch the current complete your cast.",
		4.0
	)


func _update_drift_lesson(delta: float) -> void:
	if _caster == null or _current_service == null:
		return
	if not _caster.has_method("has_active_bait") or not bool(_caster.call("has_active_bait")):
		_phase = LessonPhase.WAITING_FOR_CAST
		_reset_attempt()
		return
	if not _caster.has_method("is_active_bait_in_water") or not bool(_caster.call("is_active_bait_in_water")):
		return

	var bait_position: Vector3 = _caster.call("get_active_bait_world_position")
	var current_velocity: Vector3 = _current_service.sample_current_velocity(bait_position)
	var reeling: bool = (
		_caster.has_method("is_active_bait_reeling")
		and bool(_caster.call("is_active_bait_reeling"))
	)
	var result: Dictionary = LessonPolicy.advance_observation(
		_observation_seconds,
		_along_current_drift_meters,
		_max_cross_track_drift_meters,
		_player_position_at_cast,
		_landing_position,
		_last_bait_position,
		bait_position,
		current_velocity,
		_cast_alignment,
		reeling,
		delta
	)
	_observation_seconds = float(result.get("observation_seconds", 0.0))
	_along_current_drift_meters = float(result.get("along_current_drift_meters", 0.0))
	_max_cross_track_drift_meters = float(result.get("max_cross_track_drift_meters", 0.0))
	_last_bait_position = bait_position

	if reeling and not _reeling_warning_shown:
		_reeling_warning_shown = true
		_show_message(
			"Drift Angler: No. You moved it yourself. Release K — let the current do the work from the beginning.",
			3.6
		)
	elif not reeling:
		_reeling_warning_shown = false

	if not bool(result.get("active_water", false)) and not _weak_current_warning_shown:
		_weak_current_warning_shown = true
		_show_message(
			"Drift Angler: The flow weakened here. Keep the lure in moving water.",
			3.0
		)
	elif bool(result.get("active_water", false)):
		_weak_current_warning_shown = false

	if bool(result.get("complete", false)):
		_complete_lesson()


func _wait_for_recast() -> void:
	if _caster == null or not _caster.has_method("has_active_bait"):
		return
	if bool(_caster.call("has_active_bait")):
		return
	_reset_attempt()
	_phase = LessonPhase.WAITING_FOR_CAST


func _complete_lesson() -> void:
	var learned: Dictionary = try_learn_technique(true)
	if bool(learned.get("success", false)):
		_phase = LessonPhase.COMPLETE
		_play_animation(talk_animation)
		_show_message(
			"Technique learned — Drift Casting. You can now predict the current's short drift path and place casts for where the lure is going, not where it lands.",
			5.2
		)
		return
	_show_message(
		"Drift Angler: That's the cast. The technique could not be saved yet.",
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


func _reset_attempt() -> void:
	_observed_bait_instance_id = -1
	_player_position_at_cast = Vector3.ZERO
	_landing_position = Vector3.ZERO
	_last_bait_position = Vector3.ZERO
	_cast_alignment = 1.0
	_observation_seconds = 0.0
	_along_current_drift_meters = 0.0
	_max_cross_track_drift_meters = 0.0
	_reeling_warning_shown = false
	_weak_current_warning_shown = false
