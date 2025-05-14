// src/peon_ai.zig
// Handles AI logic for Peon entities.
const std_full = @import("std");
const types = @import("types.zig");
const config = @import("config.zig");
const art = @import("art.zig");
const items = @import("items.zig"); // For item interaction later
// const combat = @import("combat.zig"); // Will be needed for hunting/attacking

const RandomInterface = std_full.Random;
const log = std_full.log;
const math = std_full.math;

// Helper to choose a new random wander target for a Peon
fn chooseNewWanderTargetPeon(peon: *types.Entity, prng: *RandomInterface, world_width: u32, world_height: u32) void {
    const steps = prng.intRangeAtMost(u8, config.min_wander_steps, config.max_wander_steps);
    const direction = prng.intRangeAtMost(u8, 0, 7);
    var dx: i32 = 0;
    var dy: i32 = 0;
    switch (direction) {
        0 => dy = -@as(i32, @intCast(steps)),
        1 => {
            dx = @as(i32, @intCast(steps));
            dy = -@as(i32, @intCast(steps));
        },
        2 => dx = @as(i32, @intCast(steps)),
        3 => {
            dx = @as(i32, @intCast(steps));
            dy = @as(i32, @intCast(steps));
        },
        4 => dy = @as(i32, @intCast(steps)),
        5 => {
            dx = -@as(i32, @intCast(steps));
            dy = @as(i32, @intCast(steps));
        },
        6 => dx = -@as(i32, @intCast(steps)),
        7 => {
            dx = -@as(i32, @intCast(steps));
            dy = -@as(i32, @intCast(steps));
        },
        else => {},
    }
    peon.wander_target_x = math.clamp(peon.x + dx, 0, @as(i32, @intCast(world_width)) - 1);
    peon.wander_target_y = math.clamp(peon.y + dy, 0, @as(i32, @intCast(world_height)) - 1);
    peon.current_action = .Wandering;
    peon.wander_steps_taken = 0;
    peon.wander_steps_total = steps * 2;
    peon.move_cooldown_ticks = 0;
}

// Helper for a Peon to attempt one step towards its wander target
fn attemptMoveTowardsWanderTargetPeon(peon: *types.Entity, world: *const types.GameWorld, prng: *RandomInterface) void {
    _ = prng;
    if (peon.move_cooldown_ticks > 0) {
        peon.move_cooldown_ticks -= 1;
        return;
    }
    if (peon.x == peon.wander_target_x and peon.y == peon.wander_target_y) {
        peon.current_action = .Idle;
        return;
    }
    var next_x = peon.x;
    var next_y = peon.y;
    if (peon.wander_target_x > peon.x) {
        next_x += 1;
    } else if (peon.wander_target_x < peon.x) {
        next_x -= 1;
    }
    if (peon.wander_target_y > peon.y) {
        next_y += 1;
    } else if (peon.wander_target_y < peon.y) {
        next_y -= 1;
    }
    if (next_x == peon.x and next_y == peon.y) {
        if (peon.wander_target_x == peon.x and peon.wander_target_y != peon.y) {
            if (peon.wander_target_y > peon.y) next_y += 1 else next_y -= 1;
        } else if (peon.wander_target_y == peon.y and peon.wander_target_x != peon.x) {
            if (peon.wander_target_x > peon.x) next_x += 1 else next_x -= 1;
        } else {
            peon.current_action = .Idle;
            return;
        }
    }
    const rules = world.getTerrainMovementRules(types.EntityType.Player, next_x, next_y, config.player_height_pixels);
    if (rules.can_pass) {
        peon.x = next_x;
        peon.y = next_y;
        peon.wander_steps_taken += 1;
        if (rules.speed_modifier > 0.0 and rules.speed_modifier < 1.0) {
            const cooldown_float = (1.0 / rules.speed_modifier) - 1.0;
            peon.move_cooldown_ticks = @as(u16, @intFromFloat(@max(0.0, cooldown_float)));
        } else {
            peon.move_cooldown_ticks = 0;
        }
        if (peon.x == peon.wander_target_x and peon.y == peon.wander_target_y) {
            peon.current_action = .Idle;
        }
    } else {
        peon.current_action = .Idle;
        peon.move_cooldown_ticks = 3;
    }
    if (peon.wander_steps_taken >= peon.wander_steps_total) {
        peon.current_action = .Idle;
    }
}

pub fn updatePeon(peon: *types.Entity, world: *const types.GameWorld, prng: *RandomInterface) void {
    if (peon.entity_type != .Player) return;

    // Death check (though main loop also handles removal, AI might react to its own death)
    if (peon.current_hp == 0) {
        // Peon specific death logic (e.g. dropping items from inventory if any)
        // For now, just log. Item drops are handled by main loop after this AI update.
        // Or, if peon AI should handle its *own* item drops, do it here.
        // For consistency with animal_ai, let's assume main loop handles removal,
        // but AI can react to being dead (e.g., stop further actions).
        // If a peon dies, it won't drop meat/corpse like animals.
        // It might drop its inventory in the future.
        return;
    }

    // TODO: Implement hunger check: if current_hp / max_hp < config.peon_hunger_threshold_percent, change action to .SeekingFood
    // TODO: Implement .SeekingFood: find nearest Meat item or Sheep. If Sheep, change to .Hunting. If Meat, change to .PickingUpItem
    // TODO: Implement .Hunting: move towards target_entity_idx (Sheep). If adjacent, change to .Attacking.
    // TODO: Implement .Attacking: call combat.resolveAttack. If target dies, change to .PickingUpItem (for meat).
    // TODO: Implement .PickingUpItem: move towards target_item_idx. If adjacent, pick up, add to inventory. If inventory full, or item is food, change to .Eating.
    // TODO: Implement .Eating: if has Meat in inventory, consume it, gain HP, remove from inventory. Change to .Idle or .Wandering.
    // TODO: Implement .Fleeing: if threatened (e.g. by Bear).

    // CORRECTED: Added else case for exhaustive switch
    switch (peon.current_action) {
        .Idle => chooseNewWanderTargetPeon(peon, prng, world.width, world.height),
        .Wandering => attemptMoveTowardsWanderTargetPeon(peon, world, prng),
        // Placeholder for new states
        .SeekingFood, .Hunting, .Attacking, .Eating, .PickingUpItem, .Fleeing => {
            // For now, if in an unimplemented state, revert to wandering or idle
            // This prevents getting stuck.
            // log.debug("Peon in unimplemented state: {any}, reverting to wander.", .{peon.current_action});
            chooseNewWanderTargetPeon(peon, prng, world.width, world.height);
        },
    }
}
