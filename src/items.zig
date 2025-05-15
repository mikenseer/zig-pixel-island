// src/items.zig
// Defines item types and structures for items that can exist in the world.
// CarriedItemSlot is now in inventory.zig
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
    hp: i16, // Durability of the item on the ground
    decay_timer: u32, // Ticks until next HP loss

    pub fn getDecayRateTicks(item_type: ItemType) u32 {
        return switch (item_type) {
            .Meat => config.meat_decay_rate_ticks,
            .CorpseSheep => config.corpse_decay_rate_ticks,
            .CorpseBear => config.corpse_decay_rate_ticks,
            .BrushResource => config.brush_resource_decay_rate_ticks,
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

// CarriedItemSlot struct has been moved to inventory.zig

pub fn getItemTypeName(item_type: ItemType) [:0]const u8 {
    return switch (item_type) {
        .Meat => "Meat",
        .BrushResource => "Brush Parts", // Renamed for clarity if it's distinct from Grain
        .Log => "Log",
        .RockItem => "Rock",
        .CorpseSheep => "Sheep Corpse",
        .CorpseBear => "Bear Corpse",
        .Grain => "Grain",
    };
}
