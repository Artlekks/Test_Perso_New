extends FishingMasterLessonNPCBase
class_name FishingMasterLineFighterNPC

const LessonPolicy = preload(
	"res://scripts/mastery/fishing_master_line_fighter_policy.gd"
)

const TECHNIQUE_ID: StringName = &"line_feel"
const TEACHER_ID: StringName = &"master_line_fighter"

enum LessonPhase {
	INACTIVE,
	WAITING_FOR_HOOK,
	READING_LINE,
	COMPLETE,
}

var _phase: LessonPhase = LessonPhase.INACTIVE
var _encounter: Node = null

var _pull_armed: bool = false
var _pull_done: bool = false
var _hold_seconds: float = 0.0
var _hold_done: bool = false
var _yield_armed: bool = false
var _yield_done: bool = false

var _last_fight_state: StringName = &"NONE"
var _unsafe_warning_cooldown: float = 0.0


func get_technique_id() -> StringName:
	return TECHNIQUE_ID


func get_teacher_id() -> StringName:
	return TEACHER_ID


func get_known_message() -> String:
	return "Line Fighter: Good. You don't fight the gauge anymore. You feel what the line is asking for."


func get_unavailable_message() -> String:
	return "Line Fighter: I need the live fishing fight to teach this lesson."


func _process(delta: float) -> void:
	if _phase == LessonPhase.INACTIVE or _phase == LessonPhase.COMPLETE:
		return
	if is_technique_known():
		_phase = LessonPhase.COMPLETE
		return
	if not _bind_lesson_runtime():
		return

	_unsafe_warning_cooldown = maxf(_unsafe_warning_cooldown - delta, 0.0)
	var fight_state := _get_fight_state()

	if _phase == LessonPhase.WAITING_FOR_HOOK:
		if fight_state != &"NONE":
			_begin_line_read(fight_state)
		return

	if _phase == LessonPhase.READING_LINE:
		if fight_state == &"NONE":
			_reset_demonstration()
			_phase = LessonPhase.WAITING_FOR_HOOK
			_show_message(
				"Line Fighter: That fish is gone. Hook another one and show me all three reads on a single fight.",
				3.7
			)
			return
		_update_line_read(delta, fight_state)


func _on_lesson_interaction() -> void:
	if not _bind_lesson_runtime():
		_show_message(get_unavailable_message(), 2.4)
		return

	match _phase:
		LessonPhase.INACTIVE:
			_begin_lesson()
		LessonPhase.WAITING_FOR_HOOK:
			_show_message(
				"Line Fighter: Hook a fish. Then show me three things: take up a light line, hold working pressure steady, and yield a heavy line without going slack.",
				5.4
			)
		LessonPhase.READING_LINE:
			_show_progress()
		LessonPhase.COMPLETE:
			pass


func _begin_lesson() -> void:
	_reset_demonstration()
	_phase = LessonPhase.WAITING_FOR_HOOK
	_play_animation(talk_animation)
	_show_message(
		"Line Fighter: Strength isn't line control. Hook one fish. When the line is light, reel it back to working. When it's working, hold it. When it's heavy, yield before it breaks.",
		6.2
	)


func _begin_line_read(fight_state: StringName) -> void:
	_reset_demonstration()
	_phase = LessonPhase.READING_LINE
	_last_fight_state = fight_state
	_show_message(
		"Line Fighter: Feel it. LIGHT → K back to WORKING. WORKING → hold K with W/S neutral. HEAVY → release K or bow with W until it settles — never SLACK.",
		6.0
	)


func _update_line_read(delta: float, fight_state: StringName) -> void:
	_last_fight_state = fight_state
	# Only an actively resisting fish counts. Exhausted/spent pauses the lesson;
	# the same hooked fish may resume if another resistance round begins.
	if fight_state != &"RESISTING":
		return
	if _encounter == null or not _encounter.has_method("get_line_pressure_snapshot"):
		return

	var pressure: Dictionary = _encounter.call("get_line_pressure_snapshot")
	var band: StringName = StringName(pressure.get("band", &"none"))
	var player_reeling := bool(_encounter.get("player_reeling"))
	var tension_bias := float(_encounter.get("player_tension_bias"))

	var result := LessonPolicy.advance_read(
		band,
		player_reeling,
		tension_bias,
		delta,
		_pull_armed,
		_pull_done,
		_hold_seconds,
		_hold_done,
		_yield_armed,
		_yield_done
	)

	_pull_armed = bool(result.get("pull_armed", false))
	_pull_done = bool(result.get("pull_done", false))
	_hold_seconds = float(result.get("hold_seconds", 0.0))
	_hold_done = bool(result.get("hold_done", false))
	_yield_armed = bool(result.get("yield_armed", false))
	_yield_done = bool(result.get("yield_done", false))

	if bool(result.get("pull_completed_now", false)):
		_show_message(
			"Line Fighter: That's the pull. You felt the light line and took it up without overshooting.",
			3.2
		)
	if bool(result.get("hold_completed_now", false)):
		_show_message(
			"Line Fighter: That's the hold. Working pressure doesn't need constant correction.",
			3.0
		)
	if bool(result.get("yield_completed_now", false)):
		_show_message(
			"Line Fighter: That's the yield. You gave the fish line without giving it slack.",
			3.2
		)

	if bool(result.get("unsafe", false)) and _unsafe_warning_cooldown <= 0.0:
		_unsafe_warning_cooldown = 1.5
		if band == LessonPolicy.BAND_SLACK:
			_show_message(
				"Line Fighter: Too far. Yield is controlled pressure — not a loose line.",
				2.5
			)
		elif band == LessonPolicy.BAND_OVERLOAD:
			_show_message(
				"Line Fighter: That's overload. Feel HEAVY before the line reaches breaking pressure.",
				2.5
			)

	if bool(result.get("complete", false)):
		_complete_lesson()


func _show_progress() -> void:
	var hold_percent := 100 if _hold_done else int(round(clampf(
		_hold_seconds / maxf(LessonPolicy.REQUIRED_HOLD_SECONDS, 0.001),
		0.0,
		1.0
	) * 100.0))
	_show_message(
		"Line Fighter: Pull %s  |  Hold %s  |  Yield %s"
		% [
			"OK" if _pull_done else "--",
			"OK" if _hold_done else "%d%%" % hold_percent,
			"OK" if _yield_done else "--",
		],
		3.0
	)


func _complete_lesson() -> void:
	var learned := try_learn_technique(true)
	if bool(learned.get("success", false)):
		_phase = LessonPhase.COMPLETE
		_play_animation(talk_animation)
		_show_message(
			"Technique learned — Line Feel. Light, working and heavy pressure now mean something before the line ever fails.",
			5.2
		)
		return
	_show_message(
		"Line Fighter: The read was right, but the lesson could not be saved yet.",
		3.2
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
	return _encounter != null


func _get_fight_state() -> StringName:
	if _encounter == null or not _encounter.has_method("get_fish_debug_snapshot"):
		return &"NONE"
	var snapshot: Dictionary = _encounter.call("get_fish_debug_snapshot")
	return StringName(str(snapshot.get("fight_state", "NONE")))


func _reset_demonstration() -> void:
	_pull_armed = false
	_pull_done = false
	_hold_seconds = 0.0
	_hold_done = false
	_yield_armed = false
	_yield_done = false
	_last_fight_state = &"NONE"
	_unsafe_warning_cooldown = 0.0
