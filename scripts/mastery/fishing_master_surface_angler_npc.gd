extends FishingMasterLessonNPCBase
class_name FishingMasterSurfaceAnglerNPC

const LessonPolicy = preload(
	"res://scripts/mastery/fishing_master_surface_angler_policy.gd"
)

const TECHNIQUE_ID: StringName = &"surface_control"
const TEACHER_ID: StringName = &"master_surface_angler"


enum LessonPhase {
	INACTIVE,
	WAITING_FOR_HOOK,
	READING_SURFACE,
	RESPONSE_WINDOW,
	COMPLETE,
}


var _phase: LessonPhase = LessonPhase.INACTIVE
var _encounter: Node = null
var _surface_signal_connected: bool = false

var _response_window_left: float = 0.0
var _response_match_time: float = 0.0
var _expected_response: StringName = &"none"
var _intent_snapshot: Dictionary = {}


func get_technique_id() -> StringName:
	return TECHNIQUE_ID


func get_teacher_id() -> StringName:
	return TEACHER_ID


func get_known_message() -> String:
	return "Surface Angler: Good. You know how to keep a hot fish under the water instead of fighting it upright."


func get_unavailable_message() -> String:
	return "Surface Angler: I need the live fishing fight to teach this lesson."


func _process(delta: float) -> void:
	if _phase == LessonPhase.INACTIVE or _phase == LessonPhase.COMPLETE:
		return
	if is_technique_known():
		_phase = LessonPhase.COMPLETE
		return
	if not _bind_lesson_runtime():
		return

	var fight_state := _get_fight_state()
	if _phase == LessonPhase.WAITING_FOR_HOOK:
		if fight_state != &"NONE":
			_phase = LessonPhase.READING_SURFACE
			_show_message(
				"Surface Angler: Bring the fish up. When it gets violent near the surface, keep the rod LOW with W and preserve the correct run response.",
				5.0
			)
		return

	if fight_state == &"NONE":
		_reset_attempt()
		_phase = LessonPhase.WAITING_FOR_HOOK
		_show_message(
			"Surface Angler: That fish is gone. Hook another and bring it up into the surface layer.",
			3.6
		)
		return

	if _phase == LessonPhase.RESPONSE_WINDOW:
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
				"Surface Angler: Hook a fish. Bring it near the top, then read its burst with the rod kept low — W plus the normal response.",
				5.0
			)
		LessonPhase.READING_SURFACE:
			_show_message(
				"Surface Angler: Keep fighting. I want a real surface burst, not a jump and not the final landing.",
				4.0
			)
		LessonPhase.RESPONSE_WINDOW:
			_show_message(
				"Surface Angler: NOW — %s." % LessonPolicy.get_response_label(_expected_response),
				2.6
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
				"Surface Angler: Not yet. Learn Line Feel first. Surface fish punish anyone who can't feel the line.",
				4.8
			)
			return
		_show_message("Surface Angler: The lesson isn't available yet.", 3.0)
		return

	_reset_attempt()
	_phase = LessonPhase.WAITING_FOR_HOOK
	_play_animation(talk_animation)
	_show_message(
		"Surface Angler: Near the top, don't lift against every burst. Keep the rod LOW with W, then preserve the fish's normal read — ease, reel, counter, or stay steady. Show me once.",
		7.0
	)


func _on_surface_instability_started(surface_snapshot: Dictionary) -> void:
	if _phase != LessonPhase.READING_SURFACE:
		return
	if _encounter == null or not _encounter.has_method("get_fish_debug_snapshot"):
		return

	var fight_snapshot: Dictionary = _encounter.call("get_fish_debug_snapshot")
	if StringName(str(fight_snapshot.get("fight_state", "NONE"))) != &"RESISTING":
		return

	var intent: Dictionary = fight_snapshot.get("fight_intent", {})
	if not LessonPolicy.is_qualifying_event(surface_snapshot, intent):
		return

	_expected_response = LessonPolicy.get_expected_response(intent)
	_intent_snapshot = intent.duplicate(true)
	_response_window_left = LessonPolicy.get_response_window_seconds(intent)
	_response_match_time = 0.0
	_phase = LessonPhase.RESPONSE_WINDOW
	_show_message(
		"Surface Angler: Surface burst — %s!" % LessonPolicy.get_response_label(_expected_response),
		2.8
	)


func _update_response_window(delta: float) -> void:
	if _encounter == null:
		return

	var player_reeling := bool(_encounter.get("player_reeling"))
	var player_steering := float(_encounter.get("player_steering"))
	var tension_bias := float(_encounter.get("player_tension_bias"))
	var is_matching := LessonPolicy.is_response_matching(
		_expected_response,
		_intent_snapshot,
		player_reeling,
		player_steering,
		tension_bias
	)
	_response_match_time = LessonPolicy.advance_match_time(
		_response_match_time,
		is_matching,
		delta
	)

	if LessonPolicy.is_response_complete(_response_match_time):
		_complete_lesson()
		return

	_response_window_left = maxf(_response_window_left - maxf(delta, 0.0), 0.0)
	if _response_window_left <= 0.0:
		_phase = LessonPhase.READING_SURFACE
		_reset_response()
		_show_message(
			"Surface Angler: Too late. Keep fighting and wait for the next real surface burst.",
			3.5
		)


func _complete_lesson() -> void:
	var learned := try_learn_technique(true)
	if bool(learned.get("success", false)):
		_phase = LessonPhase.COMPLETE
		_play_animation(talk_animation)
		_show_message(
			"Technique learned — Surface Control. Near the top, keep W / low rod and preserve the correct fish response.",
			5.8
		)
		return

	_phase = LessonPhase.READING_SURFACE
	_reset_response()
	_show_message(
		"Surface Angler: The control was right, but the lesson could not be saved yet.",
		3.5
	)


func _bind_lesson_runtime() -> bool:
	if not _bind_runtime():
		return false
	if _encounter == null:
		var fishing := _find_fishing_root()
		if fishing != null:
			var raw_encounter = fishing.get("encounter")
			if raw_encounter is Node:
				_encounter = raw_encounter
			if _encounter == null:
				_encounter = fishing.find_child("Encounter", true, false)

	if _encounter != null and not _surface_signal_connected:
		if _encounter.has_signal("surface_instability_started"):
			_encounter.connect(
				"surface_instability_started",
				Callable(self, "_on_surface_instability_started")
			)
			_surface_signal_connected = true
	return _encounter != null


func _get_fight_state() -> StringName:
	if _encounter == null or not _encounter.has_method("get_fish_debug_snapshot"):
		return &"NONE"
	var snapshot: Dictionary = _encounter.call("get_fish_debug_snapshot")
	return StringName(str(snapshot.get("fight_state", "NONE")))


func _reset_attempt() -> void:
	_reset_response()


func _reset_response() -> void:
	_response_window_left = 0.0
	_response_match_time = 0.0
	_expected_response = &"none"
	_intent_snapshot.clear()
