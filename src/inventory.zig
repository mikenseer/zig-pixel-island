// src/inventory.zig
// Defines inventory structures and management functions for entities.
const std = @import("std");
const config = @import("config.zig");
const items = @import("items.zig"); // For ItemType
const types = @import("types.zig"); // Forward declaration for Entity

pub const CarriedItemSlot = struct {
    item_type: ?items.ItemType = null,
    quantity: u8 = 0,

    pub fn isEmpty(self: CarriedItemSlot) bool {
        return self.item_type == null or self.quantity == 0;
    }

    pub fn clear(self: *CarriedItemSlot) void {
        self.item_type = null;
        self.quantity = 0;
    }
};

// --- Inventory Management Functions (moved from types.Entity) ---

pub fn getFirstEmptyInventorySlot(entity: *const types.Entity) ?usize {
    for (entity.inventory, 0..) |slot, i| {
        if (slot.item_type == null) {
            return i;
        }
    }
    return null;
}

pub fn getFirstOccupiedInventorySlot(entity: *const types.Entity, item_type_filter: ?items.ItemType) ?usize {
    for (entity.inventory, 0..) |slot, i| {
        if (slot.item_type != null and slot.quantity > 0) {
            if (item_type_filter == null or slot.item_type == item_type_filter) {
                return i;
            }
        }
    }
    return null;
}

// Adds an item to the entity's inventory.
// Returns true if the full quantity was added, false otherwise (e.g., inventory full).
pub fn addToInventory(entity: *types.Entity, item_type: items.ItemType, quantity_to_add: u8) bool {
    if (quantity_to_add == 0) return true; // Nothing to add

    var quantity_remaining_to_add = quantity_to_add;

    // First, try to stack with existing items of the same type
    for (&entity.inventory) |*slot| {
        if (slot.item_type == item_type) {
            const can_add_to_stack = config.max_item_stack_size - slot.quantity;
            const add_this_iteration = @min(quantity_remaining_to_add, can_add_to_stack);

            if (add_this_iteration > 0) {
                slot.quantity += add_this_iteration;
                quantity_remaining_to_add -= add_this_iteration;
                if (quantity_remaining_to_add == 0) {
                    return true; // All items added
                }
            }
        }
    }

    // If items still remain, try to find an empty slot
    if (quantity_remaining_to_add > 0) {
        if (getFirstEmptyInventorySlot(entity)) |empty_idx| {
            // Ensure we don't exceed stack size even in a new slot (though current config is 1)
            const add_to_new_slot = @min(quantity_remaining_to_add, config.max_item_stack_size);
            entity.inventory[empty_idx] = .{ .item_type = item_type, .quantity = add_to_new_slot };
            quantity_remaining_to_add -= add_to_new_slot;
            if (quantity_remaining_to_add == 0) {
                return true; // All items added
            }
            // If still items remaining, it means stack size is 1 and we need more new slots.
            // This loop will only fill one new slot per call if stack size is 1.
            // For stack size > 1, this part of the logic might need adjustment if a single call
            // is expected to fill multiple new slots. For now, with stack size 1, it's okay.
        }
    }

    return quantity_remaining_to_add == 0; // True if all were added, false if some couldn't fit
}

// Removes a quantity of an item from a specific inventory slot.
// Returns the actual quantity removed.
pub fn removeFromInventory(entity: *types.Entity, slot_idx: usize, quantity_to_remove: u8) u8 {
    if (slot_idx >= entity.inventory.len or entity.inventory[slot_idx].item_type == null or quantity_to_remove == 0) {
        return 0;
    }
    const actual_remove_amount = @min(quantity_to_remove, entity.inventory[slot_idx].quantity);
    entity.inventory[slot_idx].quantity -= actual_remove_amount;
    if (entity.inventory[slot_idx].quantity == 0) {
        entity.inventory[slot_idx].item_type = null; // Clear the slot if empty
    }
    return actual_remove_amount;
}

// Counts the total quantity of a specific item type across all inventory slots.
pub fn countInInventory(entity: *const types.Entity, item_type: items.ItemType) u8 {
    var count: u8 = 0;
    for (entity.inventory) |slot| {
        if (slot.item_type == item_type) {
            count += slot.quantity;
        }
    }
    return count;
}
