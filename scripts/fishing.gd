extends Node
const GameplaySceneRoot = preload("res://scripts/gameplay_scene_root.gd")
signal cast_started

func request_cast_confirm() -> bool:
	# Orchestrators use the same gated command path and animation callbacks.
	if phase not in [Phase.AIM,Phase.CHARGE,Phase.CURVE]: return false
	var event := InputEventAction.new()
	event.action = &"enter_fishing"
	event.pressed = true
	_unhandled_input(event)
	event.pressed = false
	_unhandled_input(event)
	return true

const FishingSessionServicesScript = preload(
	"res://scripts/fishing_session_services.gd"
)
const FishingPauseControllerScript = preload(
	"res://scripts/fishing_pause_controller.gd"
)
const FishingCastInputGateScript = preload(
	"res://scripts/fishing_cast_input_gate.gd"
)
const FishingOutcomeServiceScript = preload(
	"res://scripts/fishing_outcome_service.gd"
)
const DefaultFishingOutcomePolicy = preload(
	"res://data/bof4/outcomes/default_outcome_policy.tres"
)

const FishingMenuScene = preload(
	"res://actors/FishingMenu.tscn"
)
const FishingEconomyMenuScene = preload(
	"res://actors/FishingEconomyMenu.tscn"
)

const FishingTechniqueDetectorScript = preload(
	"res://scripts/fishing_technique_detector.gd"
)
const FishingTechniqueViewScene = preload(
	"res://actors/FishingTechniqueView.tscn"
)

const FishingTackleCatalogResource = preload(
	"res://data/bof4/tackle/all_tackle.tres"
)
const FishingSurfaceSplashScene = preload(
	"res://actors/FishingSurfaceSplash.tscn"
)
const FishingCurrentSurfaceViewScript = preload(
	"res://scripts/fishing_current_surface_view.gd"
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
var session_services: FishingSessionServices = null
var debug_controller: Node = null
var technique_detector: FishingTechniqueDetector = null
var technique_view: FishingTechniqueView = null
var fishing_progress: FishingProgress = null
var fishing_inventory: FishingInventory = null
var fishing_catch_repository: FishingCatchRepository = null
var fishing_trade_service: FishingTradeService = null
var fishing_economy_service = null
var fishing_economy_access = null
var fishing_session_modifier_service = null
var fishing_prepared_bait_service: FishingPreparedBaitService = null
var fishing_environment_service = null
var fishing_current_service: FishingCurrentService = null
var fishing_mastery_service: FishingMasteryService = null
var fishing_current_view: FishingCurrentSurfaceView = null
var fishing_fish_consumable_service = null
var fishing_unlock_state: FishingUnlockState = null
var fishing_reward_service: FishingRewardService = null
var fishing_journal_service: FishingJournalService = null
var fishing_menu: FishingMenu = null
var fishing_economy_menu: CanvasLayer = null
var catch_record_result: Dictionary = {}
var last_lure_loss_result: Dictionary = {}
var last_outcome_result: Dictionary = {}
var last_prepared_bait_use_result: Dictionary = {}
var outcome_service = null

var locked_cast_power: float = 0.0
# Player input / desired curve amount.
var cast_curve_value: float = 0.0
# Smoothed preview curve used by the visible arc + torus and by the actual throw.
var preview_cast_curve_value: float = 0.0

# Cast input is owned by a small deterministic gate instead of animation
# timing. One physical K press can advance at most one cast stage.
var cast_input_gate: FishingCastInputGate = (
	FishingCastInputGateScript.new()
)
var buffered_prep_power: float = -1.0
var cast_power_locked: bool = false
var _quick_cast_cancel_active: bool = false
var _fight_splash_cooldown_left: float = 0.0

func _ready() -> void:
	# Read-only camera exclusion geometry; presentation/mechanics are unchanged.
	if camera_rig != null and camera_rig.has_method("set_fishing_hud_geometry"):
		camera_rig.set_fishing_hud_geometry(power_meter_view,depth_meter_view)
	var pause_controller := FishingPauseControllerScript.new()
	pause_controller.name = "FishingPauseController"
	add_child(pause_controller)

	game_mode.mode_changed.connect(_on_mode_changed)
	aim.aim_changed.connect(_on_aim_changed)
	caster.bait_landed.connect(_on_bait_landed)
	caster.bait_returned.connect(_on_bait_returned)
	encounter.fish_hooked.connect(_on_fish_hooked)
	encounter.fish_exhausted.connect(_on_fish_exhausted)
	encounter.bite_opportunity_started.connect(
		_on_bite_opportunity_started
	)
	encounter.bite_commit_ready.connect(_on_bite_commit_ready)

	encounter.bite_triggered.connect(_on_bite_triggered)
	encounter.bite_missed.connect(_on_bite_missed)
	encounter.fish_resistance_changed.connect(_on_fish_resistance_changed)
	encounter.fish_pull_changed.connect(_on_fish_pull_changed)
	encounter.fish_movement_changed.connect(_on_fish_movement_changed)
	encounter.fish_depth_intent_changed.connect(_on_fish_depth_intent_changed)
	encounter.fish_thrash_started.connect(_on_fish_thrash_started)
	encounter.fish_aerial_started.connect(_on_fish_aerial_started)
	encounter.fish_resistance_started.connect(_on_fish_resistance_started_splash)
	encounter.hook_off.connect(_on_fight_failed)
	encounter.line_broken.connect(_on_line_broken)
	encounter.fish_caught.connect(_on_fish_caught)
	fishing_catch_view.shown.connect(_on_catch_view_shown)
	fishing_catch_view.dismissed.connect(_on_catch_view_dismissed)
	power.power_changed.connect(_on_power_changed)

	var player_screen_notifier := player.get_node_or_null(
		"RyuScreenNotifier"
	) as VisibleOnScreenNotifier3D

	if player_screen_notifier != null:
		player_screen_notifier.screen_entered.connect(
			_on_world_player_reentered_fishing_view
		)
	else:
		push_warning(
			"Fishing: RyuScreenNotifier was not found under the player."
		)
	
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

	session_services = _get_or_create_session_services()
	fishing_progress = session_services.progress
	fishing_inventory = session_services.inventory
	fishing_catch_repository = session_services.catch_repository
	fishing_trade_service = session_services.trade_service
	fishing_economy_service = session_services.economy_service
	fishing_economy_access = session_services.economy_access
	fishing_session_modifier_service = session_services.session_modifier_service
	fishing_prepared_bait_service = session_services.prepared_bait_service
	fishing_environment_service = session_services.environment_service
	fishing_current_service = session_services.get_fishing_current_service()
	fishing_mastery_service = session_services.get_fishing_mastery_service()
	fishing_fish_consumable_service = session_services.fish_consumable_service
	fishing_unlock_state = session_services.unlock_state
	fishing_reward_service = session_services.reward_service
	fishing_journal_service = session_services.journal_service

	if caster != null and caster.has_method("set_current_service"):
		caster.set_current_service(fishing_current_service)

	if caster != null and caster.has_method("set_mastery_service"):
		caster.set_mastery_service(fishing_mastery_service)

	if encounter != null and encounter.has_method("set_mastery_service"):
		encounter.set_mastery_service(fishing_mastery_service)

	fishing_current_view = FishingCurrentSurfaceViewScript.new() as FishingCurrentSurfaceView
	fishing_current_view.name = "FishingCurrentSurfaceView"
	add_child(fishing_current_view)
	fishing_current_view.configure(
		fishing_current_service,
		fishing_mastery_service
	)
	fishing_current_view.bind_caster(caster)
	_sync_current_context_to_zone()

	if (
		encounter != null
		and encounter.has_method("set_fishing_progress")
	):
		encounter.set_fishing_progress(fishing_progress)

	if (
		encounter != null
		and encounter.has_method("set_session_modifier_service")
	):
		encounter.set_session_modifier_service(
			fishing_session_modifier_service
		)

	if (
		encounter != null
		and encounter.has_method("set_prepared_bait_service")
	):
		encounter.set_prepared_bait_service(
			fishing_prepared_bait_service
		)

	if (
		encounter != null
		and encounter.has_method("set_environment_service")
	):
		encounter.set_environment_service(
			fishing_environment_service
		)

	if (
		fishing_environment_service != null
		and fishing_environment_service.has_signal("environment_changed")
	):
		var environment_callback: Callable = Callable(
			self,
			"_on_fishing_environment_changed"
		)
		if not fishing_environment_service.is_connected(
			"environment_changed",
			environment_callback
		):
			fishing_environment_service.connect(
				"environment_changed",
				environment_callback
			)

	if loadout != null:
		session_services.bind_loadout(loadout)

	outcome_service = FishingOutcomeServiceScript.new()
	outcome_service.configure(
		fishing_catch_repository,
		loadout,
		fishing_reward_service,
		DefaultFishingOutcomePolicy
	)

	_setup_fishing_menu()
	_setup_fishing_economy_menu()

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

	var screen_bounds_script = preload("res://scripts/fishing_screen_water_bounds.gd")
	var screen_bounds = screen_bounds_script.new()
	screen_bounds.name = "ScreenWaterBounds"
	screen_bounds.fishing = self
	screen_bounds.info_view = $FishingInfoController.info_view
	add_child(screen_bounds)


func _setup_fishing_menu() -> void:
	if fishing_menu != null:
		return

	fishing_menu = FishingMenuScene.instantiate() as FishingMenu
	if fishing_menu == null:
		push_warning("Fishing: failed to instantiate FishingMenu.")
		return

	var menu_parent: Node = get_node_or_null("../../UI")
	if menu_parent == null:
		menu_parent = GameplaySceneRoot.resolve(get_tree())

	if menu_parent == null:
		push_warning("Fishing: no parent available for FishingMenu.")
		fishing_menu.queue_free()
		fishing_menu = null
		return

	menu_parent.add_child(fishing_menu)
	fishing_menu.configure(
		game_mode,
		loadout,
		fishing_inventory,
		fishing_journal_service,
		FishingTackleCatalogResource
	)


func _setup_fishing_economy_menu() -> void:
	if fishing_economy_menu != null or fishing_economy_access == null:
		return

	var menu = FishingEconomyMenuScene.instantiate()
	if menu == null:
		push_warning("Fishing: failed to instantiate FishingEconomyMenu.")
		return

	var menu_parent: Node = get_node_or_null("../../UI")
	if menu_parent == null:
		menu_parent = GameplaySceneRoot.resolve(get_tree())
	if menu_parent == null:
		menu.queue_free()
		return

	menu_parent.add_child(menu)
	fishing_economy_menu = menu as CanvasLayer
	if menu.has_method("configure"):
		menu.configure(game_mode, fishing_economy_access)


func _unhandled_input(event: InputEvent) -> void:
	if not ModalInputOwnership.gameplay_accepts(self, event): return
	if not game_mode.is_fishing():
		return

	if (
		debug_controller != null
		and debug_controller.is_toggle_event(event)
	):
		debug_controller.toggle(
			phase == Phase.AIM and not lure_selector_open
		)
		get_viewport().set_input_as_handled()
		return

	if (
		debug_controller != null
		and debug_controller.route_open_input(event)
	):
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

	# Re-arm only after a genuine physical release.
	if (
		_is_cast_input_phase()
		and event.is_action_released("enter_fishing")
	):
		cast_input_gate.release(
			_get_cast_input_gate_stage()
		)
		get_viewport().set_input_as_handled()
		return

	# Fast second K during Prep_Throw is BUFFERED rather than swallowed.
	# We capture the power value at the actual press time, then transition into
	# CURVE as soon as Prep_Throw finishes.
	if (
		phase == Phase.PREP_THROW
		and event.is_action_pressed("enter_fishing")
	):
		var prep_result: FishingCastInputGate.PressResult = (
			cast_input_gate.press(
				FishingCastInputGate.Stage.PREP_THROW,
				_is_key_echo(event)
			)
		)

		if (
			prep_result
			== FishingCastInputGate.PressResult.BUFFERED
		):
			buffered_prep_power = power.lock_value()

		get_viewport().set_input_as_handled()
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
			buffered_prep_power = -1.0
			cast_curve_value = 0.0
			preview_cast_curve_value = 0.0
			cast_power_locked = false

			phase = Phase.PREP_THROW
			power.start()
			sprite_director.play(&"Prep_Throw")
			get_viewport().set_input_as_handled()
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
			buffered_prep_power = -1.0
			cast_curve_value = 0.0
			preview_cast_curve_value = 0.0
			cast_power_locked = false
			cast_input_gate.reset(
				Input.is_action_pressed(
					"enter_fishing"
				)
			)

			phase = Phase.CANCEL_THROW
			sprite_director.play_backwards(&"Prep_Throw")
			return
			
	if phase == Phase.CHARGE:
		if _try_consume_cast_confirm(event):
			_lock_cast_power_to_curve(
				power.lock_value()
			)
			get_viewport().set_input_as_handled()
			return

	if phase == Phase.CURVE:
		if _try_consume_cast_confirm(event):
			_commit_curved_cast()
			get_viewport().set_input_as_handled()
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
			technique_detector.record_pulse(&"rod_pull")
			caster.pull_bait_toward_player()
			_play_manual_pull_animation()
			get_viewport().set_input_as_handled()
			return

		if event.is_action_pressed("ds_left"):
			technique_detector.record_pulse(&"left")
			caster.twitch_bait(-1.0)
			encounter.add_lure_tension(0.05)
			return

		if event.is_action_pressed("ds_right"):
			technique_detector.record_pulse(&"right")
			caster.twitch_bait(1.0)
			encounter.add_lure_tension(0.05)
			return

		if event.is_action_pressed("enter_fishing"):
			if encounter.try_hook():
				technique_detector.reset()
				return

			technique_detector.record_pulse(&"reel")
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
		if fishing_prepared_bait_service != null:
			fishing_prepared_bait_service.clear_cast(&"fishing_exit")
		if fishing_economy_menu != null and fishing_economy_menu.has_method("is_open"):
			if bool(fishing_economy_menu.is_open()):
				fishing_economy_menu.close_menu()
		if session_services != null:
			var save_result: Dictionary = session_services.save_all_fishing_state()
			if not bool(save_result.get("durable", false)):
				push_warning("Fishing: one or more fishing save domains failed to persist on exit.")

		cast_input_gate.reset(false)
		buffered_prep_power = -1.0
		cast_power_locked = false
		locked_cast_power = 0.0
		cast_curve_value = 0.0
		preview_cast_curve_value = 0.0

		_close_lure_selector(false)
		if debug_controller != null:
			debug_controller.close(false)

		if technique_detector != null:
			technique_detector.reset()

		# Macro Fishing owns session teardown. Encounter then clears every pending
		# timer/fight input so an interrupted mode can never leak into the next cast.
		if encounter != null and encounter.has_method("reset_cast_session"):
			encounter.reset_cast_session()

		if encounter.has_method("set_fish_zone"):
			encounter.set_fish_zone(null)

		if (
			fishing_environment_service != null
			and fishing_environment_service.has_method("set_spot")
		):
			fishing_environment_service.set_spot(null)

		if fishing_current_service != null:
			fishing_current_service.set_spot(null)
			fishing_current_service.set_swim_bounds(null)
		if fishing_current_view != null:
			fishing_current_view.bind_zone(null)

		if (
			depth_meter_view != null
			and depth_meter_view.has_method(
				"set_fish_zone"
			)
		):
			depth_meter_view.set_fish_zone(null)

		if technique_view != null:
			technique_view.clear()

		if outcome_service != null:
			outcome_service.reset_session()

		return

	cast_input_gate.reset(
		Input.is_action_pressed(
			"enter_fishing"
		)
	)
	buffered_prep_power = -1.0
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

		if (
			fishing_environment_service != null
			and fishing_environment_service.has_method("set_spot")
		):
			fishing_environment_service.set_spot(
				zone.get_fishing_spot()
			)

		if fishing_current_service != null:
			fishing_current_service.set_spot(zone.get_fishing_spot())
			var zone_swim_bounds: FishSwimBounds = null
			if zone.has_method("get_swim_bounds"):
				zone_swim_bounds = zone.get_swim_bounds() as FishSwimBounds
			fishing_current_service.set_swim_bounds(zone_swim_bounds)
		if fishing_current_view != null:
			fishing_current_view.bind_zone(zone)

		if encounter.has_method("set_fish_zone"):
			encounter.set_fish_zone(zone)

		if (
			depth_meter_view != null
			and depth_meter_view.has_method(
				"set_fish_zone"
			)
		):
			depth_meter_view.set_fish_zone(zone)

		if debug_controller != null:
			debug_controller.set_fish_zone(zone)
			debug_controller.sync_environment()
		_sync_environment_context_to_zone()
		camera_rig.enter_fishing_view()







func _sync_current_context_to_zone() -> void:
	if fishing_current_service == null:
		return
	if game_mode == null or not game_mode.is_fishing():
		fishing_current_service.set_spot(null)
		fishing_current_service.set_swim_bounds(null)
		if fishing_current_view != null:
			fishing_current_view.bind_zone(null)
		return
	var zone = game_mode.active_fish_zone
	if zone == null:
		fishing_current_service.set_spot(null)
		fishing_current_service.set_swim_bounds(null)
		if fishing_current_view != null:
			fishing_current_view.bind_zone(null)
		return
	var zone_swim_bounds: FishSwimBounds = null
	if zone.has_method("get_swim_bounds"):
		zone_swim_bounds = zone.get_swim_bounds() as FishSwimBounds
	fishing_current_service.set_spot(zone.get_fishing_spot())
	fishing_current_service.set_swim_bounds(zone_swim_bounds)
	if fishing_current_view != null:
		fishing_current_view.bind_zone(zone)


func _on_fishing_environment_changed(_snapshot: Dictionary) -> void:
	_sync_environment_context_to_zone()


func _sync_environment_context_to_zone() -> void:
	if fishing_environment_service == null:
		return
	var zone = game_mode.active_fish_zone
	if zone == null or not zone.has_method("set_environment_context"):
		return
	var population: Array = zone.get_fish_population()
	var context: Dictionary = fishing_environment_service.get_selection_context(
		population
	)
	zone.set_environment_context(context)


func get_fishing_environment_service() -> Node:
	return fishing_environment_service


func get_fishing_progress() -> FishingProgress:
	return fishing_progress


func get_fishing_catch_repository() -> FishingCatchRepository:
	return fishing_catch_repository


func get_fishing_inventory() -> FishingInventory:
	return fishing_inventory


func get_last_lure_loss_result() -> Dictionary:
	return last_lure_loss_result.duplicate(true)


func get_last_outcome_result() -> Dictionary:
	return last_outcome_result.duplicate(true)


func get_fishing_trade_service() -> FishingTradeService:
	return fishing_trade_service


func get_fishing_economy_service():
	return fishing_economy_service


func get_fishing_unlock_state() -> FishingUnlockState:
	return fishing_unlock_state


func get_fishing_reward_service() -> FishingRewardService:
	return fishing_reward_service


func get_fishing_journal_service() -> FishingJournalService:
	return fishing_journal_service




func _get_or_create_session_services() -> FishingSessionServices:
	return SessionComposition.acquire(get_tree())


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


func _get_cast_input_gate_stage() -> FishingCastInputGate.Stage:
	match phase:
		Phase.AIM:
			return FishingCastInputGate.Stage.AIM
		Phase.PREP_THROW:
			return FishingCastInputGate.Stage.PREP_THROW
		Phase.CHARGE:
			return FishingCastInputGate.Stage.CHARGE
		Phase.CURVE:
			return FishingCastInputGate.Stage.CURVE
		_:
			return FishingCastInputGate.Stage.NONE


func _try_consume_cast_confirm(
	event: InputEvent
) -> bool:
	if not event.is_action_pressed("enter_fishing"):
		return false

	var result: FishingCastInputGate.PressResult = (
		cast_input_gate.press(
			_get_cast_input_gate_stage(),
			_is_key_echo(event)
		)
	)

	return (
		result
		== FishingCastInputGate.PressResult.CONSUMED
	)


func _lock_cast_power_to_curve(
	captured_power: float
) -> void:
	if phase != Phase.CHARGE:
		return

	locked_cast_power = clampf(
		captured_power,
		0.0,
		1.0
	)
	buffered_prep_power = -1.0
	cast_power_locked = true
	cast_curve_value = 0.0
	preview_cast_curve_value = 0.0
	aim.stop()

	phase = Phase.CURVE
	_update_cast_preview(
		locked_cast_power,
		preview_cast_curve_value
	)



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

	# Reel_Bite_Strong is the one-shot committed-take cue.
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

	# W gives a forward-lean pose even without K. Without reeling we freeze
	# the first Reel_Front frame instead of playing the reel cycle.
	elif vertical < -0.1:
		desired_animation = (
			&"Reel_Front"
			if is_reeling
			else &"Reel_Front_Idle_Pose"
		)

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
	if (
		desired_animation == &"Reel_Front_Idle_Pose"
		and sprite_director.has_method("show_animation_frame")
	):
		sprite_director.call("show_animation_frame", &"Reel_Front", 0)
	else:
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

			if cast_input_gate.take_prep_buffer():
				var captured_power: float = buffered_prep_power

				if captured_power < 0.0:
					captured_power = power.lock_value()

				_lock_cast_power_to_curve(
					captured_power
				)

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

func _on_world_player_reentered_fishing_view() -> void:
	# CharacterView hides its HUD copy on this exact event. Do NOT snap or tween
	# the camera here. We only change the camera's ownership rule: from this
	# point, remaining fish/lure distance progressively carries the rig home.
	if (
		phase != Phase.IN_WATER
		and phase != Phase.FIGHT
		and phase != Phase.LANDING
	):
		return

	if camera_rig == null:
		return

	if camera_rig.has_method("begin_fishing_player_return"):
		camera_rig.begin_fishing_player_return()


func _on_bait_landed(point: Vector3) -> void:
	last_lure_loss_result = {}
	last_outcome_result = {}
	if outcome_service != null:
		outcome_service.begin_cast()

	_spawn_surface_splash(
		point,
		landing_splash_strength,
		false
	)

	# The camera must not infer water contact from lure depth. Tell it exactly
	# when the cast becomes waterborne so camera ownership is deterministic on
	# the first cast, second cast, and every cast after that.
	if camera_rig.has_method("notify_fishing_target_landed"):
		camera_rig.notify_fishing_target_landed()

	if phase == Phase.THROW:
		bait_landed_during_throw = true
		return

	if phase == Phase.BAIT_FLYING:
		_enter_in_water()
		
func _enter_in_water() -> void:
	phase = Phase.IN_WATER
	_sync_fight_camera_tracking()
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

	if outcome_service != null:
		last_outcome_result = outcome_service.resolve_cancelled()

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

	if phase == Phase.IN_WATER and fishing_prepared_bait_service != null:
		fishing_prepared_bait_service.clear_cast(&"bait_returned")

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
		camera_rig.return_fishing_follow_to_target(true)

	cast_power_locked = false
	locked_cast_power = 0.0
	buffered_prep_power = -1.0
	cast_curve_value = 0.0
	preview_cast_curve_value = 0.0
	cast_input_gate.reset(
		Input.is_action_pressed(
			"enter_fishing"
		)
	)

	phase = Phase.AIM
	sprite_director.play(&"Fishing_Idle")
	aim.resume()
	
func _begin_catch_landing() -> void:
	if phase != Phase.FIGHT:
		return

	# Encounter owns bite/fight legality. Fishing requests the transition once and
	# only advances the macro phase if Encounter accepts it. This prevents camera/
	# animation state from entering LANDING with no valid hooked fish behind it.
	if (
		encounter.has_method("begin_catch_landing")
		and not bool(encounter.begin_catch_landing())
	):
		push_warning(
			"Fishing: rejected invalid FIGHT -> LANDING transition."
		)
		return

	phase = Phase.LANDING
	_sync_fight_camera_tracking()

	# The fish has genuinely reached the catch threshold. Stop player/fight
	# control immediately so no new resistance round can start during the
	# presentation beat. Encounter already rejects stale input in LANDING.
	encounter.set_player_reeling(false)
	caster.set_reeling(false)
	caster.set_bait_frozen(true)

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
	if encounter.has_method("catch_fish") and not bool(encounter.catch_fish()):
		push_warning("Fishing: catch commit rejected because landing was no longer valid.")
		_abort_invalid_catch_landing()
		return

	if caster.has_method("release_returned_bait_after_landing"):
		caster.release_returned_bait_after_landing()

	phase = Phase.CATCH
	sprite_director.play(&"Fishing_Catch")


func _abort_invalid_catch_landing() -> void:
	# Defensive recovery only. A valid runtime should never need this path, but a
	# stale async timer or future feature must not strand the player in LANDING.
	if caster.has_method("set_hold_returned_bait_for_landing"):
		caster.set_hold_returned_bait_for_landing(false)
	if caster.has_method("release_returned_bait_after_landing"):
		caster.release_returned_bait_after_landing()

	camera_rig.set_fishing_camera_frozen(false)
	camera_rig.reset_fishing_follow()

	if encounter.has_method("reset_cast_session"):
		encounter.reset_cast_session()

	current_reel_animation = &""
	fish_resisting = false
	bite_opportunity_animation_active = false
	bite_animation_active = false
	manual_pull_animation_active = false

	phase = Phase.AIM
	sprite_director.play(&"Fishing_Idle")
	aim.resume()


func _sync_fight_camera_tracking() -> void:
	if camera_rig == null or not camera_rig.has_method("set_fishing_fight_tracking"):
		return
	var active: bool = phase == Phase.IN_WATER or (phase == Phase.FIGHT and encounter.lifecycle.is_hooked())
	# Water steering already moves the bait before a bite. Keep this same owner
	# through hooking, without releasing or recapturing the camera base.
	# active_bait is the physical mechanics target even when submerged or when
	# the fight shadow/sprite is hidden. Never substitute a presentation node.
	camera_rig.set_fishing_fight_tracking(active, caster.active_bait if active else null)


func _process(delta: float) -> void:
	_sync_fight_camera_tracking()
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
				# Sync the current K state before evaluating the S lift. This
				# makes release-K + tap-S work even when both changes land in
				# the same frame.
				var pump_reeling_now := Input.is_action_pressed(
					"enter_fishing"
				)
				encounter.set_player_reeling(pump_reeling_now)

				if encounter.has_method("try_start_pump_reel_cycle"):
					encounter.try_start_pump_reel_cycle()

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
	_sync_fight_camera_tracking()
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

	if fish == null:
		push_error("Fishing: Encounter emitted a null caught fish.")
		return

	var should_record: bool = true
	if debug_controller != null:
		should_record = debug_controller.should_record_catch()

	if outcome_service == null:
		push_error("Fishing: outcome service is unavailable during catch resolution.")
		return

	last_outcome_result = outcome_service.resolve_catch(
		fish,
		_build_catch_record_context(),
		should_record
	)
	if fishing_prepared_bait_service != null:
		fishing_prepared_bait_service.clear_cast(&"catch_completed")

	var raw_catch_result: Variant = last_outcome_result.get(
		"catch_result",
		{}
	)
	if raw_catch_result is Dictionary:
		catch_record_result = (raw_catch_result as Dictionary).duplicate(true)

	# A physical catch is still presented if disk/backend persistence fails, but
	# never fail silently. The outcome snapshot remains available for QA and the
	# pending-journal path can recover durable writes when applicable.
	if (
		should_record
		and not bool(last_outcome_result.get("backend_ok", false))
	):
		push_error(
			"Fishing: caught fish was not committed to progression/inventory. "
			+ "Outcome="
			+ str(last_outcome_result)
		)

func _build_catch_record_context() -> Dictionary:
	var context := {
		"spot_id": "",
		"spot_name": "",
		"lure_id": "",
		"lure_name": "",
		"prepared_bait_used": false,
		"prepared_bait_item_id": "",
	}

	if fishing_prepared_bait_service != null:
		context["prepared_bait_used"] = (
			fishing_prepared_bait_service.is_cast_baited()
		)
		context["prepared_bait_item_id"] = String(
			fishing_prepared_bait_service.get_prepared_bait_item_id()
		)

	var zone = game_mode.active_fish_zone if game_mode != null else null
	if zone != null and zone.has_method("get_fishing_spot"):
		var spot_value: Variant = zone.call("get_fishing_spot")
		if spot_value is FishingSpotData:
			var spot := spot_value as FishingSpotData
			context["spot_id"] = str(spot.spot_id)
			context["spot_name"] = spot.spot_name

	if loadout != null:
		var lure := loadout.get_selected_lure()
		if lure != null:
			context["lure_id"] = str(lure.lure_id)
			context["lure_name"] = lure.display_name

	return context


func _on_bite_commit_ready(_snapshot: Dictionary) -> void:
	if phase != Phase.IN_WATER:
		return

	# This is the readable moment the player is waiting for. Tentative bites hold
	# Reel_Front first; the strong one-shot marks the actual hook-set window.
	bite_opportunity_animation_active = false
	manual_pull_animation_active = false
	bite_animation_active = true
	current_reel_animation = &"Reel_Bite_Strong"

	# The opportunity remains a ripple until the physical hook is confirmed.
	sprite_director.play(&"Reel_Bite_Strong")


func _on_bite_triggered() -> void:
	if phase != Phase.IN_WATER:
		return

	caster.show_bait_bite_splash()

	# The strong take is now the pre-hook recognition cue, so a successful K
	# should not replay it a second time. If the one-shot is still running it owns
	# presentation into FIGHT; otherwise the normal reel resolver takes over.
	bite_opportunity_animation_active = false
	manual_pull_animation_active = false

	if not bite_animation_active:
		current_reel_animation = &""
		_update_reel_animation()

func _on_bite_opportunity_started() -> void:
	if phase != Phase.IN_WATER:
		return

	# The fish is tugging without being hooked yet: visibly pull Ryu
	# forward until the bite commits or the opportunity is missed.
	manual_pull_animation_active = false
	bite_opportunity_animation_active = true
	current_reel_animation = &"Reel_Front"

	caster.show_bait_ripple(float(encounter.get_bite_timing_snapshot().get("total_window", encounter.base_bite_window_time)))
	sprite_director.play(&"Reel_Front")
	
func _on_bite_missed() -> void:
	if phase != Phase.IN_WATER:
		return

	if outcome_service != null:
		last_outcome_result = outcome_service.resolve_miss()

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


func _on_fish_aerial_started(snapshot: Dictionary) -> void:
	if phase != Phase.FIGHT:
		return

	# V1 uses the existing surface splash language as the breach cue. The actual
	# fish shadow remains the underwater ownership/presentation actor; a later art
	# pass can add a dedicated above-water fish sprite without changing mechanics.
	var surface_position: Vector3 = caster.get_active_bait_visual_surface_position()
	var intensity := clampf(float(snapshot.get("intensity", 0.6)), 0.0, 1.0)
	var response := StringName(str(snapshot.get("expected_response", "none")))
	var strength_multiplier := lerpf(0.95, 1.20, intensity)
	if response == &"bow_low":
		# Acrobatic launches get the sharper splash cue; power breaches stay
		# broader/calmer so the two learned response families are not identical.
		strength_multiplier = lerpf(1.25, 1.55, intensity)
	var strength := fight_thrash_splash_strength * strength_multiplier
	_spawn_surface_splash(surface_position, strength, true)
	_fight_splash_cooldown_left = fight_thrash_splash_cooldown


func _spawn_surface_splash(
	world_position: Vector3,
	strength: float,
	is_fight_splash: bool
) -> void:
	if FishingSurfaceSplashScene == null:
		return

	var scene_root := GameplaySceneRoot.resolve(get_tree())

	if scene_root == null:
		return

	var splash := FishingSurfaceSplashScene.instantiate()
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
	_resolve_failed_fight(FishingOutcomeServiceScript.OUTCOME_LINE_BREAK)


func _freeze_failed_fight() -> void:
	caster.set_reeling(false)
	caster.set_bait_frozen(true)
	camera_rig.set_fishing_camera_frozen(true)


func _on_fight_failed() -> void:
	_resolve_failed_fight(FishingOutcomeServiceScript.OUTCOME_HOOK_OFF)


func _resolve_failed_fight(outcome: StringName) -> void:
	# Phase is the macro terminal latch. Encounter has its own one-shot lifecycle,
	# and OutcomeService independently guarantees that gameplay consequences such
	# as lure loss can only be applied once.
	if phase != Phase.FIGHT:
		return

	if outcome_service == null:
		push_error("Fishing: outcome service unavailable during fight failure.")
		return

	var result: Dictionary = {}
	if outcome == FishingOutcomeServiceScript.OUTCOME_LINE_BREAK:
		result = outcome_service.resolve_line_break()
	elif outcome == FishingOutcomeServiceScript.OUTCOME_HOOK_OFF:
		result = outcome_service.resolve_hook_off()
	else:
		push_error("Fishing: unsupported failure outcome " + str(outcome))
		return

	if not bool(result.get("applied", false)):
		return

	last_outcome_result = result.duplicate(true)
	if fishing_prepared_bait_service != null:
		fishing_prepared_bait_service.clear_cast(outcome)
	var raw_lure_loss: Variant = result.get("lure_loss", {})
	last_lure_loss_result = (
		(raw_lure_loss as Dictionary).duplicate(true)
		if raw_lure_loss is Dictionary
		else {}
	)

	phase = Phase.LINE_BROKEN
	_sync_fight_camera_tracking()

	if caster.has_method("set_hold_returned_bait_for_landing"):
		caster.set_hold_returned_bait_for_landing(false)

	_freeze_failed_fight()

	current_reel_animation = &""
	fish_resisting = false
	bite_opportunity_animation_active = false
	bite_animation_active = false
	manual_pull_animation_active = false

	# Hook Off and Line Break already have distinct feedback textures. Until a
	# dedicated Hook-Off character animation exists, both reuse the existing
	# terminal reel-back animation; outcome consequences remain fully distinct.
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

	if encounter.has_method("reset_cast_session"):
		encounter.reset_cast_session()

	camera_rig.set_fishing_camera_frozen(false)
	camera_rig.return_fishing_follow_to_target(true)

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

	if encounter.has_method("reset_cast_session"):
		encounter.reset_cast_session()

	camera_rig.set_fishing_camera_frozen(false)
	camera_rig.return_fishing_follow_to_target(true)

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
		push_warning(
			"Fishing: cast commit blocked because active fish zone is null."
		)
		return

	var captured_power := locked_cast_power
	# Throw exactly what the player currently sees on screen.
	var selected_curve := preview_cast_curve_value
	var cast_direction: Vector3 = aim.get_direction()
	var cast_lure: BaitData = null
	var cast_swim_bounds: Node = null
	var cast_shore_boundary: Node3D = null

	if loadout != null:
		cast_lure = loadout.get_selected_lure()

	# Once tackle ownership is active, an empty loadout must not silently cast
	# the bait scene with its default data. This is the backend guard; the future
	# menu can provide the proper "select/get bait" presentation.
	if cast_lure == null:
		push_warning(
			"Fishing: cast commit blocked because no lure is equipped."
		)
		return

	if zone.has_method("get_swim_bounds"):
		cast_swim_bounds = zone.get_swim_bounds()

	if zone.has_method("get_shore_boundary"):
		cast_shore_boundary = zone.get_shore_boundary()

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

	var cast_bait: Node3D = caster.perform_cast(
		captured_power,
		cast_direction,
		zone.get_water_y(),
		zone.get_bottom_y(),
		cast_lure,
		cast_swim_bounds,
		cast_shore_boundary,
		selected_curve
	)

	if not is_instance_valid(cast_bait):
		push_warning(
			"Fishing: caster failed to create bait; keeping cast selection active."
		)
		return

	# Only a successfully created bait can consume prepared bait. The cast remains
	# legal if no prepared bait is owned or if its persistence transaction fails.
	last_prepared_bait_use_result = {}
	if fishing_prepared_bait_service != null:
		last_prepared_bait_use_result = (
			fishing_prepared_bait_service.try_begin_cast(true)
		)

	# Only a successfully created bait commits the cast visually/state-wise.
	power.confirm_locked()
	throw_preview.hide_preview()

	encounter.set_active_bait_data(cast_lure)
	camera_rig.arm_fishing_follow(
		cast_bait,
		camera_follow_direction,
		zone.get_water_y()
	)

	locked_cast_power = 0.0
	buffered_prep_power = -1.0
	cast_curve_value = 0.0
	preview_cast_curve_value = 0.0
	cast_power_locked = false
	cast_input_gate.reset(
		Input.is_action_pressed(
			"enter_fishing"
		)
	)
	bait_landed_during_throw = false

	phase = Phase.THROW
	sprite_director.play(&"Throw")
	cast_started.emit()
