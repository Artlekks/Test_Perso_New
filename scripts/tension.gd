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

@export_range(0.0, 1.0, 0.01) var start_tension: float = 0.45

@export_category("Free Reel")
@export_range(0.0, 1.0, 0.01) var free_reel_start: float = 0.05
@export_range(0.0, 1.0, 0.01) var free_reel_max: float = 0.18
@export var free_reel_gain_speed: float = 0.08
@export var free_reel_loss_speed: float = 0.10

@export_category("Safe Zone")
@export_range(0.0, 1.0, 0.01) var safe_min: float = 0.35
@export_range(0.0, 1.0, 0.01) var safe_max: float = 0.55

@export_category("Tension Speeds")
@export var reel_gain_speed: float = 0.20
@export var release_loss_speed: float = 0.18
@export var resistance_gain_speed: float = 0.10
@export var directional_tension_speed: float = 0.035
@export_category("Failure")
@export var line_break_delay: float = 1.5
@export_category("Fight Start")
@export var hit_grace_time: float = 0.75
@export_category("Fight Balance")

# How quickly tension moves toward its desired position.
@export var tension_response_speed: float = 0.18

# Small player influence around the center.
@export var reel_target_offset: float = 0.03

# Fish resistance below this does not push the bar toward danger.
@export_range(0.0, 1.0, 0.05)
var thrash_threshold: float = 0.70

# Maximum additional tension caused by a fully thrashing fish.
@export var thrash_target_offset: float = 0.25
@export var release_tension_speed: float = 0.12
@export var passive_resistance_offset: float = 0.08

var value: float = 0.45
var active: bool = false
var player_reeling: bool = false
var fish_resistance: float = 0.0
var current_state: State = State.SAFE
var failure_enabled: bool = false
var reel_gain_multiplier: float = 1.0
var player_tension_bias: float = 0.0
var overload_time: float = 0.0
var hit_grace_time_left: float = 0.0

func _process(delta: float) -> void:
	if not active:
		return

	# ---------------------------------------------------------
	# FREE REEL
	# Keep the old simple behaviour before a fish is hooked.
	# ---------------------------------------------------------
	if not failure_enabled:
		var change := 0.0

		if player_reeling:
			change += free_reel_gain_speed
		else:
			change -= free_reel_loss_speed

		value = clampf(
			value + change * delta,
			0.0,
			free_reel_max
		)

		tension_changed.emit(value)
		_update_state()
		return


	# ---------------------------------------------------------
	# FISH FIGHT
	# Tension naturally wants to stay around the middle.
	# ---------------------------------------------------------
	var safe_center := (safe_min + safe_max) * 0.5

	var target_tension: float = 0.0
	var response_speed: float = release_tension_speed

	if player_reeling:
		# K held: tension naturally settles around the safe center.
		target_tension = safe_center

		target_tension += (
			reel_target_offset
			* reel_gain_multiplier
		)

		# Even normal fish resistance gives the gauge
		# a little organic movement.
		target_tension += (
			fish_resistance
			* passive_resistance_offset
		)

		# Only genuine thrashing adds serious danger.
		if fish_resistance > thrash_threshold:
			var thrash_amount := inverse_lerp(
				thrash_threshold,
				1.0,
				fish_resistance
			)

			target_tension += (
				thrash_amount
				* thrash_target_offset
			)

		target_tension += (
			player_tension_bias
			* directional_tension_speed
		)

		response_speed = tension_response_speed


	target_tension = clampf(
		target_tension,
		0.0,
		1.0
	)

	value = move_toward(
		value,
		target_tension,
		response_speed * delta
	)
	# W/S can still bias tension.
	if player_reeling:
		target_tension += (
			player_tension_bias
			* directional_tension_speed
		)


	target_tension = clampf(
		target_tension,
		0.0,
		1.0
	)


	# Smoothly move toward the desired tension instead of
	# constantly accumulating tension forever.
	value = move_toward(
		value,
		target_tension,
		tension_response_speed * delta
	)

	tension_changed.emit(value)

	_update_state()


	# Slack failure.
	if value <= 0.0:
		active = false
		hook_off.emit()
		return


	# Overload failure.
	if current_state == State.OVERLOAD:
		overload_time += delta

		if overload_time >= line_break_delay:
			active = false
			overload_time = 0.0
			line_broken.emit()
			return
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
	hit_grace_time_left = hit_grace_time
	
	_update_state()
	tension_changed.emit(value)

func stop() -> void:
	active = false
	player_reeling = false
	fish_resistance = 0.0
	failure_enabled = false
	overload_time = 0.0
	hit_grace_time_left = 0.0
	
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

	var max_value := 1.0 if failure_enabled else free_reel_max
	value = clampf(value + amount, 0.0, max_value)

	tension_changed.emit(value)
	_update_state()

func set_player_tension_bias(bias: float) -> void:
	player_tension_bias = clampf(bias, -1.0, 1.0)
	
