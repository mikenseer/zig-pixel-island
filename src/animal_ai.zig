// src/animal_ai.zig
// Handles AI logic for Animal entities (Sheep, Bear).
const std_full = @import("std");
const types = @import("types.zig");
const config = @import("config.zig");
const art = @import("art.zig");
const items = @import("items.zig");
const math = std_full.math; // For general math functions like clamp, @max
const log = std_full.log;
const RandomInterface = std_full.Random;

// Helper function for integer absolute value
fn absInt(x: i32) i32 {
    return if (x < 0) -x else x;
}

// Helper to calculate squared distance between two points
fn distSq(x1: i32, y1: i32, x2: i32, y2: i32) i64 {
    const dx = x1 - x2;
    const dy = y1 - y2;
    return @as(i64, dx) * @as(i64, dx) + @as(i64, dy) * @as(i64, dy);
}

// Helper to choose a new random wander target for an entity
fn chooseNewWanderTarget(entity: *types.Entity, prng: *RandomInterface, world_width: u32, world_height: u32) void {
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
    entity.wander_target_x = math.clamp(entity.x + dx, 0, @as(i32, @intCast(world_width)) - 1);
    entity.wander_target_y = math.clamp(entity.y + dy, 0, @as(i32, @intCast(world_height)) - 1);
    entity.current_action = .Wandering;
    entity.wander_steps_taken = 0;
    entity.wander_steps_total = steps * 2;
    entity.move_cooldown_ticks = 0;
    entity.target_entity_idx = null;
    entity.target_item_idx = null;
}

// Helper for an entity to attempt one step towards its current wander_target_x/y
fn attemptMoveTowardsWanderTarget(entity: *types.Entity, world: *const types.GameWorld, prng: *RandomInterface) void {
    if (entity.move_cooldown_ticks > 0) {
        entity.move_cooldown_ticks -= 1;
        return;
    }
    if ((entity.x == entity.wander_target_x and entity.y == entity.wander_target_y)) {
        if (entity.current_action == .Wandering or entity.target_entity_idx == null and entity.target_item_idx == null) {
            entity.current_action = .Idle;
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

    if (next_x == entity.x and next_y == entity.y) {
        if (entity.wander_target_x == entity.x and entity.y != entity.wander_target_y) {
            if (entity.wander_target_y > entity.y) next_y += 1 else next_y -= 1;
        } else if (entity.wander_target_y == entity.y and entity.x != entity.wander_target_x) {
            if (entity.wander_target_x > entity.x) next_x += 1 else next_x -= 1;
        } else {
            if (entity.current_action == .Wandering) entity.current_action = .Idle;
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
        if (entity.current_action == .Wandering) {
            entity.wander_steps_taken += 1;
        }

        if (rules.speed_modifier > 0.0 and rules.speed_modifier < 1.0) {
            const cooldown_float = (1.0 / rules.speed_modifier) - 1.0;
            entity.move_cooldown_ticks = @as(u16, @intFromFloat(math.round(cooldown_float))); // Use math.round for float to int
        } else {
            entity.move_cooldown_ticks = 0;
        }
    } else {
        if (entity.current_action != .Idle) {
            log.debug("{any} move blocked to {d},{d}, becoming Idle.", .{ entity.entity_type, next_x, next_y });
        }
        entity.current_action = .Idle;
        entity.move_cooldown_ticks = prng.intRangeAtMost(u16, 3, 10);
        entity.target_entity_idx = null;
        entity.target_item_idx = null;
    }

    if (entity.current_action == .Wandering and entity.wander_steps_taken >= entity.wander_steps_total) {
        entity.current_action = .Idle;
    }
}

// Updates the AI state for a Sheep entity
pub fn updateSheep(sheep: *types.Entity, world_ptr: *types.GameWorld, prng: *RandomInterface) void {
    if (sheep.entity_type != .Sheep) return;

    if (sheep.current_hp == 0) {
        if (!sheep.processed_death_drops) {
            log.info("Sheep AI: I am dead at {d},{d}. Dropping items.", .{ sheep.x, sheep.y });
            world_ptr.spawnItem(.CorpseSheep, sheep.x, sheep.y);
            var m: u8 = 0;
            while (m < config.meat_drops_from_sheep) : (m += 1) {
                if (world_ptr.findRandomAdjacentEmptyTile(sheep.x, sheep.y, 8, prng)) |drop_pos| {
                    world_ptr.spawnItem(.Meat, drop_pos.x, drop_pos.y);
                } else {
                    world_ptr.spawnItem(.Meat, sheep.x, sheep.y);
                }
            }
            sheep.processed_death_drops = true;
        }
        return;
    }

    if (sheep.current_action_timer > 0) {
        sheep.current_action_timer -= 1;
        if (sheep.current_action_timer == 0) {
            switch (sheep.current_action) {
                .Eating => {
                    if (sheep.inventory[0].item_type == .Grain and sheep.inventory[0].quantity > 0) {
                        _ = sheep.removeFromInventory(0, 1);
                        sheep.current_hp = @min(sheep.max_hp, sheep.current_hp + config.grain_hp_gain_sheep);
                        log.debug("Sheep ate Grain. HP: {d}/{d}", .{ sheep.current_hp, sheep.max_hp });
                    } else {
                        log.warn("Sheep finished eating action but had no grain in inventory slot 0.", .{});
                    }
                    sheep.current_action = .Idle;
                },
                .Attacking => {
                    if (sheep.target_entity_idx) |target_idx| {
                        if (target_idx < world_ptr.entities.items.len) {
                            var target_brush_ptr = &world_ptr.entities.items[target_idx];
                            if (target_brush_ptr.entity_type == .Brush and target_brush_ptr.current_hp > 0) {
                                target_brush_ptr.current_hp -= config.sheep_damage_vs_brush;
                                log.debug("Sheep attacked Brush ({d}/{d} HP).", .{ target_brush_ptr.current_hp, target_brush_ptr.max_hp });
                                if (target_brush_ptr.current_hp <= 0) {
                                    target_brush_ptr.current_hp = 0;
                                    log.info("Sheep destroyed Brush at {d},{d}.", .{ target_brush_ptr.x, target_brush_ptr.y });
                                    sheep.target_entity_idx = null;
                                    sheep.current_action = .SeekingFood;
                                } else {
                                    sheep.attack_cooldown = config.harvest_brush_cooldown_ticks;
                                }
                            } else {
                                sheep.target_entity_idx = null;
                                sheep.current_action = .Idle;
                            }
                        } else {
                            sheep.target_entity_idx = null;
                            sheep.current_action = .Idle;
                        }
                    } else {
                        sheep.current_action = .Idle;
                    }
                },
                else => {},
            }
        }
        if (sheep.current_action == .Eating or (sheep.current_action == .Attacking and sheep.current_action_timer > 0)) return;
    }

    if (sheep.attack_cooldown > 0) {
        sheep.attack_cooldown -= 1;
        if (sheep.current_action == .Attacking) return;
    }

    const general_hunger_hp_threshold = @as(i16, @intFromFloat(@as(f32, @floatFromInt(sheep.max_hp)) * config.animal_hunger_threshold_percent));
    const grain_priority_hunger_hp_threshold = @as(i16, @intFromFloat(@as(f32, @floatFromInt(sheep.max_hp)) * config.sheep_hunger_threshold_for_grain_percent));

    if ((sheep.current_hp < grain_priority_hunger_hp_threshold or sheep.current_hp < general_hunger_hp_threshold) and
        (sheep.current_action == .Idle or sheep.current_action == .Wandering))
    {
        sheep.current_action = .SeekingFood;
        sheep.target_entity_idx = null;
        sheep.target_item_idx = null;
    }

    switch (sheep.current_action) {
        .Idle => {
            if (sheep.current_hp < grain_priority_hunger_hp_threshold or sheep.current_hp < general_hunger_hp_threshold) {
                sheep.current_action = .SeekingFood;
            } else {
                if (prng.float(f32) < config.sheep_move_attempt_chance) {
                    chooseNewWanderTarget(sheep, prng, world_ptr.width, world_ptr.height);
                }
            }
        },
        .Wandering => {
            if (sheep.current_hp < grain_priority_hunger_hp_threshold or sheep.current_hp < general_hunger_hp_threshold) {
                sheep.current_action = .SeekingFood;
            } else {
                if (prng.float(f32) < config.sheep_move_attempt_chance) {
                    attemptMoveTowardsWanderTarget(sheep, world_ptr, prng);
                } else {
                    if (sheep.move_cooldown_ticks > 0) sheep.move_cooldown_ticks -= 1;
                }
            }
        },
        .SeekingFood => {
            var found_food_this_tick = false;
            if (sheep.current_hp < grain_priority_hunger_hp_threshold and sheep.countInInventory(.Grain) > 0) {
                sheep.current_action = .Eating;
                sheep.current_action_timer = config.eating_duration_ticks;
                log.debug("Sheep is hungry and has Grain, starting to eat from inventory.", .{});
                found_food_this_tick = true;
            }
            if (!found_food_this_tick and sheep.current_hp < grain_priority_hunger_hp_threshold and sheep.target_item_idx == null) {
                var closest_grain_idx: ?usize = null;
                var min_dist_sq_grain: i64 = -1;
                for (world_ptr.items.items, 0..) |*item, idx| {
                    if (item.item_type == .Grain) {
                        const d_sq = distSq(sheep.x, sheep.y, item.x, item.y);
                        if (d_sq <= config.animal_food_sight_radius * config.animal_food_sight_radius) {
                            if (closest_grain_idx == null or d_sq < min_dist_sq_grain) {
                                min_dist_sq_grain = d_sq;
                                closest_grain_idx = idx;
                            }
                        }
                    }
                }
                if (closest_grain_idx) |idx| {
                    sheep.target_item_idx = idx;
                    sheep.wander_target_x = world_ptr.items.items[idx].x;
                    sheep.wander_target_y = world_ptr.items.items[idx].y;
                    sheep.current_action = .PickingUpItem;
                    log.debug("Sheep found Grain item at {d},{d}, moving to pick up.", .{ sheep.wander_target_x, sheep.wander_target_y });
                    found_food_this_tick = true;
                }
            }
            if (!found_food_this_tick and sheep.current_hp < general_hunger_hp_threshold and sheep.target_entity_idx == null) {
                var closest_brush_idx: ?usize = null;
                var min_dist_sq_brush: i64 = -1;
                for (world_ptr.entities.items, 0..) |*other_entity, idx| {
                    if (other_entity.entity_type == .Brush and other_entity.current_hp > 0) {
                        const d_sq = distSq(sheep.x, sheep.y, other_entity.x, other_entity.y);
                        if (d_sq <= config.animal_food_sight_radius * config.animal_food_sight_radius) {
                            if (closest_brush_idx == null or d_sq < min_dist_sq_brush) {
                                min_dist_sq_brush = d_sq;
                                closest_brush_idx = idx;
                            }
                        }
                    }
                }
                if (closest_brush_idx) |idx| {
                    sheep.target_entity_idx = idx;
                    sheep.wander_target_x = world_ptr.entities.items[idx].x;
                    sheep.wander_target_y = world_ptr.entities.items[idx].y;
                    sheep.current_action = .Hunting;
                    log.debug("Sheep found Brush entity at {d},{d}, moving to harvest.", .{ sheep.wander_target_x, sheep.wander_target_y });
                    found_food_this_tick = true;
                }
            }

            if (found_food_this_tick) {
                if (sheep.current_action == .PickingUpItem or sheep.current_action == .Hunting) {
                    attemptMoveTowardsWanderTarget(sheep, world_ptr, prng);
                }
            } else {
                sheep.current_action = .Idle;
                sheep.move_cooldown_ticks = prng.intRangeAtMost(u16, 30, 90);
            }
        },
        .PickingUpItem => {
            if (sheep.target_item_idx) |target_idx| {
                if (target_idx < world_ptr.items.items.len) {
                    const target_item = world_ptr.items.items[target_idx];
                    if (target_item.item_type == .Grain) {
                        if (sheep.x == target_item.x and sheep.y == target_item.y) {
                            if (sheep.addToInventory(.Grain, 1)) {
                                log.debug("Sheep picked up Grain.", .{});
                                _ = world_ptr.items.orderedRemove(target_idx);
                                sheep.target_item_idx = null;
                                if (sheep.current_hp < sheep.max_hp) {
                                    sheep.current_action = .Eating;
                                    sheep.current_action_timer = config.eating_duration_ticks;
                                } else {
                                    sheep.current_action = .Idle;
                                }
                            } else {
                                log.debug("Sheep inventory full, cannot pick up Grain.", .{});
                                sheep.target_item_idx = null;
                                sheep.current_action = .Idle;
                            }
                        } else {
                            sheep.wander_target_x = target_item.x;
                            sheep.wander_target_y = target_item.y;
                            attemptMoveTowardsWanderTarget(sheep, world_ptr, prng);
                        }
                    } else {
                        sheep.target_item_idx = null;
                        sheep.current_action = .SeekingFood;
                    }
                } else {
                    sheep.target_item_idx = null;
                    sheep.current_action = .SeekingFood;
                }
            } else {
                sheep.current_action = .SeekingFood;
            }
        },
        .Hunting => {
            if (sheep.target_entity_idx) |target_idx| {
                if (target_idx < world_ptr.entities.items.len) {
                    const target_brush = world_ptr.entities.items[target_idx];
                    if (target_brush.entity_type == .Brush and target_brush.current_hp > 0) {
                        // CORRECTED: Use absInt helper function
                        if (absInt(sheep.x - target_brush.x) <= 1 and absInt(sheep.y - target_brush.y) <= 1 and
                            (absInt(sheep.x - target_brush.x) + absInt(sheep.y - target_brush.y) <= 1))
                        {
                            sheep.current_action = .Attacking;
                            sheep.attack_cooldown = 0;
                            sheep.current_action_timer = config.harvest_brush_cooldown_ticks;
                            log.debug("Sheep reached Brush, preparing to harvest.", .{});
                        } else {
                            sheep.wander_target_x = target_brush.x;
                            sheep.wander_target_y = target_brush.y;
                            attemptMoveTowardsWanderTarget(sheep, world_ptr, prng);
                        }
                    } else {
                        sheep.target_entity_idx = null;
                        sheep.current_action = .Idle;
                    }
                } else {
                    sheep.target_entity_idx = null;
                    sheep.current_action = .Idle;
                }
            } else {
                sheep.current_action = .Idle;
            }
        },
        .Attacking => {
            if (sheep.attack_cooldown == 0) {
                sheep.current_action_timer = config.harvest_brush_cooldown_ticks;
            }
        },
        .Eating => {},
        .Fleeing => {
            chooseNewWanderTarget(sheep, prng, world_ptr.width, world_ptr.height);
        },
    }
}

// Updates the AI state for a Bear entity
pub fn updateBear(bear: *types.Entity, world_ptr: *types.GameWorld, prng: *RandomInterface) void {
    if (bear.entity_type != .Bear) return;

    if (bear.current_hp == 0) {
        if (!bear.processed_death_drops) {
            log.info("Bear AI: I am dead at {d},{d}. Dropping items.", .{ bear.x, bear.y });
            world_ptr.spawnItem(.CorpseBear, bear.x, bear.y);
            var m: u8 = 0;
            while (m < config.meat_drops_from_bear) : (m += 1) {
                if (world_ptr.findRandomAdjacentEmptyTile(bear.x, bear.y, 8, prng)) |drop_pos| {
                    world_ptr.spawnItem(.Meat, drop_pos.x, drop_pos.y);
                } else {
                    world_ptr.spawnItem(.Meat, bear.x, bear.y);
                }
            }
            bear.processed_death_drops = true;
        }
        return;
    }

    if (prng.float(f32) < config.bear_move_attempt_chance) {
        switch (bear.current_action) {
            .Idle => chooseNewWanderTarget(bear, prng, world_ptr.width, world_ptr.height),
            .Wandering => attemptMoveTowardsWanderTarget(bear, world_ptr, prng),
            else => {
                chooseNewWanderTarget(bear, prng, world_ptr.width, world_ptr.height);
            },
        }
    } else {
        if (bear.move_cooldown_ticks > 0) {
            bear.move_cooldown_ticks -= 1;
        }
    }
}
