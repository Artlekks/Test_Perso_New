extends Node
## Calendar-driven, presentation-neutral weather schedule for the entire world.
## GameClock owns time/persistence; this service only derives weather from it.
## No fish multipliers or visual effects are applied here.

signal weather_changed(snapshot: Dictionary)

const CONDITION_CALM: StringName = &"calm"
const CONDITION_RAIN: StringName = &"rain"
const CONDITION_TEMPEST: StringName = &"tempest"
const DEFAULT_GAME_MINUTE: int = 480

## Each window is in game minutes. At the standard clock rate, 240 game
## minutes equal 20 real minutes. Consecutive equal conditions merge naturally.
@export_range(60, 720, 30) var weather_window_minutes: int = 240
@export_range(0, 80, 1) var rain_chance_percent: int = 27
@export_range(0, 40, 1) var tempest_chance_percent: int = 8

var _clock: Node = null
var _last_condition_id: StringName = &""


func _ready() -> void:
	_bind_clock()


func _exit_tree() -> void:
	if is_instance_valid(_clock):
		var callback: Callable = Callable(self, "_on_clock_changed")
		if _clock.has_signal("clock_changed") and _clock.is_connected("clock_changed", callback):
			_clock.disconnect("clock_changed", callback)
	_clock = null


func _bind_clock() -> void:
	var clock: Node = get_node_or_null("/root/GameClock")
	if clock == _clock:
		return
	_clock = clock
	if is_instance_valid(_clock) and _clock.has_signal("clock_changed"):
		var callback: Callable = Callable(self, "_on_clock_changed")
		if not _clock.is_connected("clock_changed", callback):
			_clock.connect("clock_changed", callback)
	_refresh_weather()


func _on_clock_changed(_snapshot: Dictionary) -> void:
	_refresh_weather()


func _refresh_weather() -> void:
	var snapshot: Dictionary = get_snapshot()
	var condition: StringName = StringName(snapshot.get("condition_id", "calm"))
	if condition == _last_condition_id:
		return
	_last_condition_id = condition
	weather_changed.emit(snapshot)


func get_snapshot() -> Dictionary:
	var minute: int = DEFAULT_GAME_MINUTE
	if is_instance_valid(_clock) and _clock.has_method("get_snapshot"):
		var clock_state: Dictionary = _clock.call("get_snapshot") as Dictionary
		minute = int(clock_state.get("total_minutes", DEFAULT_GAME_MINUTE))
	return get_snapshot_at_minutes(minute)


func get_snapshot_at_minutes(total_minutes: int) -> Dictionary:
	var interval: int = maxi(weather_window_minutes, 60)
	var minute: int = maxi(total_minutes, 0)
	var window: int = floori(float(minute) / float(interval))
	var condition: StringName = _condition_for_window(window)
	var prior: StringName = _condition_for_window(maxi(0, window - 1))
	var remaining: int = interval - (minute % interval)
	var label: String = "Calm"
	var tags: PackedStringArray = PackedStringArray(["calm", "clear"])
	match condition:
		CONDITION_RAIN:
			label = "Rain"
			tags = PackedStringArray(["rain", "wet"])
		CONDITION_TEMPEST:
			label = "Tempest"
			tags = PackedStringArray(["tempest", "storm", "rough_water"])
	return {
		"available": true,
		"condition_id": condition,
		"display": label,
		"tags": tags,
		"previous_condition_id": prior,
		"transition_progress": float(minute % interval) / float(interval),
		"minutes_until_next_window": remaining,
		"window": window,
		"total_minutes": minute,
	}


func _condition_for_window(window: int) -> StringName:
	# Int-only, stateless pseudo-random schedule: not affected by FPS, changing
	# scenes, window size, save/load, randomize(), or global RNG calls.
	var slot: int = maxi(0, window)
	var value: int = posmod((slot + 29) * 48271 + (slot + 1) * (slot + 7) * 13 + 1777, 1009) % 100
	var tempest_limit: int = clampi(tempest_chance_percent, 0, 40)
	var rain_limit: int = clampi(rain_chance_percent, 0, 80)
	if value < tempest_limit:
		return CONDITION_TEMPEST
	if value < tempest_limit + rain_limit:
		return CONDITION_RAIN
	return CONDITION_CALM
