extends Node
class_name FishingTension

signal tension_changed(value: float)
signal state_changed(state: State)
signal hook_off
signal line_broken

enum State {
	SLACK,
	SAFE,
	OVERLOAD
}

@export_category("Free Reel")
@export_range(0.0, 1.0, 0.01) var free_reel_start: float = 0.05
@export_range(0.0, 1.0, 0.01) var free_reel_max: float = 0.18
@export var free_reel_gain_speed: float = 0.08
@export var free_reel_loss_speed: float = 0.10

@export_category("Safe Zone")
@export_range(0.0, 1.0, 0.01) var safe_min: float = 0.35
@export_range(0.0, 1.0, 0.01) var safe_max: float = 0.55

@export_category("Fight Balance")
# The old prototype applied two 0.18 response steps every frame.
# 0.36 preserves that established feel with one clear update.
@export var tension_response_speed: float = 0.36
# The old release path effectively moved at 0.12 + 0.18 per second.
@export var release_tension_speed: float = 0.30
@export var reel_target_offset: float = 0.03
@export var passive_resistance_offset: float = 0.08
@export var directional_tension_speed: float = 0.035
@export_range(0.0, 1.0, 0.05) var thrash_threshold: float = 0.70
@export var thrash_target_offset: float = 0.25

@export_category("Failure")
@export var line_break_delay: float = 1.5

var value: float = 0.45
var active: bool = false
var player_reeling: bool = false
var fish_resistance: float = 0.0
var current_state: State = State.SAFE
var failure_enabled: bool = false
var reel_gain_multiplier: float = 1.0
var player_tension_bias: float = 0.0
var overload_time: float = 0.0


func _process(delta: float) -> void:
	if not active:
		return

	if not failure_enabled:
		_update_free_reel(delta)
		return

	_update_fight_tension(delta)


func _update_free_reel(delta: float) -> void:
	var change := free_reel_gain_speed if player_reeling else -free_reel_loss_speed

	value = clampf(
		value + change * delta,
		0.0,
		free_reel_max
	)

	tension_changed.emit(value)
	_update_state()


func _update_fight_tension(delta: float) -> void:
	var safe_center := (safe_min + safe_max) * 0.5
	var target_tension := 0.0
	var response_speed := release_tension_speed

	if player_reeling:
		target_tension = safe_center
		target_tension += reel_target_offset * reel_gain_multiplier
		target_tension += fish_resistance * passive_resistance_offset

		if fish_resistance > thrash_threshold:
			var thrash_amount := inverse_lerp(
				thrash_threshold,
				1.0,
				fish_resistance
			)
			target_tension += thrash_amount * thrash_target_offset

		# The previous implementation applied this bias in both of its
		# sequential update passes. Multiplying by two preserves the
		# established W/S resting target without the duplicate simulation.
		target_tension += (
			player_tension_bias
			* directional_tension_speed
			* 2.0
		)
		response_speed = tension_response_speed

	target_tension = clampf(target_tension, 0.0, 1.0)
	value = move_toward(
		value,
		target_tension,
		response_speed * delta
	)

	tension_changed.emit(value)
	_update_state()
	_update_failure(delta)


func _update_failure(delta: float) -> void:
	if value <= 0.0:
		active = false
		hook_off.emit()
		return

	if current_state == State.OVERLOAD:
		overload_time += delta

		if overload_time >= line_break_delay:
			active = false
			overload_time = 0.0
			line_broken.emit()
	else:
		overload_time = 0.0


func set_reel_gain_multiplier(multiplier: float) -> void:
	reel_gain_multiplier = maxf(multiplier, 0.0)


func start() -> void:
	value = (safe_min + safe_max) * 0.5
	active = true
	failure_enabled = true
	player_reeling = false
	reel_gain_multiplier = 1.0
	overload_time = 0.0

	_update_state()
	tension_changed.emit(value)


func stop() -> void:
	active = false
	player_reeling = false
	fish_resistance = 0.0
	failure_enabled = false
	overload_time = 0.0


func set_player_reeling(reeling: bool) -> void:
	player_reeling = reeling


func set_fish_resistance(resistance: float) -> void:
	fish_resistance = clampf(resistance, 0.0, 1.0)


func _update_state() -> void:
	var new_state: State

	if not failure_enabled:
		new_state = State.SAFE
	elif value < safe_min:
		new_state = State.SLACK
	elif value > safe_max:
		new_state = State.OVERLOAD
	else:
		new_state = State.SAFE

	if new_state == current_state:
		return

	current_state = new_state
	state_changed.emit(current_state)


func start_free_reel() -> void:
	value = free_reel_start
	active = true
	failure_enabled = false
	player_reeling = false
	fish_resistance = 0.0

	_update_state()
	tension_changed.emit(value)


func add_impulse(amount: float) -> void:
	if not active:
		return

	value = clampf(value + amount, 0.0, 1.0)
	tension_changed.emit(value)
	_update_state()


func set_player_tension_bias(bias: float) -> void:
	player_tension_bias = clampf(bias, -1.0, 1.0)
