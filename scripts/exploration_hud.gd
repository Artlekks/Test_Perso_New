extends CanvasLayer

const LOCATION_FONT_REFINED := "res://assets/fonts/BOF_Font_Refined.fnt"
const LOCATION_FONT_FALLBACK := "res://assets/fonts/BOF_Font.fnt"

@onready var cast_ready_overlay: TextureRect = $Root/Compass/CastReadyOverlay
@onready var cast_ready_animation: AnimationPlayer = $Root/Compass/AnimationPlayer
@onready var menu: TextureRect = $Root/HelpPanel/Menu
@onready var menu_cast: TextureRect = $Root/HelpPanel/Menu_Cast
@onready var compass: Control = $Root/Compass
@onready var location: TextureRect = $Root/Location
@onready var help_panel: Control = $Root/HelpPanel

@export_category("References")
@export var exploration: Node

@onready var compass_needle: TextureRect = $Root/Compass/CompassNeedle

@export_category("Compass")
@export var needle_rotation_offset: float = 0.0
@export var camera_rig: Node3D
@export_category("Transitions")
@export var hide_duration: float = 0.35
@export var show_duration: float = 0.35
@export var offscreen_margin: float = 20.0
@export var game_mode: Node
@export var show_delay: float = 0.15

@export_category("Location Label")
@export var location_name_fallback: String = "Ocean Spot 3"
@export var location_font_size: int = 12
@export var location_text_offset: Vector2 = Vector2(-14.0, 1.0)

var compass_home: Vector2
var location_home: Vector2
var help_panel_home: Vector2

var hud_tween: Tween
var location_label: Label
var _location_fish_zone: Node = null

func _ready() -> void:
	set_cast_available(false)
	_setup_location_label()


	if exploration == null:
		push_warning("ExplorationHud: Exploration is not assigned.")
		return

	exploration.cast_availability_changed.connect(
		_on_cast_availability_changed
	)
	_bind_location_source()

	if camera_rig == null:
		push_warning("ExplorationHud: CameraRig is not assigned.")
		return

	camera_rig.heading_changed.connect(_on_camera_heading_changed)
	_on_camera_heading_changed(camera_rig.rotation.y)
	
	compass_home = compass.position
	location_home = location.position
	help_panel_home = help_panel.position

	camera_rig.exploration_view_started.connect(_show_exploration_hud)

	if game_mode != null:
		game_mode.mode_changed.connect(_on_mode_changed)
		
func _setup_location_label() -> void:
	location_label = location.get_node_or_null("LocationLabel") as Label
	var created_at_runtime := false

	if location_label == null:
		location_label = Label.new()
		location_label.name = "LocationLabel"
		location.add_child(location_label)
		created_at_runtime = true

	location_label.z_index = 1
	location_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	location_label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	location_label.clip_text = false

	var font_path := LOCATION_FONT_FALLBACK
	if ResourceLoader.exists(LOCATION_FONT_REFINED):
		font_path = LOCATION_FONT_REFINED

	var location_font := load(font_path) as Font
	if location_font != null:
		location_label.add_theme_font_override("font", location_font)
	location_label.add_theme_font_size_override("font_size", location_font_size)

	# Layout belongs to the scene/Inspector. We only supply fallback layout
	# when the node does not exist and has to be created at runtime.
	if created_at_runtime:
		location_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		location_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

		var label_size := location.size
		if location.texture != null:
			label_size = location.texture.get_size()

		location_label.position = location_text_offset
		location_label.size = label_size

	location_label.text = location_name_fallback


func _bind_location_source() -> void:
	_location_fish_zone = null

	if exploration != null:
		var zone_value: Variant = exploration.get("fish_zone")
		if zone_value is Node:
			_location_fish_zone = zone_value as Node

	if _location_fish_zone != null and _location_fish_zone.has_signal("fishing_spot_changed"):
		var callback := Callable(self, "_on_fishing_spot_changed")
		if not _location_fish_zone.is_connected("fishing_spot_changed", callback):
			_location_fish_zone.connect("fishing_spot_changed", callback)

	_refresh_location_label()


func _on_fishing_spot_changed(_spot: Variant) -> void:
	_refresh_location_label()


func _refresh_location_label() -> void:
	if location_label == null:
		return

	var raw_name := ""
	if _location_fish_zone != null:
		var spot: Variant = null
		if _location_fish_zone.has_method("get_fishing_spot"):
			spot = _location_fish_zone.call("get_fishing_spot")
		else:
			spot = _location_fish_zone.get("fishing_spot")

		if spot is Object:
			raw_name = str((spot as Object).get("spot_name"))

	if raw_name.strip_edges().is_empty():
		raw_name = location_name_fallback

	location_label.text = _format_location_name(raw_name)


func _format_location_name(raw_name: String) -> String:
	var cleaned := raw_name.strip_edges()
	if cleaned.is_empty() or cleaned.contains(" Spot "):
		return cleaned

	var words := cleaned.split(" ", false)
	if words.size() == 2 and words[1].is_valid_int():
		if words[0] == "Ocean" or words[0] == "River" or words[0] == "Lake":
			return "%s Spot %s" % [words[0], words[1]]

	return cleaned


func _on_cast_availability_changed(available: bool) -> void:
	set_cast_available(available)
	
func set_cast_available(available: bool) -> void:
	menu.visible = not available
	menu_cast.visible = available

	if available:
		cast_ready_overlay.visible = true

		if not cast_ready_animation.is_playing():
			cast_ready_animation.play("cast_ready")
	else:
		cast_ready_animation.stop()
		cast_ready_overlay.visible = false

func _on_camera_heading_changed(yaw: float) -> void:
	compass_needle.rotation_degrees = (
		-rad_to_deg(yaw)
		+ needle_rotation_offset
	)

func _on_mode_changed(new_mode: int) -> void:
	if new_mode == game_mode.Mode.FISHING:
		_hide_exploration_hud()
		
func _hide_exploration_hud() -> void:
	if hud_tween != null and hud_tween.is_valid():
		hud_tween.kill()

	var compass_target := Vector2(
		compass_home.x,
		-compass.size.y - offscreen_margin
	)

	var location_target := Vector2(
		location_home.x,
		-location.size.y - offscreen_margin
	)

	var viewport_width := get_viewport().get_visible_rect().size.x

	var help_target := Vector2(
		help_panel_home.x - viewport_width - offscreen_margin,
		help_panel_home.y
	)

	hud_tween = create_tween()
	hud_tween.set_trans(Tween.TRANS_CUBIC)
	hud_tween.set_ease(Tween.EASE_IN_OUT)

	hud_tween.parallel().tween_property(
		compass,
		"position",
		compass_target,
		hide_duration
	)

	hud_tween.parallel().tween_property(
		location,
		"position",
		location_target,
		hide_duration
	)

	hud_tween.parallel().tween_property(
		help_panel,
		"position",
		help_target,
		hide_duration
	)

func _show_exploration_hud() -> void:
	if show_delay > 0.0:
		await get_tree().create_timer(show_delay).timeout
		
	if hud_tween != null and hud_tween.is_valid():
		hud_tween.kill()

	hud_tween = create_tween()
	hud_tween.set_trans(Tween.TRANS_CUBIC)
	hud_tween.set_ease(Tween.EASE_IN_OUT)

	hud_tween.parallel().tween_property(
		compass,
		"position",
		compass_home,
		show_duration
	)

	hud_tween.parallel().tween_property(
		location,
		"position",
		location_home,
		show_duration
	)

	hud_tween.parallel().tween_property(
		help_panel,
		"position",
		help_panel_home,
		show_duration
	)
