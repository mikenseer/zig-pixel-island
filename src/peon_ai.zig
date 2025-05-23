// src/peon_ai.zig
// Handles AI logic for Peon entities.
const std_full = @import("std");
const types = @import("types.zig");
const config = @import("config.zig");
const items_module = @import("items.zig");
const inventory = @import("inventory.zig");
const entity_processing = @import("entity_processing.zig"); // NEW

const RandomInterface = std_full.Random;
const log = std_full.log;
const math = std_full.math;

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
    peon.target_entity_idx = null;
    peon.target_item_idx = null;
    peon.must_complete_wander_step = false;
}

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

pub fn updatePeon(peon_ptr: *types.Entity, world_ptr: *types.GameWorld, prng: *RandomInterface) void {
    if (peon_ptr.entity_type != .Player) return;

    // Process HP decay first for this entity
    entity_processing.processHpDecay(peon_ptr); // NEW

    if (peon_ptr.current_hp == 0) return; // Check if died from decay

    switch (peon_ptr.current_action) {
        .Idle => chooseNewWanderTargetPeon(peon_ptr, prng, world_ptr.width, world_ptr.height),
        .Wandering => attemptMoveTowardsWanderTargetPeon(peon_ptr, world_ptr, prng),
        .SeekingFood, .Hunting, .Attacking, .Eating, .PickingUpItem, .Fleeing => {
            chooseNewWanderTargetPeon(peon_ptr, prng, world_ptr.width, world_ptr.height);
        },
    }
}
