extends Resource
class_name MerchantEconomyContext

## Authored access policy only. No wallet, inventory or save/progression state.
@export var shop_ids: PackedStringArray = PackedStringArray()
@export var trade_shop_ids: PackedStringArray = PackedStringArray()
@export var availability: Dictionary = {}
@export var full_catalog_access: bool = false


func apply_to(access: Node) -> void:
	access.set_access_context(shop_ids, trade_shop_ids, availability, full_catalog_access)
