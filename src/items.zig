// src/items.zig
// Defines item types and structures for items that can exist in the world or be carried.
const std = @import("std");
const config = @import("config.zig"); // For decay rates, HP, etc.

// Enum for different types of items
pub const ItemType = enum {
    Meat,
    BrushResource, // What sheep eat and what might be dropped from Brush entities
    Log,
    RockItem, // Dropped by RockCluster
    CorpseSheep,
    CorpseBear,
    // Grain, // Example for future expansion
};

// Represents an item on the ground
pub const Item = struct {
    x: i32,
    y: i32,
    item_type: ItemType,
    hp: i16, // For decay; when it reaches 0, the item disappears
    decay_timer: u32, // CORRECTED: Changed from u16 to u32 to match getDecayRateTicks

    pub fn getDecayRateTicks(item_type: ItemType) u32 {
        return switch (item_type) {
            .Meat => config.meat_decay_rate_ticks,
            .CorpseSheep => config.corpse_decay_rate_ticks,
            .CorpseBear => config.corpse_decay_rate_ticks,
            .BrushResource => config.brush_resource_decay_rate_ticks,
            .Log => config.log_decay_rate_ticks,
            .RockItem => config.rock_item_decay_rate_ticks,
        };
    }

    pub fn getInitialHp(item_type: ItemType) i16 {
        return switch (item_type) {
            .Meat => config.meat_initial_hp,
            .CorpseSheep => config.corpse_initial_hp,
            .CorpseBear => config.corpse_initial_hp,
            .BrushResource => config.brush_resource_initial_hp,
            .Log => config.log_initial_hp,
            .RockItem => config.rock_item_initial_hp,
        };
    }
};

// Represents a slot in an entity's inventory
pub const CarriedItemSlot = struct {
    item_type: ?ItemType = null,
    quantity: u8 = 0,

    pub fn isEmpty(self: CarriedItemSlot) bool {
        return self.item_type == null or self.quantity == 0;
    }

    pub fn clear(self: *CarriedItemSlot) void {
        self.item_type = null;
        self.quantity = 0;
    }
};

// Helper to get a string name for item types, useful for UI or logging
pub fn getItemTypeName(item_type: ItemType) [:0]const u8 {
    return switch (item_type) {
        .Meat => "Meat",
        .BrushResource => "Brush",
        .Log => "Log",
        .RockItem => "Rock",
        .CorpseSheep => "Sheep Corpse",
        .CorpseBear => "Bear Corpse",
    };
}
