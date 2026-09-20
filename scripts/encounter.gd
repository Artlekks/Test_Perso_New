extends Node

signal bite_opportunity_started
signal bite_triggered
signal bite_missed
signal fish_hooked
signal fish_caught(fish: FishInstance)
signal fish_stamina_changed(current: float, maximum: float)
signal fish_exhausted
signal fish_resistance_changed(value: float)
signal fish_pull_changed(value: float)
signal fish_movement_changed(lateral: float)
signal fish_depth_intent_changed(value: float)
signal tension_changed(value: float)
signal tension_state_changed(state: int)
signal hook_off
signal line_broken
signal fish_resistance_started
signal fish_spent

@onready var bite_window_timer: Timer = $BiteWindowTimer
@onready var bite_timer: Timer = $BiteTimer
@onready var fish_behavior: Node = $FishBehavior
@onready var fish_selector: FishSelector = $FishSelector
@onready var tension: FishingTension = $Tension

@export var max_fish_stamina: float = 100.0
@export var stamina_drain_speed: float = 30.0
@export var stamina_recovery_speed: float = 10.0
@export var caster: Node

@export_category("Spent Recovery")
@export_range(0.0, 1.0, 0.05)
var spent_behavior_intensity: float = 0.20

@export_range(0.0, 1.0, 0.05)
var spent_resistance: float = 0.18

@export_range(0.0, 1.0, 0.05)
var spent_pull_strength: float = 0.20
@export var spent_recovery_time: float = 5.0
@export_range(0.0, 1.0, 0.05) var spent_recovery_stamina_ratio: float = 0.35
@export_range(0.0, 1.0, 0.05) var spent_restart_intensity: float = 0.65
@export var spent_tension_multiplier: float = 0.12
@export var spent_reel_speed_multiplier: float = 4.0

@export_category("Directional Fatigue")
@export var counter_steer_fatigue_multiplier: float = 1.35
@export var steering_deadzone: float = 0.2

@export var first_bite_delay: float = 0.5
@export var retry_bite_delay: float = 0.5
@export_range(0.0, 1.0, 0.05)
var direct_hit_chance: float = 0.5

@export_range(0.0, 1.0, 0.05)
var max_bite_chance_per_check: float = 1.0

@export_category("Release Movement")
@export_range(0.0, 1.0, 0.05)
var release_movement_intensity: float = 0.40

@export_range(0.0, 1.0, 0.05)
var spent_release_movement_intensity: float = 0.22

@export_category("Fight State Movement")

@export_range(0.0, 1.0, 0.05)
var resisting_behavior_intensity: float = 1.0

@export_range(0.0, 1.0, 0.05)
var exhausted_behavior_intensity: float = 0.30

@export_range(0.0, 1.0, 0.05)
var exhausted_resistance: float = 0.10

@export_range(0.0, 1.0, 0.05)
var exhausted_pull_strength: float = 0.18

var fish_behavior_pressure: float = 0.0
var current_tension_state: int = FishingTension.State.SAFE
var player_steering: float = 0.0
var current_fish_lateral: float = 0.0

enum FightState {
	NONE,
	RESISTING,
	EXHAUSTED,
	SPENT
}

var fish_stamina: float = 0.0
var player_reeling: bool = false
var bite_active: bool = false
var active_fish: FishInstance = null

var fight_state: int = FightState.NONE
var rounds_remaining: int = 0
var recovery_time_left: float = 0.0
var fish_population: Array[FishSpawnEntry] = []
var pending_fish_entry: FishSpawnEntry = null
var active_bait_data: BaitData = null

func _ready() -> void:
	if caster == null:
		return

	caster.bait_landed.connect(_on_bait_landed)
	caster.bait_returned.connect(_on_bait_returned)
	bite_timer.timeout.connect(_on_bite_timer_timeout)
	bite_window_timer.timeout.connect(_on_bite_window_timeout)
	fish_behavior.movement_changed.connect(_on_fish_behavior_movement_changed)
	fish_behavior.depth_changed.connect(_on_fish_behavior_depth_changed)
	tension.tension_changed.connect(_on_tension_changed)
	tension.state_changed.connect(_on_tension_state_changed)
	tension.hook_off.connect(_on_hook_off)
	tension.line_broken.connect(_on_line_broken)
	fish_behavior.pressure_changed.connect(_on_fish_behavior_pressure_changed)
	
func _on_bait_landed(_point: Vector3) -> void:
	tension.start_free_reel()
	bite_timer.start(first_bite_delay)

func _on_bait_returned() -> void:
	bite_timer.stop()
	bite_window_timer.stop()
	bite_active = false
	pending_fish_entry = null
	active_bait_data = null
	tension.stop()
	
func _on_bite_timer_timeout() -> void:
	var attraction := fish_selector.get_attraction_ratio(
		fish_population,
		active_bait_data,
		caster.get_current_bait_depth(),
		caster.get_current_total_depth()
	)

	var bite_chance := attraction * max_bite_chance_per_check

	if randf() > bite_chance:

		bite_timer.start(retry_bite_delay)
		return
		
	pending_fish_entry = fish_selector.choose(
		fish_population,
		active_bait_data,
		caster.get_current_bait_depth(),
		caster.get_current_total_depth()
	)

	if pending_fish_entry == null:
		return

	if pending_fish_entry.fish == null:
		return

	if randf() < direct_hit_chance:

		_confirm_hit()
		return


	bite_active = true


	bite_opportunity_started.emit()
	bite_window_timer.start()

func try_hook() -> bool:
	if not bite_active:
		return false

	return _confirm_hit()

func _confirm_hit() -> bool:
	if pending_fish_entry == null:
		return false

	if pending_fish_entry.fish == null:
		return false

	bite_active = false
	bite_window_timer.stop()

	active_fish = FishInstance.new()
	active_fish.setup(pending_fish_entry.fish)

	fish_behavior.configure(active_fish)

	fish_stamina = active_fish.max_stamina
	player_reeling = false


	pending_fish_entry = null

	var total_rounds := maxi(
		active_fish.resistance_rounds,
		1
	)

	rounds_remaining = total_rounds

	_start_resistance_round()

	tension.start()
	tension.set_reel_gain_multiplier(1.0)

	bite_triggered.emit()
	fish_hooked.emit()

	return true
	
func _on_bite_window_timeout() -> void:
	bite_active = false
	pending_fish_entry = null
	bite_missed.emit()

	bite_timer.start(retry_bite_delay)

func catch_fish() -> void:
	bite_active = false
	bite_timer.stop()
	bite_window_timer.stop()

	tension.stop()

	fight_state = FightState.NONE
	rounds_remaining = 0
	recovery_time_left = 0.0
	player_reeling = false
	fish_behavior.stop()
	active_bait_data = null
	fish_caught.emit(active_fish)

func _process(delta: float) -> void:
	if fight_state == FightState.NONE:
		return

	if fight_state == FightState.SPENT:
		var spent_pressure := clampf(
			fish_behavior_pressure,
			0.0,
			1.0
		)

		var current_spent_resistance := (
			spent_resistance
			* lerpf(0.5, 1.0, spent_pressure)
		)

		tension.set_fish_resistance(
			current_spent_resistance
		)

		fish_pull_changed.emit(
			lerpf(
				spent_pull_strength * 0.5,
				spent_pull_strength,
				spent_pressure
			)
		)

		recovery_time_left -= delta

		if recovery_time_left <= 0.0:
			_restart_from_spent()

		return

	if fight_state == FightState.EXHAUSTED:
		var exhausted_pressure := clampf(
			fish_behavior_pressure,
			0.0,
			1.0
		)

		var current_exhausted_resistance := (
			exhausted_resistance
			* lerpf(
				0.5,
				1.0,
				exhausted_pressure
			)
		)

		tension.set_fish_resistance(
			current_exhausted_resistance
		)

		fish_pull_changed.emit(
			lerpf(
				exhausted_pull_strength * 0.5,
				exhausted_pull_strength,
				exhausted_pressure
			)
		)

		recovery_time_left -= delta

		if recovery_time_left <= 0.0:
			_start_resistance_round()

		return

	# From here we know the fish is RESISTING.

	var max_stamina := _get_max_stamina()

	if player_reeling:
		if current_tension_state == FishingTension.State.SAFE:
			var drain_speed := stamina_drain_speed

			var player_is_steering := absf(player_steering) > steering_deadzone
			var fish_is_running_sideways := absf(current_fish_lateral) > steering_deadzone

			if player_is_steering and fish_is_running_sideways:
				var steering_against_fish := (
					signf(player_steering) != signf(current_fish_lateral)
				)

				if steering_against_fish:
					drain_speed *= counter_steer_fatigue_multiplier

			fish_stamina = maxf(
				fish_stamina - drain_speed * delta,
				0.0
			)
	else:
		fish_stamina = minf(
			fish_stamina + stamina_recovery_speed * delta,
			max_stamina
		)

	fish_stamina_changed.emit(
		fish_stamina,
		max_stamina
	)

	var strength := _get_strength()

	var stamina_ratio := 0.0

	if max_stamina > 0.0:
		stamina_ratio = fish_stamina / max_stamina

	var resistance := clampf(
		stamina_ratio * strength,
		0.0,
		1.0
	)
	
	var tension_resistance := resistance * fish_behavior_pressure
	
	tension.set_fish_resistance(tension_resistance)
	fish_resistance_changed.emit(resistance)

	var pull_strength := lerpf(
		0.2,
		1.0,
		resistance
	)

	fish_pull_changed.emit(pull_strength)

	if fish_stamina <= 0.0:
		_finish_resistance_round() 
		
func set_player_reeling(active: bool) -> void:
	var was_reeling := player_reeling

	player_reeling = active
	tension.set_player_reeling(active)

	# Only react on the transition:
	# K held -> K released.
	if was_reeling and not active:
		_react_to_reel_release()

func _react_to_reel_release() -> void:
	if fight_state == FightState.NONE:
		return

	var reaction_intensity := release_movement_intensity

	if fight_state == FightState.EXHAUSTED:
		reaction_intensity = exhausted_behavior_intensity

	elif fight_state == FightState.SPENT:
		reaction_intensity = spent_release_movement_intensity

	fish_behavior.react_to_release(
		reaction_intensity
	)
	
func set_player_steering(value: float) -> void:
	player_steering = clampf(value, -1.0, 1.0)
	
func _get_max_stamina() -> float:
	if active_fish != null:
		return active_fish.max_stamina

	return max_fish_stamina


func _get_strength() -> float:
	if active_fish != null:
		return active_fish.strength

	return 1.0

func _on_fish_behavior_movement_changed(lateral: float) -> void:
	if fight_state == FightState.NONE:
		return

	current_fish_lateral = lateral
	fish_movement_changed.emit(lateral)

func _on_fish_behavior_depth_changed(value: float) -> void:
	if fight_state == FightState.NONE:
		return

	fish_depth_intent_changed.emit(value)

func _start_resistance_round() -> void:
	fight_state = FightState.RESISTING
	fish_resistance_started.emit()
	recovery_time_left = 0.0
	caster.set_reel_speed_multiplier(1.0)
	
	fish_stamina = _get_max_stamina()

	fish_stamina_changed.emit(
		fish_stamina,
		_get_max_stamina()
	)

	fish_behavior.start(
		resisting_behavior_intensity
	)



func _finish_resistance_round() -> void:
	rounds_remaining = maxi(
		rounds_remaining - 1,
		0
	)

	fish_stamina = 0.0
	fish_exhausted.emit()

	# Animation/controller still sees the fish as exhausted,
	# so we keep this at zero.
	fish_resistance_changed.emit(0.0)

	if rounds_remaining <= 0:
		_enter_spent()
		return

	fight_state = FightState.EXHAUSTED

	# Exhausted does NOT mean motionless.
	tension.set_fish_resistance(
		exhausted_resistance
	)

	fish_pull_changed.emit(
		exhausted_pull_strength
	)

	fish_behavior.start(
		exhausted_behavior_intensity
	)

	var recovery_min := 0.8
	var recovery_max := 1.5

	if active_fish != null:
		recovery_min = active_fish.recovery_time_min
		recovery_max = active_fish.recovery_time_max

	recovery_time_left = randf_range(
		recovery_min,
		recovery_max
	)


func _enter_spent() -> void:
	fight_state = FightState.SPENT
	fish_spent.emit()
	
	recovery_time_left = spent_recovery_time

	tension.set_fish_resistance(spent_resistance)
	tension.set_reel_gain_multiplier(spent_tension_multiplier)

	# The fish is exhausted, not dead.
	fish_behavior.start(spent_behavior_intensity)

	# Keep this at zero so the animation system still
	# considers the fish "spent" and stays relaxed.
	fish_resistance_changed.emit(0.0)

	fish_pull_changed.emit(spent_pull_strength)

	caster.set_reel_speed_multiplier(spent_reel_speed_multiplier)

func _restart_from_spent() -> void:
	fight_state = FightState.RESISTING
	recovery_time_left = 0.0

	rounds_remaining = 1

	fish_stamina = (
		_get_max_stamina()
		* spent_recovery_stamina_ratio
	)

	fish_stamina_changed.emit(
		fish_stamina,
		_get_max_stamina()
	)

	tension.set_reel_gain_multiplier(1.0)

	caster.set_reel_speed_multiplier(1.0)

	fish_behavior.start(spent_restart_intensity)
	
func set_fish_population(entries: Array[FishSpawnEntry]) -> void:
	fish_population = entries.duplicate()

func set_active_bait_data(bait_data: BaitData) -> void:
	active_bait_data = bait_data

func _on_tension_changed(value: float) -> void:
	tension_changed.emit(value)


func _on_tension_state_changed(state: int) -> void:
	current_tension_state = state
	tension_state_changed.emit(state)



func _on_hook_off() -> void:
	_fail_fight()
	hook_off.emit()


func _on_line_broken() -> void:
	_fail_fight()
	line_broken.emit()

func _fail_fight() -> void:
	tension.stop()

	fight_state = FightState.NONE
	rounds_remaining = 0
	recovery_time_left = 0.0
	player_reeling = false

	fish_behavior.stop()

	fish_resistance_changed.emit(0.0)
	fish_pull_changed.emit(0.0)
	fish_movement_changed.emit(0.0)
	fish_depth_intent_changed.emit(0.0)

	active_fish = null
	pending_fish_entry = null
	active_bait_data = null

func _on_fish_behavior_pressure_changed(value: float) -> void:
	fish_behavior_pressure = clampf(value, 0.0, 1.0)

func add_lure_tension(amount: float) -> void:
	tension.add_impulse(amount)

func set_player_tension_bias(value: float) -> void:
	tension.set_player_tension_bias(value)
