extends Node
## Runtime-only scheduling/orchestration. Encounter owns selection and rewards.
signal cancelled(reason: String)
signal opportunity_ready
enum State { IDLE, STARTING, FOCUS, READY, HANDOFF }
@export var focus_seconds := 1200.0
@export var opportunity_seconds := 300.0
@export_range(0.1,0.9,0.05) var cast_power := 0.65
var host: Node
var state := State.IDLE
var reason := ""
var elapsed := 0.0
var scheduled_at := 0.0
var opportunities := 0
var rng := RandomNumberGenerator.new()
var _fishing: WeakRef
var _water_started := 0
var _phase_time := 0.0
var _last_phase := -1
var _start_time := 0
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.randomize()
func current() -> Node:
	return _fishing.get_ref() if _fishing != null else null
func is_ready() -> bool: return state in [State.READY,State.HANDOFF]
func begin() -> bool:
	var fishing: Node = host.game.get_node_or_null("Game/Fishing") if is_instance_valid(host.game) else null
	if fishing == null or get_tree().paused:
		reason = "Close the current interface before focusing."
		return false
	if state != State.IDLE:
		reason = "Resolve or cancel the current opportunity first."
		return false
	if fishing.game_mode.is_fishing() and fishing.phase not in [fishing.Phase.AIM,fishing.Phase.IN_WATER]:
		reason = "Finish the current cast/fight first."
		return false
	if fishing.loadout.get_selected_lure() == null or fishing.loadout.get_selected_rod() == null:
		reason = "Equip an owned rod and lure first."
		return false
	if not fishing.fishing_inventory.owns_lure(fishing.loadout.get_selected_lure()) or not fishing.fishing_inventory.owns_rod(fishing.loadout.get_selected_rod()):
		reason = "The selected fishing gear is not owned."
		return false
	if fishing.game_mode.is_exploration():
		var exploration: Node = host.game.get_node("Game/Exploration")
		var zone: Node = exploration.fish_zone
		if zone == null or not zone.overlaps_body(fishing.player):
			reason = "Stand at a fishing spot before starting Passive."
			return false
		# Autonomous entry may face the water, but never moves the physical feet.
		var heading: Vector3 = zone.get_water_forward()
		fishing.player.rotation.y = atan2(heading.x,heading.z)
		if not zone.can_player_fish(fishing.player): return false
	if not fishing.encounter.acquire_opportunity_schedule(self):
		reason = "A bite or fight is already active."
		return false
	_fishing = weakref(fishing)
	state = State.STARTING
	_start_time = Time.get_ticks_msec()
	_last_phase = -1
	_phase_time = 0
	elapsed = 0
	opportunities = 0
	reason = "Preparing cast"
	if fishing.game_mode.is_exploration(): fishing.game_mode.enter_fishing(host.game.get_node("Game/Exploration").fish_zone)
	return true
func activate() -> void:
	if state == State.READY:
		state = State.HANDOFF # Persistent hook window survives presentation changes.
	else: cancel("active",false)
func cancel(why: String, discard_cast := false) -> void:
	var was_active := state != State.IDLE
	var fishing := current()
	if is_instance_valid(fishing):
		fishing.encounter.release_opportunity_schedule(self,not discard_cast)
		if discard_cast and fishing.phase == fishing.Phase.IN_WATER: fishing._cancel_water_cast_to_aim()
	_fishing = null
	state = State.IDLE
	reason = why
	elapsed = 0
	if was_active and why != "active": cancelled.emit(why)
func _process(delta: float) -> void:
	if state == State.IDLE: return
	var fishing := current()
	if not is_instance_valid(fishing) or not fishing.game_mode.is_fishing(): cancel("fishing ended",false); return
	if state == State.HANDOFF:
		if fishing.phase != fishing.Phase.IN_WATER: cancel("handoff complete",false)
		return
	if state == State.READY:
		if not fishing.encounter.bite_active: cancel("opportunity ended",false)
		return
	if state == State.STARTING:
		if Time.get_ticks_msec()-_start_time > 30000: cancel("Unable to complete the cast",true); return
		if get_tree().paused: return
		if fishing.phase != _last_phase: _last_phase = fishing.phase; _phase_time = 0
		_phase_time += delta
		if fishing.phase == fishing.Phase.IN_WATER:
			state = State.FOCUS
			_water_started = Time.get_ticks_msec()
			scheduled_at = maxf(0,focus_seconds)+rng.randf_range(0,maxf(0,opportunity_seconds))
			reason = "Focus"
		elif fishing.phase == fishing.Phase.AIM and _phase_time > 0.15: fishing.request_cast_confirm()
		elif fishing.phase == fishing.Phase.CHARGE and fishing.power.value >= cast_power: fishing.request_cast_confirm()
		elif fishing.phase == fishing.Phase.CURVE and _phase_time > 0.2: fishing.request_cast_confirm()
	elif state == State.FOCUS:
		if fishing.phase != fishing.Phase.IN_WATER: cancel("cast ended",false); return
		elapsed = float(Time.get_ticks_msec()-_water_started)/1000.0
		if elapsed >= scheduled_at and not get_tree().paused:
			opportunities += 1
			if fishing.encounter.request_persistent_opportunity(self):
				state = State.READY
				reason = "FISH READY — switch Active and confirm to hook"
				opportunity_ready.emit()
			else: cancel("No eligible fish for this lure/depth at this spot",false)
func _exit_tree() -> void: cancel("shutdown",false)
