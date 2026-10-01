extends CanvasLayer
class_name BeachCraftingMenu

@onready var root: Control = $Root
@onready var recipe_label: Label = $Root/Panel/RecipeLabel
@onready var slots_label: Label = $Root/Panel/SlotsLabel
@onready var preview_label: Label = $Root/Panel/PreviewLabel
@onready var inventory_label: Label = $Root/Panel/InventoryLabel
@onready var status_label: Label = $Root/Panel/StatusLabel
@onready var help_label: Label = $Root/Panel/HelpLabel

var _service: BeachCraftingService = null
var _inventory: BeachGatheringInventory = null
var _recipe_index: int = 0
var _slot_index: int = 0
var _body_index: int = 0
var _core_index: int = 0
var _accent_index: int = 0
var _previous_tree_paused: bool = false
var _ignore_until_frame: int = 0
var _status: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	root.hide()


func configure(
	service: BeachCraftingService,
	inventory: BeachGatheringInventory
) -> void:
	_service = service
	_inventory = inventory
	_reset_indices()
	_refresh()


func open_menu() -> bool:
	if _service == null or _service.get_catalog() == null:
		return false
	var catalog := _service.get_catalog()
	if catalog.recipes.is_empty():
		return false

	_previous_tree_paused = get_tree().paused
	get_tree().paused = true
	_ignore_until_frame = Engine.get_process_frames() + 1
	_status = ""
	_refresh()
	root.show()
	return true


func close_menu() -> void:
	if not root.visible:
		return
	root.hide()
	get_tree().paused = _previous_tree_paused


func is_open() -> bool:
	return root.visible


func _input(event: InputEvent) -> void:
	if not root.visible:
		return
	if Engine.get_process_frames() <= _ignore_until_frame:
		return
	if not _pressed(event):
		return

	if _is_back(event):
		close_menu()
		get_viewport().set_input_as_handled()
		return

	if _is_up(event):
		_move_recipe(-1)
	elif _is_down(event):
		_move_recipe(1)
	elif _is_left(event):
		_cycle_active_material(-1)
	elif _is_right(event):
		_cycle_active_material(1)
	elif _is_key(event, KEY_J):
		_slot_index = posmod(_slot_index + 1, 3)
		_status = ""
		_refresh()
	elif _is_confirm(event):
		_craft_current()
	elif OS.is_debug_build() and _is_key(event, KEY_R):
		var result: Dictionary = _service.grant_qa_material_bundle(10)
		_status = (
			"QA: +10 of every beach material."
			if bool(result.get("success", false))
			else "QA material grant failed."
		)
		_refresh()
	else:
		return

	get_viewport().set_input_as_handled()


func _move_recipe(step: int) -> void:
	var recipes := _service.get_catalog().recipes
	if recipes.is_empty():
		return
	_recipe_index = posmod(_recipe_index + step, recipes.size())
	_reset_indices()
	_status = ""
	_refresh()


func _cycle_active_material(step: int) -> void:
	var recipe := _current_recipe()
	if recipe == null:
		return
	var count: int = 0
	match _slot_index:
		0:
			count = recipe.body_material_ids.size()
			if count > 0:
				_body_index = posmod(_body_index + step, count)
		1:
			count = recipe.core_material_ids.size()
			if count > 0:
				_core_index = posmod(_core_index + step, count)
		2:
			count = recipe.accent_material_ids.size()
			var option_count: int = count + (1 if recipe.accent_optional else 0)
			if option_count > 0:
				_accent_index = posmod(_accent_index + step, option_count)
	_status = ""
	_refresh()


func _craft_current() -> void:
	var recipe := _current_recipe()
	if recipe == null:
		return
	var result: Dictionary = _service.craft(
		recipe.recipe_id,
		_current_body_id(),
		_current_core_id(),
		_current_accent_id()
	)
	if bool(result.get("success", false)):
		_status = "Crafted %s. Equip it from your fishing lure list." % str(
			result.get("display_name", recipe.display_name)
		)
	else:
		match str(result.get("reason", "")):
			"missing_materials":
				_status = "Not enough materials."
			_:
				_status = "Craft failed: %s" % str(
					result.get("reason", "unknown")
				)
	_refresh()


func _refresh() -> void:
	if _service == null or _service.get_catalog() == null:
		return
	var recipe := _current_recipe()
	if recipe == null:
		return

	recipe_label.text = "%s\n%s" % [
		recipe.display_name,
		recipe.description,
	]

	var body_id := _current_body_id()
	var core_id := _current_core_id()
	var accent_id := _current_accent_id()

	slots_label.text = "%s BODY     %s\n%s CORE     %s\n%s ACCENT   %s" % [
		">" if _slot_index == 0 else " ",
		_material_display(body_id),
		">" if _slot_index == 1 else " ",
		_material_display(core_id),
		">" if _slot_index == 2 else " ",
		"None" if accent_id == &"" else _material_display(accent_id),
	]

	var preview: Dictionary = _service.preview_craft(
		recipe.recipe_id,
		body_id,
		core_id,
		accent_id
	)
	if bool(preview.get("success", false)):
		preview_label.text = (
			"%s\nDepth %.2f   Steer %.2f   Attraction x%.2f"
			% [
				str(preview.get("property_text", "")),
				float(preview.get("sink_depth", 0.0)),
				float(preview.get("reel_steer_strength", 0.0)),
				float(preview.get("attraction_multiplier", 1.0)),
			]
		)
	else:
		preview_label.text = "Invalid material combination."

	inventory_label.text = _inventory_text()
	status_label.text = _status
	help_label.text = (
		"W/S Recipe   A/D Material   J Slot   K Craft   I Back"
		+ ("\nDEBUG: R = +10 all materials" if OS.is_debug_build() else "")
	)


func _inventory_text() -> String:
	if _inventory == null:
		return "MATERIALS: unavailable"
	var pieces := PackedStringArray()
	for material in _service.get_catalog().materials:
		if material == null:
			continue
		pieces.append(
			"%s %d"
			% [
				material.display_name,
				_inventory.get_count(material.material_id),
			]
		)
	return "MATERIALS  " + "   ".join(pieces)


func _current_recipe() -> BeachCraftingRecipe:
	var catalog := _service.get_catalog()
	if catalog == null or catalog.recipes.is_empty():
		return null
	_recipe_index = clampi(
		_recipe_index,
		0,
		catalog.recipes.size() - 1
	)
	return catalog.recipes[_recipe_index]


func _current_body_id() -> StringName:
	var recipe := _current_recipe()
	if recipe == null or recipe.body_material_ids.is_empty():
		return &""
	_body_index = clampi(
		_body_index,
		0,
		recipe.body_material_ids.size() - 1
	)
	return StringName(recipe.body_material_ids[_body_index])


func _current_core_id() -> StringName:
	var recipe := _current_recipe()
	if recipe == null or recipe.core_material_ids.is_empty():
		return &""
	_core_index = clampi(
		_core_index,
		0,
		recipe.core_material_ids.size() - 1
	)
	return StringName(recipe.core_material_ids[_core_index])


func _current_accent_id() -> StringName:
	var recipe := _current_recipe()
	if recipe == null:
		return &""

	var allowed_count: int = recipe.accent_material_ids.size()
	if recipe.accent_optional:
		if _accent_index <= 0:
			return &""
		var material_index: int = _accent_index - 1
		if material_index >= 0 and material_index < allowed_count:
			return StringName(
				recipe.accent_material_ids[material_index]
			)
		return &""

	if allowed_count <= 0:
		return &""
	_accent_index = clampi(
		_accent_index,
		0,
		allowed_count - 1
	)
	return StringName(recipe.accent_material_ids[_accent_index])


func _material_display(material_id: StringName) -> String:
	var material := _service.get_material_definition(material_id)
	if material == null:
		return String(material_id)
	return material.display_name


func _reset_indices() -> void:
	_slot_index = 0
	_body_index = 0
	_core_index = 0
	_accent_index = 0


func _pressed(event: InputEvent) -> bool:
	return (
		event is InputEventKey
		and (event as InputEventKey).pressed
		and not (event as InputEventKey).echo
	)


func _is_confirm(event: InputEvent) -> bool:
	return _is_key(event, KEY_K) or _is_key(event, KEY_ENTER)


func _is_back(event: InputEvent) -> bool:
	return _is_key(event, KEY_I) or _is_key(event, KEY_ESCAPE)


func _is_left(event: InputEvent) -> bool:
	return _is_key(event, KEY_A) or _is_key(event, KEY_LEFT)


func _is_right(event: InputEvent) -> bool:
	return _is_key(event, KEY_D) or _is_key(event, KEY_RIGHT)


func _is_up(event: InputEvent) -> bool:
	return _is_key(event, KEY_W) or _is_key(event, KEY_UP)


func _is_down(event: InputEvent) -> bool:
	return _is_key(event, KEY_S) or _is_key(event, KEY_DOWN)


func _is_key(event: InputEvent, key: Key) -> bool:
	if not (event is InputEventKey):
		return false
	var key_event := event as InputEventKey
	return (
		key_event.keycode == key
		or key_event.physical_keycode == key
	)
