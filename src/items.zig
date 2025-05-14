// src/items.zig
// Defines item types and structures for items that can exist in the world or be carried.
const std = @import("std");
const config = @import("config.zig");

pub const ItemType = enum {
    Meat,
    BrushResource, // Represents the "harvestable" part of a brush before it becomes Grain
    Log, // Dropped from Trees
    RockItem, // Dropped from RockClusters
    CorpseSheep,
    CorpseBear,
    Grain, // Dropped from destroyed Brush entities
};

pub const Item = struct {
    x: i32,
    y: i32,
    item_type: ItemType,
    hp: i16,
    decay_timer: u32,

    pub fn getDecayRateTicks(item_type: ItemType) u32 {
        return switch (item_type) {
            .Meat => config.meat_decay_rate_ticks,
            .CorpseSheep => config.corpse_decay_rate_ticks,
            .CorpseBear => config.corpse_decay_rate_ticks,
            .BrushResource => config.brush_resource_decay_rate_ticks, // Might be short if it converts to grain quickly
            .Log => config.log_decay_rate_ticks,
            .RockItem => config.rock_item_decay_rate_ticks,
            .Grain => config.grain_decay_rate_ticks,
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
            .Grain => config.grain_initial_hp,
        };
    }
};

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

pub fn getItemTypeName(item_type: ItemType) [:0]const u8 {
    return switch (item_type) {
        .Meat => "Meat",
        .BrushResource => "Brush", // This is the item sheep eat directly from Brush entity for now
        .Log => "Log",
        .RockItem => "Rock",
        .CorpseSheep => "Sheep Corpse",
        .CorpseBear => "Bear Corpse",
        .Grain => "Grain",
    };
}
