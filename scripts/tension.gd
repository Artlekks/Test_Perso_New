extends Node
class_name FishingTension

signal tension_changed(value: float)
signal state_changed(state: State)
signal hook_off
signal line_broken
signal tuning_changed(safe_min: float, safe_max: float)

enum State {
	SLACK,
	SAFE,
	OVERLOAD,
}

enum FailureReason {
	NONE,
	HOOK_OFF,
	LINE_BREAK,
}

const DefaultTensionProfile: FishingTensionProfile = preload(
	"res://data/bof4/fight/default_tension.tres"
)

# Exact defaults of the pre-profile script. They are used only to detect old
# scene-level overrides and migrate them into the cached runtime profile.
const LEGACY_FREE_REEL_START: float = 0.05
const LEGACY_FREE_REEL_MAX: float = 0.18
const LEGACY_FREE_REEL_GAIN_SPEED: float = 0.08
const LEGACY_FREE_REEL_LOSS_SPEED: float = 0.10
const LEGACY_SAFE_MIN: float = 0.35
const LEGACY_SAFE_MAX: float = 0.55
const LEGACY_TENSION_RESPONSE_SPEED: float = 0.36
const LEGACY_RELEASE_TENSION_SPEED: float = 0.30
const LEGACY_REEL_TARGET_OFFSET: float = 0.03
const LEGACY_PASSIVE_RESISTANCE_OFFSET: float = 0.08
const LEGACY_DIRECTIONAL_TENSION_SPEED: float = 0.035
const LEGACY_THRASH_THRESHOLD: float = 0.70
const LEGACY_THRASH_TARGET_OFFSET: float = 0.25
const LEGACY_LINE_BREAK_DELAY: float = 1.50

@export_category("Tension Backend")
@export var tension_profile: FishingTensionProfile = DefaultTensionProfile

@export_category("Legacy Scene Compatibility")
## Existing scene overrides still deserialize into these properties. Runtime
## behavior is copied once into a private profile and never reads these in the
## hot loop afterward.
@export_range(0.0, 1.0, 0.01)
var free_reel_start: float = LEGACY_FREE_REEL_START

@export_range(0.0, 1.0, 0.01)
var free_reel_max: float = LEGACY_FREE_REEL_MAX

@export var free_reel_gain_speed: float = LEGACY_FREE_REEL_GAIN_SPEED
@export var free_reel_loss_speed: float = LEGACY_FREE_REEL_LOSS_SPEED

@export_range(0.0, 1.0, 0.01)
var safe_min: float = LEGACY_SAFE_MIN

@export_range(0.0, 1.0, 0.01)
var safe_max: float = LEGACY_SAFE_MAX

@export var tension_response_speed: float = LEGACY_TENSION_RESPONSE_SPEED
@export var release_tension_speed: float = LEGACY_RELEASE_TENSION_SPEED
@export var reel_target_offset: float = LEGACY_REEL_TARGET_OFFSET
@export var passive_resistance_offset: float = LEGACY_PASSIVE_RESISTANCE_OFFSET
@export var directional_tension_speed: float = LEGACY_DIRECTIONAL_TENSION_SPEED

@export_range(0.0, 1.0, 0.05)
var thrash_threshold: float = LEGACY_THRASH_THRESHOLD

@export var thrash_target_offset: float = LEGACY_THRASH_TARGET_OFFSET
@export var line_break_delay: float = LEGACY_LINE_BREAK_DELAY

var value: float = 0.45
var active: bool = false
var player_reeling: bool = false
var fish_resistance: float = 0.0
var current_state: State = State.SAFE
var failure_enabled: bool = false
var reel_gain_multiplier: float = 1.0
var player_tension_bias: float = 0.0

var overload_time: float = 0.0
var hook_off_time: float = 0.0
var line_tolerance_multiplier: float = 1.0
var hook_off_delay_multiplier: float = 1.0
var last_target_tension: float = 0.0
var last_failure_reason: FailureReason = FailureReason.NONE

var _runtime_profile: FishingTensionProfile = null


func _ready() -> void:
	_rebuild_runtime_profile()
	set_process(false)


func _process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	# Single deterministic update entry point. Runtime _process and regression
	# simulations use the exact same path, so frame-rate/input stress tests cannot
	# accidentally exercise a second implementation.
	if not active or delta <= 0.0:
		return

	if not failure_enabled:
		_update_free_reel(delta)
		return

	_update_fight_tension(delta)


func configure_profile(
	profile: FishingTensionProfile
) -> void:
	if profile == null or not profile.is_valid_profile():
		return

	tension_profile = profile
	_rebuild_runtime_profile()


func _rebuild_runtime_profile() -> void:
	var source: FishingTensionProfile = tension_profile

	if source == null or not source.is_valid_profile():
		source = DefaultTensionProfile

	_runtime_profile = source.duplicate(true) as FishingTensionProfile

	if _runtime_profile == null:
		_runtime_profile = FishingTensionProfile.new()

	# Migration-safe compatibility: only values that differ from the old script
	# defaults are interpreted as scene overrides. This preserves the current
	# FishingTestScene's safe_min=.32, safe_max=.72, break_delay=2.5 exactly.
	_apply_legacy_override(
		&"free_reel_start",
		free_reel_start,
		LEGACY_FREE_REEL_START
	)
	_apply_legacy_override(
		&"free_reel_max",
		free_reel_max,
		LEGACY_FREE_REEL_MAX
	)
	_apply_legacy_override(
		&"free_reel_gain_speed",
		free_reel_gain_speed,
		LEGACY_FREE_REEL_GAIN_SPEED
	)
	_apply_legacy_override(
		&"free_reel_loss_speed",
		free_reel_loss_speed,
		LEGACY_FREE_REEL_LOSS_SPEED
	)
	_apply_legacy_override(
		&"safe_min",
		safe_min,
		LEGACY_SAFE_MIN
	)
	_apply_legacy_override(
		&"safe_max",
		safe_max,
		LEGACY_SAFE_MAX
	)
	_apply_legacy_override(
		&"tension_response_speed",
		tension_response_speed,
		LEGACY_TENSION_RESPONSE_SPEED
	)
	_apply_legacy_override(
		&"release_tension_speed",
		release_tension_speed,
		LEGACY_RELEASE_TENSION_SPEED
	)
	_apply_legacy_override(
		&"reel_target_offset",
		reel_target_offset,
		LEGACY_REEL_TARGET_OFFSET
	)
	_apply_legacy_override(
		&"passive_resistance_offset",
		passive_resistance_offset,
		LEGACY_PASSIVE_RESISTANCE_OFFSET
	)
	_apply_legacy_override(
		&"directional_tension_speed",
		directional_tension_speed,
		LEGACY_DIRECTIONAL_TENSION_SPEED
	)
	_apply_legacy_override(
		&"thrash_threshold",
		thrash_threshold,
		LEGACY_THRASH_THRESHOLD
	)
	_apply_legacy_override(
		&"thrash_target_offset",
		thrash_target_offset,
		LEGACY_THRASH_TARGET_OFFSET
	)
	_apply_legacy_override(
		&"line_break_delay",
		line_break_delay,
		LEGACY_LINE_BREAK_DELAY
	)

	tuning_changed.emit(
		_runtime_profile.safe_min,
		_runtime_profile.safe_max
	)


func _apply_legacy_override(
	property_name: StringName,
	legacy_value: float,
	legacy_default: float
) -> void:
	if is_equal_approx(
		legacy_value,
		legacy_default
	):
		return

	_runtime_profile.set(
		property_name,
		legacy_value
	)


func _get_profile() -> FishingTensionProfile:
	if _runtime_profile == null:
		_rebuild_runtime_profile()

	return _runtime_profile


func _update_free_reel(delta: float) -> void:
	var profile: FishingTensionProfile = _get_profile()
	var change: float = (
		profile.free_reel_gain_speed
		if player_reeling
		else -profile.free_reel_loss_speed
	)

	value = clampf(
		value + change * delta,
		0.0,
		profile.free_reel_max
	)

	last_target_tension = value
	tension_changed.emit(value)
	_update_state()


func _update_fight_tension(delta: float) -> void:
	var profile: FishingTensionProfile = _get_profile()
	var safe_center: float = profile.get_safe_center()
	var target_tension: float = 0.0
	var response_speed: float = profile.release_tension_speed

	if player_reeling:
		target_tension = safe_center
		target_tension += (
			profile.reel_target_offset
			* reel_gain_multiplier
		)
		target_tension += (
			fish_resistance
			* profile.passive_resistance_offset
		)

		if fish_resistance > profile.thrash_threshold:
			var thrash_amount: float = inverse_lerp(
				profile.thrash_threshold,
				1.0,
				fish_resistance
			)
			target_tension += (
				thrash_amount
				* profile.thrash_target_offset
			)

		# Preserve the established W/S influence from the previous runtime.
		target_tension += (
			player_tension_bias
			* profile.directional_tension_speed
			* 2.0
		)
		response_speed = profile.tension_response_speed

	target_tension = clampf(
		target_tension,
		0.0,
		1.0
	)
	last_target_tension = target_tension

	value = move_toward(
		value,
		target_tension,
		response_speed * delta
	)

	tension_changed.emit(value)
	_update_state()
	_update_failure(delta)


func _update_failure(delta: float) -> void:
	var profile: FishingTensionProfile = _get_profile()

	if value <= profile.hook_off_threshold:
		var effective_hook_off_delay := get_effective_hook_off_delay()
		if effective_hook_off_delay <= 0.0:
			_trigger_hook_off()
			return

		hook_off_time += delta

		if hook_off_time >= effective_hook_off_delay:
			_trigger_hook_off()
			return
	else:
		hook_off_time = 0.0

	if current_state == State.OVERLOAD:
		overload_time += delta

		if overload_time >= get_effective_line_break_delay():
			_trigger_line_break()
	else:
		overload_time = 0.0


func _trigger_hook_off() -> void:
	if not active or last_failure_reason != FailureReason.NONE:
		return

	last_failure_reason = FailureReason.HOOK_OFF
	active = false
	hook_off_time = 0.0
	overload_time = 0.0
	set_process(false)
	hook_off.emit()


func _trigger_line_break() -> void:
	if not active or last_failure_reason != FailureReason.NONE:
		return

	last_failure_reason = FailureReason.LINE_BREAK
	active = false
	hook_off_time = 0.0
	overload_time = 0.0
	set_process(false)
	line_broken.emit()


func set_reel_gain_multiplier(
	multiplier: float
) -> void:
	reel_gain_multiplier = maxf(
		multiplier,
		0.0
	)


func set_line_tolerance_multiplier(
	multiplier: float
) -> void:
	line_tolerance_multiplier = maxf(
		multiplier,
		0.01
	)


func get_effective_line_break_delay() -> float:
	return maxf(
		_get_profile().line_break_delay
		* line_tolerance_multiplier,
		0.0
	)


func set_hook_off_delay_multiplier(multiplier: float) -> void:
	hook_off_delay_multiplier = maxf(multiplier, 0.01)


func get_effective_hook_off_delay() -> float:
	return maxf(
		_get_profile().hook_off_delay
		* hook_off_delay_multiplier,
		0.0
	)


func start() -> void:
	var profile: FishingTensionProfile = _get_profile()

	value = profile.get_safe_center()
	active = true
	failure_enabled = true
	player_reeling = false
	fish_resistance = 0.0
	reel_gain_multiplier = 1.0
	player_tension_bias = 0.0
	overload_time = 0.0
	hook_off_time = 0.0
	last_failure_reason = FailureReason.NONE
	last_target_tension = value
	set_process(true)

	_update_state()
	tension_changed.emit(value)


func stop() -> void:
	active = false
	player_reeling = false
	fish_resistance = 0.0
	failure_enabled = false
	reel_gain_multiplier = 1.0
	player_tension_bias = 0.0
	overload_time = 0.0
	hook_off_time = 0.0
	last_target_tension = 0.0
	set_process(false)

	# Stopped means neutral. Do not leave stale OVERLOAD/SLACK or a stale gauge
	# value around for debug/UI consumers after a catch, failure, or recast.
	value = 0.0
	if current_state != State.SAFE:
		current_state = State.SAFE
		state_changed.emit(current_state)
	tension_changed.emit(value)


func set_player_reeling(
	reeling: bool
) -> void:
	player_reeling = reeling


func set_fish_resistance(
	resistance: float
) -> void:
	fish_resistance = clampf(
		resistance,
		0.0,
		1.0
	)


func _update_state() -> void:
	var profile: FishingTensionProfile = _get_profile()
	var new_state: State

	if not failure_enabled:
		new_state = State.SAFE
	elif value < profile.safe_min:
		new_state = State.SLACK
	elif value > profile.safe_max:
		new_state = State.OVERLOAD
	else:
		new_state = State.SAFE

	if new_state == current_state:
		return

	current_state = new_state
	state_changed.emit(current_state)


func start_free_reel() -> void:
	var profile: FishingTensionProfile = _get_profile()

	value = profile.free_reel_start
	active = true
	failure_enabled = false
	player_reeling = false
	fish_resistance = 0.0
	reel_gain_multiplier = 1.0
	player_tension_bias = 0.0
	overload_time = 0.0
	hook_off_time = 0.0
	last_failure_reason = FailureReason.NONE
	last_target_tension = value
	set_process(true)

	_update_state()
	tension_changed.emit(value)


func add_impulse(amount: float) -> void:
	if not active:
		return

	value = clampf(
		value + amount,
		0.0,
		1.0
	)
	tension_changed.emit(value)
	_update_state()


func set_player_tension_bias(
	bias: float
) -> void:
	player_tension_bias = clampf(
		bias,
		-1.0,
		1.0
	)


func get_state_label() -> String:
	match current_state:
		State.SLACK:
			return "SLACK"
		State.OVERLOAD:
			return "OVERLOAD"
		_:
			return "SAFE"


func get_failure_reason_label() -> String:
	match last_failure_reason:
		FailureReason.HOOK_OFF:
			return "HOOK_OFF"
		FailureReason.LINE_BREAK:
			return "LINE_BREAK"
		_:
			return "NONE"


func get_debug_snapshot() -> Dictionary:
	var profile: FishingTensionProfile = _get_profile()
	var break_delay: float = get_effective_line_break_delay()
	var hook_delay: float = get_effective_hook_off_delay()
	var break_progress: float = 0.0
	var escape_progress: float = 0.0

	if break_delay > 0.0:
		break_progress = clampf(
			overload_time / break_delay,
			0.0,
			1.0
		)
	elif current_state == State.OVERLOAD:
		break_progress = 1.0

	if hook_delay > 0.0:
		escape_progress = clampf(
			hook_off_time / hook_delay,
			0.0,
			1.0
		)
	elif value <= profile.hook_off_threshold:
		escape_progress = 1.0

	return {
		"active": active,
		"failure_enabled": failure_enabled,
		"value": value,
		"state": current_state,
		"state_label": get_state_label(),
		"safe_min": profile.safe_min,
		"safe_max": profile.safe_max,
		"target": last_target_tension,
		"fish_resistance": fish_resistance,
		"player_reeling": player_reeling,
		"reel_gain_multiplier": reel_gain_multiplier,
		"player_tension_bias": player_tension_bias,
		"line_tolerance_multiplier": line_tolerance_multiplier,
		"base_line_break_delay": profile.line_break_delay,
		"effective_line_break_delay": break_delay,
		"overload_time": overload_time,
		"break_progress": break_progress,
		"hook_off_threshold": profile.hook_off_threshold,
		"base_hook_off_delay": profile.hook_off_delay,
		"hook_off_delay_multiplier": hook_off_delay_multiplier,
		"hook_off_delay": hook_delay,
		"effective_hook_off_delay": hook_delay,
		"hook_off_time": hook_off_time,
		"escape_progress": escape_progress,
		"last_failure_reason": last_failure_reason,
		"last_failure_label": get_failure_reason_label(),
		"profile": profile.get_debug_summary(),
	}
