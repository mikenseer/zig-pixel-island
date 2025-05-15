// src/sheep_ai.zig
// Handles AI logic for Sheep entities.
const std_full = @import("std");
const types = @import("types.zig");
const config = @import("config.zig");
const art = @import("art.zig");
const items_module = @import("items.zig");
const inventory = @import("inventory.zig");
const combat = @import("combat.zig");
const animal_ai_utils = @import("animal_ai.zig");
const entity_processing = @import("entity_processing.zig");

const log = std_full.log;
const math = std_full.math;
const RandomInterface = std_full.Random;

// Updates the AI state for a Sheep entity
pub fn updateSheep(sheep_ptr: *types.Entity, world_ptr: *types.GameWorld, prng: *RandomInterface) void {
    if (sheep_ptr.entity_type != .Sheep) {
        return;
    }

    entity_processing.processHpDecay(sheep_ptr);

    if (sheep_ptr.current_hp == 0) {
        return;
    }

    if (sheep_ptr.blocked_target_cooldown > 0) {
        sheep_ptr.blocked_target_cooldown -= 1;
        if (sheep_ptr.blocked_target_cooldown == 0) {
            log.debug("Sheep {d},{d} blocked target cooldown expired for target {?d} (is_item: {any})", .{ sheep_ptr.x, sheep_ptr.y, sheep_ptr.blocked_target_idx, sheep_ptr.blocked_target_is_item });
            sheep_ptr.blocked_target_idx = null;
        }
    }
    if (sheep_ptr.post_action_cooldown > 0) {
        sheep_ptr.post_action_cooldown -= 1;
    }

    const graze_opportunistic_hp_val = @as(i16, @intFromFloat(@as(f32, @floatFromInt(sheep_ptr.max_hp)) * config.sheep_hp_graze_opportunistic_threshold_percent));
    const seek_food_actively_hp_val = @as(i16, @intFromFloat(@as(f32, @floatFromInt(sheep_ptr.max_hp)) * config.sheep_hp_seek_food_actively_threshold_percent));

    const is_opportunistically_grazing = sheep_ptr.current_hp <= graze_opportunistic_hp_val;
    const is_actively_seeking_food = sheep_ptr.current_hp < seek_food_actively_hp_val;

    if (sheep_ptr.current_action == .Eating) {
        if (sheep_ptr.current_action_timer > 0) {
            sheep_ptr.current_action_timer -= 1;
            if (sheep_ptr.current_action_timer == 0) {
                if (sheep_ptr.inventory[0].item_type == .Grain and sheep_ptr.inventory[0].quantity > 0) {
                    _ = inventory.removeFromInventory(sheep_ptr, 0, 1);
                    sheep_ptr.current_hp = @min(sheep_ptr.max_hp, sheep_ptr.current_hp + config.grain_hp_gain_sheep);
                }
                sheep_ptr.current_action = .Idle;
                sheep_ptr.must_complete_wander_step = false;
                sheep_ptr.post_action_cooldown = config.general_post_action_cooldown; // Cooldown after eating
            }
        }
        return;
    }

    if (sheep_ptr.attack_cooldown > 0) {
        sheep_ptr.attack_cooldown -= 1;
    }

    // If Idle and actively hungry (and not on post-action cooldown), start seeking food.
    if (is_actively_seeking_food and sheep_ptr.current_action == .Idle and sheep_ptr.post_action_cooldown == 0) {
        log.debug("Sheep {d},{d} is Idle and ACTIVELY hungry (HP: {d}/{d}). -> SeekingFood.", .{ sheep_ptr.x, sheep_ptr.y, sheep_ptr.current_hp, sheep_ptr.max_hp });
        sheep_ptr.current_action = .SeekingFood;
        sheep_ptr.target_entity_idx = null;
        sheep_ptr.target_item_idx = null;
        sheep_ptr.must_complete_wander_step = false;
        sheep_ptr.pathing_attempts_to_current_target = 0;
    }

    switch (sheep_ptr.current_action) {
        .Idle => {
            if (sheep_ptr.post_action_cooldown > 0) {
                return;
            } // Wait out post-action cooldown

            // If actively hungry, the check above should have transitioned it.
            // If opportunistically hungry (but not actively so), look for nearby food.
            if (is_opportunistically_grazing and !is_actively_seeking_food) {
                var found_opportunistic_food = false;

                // Try to resume previous target if valid & not on blocked cooldown
                if (sheep_ptr.target_item_idx) |target_item_idx_val| {
                    if (!(sheep_ptr.blocked_target_idx != null and sheep_ptr.blocked_target_idx.? == target_item_idx_val and sheep_ptr.blocked_target_is_item and sheep_ptr.blocked_target_cooldown > 0)) {
                        if (target_item_idx_val < world_ptr.items.items.len) {
                            const remembered_item = world_ptr.items.items[target_item_idx_val];
                            if (remembered_item.item_type == .Grain) {
                                sheep_ptr.wander_target_x = remembered_item.x;
                                sheep_ptr.wander_target_y = remembered_item.y;
                                sheep_ptr.current_action = .PickingUpItem;
                                found_opportunistic_food = true;
                            } else {
                                sheep_ptr.target_item_idx = null;
                            }
                        } else {
                            sheep_ptr.target_item_idx = null;
                        }
                    } else {
                        sheep_ptr.target_item_idx = null;
                    } // It's blocked, forget it
                } else if (sheep_ptr.target_entity_idx) |target_brush_idx| {
                    if (!(sheep_ptr.blocked_target_idx != null and sheep_ptr.blocked_target_idx.? == target_brush_idx and !sheep_ptr.blocked_target_is_item and sheep_ptr.blocked_target_cooldown > 0)) {
                        if (target_brush_idx < world_ptr.entities.items.len) {
                            const remembered_brush = world_ptr.entities.items[target_brush_idx];
                            if (remembered_brush.entity_type == .Brush and remembered_brush.current_hp > 0) {
                                sheep_ptr.wander_target_x = remembered_brush.x;
                                sheep_ptr.wander_target_y = remembered_brush.y;
                                sheep_ptr.current_action = .Hunting;
                                found_opportunistic_food = true;
                            } else {
                                sheep_ptr.target_entity_idx = null;
                            }
                        } else {
                            sheep_ptr.target_entity_idx = null;
                        }
                    } else {
                        sheep_ptr.target_entity_idx = null;
                    } // It's blocked, forget it
                }

                // If no remembered target, scan for new opportunistic targets
                if (!found_opportunistic_food) {
                    var closest_grain_idx: ?usize = null;
                    var min_dist_sq_grain: i64 = -1;
                    for (world_ptr.items.items, 0..) |*item_on_ground, idx| {
                        if (sheep_ptr.blocked_target_idx != null and sheep_ptr.blocked_target_idx.? == idx and sheep_ptr.blocked_target_is_item and sheep_ptr.blocked_target_cooldown > 0) {
                            continue;
                        }
                        if (item_on_ground.item_type == .Grain) {
                            const d_sq = animal_ai_utils.distSq(sheep_ptr.x, sheep_ptr.y, item_on_ground.x, item_on_ground.y);
                            if (d_sq <= config.sheep_brush_opportunistic_sight_radius * config.sheep_brush_opportunistic_sight_radius) {
                                if (closest_grain_idx == null or d_sq < min_dist_sq_grain) {
                                    min_dist_sq_grain = d_sq;
                                    closest_grain_idx = idx;
                                }
                            }
                        }
                    }
                    if (closest_grain_idx) |target_idx| {
                        sheep_ptr.target_item_idx = target_idx;
                        sheep_ptr.target_entity_idx = null;
                        sheep_ptr.wander_target_x = world_ptr.items.items[target_idx].x;
                        sheep_ptr.wander_target_y = world_ptr.items.items[target_idx].y;
                        sheep_ptr.current_action = .PickingUpItem;
                        found_opportunistic_food = true;
                        sheep_ptr.pathing_attempts_to_current_target = 0;
                    }
                }
                if (!found_opportunistic_food) {
                    var closest_brush_idx: ?usize = null;
                    var min_dist_sq_brush: i64 = -1;
                    for (world_ptr.entities.items, 0..) |*other_entity, e_idx| {
                        if (sheep_ptr.blocked_target_idx != null and sheep_ptr.blocked_target_idx.? == e_idx and !sheep_ptr.blocked_target_is_item and sheep_ptr.blocked_target_cooldown > 0) {
                            continue;
                        }
                        if (other_entity.entity_type == .Brush and other_entity.current_hp > 0) {
                            const d_sq = animal_ai_utils.distSq(sheep_ptr.x, sheep_ptr.y, other_entity.x, other_entity.y);
                            if (d_sq <= config.sheep_brush_opportunistic_sight_radius * config.sheep_brush_opportunistic_sight_radius) {
                                if (closest_brush_idx == null or d_sq < min_dist_sq_brush) {
                                    min_dist_sq_brush = d_sq;
                                    closest_brush_idx = e_idx;
                                }
                            }
                        }
                    }
                    if (closest_brush_idx) |target_idx| {
                        sheep_ptr.target_entity_idx = target_idx;
                        sheep_ptr.target_item_idx = null;
                        sheep_ptr.wander_target_x = world_ptr.entities.items[target_idx].x;
                        sheep_ptr.wander_target_y = world_ptr.entities.items[target_idx].y;
                        sheep_ptr.current_action = .Hunting;
                        found_opportunistic_food = true;
                        sheep_ptr.pathing_attempts_to_current_target = 0;
                    }
                }

                if (!found_opportunistic_food and prng.float(f32) < config.sheep_move_attempt_chance) {
                    animal_ai_utils.chooseNewWanderTarget(sheep_ptr, prng, world_ptr.width, world_ptr.height, false);
                    sheep_ptr.current_action = .Wandering;
                    sheep_ptr.must_complete_wander_step = false;
                }
            } else if (!is_opportunistically_grazing) {
                if (prng.float(f32) < config.sheep_move_attempt_chance) {
                    animal_ai_utils.chooseNewWanderTarget(sheep_ptr, prng, world_ptr.width, world_ptr.height, false);
                    sheep_ptr.current_action = .Wandering;
                    sheep_ptr.must_complete_wander_step = false;
                }
            }
        },
        .Wandering => {
            if (sheep_ptr.must_complete_wander_step) {
                animal_ai_utils.attemptMoveTowardsWanderTarget(sheep_ptr, world_ptr, prng);
            } else if (is_actively_seeking_food) {
                sheep_ptr.current_action = .SeekingFood;
                sheep_ptr.target_entity_idx = null;
                sheep_ptr.target_item_idx = null;
                sheep_ptr.pathing_attempts_to_current_target = 0;
            } else if (is_opportunistically_grazing and sheep_ptr.post_action_cooldown == 0) {
                var found_opportunistic_food = false;
                var closest_grain_idx: ?usize = null;
                var min_dist_sq_grain: i64 = -1;
                for (world_ptr.items.items, 0..) |*item_on_ground, idx| {
                    if (sheep_ptr.blocked_target_idx != null and sheep_ptr.blocked_target_idx.? == idx and sheep_ptr.blocked_target_is_item and sheep_ptr.blocked_target_cooldown > 0) {
                        continue;
                    }
                    if (item_on_ground.item_type == .Grain) {
                        const d_sq = animal_ai_utils.distSq(sheep_ptr.x, sheep_ptr.y, item_on_ground.x, item_on_ground.y);
                        if (d_sq <= config.sheep_brush_opportunistic_sight_radius * config.sheep_brush_opportunistic_sight_radius) {
                            if (closest_grain_idx == null or d_sq < min_dist_sq_grain) {
                                min_dist_sq_grain = d_sq;
                                closest_grain_idx = idx;
                            }
                        }
                    }
                }
                if (closest_grain_idx) |target_idx| {
                    sheep_ptr.target_item_idx = target_idx;
                    sheep_ptr.target_entity_idx = null;
                    sheep_ptr.wander_target_x = world_ptr.items.items[target_idx].x;
                    sheep_ptr.wander_target_y = world_ptr.items.items[target_idx].y;
                    sheep_ptr.current_action = .PickingUpItem;
                    found_opportunistic_food = true;
                    sheep_ptr.pathing_attempts_to_current_target = 0;
                }
                if (!found_opportunistic_food) {
                    var closest_brush_idx: ?usize = null;
                    var min_dist_sq_brush: i64 = -1;
                    for (world_ptr.entities.items, 0..) |*other_entity, e_idx| {
                        if (sheep_ptr.blocked_target_idx != null and sheep_ptr.blocked_target_idx.? == e_idx and !sheep_ptr.blocked_target_is_item and sheep_ptr.blocked_target_cooldown > 0) {
                            continue;
                        }
                        if (other_entity.entity_type == .Brush and other_entity.current_hp > 0) {
                            const d_sq = animal_ai_utils.distSq(sheep_ptr.x, sheep_ptr.y, other_entity.x, other_entity.y);
                            if (d_sq <= config.sheep_brush_opportunistic_sight_radius * config.sheep_brush_opportunistic_sight_radius) {
                                if (closest_brush_idx == null or d_sq < min_dist_sq_brush) {
                                    min_dist_sq_brush = d_sq;
                                    closest_brush_idx = e_idx;
                                }
                            }
                        }
                    }
                    if (closest_brush_idx) |target_idx| {
                        sheep_ptr.target_entity_idx = target_idx;
                        sheep_ptr.target_item_idx = null;
                        sheep_ptr.wander_target_x = world_ptr.entities.items[target_idx].x;
                        sheep_ptr.wander_target_y = world_ptr.entities.items[target_idx].y;
                        sheep_ptr.current_action = .Hunting;
                        found_opportunistic_food = true;
                        sheep_ptr.pathing_attempts_to_current_target = 0;
                    }
                }

                if (found_opportunistic_food) {
                    animal_ai_utils.attemptMoveTowardsWanderTarget(sheep_ptr, world_ptr, prng);
                } else {
                    animal_ai_utils.attemptMoveTowardsWanderTarget(sheep_ptr, world_ptr, prng);
                }
            } else {
                animal_ai_utils.attemptMoveTowardsWanderTarget(sheep_ptr, world_ptr, prng);
            }
        },
        .SeekingFood => {
            var found_food_target_this_tick = false;
            sheep_ptr.must_complete_wander_step = false;

            if (is_actively_seeking_food and inventory.countInInventory(sheep_ptr, .Grain) > 0) {
                sheep_ptr.current_action = .Eating;
                sheep_ptr.current_action_timer = config.eating_duration_ticks;
                found_food_target_this_tick = true;
            }

            if (!found_food_target_this_tick and is_actively_seeking_food and sheep_ptr.target_item_idx == null) {
                var closest_grain_idx: ?usize = null;
                var min_dist_sq_grain: i64 = -1;
                for (world_ptr.items.items, 0..) |*item_on_ground, idx| {
                    if (sheep_ptr.blocked_target_idx != null and sheep_ptr.blocked_target_idx.? == idx and sheep_ptr.blocked_target_is_item and sheep_ptr.blocked_target_cooldown > 0) {
                        continue;
                    }
                    if (item_on_ground.item_type == .Grain) {
                        const d_sq = animal_ai_utils.distSq(sheep_ptr.x, sheep_ptr.y, item_on_ground.x, item_on_ground.y);
                        if (d_sq <= config.sheep_hungry_food_sight_radius * config.sheep_hungry_food_sight_radius) {
                            if (closest_grain_idx == null or d_sq < min_dist_sq_grain) {
                                min_dist_sq_grain = d_sq;
                                closest_grain_idx = idx;
                            }
                        }
                    }
                }
                if (closest_grain_idx) |idx| {
                    sheep_ptr.target_item_idx = idx;
                    sheep_ptr.target_entity_idx = null;
                    sheep_ptr.wander_target_x = world_ptr.items.items[idx].x;
                    sheep_ptr.wander_target_y = world_ptr.items.items[idx].y;
                    sheep_ptr.current_action = .PickingUpItem;
                    found_food_target_this_tick = true;
                    sheep_ptr.pathing_attempts_to_current_target = 0;
                }
            }

            if (!found_food_target_this_tick and is_actively_seeking_food and sheep_ptr.target_entity_idx == null) {
                var closest_brush_idx: ?usize = null;
                var min_dist_sq_brush: i64 = -1;
                for (world_ptr.entities.items, 0..) |*other_entity, idx| {
                    if (sheep_ptr.blocked_target_idx != null and sheep_ptr.blocked_target_idx.? == idx and !sheep_ptr.blocked_target_is_item and sheep_ptr.blocked_target_cooldown > 0) {
                        continue;
                    }
                    if (other_entity.entity_type == .Brush and other_entity.current_hp > 0) {
                        const d_sq = animal_ai_utils.distSq(sheep_ptr.x, sheep_ptr.y, other_entity.x, other_entity.y);
                        if (d_sq <= config.sheep_hungry_food_sight_radius * config.sheep_hungry_food_sight_radius) {
                            if (closest_brush_idx == null or d_sq < min_dist_sq_brush) {
                                min_dist_sq_brush = d_sq;
                                closest_brush_idx = idx;
                            }
                        }
                    }
                }
                if (closest_brush_idx) |idx| {
                    sheep_ptr.target_entity_idx = idx;
                    sheep_ptr.target_item_idx = null;
                    sheep_ptr.wander_target_x = world_ptr.entities.items[idx].x;
                    sheep_ptr.wander_target_y = world_ptr.entities.items[idx].y;
                    sheep_ptr.current_action = .Hunting;
                    found_food_target_this_tick = true;
                    sheep_ptr.pathing_attempts_to_current_target = 0;
                }
            }

            if (found_food_target_this_tick) {
                if (sheep_ptr.current_action == .PickingUpItem or sheep_ptr.current_action == .Hunting) {
                    animal_ai_utils.attemptMoveTowardsWanderTarget(sheep_ptr, world_ptr, prng);
                }
            } else {
                log.debug("Sheep {d},{d} no food targets in SeekingFood (actively hungry). -> Wandering (forced escape).", .{ sheep_ptr.x, sheep_ptr.y });
                animal_ai_utils.chooseNewWanderTarget(sheep_ptr, prng, world_ptr.width, world_ptr.height, true);
                sheep_ptr.current_action = .Wandering;
                sheep_ptr.must_complete_wander_step = true;
                sheep_ptr.pathing_attempts_to_current_target = 0;
            }
        },
        .PickingUpItem => {
            sheep_ptr.must_complete_wander_step = false;
            if (sheep_ptr.target_item_idx) |target_idx| {
                if (target_idx < world_ptr.items.items.len) {
                    const target_item = world_ptr.items.items[target_idx];
                    if (target_item.item_type == .Grain) {
                        const dx_item = animal_ai_utils.absInt(sheep_ptr.x - target_item.x);
                        const dy_item = animal_ai_utils.absInt(sheep_ptr.y - target_item.y);
                        if (dx_item <= 1 and dy_item <= 1) {
                            if (inventory.addToInventory(sheep_ptr, .Grain, 1)) {
                                _ = world_ptr.items.orderedRemove(target_idx);
                                sheep_ptr.target_item_idx = null;
                                sheep_ptr.pathing_attempts_to_current_target = 0;
                                // Eat if actively seeking food OR opportunistically grazing (HP <= 80%)
                                if (is_actively_seeking_food or is_opportunistically_grazing) {
                                    sheep_ptr.current_action = .Eating;
                                    sheep_ptr.current_action_timer = config.eating_duration_ticks;
                                } else {
                                    sheep_ptr.current_action = .Idle;
                                }
                            } else {
                                sheep_ptr.target_item_idx = null;
                                sheep_ptr.current_action = .Idle;
                                sheep_ptr.pathing_attempts_to_current_target = 0;
                            }
                        } else {
                            sheep_ptr.wander_target_x = target_item.x;
                            sheep_ptr.wander_target_y = target_item.y;
                            animal_ai_utils.attemptMoveTowardsWanderTarget(sheep_ptr, world_ptr, prng);
                        }
                    } else {
                        sheep_ptr.target_item_idx = null;
                        sheep_ptr.current_action = .SeekingFood;
                        sheep_ptr.pathing_attempts_to_current_target = 0;
                    }
                } else {
                    sheep_ptr.target_item_idx = null;
                    sheep_ptr.current_action = .SeekingFood;
                    sheep_ptr.pathing_attempts_to_current_target = 0;
                }
            } else {
                sheep_ptr.current_action = .SeekingFood;
                sheep_ptr.pathing_attempts_to_current_target = 0;
            }
        },
        .Hunting => {
            sheep_ptr.must_complete_wander_step = false;
            if (sheep_ptr.target_entity_idx) |target_idx| {
                if (target_idx < world_ptr.entities.items.len) {
                    const target_brush = world_ptr.entities.items[target_idx];
                    if (target_brush.entity_type == .Brush and target_brush.current_hp > 0) {
                        const dx_brush = animal_ai_utils.absInt(sheep_ptr.x - target_brush.x);
                        const dy_brush = animal_ai_utils.absInt(sheep_ptr.y - target_brush.y);
                        if (dx_brush <= 1 and dy_brush <= 1) {
                            sheep_ptr.current_action = .Attacking;
                            sheep_ptr.attack_cooldown = 0;
                            sheep_ptr.pathing_attempts_to_current_target = 0;
                        } else {
                            sheep_ptr.wander_target_x = target_brush.x;
                            sheep_ptr.wander_target_y = target_brush.y;
                            animal_ai_utils.attemptMoveTowardsWanderTarget(sheep_ptr, world_ptr, prng);
                        }
                    } else {
                        sheep_ptr.target_entity_idx = null;
                        sheep_ptr.pathing_attempts_to_current_target = 0;
                        if (is_actively_seeking_food) {
                            sheep_ptr.current_action = .SeekingFood;
                        } else {
                            sheep_ptr.current_action = .Idle;
                        }
                    }
                } else {
                    sheep_ptr.target_entity_idx = null;
                    sheep_ptr.pathing_attempts_to_current_target = 0;
                    if (is_actively_seeking_food) {
                        sheep_ptr.current_action = .SeekingFood;
                    } else {
                        sheep_ptr.current_action = .Idle;
                    }
                }
            } else {
                sheep_ptr.pathing_attempts_to_current_target = 0;
                if (is_actively_seeking_food) {
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
                            const dx_brush_attack = animal_ai_utils.absInt(sheep_ptr.x - target_brush_ptr.x);
                            const dy_brush_attack = animal_ai_utils.absInt(sheep_ptr.y - target_brush_ptr.y);
                            if (dx_brush_attack <= 1 and dy_brush_attack <= 1) {
                                combat.resolveAttack(sheep_ptr, target_brush_ptr, world_ptr, prng);
                                sheep_ptr.pathing_attempts_to_current_target = 0;
                                if (target_brush_ptr.current_hp == 0) {
                                    log.info("Sheep at {d},{d} destroyed Brush {d}. -> SeekingFood.", .{ sheep_ptr.x, sheep_ptr.y, target_idx });
                                    sheep_ptr.target_entity_idx = null;
                                    sheep_ptr.current_action = .SeekingFood;
                                } else {
                                    sheep_ptr.attack_cooldown = config.harvest_brush_cooldown_ticks;
                                }
                            } else {
                                log.debug("Sheep at {d},{d} in Attacking, but no longer adjacent to Brush {d}. -> Hunting.", .{ sheep_ptr.x, sheep_ptr.y, target_idx });
                                sheep_ptr.current_action = .Hunting;
                                sheep_ptr.pathing_attempts_to_current_target = 0;
                            }
                        } else {
                            log.debug("Sheep at {d},{d} in Attacking, target Brush {d} invalid/dead. -> Re-evaluate.", .{ sheep_ptr.x, sheep_ptr.y, target_idx });
                            sheep_ptr.target_entity_idx = null;
                            sheep_ptr.pathing_attempts_to_current_target = 0;
                            if (is_actively_seeking_food) {
                                sheep_ptr.current_action = .SeekingFood;
                            } else {
                                sheep_ptr.current_action = .Idle;
                            }
                        }
                    } else {
                        log.warn("Sheep at {d},{d} in Attacking, target_idx {d} out of bounds. -> Re-evaluate.", .{ sheep_ptr.x, sheep_ptr.y, target_idx });
                        sheep_ptr.target_entity_idx = null;
                        sheep_ptr.pathing_attempts_to_current_target = 0;
                        if (is_actively_seeking_food) {
                            sheep_ptr.current_action = .SeekingFood;
                        } else {
                            sheep_ptr.current_action = .Idle;
                        }
                    }
                } else {
                    log.warn("Sheep at {d},{d} in Attacking with no target. -> Re-evaluate.", .{ sheep_ptr.x, sheep_ptr.y });
                    sheep_ptr.pathing_attempts_to_current_target = 0;
                    if (is_actively_seeking_food) {
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
            animal_ai_utils.chooseNewWanderTarget(sheep_ptr, prng, world_ptr.width, world_ptr.height, false);
            sheep_ptr.current_action = .Wandering;
            sheep_ptr.must_complete_wander_step = false;
        },
    }
}
