extends Node3D
class_name FishShadowPresence

const DefaultLongFishShadowScene := preload("res://actors/FishShadow.tscn")
const DefaultRoundFishShadowScene := preload("res://actors/FishShadowRound.tscn")
const DefaultWideFishShadowScene := preload("res://actors/FishShadowWide.tscn")
const DefaultSquidFishShadowScene := preload("res://actors/FishShadowSquid.tscn")
const DefaultJellyFishShadowScene := preload("res://actors/FishShadowJelly.tscn")
const DefaultAmbientFishProfile := preload("res://data/bof4/ambient_profiles/default.tres")

@export_category("Visual Profiles")
## Alternate shadow scenes are optional. Every scene must use FishShadowActor
## as its root script so gameplay behavior stays shared across silhouettes.
## Missing profiles automatically fall back to the current long-fish shadow.
@export var long_fish_shadow_scene: PackedScene = DefaultLongFishShadowScene
@export var round_shadow_scene: PackedScene = DefaultRoundFishShadowScene
@export var wide_shadow_scene: PackedScene = DefaultWideFishShadowScene
@export var squid_shadow_scene: PackedScene = DefaultSquidFishShadowScene
@export var jelly_shadow_scene: PackedScene = DefaultJellyFishShadowScene

@export_category("Presence")
@export var enabled: bool = true

## Used only when the active FishingSpotData has no ambient_profile assigned.
## Spot-specific population tuning belongs in FishingSpotData.ambient_profile.
@export var default_ambient_profile: AmbientFishProfile = DefaultAmbientFishProfile

@export_range(2.0, 30.0, 0.5)
var population_reconsider_time_min: float = 10.0

@export_range(2.0, 30.0, 0.5)
var population_reconsider_time_max: float = 18.0

@export_range(0.1, 8.0, 0.1)
var respawn_delay_min: float = 1.5

@export_range(0.1, 8.0, 0.1)
var respawn_delay_max: float = 4.0

@export_range(2.0, 40.0, 0.5)
var shadow_lifetime_min: float = 16.0

@export_range(2.0, 40.0, 0.5)
var shadow_lifetime_max: float = 30.0

@export_category("Movement")
@export_range(0.05, 2.0, 0.05)
var small_fish_speed: float = 0.44

@export_range(0.05, 2.0, 0.05)
var large_fish_speed: float = 0.24

@export_range(0.0, 0.5, 0.01)
var speed_variation: float = 0.10

@export_category("Ambient Readability")
## Ambient shadows are allowed to dive/fade, but if every live fish becomes
## effectively invisible for this long, bring one back toward a readable depth.
@export var readability_guard_enabled: bool = true

@export_range(0.25, 8.0, 0.25)
var no_readable_shadow_grace_time: float = 2.0

@export_category("Presentation")
@export_range(0.1, 3.0, 0.05)
var small_fish_scale: float = 0.72

@export_range(0.1, 3.0, 0.05)
var large_fish_scale: float = 1.12

var _fish_zone: Node = null
var _swim_bounds: FishSwimBounds = null
var _rng := RandomNumberGenerator.new()
var _spawned_shadows: Array[FishShadowActor] = []
var _desired_count: int = 1
var _population_reconsider_remaining: float = 0.0
var _spawn_remaining: float = 0.0
var _fight_shadow: FishShadowActor = null
var _no_readable_shadow_time: float = 0.0
var _debug_forced_fish: FishData = null
var _debug_shadow_count_override: int = 0
var _ambient_profile: AmbientFishProfile = null


func _ready() -> void:
	_fish_zone = get_parent()
	_rng.randomize()

	if not enabled:
		visible = false
		set_process(false)
		return

	call_deferred("_initialize_presence")


func _process(delta: float) -> void:
	_cleanup_invalid_shadows()
	_population_reconsider_remaining -= delta
	_spawn_remaining -= delta

	if _population_reconsider_remaining <= 0.0:
		_desired_count = _choose_population_count()
		_population_reconsider_remaining = _rng.randf_range(
			population_reconsider_time_min,
			maxf(population_reconsider_time_max, population_reconsider_time_min)
		)
		_trim_population_if_needed()

	if _get_ambient_shadow_count() < _desired_count and _spawn_remaining <= 0.0:
		_spawn_one_shadow()
		_spawn_remaining = _rng.randf_range(
			respawn_delay_min,
			maxf(respawn_delay_max, respawn_delay_min)
		)

	_update_readability_guard(delta)


func _initialize_presence() -> void:
	if _fish_zone == null:
		return

	if _fish_zone.has_method("get_swim_bounds"):
		_swim_bounds = _fish_zone.get_swim_bounds() as FishSwimBounds

	if _swim_bounds == null:
		var fallback_bounds := _fish_zone.get_node_or_null("FishSwimBounds")
		_swim_bounds = fallback_bounds as FishSwimBounds

	if _swim_bounds == null:
		push_warning("FishShadowPresence needs FishSwimBounds on its fish zone.")
		return

	_refresh_spot_identity()
	_desired_count = _choose_population_count()
	_population_reconsider_remaining = _rng.randf_range(
		population_reconsider_time_min,
		maxf(population_reconsider_time_max, population_reconsider_time_min)
	)

	# Spawn the initial population immediately. Later replacements are staggered.
	for _index in range(_desired_count):
		_spawn_one_shadow()


func get_shadows() -> Array[FishShadowActor]:
	_cleanup_invalid_shadows()
	return _spawned_shadows.duplicate()


func get_interested_shadow_near(
	world_position: Vector3,
	max_distance: float
) -> FishShadowActor:
	_cleanup_invalid_shadows()

	var nearest: FishShadowActor = null
	var nearest_distance := max_distance

	for shadow in _spawned_shadows:
		if not is_instance_valid(shadow):
			continue
		if not shadow.is_interested_near(world_position, max_distance):
			continue

		var offset := shadow.global_position - world_position
		offset.y = 0.0
		var distance := offset.length()

		if distance < nearest_distance:
			nearest = shadow
			nearest_distance = distance

	return nearest


func has_active_pre_bite_near(
	world_position: Vector3,
	max_distance: float
) -> bool:
	_cleanup_invalid_shadows()

	for shadow in _spawned_shadows:
		if not is_instance_valid(shadow):
			continue
		if not shadow.has_method("is_pre_bite_active_near"):
			continue
		if shadow.is_pre_bite_active_near(world_position, max_distance):
			return true

	return false


func start_fight_shadow(
	fish: FishData,
	bait: Node3D,
	existing_shadow: FishShadowActor = null,
	size_multiplier: float = 1.0
) -> FishShadowActor:
	if _swim_bounds == null or not is_instance_valid(bait):
		return null

	if is_instance_valid(_fight_shadow) and _fight_shadow != existing_shadow:
		_fight_shadow.release_from_hooked_bait(false)

	var shadow := existing_shadow

	if not is_instance_valid(shadow):
		shadow = _instantiate_shadow_for_fish(fish)
		if shadow == null:
			return null

		add_child(shadow)
		shadow.expired.connect(_on_shadow_expired)

		var size_t := _get_size_ratio(fish)
		var speed := lerpf(small_fish_speed, large_fish_speed, size_t)
		var visual_scale := lerpf(small_fish_scale, large_fish_scale, size_t)

		shadow.configure(
			fish,
			_swim_bounds,
			_get_water_y(),
			0.22,
			speed,
			visual_scale,
			9999.0,
			_rng.randi()
		)

		_spawned_shadows.append(shadow)

	_fight_shadow = shadow
	shadow.attach_to_hooked_bait(bait, fish, size_multiplier)
	return shadow


func _instantiate_shadow_for_fish(fish: FishData) -> FishShadowActor:
	var scene := _get_shadow_scene_for_fish(fish)
	if scene == null:
		push_warning("FishShadowPresence has no usable shadow scene.")
		return null

	var instance := scene.instantiate()
	var shadow := instance as FishShadowActor

	if shadow == null:
		if is_instance_valid(instance):
			instance.queue_free()
		push_warning(
			"Fish shadow profile scene must use FishShadowActor as its root script."
		)
		return null

	return shadow


func _get_shadow_scene_for_fish(fish: FishData) -> PackedScene:
	var profile := FishData.ShadowVisualProfile.LONG_FISH

	if fish != null:
		profile = fish.shadow_visual_profile

	var scene: PackedScene = null

	match profile:
		FishData.ShadowVisualProfile.ROUND:
			scene = round_shadow_scene
		FishData.ShadowVisualProfile.WIDE:
			scene = wide_shadow_scene
		FishData.ShadowVisualProfile.SQUID:
			scene = squid_shadow_scene
		FishData.ShadowVisualProfile.JELLY:
			scene = jelly_shadow_scene
		_:
			scene = long_fish_shadow_scene

	if scene != null:
		return scene

	# During the architecture pass only LONG_FISH has authored visuals. This
	# fallback lets us tag unusual species now without changing their current
	# appearance until their dedicated scenes are added later.
	if long_fish_shadow_scene != null:
		return long_fish_shadow_scene

	return DefaultLongFishShadowScene


func end_fight_shadow(dive_away: bool = true) -> void:
	if not is_instance_valid(_fight_shadow):
		_fight_shadow = null
		return

	_fight_shadow.release_from_hooked_bait(dive_away)
	_fight_shadow = null


func set_debug_overrides(fish: FishData, shadow_count: int) -> void:
	var next_count := clampi(shadow_count, 0, 32)
	if _debug_forced_fish == fish and _debug_shadow_count_override == next_count:
		return

	_debug_forced_fish = fish
	_debug_shadow_count_override = next_count

	# QA overrides can be assigned before deferred initialization resolves
	# FishSwimBounds. Store immediately, rebuild once when the system is ready.
	if _swim_bounds != null:
		rebuild_population()


func set_debug_forced_fish(fish: FishData) -> void:
	set_debug_overrides(fish, _debug_shadow_count_override)


func get_debug_forced_fish() -> FishData:
	return _debug_forced_fish


## Runtime-only QA override. 0 means the active spot AmbientFishProfile stays
## authoritative. A positive value forces an exact ambient population without
## mutating the spot/profile resource in the editor.
func set_debug_shadow_count_override(count: int) -> void:
	set_debug_overrides(_debug_forced_fish, count)


func get_debug_shadow_count_override() -> int:
	return _debug_shadow_count_override


func get_population_debug_counts() -> Vector2i:
	return Vector2i(
		_get_ambient_shadow_count(),
		_get_readable_ambient_shadow_count()
	)


func rebuild_population() -> void:
	_refresh_spot_identity()
	_clear_population()
	_desired_count = _choose_population_count()

	for _index in range(_desired_count):
		_spawn_one_shadow()


func _spawn_one_shadow() -> void:
	if _swim_bounds == null:
		return

	var profile := _get_active_ambient_profile()
	var spawn_cap := _get_spawn_cap(profile)
	if _get_ambient_shadow_count() >= spawn_cap:
		return

	var population := _get_population()
	var fish: FishData = _debug_forced_fish

	if fish == null:
		fish = _pick_weighted_fish(population)

	var shadow := _instantiate_shadow_for_fish(fish)

	if shadow == null:
		return

	add_child(shadow)
	shadow.expired.connect(_on_shadow_expired)

	var size_t := _get_size_ratio(fish)
	var speed := lerpf(small_fish_speed, large_fish_speed, size_t)
	speed *= _rng.randf_range(1.0 - speed_variation, 1.0 + speed_variation)
	speed *= profile.speed_multiplier

	var visual_scale := lerpf(small_fish_scale, large_fish_scale, size_t)
	var initial_depth := clampf(
		_pick_visual_depth(fish) + profile.depth_bias,
		0.05,
		0.82
	)
	var lifetime := _rng.randf_range(
		shadow_lifetime_min,
		maxf(shadow_lifetime_max, shadow_lifetime_min)
	)
	lifetime *= profile.lifetime_multiplier

	if shadow.has_method("set_ambient_depth_bias"):
		shadow.set_ambient_depth_bias(profile.depth_bias)
	shadow.configure(
		fish,
		_swim_bounds,
		_get_water_y(),
		initial_depth,
		speed,
		visual_scale,
		lifetime,
		_rng.randi()
	)

	# A manual QA shadow-count override means "show me exactly this many
	# shadows". Keep those test shadows in a readable depth band so the debug
	# control measures presentation rather than hidden/deep population members.
	if _debug_shadow_count_override > 0:
		shadow.set_debug_force_readable(true)

	_spawned_shadows.append(shadow)


func _trim_population_if_needed() -> void:
	var excess := _get_ambient_shadow_count() - _desired_count

	while excess > 0:
		var chosen: FishShadowActor = null

		# Prefer fading a fish that is not currently investigating the lure.
		for shadow in _spawned_shadows:
			if (
				is_instance_valid(shadow)
				and not shadow.is_interested_in_bait()
				and not shadow.is_hooked_tracking()
			):
				chosen = shadow
				break

		if chosen == null:
			break

		chosen.request_expire()
		_spawned_shadows.erase(chosen)
		excess -= 1


func _on_shadow_expired(shadow: FishShadowActor) -> void:
	_spawned_shadows.erase(shadow)
	if shadow == _fight_shadow:
		_fight_shadow = null


func _cleanup_invalid_shadows() -> void:
	for index in range(_spawned_shadows.size() - 1, -1, -1):
		if not is_instance_valid(_spawned_shadows[index]):
			_spawned_shadows.remove_at(index)


func _get_ambient_shadow_count() -> int:
	_cleanup_invalid_shadows()
	var count := 0

	for shadow in _spawned_shadows:
		if not is_instance_valid(shadow):
			continue
		if shadow.is_hooked_tracking():
			continue
		count += 1

	return count


func _get_readable_ambient_shadow_count() -> int:
	_cleanup_invalid_shadows()
	var count := 0

	for shadow in _spawned_shadows:
		if not is_instance_valid(shadow):
			continue
		if shadow.is_hooked_tracking():
			continue
		if shadow.has_method("is_ambient_readable") and shadow.is_ambient_readable():
			count += 1

	return count


func _update_readability_guard(delta: float) -> void:
	if not readability_guard_enabled:
		_no_readable_shadow_time = 0.0
		return

	var ambient_count := _get_ambient_shadow_count()
	if ambient_count <= 0:
		_no_readable_shadow_time = 0.0
		return

	if _get_readable_ambient_shadow_count() > 0:
		_no_readable_shadow_time = 0.0
		return

	_no_readable_shadow_time += delta
	if _no_readable_shadow_time < no_readable_shadow_grace_time:
		return

	_no_readable_shadow_time = 0.0
	_restore_one_readable_shadow()


func _restore_one_readable_shadow() -> void:
	for shadow in _spawned_shadows:
		if not is_instance_valid(shadow):
			continue
		if shadow.is_hooked_tracking():
			continue
		if shadow.has_method("restore_readable_presence"):
			shadow.restore_readable_presence()
			return


func _clear_population() -> void:
	for shadow in _spawned_shadows:
		if is_instance_valid(shadow):
			shadow.queue_free()

	_spawned_shadows.clear()
	_fight_shadow = null


func _choose_population_count() -> int:
	if _debug_shadow_count_override > 0:
		return _debug_shadow_count_override

	var profile := _get_active_ambient_profile()
	var minimum := profile.get_min_count()
	var maximum := profile.get_max_count()

	var options: Array[int] = []
	var weights: Array[float] = []

	for count in range(minimum, maximum + 1):
		options.append(count)
		weights.append(profile.get_weight_for_count(count))

	if options.is_empty():
		return minimum

	var total := 0.0
	for weight in weights:
		total += weight

	# A zeroed/missing weight table should never make the system unusable.
	# Fall back to an even choice across the configured min/max range.
	if total <= 0.0:
		return options[_rng.randi_range(0, options.size() - 1)]

	var roll := _rng.randf_range(0.0, total)
	var cumulative := 0.0

	for index in range(options.size()):
		cumulative += weights[index]
		if roll <= cumulative:
			return options[index]

	return options[options.size() - 1]


func _get_spawn_cap(profile: AmbientFishProfile) -> int:
	if _debug_shadow_count_override > 0:
		return _debug_shadow_count_override
	return profile.get_max_count()


func _refresh_spot_identity() -> void:
	_ambient_profile = default_ambient_profile

	if _fish_zone == null:
		return

	var spot: FishingSpotData = null
	if _fish_zone.has_method("get_fishing_spot"):
		spot = _fish_zone.get_fishing_spot() as FishingSpotData

	if spot != null and spot.get_ambient_profile() != null:
		_ambient_profile = spot.get_ambient_profile()


func _get_active_ambient_profile() -> AmbientFishProfile:
	if _ambient_profile != null:
		return _ambient_profile
	if default_ambient_profile != null:
		return default_ambient_profile
	return DefaultAmbientFishProfile


func _get_water_y() -> float:
	if _fish_zone != null and _fish_zone.has_method("get_water_y"):
		return float(_fish_zone.get_water_y())

	return global_position.y


func _get_population() -> Array[FishSpawnEntry]:
	if _fish_zone != null and _fish_zone.has_method("get_fish_population"):
		return _fish_zone.get_fish_population()

	return []


func _pick_weighted_fish(population: Array[FishSpawnEntry]) -> FishData:
	if population.is_empty():
		return null

	var total_weight := 0.0

	for entry in population:
		if entry == null or entry.fish == null:
			continue
		total_weight += maxf(entry.weight, 0.0)

	if total_weight <= 0.0:
		for entry in population:
			if entry != null and entry.fish != null:
				return entry.fish
		return null

	var roll := _rng.randf_range(0.0, total_weight)
	var cumulative := 0.0

	for entry in population:
		if entry == null or entry.fish == null:
			continue
		cumulative += maxf(entry.weight, 0.0)
		if roll <= cumulative:
			return entry.fish

	for index in range(population.size() - 1, -1, -1):
		var fallback_entry := population[index]
		if fallback_entry != null and fallback_entry.fish != null:
			return fallback_entry.fish

	return null


func _get_size_ratio(fish: FishData) -> float:
	if fish == null:
		return _rng.randf_range(0.15, 0.55)

	return clampf(inverse_lerp(18.0, 187.0, fish.average_size), 0.0, 1.0)


func _pick_visual_depth(fish: FishData) -> float:
	if fish == null:
		return _rng.randf_range(0.15, 0.60)

	var depth_min := clampf(
		minf(fish.preferred_depth_min, fish.preferred_depth_max),
		0.0,
		1.0
	)
	var depth_max := clampf(
		maxf(fish.preferred_depth_min, fish.preferred_depth_max),
		0.0,
		1.0
	)

	# Initial ambient shadows must be readable at 320x240. They can dive/fade
	# naturally after spawning, but do not allow every deep-preferring species
	# to begin nearly invisible.
	var sampled := _rng.randf_range(depth_min, depth_max)
	return clampf(sampled, 0.12, 0.52)
