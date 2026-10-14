extends Control
## Gameplay-viewport-only presentation: wind readout and optional weather.
## No gameplay physics, camera, input, clock or environment state is modified.
## Future effect families can be added through _resolve_weather_mode/_draw_weather.

@export_category("Wind Readout")
@export var show_wind_readout: bool = true
@export_range(0.0, 100.0, 1.0) var readout_top_margin: float = 12.0
@export_range(0.5, 3.0, 0.1) var readout_scale: float = 1.0
@export var speed_units: String = "m/s" # Use "mph" if desired.

@export_category("Atmosphere Preview")
## auto uses authored condition tags; change for a visual-only preview.
@export_enum("auto", "clear", "rain", "storm", "snow", "sandstorm") var preview_weather: String = "auto"
@export_range(0.0, 1.0, 0.05) var weather_opacity: float = 0.6
@export_range(0, 120, 1) var weather_particle_count: int = 45
## The world-owned 3D rain is authoritative. Keep this legacy renderer
## available for future 2D-only scenes, but OFF in the fishing world.
@export var draw_legacy_weather_particles: bool = false

const CARD_BG := Color(0.06, 0.14, 0.19, 0.69)
const CARD_BORDER := Color(0.81, 0.73, 0.57, 0.75)
const CARD_TEXT := Color(1.0, 0.95, 0.80)
const WEATHER_SEED: int = 7102026

var _fishing: Node = null
var _direction_radians: float = 0.0
var _wind_speed: float = 0.0
var _wind_valid: bool = false
var _weather_mode: String = "clear"
var _particles: Array[Vector2] = []
var _speeds: PackedFloat32Array = PackedFloat32Array()
var _animation_time: float = 0.0
var _wind_poll_left: float = 0.0
var _weather_poll_left: float = 0.0

func bind_fishing(fishing: Node) -> void:
	_fishing = fishing

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_seed_particles()
	set_process(true)

func _process(delta: float) -> void:
	if not is_instance_valid(_fishing):
		visible = false
		return
	# This readout belongs in the gameplay viewport only, while fishing.
	var state: int = int(_fishing.get("phase"))
	visible = state != 0 # Phase.INACTIVE (the gameplay scene owns this overlay)
	if not visible:
		return
	_animation_time += delta
	_wind_poll_left -= delta
	_weather_poll_left -= delta
	if _wind_poll_left <= 0.0:
		_wind_poll_left = 0.1
		_read_wind(delta)
	if _weather_poll_left <= 0.0:
		_weather_poll_left = 0.5
		_weather_mode = _resolve_weather_mode()
	queue_redraw()

func _read_wind(delta: float) -> void:
	var wind: Node = get_tree().root.get_node_or_null("GameWind")
	if wind == null or not wind.has_method("get_snapshot"):
		_wind_valid = false
		return
	var snapshot: Dictionary = wind.call("get_snapshot") as Dictionary
	_wind_valid = bool(snapshot.get("available", false))
	if not _wind_valid:
		return
	_wind_speed = maxf(0.0, float(snapshot.get("speed_mps", 0.0)))
	var target: float = deg_to_rad(float(snapshot.get("bearing_degrees", 0.0)))
	# Present wind relative to the player's camera, not a fixed compass icon.
	# This does NOT move or modify the camera; it only reads its basis.
	var velocity_2d: Vector2 = snapshot.get("velocity_xz", Vector2.ZERO)
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera != null and velocity_2d.length_squared() > 0.00001:
		var world_direction: Vector3 = Vector3(velocity_2d.x, 0.0, velocity_2d.y).normalized()
		var projected: Vector2 = Vector2(
			world_direction.dot(camera.global_basis.x),
			-world_direction.dot(camera.global_basis.y)
		)
		if projected.length_squared() > 0.00001:
			target = atan2(projected.x, -projected.y)
	# Continuous angular interpolation, no snapping at 0/360 degrees.
	_direction_radians = lerp_angle(_direction_radians, target, clampf(delta * 4.0 + 0.18, 0.0, 1.0))

func _resolve_weather_mode() -> String:
	if preview_weather != "auto":
		return preview_weather
	var env: Node = _fishing.get("fishing_environment_service") as Node
	if env == null or not env.has_method("get_active_tags"):
		return "clear"
	var tags: PackedStringArray = env.call("get_active_tags") as PackedStringArray
	if tags.has("tempest") or tags.has("storm"):
		return "storm"
	if tags.has("rain"):
		return "rain"
	if tags.has("snow") or tags.has("blizzard"):
		return "snow"
	if tags.has("sandstorm") or tags.has("dust"):
		return "sandstorm"
	return "clear"

func _seed_particles() -> void:
	_particles.clear()
	_speeds.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = WEATHER_SEED
	for index in range(120):
		_particles.append(Vector2(rng.randf(), rng.randf()))
		_speeds.append(rng.randf_range(0.66, 1.45))

func _draw() -> void:
	if draw_legacy_weather_particles and _weather_mode != "clear":
		_draw_weather()
	if show_wind_readout:
		_draw_wind_readout()

func _draw_wind_readout() -> void:
	var card_width: float = 124.0 * readout_scale
	var card_height: float = 64.0 * readout_scale
	var card: Rect2 = Rect2(Vector2((size.x - card_width) * 0.5, readout_top_margin), Vector2(card_width, card_height))
	draw_rect(card, CARD_BG, true)
	draw_rect(card, CARD_BORDER, false, 1.0)
	var font: Font = ThemeDB.fallback_font
	var label: String = "WIND"
	var speed: String = "N/A"
	if _wind_valid:
		var value: float = _wind_speed * (2.236936 if speed_units == "mph" else 1.0)
		speed = "%.1f %s" % [value, speed_units]
	draw_string(font, Vector2(card.position.x + 7.0 * readout_scale, card.position.y + 17.0 * readout_scale), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, maxi(9, int(10.0 * readout_scale)), CARD_TEXT)
	draw_string(font, Vector2(card.position.x + 7.0 * readout_scale, card.position.y + 34.0 * readout_scale), speed, HORIZONTAL_ALIGNMENT_LEFT, -1.0, maxi(10, int(13.0 * readout_scale)), CARD_TEXT)
	# Small original placeholder wind icon below the speed (replace with your sprite later).
	for line_index in range(2):
		var line_y: float = card.position.y + (46.0 + float(line_index) * 7.0) * readout_scale
		var start: Vector2 = Vector2(card.position.x + 9.0 * readout_scale, line_y)
		draw_line(start, start + Vector2(38.0 * readout_scale, 0.0), Color(0.72, 0.89, 0.90, 0.78), 1.0, false)
		draw_line(start + Vector2(35.0 * readout_scale, 0.0), start + Vector2(42.0 * readout_scale, -3.0 * readout_scale), Color(0.72, 0.89, 0.90, 0.78), 1.0, false)
	# Faux-depth wind arrow: darker offset silhouette behind a bright triangular head.
	# The arrow points where the air is going, as does GameWind.velocity_xz.
	var pivot: Vector2 = card.position + Vector2(card_width - 25.0 * readout_scale, 33.0 * readout_scale)
	_draw_arrow(pivot + Vector2(1.5, 2.0), _direction_radians, Color(0.10, 0.12, 0.13, 0.9), readout_scale)
	_draw_arrow(pivot, _direction_radians, CARD_TEXT if _wind_valid else Color(0.55, 0.55, 0.55), readout_scale)

func _draw_arrow(center: Vector2, angle: float, color: Color, scale_factor: float) -> void:
	var direction := Vector2(sin(angle), -cos(angle))
	var sideways := Vector2(-direction.y, direction.x)
	var tip := center + direction * (15.0 * scale_factor)
	var tail := center - direction * (11.0 * scale_factor)
	var cross := center - direction * (1.0 * scale_factor)
	var arrow := PackedVector2Array([
		tip,
		cross + sideways * (7.0 * scale_factor),
		cross + sideways * (2.5 * scale_factor),
		tail + sideways * (2.5 * scale_factor),
		tail - sideways * (2.5 * scale_factor),
		cross - sideways * (2.5 * scale_factor),
		cross - sideways * (7.0 * scale_factor)
	])
	draw_colored_polygon(arrow, color)

func _draw_weather() -> void:
	var count: int = mini(weather_particle_count, _particles.size())
	var viewport_size: Vector2 = size
	if viewport_size.x <= 1.0 or viewport_size.y <= 1.0:
		return
	for index in range(count):
		var seed_pos: Vector2 = _particles[index]
		var speed: float = _speeds[index]
		var drift: float = _animation_time * speed
		match _weather_mode:
			"rain", "storm":
				var x: float = fposmod(seed_pos.x * viewport_size.x - drift * (80.0 if _weather_mode == "storm" else 34.0), viewport_size.x)
				var y: float = fposmod(seed_pos.y * viewport_size.y + drift * (285.0 if _weather_mode == "storm" else 195.0), viewport_size.y)
				var length: float = 14.0 if _weather_mode == "storm" else 9.0
				draw_line(Vector2(x, y), Vector2(x - length * 0.28, y + length), Color(0.72, 0.85, 0.97, weather_opacity * 0.55), 1.0, false)
			"snow":
				var x: float = fposmod(seed_pos.x * viewport_size.x + sin(_animation_time * 0.75 + float(index)) * 18.0, viewport_size.x)
				var y: float = fposmod(seed_pos.y * viewport_size.y + drift * 28.0, viewport_size.y)
				draw_circle(Vector2(x, y), 1.2, Color(0.95, 0.97, 1.0, weather_opacity * 0.8))
			"sandstorm":
				var x: float = fposmod(seed_pos.x * viewport_size.x + drift * 160.0, viewport_size.x)
				var y: float = fposmod(seed_pos.y * viewport_size.y + drift * 14.0, viewport_size.y)
				draw_line(Vector2(x, y), Vector2(x + 8.0, y - 1.0), Color(0.78, 0.66, 0.42, weather_opacity * 0.55), 1.0, false)
