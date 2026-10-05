extends FishingMasterLessonNPCBase
class_name FishingMasterLandingGuideNPC

const LessonPolicy = preload(
	"res://scripts/mastery/fishing_master_landing_guide_policy.gd"
)

const TECHNIQUE_ID: StringName = &"landing_technique"
const TEACHER_ID: StringName = &"master_landing_guide"


enum LessonPhase {
	INACTIVE,
	WAITING_FOR_HOOK,
	WATCHING_FIGHT,
	RESPONSE_WINDOW,
	COMPLETE,
}


var _phase: LessonPhase = LessonPhase.INACTIVE
var _encounter: Node = null
var _caster = null

var _attempt_used: bool = false
var _training_block_owned: bool = false
var _response_window_left: float = 0.0
var _response_match_time: float = 0.0
var _expected_response: StringName = &"none"
var _fish_lateral: float = 0.0
var _difficulty_tier: int = 1
var _is_king: bool = false


func get_technique_id() -> StringName:
	return TECHNIQUE_ID


func get_teacher_id() -> StringName:
	return TEACHER_ID


func get_known_message() -> String:
	return "Landing Guide: Good. You know how to lead a spent fish home instead of dragging it sideways."


func get_unavailable_message() -> String:
	return "Landing Guide: I need the live fishing fight to teach this lesson."


func _process(delta: float) -> void:
	if _phase == LessonPhase.INACTIVE or _phase == LessonPhase.COMPLETE:
		return
	if is_technique_known():
		_release_training_block(false)
		_phase = LessonPhase.COMPLETE
		return
	if not _bind_lesson_runtime():
		return

	var fight_snapshot := _get_fight_snapshot()
	var fight_state := StringName(str(fight_snapshot.get("fight_state", "NONE")))
	var landing_snapshot: Dictionary = fight_snapshot.get("landing", {})
	var final_surge_checked := bool(landing_snapshot.get("checked", false))
	var final_surge_active := bool(landing_snapshot.get("active", false))

	if _phase == LessonPhase.WAITING_FOR_HOOK:
		if fight_state != &"NONE":
			_phase = LessonPhase.WATCHING_FIGHT
			_show_message(
				"Landing Guide: Wear the fish down. When it is spent and close, line its head up before the last surge.",
				5.2
			)
		return

	if fight_state == &"NONE":
		_release_training_block(false)
		_reset_attempt()
		_phase = LessonPhase.WAITING_FOR_HOOK
		_show_message(
			"Landing Guide: Hook another fish. I want one clean final approach from a spent fish.",
			3.8
		)
		return

	if _phase == LessonPhase.WATCHING_FIGHT:
		_try_open_response_window(
			fight_snapshot,
			fight_state,
			final_surge_checked,
			final_surge_active
		)
		return

	if _phase == LessonPhase.RESPONSE_WINDOW:
		# Final Surge can move the fish back out of SPENT. Check ownership first so
		# we never clear Encounter's landing-completion block underneath an active surge.
		if final_surge_checked or final_surge_active:
			_fail_attempt(
				"Landing Guide: Too late — the final surge already took the fish. Try the approach earlier on the next one.",
				final_surge_active
			)
			return
		if fight_state != &"SPENT":
			_fail_attempt(
				"Landing Guide: The fish was not settled enough. Hook another and bring it in spent.",
				false
			)
			return
		_update_response_window(delta)


func _on_lesson_interaction() -> void:
	if not _bind_lesson_runtime():
		_show_message(get_unavailable_message(), 2.4)
		return

	match _phase:
		LessonPhase.INACTIVE:
			_begin_lesson()
		LessonPhase.WAITING_FOR_HOOK:
			_show_message(
				"Landing Guide: Hook a fish, wear it down, then bring it close while it is SPENT.",
				4.2
			)
		LessonPhase.WATCHING_FIGHT:
			_show_message(
				"Landing Guide: Keep fighting. I only care about the final approach after the fish is spent.",
				4.0
			)
		LessonPhase.RESPONSE_WINDOW:
			_show_message(
				"Landing Guide: NOW — %s." % LessonPolicy.get_response_label(
					_expected_response,
					_fish_lateral
				),
				2.8
			)
		LessonPhase.COMPLETE:
			pass


func _begin_lesson() -> void:
	if _mastery_service == null:
		_show_message(get_unavailable_message(), 2.4)
		return

	var quote := _mastery_service.can_learn(TECHNIQUE_ID, TEACHER_ID)
	if not bool(quote.get("can_learn", false)):
		if str(quote.get("reason", "")) == "missing_prerequisite":
			_show_message(
				"Landing Guide: Not yet. Learn Surface Control first. If you cannot manage the top layer, you cannot land cleanly.",
				5.0
			)
			return
		_show_message("Landing Guide: The lesson isn't available yet.", 3.0)
		return

	_reset_attempt()
	_phase = LessonPhase.WAITING_FOR_HOOK
	_play_animation(talk_animation)
	_show_message(
		"Landing Guide: A spent fish can still beat you at the bank. Bring one close. If its head is straight, hold K and stay neutral. If it crosses, hold K and counter-steer its head back toward you. Show me once.",
		8.0
	)


func _try_open_response_window(
	fight_snapshot: Dictionary,
	fight_state: StringName,
	final_surge_checked: bool,
	final_surge_active: bool
) -> void:
	if _caster == null or not _caster.has_method("get_active_bait_distance_meters"):
		return

	var distance_meters := maxf(
		float(_caster.call("get_active_bait_distance_meters")),
		0.0
	)
	var final_surge_trigger := maxf(
		float(_encounter.get("final_surge_trigger_distance_meters")),
		0.05
	)
	var trigger_distance := LessonPolicy.get_trigger_distance(final_surge_trigger)
	if not LessonPolicy.should_open_lesson(
		fight_state,
		distance_meters,
		trigger_distance,
		_attempt_used,
		final_surge_checked,
		final_surge_active
	):
		return

	_attempt_used = true
	_fish_lateral = clampf(float(fight_snapshot.get("lateral", 0.0)), -1.0, 1.0)
	_expected_response = LessonPolicy.get_expected_response(_fish_lateral)
	var fight_context: Dictionary = fight_snapshot.get("fight_context", {})
	_difficulty_tier = clampi(int(fight_context.get("difficulty_tier", 1)), 1, 5)
	_is_king = bool(fight_context.get("is_king", false))
	_response_window_left = LessonPolicy.get_response_window_seconds(
		_difficulty_tier,
		_is_king
	)
	_response_match_time = 0.0
	_set_training_block(true)
	_phase = LessonPhase.RESPONSE_WINDOW
	_show_message(
		"Landing Guide: Final approach — %s!" % LessonPolicy.get_response_label(
			_expected_response,
			_fish_lateral
		),
		3.0
	)


func _update_response_window(delta: float) -> void:
	if _encounter == null:
		return

	var player_reeling := bool(_encounter.get("player_reeling"))
	var player_steering := float(_encounter.get("player_steering"))
	var is_matching := LessonPolicy.is_response_matching(
		_expected_response,
		_fish_lateral,
		player_reeling,
		player_steering
	)
	_response_match_time = LessonPolicy.advance_match_time(
		_response_match_time,
		is_matching,
		delta
	)

	if LessonPolicy.is_response_complete(_response_match_time):
		_complete_lesson()
		return

	_response_window_left = maxf(
		_response_window_left - maxf(delta, 0.0),
		0.0
	)
	if _response_window_left <= 0.0:
		_fail_attempt(
			"Landing Guide: You lost the head line. Finish this fish, then show me a clean approach on the next one.",
			false
		)


func _complete_lesson() -> void:
	var learned := try_learn_technique(true)
	if not bool(learned.get("success", false)):
		_release_training_block(false)
		_phase = LessonPhase.WATCHING_FIGHT
		_show_message(
			"Landing Guide: The approach was right, but the lesson could not be saved yet.",
			3.8
		)
		return

	# The player has just demonstrated the exact landing response. Mark this same
	# fish as secured so Encounter does not immediately ask for Landing Technique
	# a second time after the mastery becomes known.
	if _encounter != null and _encounter.has_method("apply_landing_training_success"):
		_encounter.call(
			"apply_landing_training_success",
			_fish_lateral
		)
	_training_block_owned = false
	_phase = LessonPhase.COMPLETE
	_play_animation(talk_animation)
	_show_message(
		"Technique learned — Landing Technique. Lead a spent fish head-first through the final approach before its last surge.",
		6.0
	)


func _fail_attempt(message: String, final_surge_owns_block: bool) -> void:
	_release_training_block(final_surge_owns_block)
	_reset_response()
	_phase = LessonPhase.WATCHING_FIGHT
	_show_message(message, 4.5)


func _bind_lesson_runtime() -> bool:
	if not _bind_runtime():
		return false
	var fishing := _find_fishing_root()
	if fishing == null:
		return false

	if _encounter == null:
		var raw_encounter = fishing.get("encounter")
		if raw_encounter is Node:
			_encounter = raw_encounter
		if _encounter == null:
			_encounter = fishing.find_child("Encounter", true, false)
	if _caster == null:
		_caster = fishing.get("caster")
	return _encounter != null and _caster != null


func _get_fight_snapshot() -> Dictionary:
	if _encounter == null or not _encounter.has_method("get_fish_debug_snapshot"):
		return {"fight_state": "NONE"}
	return _encounter.call("get_fish_debug_snapshot")


func _set_training_block(active: bool) -> void:
	if _caster == null or not _caster.has_method("set_landing_completion_blocked"):
		return
	_caster.call("set_landing_completion_blocked", active)
	_training_block_owned = active


func _release_training_block(final_surge_owns_block: bool) -> void:
	if not _training_block_owned:
		return
	_training_block_owned = false
	if final_surge_owns_block:
		return
	if _caster != null and _caster.has_method("set_landing_completion_blocked"):
		_caster.call("set_landing_completion_blocked", false)


func _reset_attempt() -> void:
	_attempt_used = false
	_reset_response()


func _reset_response() -> void:
	_response_window_left = 0.0
	_response_match_time = 0.0
	_expected_response = &"none"
	_fish_lateral = 0.0
	_difficulty_tier = 1
	_is_king = false
