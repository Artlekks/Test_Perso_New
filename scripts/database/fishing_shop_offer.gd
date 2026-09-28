extends Resource
class_name FishingShopOffer

enum ItemType {
	LURE,
	ROD,
}

@export_category("Identity")
@export var offer_id: StringName = &""
@export var shop_id: StringName = &""
@export var shop_name: String = ""
@export var sort_order: int = 0

@export_category("Item")
@export var item_type: ItemType = ItemType.LURE
@export var item_id: StringName = &""
@export var item_name: String = ""
@export_range(1, 99, 1)
var quantity: int = 1
@export_range(0, 999999, 1)
var price_zenny: int = 0

## Rods and other one-off equipment should not be purchased again once owned.
@export var unique_item: bool = false

@export_category("Availability")
## Empty means the offer is normally available when the shop exists. World/game
## progression can pass a matching tag into FishingEconomyService later without
## coupling shop data to a particular quest system.
@export var availability_tag: StringName = &""

@export_multiline var source_note: String = ""


func is_valid_definition() -> bool:
	return (
		offer_id != &""
		and shop_id != &""
		and item_id != &""
		and quantity > 0
		and price_zenny >= 0
	)


func get_total_price(purchase_count: int = 1) -> int:
	return maxi(price_zenny, 0) * maxi(purchase_count, 0)
