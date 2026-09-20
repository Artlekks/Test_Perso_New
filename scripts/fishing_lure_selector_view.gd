extends CanvasLayer

@onready var root: Control = $Root
@onready var counter_label: Label = $Root/Panel/CounterLabel
@onready var name_label: Label = $Root/Panel/NameLabel
@onready var details_label: Label = $Root/Panel/DetailsLabel
@onready var description_label: Label = $Root/Panel/DescriptionLabel

var _catalog: Resource = null
var _preview_index: int = -1


func _ready() -> void:
	root.hide()


func open_for_loadout(loadout: Node) -> bool:
	if loadout == null:
		return false

	_catalog = loadout.lure_catalog

	if _catalog == null or _catalog.get_lure_count() <= 0:
		_catalog = null
		return false

	_preview_index = loadout.get_selected_lure_index()

	if _preview_index < 0:
		_preview_index = 0

	_refresh()
	root.show()
	return true


func close_selector() -> void:
	root.hide()
	_catalog = null
	_preview_index = -1


func is_open() -> bool:
	return root.visible


func move_selection(step: int) -> void:
	if _catalog == null:
		return

	var lure_count: int = _catalog.get_lure_count()

	if lure_count <= 0:
		return

	_preview_index = posmod(_preview_index + step, lure_count)
	_refresh()


func get_preview_lure() -> BaitData:
	if _catalog == null or _preview_index < 0:
		return null

	return _catalog.get_lure(_preview_index)


func _refresh() -> void:
	var lure: BaitData = get_preview_lure()

	if lure == null:
		return

	var lure_count: int = _catalog.get_lure_count()

	counter_label.text = "LURE  %02d / %02d" % [
		_preview_index + 1,
		lure_count
	]

	name_label.text = "<   %s   >" % lure.display_name
	details_label.text = "%s    Lv.%d" % [
		lure.get_type_label(),
		lure.level
	]
	description_label.text = lure.description
