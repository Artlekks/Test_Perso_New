extends Node
class_name FishingEconomyService

signal fish_sold(result: Dictionary)
signal item_purchased(result: Dictionary)

const ShopOfferScript = preload("res://scripts/database/fishing_shop_offer.gd")
const ShopCatalogScript = preload("res://scripts/fishing_shop_catalog.gd")

const STATE_INVALID := "INVALID"
const STATE_LOCKED := "LOCKED"
const STATE_NOT_ENOUGH_ZENNY := "NOT_ENOUGH_ZENNY"
const STATE_OWNED := "OWNED"
const STATE_READY := "READY"
const STATE_COMPLETED := "COMPLETED"

var inventory: FishingInventory = null
var content_catalog: FishingContentCatalog = null
var tackle_catalog: FishingTackleCatalog = null
var shop_catalog: ShopCatalogScript = null
var trade_service: FishingTradeService = null
var economy_config: FishingEconomyConfig = null


func configure(
	new_inventory: FishingInventory,
	new_content_catalog: FishingContentCatalog,
	new_tackle_catalog: FishingTackleCatalog,
	new_shop_catalog: ShopCatalogScript,
	new_trade_service: FishingTradeService = null,
	new_economy_config: FishingEconomyConfig = null
) -> void:
	inventory = new_inventory
	content_catalog = new_content_catalog
	tackle_catalog = new_tackle_catalog
	shop_catalog = new_shop_catalog
	trade_service = new_trade_service
	economy_config = new_economy_config


func get_zenny() -> int:
	if inventory == null:
		return 0
	return inventory.get_zenny()


func get_fish_sell_value(species_id: StringName) -> int:
	var fish := _get_fish(species_id)
	if fish == null:
		return 0
	var fallback: int = fish.get_sell_value_zenny()
	if economy_config == null:
		return fallback
	return economy_config.get_fish_sell_price(
		StringName(fish.get_stable_species_id()),
		fallback
	)


func get_fish_reference(species_id: StringName) -> Dictionary:
	var fish := _get_fish(species_id)
	if fish == null:
		return {}
	return {
		"species_id": fish.get_stable_species_id(),
		"fish_name": fish.fish_name,
		"sell_value_zenny": get_fish_sell_value(
			StringName(fish.get_stable_species_id())
		),
		"legacy_item_effect": fish.get_legacy_item_effect(),
		"owned_count": inventory.get_fish_count(fish.get_stable_species_id()) if inventory != null else 0,
	}


func evaluate_fish_sale(species_id: StringName, amount: int = 1) -> Dictionary:
	var result := {
		"can_sell": false,
		"reason": "",
		"species_id": species_id,
		"amount": maxi(amount, 0),
		"unit_value_zenny": 0,
		"total_value_zenny": 0,
		"owned_count": 0,
		"zenny_before": get_zenny(),
	}
	if inventory == null:
		result["reason"] = "inventory_unavailable"
		return result
	if amount <= 0:
		result["reason"] = "invalid_amount"
		return result
	var fish := _get_fish(species_id)
	if fish == null:
		result["reason"] = "unknown_species"
		return result
	var stable_id := fish.get_stable_species_id()
	var owned := inventory.get_fish_count(stable_id)
	var unit_value := get_fish_sell_value(StringName(stable_id))
	result["species_id"] = StringName(stable_id)
	result["owned_count"] = owned
	result["unit_value_zenny"] = unit_value
	result["total_value_zenny"] = unit_value * amount
	if unit_value <= 0:
		result["reason"] = "not_sellable"
		return result
	if owned < amount:
		result["reason"] = "not_enough_fish"
		return result
	result["can_sell"] = true
	result["reason"] = "ok"
	return result


func sell_fish(species_id: StringName, amount: int = 1) -> Dictionary:
	var result := evaluate_fish_sale(species_id, amount)
	if not bool(result.get("can_sell", false)):
		return result
	var snapshot := inventory.create_transaction_snapshot()
	inventory.begin_notification_batch()
	var stable_id := str(result.get("species_id", species_id))
	var consumption := inventory.consume_fish_costs(
		PackedStringArray([stable_id]),
		PackedInt32Array([amount]),
		false
	)
	if not bool(consumption.get("success", false)):
		inventory.restore_transaction_snapshot(snapshot)
		inventory.cancel_notification_batch()
		result["can_sell"] = false
		result["reason"] = "inventory_changed"
		return result
	var total := int(result.get("total_value_zenny", 0))
	inventory.add_zenny(total, false)
	if not inventory.commit_changes():
		inventory.restore_transaction_snapshot(snapshot)
		inventory.cancel_notification_batch()
		result["can_sell"] = false
		result["reason"] = "inventory_save_failed"
		return result
	inventory.commit_notification_batch()
	result["reason"] = "completed"
	result["state_label"] = STATE_COMPLETED
	result["zenny_after"] = inventory.get_zenny()
	result["remaining_count"] = inventory.get_fish_count(stable_id)
	result["consumed_specimens"] = consumption.get("consumed_specimens", {})
	fish_sold.emit(result.duplicate(true))
	return result


func evaluate_purchase(
	offer: ShopOfferScript,
	purchase_count: int = 1,
	availability: Dictionary = {}
) -> Dictionary:
	var result := {
		"state_label": STATE_INVALID,
		"can_purchase": false,
		"reason": "",
		"offer_id": &"",
		"shop_id": &"",
		"item_id": &"",
		"item_type": -1,
		"purchase_count": maxi(purchase_count, 0),
		"reward_quantity": 0,
		"unit_price_zenny": 0,
		"total_price_zenny": 0,
		"zenny_before": get_zenny(),
	}
	if inventory == null or tackle_catalog == null:
		result["reason"] = "economy_unavailable"
		return result
	if offer == null or not offer.is_valid_definition() or purchase_count <= 0:
		result["reason"] = "invalid_offer"
		return result
	result["offer_id"] = offer.offer_id
	result["shop_id"] = offer.shop_id
	result["item_id"] = offer.item_id
	result["item_type"] = offer.item_type
	result["reward_quantity"] = offer.quantity * purchase_count
	var unit_price: int = offer.price_zenny
	if economy_config != null:
		unit_price = economy_config.get_offer_buy_price(
			int(offer.item_type),
			offer.item_id,
			unit_price
		)
	result["unit_price_zenny"] = maxi(0, unit_price)
	result["total_price_zenny"] = (
		maxi(0, unit_price) * purchase_count
	)
	if offer.availability_tag != &"":
		var availability_ok := bool(
			availability.get(
				offer.availability_tag,
				availability.get(str(offer.availability_tag), false)
			)
		)
		if not availability_ok:
			result["state_label"] = STATE_LOCKED
			result["reason"] = "availability_locked"
			return result
	var item := _resolve_offer_item(offer)
	if item == null:
		result["reason"] = "unknown_item"
		return result
	if offer.unique_item and purchase_count > 1:
		result["reason"] = "unique_item_quantity"
		return result
	if offer.unique_item and _owns_offer_item(offer):
		result["state_label"] = STATE_OWNED
		result["reason"] = "already_owned_unique_item"
		return result
	var total_price := int(result["total_price_zenny"])
	if inventory.get_zenny() < total_price:
		result["state_label"] = STATE_NOT_ENOUGH_ZENNY
		result["reason"] = "not_enough_zenny"
		return result
	result["state_label"] = STATE_READY
	result["can_purchase"] = true
	result["reason"] = "ok"
	return result


func purchase_offer(
	offer: ShopOfferScript,
	purchase_count: int = 1,
	availability: Dictionary = {}
) -> Dictionary:
	var result := evaluate_purchase(offer, purchase_count, availability)
	if not bool(result.get("can_purchase", false)):
		return result
	var snapshot := inventory.create_transaction_snapshot()
	inventory.begin_notification_batch()
	var total_price := int(result.get("total_price_zenny", 0))
	if not inventory.spend_zenny(total_price, false):
		inventory.restore_transaction_snapshot(snapshot)
		inventory.cancel_notification_batch()
		result["can_purchase"] = false
		result["state_label"] = STATE_NOT_ENOUGH_ZENNY
		result["reason"] = "wallet_changed"
		return result
	var quantity := int(result.get("reward_quantity", 0))
	var count_after := 0
	match offer.item_type:
		ShopOfferScript.ItemType.LURE:
			count_after = inventory.grant_lure(offer.item_id, quantity, false)
		ShopOfferScript.ItemType.ROD:
			count_after = inventory.grant_rod(offer.item_id, quantity, false)
		_:
			count_after = 0
	if count_after <= 0:
		inventory.restore_transaction_snapshot(snapshot)
		inventory.cancel_notification_batch()
		result["can_purchase"] = false
		result["state_label"] = STATE_INVALID
		result["reason"] = "grant_failed"
		return result
	if not inventory.commit_changes():
		inventory.restore_transaction_snapshot(snapshot)
		inventory.cancel_notification_batch()
		result["can_purchase"] = false
		result["state_label"] = STATE_INVALID
		result["reason"] = "inventory_save_failed"
		return result
	inventory.commit_notification_batch()
	result["state_label"] = STATE_COMPLETED
	result["reason"] = "completed"
	result["zenny_after"] = inventory.get_zenny()
	result["item_count_after"] = count_after
	item_purchased.emit(result.duplicate(true))
	return result


func get_offer_by_id(offer_id: StringName) -> ShopOfferScript:
	if shop_catalog == null:
		return null
	return shop_catalog.get_offer_by_id(offer_id)


func get_shop_statuses(
	shop_id: StringName,
	availability: Dictionary = {}
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if shop_catalog == null:
		return result
	for offer in shop_catalog.get_offers_for_shop(shop_id):
		result.append(evaluate_purchase(offer, 1, availability))
	return result


func get_manillo_trade_statuses(shop_id: StringName) -> Array[Dictionary]:
	if trade_service == null:
		return []
	return trade_service.get_trade_statuses_for_shop(shop_id)


func _get_fish(species_id: StringName) -> FishData:
	if content_catalog == null:
		return null
	return content_catalog.get_fish_by_id(species_id)


func _resolve_offer_item(offer: ShopOfferScript) -> Resource:
	match offer.item_type:
		ShopOfferScript.ItemType.LURE:
			return tackle_catalog.get_lure_by_id(offer.item_id)
		ShopOfferScript.ItemType.ROD:
			return tackle_catalog.get_rod_by_id(offer.item_id)
		_:
			return null


func _owns_offer_item(offer: ShopOfferScript) -> bool:
	match offer.item_type:
		ShopOfferScript.ItemType.LURE:
			return inventory.owns_lure(offer.item_id)
		ShopOfferScript.ItemType.ROD:
			return inventory.owns_rod(offer.item_id)
		_:
			return false
