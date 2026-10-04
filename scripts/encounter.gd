extends Node

const DefaultTechniqueCatalog: FishingTechniqueCatalog = preload(
	"res://data/bof4/techniques/all_techniques.tres"
)
const FightLifecycleScript = preload(
	"res://scripts/fishing_fight_lifecycle.gd"
)
const FightResolver = preload(
	"res://scripts/fishing_fight_resolver.gd"
)
const FightPressurePolicy = preload(
	"res://scripts/fishing_fight_pressure_policy.gd"
)
const StructureCombatPolicy = preload(
	"res://scripts/fishing_structure_combat_policy.gd"
)
const LandingPolicy = preload(
	"res://scripts/fishing_landing_policy.gd"
)

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
signal technique_applied(level: int)
signal fish_thrash_started(intensity: float)
signal fish_intent_changed(snapshot: Dictionary)
signal line_pressure_band_changed(snapshot: Dictionary)
signal structure_threat_changed(snapshot: Dictionary)
signal line_abrasion_changed(value: float)
signal fish_final_surge_started(snapshot: Dictionary)
signal fish_final_surge_ended

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

@export_category("Structure Fighting")
@export_range(0.05, 2.0, 0.05) var structure_line_break_threshold: float = 1.0

@export_category("Landing / Final Surge")
## Trigger check happens before the normal 1 m-ish catch threshold so a fish
## has room to make a readable last burst instead of teleporting into landing.
@export_range(1.0, 6.0, 0.1) var final_surge_trigger_distance_meters: float = 2.4
@export var final_surge_enabled: bool = true

@export var first_bite_delay: float = 0.5
@export var retry_bite_delay: float = 0.5
@export_range(0.0, 1.0, 0.05)
var direct_hit_chance: float = 0.5

@export_range(0.0, 1.0, 0.05)
var max_bite_chance_per_check: float = 1.0

@export_category("Visible Fish Shadows")
## A visible interested fish near the lure is a genuine bite candidate, but
## never a guaranteed bite. Invisible fish continue to use the normal system.
@export_range(1.0, 2.0, 0.05)
var shadow_bite_chance_multiplier: float = 1.30

@export_range(0.0, 1.0, 0.05)
var shadow_species_selection_chance: float = 0.75

@export_range(0.1, 1.5, 0.05)
var shadow_candidate_radius: float = 0.55

## While a visible fish is WATCHING / APPROACHING / INSPECTING the lure, give
## that readable pre-bite interaction priority over an unrelated invisible bite.
@export_range(0.25, 4.0, 0.05)
var shadow_pre_bite_hold_radius: float = 1.9

@export_range(0.05, 1.0, 0.05)
var shadow_pre_bite_retry_delay: float = 0.25

@export_category("Fishing Techniques")
@export var technique_catalog: FishingTechniqueCatalog = (
	DefaultTechniqueCatalog
)

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
var current_fight_intent: Dictionary = {}
var current_line_pressure_band: StringName = &"none"
var current_safe_pressure_ratio: float = 0.5
var current_pressure_fatigue_multiplier: float = 1.0
var current_structure_contact: Dictionary = {}
var current_structure_snapshot: Dictionary = {}
var line_abrasion: float = 0.0
var final_surge_checked: bool = false
var final_surge_active: bool = false
var final_surge_snapshot: Dictionary = {}

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
var lifecycle = FightLifecycleScript.new()
var rounds_remaining: int = 0
var recovery_time_left: float = 0.0
var fish_population: Array[FishSpawnEntry] = []
var fish_zone: Node = null
var last_spatial_context: Dictionary = {}
var pending_fish_entry: FishSpawnEntry = null
var pending_shadow: Node = null
var active_fight_shadow: Node = null
var active_bait_data: BaitData = null
var debug_settings = null
var fishing_progress: FishingProgress = null
var session_modifier_service = null
var prepared_bait_service = null
var environment_service = null
var mastery_service = null
var active_rod_data: RodData = null
## Immutable per-hook snapshot of fish + rod + lure fight values. Encounter only
## consumes this resolved package; it does not reinterpret source resources.
var active_fight_context: Dictionary = {}
var base_bite_window_time: float = 0.8
var active_tech_level: int = 0
var technique_time_left: float = 0.0

func _ready() -> void:
	if caster == null:
		return

	caster.bait_landed.connect(_on_bait_landed)
	caster.bait_returned.connect(_on_bait_returned)
	bite_timer.timeout.connect(_on_bite_timer_timeout)
	bite_window_timer.timeout.connect(_on_bite_window_timeout)
	fish_behavior.movement_changed.connect(_on_fish_behavior_movement_changed)
	fish_behavior.depth_changed.connect(_on_fish_behavior_depth_changed)
	fish_behavior.intent_started.connect(_on_fish_behavior_intent_started)
	tension.tension_changed.connect(_on_tension_changed)
	tension.state_changed.connect(_on_tension_state_changed)
	tension.hook_off.connect(_on_hook_off)
	tension.line_broken.connect(_on_line_broken)
	fish_behavior.pressure_changed.connect(_on_fish_behavior_pressure_changed)
	fish_behavior.thrash_started.connect(_on_fish_behavior_thrash_started)

	base_bite_window_time = maxf(bite_window_timer.wait_time, 0.05)
	_apply_rod_tension_settings()

func _on_bait_landed(_point: Vector3) -> void:
	# One authoritative start point for a waterborne encounter. If a future bug
	# somehow leaves the prior cast open, close that lifecycle before resetting
	# runtime state. Preserve the newly selected bait/rod/debug configuration.
	if lifecycle.state != FightLifecycleScript.State.IDLE:
		lifecycle.cancel_cast()
		lifecycle.finish_cast()

	_reset_cast_runtime(false)
	if not lifecycle.begin_cast():
		push_error("Encounter: unable to begin a clean fishing-fight lifecycle.")
		return

	_reset_technique()
	tension.start_free_reel()
	bite_timer.start(first_bite_delay)


func _on_bait_returned() -> void:
	# Fishing owns the macro transition from FIGHT -> LANDING. When Caster is
	# deliberately holding the returned hooked bait, do not also begin landing
	# here. That used to make Encounter enter landing twice from the same signal.
	if (
		lifecycle.is_hooked()
		and caster != null
		and caster.has_method("is_holding_returned_bait_for_landing")
		and caster.is_holding_returned_bait_for_landing()
	):
		return

	if lifecycle.is_landing():
		return

	# Normal lure return / quick cancel ends the cast immediately.
	if lifecycle.state != FightLifecycleScript.State.IDLE:
		lifecycle.cancel_cast()

	_reset_cast_runtime(true)
	lifecycle.finish_cast()


func _on_bite_timer_timeout() -> void:
	# Stale one-shot timer callbacks are harmless. Only the explicit waiting
	# state may select a new fish or open a bite window.
	if not lifecycle.is_waiting_for_bite():
		return

	# Each bite check owns a fresh pending selection.
	pending_fish_entry = null
	pending_shadow = null

	var forced_fish: FishData = null

	if (
		debug_settings != null
		and debug_settings.has_method("get_forced_fish")
	):
		forced_fish = debug_settings.get_forced_fish()

	if forced_fish != null:
		pending_fish_entry = FishSpawnEntry.new()
		pending_fish_entry.fish = forced_fish
		pending_fish_entry.weight = 1.0
	else:
		var spatial_context: Dictionary = (
			_get_spatial_context()
		)
		last_spatial_context = spatial_context.duplicate(true)

		var environment_context: Dictionary = _get_environment_selection_context()

		var shadow_candidate := _get_visible_shadow_candidate()

		# If a visible fish is actively performing the pre-bite sequence but has
		# not finished inspecting yet, do not let a background invisible fish
		# steal the moment. The visible fish can still reject the lure and leave.
		if shadow_candidate == null and _has_active_visible_pre_bite():
			bite_timer.start(shadow_pre_bite_retry_delay)
			return

		var attraction := fish_selector.get_attraction_ratio(
			fish_population,
			active_bait_data,
			caster.get_current_bait_depth(),
			caster.get_current_total_depth(),
			caster.is_active_bait_reeling(),
			spatial_context,
			environment_context
		)

		var session_bite_multiplier: float = 1.0
		if (
			session_modifier_service != null
			and session_modifier_service.has_method("get_bite_attraction_multiplier")
		):
			session_bite_multiplier = maxf(
				float(session_modifier_service.get_bite_attraction_multiplier()),
				0.01
			)

		var prepared_bait_multiplier: float = 1.0
		if (
			prepared_bait_service != null
			and prepared_bait_service.has_method("get_bite_attraction_multiplier")
		):
			prepared_bait_multiplier = maxf(
				float(prepared_bait_service.get_bite_attraction_multiplier()),
				0.01
			)

		var environment_bite_multiplier: float = 1.0
		if (
			environment_service != null
			and environment_service.has_method("get_bite_activity_multiplier")
		):
			environment_bite_multiplier = maxf(
				float(environment_service.get_bite_activity_multiplier(
					caster.get_current_bait_depth(),
					caster.get_current_total_depth()
				)),
				0.01
			)

		var bite_chance := (
			attraction
			* max_bite_chance_per_check
			* _get_tech_attraction_multiplier()
			* session_bite_multiplier
			* prepared_bait_multiplier
			* environment_bite_multiplier
			* _get_spatial_bite_density_multiplier(
				spatial_context
			)
		)

		if shadow_candidate != null:
			bite_chance *= shadow_bite_chance_multiplier

		bite_chance = clampf(
			bite_chance,
			0.0,
			1.0
		)

		if randf() > bite_chance:
			bite_timer.start(retry_bite_delay)
			return

		if (
			shadow_candidate != null
			and randf() <= shadow_species_selection_chance
		):
			var shadow_fish: FishData = null

			if shadow_candidate.has_method("get_fish_data"):
				shadow_fish = shadow_candidate.get_fish_data() as FishData

			if shadow_fish != null:
				pending_fish_entry = FishSpawnEntry.new()
				pending_fish_entry.fish = shadow_fish
				pending_fish_entry.weight = 1.0
				pending_shadow = shadow_candidate

		if pending_fish_entry == null:
			pending_fish_entry = fish_selector.choose(
				fish_population,
				active_bait_data,
				caster.get_current_bait_depth(),
				caster.get_current_total_depth(),
				caster.is_active_bait_reeling(),
				spatial_context,
				environment_context
			)

	if (
		pending_fish_entry == null
		or pending_fish_entry.fish == null
	):
		pending_fish_entry = null
		pending_shadow = null
		bite_timer.start(retry_bite_delay)
		return

	if randf() < direct_hit_chance:
		_confirm_hit()
		return

	if not lifecycle.open_bite_window():
		pending_fish_entry = null
		pending_shadow = null
		return

	bite_active = true
	bite_opportunity_started.emit()
	bite_window_timer.start(_get_pending_bite_window_time())

func try_hook() -> bool:
	if not bite_active or not lifecycle.is_bite_window_open():
		return false

	return _confirm_hit()

func _confirm_hit() -> bool:
	if (
		not lifecycle.is_waiting_for_bite()
		and not lifecycle.is_bite_window_open()
	):
		return false

	if pending_fish_entry == null:
		return false

	if pending_fish_entry.fish == null:
		return false

	if not lifecycle.confirm_hook():
		return false

	bite_active = false
	bite_timer.stop()
	bite_window_timer.stop()

	active_fish = FishInstance.new()

	var king_override := -1
	var size_override_cm: float = -1.0

	if (
		debug_settings != null
		and debug_settings.has_method("get_king_override")
	):
		king_override = debug_settings.get_king_override()

	if (
		debug_settings != null
		and debug_settings.has_method("get_forced_specimen_size")
	):
		size_override_cm = float(
			debug_settings.get_forced_specimen_size(
				pending_fish_entry.fish
			)
		)

	var generation_context: Dictionary = {}
	if (
		is_instance_valid(fishing_progress)
		and fishing_progress.has_method("get_record_mercy_context")
	):
		generation_context = fishing_progress.get_record_mercy_context(
			pending_fish_entry.fish
		)

	if (
		session_modifier_service != null
		and session_modifier_service.has_method("get_specimen_generation_context")
	):
		var session_generation: Dictionary = (
			session_modifier_service.get_specimen_generation_context()
		)
		for key in session_generation:
			generation_context[key] = session_generation[key]

	if (
		prepared_bait_service != null
		and prepared_bait_service.has_method("get_specimen_generation_context")
	):
		var bait_generation: Dictionary = (
			prepared_bait_service.get_specimen_generation_context()
		)
		for key in bait_generation:
			generation_context[key] = bait_generation[key]

	if (
		environment_service != null
		and environment_service.has_method("get_specimen_generation_context")
	):
		var environment_generation: Dictionary = (
			environment_service.get_specimen_generation_context()
		)
		for key in environment_generation:
			generation_context[key] = environment_generation[key]

	active_fish.setup(
		pending_fish_entry.fish,
		king_override,
		size_override_cm,
		generation_context
	)

	_rebuild_active_fight_context()
	_apply_rod_tension_settings()
	_reset_technique()
	fish_behavior.configure(active_fish)

	fish_stamina = _get_max_stamina()
	player_reeling = false


	# Every hooked fish now gets a persistent fight shadow. If the bite came
	# from a visible pre-bite fish, that same shadow becomes the fight shadow.
	# Invisible bites spawn one at the lure so the fish remains readable through
	# the entire retrieve.
	_start_active_fight_shadow(pending_shadow)

	pending_shadow = null
	pending_fish_entry = null

	var total_rounds := maxi(
		int(active_fight_context.get(
			"resistance_rounds",
			active_fish.resistance_rounds
		)),
		1
	)

	rounds_remaining = total_rounds
	_reset_fight_readouts()

	_start_resistance_round()

	tension.start()
	tension.set_reel_gain_multiplier(1.0)
	_update_line_pressure_state()

	bite_triggered.emit()
	fish_hooked.emit()

	return true

func _on_bite_window_timeout() -> void:
	if not lifecycle.is_bite_window_open():
		return

	bite_active = false

	var retry_delay: float = (
		retry_bite_delay * _get_pending_bite_retry_multiplier()
	)

	if is_instance_valid(pending_shadow):
		if pending_shadow.has_method("abandon_bait_and_dive"):
			pending_shadow.abandon_bait_and_dive()

	pending_shadow = null
	pending_fish_entry = null

	if not lifecycle.miss_bite():
		return

	bite_missed.emit()
	bite_timer.start(retry_delay)

func _get_visible_shadow_candidate() -> Node:
	var bait := get_tree().get_first_node_in_group("bait") as Node3D

	if not is_instance_valid(bait):
		return null

	var nearest: Node = null
	var nearest_distance := shadow_candidate_radius

	for presence in get_tree().get_nodes_in_group("fish_shadow_presence"):
		if not is_instance_valid(presence):
			continue
		if not presence.has_method("get_interested_shadow_near"):
			continue

		var shadow = presence.get_interested_shadow_near(
			bait.global_position,
			shadow_candidate_radius
		)

		if shadow == null or not is_instance_valid(shadow):
			continue

		var offset: Vector3 = shadow.global_position - bait.global_position
		offset.y = 0.0
		var distance := offset.length()

		if distance <= nearest_distance:
			nearest = shadow
			nearest_distance = distance

	return nearest


func _has_active_visible_pre_bite() -> bool:
	var bait := get_tree().get_first_node_in_group("bait") as Node3D

	if not is_instance_valid(bait):
		return false

	for presence in get_tree().get_nodes_in_group("fish_shadow_presence"):
		if not is_instance_valid(presence):
			continue
		if not presence.has_method("has_active_pre_bite_near"):
			continue
		if presence.has_active_pre_bite_near(
			bait.global_position,
			shadow_pre_bite_hold_radius
		):
			return true

	return false


func _start_active_fight_shadow(existing_shadow: Node = null) -> void:
	var bait := get_tree().get_first_node_in_group("bait") as Node3D
	if not is_instance_valid(bait) or active_fish == null or active_fish.species == null:
		return

	var preferred_presence: Node = null
	var typed_existing := existing_shadow as FishShadowActor

	if is_instance_valid(typed_existing):
		preferred_presence = typed_existing.get_parent()

	if (
		preferred_presence == null
		or not preferred_presence.has_method("start_fight_shadow")
	):
		for presence in get_tree().get_nodes_in_group("fish_shadow_presence"):
			if is_instance_valid(presence) and presence.has_method("start_fight_shadow"):
				preferred_presence = presence
				break

	if preferred_presence == null:
		return

	var size_multiplier := 1.0
	if active_fish.species.average_size > 0.001:
		size_multiplier = clampf(
			active_fish.size / active_fish.species.average_size,
			0.70,
			1.45
		)

	active_fight_shadow = preferred_presence.start_fight_shadow(
		active_fish.species,
		bait,
		typed_existing,
		size_multiplier
	)


func _set_active_fight_shadow_visual_state(state_name: StringName) -> void:
	if not is_instance_valid(active_fight_shadow):
		return

	if active_fight_shadow.has_method("set_fight_visual_state"):
		active_fight_shadow.set_fight_visual_state(state_name)


func _end_active_fight_shadow(dive_away: bool) -> void:
	if not is_instance_valid(active_fight_shadow):
		active_fight_shadow = null
		return

	var presence := active_fight_shadow.get_parent()
	if is_instance_valid(presence) and presence.has_method("end_fight_shadow"):
		presence.end_fight_shadow(dive_away)
	elif active_fight_shadow.has_method("release_from_hooked_bait"):
		active_fight_shadow.release_from_hooked_bait(dive_away)

	active_fight_shadow = null


func begin_catch_landing() -> bool:
	# Idempotent because Caster/Fishing can observe the same return event in the
	# same frame. The lifecycle is the authority; presentation may call twice
	# without changing gameplay twice.
	if not lifecycle.begin_landing():
		return false

	bite_active = false
	pending_fish_entry = null
	pending_shadow = null
	bite_timer.stop()
	bite_window_timer.stop()
	tension.stop()

	fight_state = FightState.NONE
	rounds_remaining = 0
	recovery_time_left = 0.0
	player_reeling = false
	player_steering = 0.0
	current_fish_lateral = 0.0
	fish_behavior_pressure = 0.0
	fish_behavior.stop()
	_reset_fight_readouts()

	_set_active_fight_shadow_visual_state(&"spent")
	if (
		is_instance_valid(active_fight_shadow)
		and active_fight_shadow.has_method("begin_catch_landing")
	):
		active_fight_shadow.begin_catch_landing()

	return true


func catch_fish() -> bool:
	if not lifecycle.is_landing() or active_fish == null:
		return false

	if not lifecycle.resolve_catch():
		return false

	var caught: FishInstance = active_fish

	_end_active_fight_shadow(false)
	bite_active = false
	pending_fish_entry = null
	pending_shadow = null
	bite_timer.stop()
	bite_window_timer.stop()
	tension.stop()

	fight_state = FightState.NONE
	rounds_remaining = 0
	recovery_time_left = 0.0
	player_reeling = false
	player_steering = 0.0
	current_fish_lateral = 0.0
	fish_behavior_pressure = 0.0
	fish_behavior.stop()
	_reset_fight_readouts()
	active_fish = null
	active_bait_data = null
	active_fight_context.clear()

	# Emit the immutable result exactly once, after Encounter has become terminal.
	# Re-entrant listeners can no longer call catch_fish() a second time.
	fish_caught.emit(caught)
	lifecycle.finish_cast()
	return true


func _process(delta: float) -> void:
	_update_technique_timer(delta)

	if not lifecycle.is_hooked() or fight_state == FightState.NONE:
		return

	_update_line_pressure_state()
	_update_structure_combat(delta)
	_update_final_surge_state()

	if not lifecycle.is_hooked():
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
			clampf(
				lerpf(
					spent_pull_strength * 0.5,
					spent_pull_strength,
					spent_pressure
				) * _get_pull_multiplier(),
				0.0,
				1.0
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
			clampf(
				lerpf(
					exhausted_pull_strength * 0.5,
					exhausted_pull_strength,
					exhausted_pressure
				) * _get_pull_multiplier(),
				0.0,
				1.0
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
			drain_speed *= maxf(
				float(active_fight_context.get(
					"stamina_drain_multiplier",
					1.0
				)),
				0.01
			)
			drain_speed *= maxf(
				current_pressure_fatigue_multiplier,
				0.01
			)

			var player_is_steering := absf(player_steering) > steering_deadzone
			var fish_is_running_sideways := absf(current_fish_lateral) > steering_deadzone

			if player_is_steering and fish_is_running_sideways:
				var steering_against_fish := (
					signf(player_steering) != signf(current_fish_lateral)
				)

				if steering_against_fish:
					var rod_handling := maxf(
						float(active_fight_context.get(
							"counter_steer_multiplier",
							1.0
						)),
						0.01
					)

					drain_speed *= (
						counter_steer_fatigue_multiplier
						* rod_handling
					)

			fish_stamina = maxf(
				fish_stamina - drain_speed * delta,
				0.0
			)
	else:
		fish_stamina = minf(
			fish_stamina
			+ stamina_recovery_speed
			* _get_stamina_recovery_multiplier()
			* delta,
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

	var pull_strength: float = clampf(
		lerpf(0.2, 1.0, resistance)
		* _get_pull_multiplier(),
		0.0,
		1.0
	)

	fish_pull_changed.emit(pull_strength)

	if fish_stamina <= 0.0:
		_finish_resistance_round()

func _update_final_surge_state() -> void:
	if (
		not final_surge_enabled
		or final_surge_checked
		or final_surge_active
		or fight_state != FightState.SPENT
		or active_fish == null
		or caster == null
		or not caster.has_method("get_active_bait_distance_meters")
	):
		return

	var distance_meters: float = caster.get_active_bait_distance_meters()
	if not LandingPolicy.is_in_final_surge_window(
		distance_meters,
		final_surge_trigger_distance_meters
	):
		return

	# One roll per hooked fish. A fish that stays calm here remains calm; moving
	# in/out of the landing window cannot be used to reroll the encounter.
	final_surge_checked = true
	var difficulty_tier := clampi(
		int(active_fight_context.get("difficulty_tier", 1)),
		1,
		5
	)
	var size_ratio := maxf(
		float(active_fight_context.get("size_ratio_to_average", 1.0)),
		0.0
	)
	var is_king := bool(active_fight_context.get("is_king", false))
	var chance := LandingPolicy.get_final_surge_chance(
		difficulty_tier,
		size_ratio,
		is_king
	)

	if randf() > chance:
		return

	_start_final_surge(
		distance_meters,
		chance,
		difficulty_tier,
		is_king
	)


func _start_final_surge(
	distance_meters: float,
	chance: float,
	difficulty_tier: int,
	is_king: bool
) -> void:
	if not lifecycle.is_hooked() or active_fish == null:
		return

	final_surge_active = true
	_set_landing_completion_blocked(true)

	var stamina_ratio := LandingPolicy.get_final_surge_stamina_ratio(
		difficulty_tier,
		is_king
	)
	var intensity := LandingPolicy.get_final_surge_intensity(
		difficulty_tier,
		is_king
	)

	final_surge_snapshot = LandingPolicy.build_snapshot(
		distance_meters,
		chance,
		stamina_ratio,
		intensity
	)

	fight_state = FightState.RESISTING
	rounds_remaining = 1
	recovery_time_left = 0.0
	_set_active_fight_shadow_visual_state(&"resisting")

	fish_stamina = _get_max_stamina() * stamina_ratio
	fish_stamina_changed.emit(fish_stamina, _get_max_stamina())
	tension.set_reel_gain_multiplier(1.0)
	caster.set_reel_speed_multiplier(1.0)
	fish_behavior.start(intensity)

	# Presentation can use this as a distinct last-second tell; the existing
	# thrash signal also gives the current splash system immediate feedback.
	fish_final_surge_started.emit(final_surge_snapshot.duplicate(true))
	fish_thrash_started.emit(clampf(intensity, 0.0, 1.0))


func _finish_final_surge_if_active() -> void:
	if not final_surge_active:
		return

	final_surge_active = false
	_set_landing_completion_blocked(false)
	fish_final_surge_ended.emit()


func _set_landing_completion_blocked(active: bool) -> void:
	if caster != null and caster.has_method("set_landing_completion_blocked"):
		caster.set_landing_completion_blocked(active)


func get_landing_combat_snapshot() -> Dictionary:
	if final_surge_snapshot.is_empty():
		return {
			"active": false,
			"checked": final_surge_checked,
		}
	var snapshot := final_surge_snapshot.duplicate(true)
	snapshot["active"] = final_surge_active
	snapshot["checked"] = final_surge_checked
	return snapshot


func _get_pending_bite_window_time() -> float:
	var multiplier: float = 1.0
	if pending_fish_entry != null and pending_fish_entry.fish != null:
		multiplier = pending_fish_entry.fish.get_bite_window_multiplier()
	return maxf(base_bite_window_time * multiplier, 0.05)


func _get_pending_bite_retry_multiplier() -> float:
	if pending_fish_entry == null or pending_fish_entry.fish == null:
		return 1.0
	return pending_fish_entry.fish.get_bite_retry_multiplier()


func _get_pull_multiplier() -> float:
	return maxf(
		float(active_fight_context.get("pull_multiplier", 1.0)),
		0.01
	)


func _get_stamina_recovery_multiplier() -> float:
	return maxf(
		float(active_fight_context.get(
			"stamina_recovery_multiplier",
			1.0
		)),
		0.01
	)


func set_player_reeling(active: bool) -> void:
	# Free reeling is valid while waiting for a bite; fight reeling is valid only
	# while a fish is actually hooked. Resolved/landing states reject stale input.
	var accepts_reel_input := (
		lifecycle.is_waiting_for_bite()
		or lifecycle.is_bite_window_open()
		or lifecycle.is_hooked()
	)

	if not accepts_reel_input:
		active = false

	var was_reeling := player_reeling
	player_reeling = active
	tension.set_player_reeling(active)

	# Only a hooked fish owns release reactions. Releasing free-reel input must
	# never wake FishBehavior or mutate a future fight.
	if (
		lifecycle.is_hooked()
		and was_reeling
		and not active
	):
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
	if not lifecycle.is_hooked():
		player_steering = 0.0
		return

	player_steering = clampf(value, -1.0, 1.0)

func _get_max_stamina() -> float:
	if not active_fight_context.is_empty():
		return maxf(
			float(active_fight_context.get("max_stamina", max_fish_stamina)),
			0.001
		)

	if active_fish != null:
		return active_fish.max_stamina

	return max_fish_stamina


func _get_strength() -> float:
	if not active_fight_context.is_empty():
		return maxf(
			float(active_fight_context.get("strength", 1.0)),
			0.01
		)

	if active_fish != null:
		return active_fish.strength

	return 1.0

func _on_fish_behavior_movement_changed(lateral: float) -> void:
	if not lifecycle.is_hooked() or fight_state == FightState.NONE:
		return

	var resolved_lateral := lateral
	if not current_structure_contact.is_empty() and caster != null:
		var bait_position: Vector3 = caster.get_active_bait_world_position()
		var structure_position: Vector3 = current_structure_contact.get(
			"world_position",
			bait_position
		)
		var escape_sign := StructureCombatPolicy.get_escape_steering_sign(
			bait_position,
			structure_position
		)
		resolved_lateral = StructureCombatPolicy.get_structure_seek_lateral(
			lateral,
			escape_sign,
			float(current_structure_contact.get("seek_strength", 0.0))
		)

	current_fish_lateral = resolved_lateral
	fish_movement_changed.emit(resolved_lateral)

func _on_fish_behavior_depth_changed(value: float) -> void:
	if not lifecycle.is_hooked() or fight_state == FightState.NONE:
		return

	fish_depth_intent_changed.emit(value)

func _start_resistance_round() -> void:
	fight_state = FightState.RESISTING
	_set_active_fight_shadow_visual_state(&"resisting")
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
	_set_active_fight_shadow_visual_state(&"exhausted")

	# Exhausted does NOT mean motionless.
	tension.set_fish_resistance(
		exhausted_resistance
	)

	fish_pull_changed.emit(
		clampf(
			exhausted_pull_strength * _get_pull_multiplier(),
			0.0,
			1.0
		)
	)

	fish_behavior.start(
		exhausted_behavior_intensity
	)

	var recovery_min := maxf(
		float(active_fight_context.get("recovery_time_min", 0.8)),
		0.0
	)
	var recovery_max := maxf(
		float(active_fight_context.get("recovery_time_max", 1.5)),
		recovery_min
	)

	recovery_time_left = randf_range(
		recovery_min,
		recovery_max
	)


func _enter_spent() -> void:
	fight_state = FightState.SPENT
	_set_active_fight_shadow_visual_state(&"spent")
	fish_spent.emit()
	_finish_final_surge_if_active()

	recovery_time_left = spent_recovery_time

	tension.set_fish_resistance(spent_resistance)
	tension.set_reel_gain_multiplier(spent_tension_multiplier)

	# The fish is exhausted, not dead.
	fish_behavior.start(spent_behavior_intensity)

	# Keep this at zero so the animation system still
	# considers the fish "spent" and stays relaxed.
	fish_resistance_changed.emit(0.0)

	fish_pull_changed.emit(
		clampf(
			spent_pull_strength * _get_pull_multiplier(),
			0.0,
			1.0
		)
	)

	caster.set_reel_speed_multiplier(spent_reel_speed_multiplier)

func _restart_from_spent() -> void:
	fight_state = FightState.RESISTING
	_set_active_fight_shadow_visual_state(&"resisting")
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

func get_fish_debug_snapshot() -> Dictionary:
	var snapshot := {
		"fight_state": _get_fight_state_label(),
		"stamina": fish_stamina,
		"max_stamina": _get_max_stamina(),
		"rounds_remaining": rounds_remaining,
		"pressure": fish_behavior_pressure,
		"lateral": current_fish_lateral,
		"bite_active": bite_active,
		"pending_fish": "NONE",
		"fight_intent": current_fight_intent.duplicate(true),
		"line_pressure": get_line_pressure_snapshot(),
		"line_abrasion": line_abrasion,
		"structure": current_structure_snapshot.duplicate(true),
		"landing": get_landing_combat_snapshot(),
	}

	if pending_fish_entry != null and pending_fish_entry.fish != null:
		snapshot["pending_fish"] = pending_fish_entry.fish.fish_name

	if active_fish != null:
		snapshot.merge(active_fish.get_debug_snapshot(), true)

	snapshot["fight_context"] = active_fight_context.duplicate(true)

	if fish_behavior != null and fish_behavior.has_method("get_debug_snapshot"):
		snapshot["behavior"] = fish_behavior.get_debug_snapshot()

	snapshot["lifecycle"] = lifecycle.get_debug_snapshot()
	snapshot["technique"] = get_technique_debug_snapshot()
	snapshot["tension"] = get_tension_debug_snapshot()
	if (
		session_modifier_service != null
		and session_modifier_service.has_method("get_composite_snapshot")
	):
		snapshot["session_modifiers"] = (
			session_modifier_service.get_composite_snapshot()
		)

	if (
		prepared_bait_service != null
		and prepared_bait_service.has_method("get_runtime_snapshot")
	):
		snapshot["prepared_bait"] = prepared_bait_service.get_runtime_snapshot()

	if (
		environment_service != null
		and environment_service.has_method("get_debug_snapshot")
	):
		snapshot["environment"] = environment_service.get_debug_snapshot(
			caster.get_current_bait_depth(),
			caster.get_current_total_depth()
		)

	return snapshot


func _get_fight_state_label() -> String:
	match fight_state:
		FightState.RESISTING:
			return "RESISTING"
		FightState.EXHAUSTED:
			return "EXHAUSTED"
		FightState.SPENT:
			return "SPENT"
		_:
			return "NONE"


func set_fish_population(entries: Array[FishSpawnEntry]) -> void:
	fish_population = entries.duplicate()


func set_fish_zone(new_zone: Node) -> void:
	fish_zone = new_zone
	last_spatial_context.clear()


func set_active_bait_data(bait_data: BaitData) -> void:
	active_bait_data = bait_data
	if active_fish != null:
		_rebuild_active_fight_context()
	_apply_rod_tension_settings()

func _get_environment_selection_context() -> Dictionary:
	if (
		environment_service == null
		or not environment_service.has_method("get_selection_context")
	):
		return {}
	return environment_service.get_selection_context(fish_population)


func _get_spatial_context() -> Dictionary:
	if (
		fish_zone == null
		or caster == null
		or not fish_zone.has_method(
			"get_concentration_snapshot"
		)
		or not caster.has_method(
			"get_active_bait_world_position"
		)
	):
		return {}

	return fish_zone.get_concentration_snapshot(
		caster.get_active_bait_world_position(),
		caster.get_current_bait_depth(),
		caster.get_current_total_depth()
	)


func _get_spatial_bite_density_multiplier(
	spatial_context: Dictionary
) -> float:
	if spatial_context.is_empty():
		return 1.0

	return clampf(
		float(
			spatial_context.get(
				"bite_density_multiplier",
				1.0
			)
		),
		0.25,
		2.0
	)


func get_spatial_debug_snapshot() -> Dictionary:
	return last_spatial_context.duplicate(true)


func apply_technique(level: int) -> void:
	if technique_catalog == null:
		return

	var definition: FishingTechniqueDefinition = (
		technique_catalog.get_technique(level)
	)

	if definition == null:
		return

	active_tech_level = definition.level
	technique_time_left = maxf(
		definition.boost_duration,
		0.0
	)

	technique_applied.emit(
		active_tech_level
	)


func get_effective_tech_level() -> int:
	if (
		debug_settings != null
		and debug_settings.has_method(
			"get_forced_tech_level"
		)
	):
		var forced_level: int = (
			debug_settings.get_forced_tech_level()
		)

		if (
			forced_level > 0
			and technique_catalog != null
			and technique_catalog.get_technique(
				forced_level
			) != null
		):
			return forced_level

	return active_tech_level


func get_effective_technique() -> FishingTechniqueDefinition:
	if technique_catalog == null:
		return null

	return technique_catalog.get_technique(
		get_effective_tech_level()
	)


func _get_tech_attraction_multiplier() -> float:
	var definition: FishingTechniqueDefinition = (
		get_effective_technique()
	)

	if definition == null:
		return 1.0

	return maxf(
		definition.attraction_multiplier,
		1.0
	)


func get_technique_debug_snapshot() -> Dictionary:
	var effective_level: int = (
		get_effective_tech_level()
	)
	var definition: FishingTechniqueDefinition = (
		get_effective_technique()
	)

	return {
		"active_level": active_tech_level,
		"effective_level": effective_level,
		"time_left": maxf(
			technique_time_left,
			0.0
		),
		"forced": (
			effective_level > 0
			and effective_level != active_tech_level
		),
		"attraction_multiplier": (
			definition.attraction_multiplier
			if definition != null
			else 1.0
		),
		"broad_attraction": (
			definition.broad_attraction
			if definition != null
			else false
		),
		"rhythm": (
			definition.get_rhythm_label()
			if definition != null
			else ""
		),
		"catalog": (
			technique_catalog.get_debug_summary()
			if technique_catalog != null
			else "NONE"
		),
	}


func _update_technique_timer(delta: float) -> void:
	if active_tech_level <= 0:
		return

	technique_time_left -= delta

	if technique_time_left <= 0.0:
		_reset_technique()


func _reset_technique() -> void:
	active_tech_level = 0
	technique_time_left = 0.0


func set_debug_settings(settings) -> void:
	debug_settings = settings


func set_fishing_progress(progress: FishingProgress) -> void:
	fishing_progress = progress


func set_session_modifier_service(service) -> void:
	var callback := Callable(self, "_on_session_modifiers_changed")
	if (
		session_modifier_service != null
		and session_modifier_service.has_signal("modifiers_changed")
		and session_modifier_service.is_connected("modifiers_changed", callback)
	):
		session_modifier_service.disconnect("modifiers_changed", callback)

	session_modifier_service = service

	if (
		session_modifier_service != null
		and session_modifier_service.has_signal("modifiers_changed")
		and not session_modifier_service.is_connected("modifiers_changed", callback)
	):
		session_modifier_service.connect("modifiers_changed", callback)

	_on_session_modifiers_changed({})


func _on_session_modifiers_changed(_snapshot: Dictionary) -> void:
	if active_fish != null:
		_rebuild_active_fight_context()
	_apply_rod_tension_settings()


func set_prepared_bait_service(service) -> void:
	prepared_bait_service = service


func set_environment_service(service) -> void:
	var callback: Callable = Callable(self, "_on_environment_changed")
	if (
		environment_service != null
		and environment_service.has_signal("environment_changed")
		and environment_service.is_connected("environment_changed", callback)
	):
		environment_service.disconnect("environment_changed", callback)

	environment_service = service

	if (
		environment_service != null
		and environment_service.has_signal("environment_changed")
		and not environment_service.is_connected("environment_changed", callback)
	):
		environment_service.connect("environment_changed", callback)

	_on_environment_changed({})


func set_mastery_service(service) -> void:
	mastery_service = service


func _has_mastery_capability(capability: StringName) -> bool:
	return (
		mastery_service != null
		and mastery_service.has_method("has_capability")
		and bool(mastery_service.has_capability(capability))
	)


func _on_environment_changed(_snapshot: Dictionary) -> void:
	if active_fish != null:
		_rebuild_active_fight_context()
	_apply_rod_tension_settings()


func set_rod_data(rod_data: RodData) -> void:
	active_rod_data = rod_data
	if active_fish != null:
		_rebuild_active_fight_context()
	_apply_rod_tension_settings()


func _rebuild_active_fight_context() -> void:
	if active_fish == null:
		active_fight_context.clear()
		return

	var session_fight_modifiers: Dictionary = {}
	if (
		session_modifier_service != null
		and session_modifier_service.has_method("get_fight_modifiers")
	):
		session_fight_modifiers = session_modifier_service.get_fight_modifiers()

	var environment_fight_modifiers: Dictionary = {}
	if (
		environment_service != null
		and environment_service.has_method("get_fight_modifiers")
	):
		environment_fight_modifiers = environment_service.get_fight_modifiers()

	active_fight_context = FightResolver.resolve_context(
		active_fish,
		active_rod_data,
		active_bait_data,
		session_fight_modifiers,
		environment_fight_modifiers
	)

	if not FightResolver.is_valid_context(active_fight_context):
		push_warning(
			"Encounter: invalid resolved fight context for %s."
			% (
				active_fish.species.fish_name
				if active_fish.species != null
				else "UNKNOWN"
			)
		)


func _apply_rod_tension_settings() -> void:
	# Kept under the historical function name because callers already use it,
	# but this now applies the full resolved tackle safety package.
	if tension == null:
		return

	var tolerance_multiplier: float = 1.0
	var hook_delay_multiplier: float = 1.0

	if not active_fight_context.is_empty():
		tolerance_multiplier = maxf(
			float(active_fight_context.get(
				"line_tolerance_multiplier",
				1.0
			)),
			0.01
		)
		hook_delay_multiplier = maxf(
			float(active_fight_context.get(
				"hook_off_delay_multiplier",
				1.0
			)),
			0.01
		)
	elif active_rod_data != null:
		tolerance_multiplier = maxf(
			active_rod_data.line_tolerance_multiplier,
			0.01
		)
		hook_delay_multiplier = maxf(
			active_rod_data.hook_security_multiplier,
			0.01
		)

	tension.set_line_tolerance_multiplier(tolerance_multiplier)
	tension.set_hook_off_delay_multiplier(hook_delay_multiplier)


func get_tension_debug_snapshot() -> Dictionary:
	if tension == null:
		return {}

	var snapshot: Dictionary = tension.get_debug_snapshot()
	snapshot["rod_name"] = (
		active_rod_data.rod_name
		if active_rod_data != null
		else "NONE"
	)

	if active_fish != null:
		snapshot["fish_strength"] = _get_strength()
		snapshot["fish_size"] = active_fish.size
		snapshot["fish_is_king"] = active_fish.is_king
		snapshot["fish_archetype"] = str(active_fight_context.get("archetype", "NONE"))
		snapshot["fish_dominant_action"] = str(active_fight_context.get("dominant_action", "NONE"))
	else:
		snapshot["fish_strength"] = 0.0
		snapshot["fish_size"] = 0.0
		snapshot["fish_is_king"] = false

	return snapshot


func _on_tension_changed(value: float) -> void:
	tension_changed.emit(value)


func _on_tension_state_changed(state: int) -> void:
	current_tension_state = state
	tension_state_changed.emit(state)



func _on_hook_off() -> void:
	if not _fail_fight(FightLifecycleScript.Resolution.HOOK_OFF):
		return

	hook_off.emit()


func _on_line_broken() -> void:
	if not _fail_fight(FightLifecycleScript.Resolution.LINE_BREAK):
		return

	line_broken.emit()


func _fail_fight(reason: int) -> bool:
	var accepted := false

	match reason:
		FightLifecycleScript.Resolution.HOOK_OFF:
			accepted = lifecycle.resolve_hook_off()
		FightLifecycleScript.Resolution.LINE_BREAK:
			accepted = lifecycle.resolve_line_break()

	if not accepted:
		return false

	_end_active_fight_shadow(true)
	tension.stop()

	fight_state = FightState.NONE
	rounds_remaining = 0
	recovery_time_left = 0.0
	player_reeling = false
	player_steering = 0.0
	current_fish_lateral = 0.0
	fish_behavior_pressure = 0.0

	fish_behavior.stop()
	_reset_fight_readouts()

	fish_resistance_changed.emit(0.0)
	fish_pull_changed.emit(0.0)
	fish_movement_changed.emit(0.0)
	fish_depth_intent_changed.emit(0.0)

	active_fish = null
	pending_fish_entry = null
	pending_shadow = null
	active_bait_data = null
	active_fight_context.clear()
	return true


func _on_fish_behavior_intent_started(snapshot: Dictionary) -> void:
	if not lifecycle.is_hooked() or fight_state == FightState.NONE:
		return

	current_fight_intent = snapshot.duplicate(true)
	fish_intent_changed.emit(current_fight_intent.duplicate(true))


func _update_line_pressure_state() -> void:
	if tension == null:
		return

	var value := tension.get_tension_value()
	var safe_min := tension.get_safe_min_value()
	var safe_max := tension.get_safe_max_value()
	var next_band: StringName = FightPressurePolicy.get_band(
		value,
		safe_min,
		safe_max
	)

	current_safe_pressure_ratio = FightPressurePolicy.get_safe_ratio(
		value,
		safe_min,
		safe_max
	)
	current_pressure_fatigue_multiplier = (
		FightPressurePolicy.get_fatigue_multiplier(
			value,
			safe_min,
			safe_max
		)
	)

	if next_band == current_line_pressure_band:
		return

	current_line_pressure_band = next_band
	line_pressure_band_changed.emit(get_line_pressure_snapshot())


func get_line_pressure_snapshot() -> Dictionary:
	if tension == null:
		return {
			"band": &"none",
			"safe_ratio": 0.5,
			"fatigue_multiplier": 1.0,
		}

	return {
		"band": current_line_pressure_band,
		"safe_ratio": current_safe_pressure_ratio,
		"fatigue_multiplier": current_pressure_fatigue_multiplier,
		"tension": tension.get_tension_value(),
		"safe_min": tension.get_safe_min_value(),
		"safe_max": tension.get_safe_max_value(),
	}


func _get_structure_contacts() -> Array[Dictionary]:
	if caster == null or not caster.has_method("get_active_fight_structure_contacts"):
		return []
	return caster.get_active_fight_structure_contacts()


func _select_structure_contact(contacts: Array[Dictionary]) -> Dictionary:
	var best: Dictionary = {}
	var best_score := -1.0
	for contact in contacts:
		var score := (
			maxf(float(contact.get("abrasion_rate", 0.0)), 0.0)
			* maxf(float(contact.get("pressure_multiplier", 1.0)), 0.0)
		)
		if score > best_score:
			best_score = score
			best = contact.duplicate(true)
	return best


func _update_structure_combat(delta: float) -> void:
	if delta <= 0.0 or caster == null:
		return

	var contacts := _get_structure_contacts()
	if contacts.is_empty():
		if not current_structure_contact.is_empty():
			current_structure_contact.clear()
			current_structure_snapshot.clear()
			structure_threat_changed.emit({})
		return

	current_structure_contact = _select_structure_contact(contacts)
	if current_structure_contact.is_empty():
		return

	var bait_position: Vector3 = caster.get_active_bait_world_position()
	var structure_position: Vector3 = current_structure_contact.get(
		"world_position",
		bait_position
	)
	var escape_sign := StructureCombatPolicy.get_escape_steering_sign(
		bait_position,
		structure_position
	)
	var steering_away := StructureCombatPolicy.is_steering_away(
		player_steering,
		escape_sign,
		steering_deadzone
	)
	var fish_driving_in := StructureCombatPolicy.is_fish_driving_into_structure(
		current_fish_lateral,
		escape_sign,
		steering_deadzone
	)
	var knows_structure_fighting := _has_mastery_capability(
		&"structure_fighting"
	)
	var abrasion_rate := maxf(
		float(current_structure_contact.get("abrasion_rate", 0.0)),
		0.0
	)
	abrasion_rate *= maxf(
		float(current_structure_contact.get("pressure_multiplier", 1.0)),
		0.0
	)
	abrasion_rate *= StructureCombatPolicy.get_abrasion_rate_multiplier(
		current_safe_pressure_ratio,
		fish_behavior_pressure,
		fish_driving_in,
		steering_away,
		knows_structure_fighting
	)

	var threshold := maxf(structure_line_break_threshold, 0.05)
	var previous := line_abrasion
	line_abrasion = clampf(
		line_abrasion + abrasion_rate * delta,
		0.0,
		threshold
	)
	if not is_equal_approx(previous, line_abrasion):
		line_abrasion_changed.emit(line_abrasion / threshold)

	current_structure_snapshot = StructureCombatPolicy.build_structure_snapshot(
		current_structure_contact,
		line_abrasion / threshold,
		escape_sign,
		steering_away,
		fish_driving_in,
		knows_structure_fighting
	)
	current_structure_snapshot["read_structure_known"] = _has_mastery_capability(
		&"read_structure"
	)
	structure_threat_changed.emit(current_structure_snapshot.duplicate(true))

	if line_abrasion >= threshold and tension != null:
		if tension.has_method("force_line_break"):
			tension.force_line_break()


func get_structure_combat_snapshot() -> Dictionary:
	if current_structure_snapshot.is_empty():
		return {
			"active": false,
			"abrasion": line_abrasion / maxf(structure_line_break_threshold, 0.05),
		}
	var snapshot := current_structure_snapshot.duplicate(true)
	snapshot["active"] = true
	return snapshot


func _reset_fight_readouts() -> void:
	current_fight_intent.clear()
	current_line_pressure_band = &"none"
	current_safe_pressure_ratio = 0.5
	current_pressure_fatigue_multiplier = 1.0
	current_structure_contact.clear()
	current_structure_snapshot.clear()
	line_abrasion = 0.0
	final_surge_checked = false
	final_surge_active = false
	final_surge_snapshot.clear()
	_set_landing_completion_blocked(false)
	line_abrasion_changed.emit(0.0)
	structure_threat_changed.emit({})


func _on_fish_behavior_thrash_started(intensity: float) -> void:
	if not lifecycle.is_hooked() or fight_state == FightState.NONE:
		return

	var clamped_intensity := clampf(intensity, 0.0, 1.0)

	if (
		is_instance_valid(active_fight_shadow)
		and active_fight_shadow.has_method("play_fight_thrash")
	):
		active_fight_shadow.play_fight_thrash(clamped_intensity)

	fish_thrash_started.emit(clamped_intensity)

func _on_fish_behavior_pressure_changed(value: float) -> void:
	if not lifecycle.is_hooked():
		fish_behavior_pressure = 0.0
		return

	var runtime_pressure_multiplier: float = maxf(
		float(active_fight_context.get(
			"runtime_fish_pressure_multiplier",
			1.0
		)),
		0.01
	)
	fish_behavior_pressure = clampf(
		value * runtime_pressure_multiplier,
		0.0,
		1.0
	)


func add_lure_tension(amount: float) -> void:
	if (
		lifecycle.is_waiting_for_bite()
		or lifecycle.is_bite_window_open()
	):
		tension.add_impulse(amount)


func set_player_tension_bias(value: float) -> void:
	if lifecycle.is_hooked():
		tension.set_player_tension_bias(value)
	else:
		tension.set_player_tension_bias(0.0)


func reset_cast_session() -> void:
	if lifecycle.state != FightLifecycleScript.State.IDLE:
		lifecycle.cancel_cast()

	_reset_cast_runtime(true)
	lifecycle.finish_cast()


func _reset_cast_runtime(clear_bait_data: bool) -> void:
	_end_active_fight_shadow(false)
	bite_timer.stop()
	bite_window_timer.stop()
	bite_active = false
	pending_fish_entry = null
	pending_shadow = null
	active_fish = null
	active_fight_context.clear()

	fight_state = FightState.NONE
	rounds_remaining = 0
	recovery_time_left = 0.0
	player_reeling = false
	player_steering = 0.0
	current_fish_lateral = 0.0
	fish_behavior_pressure = 0.0

	fish_behavior.stop()
	tension.stop()
	_reset_fight_readouts()

	fish_resistance_changed.emit(0.0)
	fish_pull_changed.emit(0.0)
	fish_movement_changed.emit(0.0)
	fish_depth_intent_changed.emit(0.0)

	if clear_bait_data:
		active_bait_data = null
		last_spatial_context.clear()

	_reset_technique()
