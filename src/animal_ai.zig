// src/animal_ai.zig
// Shared utility functions for animal AI (Sheep, Bear).
// Specific update functions (updateSheep, updateBear) are now in their own files.
const std_full = @import("std");
const types = @import("types.zig");
const config = @import("config.zig");
const art = @import("art.zig"); // For art dimensions
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
// This is now a general utility. The calling AI sets the current_action.
pub fn chooseNewWanderTarget(entity: *types.Entity, prng: *RandomInterface, world_width: u32, world_height: u32) void {
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
        else => {
            log.err("Invalid direction in chooseNewWanderTarget: {d}", .{direction});
        },
    }
    entity.wander_target_x = math.clamp(entity.x + dx, 0, @as(i32, @intCast(world_width)) - 1);
    entity.wander_target_y = math.clamp(entity.y + dy, 0, @as(i32, @intCast(world_height)) - 1);
    entity.wander_steps_taken = 0;
    entity.wander_steps_total = steps + prng.intRangeAtMost(u8, 0, @divTrunc(steps, 2));
    entity.move_cooldown_ticks = 0;

    // Clear specific interaction targets when choosing a general wander target.
    // This is important if the wander is due to failed seeking or general idling.
    if (entity.current_action == .Idle or entity.current_action == .SeekingFood or entity.current_action == .Wandering) {
        entity.target_entity_idx = null;
        entity.target_item_idx = null;
    }
    // Log is now in the calling function or specific AI to provide context of *why* wander target was chosen.
}

// Helper for an entity to attempt one step towards its current wander_target_x/y
pub fn attemptMoveTowardsWanderTarget(entity: *types.Entity, world: *const types.GameWorld, prng: *RandomInterface) void {
    if (entity.move_cooldown_ticks > 0) {
        entity.move_cooldown_ticks -= 1;
        return;
    }

    if (entity.x == entity.wander_target_x and entity.y == entity.wander_target_y) {
        if (entity.current_action == .Wandering or
            (entity.current_action == .Hunting and entity.target_entity_idx == null) or
            (entity.current_action == .PickingUpItem and entity.target_item_idx == null))
        {
            log.debug("{any} at {d},{d} reached target/destination {d},{d}. Action: {any} -> Idle. Resetting must_complete_wander_step.", .{ entity.entity_type, entity.x, entity.y, entity.wander_target_x, entity.wander_target_y, entity.current_action });
            entity.current_action = .Idle;
            entity.must_complete_wander_step = false;
        }
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

    if (next_x == entity.x and next_y == entity.y and (entity.x != entity.wander_target_x or entity.y != entity.wander_target_y)) {
        log.debug("{any} at {d},{d} seems stuck trying to reach {d},{d}. Next calculated step {d},{d} is current pos. Reverting to Idle. Resetting must_complete_wander_step.", .{ entity.entity_type, entity.x, entity.y, entity.wander_target_x, entity.wander_target_y, next_x, next_y });
        entity.current_action = .Idle;
        entity.must_complete_wander_step = false;
        entity.move_cooldown_ticks = prng.intRangeAtMost(u16, 5, 15);
        entity.target_entity_idx = null;
        entity.target_item_idx = null;
        return;
    }

    const art_h: u32 = switch (entity.entity_type) {
        .Sheep => art.sheep_art_height,
        .Bear => art.bear_art_height,
        .Player => config.player_height_pixels,
        else => 1,
    };
    const rules = world.getTerrainMovementRules(entity.entity_type, next_x, next_y, art_h);

    if (rules.can_pass) {
        entity.x = next_x;
        entity.y = next_y;
        if (entity.current_action == .Wandering) {
            entity.wander_steps_taken += 1;
            if (entity.must_complete_wander_step) {
                log.debug("{any} at {d},{d} completed a 'must_complete_wander_step' by moving. Flag cleared.", .{ entity.entity_type, entity.x, entity.y });
                entity.must_complete_wander_step = false;
            }
        }

        if (rules.speed_modifier > 0.0 and rules.speed_modifier < 1.0) {
            const cooldown_float = (1.0 / rules.speed_modifier) - 1.0;
            entity.move_cooldown_ticks = @as(u16, @intFromFloat(math.round(cooldown_float)));
        } else {
            entity.move_cooldown_ticks = 0;
        }
    } else {
        if (entity.current_action != .Idle) {
            log.debug("{any} at {d},{d} move to {d},{d} blocked. Current action: {any}. Becoming Idle. Resetting must_complete_wander_step.", .{ entity.entity_type, entity.x, entity.y, next_x, next_y, entity.current_action });
        }
        entity.current_action = .Idle;
        entity.must_complete_wander_step = false;
        entity.move_cooldown_ticks = prng.intRangeAtMost(u16, 10, 20);
        entity.target_entity_idx = null;
        entity.target_item_idx = null;
    }

    if (entity.current_action == .Wandering and entity.wander_steps_taken >= entity.wander_steps_total) {
        log.debug("{any} at {d},{d} completed wander ({d}/{d} steps). Action: Wandering -> Idle. Resetting must_complete_wander_step.", .{ entity.entity_type, entity.x, entity.y, entity.wander_steps_taken, entity.wander_steps_total });
        entity.current_action = .Idle;
        entity.must_complete_wander_step = false;
    }
}
