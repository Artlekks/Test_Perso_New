extends RefCounted

## Pass 3 page controller extracted from FishingMenu.
##
## The coordinator still owns scene references/state in this conservative
## pass. Keeping that ownership stable lets us modularize behavior without
## changing the scene graph, selector calibration, transitions or save/UI
## semantics during the architecture cleanup.

static func handle_data_input(menu, event: InputEvent) -> void:
	if menu._data_entries.is_empty():
		return

	if menu._data_detail_open:
		var detail_step: int = 0
		var vertical_step: int = menu._vertical_step(event)
		var horizontal_step: int = menu._horizontal_step(event)

		# Original BOF4 behavior:
		# W or A = previous fish.
		# S or D = next fish.
		if vertical_step < 0 or horizontal_step < 0:
			detail_step = -1
		elif vertical_step > 0 or horizontal_step > 0:
			detail_step = 1

		if detail_step != 0:
			menu._move_data_detail_selection(detail_step)
		return

	if menu._is_confirm(event):
		var entry: Dictionary = menu._data_entries[menu._data_index]
		if bool(entry.get("discovered", false)):
			menu._transition_data_detail(true)
		return

	var step: int = menu._vertical_step(event)
	if step == 0:
		return

	menu._data_index = clampi(menu._data_index + step, 0, menu._data_entries.size() - 1)
	menu.data_species_list.select(menu._data_index)
	menu.data_species_list.ensure_current_is_visible()
	menu._sync_data_selector_window()
	menu._update_data_selector()
	menu._update_data_scroll_thumb()
	menu._update_data_details()


static func move_data_detail_selection(menu, step: int) -> void:
	if step == 0 or menu._data_entries.is_empty():
		return

	var new_index: int = menu._data_index

	# Skip undiscovered entries in normal gameplay.
	while true:
		var candidate: int = new_index + step
		if candidate < 0 or candidate >= menu._data_entries.size():
			return

		new_index = candidate
		var candidate_entry: Dictionary = menu._data_entries[new_index]
		if bool(candidate_entry.get("discovered", false)):
			break

	menu._data_index = new_index

	# Keep the hidden list synchronized so returning with I lands on the
	# same fish currently displayed in the detail page.
	menu.data_species_list.select(menu._data_index)
	menu.data_species_list.ensure_current_is_visible()
	menu._sync_data_selector_window()
	menu._update_data_scroll_thumb()

	# Refresh every shared/manual field without changing page layout.
	menu._update_data_details()
	menu._update_data_detail_content()
	menu.info_label.text = "Directional buttons: Change page"


static func refresh_data_page(menu) -> void:
	menu._data_entries.clear()
	menu.data_species_list.clear()

	if not is_instance_valid(menu._journal):
		menu.info_label.text = "Fishing data is unavailable."
		menu._update_data_details()
		return

	# Pass 2: catalog order, identity, display names and portraits now come from
	# FishingJournalService/FishData. FishingMenu no longer owns a fish database.
	# Details are revealed here to preserve the current BOF4-style list/preview
	# behavior; record values remain gated by the discovered flag below.
	var snapshot: Dictionary = menu._journal.get_data_menu_snapshot(true, true)
	var raw_species: Variant = snapshot.get("species", [])

	if raw_species is Array:
		for value in raw_species:
			if not (value is Dictionary):
				continue

			var entry: Dictionary = (value as Dictionary).duplicate(true)
			menu._data_entries.append(entry)
			menu.data_species_list.add_item(
				str(entry.get("display_name", "????"))
			)

	if menu._data_entries.is_empty():
		menu._data_index = 0
		menu._data_window_start = 0
	else:
		menu._data_index = clampi(menu._data_index, 0, menu._data_entries.size() - 1)
		menu.data_species_list.select(menu._data_index)
		menu.data_species_list.ensure_current_is_visible()
		menu._sync_data_selector_window()

	menu._update_data_selector()
	menu._update_data_scroll_thumb()
	menu._update_data_details()


static func update_data_details(menu) -> void:
	menu.data_portrait.texture = null
	menu.data_size_label.text = "--"
	menu.data_points_label.text = "--"
	menu.data_point_label.text = "---"
	menu.data_caught_count_label.text = "00"
	menu._set_data_lure_dark_overlays({}, false)
	menu._set_data_wave_dark_overlays({}, false)

	if menu._data_entries.is_empty():
		menu.info_label.text = "No fishing data."
		return

	var entry: Dictionary = menu._data_entries[menu._data_index]
	var fish_name: String = str(entry.get("display_name", "????"))

	if menu._data_detail_open:
		menu.info_label.text = "Directional buttons: Change page"
	else:
		menu.info_label.text = "View data on %s" % fish_name

	var portrait: Texture2D = entry.get("portrait", null) as Texture2D
	if portrait != null:
		menu.data_portrait.texture = portrait

	var discovered: bool = bool(entry.get("discovered", false))
	menu._set_data_lure_dark_overlays(entry, discovered)
	menu._set_data_wave_dark_overlays(entry, discovered)

	if not discovered:
		return

	menu.data_size_label.text = "%d" % int(round(float(entry.get("best_size", 0.0))))
	menu.data_points_label.text = "%d" % int(entry.get("best_points", 0))
	menu.data_point_label.text = menu._get_primary_location_name(entry)
	menu.data_caught_count_label.text = "%02d" % int(entry.get("current_owned_count", 0))
	menu._update_data_detail_content()


static func set_data_lure_dark_overlays(
	menu,
	entry: Dictionary,
	discovered: bool
) -> void:
	var unavailable_types: Array = entry.get(
		"unavailable_lure_types",
		[]
	)

	menu.data_lure_spinner_dark.visible = (
		discovered and unavailable_types.has(LureType.Type.SPINNER)
	)
	menu.data_lure_winder_dark.visible = (
		discovered and unavailable_types.has(LureType.Type.WINDER)
	)
	menu.data_lure_topper_dark.visible = (
		discovered and unavailable_types.has(LureType.Type.TOPPER)
	)
	menu.data_lure_minnow_dark.visible = (
		discovered and unavailable_types.has(LureType.Type.MINNOW)
	)
	menu.data_lure_frogger_dark.visible = (
		discovered and unavailable_types.has(LureType.Type.FROG)
	)
	menu.data_lure_worm_dark.visible = (
		discovered and unavailable_types.has(LureType.Type.WORM)
	)


static func set_data_wave_dark_overlays(
	menu,
	entry: Dictionary,
	discovered: bool
) -> void:
	var habitats: PackedStringArray = entry.get(
		"habitat_types",
		PackedStringArray()
	)

	menu.data_wave_calm_dark.visible = (
		discovered and not habitats.has("RIVER")
	)
	menu.data_wave_big_dark.visible = (
		discovered and not habitats.has("LAKE")
	)
	menu.data_wave_tsunami_dark.visible = (
		discovered and not habitats.has("OCEAN")
	)


static func update_data_detail_content(menu) -> void:
	menu.data_detail_name_label.text = ""
	menu.data_detail_effect_label.text = ""
	menu.data_detail_guide_label.text = ""
	menu.data_detail_avg_label.text = ""

	if menu._data_entries.is_empty():
		return

	var entry: Dictionary = menu._data_entries[menu._data_index]
	if not bool(entry.get("discovered", false)):
		return

	menu.data_detail_name_label.text = str(entry.get("display_name", ""))
	menu.data_detail_avg_label.text = "%d" % int(
		round(float(entry.get("average_size", 0.0)))
	)
	menu.data_detail_effect_label.text = str(entry.get("guide_effect", ""))
	menu.data_detail_guide_label.text = str(entry.get("guide_description", ""))


static func sync_data_selector_window(menu) -> void:
	const visible_rows: int = 8
	if menu._data_entries.is_empty():
		menu._data_window_start = 0
		return

	if menu._data_index < menu._data_window_start:
		menu._data_window_start = menu._data_index
	elif menu._data_index >= menu._data_window_start + visible_rows:
		menu._data_window_start = menu._data_index - visible_rows + 1

	menu._data_window_start = clampi(
		menu._data_window_start,
		0,
		maxi(menu._data_entries.size() - visible_rows, 0)
	)


static func update_data_selector(menu) -> void:
	menu.data_species_list.select(menu._data_index)
	menu.data_species_list.ensure_current_is_visible()
	menu.call_deferred("_place_data_selector")


static func configure_data_list_visuals(menu) -> void:
	# ItemList keeps its internal scrollbar for scrolling logic, but BOF4 draws
	# its own thin L1/R1 indicator. Hide only the native Godot visual.
	if is_instance_valid(menu.data_species_list):
		var native_scrollbar: VScrollBar = menu.data_species_list.get_v_scroll_bar()
		if is_instance_valid(native_scrollbar):
			native_scrollbar.modulate = Color(1.0, 1.0, 1.0, 0.0)
			native_scrollbar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	menu._update_data_scroll_thumb()


static func update_data_scroll_thumb(menu) -> void:
	if not is_instance_valid(menu.data_scroll_thumb):
		return

	menu.data_scroll_thumb.visible = menu._data_entries.size() > 8
	if not menu.data_scroll_thumb.visible:
		return

	# The thumb has a fixed 2x34 native-pixel size. It represents the current
	# eight-row viewport, so it moves only when the list itself scrolls.
	const visible_rows: int = 8
	const track_top_y: float = 45.0
	const track_bottom_y: float = 118.0
	var max_window_start: int = maxi(menu._data_entries.size() - visible_rows, 0)
	var ratio: float = 0.0
	if max_window_start > 0:
		ratio = clampf(float(menu._data_window_start) / float(max_window_start), 0.0, 1.0)

	menu.data_scroll_thumb.position.y = roundf(lerpf(track_top_y, track_bottom_y, ratio))


static func get_primary_location_name(_menu, entry: Dictionary) -> String:
	var preferred_fields: PackedStringArray = [
		"best_size_spot_name",
		"best_points_spot_name",
		"last_catch_spot_name",
	]

	for field_name in preferred_fields:
		var spot_name: String = str(entry.get(field_name, "")).strip_edges()
		if not spot_name.is_empty():
			return spot_name

	var raw_locations: Variant = entry.get("locations", [])
	if raw_locations is Array:
		for value in raw_locations:
			if not (value is Dictionary):
				continue
			var spot_name: String = str((value as Dictionary).get("spot_name", "")).strip_edges()
			if not spot_name.is_empty():
				return spot_name

	return "---"


static func join_location_names(_menu, entry: Dictionary) -> String:
	var names: PackedStringArray = PackedStringArray()
	var raw_locations: Variant = entry.get("locations", [])
	if raw_locations is Array:
		var source_locations: Array = raw_locations
		for value in source_locations:
			if not (value is Dictionary):
				continue
			var location: Dictionary = value as Dictionary
			var spot_name: String = str(location.get("spot_name", ""))
			if not spot_name.is_empty():
				names.append(spot_name)

	return ", ".join(names) if not names.is_empty() else "---"


static func join_lure_names(_menu, entry: Dictionary) -> String:
	var names: PackedStringArray = PackedStringArray()
	var raw_successful: Variant = entry.get("successful_lures", [])
	if raw_successful is Array:
		var source_lures: Array = raw_successful
		for value in source_lures:
			if not (value is Dictionary):
				continue
			var lure_name: String = str((value as Dictionary).get("lure_name", ""))
			if not lure_name.is_empty() and not names.has(lure_name):
				names.append(lure_name)

	if names.is_empty():
		var preferred: Variant = entry.get("preferred_lure_ids", PackedStringArray())
		if preferred is PackedStringArray:
			var preferred_ids: PackedStringArray = preferred
			for lure_id in preferred_ids:
				names.append(str(lure_id))

	return ", ".join(names) if not names.is_empty() else "---"
