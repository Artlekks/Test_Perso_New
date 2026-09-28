extends Resource
class_name FishingShopCatalog

const ShopOfferScript = preload("res://scripts/database/fishing_shop_offer.gd")

@export var offers: Array[Resource] = []


func get_all_offers() -> Array[Resource]:
	var result: Array[Resource] = []
	for offer in offers:
		if offer != null and offer.is_valid_definition():
			result.append(offer)
	result.sort_custom(Callable(self, "_offer_less"))
	return result


func get_offer_by_id(offer_id: StringName) -> ShopOfferScript:
	if offer_id == &"":
		return null
	for offer in get_all_offers():
		if offer.offer_id == offer_id:
			return offer as ShopOfferScript
	return null


func get_offers_for_shop(shop_id: StringName) -> Array[Resource]:
	var result: Array[Resource] = []
	for offer in get_all_offers():
		if offer.shop_id == shop_id:
			result.append(offer)
	return result


func get_shop_ids() -> PackedStringArray:
	var seen: Dictionary = {}
	var result := PackedStringArray()
	for offer in get_all_offers():
		var key := str(offer.shop_id)
		if seen.has(key):
			continue
		seen[key] = true
		result.append(key)
	return result


func get_shop_display_name(shop_id: StringName) -> String:
	for offer in get_all_offers():
		if offer.shop_id == shop_id:
			return offer.shop_name
	return ""


func _offer_less(a, b) -> bool:
	var shop_compare := str(a.shop_id).naturalnocasecmp_to(str(b.shop_id))
	if shop_compare != 0:
		return shop_compare < 0
	if a.sort_order != b.sort_order:
		return a.sort_order < b.sort_order
	return str(a.offer_id).naturalnocasecmp_to(str(b.offer_id)) < 0
