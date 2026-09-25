extends Node

const FishingDebugSettingsScript = preload(
	"res://scripts/fishing_debug_settings.gd"
)
const FishingDebugMenuScene = preload(
	"res://actors/FishingDebugMenu.tscn"
)

const FishingTechniqueDetectorScript = preload(
	"res://scripts/fishing_technique_detector.gd"
)
const FishingTechniqueViewScene = preload(
	"res://actors/FishingTechniqueView.tscn"
)

const FishingProgressScript = preload(
	"res://scripts/fishing_progress.gd"
)
const FishingInventoryScript = preload(
	"res://scripts/fishing_inventory.gd"
)
const FishingTradeServiceScript = preload(
	"res://scripts/fishing_trade_service.gd"
)
const FishingTackleCatalogResource = preload(
	"res://data/bof4/tackle/all_tackle.tres"
)
const FishingTradeCatalogResource = preload(
	"res://data/bof4/trades/all_trades.tres"
)
const FishingUnlockStateScript = preload(
	"res://scripts/fishing_unlock_state.gd"
)
const FishingRewardServiceScript = preload(
	"res://scripts/fishing_reward_service.gd"
)
const FishingRewardCatalogResource = preload(
	"res://data/bof4/rewards/all_rewards.tres"
)
const FishingJournalServiceScript = preload(
	"res://scripts/fishing_journal_service.gd"
)
const FishingJournalCatalogResource = preload(
	"res://data/bof4/journal/all_journal_data.tres"
)
const FishingSurfaceSplashScene = preload(
	"res://actors/FishingSurfaceSplash.tscn"
)

enum Phase {
	INACTIVE,
	ENTER,
	PREP,
	AIM,
	PREP_THROW,
	CHARGE,
	CURVE,
	CANCEL_THROW,
	THROW,
	BAIT_FLYING,
	IN_WATER,
	FIGHT,
	LANDING,
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
@export var loadout: FishingLoadout
@export var lure_selector_view: Node
@export_category("Catch Result")
@export var catch_frame_delay: float = 0.5

@export_category("Catch Landing")
## Short presentation bridge after the fish has genuinely reached Ryu. Fight
## mechanics are already over here; this only gives the final splash/shadow a
## readable beat before the existing Fishing_Catch animation/result view.
@export_range(0.05, 1.0, 0.05)
var catch_landing_hold_time: float = 0.32
@export_range(0.1, 2.0, 0.05)
var catch_landing_splash_strength: float = 0.90

@export_category("Surface Splash Presentation")
## Placeholder strengths only. The event timing stays valid when the final
## BOF4 splash sprites replace the procedural placeholder.
@export_range(0.1, 2.0, 0.05)
var landing_splash_strength: float = 0.66
@export_range(0.1, 2.0, 0.05)
var fight_thrash_splash_strength: float = 0.82
@export_range(0.05, 1.5, 0.05)
var fight_thrash_splash_cooldown: float = 0.35

@export_category("Pre-Cast Curve")
## Seconds of held A/D needed to move from straight to maximum curve.
@export var curve_adjust_speed: float = 1.25
## Preview-only smoothing so the torus and arc glide instead of updating in visible increments.
@export_range(1.0, 30.0, 0.5)
var curve_preview_smoothing_speed: float = 7.0

var phase: int = Phase.INACTIVE
var bait_landed_during_throw: bool = false
var current_reel_animation: StringName = &""
var bite_opportunity_animation_active: bool = false
var bite_animation_active: bool = false
var manual_pull_animation_active: bool = false
var fish_resisting: bool = false
var caught_fish: FishInstance = null
var lure_selector_open: bool = false
var debug_settings = null
var debug_menu: Node = null
var debug_menu_open: bool = false
var technique_detector: FishingTechniqueDetector = null
var technique_view: FishingTechniqueView = null
var fishing_progress: FishingProgress = null
var fishing_inventory: FishingInventory = null
var fishing_trade_service: FishingTradeService = null
var fishing_unlock_state: FishingUnlockState = null
var fishing_reward_service: FishingRewardService = null
var fishing_journal_service: FishingJournalService = null
var catch_record_result: Dictionary = {}
var last_lure_loss_result: Dictionary = {}

var locked_cast_power: float = 0.0
# Player input / desired curve amount.
var cast_curve_value: float = 0.0
# Smoothed preview curve used by the visible arc + torus and by the actual throw.
var preview_cast_curve_value: float = 0.0

# Casting uses press -> release -> press semantics. One physical K press can
# never advance more than one cast stage, even if the key is held or repeats.
var cast_confirm_ready: bool = true
var cast_power_locked: bool = false
var _quick_cast_cancel_active: bool = false
var _fight_splash_cooldown_left: float = 0.0

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
	encounter.fish_thrash_started.connect(_on_fish_thrash_started)
	encounter.fish_resistance_started.connect(_on_fish_resistance_started_splash)
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

	debug_settings = FishingDebugSettingsScript.new()
	encounter.set_debug_settings(debug_settings)

	fishing_progress = _get_or_create_fishing_progress()
	fishing_inventory = _get_or_create_fishing_inventory()
	fishing_inventory.bind_progress(fishing_progress)

	if loadout != null:
		loadout.set_inventory(fishing_inventory)

	fishing_trade_service = _get_or_create_fishing_trade_service(
		fishing_inventory
	)
	fishing_unlock_state = _get_or_create_fishing_unlock_state()
	fishing_reward_service = _get_or_create_fishing_reward_service(
		fishing_progress,
		fishing_inventory,
		fishing_unlock_state
	)
	fishing_journal_service = _get_or_create_fishing_journal_service(
		fishing_progress,
		fishing_inventory
	)

	debug_menu = FishingDebugMenuScene.instantiate()
	add_child(debug_menu)
	debug_menu.configure(
		loadout,
		debug_settings,
		fishing_progress
	)
	debug_menu.connect(
		"spot_requested",
		Callable(self, "_on_debug_spot_requested")
	)
	debug_menu.connect(
		"debug_environment_changed",
		Callable(self, "_sync_debug_environment")
	)

	technique_detector = FishingTechniqueDetectorScript.new()
	add_child(technique_detector)
	technique_detector.technique_triggered.connect(
		_on_technique_triggered
	)

	technique_view = FishingTechniqueViewScene.instantiate()
	add_child(technique_view)

	if loadout != null:
		if not loadout.rod_changed.is_connected(_on_rod_changed):
			loadout.rod_changed.connect(_on_rod_changed)

		_on_rod_changed(loadout.get_selected_rod())

func _unhandled_input(event: InputEvent) -> void:
	if not game_mode.is_fishing():
		return

	if _is_debug_toggle(event):
		if debug_menu_open:
			_close_debug_menu(true)
		elif phase == Phase.AIM and not lure_selector_open:
			_open_debug_menu()

		get_viewport().set_input_as_handled()
		return

	if debug_menu_open:
		var close_requested: bool = (
			debug_menu.handle_input(event)
		)

		if close_requested:
			_close_debug_menu(true)

		# Debug overlay owns input completely while open.
		get_viewport().set_input_as_handled()
		return

	if lure_selector_open:
		if (
			event.is_action_pressed("ds_left")
			or event.is_action_pressed("ui_left")
		):
			lure_selector_view.move_selection(-1)
			get_viewport().set_input_as_handled()
			return

		if (
			event.is_action_pressed("ds_right")
			or event.is_action_pressed("ui_right")
		):
			lure_selector_view.move_selection(1)
			get_viewport().set_input_as_handled()
			return

		if event.is_action_pressed("enter_fishing"):
			var preview_lure: BaitData = (
				lure_selector_view.get_preview_lure()
			)

			if preview_lure != null and loadout != null:
				loadout.equip_lure(preview_lure)

			_close_lure_selector(true)
			get_viewport().set_input_as_handled()
			return

		if (
			event.is_action_pressed("cancel_fishing")
			or event.is_action_pressed("lure_menu")
		):
			_close_lure_selector(true)
			get_viewport().set_input_as_handled()
			return

		# While the selector owns input, nothing beneath it should react.
		get_viewport().set_input_as_handled()
		return

	# Re-arm cast confirmation only after K has genuinely been released.
	# This prevents a held key or OS key-repeat from leaking into the next
	# cast stage.
	if (
		_is_cast_input_phase()
		and event.is_action_released("enter_fishing")
	):
		cast_confirm_ready = true

	# During the Prep_Throw transition, a premature K press is deliberately
	# swallowed. It must be released before CHARGE can accept another press.
	if (
		phase == Phase.PREP_THROW
		and event.is_action_pressed("enter_fishing")
	):
		if not _is_key_echo(event):
			cast_confirm_ready = false
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
		if event.is_action_pressed("lure_menu"):
			_open_lure_selector()
			return

		if _try_consume_cast_confirm(event):
			locked_cast_power = 0.0
			cast_curve_value = 0.0
			preview_cast_curve_value = 0.0
			cast_power_locked = false

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
	
	if (
		phase == Phase.PREP_THROW
		or phase == Phase.CHARGE
		or phase == Phase.CURVE
	):
		if event.is_action_pressed("cancel_fishing"):
			throw_preview.hide_preview()

			if (
				power_meter_view != null
				and power_meter_view.has_method("cancel_to_aim")
			):
				power_meter_view.cancel_to_aim()

			# Stop the power mechanic. The HUD has already been told
			# that this stop is a cancel, not a confirmed cast.
			power.stop()

			locked_cast_power = 0.0
			cast_curve_value = 0.0
			preview_cast_curve_value = 0.0
			cast_power_locked = false
			cast_confirm_ready = not Input.is_action_pressed(
				"enter_fishing"
			)

			phase = Phase.CANCEL_THROW
			sprite_director.play_backwards(&"Prep_Throw")
			return
			
	if phase == Phase.CHARGE:
		if _try_consume_cast_confirm(event):
			# POWER LOCK:
			# Freeze distance, base heading, and the landing torus.
			# A/D bends only the middle of the trajectory.
			locked_cast_power = power.lock_value()
			cast_power_locked = true
			cast_curve_value = 0.0
			preview_cast_curve_value = 0.0
			aim.stop()

			phase = Phase.CURVE
			_update_cast_preview(
				locked_cast_power,
				preview_cast_curve_value
			)
			return

	if phase == Phase.CURVE:
		if _try_consume_cast_confirm(event):
			_commit_curved_cast()
			return


	if phase == Phase.IN_WATER:
		# BOF4-style quick abandon: while the lure is simply waiting in the
		# water, I immediately discards the cast and returns to AIM. Do not
		# allow this to bypass an active bite opportunity.
		if (
			event.is_action_pressed("cancel_fishing")
			and not bite_opportunity_animation_active
			and not bite_animation_active
		):
			_cancel_water_cast_to_aim()
			get_viewport().set_input_as_handled()
			return

		# S is a discrete rod pull even before a fish bites. It plays the same
		# one-shot pull reaction used during a fight and queues a short lure
		# movement toward Ryu. K remains the smooth continuous retrieve.
		if (
			event.is_action_pressed("move_back")
			and not _is_key_echo(event)
			and not bite_opportunity_animation_active
			and not bite_animation_active
		):
			caster.pull_bait_toward_player()
			_play_manual_pull_animation()
			get_viewport().set_input_as_handled()
			return

		if event.is_action_pressed("ds_left"):
			technique_detector.record_pulse()
			caster.twitch_bait(-1.0)
			encounter.add_lure_tension(0.05)
			return

		if event.is_action_pressed("ds_right"):
			technique_detector.record_pulse()
			caster.twitch_bait(1.0)
			encounter.add_lure_tension(0.05)
			return

		if event.is_action_pressed("enter_fishing"):
			if encounter.try_hook():
				technique_detector.reset()
				return

			technique_detector.record_pulse()
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
	
func _on_mode_changed(new_mode) -> void:
	var active: bool = new_mode == game_mode.Mode.FISHING

	set_process_unhandled_input(active)

	if not active:
		cast_confirm_ready = true
		cast_power_locked = false
		locked_cast_power = 0.0
		cast_curve_value = 0.0
		preview_cast_curve_value = 0.0

		_close_lure_selector(false)
		_close_debug_menu(false)

		if technique_detector != null:
			technique_detector.reset()

		if technique_view != null:
			technique_view.clear()

		return

	cast_confirm_ready = not Input.is_action_pressed(
		"enter_fishing"
	)
	cast_power_locked = false
	locked_cast_power = 0.0
	cast_curve_value = 0.0
	preview_cast_curve_value = 0.0

	phase = Phase.ENTER

	var zone = game_mode.active_fish_zone

	if zone != null:
		encounter.set_fish_population(
			zone.get_fish_population()
		)

		if debug_menu != null:
			debug_menu.set_fish_zone(zone)

		_sync_debug_environment()
		camera_rig.enter_fishing_view()







func get_fishing_progress() -> FishingProgress:
	return fishing_progress


func get_fishing_inventory() -> FishingInventory:
	return fishing_inventory


func get_last_lure_loss_result() -> Dictionary:
	return last_lure_loss_result.duplicate(true)


func get_fishing_trade_service() -> FishingTradeService:
	return fishing_trade_service


func get_fishing_unlock_state() -> FishingUnlockState:
	return fishing_unlock_state


func get_fishing_reward_service() -> FishingRewardService:
	return fishing_reward_service


func get_fishing_journal_service() -> FishingJournalService:
	return fishing_journal_service


func _get_or_create_fishing_progress() -> FishingProgress:
	var tree_root := get_tree().root
	var existing := tree_root.get_node_or_null(
		"FishingProgress"
	)

	if existing is FishingProgress:
		var existing_progress := existing as FishingProgress
		existing_progress.initialize()
		return existing_progress

	var new_progress := FishingProgressScript.new()
	new_progress.name = "FishingProgress"

	# Fishing._ready() can run while SceneTree root is still setting up
	# its children. Adding another root child immediately at that moment
	# is rejected by Godot, so defer only the tree attachment.
	#
	# The object itself is valid immediately, so we can initialize and use
	# it now; FishingProgress.initialize() is idempotent when _ready()
	# later fires after the deferred add.
	tree_root.add_child.call_deferred(new_progress)
	new_progress.initialize()
	return new_progress


func _get_or_create_fishing_inventory() -> FishingInventory:
	var tree_root := get_tree().root
	var existing := tree_root.get_node_or_null("FishingInventory")

	if existing is FishingInventory:
		var existing_inventory := existing as FishingInventory
		existing_inventory.initialize()
		return existing_inventory

	var new_inventory := FishingInventoryScript.new()
	new_inventory.name = "FishingInventory"
	tree_root.add_child.call_deferred(new_inventory)
	new_inventory.initialize()
	return new_inventory


func _get_or_create_fishing_trade_service(
	inventory: FishingInventory
) -> FishingTradeService:
	var tree_root := get_tree().root
	var existing := tree_root.get_node_or_null("FishingTradeService")

	if existing is FishingTradeService:
		var existing_service := existing as FishingTradeService
		existing_service.configure(
			inventory,
			FishingTackleCatalogResource,
			FishingTradeCatalogResource
		)
		return existing_service

	var new_service := FishingTradeServiceScript.new()
	new_service.name = "FishingTradeService"
	new_service.configure(
		inventory,
		FishingTackleCatalogResource,
		FishingTradeCatalogResource
	)
	tree_root.add_child.call_deferred(new_service)
	return new_service


func _get_or_create_fishing_unlock_state() -> FishingUnlockState:
	var tree_root := get_tree().root
	var existing := tree_root.get_node_or_null("FishingUnlockState")

	if existing is FishingUnlockState:
		var existing_state := existing as FishingUnlockState
		existing_state.initialize()
		return existing_state

	var new_state := FishingUnlockStateScript.new()
	new_state.name = "FishingUnlockState"
	tree_root.add_child.call_deferred(new_state)
	new_state.initialize()
	return new_state


func _get_or_create_fishing_reward_service(
	progress: FishingProgress,
	inventory: FishingInventory,
	unlock_state: FishingUnlockState
) -> FishingRewardService:
	var tree_root := get_tree().root
	var existing := tree_root.get_node_or_null("FishingRewardService")

	if existing is FishingRewardService:
		var existing_service := existing as FishingRewardService
		existing_service.configure(
			progress,
			inventory,
			FishingTackleCatalogResource,
			unlock_state,
			FishingRewardCatalogResource
		)
		return existing_service

	var new_service := FishingRewardServiceScript.new()
	new_service.name = "FishingRewardService"
	new_service.configure(
		progress,
		inventory,
		FishingTackleCatalogResource,
		unlock_state,
		FishingRewardCatalogResource
	)
	tree_root.add_child.call_deferred(new_service)
	return new_service


func _get_or_create_fishing_journal_service(
	progress: FishingProgress,
	inventory: FishingInventory
) -> FishingJournalService:
	var tree_root := get_tree().root
	var existing := tree_root.get_node_or_null("FishingJournalService")

	if existing is FishingJournalService:
		var existing_service := existing as FishingJournalService
		existing_service.configure(
			progress,
			inventory,
			FishingJournalCatalogResource
		)
		return existing_service

	var new_service := FishingJournalServiceScript.new()
	new_service.name = "FishingJournalService"
	new_service.configure(
		progress,
		inventory,
		FishingJournalCatalogResource
	)
	tree_root.add_child.call_deferred(new_service)
	return new_service


func _on_technique_triggered(level: int) -> void:
	if phase != Phase.IN_WATER:
		return

	encounter.apply_technique(level)
	technique_view.show_tech(level, caster.active_bait)


func _on_rod_changed(rod: RodData) -> void:
	caster.set_rod_data(rod)
	encounter.set_rod_data(rod)


func _is_cast_input_phase() -> bool:
	# AIM must be included here because entering fishing can happen while
	# the same K button is still held. Its release must re-arm the first
	# cast confirmation.
	return (
		phase == Phase.AIM
		or phase == Phase.PREP_THROW
		or phase == Phase.CHARGE
		or phase == Phase.CURVE
	)


func _is_key_echo(event: InputEvent) -> bool:
	return (
		event is InputEventKey
		and (event as InputEventKey).echo
	)


func _try_consume_cast_confirm(event: InputEvent) -> bool:
	if not event.is_action_pressed("enter_fishing"):
		return false

	# Keyboard repeat must never count as a new cast confirmation.
	if _is_key_echo(event):
		return false

	# Every accepted press disarms the next stage until K is released.
	if not cast_confirm_ready:
		return false

	cast_confirm_ready = false
	return true


func _is_debug_toggle(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false

	if not event.pressed or event.echo:
		return false

	return (
		event.keycode == KEY_F10
		or event.physical_keycode == KEY_F10
	)


func _on_debug_spot_requested(spot: FishingSpotData) -> void:
	var zone = game_mode.active_fish_zone
	if zone == null or spot == null:
		return

	if zone.has_method("set_fishing_spot"):
		zone.set_fishing_spot(spot)
	else:
		zone.set("fishing_spot", spot)

	encounter.set_fish_population(zone.get_fish_population())


func _sync_debug_environment() -> void:
	var zone = game_mode.active_fish_zone
	if zone == null:
		return

	encounter.set_fish_population(zone.get_fish_population())

	if debug_settings == null:
		return

	# Apply the two shadow QA controls together so changing a profile rebuilds
	# the ambient population once, not once for species and again for count.
	if zone.has_method("set_debug_shadow_overrides"):
		zone.set_debug_shadow_overrides(
			debug_settings.get_shadow_fish_override(),
			debug_settings.get_shadow_count_override()
		)
		return

	# Compatibility fallback for any older FishZone scene.
	if zone.has_method("set_debug_shadow_fish"):
		zone.set_debug_shadow_fish(debug_settings.get_shadow_fish_override())
	if zone.has_method("set_debug_shadow_count"):
		zone.set_debug_shadow_count(debug_settings.get_shadow_count_override())


func _open_debug_menu() -> void:
	if (
		debug_menu == null
		or phase != Phase.AIM
		or lure_selector_open
	):
		return

	debug_menu.set_fish_zone(game_mode.active_fish_zone)

	if not debug_menu.open_menu():
		return

	debug_menu_open = true
	aim.stop()


func _close_debug_menu(resume_aim: bool) -> void:
	if debug_menu != null:
		debug_menu.close_menu()

	var was_open := debug_menu_open
	debug_menu_open = false

	if was_open and resume_aim and phase == Phase.AIM:
		aim.resume()


func _open_lure_selector() -> void:
	if (
		lure_selector_view == null
		or loadout == null
		or phase != Phase.AIM
	):
		return

	if not lure_selector_view.open_for_loadout(loadout):
		return

	lure_selector_open = true
	aim.stop()


func _close_lure_selector(resume_aim: bool) -> void:
	if lure_selector_view != null:
		lure_selector_view.close_selector()

	var was_open := lure_selector_open
	lure_selector_open = false

	if was_open and resume_aim and phase == Phase.AIM:
		aim.resume()


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

	# A manual S pull is also a one-shot. Do not let the continuous input
	# resolver replace it with Reel/Reel_Idle before the reaction finishes.
	if manual_pull_animation_active:
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
		# Normal lure-in-water state keeps the original control contract:
		# no K = true idle; K held = active reel animation. Bite/fight
		# presentation states above may temporarily override this.
		if is_reeling:
			desired_animation = &"Reel"
		else:
			desired_animation = &"Reel_Idle"

	else:
		return

	if desired_animation == current_reel_animation:
		return

	current_reel_animation = desired_animation
	sprite_director.play(desired_animation)


func _play_manual_pull_animation() -> void:
	# The physical pulse is handled by Bait. This flag only gives the one-shot
	# character reaction temporary ownership of the animation layer.
	manual_pull_animation_active = true
	current_reel_animation = &"Reel_Bite"
	sprite_director.play(&"Reel_Bite")
	
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
			fishing_catch_view.show_catch(
				caught_fish,
				catch_record_result
			)

		return
	
	if animation_name == &"Reel_Broken_Rod" and phase == Phase.LINE_BROKEN:
		phase = Phase.WAIT_RESULT
		return
	
	if (
		animation_name == &"Reel_Bite"
		and manual_pull_animation_active
	):
		manual_pull_animation_active = false
		current_reel_animation = &""

		_update_reel_animation()
		return

	if (
		animation_name == &"Reel_Bite_Strong"
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

func _on_bait_landed(point: Vector3) -> void:
	_spawn_surface_splash(
		point,
		landing_splash_strength,
		false
	)

	if phase == Phase.THROW:
		bait_landed_during_throw = true
		return

	if phase == Phase.BAIT_FLYING:
		_enter_in_water()
		
func _enter_in_water() -> void:
	phase = Phase.IN_WATER
	last_lure_loss_result = {}
	technique_detector.reset()
	technique_view.clear()

	# No K means true idle from the first water frame. Bite/pull reactions may
	# temporarily own the animation, then resolve back through the normal
	# reel animation state machine.
	bite_opportunity_animation_active = false
	bite_animation_active = false
	manual_pull_animation_active = false
	current_reel_animation = &"Reel_Idle"
	sprite_director.play(&"Reel_Idle")


func _cancel_water_cast_to_aim() -> void:
	if phase != Phase.IN_WATER:
		return

	# Stop any held reel state before destroying the lure.
	encounter.set_player_reeling(false)
	caster.set_reeling(false)

	# Mark this return as a player-requested quick cancel. The normal
	# bait_returned signal remains the single cleanup path for Encounter,
	# HUD and Fishing state; the flag only changes how the camera comes home.
	_quick_cast_cancel_active = true
	caster.cancel_bait_to_aim()
	_quick_cast_cancel_active = false

	# Do NOT hard-hide the fishing HUD here. Power meter, depth meter and
	# character view all already listen to bait_returned and have approved
	# slide-out animations. Let those play at the same speed/style as their
	# normal appearance instead of overriding them with an instant reset.


func _on_bait_returned() -> void:
	if phase != Phase.IN_WATER and phase != Phase.FIGHT:
		return

	technique_detector.reset()
	technique_view.clear()

	if phase == Phase.FIGHT:
		_begin_catch_landing()
		return
	
	if _quick_cast_cancel_active and camera_rig.has_method(
		"return_fishing_follow_to_target"
	):
		camera_rig.return_fishing_follow_to_target()
	else:
		camera_rig.reset_fishing_follow()

	cast_power_locked = false
	locked_cast_power = 0.0
	cast_curve_value = 0.0
	preview_cast_curve_value = 0.0
	cast_confirm_ready = not Input.is_action_pressed(
		"enter_fishing"
	)

	phase = Phase.AIM
	sprite_director.play(&"Fishing_Idle")
	aim.resume()
	
func _begin_catch_landing() -> void:
	if phase != Phase.FIGHT:
		return

	phase = Phase.LANDING

	# The fish has genuinely reached the catch threshold. Stop player/fight
	# control immediately so a new resistance round cannot start during the
	# presentation beat.
	encounter.set_player_reeling(false)
	caster.set_reeling(false)
	caster.set_bait_frozen(true)
	encounter.begin_catch_landing()

	current_reel_animation = &"Reel_Idle"
	fish_resisting = false
	bite_opportunity_animation_active = false
	bite_animation_active = false
	manual_pull_animation_active = false
	sprite_director.play(&"Reel_Idle")

	# Keep the close-up stable while the final surface reaction plays. The normal
	# catch-result cleanup already unfreezes the fishing camera afterwards.
	camera_rig.set_fishing_camera_frozen(true)

	if is_instance_valid(caster.active_bait):
		var landing_position: Vector3 = (
			caster.get_active_bait_visual_surface_position()
		)
		_spawn_surface_splash(
			landing_position,
			catch_landing_splash_strength,
			true
		)

	_run_catch_landing_sequence()


func _run_catch_landing_sequence() -> void:
	await get_tree().create_timer(
		maxf(catch_landing_hold_time, 0.05)
	).timeout

	if phase != Phase.LANDING:
		return

	# This is the actual commit point. Records/CATCH feedback happen here, after
	# the visual landing beat, not the instant the bait crosses the threshold.
	encounter.catch_fish()

	if caster.has_method("release_returned_bait_after_landing"):
		caster.release_returned_bait_after_landing()

	phase = Phase.CATCH
	sprite_director.play(&"Fishing_Catch")


func _process(delta: float) -> void:
	_fight_splash_cooldown_left = maxf(
		_fight_splash_cooldown_left - delta,
		0.0
	)

	if phase == Phase.CURVE:
		var curve_input := -Input.get_axis(
			"ds_left",
			"ds_right"
		)

		if not is_zero_approx(curve_input):
			cast_curve_value = clampf(
				cast_curve_value
				+ curve_input
				* curve_adjust_speed
				* delta,
				-1.0,
				1.0
			)

		var previous_preview_curve := preview_cast_curve_value
		var blend := 1.0 - exp(
			-curve_preview_smoothing_speed * delta
		)

		preview_cast_curve_value = lerpf(
			preview_cast_curve_value,
			cast_curve_value,
			blend
		)

		if absf(
			cast_curve_value - preview_cast_curve_value
		) < 0.0005:
			preview_cast_curve_value = cast_curve_value

		if not is_equal_approx(
			previous_preview_curve,
			preview_cast_curve_value
		):
			_update_cast_preview(
				locked_cast_power,
				preview_cast_curve_value
			)

		return

	if phase != Phase.IN_WATER and phase != Phase.FIGHT:
		return
	
	if phase == Phase.FIGHT:
		if Input.is_action_just_pressed("move_back"):
			if not bite_animation_active:
				caster.pull_bait_toward_player()
				_play_manual_pull_animation()

		# A/D already drives continuous counter-steering below. Add a restrained
		# fight-only physical side tug on the press as well, so the hooked fish
		# visibly answers the rod input instead of only changing hidden fatigue.
		if not bite_animation_active:
			if Input.is_action_just_pressed("ds_left"):
				caster.twitch_bait(-1.0)
			elif Input.is_action_just_pressed("ds_right"):
				caster.twitch_bait(1.0)
			
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

	technique_detector.reset()
	technique_view.clear()
	phase = Phase.FIGHT
	fish_resisting = true
	caster.set_fight_mode(true)

	if caster.has_method("set_hold_returned_bait_for_landing"):
		caster.set_hold_returned_bait_for_landing(true)

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
	catch_record_result = {}

	if fish == null or fishing_progress == null:
		return

	var debug_override_active := false
	var allow_debug_record := false

	if debug_settings != null:
		debug_override_active = (
			debug_settings.is_encounter_override_active()
		)
		allow_debug_record = (
			debug_settings.should_record_debug_catches()
		)

	# Forced fish / king / technique tests do not pollute the player's
	# permanent records unless SAVE DBG is explicitly enabled.
	if debug_override_active and not allow_debug_record:
		return

	catch_record_result = fishing_progress.record_catch(fish)
	
func _on_bite_triggered() -> void:
	if phase != Phase.IN_WATER:
		return

	caster.hide_bait_ripple()

	# Confirmed hit owns the character until this non-looping animation
	# finishes. _on_fish_hooked() may switch the gameplay phase to FIGHT
	# immediately, but it deliberately does not stomp this reaction.
	bite_opportunity_animation_active = false
	manual_pull_animation_active = false
	bite_animation_active = true
	current_reel_animation = &"Reel_Bite_Strong"

	sprite_director.play(&"Reel_Bite_Strong")

func _on_bite_opportunity_started() -> void:
	if phase != Phase.IN_WATER:
		return

	# The fish is tugging without being hooked yet: visibly pull Ryu
	# forward and hold this state for the entire bite window.
	manual_pull_animation_active = false
	bite_opportunity_animation_active = true
	current_reel_animation = &"Reel_Front"

	caster.show_bait_ripple()
	sprite_director.play(&"Reel_Front")
	
func _on_bite_missed() -> void:
	if phase != Phase.IN_WATER:
		return

	caster.hide_bait_ripple()

	# Release presentation ownership and immediately resolve back to the
	# correct current state: Reel_Idle with no K, Reel while K is held.
	bite_opportunity_animation_active = false
	bite_animation_active = false
	manual_pull_animation_active = false
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

	caster.set_fish_pull_strength(value)

func _on_fish_movement_changed(lateral: float) -> void:
	if phase != Phase.FIGHT:
		return

	caster.set_fish_lateral(lateral)

func _on_fish_depth_intent_changed(value: float) -> void:
	if phase != Phase.FIGHT:
		return

	caster.set_fish_depth_intent(value)


func _on_fish_resistance_started_splash() -> void:
	# The info box calls the beginning of a resistance round "thrashing about".
	# Guarantee matching visual feedback here instead of relying only on the
	# separate random micro-thrash roll inside FishBehavior.
	if phase != Phase.FIGHT:
		return

	var surface_position: Vector3 = caster.get_active_bait_visual_surface_position()
	_spawn_surface_splash(
		surface_position,
		maxf(fight_thrash_splash_strength * 0.95, 0.05),
		true
	)
	_fight_splash_cooldown_left = fight_thrash_splash_cooldown


func _on_fish_thrash_started(intensity: float) -> void:
	if phase != Phase.FIGHT:
		return

	# A real FishBehavior thrash should always have a visual cue. Do not let the
	# generic splash cooldown swallow the event; the signal itself is already
	# discrete and only fires once per actual thrash choice.
	var surface_position: Vector3 = caster.get_active_bait_visual_surface_position()
	var strength := fight_thrash_splash_strength * lerpf(
		0.70,
		1.15,
		clampf(intensity, 0.0, 1.0)
	)

	_spawn_surface_splash(surface_position, strength, true)
	_fight_splash_cooldown_left = fight_thrash_splash_cooldown


func _spawn_surface_splash(
	world_position: Vector3,
	strength: float,
	is_fight_splash: bool
) -> void:
	if FishingSurfaceSplashScene == null:
		return

	var splash := FishingSurfaceSplashScene.instantiate()
	var scene_root := get_tree().current_scene

	if scene_root == null:
		return

	scene_root.add_child(splash)

	if splash.has_method("configure"):
		splash.configure(
			world_position,
			maxf(strength, 0.05),
			is_fight_splash
		)

	# Fight splashes are a readability cue for the hooked fish, not a persistent
	# footprint in world space. The bait can move a meaningful distance during
	# the splash lifetime, so keep the effect visually centered on the bait head.
	# The splash itself remains on the water plane; only its projected screen
	# position follows the underwater bait. Landing splashes stay fixed.
	if (
		is_fight_splash
		and splash.has_method("set_follow_target")
		and is_instance_valid(caster.active_bait)
	):
		splash.set_follow_target(caster.active_bait)

func _on_line_broken() -> void:
	if phase != Phase.FIGHT:
		return

	_consume_equipped_lure_for_line_break()

	if caster.has_method("set_hold_returned_bait_for_landing"):
		caster.set_hold_returned_bait_for_landing(false)

	_freeze_failed_fight()

	current_reel_animation = &""
	fish_resisting = false
	bite_opportunity_animation_active = false
	bite_animation_active = false
	manual_pull_animation_active = false

	phase = Phase.LINE_BROKEN
	sprite_director.play(&"Reel_Broken_Rod")

func _consume_equipped_lure_for_line_break() -> void:
	last_lure_loss_result = {}
	if loadout == null or not loadout.has_method("consume_equipped_lure"):
		return

	var result = loadout.consume_equipped_lure(&"line_break")
	if result is Dictionary:
		last_lure_loss_result = (result as Dictionary).duplicate(true)


func _freeze_failed_fight() -> void:
	caster.set_reeling(false)
	caster.set_bait_frozen(true)
	camera_rig.set_fishing_camera_frozen(true)
	
func _on_fight_failed() -> void:
	if phase != Phase.FIGHT:
		return

	if caster.has_method("set_hold_returned_bait_for_landing"):
		caster.set_hold_returned_bait_for_landing(false)

	_freeze_failed_fight()

	current_reel_animation = &""
	fish_resisting = false
	bite_opportunity_animation_active = false
	bite_animation_active = false
	manual_pull_animation_active = false

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
	if caster.has_method("set_hold_returned_bait_for_landing"):
		caster.set_hold_returned_bait_for_landing(false)
	caster.cancel_bait()

	camera_rig.set_fishing_camera_frozen(false)
	camera_rig.reset_fishing_follow()

	power_meter_view.reset_to_aim()
	depth_meter_view.reset_to_aim()
	
	fishing_catch_view.hide_catch()
	caught_fish = null
	catch_record_result = {}

	current_reel_animation = &""
	fish_resisting = false
	bite_opportunity_animation_active = false
	bite_animation_active = false
	manual_pull_animation_active = false

	sprite_director.play(&"Fishing_Idle")

	screen_transition.fade_from_black()

func _on_catch_view_dismissed() -> void:
	if phase != Phase.CATCH_DISMISS:
		return

	caster.set_reeling(false)
	if caster.has_method("set_hold_returned_bait_for_landing"):
		caster.set_hold_returned_bait_for_landing(false)
	caster.cancel_bait()

	camera_rig.set_fishing_camera_frozen(false)
	camera_rig.reset_fishing_follow()

	power_meter_view.reset_to_aim()
	depth_meter_view.reset_to_aim()

	current_reel_animation = &""
	fish_resisting = false
	bite_opportunity_animation_active = false
	bite_animation_active = false
	manual_pull_animation_active = false

	caught_fish = null
	catch_record_result = {}

	sprite_director.play(&"Fishing_Idle")

	phase = Phase.AIM
	aim.resume()
	
func _on_result_screen_revealed() -> void:
	if phase != Phase.RESULT_TRANSITION:
		return

	phase = Phase.AIM
	aim.resume()

func _on_power_changed(value: float) -> void:
	if (
		phase != Phase.PREP_THROW
		and phase != Phase.CHARGE
	):
		return

	_update_cast_preview(value, 0.0)


func _update_cast_preview(
	power_value: float,
	curve_value: float
) -> void:
	var zone = game_mode.active_fish_zone

	if zone == null:
		throw_preview.hide_preview()
		return

	var points: PackedVector3Array = caster.predict_cast(
		power_value,
		aim.get_direction(),
		zone.get_water_y(),
		curve_value
	)

	throw_preview.show_preview(points)


func _commit_curved_cast() -> void:
	if phase != Phase.CURVE:
		return

	if not cast_power_locked:
		return

	var zone = game_mode.active_fish_zone

	if zone == null:
		throw_preview.hide_preview()
		power.stop()
		locked_cast_power = 0.0
		cast_curve_value = 0.0
		preview_cast_curve_value = 0.0
		cast_power_locked = false
		cast_confirm_ready = not Input.is_action_pressed(
			"enter_fishing"
		)
		phase = Phase.CANCEL_THROW
		sprite_director.play_backwards(&"Prep_Throw")
		return

	var captured_power := locked_cast_power
	# Throw exactly what the player currently sees on screen.
	var selected_curve := preview_cast_curve_value
	var cast_direction: Vector3 = aim.get_direction()
	var cast_lure: BaitData = null
	var cast_swim_bounds: Node = null

	if loadout != null:
		cast_lure = loadout.get_selected_lure()

	# Once tackle ownership is active, an empty loadout must not silently cast
	# the bait scene with its default data. This is the backend guard; the future
	# menu can provide the proper "select/get bait" presentation.
	if cast_lure == null:
		throw_preview.hide_preview()
		power.stop()
		locked_cast_power = 0.0
		cast_curve_value = 0.0
		preview_cast_curve_value = 0.0
		cast_power_locked = false
		cast_confirm_ready = not Input.is_action_pressed("enter_fishing")
		phase = Phase.CANCEL_THROW
		sprite_director.play_backwards(&"Prep_Throw")
		return

	if zone.has_method("get_swim_bounds"):
		cast_swim_bounds = zone.get_swim_bounds()

	# Predict once more before launch so camera follow can use the actual
	# curved landing direction instead of the original straight heading.
	var predicted_points: PackedVector3Array = (
		caster.predict_cast(
			captured_power,
			cast_direction,
			zone.get_water_y(),
			selected_curve
		)
	)

	var camera_follow_direction := cast_direction

	if predicted_points.size() >= 2:
		var first_point: Vector3 = predicted_points[0]
		var landing_point: Vector3 = (
			predicted_points[
				predicted_points.size() - 1
			]
		)

		var landing_direction := (
			landing_point - first_point
		)
		landing_direction.y = 0.0

		if landing_direction.length_squared() > 0.0001:
			camera_follow_direction = (
				landing_direction.normalized()
			)

	# Only NOW is the power selection considered a confirmed cast.
	power.confirm_locked()
	throw_preview.hide_preview()

	var cast_bait: Node3D = caster.perform_cast(
		captured_power,
		cast_direction,
		zone.get_water_y(),
		zone.get_bottom_y(),
		cast_lure,
		cast_swim_bounds,
		selected_curve
	)

	if not is_instance_valid(cast_bait):
		if (
			power_meter_view != null
			and power_meter_view.has_method("cancel_to_aim")
		):
			power_meter_view.cancel_to_aim()

		locked_cast_power = 0.0
		cast_curve_value = 0.0
		preview_cast_curve_value = 0.0
		cast_power_locked = false
		cast_confirm_ready = not Input.is_action_pressed(
			"enter_fishing"
		)
		phase = Phase.CANCEL_THROW
		sprite_director.play_backwards(&"Prep_Throw")
		return

	encounter.set_active_bait_data(cast_lure)
	camera_rig.arm_fishing_follow(
		cast_bait,
		camera_follow_direction,
		zone.get_water_y()
	)

	locked_cast_power = 0.0
	cast_curve_value = 0.0
	preview_cast_curve_value = 0.0
	cast_power_locked = false
	bait_landed_during_throw = false

	phase = Phase.THROW
	sprite_director.play(&"Throw")
