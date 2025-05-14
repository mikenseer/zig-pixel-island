// src/animal_ai.zig
// Handles AI logic for Animal entities (Sheep, Bear).
const std_full = @import("std");
const types = @import("types.zig");
const config = @import("config.zig");
const art = @import("art.zig"); // For art dimensions

const RandomInterface = std_full.Random;
const log = std_full.log;
const math = std_full.math; // For @abs

// Helper to choose a new random wander target for an entity
fn chooseNewWanderTarget(entity: *types.Entity, prng: *RandomInterface, world_width: u32, world_height: u32) void {
    const steps = prng.intRangeAtMost(u8, config.min_wander_steps, config.max_wander_steps);
    const direction = prng.intRangeAtMost(u8, 0, 7); // 8 directions

    var dx: i32 = 0;
    var dy: i32 = 0;

    switch (direction) {
        0 => {
            dy = -@as(i32, @intCast(steps));
        }, // N
        1 => {
            dx = @as(i32, @intCast(steps));
            dy = -@as(i32, @intCast(steps));
        }, // NE
        2 => {
            dx = @as(i32, @intCast(steps));
        }, // E
        3 => {
            dx = @as(i32, @intCast(steps));
            dy = @as(i32, @intCast(steps));
        }, // SE
        4 => {
            dy = @as(i32, @intCast(steps));
        }, // S
        5 => {
            dx = -@as(i32, @intCast(steps));
            dy = @as(i32, @intCast(steps));
        }, // SW
        6 => {
            dx = -@as(i32, @intCast(steps));
        }, // W
        7 => {
            dx = -@as(i32, @intCast(steps));
            dy = -@as(i32, @intCast(steps));
        }, // NW
        else => {},
    }

    entity.wander_target_x = math.clamp(entity.x + dx, 0, @as(i32, @intCast(world_width)) - 1);
    entity.wander_target_y = math.clamp(entity.y + dy, 0, @as(i32, @intCast(world_height)) - 1);

    entity.current_action = .Wandering;
    entity.wander_steps_taken = 0;
    entity.wander_steps_total = steps * 2;
    entity.move_cooldown_ticks = 0;
}

// Helper for an entity to attempt one step towards its wander target
fn attemptMoveTowardsWanderTarget(entity: *types.Entity, world: *const types.GameWorld, prng: *RandomInterface) void {
    _ = prng;

    if (entity.move_cooldown_ticks > 0) {
        entity.move_cooldown_ticks -= 1;
        return;
    }

    if (entity.x == entity.wander_target_x and entity.y == entity.wander_target_y) {
        entity.current_action = .Idle;
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

    if (next_x == entity.x and next_y == entity.y) {
        if (entity.wander_target_x == entity.x and entity.wander_target_y != entity.y) {
            if (entity.wander_target_y > entity.y) {
                next_y += 1;
            } else {
                next_y -= 1;
            }
        } else if (entity.wander_target_y == entity.y and entity.wander_target_x != entity.x) {
            if (entity.wander_target_x > entity.x) {
                next_x += 1;
            } else {
                next_x -= 1;
            }
        } else {
            entity.current_action = .Idle;
            return;
        }
    }

    const art_h: u32 = switch (entity.entity_type) {
        .Sheep => art.sheep_art_height,
        .Bear => art.bear_art_height,
        else => 1,
    };
    const rules = world.getTerrainMovementRules(entity.entity_type, next_x, next_y, art_h);

    if (rules.can_pass) {
        entity.x = next_x;
        entity.y = next_y;
        entity.wander_steps_taken += 1;

        if (rules.speed_modifier > 0.0 and rules.speed_modifier < 1.0) {
            const cooldown_float = (1.0 / rules.speed_modifier) - 1.0;
            entity.move_cooldown_ticks = @as(u16, @intFromFloat(@max(0.0, cooldown_float)));
        } else {
            entity.move_cooldown_ticks = 0;
        }

        if (entity.x == entity.wander_target_x and entity.y == entity.wander_target_y) {
            entity.current_action = .Idle;
        }
    } else {
        entity.current_action = .Idle;
        entity.move_cooldown_ticks = 3;
    }

    if (entity.wander_steps_taken >= entity.wander_steps_total) {
        entity.current_action = .Idle;
    }
}

pub fn updateSheep(sheep: *types.Entity, world: *const types.GameWorld, prng: *RandomInterface) void {
    if (sheep.entity_type != .Sheep) {
        return;
    }

    if (prng.float(f32) < config.sheep_move_attempt_chance) {
        switch (sheep.current_action) {
            .Idle => chooseNewWanderTarget(sheep, prng, world.width, world.height),
            .Wandering => attemptMoveTowardsWanderTarget(sheep, world, prng),
        }
    } else {
        if (sheep.move_cooldown_ticks > 0) {
            sheep.move_cooldown_ticks -= 1;
        }
    }
}

pub fn updateBear(bear: *types.Entity, world: *const types.GameWorld, prng: *RandomInterface) void {
    if (bear.entity_type != .Bear) {
        return;
    }

    if (prng.float(f32) < config.bear_move_attempt_chance) {
        switch (bear.current_action) {
            .Idle => chooseNewWanderTarget(bear, prng, world.width, world.height),
            .Wandering => attemptMoveTowardsWanderTarget(bear, world, prng),
        }
    } else {
        if (bear.move_cooldown_ticks > 0) {
            bear.move_cooldown_ticks -= 1;
        }
    }
}
