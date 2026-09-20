extends Node

enum Phase {
	INACTIVE,
	ENTER,
	PREP,
	AIM,
	PREP_THROW,
	CHARGE,
	CANCEL_THROW,
	THROW,
	BAIT_FLYING,
	IN_WATER,
	FIGHT,
	CATCH,
	LINE_BROKEN,
	WAIT_RESULT,
	CATCH_DISMISS,
	RESULT_TRANSITION,
	PUT_AWAY,
	EXIT
}

@onready var aim: Node = $Aim
@onready var power: Node = $Power
@onready var caster: Node3D = $Caster
@onready var encounter: Node = $Encounter
@onready var throw_preview: Node3D = $ThrowPreview

@export var game_mode: Node
@export var camera_rig: Node
@export var sprite_director: Node
@export var player: CharacterBody3D
@export var power_meter_view: Node
@export var depth_meter_view: Node
@export var screen_transition: Node
@export var fishing_catch_view: Node
@export_category("Catch Result")
@export var catch_frame_delay: float = 0.5

var phase: int = Phase.INACTIVE
var bait_landed_during_throw: bool = false
var current_reel_animation: StringName = &""
var bite_opportunity_animation_active: bool = false
var bite_animation_active: bool = false
var current_fish_pull: float = 0.0
var fish_resisting: bool = false
var caught_fish: FishInstance = null

func _ready() -> void:
	game_mode.mode_changed.connect(_on_mode_changed)
	aim.aim_changed.connect(_on_aim_changed)
	caster.bait_landed.connect(_on_bait_landed)
	caster.bait_returned.connect(_on_bait_returned)
	encounter.fish_hooked.connect(_on_fish_hooked)
	encounter.fish_exhausted.connect(_on_fish_exhausted)
	encounter.bite_opportunity_started.connect(
		_on_bite_opportunity_started
	)

	encounter.bite_triggered.connect(_on_bite_triggered)
	encounter.bite_missed.connect(_on_bite_missed)
	encounter.fish_resistance_changed.connect(_on_fish_resistance_changed)
	encounter.fish_pull_changed.connect(_on_fish_pull_changed)
	encounter.fish_movement_changed.connect(_on_fish_movement_changed)
	encounter.fish_depth_intent_changed.connect(_on_fish_depth_intent_changed)
	encounter.hook_off.connect(_on_fight_failed)
	encounter.line_broken.connect(_on_line_broken)
	encounter.fish_caught.connect(_on_fish_caught)
	fishing_catch_view.shown.connect(_on_catch_view_shown)
	fishing_catch_view.dismissed.connect(_on_catch_view_dismissed)
	power.power_changed.connect(_on_power_changed)
	
	camera_rig.connect(
		"fishing_view_ready",
		Callable(self, "_on_fishing_view_ready")
	)

	camera_rig.connect(
		"exploration_view_ready",
		Callable(self, "_on_exploration_view_ready")
	)

	sprite_director.connect(
		"animation_finished",
		Callable(self, "_on_animation_finished")
	)

	_on_mode_changed(game_mode.current_mode)

	screen_transition.covered.connect(
		_on_result_screen_covered
	)

	screen_transition.revealed.connect(
		_on_result_screen_revealed
	)

func _unhandled_input(event: InputEvent) -> void:
	if not game_mode.is_fishing():
		return

	if phase == Phase.WAIT_RESULT:
		if event.is_action_pressed("enter_fishing"):
			if caught_fish != null:
				phase = Phase.CATCH_DISMISS
				fishing_catch_view.dismiss_catch()
			else:
				_begin_result_transition()

		return
		
	if phase == Phase.AIM:
		if event.is_action_pressed("enter_fishing"):
			phase = Phase.PREP_THROW
			power.start()
			sprite_director.play(&"Prep_Throw")
			return

		if event.is_action_pressed("cancel_fishing"):
			aim.stop()
			camera_rig.stop_fishing_aim()

			phase = Phase.PUT_AWAY
			sprite_director.play_backwards(&"Prep_Fishing")
			return
	
	if phase == Phase.PREP_THROW or phase == Phase.CHARGE:
		if event.is_action_pressed("cancel_fishing"):
			throw_preview.hide_preview()
			if (
				power_meter_view != null
				and power_meter_view.has_method("cancel_to_aim")
			):
				power_meter_view.cancel_to_aim()

			# Stop the power mechanic. The HUD has already been told
			# that this stop is a cancel, not a confirmed cast.
			power.capture()

			phase = Phase.CANCEL_THROW
			sprite_director.play_backwards(&"Prep_Throw")
			return
			
	if phase == Phase.CHARGE:
		if event.is_action_pressed("enter_fishing"):
			aim.stop()
			throw_preview.hide_preview()
			
			var captured_power: float = power.capture()

			var zone = game_mode.active_fish_zone

			if zone != null:
				var cast_direction: Vector3 = aim.get_direction()

				var cast_bait: Node3D = caster.perform_cast(
					captured_power,
					cast_direction,
					zone.get_water_y(),
					zone.get_bottom_y()
				)

				if is_instance_valid(cast_bait):
					camera_rig.arm_fishing_follow(
						cast_bait,
						cast_direction,
						zone.get_water_y()
					)


			bait_landed_during_throw = false
			phase = Phase.THROW
			sprite_director.play(&"Throw")
			return


	if phase == Phase.IN_WATER:
		if event.is_action_pressed("ds_left"):
			caster.twitch_bait(-1.0)
			encounter.add_lure_tension(0.05)
			return

		if event.is_action_pressed("ds_right"):
			caster.twitch_bait(1.0)
			encounter.add_lure_tension(0.05)
			return

		if event.is_action_pressed("enter_fishing"):
			if encounter.try_hook():
				return

			encounter.set_player_reeling(true)
			caster.set_reeling(true)
			current_reel_animation = &""
			_update_reel_animation()
			return

		if event.is_action_released("enter_fishing"):
			encounter.set_player_reeling(false)
			caster.set_reeling(false)
			current_reel_animation = &""
			_update_reel_animation()
			return
	
	if event.is_action_pressed("move_back"):
		if not bite_animation_active:
			bite_animation_active = true
			current_reel_animation = &""
			sprite_director.play(&"Reel_Bite")
		return

	if event.is_action_pressed("enter_fishing"):
		_set_fight_reeling(true)
		return

	if event.is_action_released("enter_fishing"):
		_set_fight_reeling(false)
		return

func _set_fight_reeling(active: bool) -> void:
	encounter.set_player_reeling(active)
	caster.set_reeling(active)

	current_reel_animation = &""
	_update_reel_animation()
		
func _on_mode_changed(new_mode) -> void:
	var active: bool = new_mode == game_mode.Mode.FISHING

	set_process_unhandled_input(active)

	if not active:
		return

	phase = Phase.ENTER

	var zone = game_mode.active_fish_zone

	if zone != null:
		encounter.set_fish_population(
			zone.get_fish_population()
		)

		camera_rig.enter_fishing_view()


func _on_fishing_view_ready() -> void:
	if phase != Phase.ENTER:
		return

	phase = Phase.PREP
	sprite_director.play(&"Prep_Fishing")

func _update_reel_animation() -> void:
	# Bite-window pose owns the animation until HIT or MISS resolves.
	if bite_opportunity_animation_active:
		return

	# Reel_Bite_Strong is a one-shot confirmed-HIT reaction.
	if bite_animation_active:
		return

	var is_reeling := Input.is_action_pressed("enter_fishing")
	var horizontal := Input.get_axis("ds_left", "ds_right")
	var vertical := Input.get_axis("move_forward", "move_back")
	var desired_animation: StringName

	# STEP 2 PRIORITY:
	# 1. Left/right steering animation.
	# 2. Forward/back input while actively reeling.
	# 3. Otherwise use the base fight/water rules from Step 1.

	# A / D steering.
	if horizontal < -0.1:
		desired_animation = (
			&"Reel_Left"
			if is_reeling
			else &"Reel_Left_Idle"
		)

	elif horizontal > 0.1:
		desired_animation = (
			&"Reel_Right"
			if is_reeling
			else &"Reel_Right_Idle"
		)

	# W / S only override the pose while K is held.
	elif is_reeling and vertical < -0.1:
		desired_animation = &"Reel_Front"

	elif is_reeling and vertical > 0.1:
		desired_animation = &"Reel_Back"

	# No directional override: use the Step 1 fishing rules.
	elif phase == Phase.FIGHT:
		if fish_resisting:
			if is_reeling:
				desired_animation = &"Reel_Back_Strong"
			else:
				desired_animation = &"Reel_Front"
		else:
			if is_reeling:
				desired_animation = &"Reel_Back"
			else:
				desired_animation = &"Reel_Idle"

	elif phase == Phase.IN_WATER:
		if is_reeling:
			desired_animation = &"Reel"
		else:
			desired_animation = &"Reel_Idle"

	elif phase == Phase.IN_WATER:
		if is_reeling:
			# No hooked fish: normal lure retrieval.
			desired_animation = &"Reel"
		else:
			# Default water pose for now, including after MISS.
			desired_animation = &"Reel_Back"

	else:
		return

	if desired_animation == current_reel_animation:
		return

	current_reel_animation = desired_animation
	sprite_director.play(desired_animation)
	
func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name == &"Prep_Fishing":
		if phase == Phase.PREP:
			phase = Phase.AIM
			sprite_director.play(&"Fishing_Idle")

			var fishing_forward := player.global_transform.basis.z
			fishing_forward.y = 0.0
			fishing_forward = fishing_forward.normalized()

			camera_rig.start_fishing_aim(fishing_forward)
			aim.start(fishing_forward)

			return

		if phase == Phase.PUT_AWAY:
			player.restore_exploration_idle()

			phase = Phase.EXIT
			camera_rig.exit_fishing_view()
			return


	if animation_name == &"Prep_Throw":
		if phase == Phase.PREP_THROW:
			phase = Phase.CHARGE
			sprite_director.play(&"Prep_Throw_Idle")
			return

		if phase == Phase.CANCEL_THROW:
			phase = Phase.AIM
			sprite_director.play(&"Fishing_Idle")
			aim.resume()
			return

	if animation_name == &"Throw" and phase == Phase.THROW:
		if bait_landed_during_throw:
			_enter_in_water()
		else:
			phase = Phase.BAIT_FLYING
			sprite_director.play(&"Throw_Idle")

		return
	
	if animation_name == &"Fishing_Catch" and phase == Phase.CATCH:
		await get_tree().create_timer(catch_frame_delay).timeout

		if phase != Phase.CATCH:
			return

		if caught_fish != null:
			fishing_catch_view.show_catch(caught_fish)

		return
	
	if animation_name == &"Reel_Broken_Rod" and phase == Phase.LINE_BROKEN:
		phase = Phase.WAIT_RESULT
		return
	
	if (
		(animation_name == &"Reel_Bite_Strong"
		or animation_name == &"Reel_Bite")
		and bite_animation_active
	):
		bite_animation_active = false
		current_reel_animation = &""

		_update_reel_animation()
		return
	
func _on_catch_view_shown() -> void:
	if phase != Phase.CATCH:
		return

	phase = Phase.WAIT_RESULT
	
func _on_exploration_view_ready() -> void:
	if phase != Phase.EXIT:
		return

	phase = Phase.INACTIVE
	game_mode.exit_fishing()

func _on_aim_changed(direction: Vector3) -> void:
	camera_rig.set_fishing_aim_direction(direction)

func _on_bait_landed(_point: Vector3) -> void:
	if phase == Phase.THROW:
		bait_landed_during_throw = true
		return

	if phase == Phase.BAIT_FLYING:
		_enter_in_water()
		
func _enter_in_water() -> void:
	phase = Phase.IN_WATER
	current_reel_animation = &"Reel_Idle"
	sprite_director.play(&"Reel_Idle")

func _on_bait_returned() -> void:
	if phase != Phase.IN_WATER and phase != Phase.FIGHT:
		return

	if phase == Phase.FIGHT:
		encounter.catch_fish()

		phase = Phase.CATCH
		sprite_director.play(&"Fishing_Catch")
		return
	
	camera_rig.reset_fishing_follow()

	phase = Phase.AIM
	sprite_director.play(&"Fishing_Idle")
	aim.resume()
	
func _process(_delta: float) -> void:
	if phase == Phase.THROW or phase == Phase.BAIT_FLYING:
		var air_curve := Input.get_axis(
			"ds_left",
			"ds_right"
		)

		caster.set_air_curve(air_curve)
		return
		
	if phase != Phase.IN_WATER and phase != Phase.FIGHT:
		return
	
	if phase == Phase.FIGHT:
		if Input.is_action_just_pressed("move_back"):
			if not bite_animation_active:
				bite_animation_active = true
				current_reel_animation = &""
				sprite_director.play(&"Reel_Bite")
			
	var steering := Input.get_axis("ds_left", "ds_right")
	var vertical := Input.get_axis(
		"move_forward",
		"move_back"
	)

	encounter.set_player_tension_bias(vertical)
	caster.set_reel_steering(steering)
	
	if phase == Phase.FIGHT:
		var is_reeling := Input.is_action_pressed("enter_fishing")

		# Continuous fight input.
		# Do not rely only on key press/release events for the mechanic.
		encounter.set_player_reeling(is_reeling)
		caster.set_reeling(is_reeling)

		encounter.set_player_steering(steering)

	if phase == Phase.IN_WATER or phase == Phase.FIGHT:
		_update_reel_animation()
	
func _on_fish_hooked() -> void:
	if phase != Phase.IN_WATER:
		return

	phase = Phase.FIGHT
	fish_resisting = true
	caster.set_fight_mode(true)

	var is_reeling := Input.is_action_pressed("enter_fishing")

	encounter.set_player_reeling(is_reeling)
	caster.set_reeling(is_reeling)

	# If the HIT reaction is still playing, it finishes first.
	# Otherwise immediately resolve to Reel_Front / Reel_Back_Strong.
	if not bite_animation_active:
		current_reel_animation = &""
		_update_reel_animation()

func _on_fish_exhausted() -> void:
	if phase != Phase.FIGHT:
		return

	fish_resisting = false
	current_reel_animation = &""
	_update_reel_animation()

func _on_fish_caught(fish: FishInstance) -> void:
	caught_fish = fish
	
func _on_bite_triggered() -> void:
	if phase != Phase.IN_WATER:
		return

	caster.hide_bait_ripple()

	bite_opportunity_animation_active = false
	bite_animation_active = true
	current_reel_animation = &""

	sprite_director.play(&"Reel_Bite_Strong")

func _on_bite_opportunity_started() -> void:
	if phase != Phase.IN_WATER:
		return

	bite_opportunity_animation_active = true

	caster.show_bait_ripple()
	sprite_director.play(&"Reel_Front")
	
func _on_bite_missed() -> void:
	if phase != Phase.IN_WATER:
		return

	caster.hide_bait_ripple()

	bite_opportunity_animation_active = false
	current_reel_animation = &""

	_update_reel_animation()

func _on_fish_resistance_changed(value: float) -> void:
	if phase != Phase.FIGHT:
		return

	caster.set_fight_resistance(value)

	var was_resisting := fish_resisting
	fish_resisting = value > 0.01

	if fish_resisting != was_resisting:
		current_reel_animation = &""
		_update_reel_animation()

func _on_fish_pull_changed(value: float) -> void:
	if phase != Phase.FIGHT:
		return

	current_fish_pull = value
	caster.set_fish_pull_strength(value)

func _on_fish_movement_changed(lateral: float) -> void:
	if phase != Phase.FIGHT:
		return

	caster.set_fish_lateral(lateral)

func _on_fish_depth_intent_changed(value: float) -> void:
	if phase != Phase.FIGHT:
		return

	caster.set_fish_depth_intent(value)

func _on_line_broken() -> void:
	if phase != Phase.FIGHT:
		return

	_freeze_failed_fight()

	current_fish_pull = 0.0
	current_reel_animation = &""
	fish_resisting = false
	bite_opportunity_animation_active = false
	bite_animation_active = false

	phase = Phase.LINE_BROKEN
	sprite_director.play(&"Reel_Broken_Rod")

func _freeze_failed_fight() -> void:
	caster.set_reeling(false)
	caster.set_bait_frozen(true)
	camera_rig.set_fishing_camera_frozen(true)
	
func _on_fight_failed() -> void:
	if phase != Phase.FIGHT:
		return

	_freeze_failed_fight()

	current_fish_pull = 0.0
	current_reel_animation = &""
	fish_resisting = false
	bite_opportunity_animation_active = false
	bite_animation_active = false

	phase = Phase.LINE_BROKEN
	sprite_director.play(&"Reel_Broken_Rod")

func _begin_result_transition() -> void:
	if phase != Phase.WAIT_RESULT:
		return

	phase = Phase.RESULT_TRANSITION
	screen_transition.fade_to_black()


func _on_result_screen_covered() -> void:
	if phase != Phase.RESULT_TRANSITION:
		return

	# We are completely black now.
	# Everything ugly happens here where the player cannot see it.

	caster.set_reeling(false)
	caster.cancel_bait()

	camera_rig.set_fishing_camera_frozen(false)
	camera_rig.reset_fishing_follow()

	power_meter_view.reset_to_aim()
	depth_meter_view.reset_to_aim()
	
	fishing_catch_view.hide_catch()
	caught_fish = null

	current_fish_pull = 0.0
	current_reel_animation = &""
	fish_resisting = false
	bite_opportunity_animation_active = false
	bite_animation_active = false

	sprite_director.play(&"Fishing_Idle")

	screen_transition.fade_from_black()

func _on_catch_view_dismissed() -> void:
	if phase != Phase.CATCH_DISMISS:
		return

	caster.set_reeling(false)
	caster.cancel_bait()

	camera_rig.set_fishing_camera_frozen(false)
	camera_rig.reset_fishing_follow()

	power_meter_view.reset_to_aim()
	depth_meter_view.reset_to_aim()

	current_fish_pull = 0.0
	current_reel_animation = &""
	fish_resisting = false
	bite_opportunity_animation_active = false
	bite_animation_active = false

	caught_fish = null

	sprite_director.play(&"Fishing_Idle")

	phase = Phase.AIM
	aim.resume()
	
func _on_result_screen_revealed() -> void:
	if phase != Phase.RESULT_TRANSITION:
		return

	phase = Phase.AIM
	aim.resume()

func _on_power_changed(value: float) -> void:
	if phase != Phase.PREP_THROW and phase != Phase.CHARGE:
		return

	var zone = game_mode.active_fish_zone

	if zone == null:
		throw_preview.hide_preview()
		return

	var points: PackedVector3Array = caster.predict_cast(
		value,
		aim.get_direction(),
		zone.get_water_y()
	)

	throw_preview.show_preview(points)
