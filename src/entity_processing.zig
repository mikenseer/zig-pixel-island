// src/entity_processing.zig
// Handles generalized entity death processing and HP decay.
const std = @import("std");
const types = @import("types.zig");
const config = @import("config.zig");
const items = @import("items.zig");
const log = std.log;
const RandomInterface = std.Random;

// Processes HP decay for an entity.
// Call this at the start of each AI's update tick.
pub fn processHpDecay(entity_ptr: *types.Entity) void {
    if (entity_ptr.current_hp == 0) { // Already dead, no decay needed
        return;
    }

    // Only certain entities decay HP over time (e.g., not static trees/rocks)
    switch (entity_ptr.entity_type) {
        .Player, .Sheep, .Bear => {
            if (entity_ptr.hp_decay_timer > 0) {
                entity_ptr.hp_decay_timer -= 1;
            }

            if (entity_ptr.hp_decay_timer == 0) {
                const decay_amount = switch (entity_ptr.entity_type) {
                    .Player => config.hp_decay_amount_peon,
                    .Sheep, .Bear => config.hp_decay_amount_animal,
                    else => 0, // Should not happen due to outer switch
                };

                if (decay_amount > 0) {
                    if (entity_ptr.current_hp > decay_amount) {
                        entity_ptr.current_hp -= decay_amount;
                    } else {
                        entity_ptr.current_hp = 0; // Entity dies from decay
                        log.info("{any} at {d},{d} died from HP decay. HP: {d}/{d}", .{ entity_ptr.entity_type, entity_ptr.x, entity_ptr.y, entity_ptr.current_hp, entity_ptr.max_hp });
                    }
                }
                entity_ptr.hp_decay_timer = config.hp_decay_interval; // Reset timer
            }
        },
        .Tree, .RockCluster, .Brush => {
            // These entities don't decay HP naturally over time.
            // Their HP is only reduced by direct actions (harvesting, combat).
        },
    }
}

// Handles item drops when an entity's HP reaches 0.
// Also handles dropping inventory.
// Sets dying_entity_ptr.processed_death_drops = true upon completion.
pub fn processEntityDeath(
    dying_entity_ptr: *types.Entity,
    world_ptr: *types.GameWorld,
    prng: *RandomInterface,
) void {
    if (dying_entity_ptr.processed_death_drops) {
        // log.warn("Attempted to process death drops for an already processed entity: {any}", .{dying_entity_ptr.entity_type});
        return;
    }

    log.info("{any} at {d},{d} has died. Processing drops.", .{ dying_entity_ptr.entity_type, dying_entity_ptr.x, dying_entity_ptr.y });

    // 1. Standard Drops based on Entity Type
    switch (dying_entity_ptr.entity_type) {
        .Sheep => {
            world_ptr.spawnItem(.CorpseSheep, dying_entity_ptr.x, dying_entity_ptr.y);
            var m: u8 = 0;
            while (m < config.meat_drops_from_sheep) : (m += 1) {
                if (world_ptr.findRandomAdjacentEmptyTile(dying_entity_ptr.x, dying_entity_ptr.y, 8, prng)) |drop_pos| {
                    world_ptr.spawnItem(.Meat, drop_pos.x, drop_pos.y);
                } else {
                    world_ptr.spawnItem(.Meat, dying_entity_ptr.x, dying_entity_ptr.y);
                }
            }
        },
        .Bear => {
            world_ptr.spawnItem(.CorpseBear, dying_entity_ptr.x, dying_entity_ptr.y);
            var m: u8 = 0;
            while (m < config.meat_drops_from_bear) : (m += 1) {
                if (world_ptr.findRandomAdjacentEmptyTile(dying_entity_ptr.x, dying_entity_ptr.y, 8, prng)) |drop_pos| {
                    world_ptr.spawnItem(.Meat, drop_pos.x, drop_pos.y);
                } else {
                    world_ptr.spawnItem(.Meat, dying_entity_ptr.x, dying_entity_ptr.y);
                }
            }
        },
        .Brush => {
            var g: u8 = 0;
            while (g < config.grain_drops_from_brush) : (g += 1) {
                if (world_ptr.findRandomAdjacentEmptyTile(dying_entity_ptr.x, dying_entity_ptr.y, 8, prng)) |drop_pos| {
                    world_ptr.spawnItem(.Grain, drop_pos.x, drop_pos.y);
                } else {
                    world_ptr.spawnItem(.Grain, dying_entity_ptr.x, dying_entity_ptr.y);
                }
            }
        },
        .Tree => {
            log.debug("Tree at {d},{d} was destroyed. (Item drop logic TBD here if not direct collection)", .{ dying_entity_ptr.x, dying_entity_ptr.y });
        },
        .RockCluster => {
            log.debug("RockCluster at {d},{d} was destroyed. (Item drop logic TBD here if not direct collection)", .{ dying_entity_ptr.x, dying_entity_ptr.y });
        },
        .Player => {
            log.info("Player entity died at {d},{d}. Inventory (if any) will be dropped.", .{ dying_entity_ptr.x, dying_entity_ptr.y });
        },
    }

    // 2. Drop All Inventory Items
    log.debug("Processing inventory drop for {any} at {d},{d}", .{ dying_entity_ptr.entity_type, dying_entity_ptr.x, dying_entity_ptr.y });
    for (dying_entity_ptr.inventory, 0..) |slot, i| {
        if (slot.item_type) |item_type_to_drop| {
            if (slot.quantity > 0) {
                log.debug("Dropping {d} of {any} from inventory slot {d}", .{ slot.quantity, item_type_to_drop, i });
                var q: u8 = 0;
                while (q < slot.quantity) : (q += 1) {
                    if (world_ptr.findRandomAdjacentEmptyTile(dying_entity_ptr.x, dying_entity_ptr.y, 8, prng)) |drop_pos| {
                        world_ptr.spawnItem(item_type_to_drop, drop_pos.x, drop_pos.y);
                    } else {
                        world_ptr.spawnItem(item_type_to_drop, dying_entity_ptr.x, dying_entity_ptr.y);
                    }
                }
            }
        }
        dying_entity_ptr.inventory[i].clear();
    }

    dying_entity_ptr.processed_death_drops = true;
    log.info("Finished processing drops for {any} at {d},{d}.", .{ dying_entity_ptr.entity_type, dying_entity_ptr.x, dying_entity_ptr.y });
}
