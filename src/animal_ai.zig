// src/animal_ai.zig
// Shared utility functions for animal AI (Sheep, Bear).
const std_full = @import("std");
const types = @import("types.zig");
const config = @import("config.zig");
const art = @import("art.zig");
const log = std_full.log;
const math = std_full.math;
const RandomInterface = std_full.Random;

// Helper function for integer absolute value
pub fn absInt(x: i32) i32 {
    return if (x < 0) -x else x;
}

// Helper to calculate squared distance between two points
pub fn distSq(x1: i32, y1: i32, x2: i32, y2: i32) i64 {
    const dx = x1 - x2;
    const dy = y1 - y2;
    return @as(i64, dx) * @as(i64, dx) + @as(i64, dy) * @as(i64, dy);
}

// Helper to choose a new random wander target for an entity
pub fn chooseNewWanderTarget(entity: *types.Entity, prng: *RandomInterface, world_width: u32, world_height: u32, is_escape_wander: bool) void {
    const min_s = if (is_escape_wander) config.min_escape_wander_steps else config.min_wander_steps;
    const max_s = if (is_escape_wander) config.max_escape_wander_steps else config.max_wander_steps;
    const steps = prng.intRangeAtMost(u8, min_s, max_s);

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
        else => {
            log.err("Invalid direction in chooseNewWanderTarget: {d}", .{direction});
        },
    }
    entity.wander_target_x = math.clamp(entity.x + dx, 0, @as(i32, @intCast(world_width)) - 1);
    entity.wander_target_y = math.clamp(entity.y + dy, 0, @as(i32, @intCast(world_height)) - 1);
    entity.wander_steps_taken = 0;
    entity.wander_steps_total = steps;
    entity.move_cooldown_ticks = 0;

    // When choosing a general wander target (e.g. from Idle or failed SeekingFood, or escape wander), clear specific targets.
    entity.target_entity_idx = null;
    entity.target_item_idx = null;
    log.debug("{any} at {d},{d} chose new general wander target: {d},{d} (escape: {any}, steps: {d}, was {any})", .{ entity.entity_type, entity.x, entity.y, entity.wander_target_x, entity.wander_target_y, is_escape_wander, steps, entity.current_action });
}

// Helper for an entity to attempt one step towards its current wander_target_x/y
pub fn attemptMoveTowardsWanderTarget(entity: *types.Entity, world: *const types.GameWorld, prng: *RandomInterface) void {
    if (entity.move_cooldown_ticks > 0) {
        entity.move_cooldown_ticks -= 1;
        return;
    }

    if (entity.x == entity.wander_target_x and entity.y == entity.wander_target_y) {
        // If it was wandering (general or escape), or hunting/picking up but target is now gone, become Idle.
        if (entity.current_action == .Wandering or
            (entity.current_action == .Hunting and entity.target_entity_idx == null) or
            (entity.current_action == .PickingUpItem and entity.target_item_idx == null))
        {
            log.debug("{any} at {d},{d} reached target/destination {d},{d}. Action: {any} -> Idle. Clearing must_complete_wander_step.", .{ entity.entity_type, entity.x, entity.y, entity.wander_target_x, entity.wander_target_y, entity.current_action });
            entity.current_action = .Idle;
            entity.must_complete_wander_step = false;
            entity.pathing_attempts_to_current_target = 0;
        }
        // If Hunting/PickingUpItem and target is still valid, the main AI loop will transition to Attacking/actual pickup.
        return;
    }

    var next_x = entity.x;
    var next_y = entity.y;

    if (entity.wander_target_x > entity.x) {
        next_x += 1;
    } else if (entity.wander_target_x < entity.x) {
        next_x -= 1;
    }

    if (entity.wander_target_y > entity.y) {
        next_y += 1;
    } else if (entity.wander_target_y < entity.y) {
        next_y -= 1;
    }

    // Check if stuck (no change in position towards target)
    if (next_x == entity.x and next_y == entity.y and (entity.x != entity.wander_target_x or entity.y != entity.wander_target_y)) {
        log.debug("{any} at {d},{d} seems stuck trying to reach {d},{d} (action: {any}).", .{ entity.entity_type, entity.x, entity.y, entity.wander_target_x, entity.wander_target_y, entity.current_action });
        if (entity.current_action == .Hunting or entity.current_action == .PickingUpItem) {
            entity.pathing_attempts_to_current_target += 1;
            log.debug("... Pathing attempt {d}/{d} for current target.", .{ entity.pathing_attempts_to_current_target, config.max_pathing_attempts_before_give_up });
            if (entity.pathing_attempts_to_current_target >= config.max_pathing_attempts_before_give_up) {
                log.info("... Giving up on current target due to being stuck, will choose an escape wander.", .{});
                if (entity.current_action == .Hunting and entity.target_entity_idx != null) {
                    entity.blocked_target_idx = entity.target_entity_idx;
                    entity.blocked_target_is_item = false;
                    entity.blocked_target_cooldown = config.general_post_action_cooldown; // Use general cooldown
                } else if (entity.current_action == .PickingUpItem and entity.target_item_idx != null) {
                    entity.blocked_target_idx = entity.target_item_idx;
                    entity.blocked_target_is_item = true;
                    entity.blocked_target_cooldown = config.general_post_action_cooldown;
                }
                entity.target_entity_idx = null;
                entity.target_item_idx = null;
                chooseNewWanderTarget(entity, prng, world.width, world.height, true); // true for escape wander
                entity.current_action = .Wandering;
                entity.must_complete_wander_step = true;
                entity.pathing_attempts_to_current_target = 0;
            } else {
                entity.current_action = .Idle; // Pause to re-evaluate next tick, target is kept (unless cleared by Idle logic)
                entity.move_cooldown_ticks = prng.intRangeAtMost(u16, 20, 40);
            }
        } else { // Was a general wander that got stuck
            entity.current_action = .Idle;
            entity.pathing_attempts_to_current_target = 0;
        }
        entity.must_complete_wander_step = false;
        return;
    }

    const art_h: u32 = switch (entity.entity_type) {
        .Sheep => config.sheep_art_height,
        .Bear => config.bear_art_height,
        .Player => config.player_height_pixels,
        else => 1,
    };
    const rules = world.getTerrainMovementRules(entity.entity_type, next_x, next_y, art_h);

    if (rules.can_pass) {
        entity.x = next_x;
        entity.y = next_y;
        if (entity.current_action == .Hunting or entity.current_action == .PickingUpItem) {
            entity.pathing_attempts_to_current_target = 0; // Successful step towards target, reset pathing attempts
        }

        if (entity.current_action == .Wandering) {
            entity.wander_steps_taken += 1;
            // must_complete_wander_step is cleared when the wander completes or becomes Idle
        }

        if (rules.speed_modifier > 0.0 and rules.speed_modifier < 1.0) {
            const cooldown_float = (1.0 / rules.speed_modifier) - 1.0;
            entity.move_cooldown_ticks = @as(u16, @intFromFloat(math.round(cooldown_float)));
        } else {
            entity.move_cooldown_ticks = 0;
        }
    } else { // Path blocked
        if (entity.current_action != .Idle) {
            log.debug("{any} at {d},{d} move to {d},{d} blocked. Current action: {any}.", .{ entity.entity_type, entity.x, entity.y, next_x, next_y, entity.current_action });
        }
        if (entity.current_action == .Hunting or entity.current_action == .PickingUpItem) {
            entity.pathing_attempts_to_current_target += 1;
            log.debug("... Pathing attempt {d}/{d} for current target.", .{ entity.pathing_attempts_to_current_target, config.max_pathing_attempts_before_give_up });
            if (entity.pathing_attempts_to_current_target >= config.max_pathing_attempts_before_give_up) {
                log.info("... Giving up on current target due to blocked path, will choose an escape wander.", .{});
                if (entity.current_action == .Hunting and entity.target_entity_idx != null) {
                    entity.blocked_target_idx = entity.target_entity_idx;
                    entity.blocked_target_is_item = false;
                    entity.blocked_target_cooldown = config.general_post_action_cooldown;
                } else if (entity.current_action == .PickingUpItem and entity.target_item_idx != null) {
                    entity.blocked_target_idx = entity.target_item_idx;
                    entity.blocked_target_is_item = true;
                    entity.blocked_target_cooldown = config.general_post_action_cooldown;
                }
                entity.target_entity_idx = null;
                entity.target_item_idx = null;
                chooseNewWanderTarget(entity, prng, world.width, world.height, true);
                entity.current_action = .Wandering;
                entity.must_complete_wander_step = true;
                entity.pathing_attempts_to_current_target = 0;
            } else {
                entity.current_action = .Idle;
                entity.move_cooldown_ticks = prng.intRangeAtMost(u16, 20, 40);
            }
        } else {
            entity.current_action = .Idle;
            entity.pathing_attempts_to_current_target = 0;
        }
        entity.must_complete_wander_step = false;
    }

    if (entity.current_action == .Wandering and entity.wander_steps_taken >= entity.wander_steps_total) {
        log.debug("{any} at {d},{d} completed wander ({d}/{d} steps). Action: Wandering -> Idle. Clearing must_complete_wander_step.", .{ entity.entity_type, entity.x, entity.y, entity.wander_steps_taken, entity.wander_steps_total });
        entity.current_action = .Idle;
        entity.must_complete_wander_step = false;
        entity.pathing_attempts_to_current_target = 0;
    }
}
