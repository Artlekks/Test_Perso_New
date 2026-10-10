extends CanvasLayer
class_name BeachCraftingMenu

const MODE_RECIPES := 0
const MODE_CUSTOMIZE := 1
const SELECTION_SAVE_PATH := "user://beach_crafting_recipe_selections.cfg"

@onready var root: Control = $Root
@onready var recipe_label: Label = $Root/Panel/RecipeLabel
@onready var slots_label: Label = $Root/Panel/SlotsLabel
@onready var preview_label: Label = $Root/Panel/PreviewLabel
@onready var comparison_label: Label = $Root/Panel/ComparisonLabel
@onready var cost_label: Label = $Root/Panel/CostLabel
@onready var inventory_label: Label = $Root/Panel/InventoryLabel
@onready var status_label: Label = $Root/Panel/StatusLabel
@onready var help_label: Label = $Root/Panel/HelpLabel
@onready var live_recipe_name_label: Label = $Root/LiveRecipeNameLabel
@onready var recipe_counter_label: Label = $Root/RecipeCounterLabel
@onready var recipe_cursor: Polygon2D = $Root/RecipeCursor
@onready var customize_cursor: Polygon2D = $Root/CustomizeCursor
@onready var body_choice_label: Label = $Root/BodyChoiceLabel
@onready var core_choice_label: Label = $Root/CoreChoiceLabel
@onready var accent_choice_label: Label = $Root/AccentChoiceLabel
@onready var body_index_label: Label = $Root/BodyIndexLabel
@onready var core_index_label: Label = $Root/CoreIndexLabel
@onready var accent_index_label: Label = $Root/AccentIndexLabel
@onready var attraction_value_label: Label = $Root/AttractionValueLabel
@onready var depth_value_label: Label = $Root/DepthValueLabel
@onready var handling_value_label: Label = $Root/HandlingValueLabel
@onready var live_status_label: Label = $Root/LiveStatusLabel
@onready var mode_hint_label: Label = $Root/ModeHintLabel

var _service: BeachCraftingService = null
var _inventory: BeachGatheringInventory = null
var _recipe_index: int = 0
var _mode: int = MODE_RECIPES
var _recipe_selections: Dictionary = {}
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

	preload("res://scripts/mobile/responsive_menu_surface.gd").attach(self, root, "crafting")

func configure(
	service: BeachCraftingService,
	inventory: BeachGatheringInventory
) -> void:
	_service = service
	_inventory = inventory
	_load_recipe_selections()
	_apply_saved_selection_for_current_recipe()
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
	_mode = MODE_RECIPES
	_slot_index = 0
	_status = ""
	_apply_saved_selection_for_current_recipe()
	_refresh()
	root.show()
	return true


func close_menu() -> void:
	if not root.visible:
		return
	_remember_current_selection()
	_save_recipe_selections()
	root.hide()
	ModalInputOwnership.release_modal(self)
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

	# Debug helpers remain available from either mode.
	if OS.is_debug_build() and _is_key(event, KEY_R):
		var result: Dictionary = _service.grant_qa_material_bundle(10)
		if bool(result.get("success", false)):
			_status = "QA: +10 of every beach material."
		else:
			_status = "QA material grant failed."
		_refresh()
		get_viewport().set_input_as_handled()
		return

	if OS.is_debug_build() and _is_key(event, KEY_T):
		var suite: Dictionary = _service.grant_qa_feel_suite()
		if bool(suite.get("success", false)):
			_status = (
				"QA feel suite ready. F8 opens telemetry."
			)
		else:
			_status = "QA feel suite failed: %s" % str(
				suite.get("reason", "unknown")
			)
		_refresh()
		get_viewport().set_input_as_handled()
		return

	# J is the explicit Recipe <-> Customize mode switch.
	if _is_key(event, KEY_J):
		_toggle_customize_mode()
		get_viewport().set_input_as_handled()
		return

	# K always means Craft, no matter which mode owns the cursor.
	if _is_confirm(event):
		_craft_current()
		get_viewport().set_input_as_handled()
		return

	if _mode == MODE_RECIPES:
		if _is_up(event):
			_move_recipe(-1)
		elif _is_down(event):
			_move_recipe(1)
		else:
			return
	else:
		# Customize:
		# A/D = Body/Core/Accent
		# W/S = cycle the selected slot's legal materials.
		if _is_left(event):
			_move_slot(-1)
		elif _is_right(event):
			_move_slot(1)
		elif _is_up(event):
			_cycle_active_material(-1)
		elif _is_down(event):
			_cycle_active_material(1)
		else:
			return

	get_viewport().set_input_as_handled()


func _move_recipe(step: int) -> void:
	var recipes := _service.get_catalog().recipes
	if recipes.is_empty():
		return

	_remember_current_selection()
	_recipe_index = posmod(
		_recipe_index + step,
		recipes.size()
	)
	_apply_saved_selection_for_current_recipe()
	_status = ""
	_refresh()


func _toggle_customize_mode() -> void:
	if _mode == MODE_RECIPES:
		_mode = MODE_CUSTOMIZE
		_slot_index = clampi(_slot_index, 0, 2)
		_status = "Customize materials."
	else:
		_remember_current_selection()
		_save_recipe_selections()
		_mode = MODE_RECIPES
		_status = ""
	_refresh()


func _move_slot(step: int) -> void:
	_slot_index = wrapi(
		_slot_index + step,
		0,
		3
	)
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
	_remember_current_selection()
	_save_recipe_selections()
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
		_status = "Crafted %s. K = craft another." % str(
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

	var recipes := _service.get_catalog().recipes
	live_recipe_name_label.text = recipe.display_name
	recipe_counter_label.text = "%d / %d" % [
		_recipe_index + 1,
		recipes.size(),
	]
	# The supplied mockup has six visible recipe rows. The actual backend
	# currently owns three recipes; future recipes use the same cursor logic.
	var visible_row: int = posmod(_recipe_index, 6)
	recipe_cursor.position = Vector2(
		64.0,
		160.0 + float(visible_row) * 45.0
	)
	recipe_cursor.visible = _mode == MODE_RECIPES
	customize_cursor.visible = _mode == MODE_CUSTOMIZE
	var customize_x := [203.0, 306.0, 409.0]
	customize_cursor.position = Vector2(
		customize_x[_slot_index],
		315.0
	)

	recipe_label.text = "%s\n%s" % [
		recipe.display_name,
		recipe.description,
	]

	var body_id := _current_body_id()
	var core_id := _current_core_id()
	var accent_id := _current_accent_id()

	body_choice_label.text = _material_display_with_owned(body_id)
	core_choice_label.text = _material_display_with_owned(core_id)
	accent_choice_label.text = (
		"None"
		if accent_id == &""
		else _material_display_with_owned(accent_id)
	)

	body_index_label.text = _slot_position_text(
		_body_index,
		recipe.body_material_ids.size()
	)
	core_index_label.text = _slot_position_text(
		_core_index,
		recipe.core_material_ids.size()
	)
	accent_index_label.text = _accent_position_text(recipe)

	slots_label.text = "%s BODY     %s\n%s CORE     %s\n%s ACCENT   %s" % [
		">" if _slot_index == 0 else " ",
		_material_display_with_owned(body_id),
		">" if _slot_index == 1 else " ",
		_material_display_with_owned(core_id),
		">" if _slot_index == 2 else " ",
		(
			"None"
			if accent_id == &""
			else _material_display_with_owned(accent_id)
		),
	]

	var preview: Dictionary = _service.preview_craft(
		recipe.recipe_id,
		body_id,
		core_id,
		accent_id
	)
	if bool(preview.get("success", false)):
		preview_label.text = (
			"RESULT\n"
			+ "Buoyancy %s  —  %s\n"
			+ "Handling %s  —  %s\n"
			+ "Attraction %s  —  %s"
		) % [
			_score_text(int(preview.get("buoyancy", 0))),
			str(preview.get("buoyancy_label", "")),
			_score_text(int(preview.get("handling", 0))),
			str(preview.get("handling_label", "")),
			_score_text(int(preview.get("attraction", 0))),
			str(preview.get("attraction_label", "")),
		]
		cost_label.text = _cost_text(preview)
		comparison_label.text = _comparison_text(
			preview.get("equipped_comparison", {})
		)
		attraction_value_label.text = "x%.2f" % float(
			preview.get("attraction_reference", 1.0)
		)
		depth_value_label.text = "%d%%" % int(
			round(
				float(preview.get("sink_depth", 0.0))
				* 100.0
			)
		)
		handling_value_label.text = _score_text(
			int(preview.get("handling", 0))
		)
	else:
		preview_label.text = "Invalid material combination."
		cost_label.text = ""
		comparison_label.text = ""
		attraction_value_label.text = "--"
		depth_value_label.text = "--"
		handling_value_label.text = "--"

	inventory_label.text = _inventory_text()
	status_label.text = _status
	live_status_label.text = _status
	if _mode == MODE_RECIPES:
		mode_hint_label.text = "W/S Recipe    J Customize    K Craft    I Back"
	else:
		mode_hint_label.text = "A/D Slot    W/S Material    J Recipes    K Craft"
	help_label.text = (
		"W/S Recipe   I Back"
		+ (
			"\nDEBUG: R = +10 mats   T = create Feel QA suite   F8 = telemetry"
			if OS.is_debug_build()
			else ""
		)
	)


func _load_recipe_selections() -> void:
	_recipe_selections.clear()

	var catalog := _service.get_catalog()
	if catalog == null:
		return

	var config := ConfigFile.new()
	var has_save: bool = (
		config.load(SELECTION_SAVE_PATH) == OK
	)

	for raw_recipe in catalog.recipes:
		if raw_recipe == null:
			continue
		var recipe := raw_recipe as BeachCraftingRecipe
		var section: String = "recipe_%s" % String(
			recipe.recipe_id
		)

		var body_id: String = _default_body_id(recipe)
		var core_id: String = _default_core_id(recipe)
		var accent_id: String = _default_accent_id(recipe)

		if has_save:
			body_id = str(
				config.get_value(
					section,
					"body_id",
					body_id
				)
			)
			core_id = str(
				config.get_value(
					section,
					"core_id",
					core_id
				)
			)
			accent_id = str(
				config.get_value(
					section,
					"accent_id",
					accent_id
				)
			)

		_recipe_selections[String(recipe.recipe_id)] = (
			_normalize_selection(
				recipe,
				body_id,
				core_id,
				accent_id
			)
		)


func _save_recipe_selections() -> void:
	if _recipe_selections.is_empty():
		return

	var config := ConfigFile.new()
	for raw_recipe_id in _recipe_selections.keys():
		var recipe_id: String = str(raw_recipe_id)
		var raw_selection = _recipe_selections[raw_recipe_id]
		if not (raw_selection is Dictionary):
			continue
		var selection: Dictionary = raw_selection
		var section: String = "recipe_%s" % recipe_id
		config.set_value(
			section,
			"body_id",
			str(selection.get("body_id", ""))
		)
		config.set_value(
			section,
			"core_id",
			str(selection.get("core_id", ""))
		)
		config.set_value(
			section,
			"accent_id",
			str(selection.get("accent_id", ""))
		)

	var save_error: Error = config.save(
		SELECTION_SAVE_PATH
	)
	if save_error != OK:
		push_warning(
			"BeachCraftingMenu: could not save recipe selections (%s)."
			% error_string(save_error)
		)


func _remember_current_selection() -> void:
	var recipe := _current_recipe()
	if recipe == null:
		return

	_recipe_selections[String(recipe.recipe_id)] = {
		"body_id": String(_current_body_id()),
		"core_id": String(_current_core_id()),
		"accent_id": String(_current_accent_id()),
	}


func _apply_saved_selection_for_current_recipe() -> void:
	var recipe := _current_recipe()
	if recipe == null:
		return

	var key: String = String(recipe.recipe_id)
	if not _recipe_selections.has(key):
		_recipe_selections[key] = _normalize_selection(
			recipe,
			_default_body_id(recipe),
			_default_core_id(recipe),
			_default_accent_id(recipe)
		)

	var raw_selection = _recipe_selections[key]
	if not (raw_selection is Dictionary):
		return
	var selection: Dictionary = raw_selection

	_body_index = maxi(
		0,
		recipe.body_material_ids.find(
			str(selection.get("body_id", ""))
		)
	)
	_core_index = maxi(
		0,
		recipe.core_material_ids.find(
			str(selection.get("core_id", ""))
		)
	)

	var accent_id: String = str(
		selection.get("accent_id", "")
	)
	if recipe.accent_optional:
		if accent_id.is_empty():
			_accent_index = 0
		else:
			var found: int = recipe.accent_material_ids.find(
				accent_id
			)
			_accent_index = (
				found + 1
				if found >= 0
				else 0
			)
	else:
		_accent_index = maxi(
			0,
			recipe.accent_material_ids.find(accent_id)
		)


func _normalize_selection(
	recipe: BeachCraftingRecipe,
	body_id: String,
	core_id: String,
	accent_id: String
) -> Dictionary:
	var normalized_body: String = body_id
	if not recipe.body_material_ids.has(normalized_body):
		normalized_body = _default_body_id(recipe)

	var normalized_core: String = core_id
	if not recipe.core_material_ids.has(normalized_core):
		normalized_core = _default_core_id(recipe)

	var normalized_accent: String = accent_id
	if recipe.accent_optional and normalized_accent.is_empty():
		pass
	elif not recipe.accent_material_ids.has(
		normalized_accent
	):
		normalized_accent = _default_accent_id(recipe)

	return {
		"body_id": normalized_body,
		"core_id": normalized_core,
		"accent_id": normalized_accent,
	}


func _default_body_id(
	recipe: BeachCraftingRecipe
) -> String:
	if recipe.body_material_ids.is_empty():
		return ""
	return str(recipe.body_material_ids[0])


func _default_core_id(
	recipe: BeachCraftingRecipe
) -> String:
	if recipe.core_material_ids.is_empty():
		return ""
	return str(recipe.core_material_ids[0])


func _default_accent_id(
	recipe: BeachCraftingRecipe
) -> String:
	if recipe.accent_optional:
		return ""
	if recipe.accent_material_ids.is_empty():
		return ""
	return str(recipe.accent_material_ids[0])


func _slot_position_text(
	index: int,
	option_count: int
) -> String:
	if option_count <= 0:
		return "0 / 0"
	return "%d / %d" % [
		clampi(index, 0, option_count - 1) + 1,
		option_count,
	]


func _accent_position_text(
	recipe: BeachCraftingRecipe
) -> String:
	var count: int = recipe.accent_material_ids.size()
	if recipe.accent_optional:
		count += 1
	if count <= 0:
		return "0 / 0"
	return "%d / %d" % [
		clampi(_accent_index, 0, count - 1) + 1,
		count,
	]


func _material_display_with_owned(
	material_id: StringName
) -> String:
	var owned: int = (
		_inventory.get_count(material_id)
		if _inventory != null
		else 0
	)
	return "%s [%d]" % [
		_material_display(material_id),
		owned,
	]


func _cost_text(preview: Dictionary) -> String:
	var costs = preview.get("costs", {})
	if not (costs is Dictionary):
		return ""
	var pieces := PackedStringArray()
	for raw_id in costs.keys():
		var material_id := StringName(str(raw_id))
		var required: int = int(costs[raw_id])
		var owned: int = (
			_inventory.get_count(material_id)
			if _inventory != null
			else 0
		)
		pieces.append(
			"%s %d/%d"
			% [
				_material_display(material_id),
				owned,
				required,
			]
		)
	return "%s   %s" % [
		"CAN CRAFT" if bool(preview.get("can_afford", false)) else "MISSING",
		"   ".join(pieces),
	]


func _comparison_text(raw_comparison) -> String:
	if not (raw_comparison is Dictionary):
		return "VS EQUIPPED: unavailable"
	var comparison: Dictionary = raw_comparison
	if not bool(comparison.get("available", false)):
		return "VS EQUIPPED: no lure selected"

	return (
		"VS EQUIPPED  %s\n"
		+ "Depth %.2f -> %.2f  (%s)\n"
		+ "Steer %.2f -> %.2f  (%s)\n"
		+ "Attract %.2f -> %.2f  (%s)"
	) % [
		str(comparison.get("display_name", "Lure")),
		float(comparison.get("current_depth", 0.0)),
		float(comparison.get("preview_depth", 0.0)),
		_signed_float_text(float(comparison.get("depth_delta", 0.0))),
		float(comparison.get("current_steer", 0.0)),
		float(comparison.get("preview_steer", 0.0)),
		_signed_float_text(float(comparison.get("steer_delta", 0.0))),
		float(comparison.get("current_attraction", 1.0)),
		float(comparison.get("preview_attraction", 1.0)),
		_signed_float_text(float(comparison.get("attraction_delta", 0.0))),
	]


func _signed_float_text(value: float) -> String:
	if value > 0.0005:
		return "+%.2f" % value
	return "%.2f" % value


func _score_text(value: int) -> String:
	if value > 0:
		return "+%d" % value
	return str(value)


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
