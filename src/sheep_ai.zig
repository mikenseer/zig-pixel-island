// src/sheep_ai.zig
// Handles AI logic for Sheep entities.
const std_full = @import("std");
const types = @import("types.zig");
const config = @import("config.zig");
const art = @import("art.zig");
const items = @import("items.zig");
const inventory = @import("inventory.zig");
const combat = @import("combat.zig");
const animal_ai_utils = @import("animal_ai.zig");
const entity_processing = @import("entity_processing.zig"); // NEW

const log = std_full.log;
const math = std_full.math;
const RandomInterface = std_full.Random;

// Updates the AI state for a Sheep entity
pub fn updateSheep(sheep_ptr: *types.Entity, world_ptr: *types.GameWorld, prng: *RandomInterface) void {
    if (sheep_ptr.entity_type != .Sheep) {
        return;
    }

    // Process HP decay first for this entity
    entity_processing.processHpDecay(sheep_ptr); // NEW

    if (sheep_ptr.current_hp == 0) { // Check if died from decay
        return;
    }

    const general_hunger_hp_threshold = @as(i16, @intFromFloat(@as(f32, @floatFromInt(sheep_ptr.max_hp)) * config.animal_hunger_threshold_percent));
    const grain_priority_hunger_hp_threshold = @as(i16, @intFromFloat(@as(f32, @floatFromInt(sheep_ptr.max_hp)) * config.sheep_hunger_threshold_for_grain_percent));
    const is_hungry_for_grain = sheep_ptr.current_hp < grain_priority_hunger_hp_threshold;
    const is_generally_hungry = sheep_ptr.current_hp < general_hunger_hp_threshold;
    const is_hungry = is_hungry_for_grain or is_generally_hungry;

    // --- Eating Timer ---
    if (sheep_ptr.current_action == .Eating) {
        if (sheep_ptr.current_action_timer > 0) {
            sheep_ptr.current_action_timer -= 1;
            if (sheep_ptr.current_action_timer == 0) {
                if (sheep_ptr.inventory[0].item_type == .Grain and sheep_ptr.inventory[0].quantity > 0) {
                    _ = inventory.removeFromInventory(sheep_ptr, 0, 1);
                    sheep_ptr.current_hp = @min(sheep_ptr.max_hp, sheep_ptr.current_hp + config.grain_hp_gain_sheep);
                    log.debug("Sheep at {d},{d} finished eating Grain. HP: {d}/{d}", .{ sheep_ptr.x, sheep_ptr.y, sheep_ptr.current_hp, sheep_ptr.max_hp });
                } else {
                    log.warn("Sheep at {d},{d} finished .Eating action but had no Grain in inventory slot 0.", .{ sheep_ptr.x, sheep_ptr.y });
                }
                sheep_ptr.current_action = .Idle;
                sheep_ptr.must_complete_wander_step = false;
            }
        }
        return;
    }

    // --- Attack/Harvest Cooldown ---
    if (sheep_ptr.attack_cooldown > 0) {
        sheep_ptr.attack_cooldown -= 1;
    }

    // --- Initial hunger check if Idle ---
    if (is_hungry and sheep_ptr.current_action == .Idle) {
        log.debug("Sheep at {d},{d} is Idle and hungry (HP: {d}/{d}). Transitioning to SeekingFood.", .{ sheep_ptr.x, sheep_ptr.y, sheep_ptr.current_hp, sheep_ptr.max_hp });
        sheep_ptr.current_action = .SeekingFood;
        sheep_ptr.target_entity_idx = null;
        sheep_ptr.target_item_idx = null;
        sheep_ptr.must_complete_wander_step = false;
    }

    // --- Main AI State Machine ---
    switch (sheep_ptr.current_action) {
        .Idle => {
            if (!is_hungry) {
                if (prng.float(f32) < config.sheep_move_attempt_chance) {
                    animal_ai_utils.chooseNewWanderTarget(sheep_ptr, prng, world_ptr.width, world_ptr.height);
                    sheep_ptr.current_action = .Wandering;
                    sheep_ptr.must_complete_wander_step = false;
                }
            }
        },
        .Wandering => {
            if (sheep_ptr.must_complete_wander_step) {
                animal_ai_utils.attemptMoveTowardsWanderTarget(sheep_ptr, world_ptr, prng);
            } else if (is_hungry) {
                log.debug("Sheep at {d},{d} became hungry (HP: {d}/{d}) during normal Wander. Transitioning to SeekingFood.", .{ sheep_ptr.x, sheep_ptr.y, sheep_ptr.current_hp, sheep_ptr.max_hp });
                sheep_ptr.current_action = .SeekingFood;
                sheep_ptr.target_entity_idx = null;
                sheep_ptr.target_item_idx = null;
            } else {
                animal_ai_utils.attemptMoveTowardsWanderTarget(sheep_ptr, world_ptr, prng);
            }
        },
        .SeekingFood => {
            var found_food_target_this_tick = false;
            sheep_ptr.must_complete_wander_step = false;

            if (is_hungry_for_grain and inventory.countInInventory(sheep_ptr, .Grain) > 0) {
                sheep_ptr.current_action = .Eating;
                sheep_ptr.current_action_timer = config.eating_duration_ticks;
                found_food_target_this_tick = true;
            }

            if (!found_food_target_this_tick and is_hungry_for_grain and sheep_ptr.target_item_idx == null) {
                var closest_grain_idx: ?usize = null;
                var min_dist_sq_grain: i64 = -1;
                for (world_ptr.items.items, 0..) |*item_on_ground, idx| {
                    if (item_on_ground.item_type == .Grain) {
                        const d_sq = animal_ai_utils.distSq(sheep_ptr.x, sheep_ptr.y, item_on_ground.x, item_on_ground.y);
                        if (d_sq <= config.animal_food_sight_radius * config.animal_food_sight_radius) {
                            if (closest_grain_idx == null or d_sq < min_dist_sq_grain) {
                                min_dist_sq_grain = d_sq;
                                closest_grain_idx = idx;
                            }
                        }
                    }
                }
                if (closest_grain_idx) |idx| {
                    sheep_ptr.target_item_idx = idx;
                    sheep_ptr.wander_target_x = world_ptr.items.items[idx].x;
                    sheep_ptr.wander_target_y = world_ptr.items.items[idx].y;
                    sheep_ptr.current_action = .PickingUpItem;
                    found_food_target_this_tick = true;
                }
            }

            if (!found_food_target_this_tick and is_generally_hungry and sheep_ptr.target_entity_idx == null) {
                var closest_brush_idx: ?usize = null;
                var min_dist_sq_brush: i64 = -1;
                for (world_ptr.entities.items, 0..) |*other_entity, idx| {
                    if (other_entity.entity_type == .Brush and other_entity.current_hp > 0) {
                        const d_sq = animal_ai_utils.distSq(sheep_ptr.x, sheep_ptr.y, other_entity.x, other_entity.y);
                        if (d_sq <= config.animal_food_sight_radius * config.animal_food_sight_radius) {
                            if (closest_brush_idx == null or d_sq < min_dist_sq_brush) {
                                min_dist_sq_brush = d_sq;
                                closest_brush_idx = idx;
                            }
                        }
                    }
                }
                if (closest_brush_idx) |idx| {
                    sheep_ptr.target_entity_idx = idx;
                    sheep_ptr.wander_target_x = world_ptr.entities.items[idx].x;
                    sheep_ptr.wander_target_y = world_ptr.entities.items[idx].y;
                    sheep_ptr.current_action = .Hunting;
                    found_food_target_this_tick = true;
                }
            }

            if (found_food_target_this_tick) {
                if (sheep_ptr.current_action == .PickingUpItem or sheep_ptr.current_action == .Hunting) {
                    animal_ai_utils.attemptMoveTowardsWanderTarget(sheep_ptr, world_ptr, prng);
                }
            } else {
                log.debug("Sheep at {d},{d} found no food targets while SeekingFood. Will wander.", .{ sheep_ptr.x, sheep_ptr.y });
                animal_ai_utils.chooseNewWanderTarget(sheep_ptr, prng, world_ptr.width, world_ptr.height);
                sheep_ptr.current_action = .Wandering;
                sheep_ptr.must_complete_wander_step = true;
            }
        },
        .PickingUpItem => {
            sheep_ptr.must_complete_wander_step = false;
            if (sheep_ptr.target_item_idx) |target_idx| {
                if (target_idx < world_ptr.items.items.len) {
                    const target_item = world_ptr.items.items[target_idx];
                    if (target_item.item_type == .Grain) {
                        if (sheep_ptr.x == target_item.x and sheep_ptr.y == target_item.y) {
                            if (inventory.addToInventory(sheep_ptr, .Grain, 1)) {
                                _ = world_ptr.items.orderedRemove(target_idx);
                                sheep_ptr.target_item_idx = null;
                                if (is_hungry) {
                                    sheep_ptr.current_action = .Eating;
                                    sheep_ptr.current_action_timer = config.eating_duration_ticks;
                                } else {
                                    sheep_ptr.current_action = .Idle;
                                }
                            } else {
                                sheep_ptr.target_item_idx = null;
                                sheep_ptr.current_action = .Idle;
                            }
                        } else {
                            sheep_ptr.wander_target_x = target_item.x;
                            sheep_ptr.wander_target_y = target_item.y;
                            animal_ai_utils.attemptMoveTowardsWanderTarget(sheep_ptr, world_ptr, prng);
                        }
                    } else {
                        sheep_ptr.target_item_idx = null;
                        sheep_ptr.current_action = .SeekingFood;
                    }
                } else {
                    sheep_ptr.target_item_idx = null;
                    sheep_ptr.current_action = .SeekingFood;
                }
            } else {
                sheep_ptr.current_action = .SeekingFood;
            }
        },
        .Hunting => {
            sheep_ptr.must_complete_wander_step = false;
            if (sheep_ptr.target_entity_idx) |target_idx| {
                if (target_idx < world_ptr.entities.items.len) {
                    const target_brush = world_ptr.entities.items[target_idx];
                    if (target_brush.entity_type == .Brush and target_brush.current_hp > 0) {
                        if (animal_ai_utils.absInt(sheep_ptr.x - target_brush.x) <= 1 and animal_ai_utils.absInt(sheep_ptr.y - target_brush.y) <= 1 and
                            (animal_ai_utils.absInt(sheep_ptr.x - target_brush.x) + animal_ai_utils.absInt(sheep_ptr.y - target_brush.y) <= 1 or (animal_ai_utils.absInt(sheep_ptr.x - target_brush.x) == 1 and animal_ai_utils.absInt(sheep_ptr.y - target_brush.y) == 1)))
                        {
                            log.debug("Sheep at {d},{d} reached Brush at {d},{d}. Transitioning to Attacking.", .{ sheep_ptr.x, sheep_ptr.y, target_brush.x, target_brush.y });
                            sheep_ptr.current_action = .Attacking;
                            sheep_ptr.attack_cooldown = 0;
                        } else {
                            sheep_ptr.wander_target_x = target_brush.x;
                            sheep_ptr.wander_target_y = target_brush.y;
                            animal_ai_utils.attemptMoveTowardsWanderTarget(sheep_ptr, world_ptr, prng);
                        }
                    } else {
                        sheep_ptr.target_entity_idx = null;
                        if (is_hungry) {
                            sheep_ptr.current_action = .SeekingFood;
                        } else {
                            sheep_ptr.current_action = .Idle;
                        }
                    }
                } else {
                    sheep_ptr.target_entity_idx = null;
                    if (is_hungry) {
                        sheep_ptr.current_action = .SeekingFood;
                    } else {
                        sheep_ptr.current_action = .Idle;
                    }
                }
            } else {
                if (is_hungry) {
                    sheep_ptr.current_action = .SeekingFood;
                } else {
                    sheep_ptr.current_action = .Idle;
                }
            }
        },
        .Attacking => {
            sheep_ptr.must_complete_wander_step = false;
            if (sheep_ptr.attack_cooldown == 0) {
                if (sheep_ptr.target_entity_idx) |target_idx| {
                    if (target_idx < world_ptr.entities.items.len) {
                        const target_brush_ptr = &world_ptr.entities.items[target_idx];
                        if (target_brush_ptr.entity_type == .Brush and target_brush_ptr.current_hp > 0) {
                            if (animal_ai_utils.absInt(sheep_ptr.x - target_brush_ptr.x) <= 1 and animal_ai_utils.absInt(sheep_ptr.y - target_brush_ptr.y) <= 1 and
                                (animal_ai_utils.absInt(sheep_ptr.x - target_brush_ptr.x) + animal_ai_utils.absInt(sheep_ptr.y - target_brush_ptr.y) <= 1 or (animal_ai_utils.absInt(sheep_ptr.x - target_brush_ptr.x) == 1 and animal_ai_utils.absInt(sheep_ptr.y - target_brush_ptr.y) == 1)))
                            {
                                combat.resolveAttack(sheep_ptr, target_brush_ptr, world_ptr, prng);
                                if (target_brush_ptr.current_hp == 0) {
                                    sheep_ptr.target_entity_idx = null;
                                    sheep_ptr.current_action = .SeekingFood;
                                } else {
                                    sheep_ptr.attack_cooldown = config.harvest_brush_cooldown_ticks;
                                }
                            } else {
                                sheep_ptr.current_action = .Hunting;
                            }
                        } else {
                            sheep_ptr.target_entity_idx = null;
                            if (is_hungry) {
                                sheep_ptr.current_action = .SeekingFood;
                            } else {
                                sheep_ptr.current_action = .Idle;
                            }
                        }
                    } else {
                        sheep_ptr.target_entity_idx = null;
                        if (is_hungry) {
                            sheep_ptr.current_action = .SeekingFood;
                        } else {
                            sheep_ptr.current_action = .Idle;
                        }
                    }
                } else {
                    if (is_hungry) {
                        sheep_ptr.current_action = .SeekingFood;
                    } else {
                        sheep_ptr.current_action = .Idle;
                    }
                }
            }
        },
        .Eating => {
            if (sheep_ptr.current_action_timer == 0) {
                sheep_ptr.current_action = .Idle;
                sheep_ptr.must_complete_wander_step = false;
            }
        },
        .Fleeing => {
            animal_ai_utils.chooseNewWanderTarget(sheep_ptr, prng, world_ptr.width, world_ptr.height);
            sheep_ptr.current_action = .Wandering;
            sheep_ptr.must_complete_wander_step = false;
        },
    }
}
