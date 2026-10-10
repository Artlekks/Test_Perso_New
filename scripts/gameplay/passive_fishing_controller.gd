extends Node
## Runtime-only scheduling/orchestration. Encounter owns selection and rewards.
signal cancelled(reason: String)
signal opportunity_ready
enum State { IDLE, STARTING, FOCUS, READY, HANDOFF, SETTLING, CONFIGURING }
@export var require_focus_confirmation := true
@export var timer_entry_delay := 1.0
var timer_entry: LineEdit
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
	timer_entry = LineEdit.new()
	timer_entry.name = "PassiveFocusTimer"
	timer_entry.text = "20:00"
	timer_entry.alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_entry.placeholder_text = "minutes or MM:SS"
	timer_entry.add_theme_font_override("font", preload("res://assets/fonts/BOF_Font_Refined.fnt"))
	timer_entry.add_theme_font_size_override("font_size", 32)
	timer_entry.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	timer_entry.text_submitted.connect(confirm_focus)
	host.add_child(timer_entry)
	timer_entry.hide()
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
	if is_instance_valid(timer_entry): timer_entry.hide()
	if is_instance_valid(timer_entry) and timer_entry.is_inside_tree(): timer_entry.release_focus()
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
			state = State.SETTLING
			_water_started = Time.get_ticks_msec()
			reason = "Waiting for focus duration"
			if not require_focus_confirmation: _start_focus(focus_seconds)
		elif fishing.phase == fishing.Phase.AIM and _phase_time > 0.15: fishing.request_cast_confirm()
		elif fishing.phase == fishing.Phase.CHARGE and fishing.power.value >= cast_power: fishing.request_cast_confirm()
		elif fishing.phase == fishing.Phase.CURVE and _phase_time > 0.2: fishing.request_cast_confirm()
	elif state == State.SETTLING:
		if float(Time.get_ticks_msec()-_water_started)/1000.0 >= timer_entry_delay:
			state = State.CONFIGURING
			timer_entry.text = _clock(focus_seconds)
			timer_entry.editable = true
			timer_entry.show()
			reason = "Click timer; Enter starts focus (K takes control)"
	elif state == State.CONFIGURING:
		if fishing.phase != fishing.Phase.IN_WATER: cancel("cast ended",false)
	elif state == State.FOCUS:
		if fishing.phase != fishing.Phase.IN_WATER: cancel("cast ended",false); return
		elapsed = float(Time.get_ticks_msec()-_water_started)/1000.0
		if timer_entry.visible: timer_entry.text = _clock(maxf(0, focus_seconds-elapsed))
		if elapsed >= scheduled_at and not get_tree().paused:
			opportunities += 1
			if fishing.encounter.request_persistent_opportunity(self):
				timer_entry.hide()
				state = State.READY
				reason = "FISH READY — switch Active and confirm to hook"
				host.set_mode(host.Mode.ACTIVE)
				opportunity_ready.emit()
			else: cancel("No eligible fish for this lure/depth at this spot",false)
func _exit_tree() -> void: cancel("shutdown",false)

static func parse_focus(text: String) -> float:
	var parts := text.strip_edges().split(":")
	if parts.size() == 1 and parts[0].is_valid_float(): return maxf(0, parts[0].to_float() * 60.0)
	if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
		var seconds := parts[1].to_int()
		if parts[0].to_int() >= 0 and seconds >= 0 and seconds < 60: return parts[0].to_int() * 60.0 + seconds
	return -1.0

func confirm_focus(text: String) -> void:
	if state != State.CONFIGURING: return
	var seconds := parse_focus(text)
	if seconds < 0: reason = "Use minutes or MM:SS"; return
	_start_focus(seconds)
	timer_entry.editable = false
	timer_entry.release_focus()

func _start_focus(seconds: float) -> void:
	focus_seconds = seconds
	elapsed = 0
	_water_started = Time.get_ticks_msec()
	scheduled_at = focus_seconds + rng.randf_range(0,maxf(0,opportunity_seconds))
	state = State.FOCUS
	reason = "Focus"

static func _clock(seconds: float) -> String:
	var whole := ceili(seconds)
	return "%02d:%02d" % [whole / 60, whole % 60]

func layout_timer(game_rect: Rect2) -> void:
	if not is_instance_valid(timer_entry): return
	if host.window_state == host.WindowState.COLLAPSED:
		timer_entry.hide()
		return
	var factor := game_rect.size.x / 640.0
	timer_entry.position = game_rect.position + Vector2(220, 500) * factor
	timer_entry.size = Vector2(200, 60) * factor
	timer_entry.add_theme_font_size_override("font_size", maxi(18, roundi(32 * factor)))
	timer_entry.visible = state in [State.CONFIGURING,State.FOCUS] and host.window_state != host.WindowState.COLLAPSED

func _input(event: InputEvent) -> void:
	if state != State.CONFIGURING: return
	if event.is_action_pressed("ui_accept") and not event.is_action_pressed("enter_fishing"):
		confirm_focus(timer_entry.text)
		get_viewport().set_input_as_handled()
