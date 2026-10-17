extends Node3D

const FishingScreenLateral = preload("res://scripts/fishing_screen_lateral.gd")

const LureActionRuntimeScript = preload(
	"res://scripts/lure_action_runtime.gd"
)
const FishingLurePresentationPolicyScript = preload(
	"res://scripts/fishing_lure_presentation_policy.gd"
)
const StructureCombatPolicy = preload(
	"res://scripts/fishing_structure_combat_policy.gd"
)

signal landed(point: Vector3)
signal returned
signal depth_changed(current_depth: float, total_depth: float)
signal snag_risk_changed(value: float)
signal snagged(reason: StringName)

@onready var ripple_view: Node3D = $RippleView
@export var gravity: float = 24.0
@export var return_distance: float = 0.5
@export var data: BaitData
@export var floor_collision_mask: int = 2048
@export var floor_ray_depth: float = 100.0
@export var fight_reel_multiplier: float = 0.2
@export_category("Fight Steering")
@export_range(0.0, 1.0, 0.05)
var min_fight_steer_authority: float = 0.45
## A/D keeps the existing free-lure twitch unchanged, but during a fight the
## visible lateral pulse is intentionally smaller and opposed by resistance.
@export_range(0.0, 2.0, 0.05)
var fight_twitch_speed_multiplier: float = 0.85
@export_range(0.0, 1.0, 0.05)
var fight_twitch_min_resistance_multiplier: float = 0.55
@export var max_fish_pull_speed: float = 1.5
@export var fish_vertical_speed: float = 0.8

@export_category("Fight Micro Movement")
## Small extra left/right correction layered on top of the main fish intent.
## This affects physical bait movement only; it does not feed back into
## stamina, tension, counter-steering, or FishBehavior state.
@export_range(0.0, 0.5, 0.01)
var micro_lateral_strength: float = 0.16
## How often the fish chooses a new tiny correction target.
@export var micro_change_time_min: float = 0.28
@export var micro_change_time_max: float = 0.62
## Higher values make the tiny correction settle faster. Kept deliberately
## soft so it reads as living movement rather than jitter.
@export var micro_response_speed: float = 5.0

@export_category("Input Smoothing")
@export var reel_steering_response_speed: float = 8.0
@export var reel_steering_return_speed: float = 10.0
## Empty-lure taps retain a slightly longer arc; hooked-fish response is unchanged.
@export var free_steering_return_speed: float = 8.0
@export var twitch_speed: float = 1.8
@export var twitch_acceleration: float = 10.0
@export var twitch_target_decay: float = 5.0
@export var twitch_deceleration: float = 12.0
@export_category("Fight Distance")
@export var max_extra_fight_distance: float = 3.0

@export_category("Reel Convergence")
## Inside this horizontal distance, lateral freedom begins to fade.
@export var convergence_start_distance: float = 2.2
## Inside this distance, fish pull and player steering can fully converge,
## but only once the fish itself is calm enough.
@export var convergence_full_distance: float = 0.70

## At or above this pull strength, a fighting fish keeps full movement even
## right beside the player. Distance alone can never force convergence.
@export_range(0.0, 1.0, 0.01)
var convergence_block_pull_strength: float = 0.55

## At or below this pull strength, the normal distance-based convergence can
## fully engage. Between this and the block threshold it blends smoothly.
@export_range(0.0, 1.0, 0.01)
var convergence_full_pull_strength: float = 0.12

## Deprecated scene-compatibility field. Fight pull still affects how hard it
## is to REACH the player, but once inside return_distance it can no longer
## veto landing/catch completion.
@export_range(0.0, 1.0, 0.01)
var fight_return_pull_threshold: float = 0.12

@export_category("Free Reeling")
@export var free_reel_speed_multiplier: float = 2.5
## The existing bait scene overrides free_reel_speed_multiplier to 10.0.
## This runtime ceiling slows *unhooked* retrieval without changing the scene,
## authored rod/lure stats, or the hooked-fish fight reel.
@export_range(0.5, 12.0, 0.5) var free_reel_speed_cap: float = 7.0
## The lure works within a BOF-style visible retrieve corridor, away from
## the upper-left beach and the bottom power bar. This is not a brick wall:
## outgoing steering is redirected into travel toward the player instead.
## The hooked-fish combat solver keeps its own movement rules.
@export_range(0.025, 0.45, 0.01) var free_reel_left_limit: float = 0.10
@export_range(0.55, 0.975, 0.01) var free_reel_right_limit: float = 0.90
@export_range(0.05, 0.55, 0.01) var free_reel_top_limit: float = 0.05
@export_range(0.55, 0.90, 0.01) var free_reel_bottom_limit: float = 0.77
## A/D gently retrieves even without K. Holding K retains the full reel speed.
@export_range(0.05, 1.0, 0.05) var free_steering_retrieve_ratio: float = 0.45
## Scale orthogonal empty-lure contributions independently; K alone is unchanged.
@export_range(0.5, 2.0, 0.025) var free_steering_lateral_multiplier: float = 1.175
@export_range(0.5, 2.0, 0.025) var free_steering_inward_multiplier: float = 1.10
## Finish close to Ryu's reachable point at the waterline, never simply
## because the lure touched a screen edge. World units (metres).
@export_range(0.05, 0.60, 0.01) var free_retrieve_shore_finish_radius: float = 0.25
## Stop on the water side of the shoreline instead of drawing an empty lure
## over dry sand while steering. This is measured in WORLD units.
@export_range(0.0, 1.0, 0.05) var free_retrieve_waterline_margin: float = 0.30
var _free_retrieve_arc_sign: float = 1.0
var _free_retrieve_lateral_gain: float = 1.0
var _free_retrieve_side_captured: bool = false
## Only close to the shoreline, the lure may enter Ryu's left-side return
## pocket instead of vanishing at the normal open-water lateral limit.
@export_range(0.5, 4.0, 0.1) var free_retrieve_near_shore_distance: float = 2.0
## Internal guard prevents single-pixel spillover at a hard edge.
const FREE_LURE_GUARD: float = 0.006
var free_lure_region_provider := Callable()

@export_category("Lure Presentation")
## Reference speed used to normalize how quickly the player is working the lure.
@export_range(0.05, 1.0, 0.01)
var presentation_reference_retrieve_speed: float = 0.18
@export_range(0.1, 5.0, 0.05)
var presentation_action_memory_seconds: float = 3.0

@export_category("Manual Pull")
## One S press queues this much horizontal travel toward the player.
## Kept deliberately small so it reads as a rod jerk, not a teleport.
@export var manual_pull_step_distance: float = 0.14
## How quickly each queued pull step is played out.
@export var manual_pull_speed: float = 1.8
## Smooth start/stop for discrete S pulls.
@export var manual_pull_acceleration: float = 8.0
@export var manual_pull_deceleration: float = 10.0
## Lets rapid S taps stack a few pulls without building an unlimited queue.
@export var manual_pull_max_queued_distance: float = 0.42
## Fight-only master scale for the physical distance gained from S. The free
## lure keeps the full 0.14 step above; hooked fish only receive this fraction.
@export_range(0.0, 1.0, 0.05)
var fight_manual_pull_distance_multiplier: float = 0.40
## At maximum fish resistance, an S pull still gets this fraction of the
## already-reduced fight step. As resistance drops, it returns toward the
## fight-only master scale above, never the full free-lure step.
@export_range(0.0, 1.0, 0.05)
var fight_manual_pull_min_multiplier: float = 0.20

@export_category("Snag Risk")
@export var bottom_snag_clearance: float = 0.12
@export var snag_build_rate: float = 0.55
@export var snag_recovery_rate: float = 0.80
@export_range(0.0, 1.0, 0.01)
var snag_reel_press_impulse: float = 0.18
@export_range(0.0, 1.0, 0.01)
var snag_twitch_impulse: float = 0.24
@export var snag_threshold: float = 1.0
@export var snag_probe_radius: float = 0.12
@export_flags_3d_physics var snag_collision_mask: int = 8

@export_category("Air Curve")
@export var air_curve_speed_degrees: float = 35.0
@export var max_air_curve_degrees: float = 30.0

var twitch_velocity: Vector3 = Vector3.ZERO
var twitch_target_velocity: Vector3 = Vector3.ZERO
var fight_max_distance: float = 0.0
var fish_depth_intent: float = 0.0
var fish_pull_strength: float = 0.0
var fight_mode: bool = false
var reel_steering: float = 0.0
var reel_steering_target: float = 0.0
var fight_resistance: float = 1.0
var fish_lateral: float = 0.0
var reel_speed_multiplier: float = 1.0
var manual_pull_remaining: float = 0.0
var manual_pull_current_speed: float = 0.0

# Rod runtime modifiers are configured once by Caster when the rod changes.
# Bait physics consumes plain floats and does not depend on RodData itself.
var rod_steering_strength_multiplier: float = 1.0
var rod_steering_response_multiplier: float = 1.0
var rod_twitch_strength_multiplier: float = 1.0
var rod_manual_pull_distance_multiplier: float = 1.0
var rod_manual_pull_response_multiplier: float = 1.0

# Physical-only micro movement. These values never leave bait_V2.gd.
var micro_lateral: float = 0.0
var micro_target_lateral: float = 0.0
var micro_time_until_change: float = 0.0
var air_curve_input: float = 0.0
var air_curve_angle: float = 0.0

var air_path: PackedVector3Array = PackedVector3Array()
var air_path_progress: float = 0.0
var air_path_playback_speed: float = 1.0

enum State {
	IDLE,
	FLYING,
	SINKING,
	IN_WATER
}

var state: int = State.IDLE

var velocity: Vector3 = Vector3.ZERO

var water_y: float = 0.0
var bottom_y: float = 0.0

var reel_target: Node3D = null
var reeling: bool = false
var simulation_frozen: bool = false
var swim_bounds: Node = null
var shore_boundary: Node = null
var current_service: FishingCurrentService = null
var _current_drift_velocity := Vector3.ZERO
var mastery_service = null

var snag_probe: Area3D = null
var snag_risk: float = 0.0
var snag_triggered: bool = false
var landing_completion_blocked: bool = false

## One cached runtime per spawned bait. Profiles are configured only when lure
## data changes; there are no per-frame resource loads or SceneTree searches.
var lure_action_runtime: LureActionRuntime = LureActionRuntimeScript.new()

# Baseline-fishing presentation memory. Fish read this; it never changes input.
var _presentation_pause_seconds: float = 0.0
var _presentation_twitch_age: float = 999.0
var _presentation_pull_age: float = 999.0

func _ready() -> void:
	_ensure_snag_probe()
	_configure_lure_action_runtime()


func _ensure_snag_probe() -> void:
	if is_instance_valid(snag_probe):
		return

	snag_probe = Area3D.new()
	snag_probe.name = "FishingSnagProbe"
	snag_probe.collision_layer = 0
	snag_probe.collision_mask = snag_collision_mask
	snag_probe.monitoring = true
	snag_probe.monitorable = false

	var shape_node := CollisionShape3D.new()
	shape_node.name = "CollisionShape3D"

	var sphere := SphereShape3D.new()
	sphere.radius = maxf(snag_probe_radius, 0.01)

	shape_node.shape = sphere
	snag_probe.add_child(shape_node)
	add_child(snag_probe)


func launch(
	start_position: Vector3,
	initial_velocity: Vector3,
	surface_y: float,
	water_bottom_y: float
) -> void:
	global_position = start_position
	velocity = initial_velocity
	water_y = surface_y
	bottom_y = water_bottom_y
	air_curve_input = 0.0
	air_curve_angle = 0.0
	air_path = PackedVector3Array()
	air_path_progress = 0.0
	air_path_playback_speed = 1.0
	_presentation_pause_seconds = 0.0
	_presentation_twitch_age = 999.0
	_presentation_pull_age = 999.0
	_reset_micro_movement()
	_reset_snag_state()
	_reset_control_smoothing()
	_free_retrieve_arc_sign = 1.0
	_free_retrieve_lateral_gain = 1.0
	_free_retrieve_side_captured = false
	simulation_frozen = false
	state = State.FLYING
	lure_action_runtime.reset()

	ripple_view.configure(
		self,
		water_y
	)

	ripple_view.hide_ripple()

func set_air_path(
	points: PackedVector3Array,
	playback_speed: float = 1.0
) -> void:
	air_path = points
	air_path_progress = 0.0
	air_path_playback_speed = maxf(
		playback_speed,
		0.01
	)

	if not air_path.is_empty():
		global_position = air_path[0]


func configure_air_curve(
	curve_speed_degrees: float,
	curve_limit_degrees: float
) -> void:
	air_curve_speed_degrees = maxf(
		curve_speed_degrees,
		0.0
	)
	max_air_curve_degrees = maxf(
		curve_limit_degrees,
		0.0
	)


func set_air_curve(value: float) -> void:
	air_curve_input = clampf(value, -1.0, 1.0)


func _update_air_curve(delta: float) -> void:
	if absf(air_curve_input) < 0.01:
		return

	var horizontal_velocity := Vector3(
		velocity.x,
		0.0,
		velocity.z
	)

	if horizontal_velocity.length_squared() < 0.001:
		return

	var max_angle := deg_to_rad(max_air_curve_degrees)

	var requested_change := (
		deg_to_rad(air_curve_speed_degrees)
		* air_curve_input
		* delta
	)

	var new_angle := clampf(
		air_curve_angle + requested_change,
		-max_angle,
		max_angle
	)

	var applied_change := new_angle - air_curve_angle
	air_curve_angle = new_angle

	horizontal_velocity = horizontal_velocity.rotated(
		Vector3.UP,
		applied_change
	)

	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z
	
func set_reel_target(target: Node3D) -> void:
	reel_target = target


func get_water_surface_y() -> float:
	return water_y


func get_surface_position() -> Vector3:
	# Surface-space presentation point above this lure. Keep surface effects
	# on the water plane even when the lure itself is several metres deep.
	return Vector3(
		global_position.x,
		water_y + 0.025,
		global_position.z
	)


func get_reel_target_node() -> Node3D:
	return reel_target


func is_cast_flying() -> bool:
	return state == State.FLYING


func is_in_water_state() -> bool:
	return state == State.SINKING or state == State.IN_WATER


func get_visual_velocity() -> Vector3:
	return velocity


func set_swim_bounds(bounds: Node) -> void:
	swim_bounds = bounds


func set_current_service(service: FishingCurrentService) -> void:
	if current_service != service:
		_current_drift_velocity = Vector3.ZERO
	current_service = service


func set_mastery_service(service) -> void:
	mastery_service = service


func set_shore_boundary(boundary: Node) -> void:
	shore_boundary = boundary


func set_reeling(active: bool) -> void:
	var was_reeling := reeling
	reeling = active

	if fight_mode:
		return

	if reeling and not was_reeling:
		_apply_snag_input_impulse(snag_reel_press_impulse)

	if snag_triggered:
		return

	if not reeling and state == State.IN_WATER:
		var target_y := _get_sink_target_y()

		if not is_equal_approx(global_position.y, target_y):
			state = State.SINKING

func set_reel_steering(value: float) -> void:
	reel_steering_target = clampf(
		value,
		-1.0,
		1.0
	)


func _physics_process(delta: float) -> void:
	if simulation_frozen:
		return

	var before_water_motion: Vector3 = global_position
	_update_reel_steering_response(delta)

	if state == State.SINKING or state == State.IN_WATER:
		_update_bottom_from_world()

	if (
		(state == State.SINKING or state == State.IN_WATER)
		and not fight_mode
	):
		_update_snag_risk(delta)

		if snag_triggered:
			return
	
	if fight_mode and fish_pull_strength > 0.0:
		_update_micro_movement(delta)
		_update_fish_pull(delta)

	# S-pull is a short, discrete retrieve impulse layered on top of the
	# normal water simulation. It is intentionally separate from K reeling:
	# repeated taps can therefore retrieve in visible little increments.
	if (
		manual_pull_remaining > 0.0
		or manual_pull_current_speed > 0.001
	):
		if _update_manual_pull(delta):
			return
	
	match state:
		State.FLYING:
			_update_flying(delta)

		State.SINKING, State.IN_WATER:
			# BOF-style A/D is a small retrieve, not endless sideways travel.
			# Do not change hooked-fish counter-steering or the K input state.
			var steering_retrieve: bool = (
				not fight_mode
				and absf(reel_steering) > 0.001
			)
			if reeling or steering_retrieve:
				_update_reeling(
					delta,
					1.0 if reeling else free_steering_retrieve_ratio * absf(reel_steering)
				)
			elif not fight_mode:
				_update_sinking(delta)
	
	if (
		(state == State.SINKING or state == State.IN_WATER)
		and not fight_mode
	):
		_update_lure_action_motion(delta)
	
	_update_twitch_motion(delta)
	_update_current_drift(delta)
	_update_presentation_state(delta)
	
	_enforce_fight_distance()
	_enforce_shore_boundary()

	# This is a motion redirect, not a hard stop. A/D cannot strand the lure
	# against the rectangle: when an edge blocks sideways travel, preserve
	# inward travel (or complete the retrieve at the shoreward boundary).
	if not fight_mode and (state == State.SINKING or state == State.IN_WATER):
		var requested_position: Vector3 = global_position
		# A/D and K share a WORLD-space return target; all screen limits
		# belong to CameraRig. Physical motion may never be redirected by
		# camera yaw, window height or a fishing-HUD rectangle.
		_guarantee_free_retrieve_progress(before_water_motion, delta)
		if _free_lure_reached_screen_return(before_water_motion, requested_position):
			_finish_return(_free_lure_landing_point())
	
func _update_current_drift(delta: float) -> void:
	if (
		current_service == null
		or simulation_frozen
		or (state != State.SINKING and state != State.IN_WATER)
		or delta <= 0.0
	):
		return

	_current_drift_velocity = current_service.smooth_current_velocity(_current_drift_velocity, global_position, delta)
	var current_velocity := _current_drift_velocity
	if current_velocity.length_squared() <= 0.0000001:
		return

	var proposed_position: Vector3 = (
		global_position + current_velocity * delta
	)
	if (
		swim_bounds != null
		and swim_bounds.has_method("constrain_fish_motion")
	):
		proposed_position = swim_bounds.constrain_fish_motion(
			global_position,
			proposed_position
		)

	global_position.x = proposed_position.x
	global_position.z = proposed_position.z


func _update_flying(delta: float) -> void:
	if air_path.size() >= 2:
		_update_flying_path(delta)
		return

	_update_air_curve(delta)
	
	velocity.y -= gravity * delta

	var previous_position := global_position
	var next_position := previous_position + velocity * delta

	if previous_position.y >= water_y and next_position.y <= water_y:
		next_position.y = water_y
		global_position = next_position

		landed.emit(global_position)

		state = State.SINKING
		return

	global_position = next_position


func _update_flying_path(delta: float) -> void:
	if air_path.size() < 2:
		air_path = PackedVector3Array()
		air_path_progress = 0.0
		return

	var last_index := air_path.size() - 1
	var previous_position := global_position

	# Prediction points are authored at the project's physics tick rate.
	# Advancing fractionally lets us slow the throw without changing the
	# trajectory itself or introducing visible frame stepping.
	air_path_progress += (
		delta
		* float(Engine.physics_ticks_per_second)
		* air_path_playback_speed
	)

	if air_path_progress >= float(last_index):
		global_position = air_path[last_index]

		if delta > 0.0:
			velocity = (
				(global_position - previous_position)
				/ delta
			)

		global_position.y = water_y
		air_path = PackedVector3Array()
		air_path_progress = 0.0

		landed.emit(global_position)
		state = State.SINKING
		return

	var lower_index := int(
		floor(air_path_progress)
	)
	var upper_index := mini(
		lower_index + 1,
		last_index
	)
	var fraction := (
		air_path_progress
		- float(lower_index)
	)

	var next_position := air_path[
		lower_index
	].lerp(
		air_path[upper_index],
		fraction
	)

	if delta > 0.0:
		velocity = (
			(next_position - previous_position)
			/ delta
		)

	global_position = next_position


func _reset_snag_state() -> void:
	snag_risk = 0.0
	snag_triggered = false
	snag_risk_changed.emit(0.0)


func _is_bottom_snag_hazard() -> bool:
	if state != State.SINKING and state != State.IN_WATER:
		return false

	var bottom_gap := global_position.y - bottom_y
	return bottom_gap <= maxf(bottom_snag_clearance, 0.0)


func _get_obstacle_snag_multiplier() -> float:
	if not is_instance_valid(snag_probe):
		return 0.0

	var strongest := 0.0

	for area in snag_probe.get_overlapping_areas():
		if not area.is_in_group("fishing_snag"):
			continue

		var multiplier := 1.0

		if area.has_method("get_snag_risk_multiplier"):
			multiplier = float(
				area.get_snag_risk_multiplier()
			)

		strongest = maxf(
			strongest,
			maxf(multiplier, 0.0)
		)

	return strongest


func get_fight_structure_contacts() -> Array[Dictionary]:
	var contacts: Array[Dictionary] = []
	if not is_instance_valid(snag_probe):
		return contacts
	for area in snag_probe.get_overlapping_areas():
		if not area.is_in_group("fishing_structure"):
			continue
		if not area.has_method("get_fight_structure_snapshot"):
			continue
		var snapshot: Dictionary = area.get_fight_structure_snapshot()
		if snapshot.is_empty():
			continue
		contacts.append(snapshot)
	return contacts


func _has_mastery_capability(capability: StringName) -> bool:
	return (
		mastery_service != null
		and mastery_service.has_method("has_capability")
		and bool(mastery_service.has_capability(capability))
	)


func _get_current_snag_multiplier() -> float:
	var multiplier := 0.0

	if _is_bottom_snag_hazard():
		var bottom_multiplier := 1.0

		if (
			data != null
			and data.has_method(
				"get_bottom_snag_multiplier"
			)
		):
			bottom_multiplier *= float(
				data.get_bottom_snag_multiplier()
			)

		multiplier = maxf(
			multiplier,
			bottom_multiplier
		)

	var obstacle_multiplier := (
		_get_obstacle_snag_multiplier()
	)

	if (
		obstacle_multiplier > 0.0
		and data != null
		and data.has_method(
			"get_obstacle_snag_multiplier"
		)
	):
		obstacle_multiplier *= float(
			data.get_obstacle_snag_multiplier()
		)

	return maxf(
		multiplier,
		obstacle_multiplier
	)


func _get_current_snag_reason() -> StringName:
	if _get_obstacle_snag_multiplier() > 0.0:
		return &"obstacle"

	if _is_bottom_snag_hazard():
		return &"bottom"

	return &"unknown"


func _change_snag_risk(amount: float) -> void:
	if snag_triggered:
		return

	var threshold := maxf(snag_threshold, 0.01)
	var previous := snag_risk
	snag_risk = clampf(
		snag_risk + amount,
		0.0,
		threshold
	)

	if not is_equal_approx(previous, snag_risk):
		snag_risk_changed.emit(snag_risk / threshold)

	if snag_risk >= threshold:
		_trigger_snag_miss(
			_get_current_snag_reason()
		)


func _apply_snag_input_impulse(amount: float) -> void:
	if fight_mode or snag_triggered:
		return

	var hazard_multiplier := (
		_get_current_snag_multiplier()
	)

	if hazard_multiplier <= 0.0:
		return

	_change_snag_risk(
		maxf(amount, 0.0)
		* hazard_multiplier
		* StructureCombatPolicy.get_lure_snag_build_multiplier(
			_has_mastery_capability(&"snag_escape")
		)
	)


func _update_snag_risk(delta: float) -> void:
	if snag_triggered:
		return

	var hazard_multiplier := (
		_get_current_snag_multiplier()
	)

	var knows_snag_escape := _has_mastery_capability(&"snag_escape")
	if hazard_multiplier > 0.0 and reeling:
		_change_snag_risk(
			maxf(snag_build_rate, 0.0)
			* hazard_multiplier
			* StructureCombatPolicy.get_lure_snag_build_multiplier(
				knows_snag_escape
			)
			* delta
		)
		return

	if snag_risk > 0.0:
		_change_snag_risk(
			-maxf(snag_recovery_rate, 0.0)
			* StructureCombatPolicy.get_lure_snag_recovery_multiplier(
				knows_snag_escape
			)
			* delta
		)


func _trigger_snag_miss(reason: StringName) -> void:
	if snag_triggered:
		return

	snag_triggered = true
	reeling = false
	_reset_control_smoothing()
	_reset_micro_movement()
	simulation_frozen = true
	hide_ripple()

	snagged.emit(reason)

	# Reuse the existing return cleanup path. This ends the attempt and
	# returns fishing to AIM without touching the cast/input state machine.
	returned.emit()


func _update_sinking(delta: float) -> void:
	if data == null:
		return

	var target_y := _get_sink_target_y()
	var previous_y := global_position.y

	global_position.y = move_toward(
		global_position.y,
		target_y,
		data.sink_speed * delta
	)

	if not is_equal_approx(previous_y, global_position.y):
		_emit_depth()

	if is_equal_approx(global_position.y, target_y):
		state = State.IN_WATER
	else:
		state = State.SINKING


func _get_sink_target_y() -> float:
	if data == null:
		return bottom_y

	var depth_ratio := clampf(data.sink_depth, 0.0, 1.0)

	return lerpf(
		water_y,
		bottom_y,
		depth_ratio
	)

func _update_reeling(delta: float, speed_scale: float = 1.0) -> void:
	if data == null or reel_target == null:
		return

	var target_position: Vector3 = reel_target.global_position if fight_mode else _free_lure_landing_point()

	var to_target := Vector3(
		target_position.x - global_position.x,
		0.0,
		target_position.z - global_position.z
	)

	var distance := to_target.length()

	if _can_complete_active_return(distance):
		_finish_return(target_position)
		return

	var forward := to_target.normalized()
	var side := Vector3.UP.cross(forward).normalized()

	# The convergence fade is ONLY for hooked fish. An empty lure must
	# continue its A/D arc right through the near-shore return pocket;
	# otherwise it suddenly straightens toward Ryu at 2.2 m.
	var convergence: float = _get_reel_convergence(distance) if fight_mode else 0.0
	var steering_fade: float = 1.0 - convergence

	var steering_strength := (
		data.reel_steer_strength
		* rod_steering_strength_multiplier
	)

	if fight_mode:
		var steer_authority := lerpf(
			min_fight_steer_authority,
			1.0,
			1.0 - fight_resistance
		)

		steering_strength *= steer_authority

	var reel_direction := (
		forward
		+ side * reel_steering * steering_strength * steering_fade
	).normalized()
	if not fight_mode:
		reel_direction = _free_retrieve_motion(forward, steering_strength).normalized()

	var reel_speed: float = data.reel_speed * reel_speed_multiplier * maxf(speed_scale, 0.0)

	if not fight_mode:
		reel_speed *= minf(maxf(free_reel_speed_multiplier, 0.0), maxf(free_reel_speed_cap, 0.0))
	
	if fight_mode:
		var multiplier := lerpf(
			1.0,
			fight_reel_multiplier,
			fight_resistance
		)

		reel_speed *= multiplier

	var move_distance := minf(
		reel_speed * delta,
		distance
	)
	if not fight_mode:
		# Preserve the same actual reel velocity right up to the final
		# water-side catch radius. Only cap the LAST sub-step to avoid
		# overshooting the target during a low-FPS physics tick.
		var radial_authority: float = maxf(reel_direction.dot(forward),0.001)
		move_distance = minf(move_distance,
			maxf(distance-free_retrieve_shore_finish_radius,0.0)/radial_authority)
	var proposed_position: Vector3 = global_position + reel_direction * move_distance
	# Neither A nor D is clamped in world space by camera/HUD limits.
	# CameraRig alone follows the visual bait when it reaches a screen edge.
	proposed_position = _constrain_waterborne_shore_position(proposed_position)

	global_position.x = proposed_position.x
	global_position.z = proposed_position.z

	if not fight_mode:
		global_position.y = move_toward(
			global_position.y,
			water_y,
			data.reel_rise_speed * delta
		)

	_emit_depth()

	var remaining_distance := Vector2(
		target_position.x - global_position.x,
		target_position.z - global_position.z
	).length()

	if _can_complete_active_return(remaining_distance):
		_finish_return(target_position)
	
# -- Screen-space water lure envelope ----------------------------------------
# Screen limits control physical free-lure travel, NOT where the camera points.
# Project at the water SURFACE, even for a sinking lure, so depth does not
# accidentally move it through the lower edge. Never edit the fishing camera.
func _free_retrieve_motion(inward: Vector3, strength: float) -> Vector3:
	# Freeze the camera-right bearing on the first waterborne pull. Using the
	# LIVE camera each frame made the same key change physical direction
	# when the camera moved, causing a drifting beachward spiral.
	if absf(reel_steering) <= 0.001:
		return inward
	var tangent: Vector3 = Vector3.UP.cross(inward).normalized()
	if not _free_retrieve_side_captured:
		var cam: Camera3D = get_viewport().get_camera_3d()
		var screen_right: Vector3 = FishingScreenLateral.right(
			cam, _free_lure_surface_position(global_position),tangent)
		_free_retrieve_arc_sign = -1.0 if tangent.dot(screen_right) < 0.0 else 1.0
		# Preserve the initial, requested SCREEN direction even when the
		# inward return vector already points strongly the opposite way.
		# Calibrate ONCE, identically for A and D; never recalculate after
		# camera panning/yaw or the left and right arcs diverge again.
		if cam != null and not cam.is_position_behind(_free_lure_surface_position(global_position)):
			var spot: Vector3 = _free_lure_surface_position(global_position)
			var pixel: Vector2 = cam.unproject_position(spot)
			var dx_inward: float = (cam.unproject_position(spot+inward*0.05)-pixel).x
			var dx_side: float = absf((cam.unproject_position(spot+tangent*0.05)-pixel).x)
			if dx_side > 0.000001 and strength > 0.000001:
				var required_gain: float = (absf(dx_inward)+0.05)/(
					dx_side*strength*free_steering_lateral_multiplier)
				_free_retrieve_lateral_gain = clampf(required_gain,1.0,2.5)
		_free_retrieve_side_captured = true
	# Rotate the tangent with the radial vector, but preserve its initial
	# handedness. A constant world-X right vector would FLIP the arc direction
	# when the lure circles past a perpendicular bearing near Ryu.
	var side: Vector3 = tangent * _free_retrieve_arc_sign
	# Reproject the same cast-time world bearing onto the tangent of the
	# radial return. Radial authority always stays positive. A and D have
	# IDENTICAL speed and mirror one another around the return vector.
	var arc: Vector3 = (inward * free_steering_inward_multiplier
		+ side * reel_steering * strength * free_steering_lateral_multiplier * _free_retrieve_lateral_gain)
	return arc.normalized()


func is_free_lure_framing_active() -> bool:
	return not fight_mode and (state == State.IN_WATER or state == State.SINKING)


func get_reel_steering_for_camera() -> float:
	return reel_steering if not fight_mode else 0.0


func _free_lure_screen_region() -> Rect2:
	var left: float = free_reel_left_limit + FREE_LURE_GUARD
	var right: float = free_reel_right_limit - FREE_LURE_GUARD
	var top: float = free_reel_top_limit + FREE_LURE_GUARD
	var bottom: float = free_reel_bottom_limit - FREE_LURE_GUARD
	if reel_target != null and not fight_mode:
		var landing: Vector3 = _free_lure_landing_point()
		var flat: Vector2 = Vector2(global_position.x, global_position.z)
		var shore: Vector2 = Vector2(landing.x, landing.z)
		var distance: float = flat.distance_to(shore)
		var release_ratio: float = clampf(
			(free_retrieve_near_shore_distance-distance)
			/ maxf(free_retrieve_near_shore_distance-0.3, 0.1),
			0.0, 1.0
		)
		# Near Ryu, the water return pocket is left of the power meter.
		# Far offshore, the original upper-left limit still applies.
		# Expansion must never narrow the already legal region. The old 19%
		# pocket moved the left edge rightward when using wider framing bounds.
		var camera := get_viewport().get_camera_3d()
		var landing_left := left
		if camera != null:
			var viewport_size := camera.get_viewport().get_visible_rect().size
			if viewport_size.x > 0.0:
				landing_left = clampf(_free_lure_screen_point(camera, landing, viewport_size).x - FREE_LURE_GUARD, 0.025, left)
		left = lerpf(left, landing_left, release_ratio)
	var region := Rect2(Vector2(left, top), Vector2(maxf(right-left, 0.001), maxf(bottom-top, 0.001)))
	# The camera's live HUD rectangles belong to presentation. They change
	# with window resizing, and must not change physical retrieve constraints.
	# The authored free-reel ratios remain the simulation's stable envelope.
	return region


func _free_lure_surface_position(world_position: Vector3) -> Vector3:
	return Vector3(world_position.x, water_y + 0.025, world_position.z)


func _free_lure_projection_scale(camera: Camera3D, viewport_size: Vector2) -> Vector2:
	# Logical physics/corridor coordinates use a 960x480 reference lens in
	# the desktop companion, independent of how tall the displayed viewport
	# becomes. DesktopCompanion stores the authored FOV before expansion.
	# Native/mobile without this metadata retain their current projection.
	if not camera.has_meta("desktop_base_projection"):
		return Vector2.ONE
	var baseline: Dictionary = camera.get_meta("desktop_base_projection")
	var baseline_fov: float = float(baseline.get("fov", camera.fov))
	if baseline_fov <= 0.01 or viewport_size.y <= 0.0:
		return Vector2.ONE
	var focal_scale: float = tan(deg_to_rad(camera.fov) * 0.5) / tan(deg_to_rad(baseline_fov) * 0.5)
	var current_aspect: float = viewport_size.x / viewport_size.y
	var reference_aspect: float = 960.0 / 480.0
	if camera.keep_aspect == Camera3D.KEEP_HEIGHT:
		return Vector2(focal_scale * current_aspect / reference_aspect, focal_scale)
	return Vector2(focal_scale, focal_scale * reference_aspect / current_aspect)


func _free_lure_screen_point(camera: Camera3D, world_position: Vector3, viewport_size: Vector2) -> Vector2:
	# Simulate the authored reference camera, NOT the display-only vertical
	# camera anchor. A taller floating viewport must not alter bait limits.
	var vertical_shift: float = float(camera.get_meta("desktop_vertical_presentation_offset", 0.0))
	var displayed: Vector2
	if absf(vertical_shift) > 0.00001:
		var optical: Transform3D = camera.global_transform
		optical.origin += optical.basis.x * camera.h_offset
		optical.origin += optical.basis.y * (camera.v_offset - vertical_shift)
		var local: Vector3 = optical.affine_inverse() * _free_lure_surface_position(world_position)
		var projected: Vector4 = camera.get_camera_projection() * Vector4(local.x,local.y,local.z,1.0)
		if absf(projected.w) <= 0.0000001:
			return Vector2.ONE * 0.5
		displayed = Vector2(0.5 + projected.x/projected.w*0.5,0.5 - projected.y/projected.w*0.5)
	else:
		displayed = camera.unproject_position(_free_lure_surface_position(world_position)) / viewport_size
	return Vector2.ONE * 0.5 + (displayed-Vector2.ONE*0.5) * _free_lure_projection_scale(camera, viewport_size)


func _free_lure_reference_ray_pixel(camera: Camera3D, stable: Vector2, viewport_size: Vector2) -> Vector2:
	var factors: Vector2 = _free_lure_projection_scale(camera, viewport_size)
	return (Vector2.ONE*0.5 + (stable-Vector2.ONE*0.5) / Vector2(maxf(factors.x,0.00001),maxf(factors.y,0.00001))) * viewport_size


func _screen_point_on_water(camera: Camera3D, viewport_point: Vector2) -> Vector3:
	var ray_origin: Vector3 = camera.project_ray_origin(viewport_point)
	# Reverse the display-only lens shift for free-retrieve tangent probes.
	# Camera orientation/FOV are unchanged; ray directions remain valid.
	var vertical_shift: float = float(camera.get_meta("desktop_vertical_presentation_offset",0.0))
	ray_origin -= camera.global_basis.y * vertical_shift
	var ray_direction: Vector3 = camera.project_ray_normal(viewport_point)
	if absf(ray_direction.y) < 0.00001:
		return Vector3.INF
	var distance: float = (water_y + 0.025 - ray_origin.y) / ray_direction.y
	if distance <= 0.0:
		return Vector3.INF
	return ray_origin + ray_direction * distance


func _free_lure_landing_point() -> Vector3:
	# The actual player is on land; the lure must approach the reachable
	# water-side projection rather than chasing a point through the beach.
	if reel_target == null:
		return global_position
	var destination: Vector3 = reel_target.global_position
	if shore_boundary != null and shore_boundary.has_method("get_water_side_projection"):
		var shore_contact: Vector3 = shore_boundary.get_water_side_projection(destination)
		var into_water: Vector3 = shore_contact - destination
		into_water.y = 0.0
		if into_water.length_squared() > 0.000001:
			destination = shore_boundary.get_water_side_projection(
				shore_contact + into_water.normalized()*free_retrieve_waterline_margin)
		else:
			destination = shore_contact
	return destination


func _free_lure_screen_error(screen: Vector2, region: Rect2) -> float:
	var dx: float = screen.x - clampf(screen.x, region.position.x, region.end.x)
	var dy: float = screen.y - clampf(screen.y, region.position.y, region.end.y)
	return Vector2(dx, dy).length_squared()


func _free_lure_retrieve_candidate(
	camera: Camera3D, viewport_size: Vector2, region: Rect2,
	from_position: Vector3, proposed_position: Vector3,
	landing_point: Vector3, requested_direction: Vector2,
	best_position: Vector3, best_rating: Vector2
) -> Dictionary:
	# Return the best legal candidate plus its rating. Ratings sort by
	# screen-envelope violation first, then proximity to the requested arc.
	# Reject candidates that do not advance toward the actual landing point.
	var adjusted: Vector3 = _constrain_waterborne_shore_position(proposed_position)
	var from_flat: Vector2 = Vector2(from_position.x, from_position.z)
	var landing_flat: Vector2 = Vector2(landing_point.x, landing_point.z)
	var adjusted_flat: Vector2 = Vector2(adjusted.x, adjusted.z)
	var start_distance: float = from_flat.distance_to(landing_flat)
	var new_distance: float = adjusted_flat.distance_to(landing_flat)
	if new_distance >= start_distance - 0.000001:
		return {"point":best_position, "rating":best_rating}
	var adjusted_surface: Vector3 = _free_lure_surface_position(adjusted)
	if camera.is_position_behind(adjusted_surface):
		return {"point":best_position, "rating":best_rating}
	var projected: Vector2 = _free_lure_screen_point(camera, adjusted, viewport_size)
	var violation: float = _free_lure_screen_error(projected, region)
	var achieved_flat: Vector2 = adjusted_flat-from_flat
	# At a hard edge, substantial inward motion matters more than matching
	# the old A/D heading. Both factors remain nonzero, preserving the arc.
	var arc_preference: float = (
		0.55 * clampf((start_distance-new_distance) / maxf(requested_direction.length(), 0.000001), 0.0, 1.0)
		+ 0.45 * achieved_flat.normalized().dot(requested_direction.normalized())
	)
	var rating: Vector2 = Vector2(-violation, arc_preference)
	if rating.x > best_rating.x + 0.0000000001 or (
		absf(rating.x-best_rating.x) <= 0.0000000001 and rating.y > best_rating.y
	):
		return {"point":adjusted, "rating":rating}
	return {"point":best_position, "rating":best_rating}


func _clamp_free_lure_to_screen(from_position: Vector3, proposed_position: Vector3) -> Vector3:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null or not camera.current or reel_target == null:
		return proposed_position
	var size: Vector2 = camera.get_viewport().get_visible_rect().size
	if size.x < 1.0 or size.y < 1.0:
		return proposed_position
	var region: Rect2 = _free_lure_screen_region()
	var intended: Vector3 = _constrain_waterborne_shore_position(proposed_position)
	var intended_surface: Vector3 = _free_lure_surface_position(intended)
	if not camera.is_position_behind(intended_surface):
		var intended_screen: Vector2 = _free_lure_screen_point(camera, intended, size)
		if region.has_point(intended_screen):
			return intended

	var landing_point: Vector3 = _free_lure_landing_point()
	var planned_flat: Vector2 = Vector2(
			proposed_position.x-from_position.x, proposed_position.z-from_position.z
	)
	var step_length: float = planned_flat.length()
	if step_length < 0.000001:
		return from_position
	var from_flat: Vector2 = Vector2(from_position.x, from_position.z)
	var goal_flat: Vector2 = Vector2(landing_point.x, landing_point.z)
	var inward_flat: Vector2 = goal_flat-from_flat
	if inward_flat.length_squared() < 0.0000001:
		return from_position
	var start_screen: Vector2 = _free_lure_screen_point(camera, from_position, size)
	var start_error: float = _free_lure_screen_error(start_screen, region)
	var best_position: Vector3 = from_position
	var best_rating: Vector2 = Vector2(-start_error, -2.0)
	# Blend away A/D authority BEFORE it becomes a brick wall. Every
	# candidate consumes the same reel distance and advances inward.
	# A/D makes an arc while there is room; at the side boundary, the arc
	# naturally curves back instead of parking the bait at a corner.
	for index in range(9):
		var blend: float = float(index) / 8.0
		var direction: Vector2 = planned_flat.normalized().lerp(
			inward_flat.normalized(), blend
		).normalized()
		if direction.length_squared() < 0.000001:
			continue
		var trial: Vector3 = from_position + Vector3(
			direction.x*step_length, 0.0, direction.y*step_length
		)
		var candidate: Dictionary = _free_lure_retrieve_candidate(
			camera, size, region, from_position, trial, landing_point,
			planned_flat, best_position, best_rating
		)
		best_position = candidate["point"] as Vector3
		best_rating = candidate["rating"] as Vector2

	# If both forward and steering push toward a blocked projected corner,
	# test water-plane tangents to that edge. This is the missing behaviour:
	# sliding inward along the upper-left or lower-right boundary instead of
	# clipping the whole move to zero. The hard shore plane is tested too.
	var goal_screen: Vector2 = _free_lure_screen_point(camera, landing_point, size)
	var screen_directions: Array[Vector2] = [
		goal_screen-start_screen,
		Vector2(1.0,0.0), Vector2(-1.0,0.0),
		Vector2(0.0,1.0), Vector2(0.0,-1.0)
	]
	for screen_direction in screen_directions:
		if screen_direction.length_squared() < 0.0000001:
			continue
		# One screen pixel is a *direction probe* only; the physical motion
		# is still limited to the exact world-space reel distance this frame.
		var probe_screen: Vector2 = start_screen + screen_direction.normalized() * (1.0 / maxf(size.x,size.y))
		var probe_water: Vector3 = _screen_point_on_water(camera, _free_lure_reference_ray_pixel(camera, probe_screen, size))
		if not probe_water.is_finite():
			continue
		var trial_delta: Vector2 = Vector2(
			probe_water.x-from_position.x, probe_water.z-from_position.z
		)
		if trial_delta.length_squared() < 0.0000001:
			continue
		var trial_direction: Vector2 = trial_delta.normalized() * step_length
		var trial: Vector3 = from_position + Vector3(trial_direction.x, 0.0, trial_direction.y)
		var candidate: Dictionary = _free_lure_retrieve_candidate(
			camera, size, region, from_position, trial, landing_point,
			planned_flat, best_position, best_rating
		)
		best_position = candidate["point"] as Vector3
		best_rating = candidate["rating"] as Vector2

	# Minimum radial progress is a physical retrieval invariant, not merely
	# "any change in position". At the D-side shoreline a solver candidate
	# may change by micrometres and suppress the old zero-motion fallback.
	# Compare its progress to the requested movement, and favor a bounded
	# inward water-side step when the lateral arc has effectively stalled.
	var best_flat: Vector2 = Vector2(best_position.x, best_position.z)
	var achieved_progress: float = inward_flat.length() - best_flat.distance_to(goal_flat)
	var needed_progress: float = minf(step_length * 0.25, inward_flat.length() * 0.25)
	if achieved_progress < needed_progress:
		var radial: Vector2 = inward_flat.normalized() * minf(step_length, inward_flat.length())
		var radial_trial: Vector3 = from_position + Vector3(radial.x, 0.0, radial.y)
		var recovered: Vector3 = _constrain_waterborne_shore_position(radial_trial)
		var recovered_flat: Vector2 = Vector2(recovered.x, recovered.z)
		var radial_progress: float = inward_flat.length() - recovered_flat.distance_to(goal_flat)
		if radial_progress > achieved_progress + 0.000001:
			# This return-point fallback is deliberately bounded to ONE physical
			# reel step; it must not teleport the lure across the shoreline.
			return recovered
	# An already out-of-bounds landing or camera yaw is allowed to converge
	# over subsequent frames; never teleport the bait across the beach.
	if best_rating.x < -start_error - 0.0000000001:
		return from_position
	return best_position


func _guarantee_free_retrieve_progress(before_position: Vector3, delta: float) -> void:
	# Physical convergence contract, independent of viewport/camera/HUD. The
	# preferred A/D arc remains untouched until it fails to move inward.
	if fight_mode or reel_target == null or data == null or delta <= 0.0:
		return
	if state != State.SINKING and state != State.IN_WATER:
		return
	if not reeling and absf(reel_steering) <= 0.001:
		return
	var landing: Vector3 = _free_lure_landing_point()
	var start: Vector2 = Vector2(before_position.x, before_position.z)
	var goal: Vector2 = Vector2(landing.x, landing.z)
	var original_distance: float = start.distance_to(goal)
	if original_distance <= maxf(free_retrieve_shore_finish_radius, 0.05):
		return
	var final_flat: Vector2 = Vector2(global_position.x, global_position.z)
	var actual_progress: float = original_distance - final_flat.distance_to(goal)
	var input_scale: float = 1.0 if reeling else free_steering_retrieve_ratio * absf(reel_steering)
	var free_speed: float = data.reel_speed * reel_speed_multiplier * minf(
		maxf(free_reel_speed_multiplier, 0.0), maxf(free_reel_speed_cap, 0.0))
	var requested_step: float = free_speed * input_scale * delta
	if requested_step <= 0.000001:
		return
	# Require only 25% of a normal reel tick's progress. Sideways arc motion
	# is still the preferred solution; this catches actual stalls, not arcs.
	var minimum_progress: float = minf(requested_step * 0.25, original_distance)
	# Do not overwrite a moving D arc with straight-to-Ryu motion just
	# because its radial component is less than the emergency 25% threshold.
	# Mirror-A has substantial inward authority. Only the *physical* zero-
	# progress case is allowed to use the final shoreline recovery below.
	if absf(reel_steering) >= 0.5 and actual_progress > 0.000001:
		return
	if actual_progress >= minimum_progress:
		return
	# Shore is a convex water-side half-plane. Advancing along the segment
	# to the already-projected reachable landing point remains on water.
	# Project again for numeric safety; never teleport more than a reel tick.
	var radial_step: float = minf(requested_step, original_distance)
	var radial_flat: Vector2 = start.move_toward(goal, radial_step)
	var candidate: Vector3 = _constrain_waterborne_shore_position(
		Vector3(radial_flat.x, global_position.y, radial_flat.y))
	var candidate_flat: Vector2 = Vector2(candidate.x, candidate.z)
	var candidate_progress: float = original_distance - candidate_flat.distance_to(goal)
	if candidate_progress > actual_progress + 0.000001:
		global_position.x = candidate.x
		global_position.z = candidate.z


func _free_lure_reached_screen_return(_from_position: Vector3, _unclamped: Vector3) -> bool:
	# Reaching x=34%, y=77%, or a right-hand corner NEVER finishes a cast.
	# Only reaching Ryu's physically reachable water-side landing point does.
	if fight_mode or reel_target == null:
		return false
	if not reeling and absf(reel_steering) <= 0.001:
		return false
	var water_destination: Vector3 = _free_lure_landing_point()
	var from_flat: Vector2 = Vector2(global_position.x, global_position.z)
	var destination_flat: Vector2 = Vector2(water_destination.x, water_destination.z)
	return from_flat.distance_to(destination_flat) <= maxf(
		free_retrieve_shore_finish_radius, 0.05
	)


func queue_manual_pull() -> void:
	if state != State.SINKING and state != State.IN_WATER:
		return

	if reel_target == null:
		return

	# Free-lure S pulls still participate in snagging. Once a fish is hooked,
	# snagging is disabled and the pulse is instead opposed by fish resistance.
	if not fight_mode:
		_apply_snag_input_impulse(snag_reel_press_impulse)

		if snag_triggered:
			return

		_presentation_pull_age = 0.0

	var distance_multiplier := 1.0

	if fight_mode:
		distance_multiplier = (
			clampf(
				fight_manual_pull_distance_multiplier,
				0.0,
				1.0
			)
			* lerpf(
				1.0,
				clampf(
					fight_manual_pull_min_multiplier,
					0.0,
					1.0
				),
				clampf(fight_resistance, 0.0, 1.0)
			)
		)

	var rod_distance_multiplier: float = maxf(
		rod_manual_pull_distance_multiplier,
		0.0
	)

	var pull_step := (
		maxf(manual_pull_step_distance, 0.0)
		* distance_multiplier
		* rod_distance_multiplier
	)
	var queue_cap := (
		maxf(manual_pull_max_queued_distance, 0.0)
		* distance_multiplier
		* rod_distance_multiplier
	)

	manual_pull_remaining = minf(
		manual_pull_remaining + pull_step,
		queue_cap
	)


func _update_manual_pull(delta: float) -> bool:
	if reel_target == null:
		_reset_manual_pull_motion()
		return false

	if state != State.SINKING and state != State.IN_WATER:
		_reset_manual_pull_motion()
		return false

	var target_position: Vector3 = reel_target.global_position
	var to_target := Vector3(
		target_position.x - global_position.x,
		0.0,
		target_position.z - global_position.z
	)
	var distance: float = to_target.length()

	if _can_complete_active_return(distance):
		_finish_return(target_position)
		return true

	if distance <= 0.0001:
		_reset_manual_pull_motion()
		return false

	var available_distance: float = maxf(
		distance - get_effective_return_distance(),
		0.0
	)

	if (
		available_distance <= 0.0
		or manual_pull_remaining <= 0.00001
	):
		manual_pull_current_speed = move_toward(
			manual_pull_current_speed,
			0.0,
			maxf(manual_pull_deceleration, 0.0)
			* maxf(rod_manual_pull_response_multiplier, 0.01)
			* delta
		)

		if manual_pull_current_speed <= 0.001:
			manual_pull_current_speed = 0.0

		return false

	var response_multiplier: float = maxf(
		rod_manual_pull_response_multiplier,
		0.01
	)
	var acceleration: float = (
		maxf(manual_pull_acceleration, 0.0)
		* response_multiplier
	)
	var deceleration: float = (
		maxf(manual_pull_deceleration, 0.001)
		* response_multiplier
	)

	# Kinematic stopping-speed cap: accelerate into the S pull, then ease
	# down naturally as the queued distance runs out instead of stopping
	# at a fixed-size positional increment.
	var stopping_speed: float = sqrt(
		maxf(
			2.0
			* deceleration
			* manual_pull_remaining,
			0.0
		)
	)
	var desired_speed: float = minf(
		maxf(manual_pull_speed, 0.0),
		stopping_speed
	)

	var speed_change: float = (
		acceleration
		if manual_pull_current_speed < desired_speed
		else deceleration
	)

	manual_pull_current_speed = move_toward(
		manual_pull_current_speed,
		desired_speed,
		speed_change * delta
	)

	var move_distance: float = minf(
		minf(
			manual_pull_current_speed * delta,
			manual_pull_remaining
		),
		available_distance
	)

	if move_distance <= 0.0:
		return false

	var previous_position := global_position
	var proposed_position := (
		global_position
		+ to_target.normalized() * move_distance
	)
	proposed_position = _constrain_waterborne_shore_position(
		proposed_position
	)

	global_position.x = proposed_position.x
	global_position.z = proposed_position.z

	var actual_move_distance := Vector2(
		global_position.x - previous_position.x,
		global_position.z - previous_position.z
	).length()
	manual_pull_remaining = maxf(
		manual_pull_remaining - actual_move_distance,
		0.0
	)

	_emit_depth()

	var remaining_flat := Vector2(
		target_position.x - global_position.x,
		target_position.z - global_position.z
	).length()

	if _can_complete_active_return(remaining_flat):
		_finish_return(target_position)
		return true

	if manual_pull_remaining <= 0.00001:
		manual_pull_remaining = 0.0

	return false


func _update_reel_steering_response(delta: float) -> void:
	# An empty lure begins curving as soon as A or D is pressed. The
	# fight steering keeps its established rod-dependent smoothing.
	if not fight_mode and (state == State.SINKING or state == State.IN_WATER):
		if absf(reel_steering_target) > 0.001:
			reel_steering = reel_steering_target
		else:
			reel_steering *= exp(-maxf(free_steering_return_speed, 0.0) * maxf(rod_steering_response_multiplier, 0.01) * delta)
			if absf(reel_steering) <= 0.001:
				reel_steering = 0.0
		return
	var response_multiplier: float = maxf(
		rod_steering_response_multiplier,
		0.01
	)
	var response_speed: float = (
		reel_steering_response_speed
		if absf(reel_steering_target) > 0.001
		else reel_steering_return_speed
	)

	reel_steering = move_toward(
		reel_steering,
		reel_steering_target,
		maxf(response_speed, 0.0)
		* response_multiplier
		* delta
	)

	if (
		absf(reel_steering_target) <= 0.001
		and absf(reel_steering) <= 0.001
	):
		reel_steering = 0.0


func _update_twitch_motion(delta: float) -> void:
	if (
		twitch_velocity.length_squared() <= 0.000001
		and twitch_target_velocity.length_squared() <= 0.000001
	):
		return

	var response_multiplier: float = maxf(
		rod_steering_response_multiplier,
		0.01
	)

	twitch_velocity = twitch_velocity.move_toward(
		twitch_target_velocity,
		maxf(twitch_acceleration, 0.0)
		* response_multiplier
		* delta
	)

	global_position += twitch_velocity * delta

	twitch_target_velocity = twitch_target_velocity.move_toward(
		Vector3.ZERO,
		maxf(twitch_target_decay, 0.0)
		* response_multiplier
		* delta
	)

	if twitch_target_velocity.length_squared() <= 0.0001:
		twitch_target_velocity = Vector3.ZERO
		twitch_velocity = twitch_velocity.move_toward(
			Vector3.ZERO,
			maxf(twitch_deceleration, 0.0)
			* response_multiplier
			* delta
		)

	if twitch_velocity.length_squared() <= 0.0001:
		twitch_velocity = Vector3.ZERO


func _reset_manual_pull_motion() -> void:
	manual_pull_remaining = 0.0
	manual_pull_current_speed = 0.0


func _reset_control_smoothing() -> void:
	reel_steering = 0.0
	reel_steering_target = 0.0
	twitch_velocity = Vector3.ZERO
	twitch_target_velocity = Vector3.ZERO
	_reset_manual_pull_motion()


func set_rod_control_multipliers(
	steering_strength: float,
	steering_response: float,
	twitch_strength: float,
	manual_pull_distance: float,
	manual_pull_response: float
) -> void:
	rod_steering_strength_multiplier = maxf(
		steering_strength,
		0.0
	)
	rod_steering_response_multiplier = maxf(
		steering_response,
		0.01
	)
	rod_twitch_strength_multiplier = maxf(
		twitch_strength,
		0.0
	)
	rod_manual_pull_distance_multiplier = maxf(
		manual_pull_distance,
		0.0
	)
	rod_manual_pull_response_multiplier = maxf(
		manual_pull_response,
		0.01
	)


func _configure_lure_action_runtime() -> void:
	if lure_action_runtime == null:
		lure_action_runtime = LureActionRuntimeScript.new()

	var profile: LureActionProfile = null

	if data != null:
		profile = data.get_action_profile()

	lure_action_runtime.configure(profile)


func _update_lure_action_motion(delta: float) -> void:
	if data == null or lure_action_runtime == null:
		return

	# Never let presentation/action motion pull a bait back out of the final
	# return radius after _update_reeling() has completed the retrieve.
	if reel_target != null:
		var bait_flat := Vector2(
			global_position.x,
			global_position.z
		)
		var target_flat := Vector2(
			reel_target.global_position.x,
			reel_target.global_position.z
		)

		if bait_flat.distance_to(target_flat) <= return_distance:
			return

	var local_delta: Vector3 = (
		lure_action_runtime.sample_motion_delta(
			delta,
			reeling
		)
	)

	if local_delta.length_squared() <= 0.0000001:
		return

	var forward: Vector3 = _get_lure_action_forward()
	var side: Vector3 = Vector3.UP.cross(forward).normalized()

	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT

	var proposed_position: Vector3 = (
		global_position
		+ side * local_delta.x
		+ Vector3.UP * local_delta.y
		+ forward * local_delta.z
	)

	if (
		swim_bounds != null
		and swim_bounds.has_method("constrain_fish_motion")
	):
		proposed_position = swim_bounds.constrain_fish_motion(
			global_position,
			proposed_position
		)

	var previous_y: float = global_position.y

	global_position.x = proposed_position.x
	global_position.z = proposed_position.z
	global_position.y = clampf(
		proposed_position.y,
		bottom_y,
		water_y + 0.03
	)

	if not is_equal_approx(previous_y, global_position.y):
		_emit_depth()


func _get_lure_action_forward() -> Vector3:
	if reel_target != null:
		var to_target: Vector3 = (
			reel_target.global_position
			- global_position
		)
		to_target.y = 0.0

		if to_target.length_squared() > 0.0001:
			return to_target.normalized()

	var horizontal_velocity := Vector3(
		velocity.x,
		0.0,
		velocity.z
	)

	if horizontal_velocity.length_squared() > 0.0001:
		return horizontal_velocity.normalized()

	return Vector3.FORWARD


func _update_presentation_state(delta: float) -> void:
	if delta <= 0.0:
		return

	var memory: float = maxf(presentation_action_memory_seconds, 0.1)
	_presentation_twitch_age = minf(_presentation_twitch_age + delta, memory)
	_presentation_pull_age = minf(_presentation_pull_age + delta, memory)

	if fight_mode or (state != State.SINKING and state != State.IN_WATER):
		_presentation_pause_seconds = 0.0
		return

	var player_working_lure: bool = (
		reeling
		or manual_pull_remaining > 0.001
		or manual_pull_current_speed > 0.02
		or twitch_velocity.length() > 0.03
		or twitch_target_velocity.length() > 0.03
	)

	if player_working_lure:
		_presentation_pause_seconds = 0.0
	else:
		_presentation_pause_seconds += delta


func get_presentation_snapshot() -> Dictionary:
	if data == null or data.get_action_profile() == null:
		return {
			"multiplier": 1.0,
			"quality": 0.5,
			"label": "GOOD",
			"retrieve_speed_ratio": 0.0,
			"pause_seconds": _presentation_pause_seconds,
			"twitch_recent": 0.0,
			"pull_recent": 0.0,
		}

	var continuous_speed: float = 0.0
	if reeling and not fight_mode:
		continuous_speed = (
			maxf(data.reel_speed, 0.0)
			* minf(maxf(free_reel_speed_multiplier, 0.0), maxf(free_reel_speed_cap, 0.0))
			* maxf(reel_speed_multiplier, 0.0)
		)

	var speed_ratio: float = continuous_speed / maxf(
		presentation_reference_retrieve_speed,
		0.01
	)

	return FishingLurePresentationPolicyScript.evaluate(
		data.get_action_profile().motion_style,
		speed_ratio,
		_presentation_pause_seconds,
		_presentation_twitch_age,
		_presentation_pull_age
	)


func get_presentation_attraction_multiplier() -> float:
	return float(get_presentation_snapshot().get("multiplier", 1.0))


func is_reeling_active() -> bool:
	return reeling


func get_lure_debug_snapshot() -> Dictionary:
	var snapshot: Dictionary = {
		"state": _get_state_debug_label(),
		"reeling": reeling,
		"fight_mode": fight_mode,
		"depth_m": maxf(water_y - global_position.y, 0.0),
		"total_depth_m": maxf(water_y - bottom_y, 0.0),
		"action_mode": "NONE",
		"action": "NONE",
		"steering": reel_steering,
		"steering_target": reel_steering_target,
		"landing_completion_blocked": landing_completion_blocked,
		"manual_pull_remaining": manual_pull_remaining,
	}

	if data != null:
		snapshot["lure"] = data.display_name
		snapshot["action"] = data.get_action_debug_summary()

	if lure_action_runtime != null:
		snapshot["action_mode"] = lure_action_runtime.get_mode_label()

	var presentation: Dictionary = get_presentation_snapshot()
	snapshot["presentation"] = presentation.get("label", "GOOD")
	snapshot["presentation_multiplier"] = presentation.get("multiplier", 1.0)
	snapshot["presentation_pause"] = presentation.get("pause_seconds", 0.0)

	return snapshot


func _get_state_debug_label() -> String:
	match state:
		State.IDLE:
			return "IDLE"
		State.FLYING:
			return "FLYING"
		State.SINKING:
			return "SINKING"
		State.IN_WATER:
			return "IN WATER"
		_:
			return "UNKNOWN"


func set_data(new_data: BaitData) -> void:
	data = new_data
	_configure_lure_action_runtime()

func set_simulation_frozen(active: bool) -> void:
	simulation_frozen = active
	
func _emit_depth() -> void:
	var current_depth := water_y - global_position.y
	var total_depth := water_y - bottom_y

	depth_changed.emit(current_depth, total_depth)

func _update_bottom_from_world() -> void:
	var ray_from := Vector3(
		global_position.x,
		water_y + 0.5,
		global_position.z
	)

	var ray_to := Vector3(
		global_position.x,
		water_y - floor_ray_depth,
		global_position.z
	)

	var query := PhysicsRayQueryParameters3D.create(
		ray_from,
		ray_to,
		floor_collision_mask
	)

	query.collide_with_areas = false
	query.collide_with_bodies = true

	var hit := get_world_3d().direct_space_state.intersect_ray(query)

	if hit.is_empty():
		return

	var hit_position: Vector3 = hit["position"]
	bottom_y = hit_position.y

	if global_position.y < bottom_y:
		global_position.y = bottom_y
		
func _get_fight_calm_factor() -> float:
	if not fight_mode:
		return 1.0

	var full_pull := clampf(
		convergence_full_pull_strength,
		0.0,
		1.0
	)

	var block_pull := clampf(
		convergence_block_pull_strength,
		full_pull + 0.01,
		1.0
	)

	if fish_pull_strength <= full_pull:
		return 1.0

	if fish_pull_strength >= block_pull:
		return 0.0

	var t := inverse_lerp(
		block_pull,
		full_pull,
		fish_pull_strength
	)

	# Smoothstep: active thrashing keeps freedom, then convergence fades in
	# naturally as the current pull dies down.
	return t * t * (3.0 - 2.0 * t)


func set_landing_completion_blocked(active: bool) -> void:
	landing_completion_blocked = active


func is_landing_completion_blocked() -> bool:
	return landing_completion_blocked


func can_complete_return(
	distance_to_player: float
) -> bool:
	return (
		distance_to_player
		<= maxf(
			return_distance,
			0.0
		)
	)


func get_effective_return_distance() -> float:
	var effective_distance := maxf(
		return_distance,
		0.0
	)

	if (
		shore_boundary == null
		or reel_target == null
		or not shore_boundary.has_method(
			"get_water_side_projection"
		)
	):
		return effective_distance

	var shore_point: Vector3 = (
		shore_boundary.get_water_side_projection(
			reel_target.global_position
		)
	)
	var target_flat := Vector2(
		reel_target.global_position.x,
		reel_target.global_position.z
	)
	var shore_flat := Vector2(
		shore_point.x,
		shore_point.z
	)

	# If a fishing spot places Ryu farther back from the actual waterline than
	# the normal 0.5 m landing radius, the shore itself becomes the reachable
	# landing point. The small epsilon prevents a fish from getting stuck on
	# floating-point noise while pressed against the blocker.
	return maxf(
		effective_distance,
		target_flat.distance_to(shore_flat) + 0.01
	)


func _can_complete_active_return(
	distance_to_player: float
) -> bool:
	if fight_mode and landing_completion_blocked:
		return false
	# Free retrieval uses the shore-safe destination, not the player's
	# inland radius. A large player-to-shore gap must never complete early.
	if not fight_mode:
		return distance_to_player <= maxf(free_retrieve_shore_finish_radius,0.05)
	return distance_to_player <= get_effective_return_distance()


func _constrain_waterborne_shore_position(
	proposed_position: Vector3
) -> Vector3:
	if (
		state != State.SINKING
		and state != State.IN_WATER
	):
		return proposed_position

	if (
		shore_boundary == null
		or not shore_boundary.has_method(
			"constrain_water_motion"
		)
	):
		return proposed_position

	return shore_boundary.constrain_water_motion(
		global_position,
		proposed_position
	)


func _enforce_shore_boundary() -> void:
	if (
		state != State.SINKING
		and state != State.IN_WATER
	):
		return

	var constrained_position := (
		_constrain_waterborne_shore_position(
			global_position
		)
	)

	global_position.x = constrained_position.x
	global_position.z = constrained_position.z


func _finish_return(
	target_position: Vector3
) -> void:
	if fight_mode:
		# The fish stays on the water side for the landing presentation. Do not
		# teleport it onto Ryu/dry land just because the return threshold fired.
		_enforce_shore_boundary()
	else:
		# No visual snap onto dry land, no second screen-dependent end point.
		# Both A and D terminate at the same water-side catch location.
		var safe_end: Vector3 = _free_lure_landing_point()
		global_position.x = safe_end.x
		global_position.z = safe_end.z

	reel_steering = 0.0
	reel_steering_target = 0.0
	fish_lateral = 0.0
	_reset_micro_movement()
	_reset_manual_pull_motion()
	reeling = false
	returned.emit()


func _get_reel_convergence(distance: float) -> float:
	var start_distance := maxf(
		convergence_start_distance,
		return_distance + 0.01
	)

	var full_distance := clampf(
		convergence_full_distance,
		return_distance,
		start_distance - 0.01
	)

	var distance_convergence := 0.0

	if distance <= full_distance:
		distance_convergence = 1.0
	elif distance < start_distance:
		var t := inverse_lerp(
			start_distance,
			full_distance,
			distance
		)

		distance_convergence = (
			t * t * (3.0 - 2.0 * t)
		)

	# The old pass used distance alone. Now distance only says how much
	# convergence is AVAILABLE; the fish's current pull decides how much is
	# actually allowed. A hard-thrashing fish therefore keeps full freedom
	# even very close to the player.
	return (
		distance_convergence
		* _get_fight_calm_factor()
	)


func set_fight_mode(active: bool) -> void:
	fight_mode = active
	_reset_manual_pull_motion()
	twitch_target_velocity = Vector3.ZERO
	_reset_micro_movement()
	lure_action_runtime.reset()

	if fight_mode:
		_choose_micro_target()
		if reel_target != null:
			var offset := global_position - reel_target.global_position
			offset.y = 0.0

			fight_max_distance = (
				offset.length()
				+ max_extra_fight_distance
			)

		if state == State.SINKING:
			state = State.IN_WATER
	else:
		fight_max_distance = 0.0

func _enforce_fight_distance() -> void:
	if not fight_mode:
		return

	if reel_target == null:
		return

	if fight_max_distance <= 0.0:
		return

	var offset := global_position - reel_target.global_position
	offset.y = 0.0

	var distance := offset.length()

	if distance <= fight_max_distance:
		return

	var clamped := (
		reel_target.global_position
		+ offset.normalized() * fight_max_distance
	)

	global_position.x = clamped.x
	global_position.z = clamped.z
	
func set_fight_resistance(value: float) -> void:
	fight_resistance = clampf(value, 0.0, 1.0)

func set_fish_pull_strength(value: float) -> void:
	fish_pull_strength = clampf(value, 0.0, 1.0)

func _reset_micro_movement() -> void:
	micro_lateral = 0.0
	micro_target_lateral = 0.0
	micro_time_until_change = 0.0


func _choose_micro_target() -> void:
	# A restrained random target gives the fish tiny corrections without
	# producing an obvious repeating sine-wave pattern.
	micro_target_lateral = randf_range(-1.0, 1.0)
	micro_time_until_change = randf_range(
		maxf(micro_change_time_min, 0.05),
		maxf(
			micro_change_time_max,
			micro_change_time_min + 0.05
		)
	)


func _update_micro_movement(delta: float) -> void:
	micro_time_until_change -= delta

	if micro_time_until_change <= 0.0:
		_choose_micro_target()

	# Frame-rate-independent smoothing. The target changes irregularly, but
	# the physical response glides toward it instead of snapping.
	var response := 1.0 - exp(
		-maxf(micro_response_speed, 0.0) * delta
	)

	micro_lateral = lerpf(
		micro_lateral,
		micro_target_lateral,
		response
	)


func _update_fish_pull(delta: float) -> void:
	if reel_target == null:
		return

	var away := global_position - reel_target.global_position
	away.y = 0.0

	var distance := away.length()

	if distance <= 0.0001:
		return

	var convergence := _get_reel_convergence(distance)
	var lateral_freedom := 1.0 - convergence

	away /= distance

	var side := Vector3.UP.cross(away).normalized()

	var has_lateral := absf(fish_lateral) > 0.05
	var has_vertical := absf(fish_depth_intent) > 0.05

	var horizontal_direction := Vector3.ZERO

	# No sideways or vertical intent = surge directly away.
	if not has_lateral and not has_vertical:
		horizontal_direction = away

	# Side run = move sideways instead of constantly escaping.
	elif has_lateral and not has_vertical:
		horizontal_direction = side * fish_lateral

	# Erratic movement = sideways + a small amount away.
	elif has_lateral and has_vertical:
		horizontal_direction = (
			side * fish_lateral
			+ away * 0.15
		).normalized()

	# Dive / rise intentionally has no primary horizontal movement.

	# Add only a small physical correction. Because the final movement is
	# already multiplied by fish_pull_strength below, exhausted/spent fish
	# naturally receive much less micro movement than resisting fish.
	var micro_side_amount := (
		micro_lateral
		* micro_lateral_strength
	)

	if absf(micro_side_amount) > 0.001:
		horizontal_direction += side * micro_side_amount

	if horizontal_direction.length_squared() > 0.0:
		var fish_step := (
			horizontal_direction.normalized()
			* max_fish_pull_speed
			* fish_pull_strength
			* lateral_freedom
			* delta
		)

		var proposed_position := global_position + fish_step

		if (
			swim_bounds != null
			and swim_bounds.has_method("constrain_fish_motion")
		):
			proposed_position = swim_bounds.constrain_fish_motion(
				global_position,
				proposed_position
			)

		global_position.x = proposed_position.x
		global_position.z = proposed_position.z

	global_position.y += (
		fish_depth_intent
		* fish_vertical_speed
		* fish_pull_strength
		* delta
	)

	global_position.y = clampf(
		global_position.y,
		bottom_y,
		water_y
	)

	_emit_depth()
			
func set_fish_lateral(value: float) -> void:
	fish_lateral = clampf(value, -1.0, 1.0)

func set_fish_depth_intent(value: float) -> void:
	fish_depth_intent = clampf(value, -1.0, 1.0)

func twitch_side(direction: float) -> void:
	if state != State.SINKING and state != State.IN_WATER:
		return

	if reel_target == null:
		return

	# Free-lure A/D remains exactly as before, including snag interaction.
	# During a fight the same input becomes a smaller physical side tug whose
	# visible response is reduced by fish resistance.
	if not fight_mode:
		_apply_snag_input_impulse(
			snag_twitch_impulse
		)

		if snag_triggered:
			return

		_presentation_twitch_age = 0.0
		# Free lure A/D is a continuous, screen-relative arc handled by
		# _update_reeling(). The old separate world-space key-down twitch
		# could make the FIRST press point away from that arc; the second
		# press then seemed to correct it. Keep snag and presentation signals,
		# but never layer an inconsistent physical impulse on a free lure.
		twitch_target_velocity = Vector3.ZERO
		twitch_velocity = Vector3.ZERO
		return

	var toward_player := reel_target.global_position - global_position
	toward_player.y = 0.0

	if toward_player.length_squared() == 0.0:
		return

	var forward := toward_player.normalized()
	var side := Vector3.UP.cross(forward).normalized()
	var twitch_multiplier := 1.0

	if fight_mode:
		twitch_multiplier = (
			maxf(fight_twitch_speed_multiplier, 0.0)
			* lerpf(
				1.0,
				clampf(
					fight_twitch_min_resistance_multiplier,
					0.0,
					1.0
				),
				clampf(fight_resistance, 0.0, 1.0)
			)
		)

	twitch_target_velocity = (
		side
		* clampf(direction, -1.0, 1.0)
		* twitch_speed
		* twitch_multiplier
		* rod_twitch_strength_multiplier
	)

func set_reel_speed_multiplier(value: float) -> void:
	reel_speed_multiplier = maxf(value, 0.0)

func show_ripple(opportunity_duration: float = 0.0) -> void:
	ripple_view.show_ripple(opportunity_duration)


func show_bite_splash() -> void:
	ripple_view.show_bite_splash()


func hide_ripple(preserve_committed_splash: bool = false) -> void:
	ripple_view.hide_ripple(preserve_committed_splash)
