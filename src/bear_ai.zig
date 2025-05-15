// src/bear_ai.zig
// Handles AI logic for Bear entities.
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

// Updates the AI state for a Bear entity
pub fn updateBear(bear_ptr: *types.Entity, world_ptr: *types.GameWorld, prng: *RandomInterface) void {
    if (bear_ptr.entity_type != .Bear) {
        return;
    }

    entity_processing.processHpDecay(bear_ptr);

    if (bear_ptr.current_hp == 0) {
        return;
    }

    if (bear_ptr.blocked_target_cooldown > 0) {
        bear_ptr.blocked_target_cooldown -= 1;
        if (bear_ptr.blocked_target_cooldown == 0) {
            log.debug("Bear {d},{d} blocked target cooldown expired for target {?d} (is_item: {any})", .{ bear_ptr.x, bear_ptr.y, bear_ptr.blocked_target_idx, bear_ptr.blocked_target_is_item });
            bear_ptr.blocked_target_idx = null;
        }
    }
    if (bear_ptr.post_action_cooldown > 0) {
        bear_ptr.post_action_cooldown -= 1;
    }

    const eat_opportunistic_hp_threshold = @as(i16, @intFromFloat(@as(f32, @floatFromInt(bear_ptr.max_hp)) * config.bear_hp_eat_opportunistic_threshold_percent));
    const seek_meat_actively_hp_threshold = @as(i16, @intFromFloat(@as(f32, @floatFromInt(bear_ptr.max_hp)) * config.bear_hp_seek_meat_actively_threshold_percent));
    const hunt_sheep_hp_threshold = @as(i16, @intFromFloat(@as(f32, @floatFromInt(bear_ptr.max_hp)) * config.bear_hp_hunt_sheep_threshold_percent));
    const hunt_peon_hp_threshold = @as(i16, @intFromFloat(@as(f32, @floatFromInt(bear_ptr.max_hp)) * config.bear_hp_hunt_peon_threshold_percent));

    const is_opportunistically_hungry = bear_ptr.current_hp <= eat_opportunistic_hp_threshold;
    const is_actively_seeking_meat = bear_ptr.current_hp < seek_meat_actively_hp_threshold;
    const is_hunting_sheep_hungry = bear_ptr.current_hp < hunt_sheep_hp_threshold;
    const is_hunting_peon_hungry = bear_ptr.current_hp < hunt_peon_hp_threshold;

    const is_very_hungry_for_anything = is_actively_seeking_meat or is_hunting_sheep_hungry or is_hunting_peon_hungry;

    if (bear_ptr.current_action == .Eating) {
        if (bear_ptr.current_action_timer > 0) {
            bear_ptr.current_action_timer -= 1;
            if (bear_ptr.current_action_timer == 0) {
                log.debug("Bear at {d},{d} finished eating. HP: {d}/{d}", .{ bear_ptr.x, bear_ptr.y, bear_ptr.current_hp, bear_ptr.max_hp });
                bear_ptr.current_action = .Idle;
                bear_ptr.must_complete_wander_step = false;
                bear_ptr.post_action_cooldown = config.general_post_action_cooldown;
            }
        }
        return;
    }

    if (bear_ptr.attack_cooldown > 0) {
        bear_ptr.attack_cooldown -= 1;
    }

    if (is_very_hungry_for_anything and bear_ptr.current_action == .Idle and bear_ptr.post_action_cooldown == 0) {
        log.debug("Bear {d},{d} is Idle and very hungry (HP: {d}/{d}). -> SeekingFood.", .{ bear_ptr.x, bear_ptr.y, bear_ptr.current_hp, bear_ptr.max_hp });
        bear_ptr.current_action = .SeekingFood;
        bear_ptr.target_entity_idx = null;
        bear_ptr.target_item_idx = null;
        bear_ptr.must_complete_wander_step = false;
        bear_ptr.pathing_attempts_to_current_target = 0;
    }

    switch (bear_ptr.current_action) {
        .Idle => {
            if (bear_ptr.post_action_cooldown > 0) {
                return;
            }

            if (!is_very_hungry_for_anything) {
                var found_opportunistic_food = false;
                // Resume previous opportunistic hunt/pickup if valid and not on blocked cooldown
                if (bear_ptr.target_entity_idx) |target_prey_idx| {
                    if (!(bear_ptr.blocked_target_idx != null and bear_ptr.blocked_target_idx.? == target_prey_idx and !bear_ptr.blocked_target_is_item and bear_ptr.blocked_target_cooldown > 0)) {
                        if (target_prey_idx < world_ptr.entities.items.len) {
                            const remembered_prey = world_ptr.entities.items[target_prey_idx];
                            if ((remembered_prey.entity_type == .Sheep or remembered_prey.entity_type == .Player) and remembered_prey.current_hp > 0) {
                                log.debug("Bear {d},{d} Idle, resuming hunt for remembered prey {d}.", .{ bear_ptr.x, bear_ptr.y, target_prey_idx });
                                bear_ptr.wander_target_x = remembered_prey.x;
                                bear_ptr.wander_target_y = remembered_prey.y;
                                bear_ptr.current_action = .Hunting;
                                found_opportunistic_food = true; // Technically not food, but a target
                            } else {
                                bear_ptr.target_entity_idx = null;
                            }
                        } else {
                            bear_ptr.target_entity_idx = null;
                        }
                    } else {
                        bear_ptr.target_entity_idx = null;
                    }
                } else if (bear_ptr.target_item_idx) |target_meat_idx| {
                    if (!(bear_ptr.blocked_target_idx != null and bear_ptr.blocked_target_idx.? == target_meat_idx and bear_ptr.blocked_target_is_item and bear_ptr.blocked_target_cooldown > 0)) {
                        if (target_meat_idx < world_ptr.items.items.len) {
                            const remembered_item = world_ptr.items.items[target_meat_idx];
                            if (remembered_item.item_type == .Meat) {
                                bear_ptr.wander_target_x = remembered_item.x;
                                bear_ptr.wander_target_y = remembered_item.y;
                                bear_ptr.current_action = .PickingUpItem;
                                found_opportunistic_food = true;
                            } else {
                                bear_ptr.target_item_idx = null;
                            }
                        } else {
                            bear_ptr.target_item_idx = null;
                        }
                    } else {
                        bear_ptr.target_item_idx = null;
                    }
                }

                if (!found_opportunistic_food and is_opportunistically_hungry) {
                    var closest_meat_idx: ?usize = null;
                    var min_dist_sq_meat: i64 = -1;
                    for (world_ptr.items.items, 0..) |*item, idx| {
                        if (bear_ptr.blocked_target_idx != null and bear_ptr.blocked_target_idx.? == idx and bear_ptr.blocked_target_is_item and bear_ptr.blocked_target_cooldown > 0) {
                            continue;
                        }
                        if (item.item_type == .Meat) {
                            const d_sq = animal_ai_utils.distSq(bear_ptr.x, bear_ptr.y, item.x, item.y);
                            if (d_sq <= config.bear_meat_opportunistic_sight_radius * config.bear_meat_opportunistic_sight_radius) {
                                if (closest_meat_idx == null or d_sq < min_dist_sq_meat) {
                                    min_dist_sq_meat = d_sq;
                                    closest_meat_idx = idx;
                                }
                            }
                        }
                    }
                    if (closest_meat_idx) |target_idx| {
                        bear_ptr.target_item_idx = target_idx;
                        bear_ptr.target_entity_idx = null;
                        bear_ptr.wander_target_x = world_ptr.items.items[target_idx].x;
                        bear_ptr.wander_target_y = world_ptr.items.items[target_idx].y;
                        bear_ptr.current_action = .PickingUpItem;
                        bear_ptr.pathing_attempts_to_current_target = 0;
                        found_opportunistic_food = true;
                    }
                }
                if (!found_opportunistic_food and prng.float(f32) < config.bear_move_attempt_chance) {
                    animal_ai_utils.chooseNewWanderTarget(bear_ptr, prng, world_ptr.width, world_ptr.height, false);
                    bear_ptr.current_action = .Wandering;
                    bear_ptr.must_complete_wander_step = false;
                }
            }
        },
        .Wandering => {
            if (bear_ptr.must_complete_wander_step) {
                animal_ai_utils.attemptMoveTowardsWanderTarget(bear_ptr, world_ptr, prng);
            } else if (is_very_hungry_for_anything) {
                bear_ptr.current_action = .SeekingFood;
                bear_ptr.target_entity_idx = null;
                bear_ptr.target_item_idx = null;
                bear_ptr.pathing_attempts_to_current_target = 0;
            } else if (is_opportunistically_hungry and bear_ptr.post_action_cooldown == 0) {
                var found_opportunistic_food = false;
                var closest_meat_idx: ?usize = null;
                var min_dist_sq_meat: i64 = -1;
                for (world_ptr.items.items, 0..) |*item, idx| {
                    if (bear_ptr.blocked_target_idx != null and bear_ptr.blocked_target_idx.? == idx and bear_ptr.blocked_target_is_item and bear_ptr.blocked_target_cooldown > 0) {
                        continue;
                    }
                    if (item.item_type == .Meat) {
                        const d_sq = animal_ai_utils.distSq(bear_ptr.x, bear_ptr.y, item.x, item.y);
                        if (d_sq <= config.bear_meat_opportunistic_sight_radius * config.bear_meat_opportunistic_sight_radius) {
                            if (closest_meat_idx == null or d_sq < min_dist_sq_meat) {
                                min_dist_sq_meat = d_sq;
                                closest_meat_idx = idx;
                            }
                        }
                    }
                }
                if (closest_meat_idx) |target_idx| {
                    bear_ptr.target_item_idx = target_idx;
                    bear_ptr.target_entity_idx = null;
                    bear_ptr.wander_target_x = world_ptr.items.items[target_idx].x;
                    bear_ptr.wander_target_y = world_ptr.items.items[target_idx].y;
                    bear_ptr.current_action = .PickingUpItem;
                    bear_ptr.pathing_attempts_to_current_target = 0;
                    found_opportunistic_food = true;
                }

                if (found_opportunistic_food) {
                    animal_ai_utils.attemptMoveTowardsWanderTarget(bear_ptr, world_ptr, prng);
                } else {
                    animal_ai_utils.attemptMoveTowardsWanderTarget(bear_ptr, world_ptr, prng);
                }
            } else {
                animal_ai_utils.attemptMoveTowardsWanderTarget(bear_ptr, world_ptr, prng);
            }
        },
        .SeekingFood => {
            var found_target_this_tick = false;
            bear_ptr.must_complete_wander_step = false;

            if (!found_target_this_tick and is_hunting_peon_hungry and bear_ptr.target_entity_idx == null) {
                var closest_peon_idx: ?usize = null;
                var min_dist_sq_peon: i64 = -1;
                for (world_ptr.entities.items, 0..) |*entity, idx| {
                    if (bear_ptr.blocked_target_idx != null and bear_ptr.blocked_target_idx.? == idx and !bear_ptr.blocked_target_is_item and bear_ptr.blocked_target_cooldown > 0) {
                        continue;
                    }
                    if (entity.entity_type == .Player and entity.current_hp > 0) {
                        const d_sq = animal_ai_utils.distSq(bear_ptr.x, bear_ptr.y, entity.x, entity.y);
                        if (d_sq <= config.bear_hunt_target_sight_radius * config.bear_hunt_target_sight_radius) {
                            if (closest_peon_idx == null or d_sq < min_dist_sq_peon) {
                                min_dist_sq_peon = d_sq;
                                closest_peon_idx = idx;
                            }
                        }
                    }
                }
                if (closest_peon_idx) |target_idx| {
                    log.info("Bear {d},{d} (HP {d}) found Peon {d} to hunt. -> Hunting.", .{ bear_ptr.x, bear_ptr.y, bear_ptr.current_hp, target_idx });
                    bear_ptr.target_entity_idx = target_idx;
                    bear_ptr.target_item_idx = null;
                    bear_ptr.wander_target_x = world_ptr.entities.items[target_idx].x;
                    bear_ptr.wander_target_y = world_ptr.entities.items[target_idx].y;
                    bear_ptr.current_action = .Hunting;
                    found_target_this_tick = true;
                    bear_ptr.pathing_attempts_to_current_target = 0;
                }
            }

            if (!found_target_this_tick and is_hunting_sheep_hungry and bear_ptr.target_entity_idx == null) {
                var closest_sheep_idx: ?usize = null;
                var min_dist_sq_sheep: i64 = -1;
                for (world_ptr.entities.items, 0..) |*entity, idx| {
                    if (bear_ptr.blocked_target_idx != null and bear_ptr.blocked_target_idx.? == idx and !bear_ptr.blocked_target_is_item and bear_ptr.blocked_target_cooldown > 0) {
                        continue;
                    }
                    if (entity.entity_type == .Sheep and entity.current_hp > 0) {
                        const d_sq = animal_ai_utils.distSq(bear_ptr.x, bear_ptr.y, entity.x, entity.y);
                        if (d_sq <= config.bear_hunt_target_sight_radius * config.bear_hunt_target_sight_radius) {
                            if (closest_sheep_idx == null or d_sq < min_dist_sq_sheep) {
                                min_dist_sq_sheep = d_sq;
                                closest_sheep_idx = idx;
                            }
                        }
                    }
                }
                if (closest_sheep_idx) |target_idx| {
                    log.info("Bear {d},{d} (HP {d}) found Sheep {d} to hunt. -> Hunting.", .{ bear_ptr.x, bear_ptr.y, bear_ptr.current_hp, target_idx });
                    bear_ptr.target_entity_idx = target_idx;
                    bear_ptr.target_item_idx = null;
                    bear_ptr.wander_target_x = world_ptr.entities.items[target_idx].x;
                    bear_ptr.wander_target_y = world_ptr.entities.items[target_idx].y;
                    bear_ptr.current_action = .Hunting;
                    found_target_this_tick = true;
                    bear_ptr.pathing_attempts_to_current_target = 0;
                }
            }

            if (!found_target_this_tick and is_actively_seeking_meat and bear_ptr.target_item_idx == null) {
                var closest_meat_idx: ?usize = null;
                var min_dist_sq_meat: i64 = -1;
                for (world_ptr.items.items, 0..) |*item, idx| {
                    if (bear_ptr.blocked_target_idx != null and bear_ptr.blocked_target_idx.? == idx and bear_ptr.blocked_target_is_item and bear_ptr.blocked_target_cooldown > 0) {
                        continue;
                    }
                    if (item.item_type == .Meat) {
                        const d_sq = animal_ai_utils.distSq(bear_ptr.x, bear_ptr.y, item.x, item.y);
                        if (d_sq <= config.bear_meat_hungry_sight_radius * config.bear_meat_hungry_sight_radius) {
                            if (closest_meat_idx == null or d_sq < min_dist_sq_meat) {
                                min_dist_sq_meat = d_sq;
                                closest_meat_idx = idx;
                            }
                        }
                    }
                }
                if (closest_meat_idx) |target_idx| {
                    log.info("Bear {d},{d} (HP {d}) found Meat {d}. -> PickingUpItem.", .{ bear_ptr.x, bear_ptr.y, bear_ptr.current_hp, target_idx });
                    bear_ptr.target_item_idx = target_idx;
                    bear_ptr.target_entity_idx = null;
                    bear_ptr.wander_target_x = world_ptr.items.items[target_idx].x;
                    bear_ptr.wander_target_y = world_ptr.items.items[target_idx].y;
                    bear_ptr.current_action = .PickingUpItem;
                    found_target_this_tick = true;
                    bear_ptr.pathing_attempts_to_current_target = 0;
                }
            }

            if (found_target_this_tick) {
                if (bear_ptr.current_action == .PickingUpItem or bear_ptr.current_action == .Hunting) {
                    animal_ai_utils.attemptMoveTowardsWanderTarget(bear_ptr, world_ptr, prng);
                }
            } else {
                log.debug("Bear {d},{d} no food/hunt targets in SeekingFood. -> Wandering (forced escape).", .{ bear_ptr.x, bear_ptr.y });
                animal_ai_utils.chooseNewWanderTarget(bear_ptr, prng, world_ptr.width, world_ptr.height, true);
                bear_ptr.current_action = .Wandering;
                bear_ptr.must_complete_wander_step = true;
                bear_ptr.pathing_attempts_to_current_target = 0;
            }
        },
        .PickingUpItem => {
            bear_ptr.must_complete_wander_step = false;
            if (bear_ptr.target_item_idx) |target_idx| {
                if (target_idx < world_ptr.items.items.len) {
                    const target_item = world_ptr.items.items[target_idx];
                    if (target_item.item_type == .Meat) {
                        const dx_item = animal_ai_utils.absInt(bear_ptr.x - target_item.x);
                        const dy_item = animal_ai_utils.absInt(bear_ptr.y - target_item.y);
                        if (dx_item <= 1 and dy_item <= 1) {
                            _ = world_ptr.items.orderedRemove(target_idx);
                            bear_ptr.target_item_idx = null;
                            bear_ptr.pathing_attempts_to_current_target = 0;
                            bear_ptr.current_hp = @min(bear_ptr.max_hp, bear_ptr.current_hp + config.meat_hp_gain_bear);
                            bear_ptr.current_action = .Eating;
                            bear_ptr.current_action_timer = config.bear_eating_duration_ticks;
                        } else {
                            bear_ptr.wander_target_x = target_item.x;
                            bear_ptr.wander_target_y = target_item.y;
                            animal_ai_utils.attemptMoveTowardsWanderTarget(bear_ptr, world_ptr, prng);
                        }
                    } else {
                        bear_ptr.target_item_idx = null;
                        bear_ptr.pathing_attempts_to_current_target = 0;
                        if (is_very_hungry_for_anything) {
                            bear_ptr.current_action = .SeekingFood;
                        } else {
                            bear_ptr.current_action = .Idle;
                        }
                    }
                } else {
                    bear_ptr.target_item_idx = null;
                    bear_ptr.pathing_attempts_to_current_target = 0;
                    if (is_very_hungry_for_anything) {
                        bear_ptr.current_action = .SeekingFood;
                    } else {
                        bear_ptr.current_action = .Idle;
                    }
                }
            } else {
                bear_ptr.pathing_attempts_to_current_target = 0;
                if (is_very_hungry_for_anything) {
                    bear_ptr.current_action = .SeekingFood;
                } else {
                    bear_ptr.current_action = .Idle;
                }
            }
        },
        .Hunting => {
            bear_ptr.must_complete_wander_step = false;
            if (bear_ptr.target_entity_idx) |target_idx| {
                if (target_idx < world_ptr.entities.items.len) {
                    const target_prey = world_ptr.entities.items[target_idx];
                    // Update wander target to current prey position
                    bear_ptr.wander_target_x = target_prey.x;
                    bear_ptr.wander_target_y = target_prey.y;

                    if ((target_prey.entity_type == .Sheep or target_prey.entity_type == .Player) and target_prey.current_hp > 0) {
                        const dx_prey = animal_ai_utils.absInt(bear_ptr.x - target_prey.x);
                        const dy_prey = animal_ai_utils.absInt(bear_ptr.y - target_prey.y);
                        if (dx_prey <= 1 and dy_prey <= 1) {
                            log.debug("Bear {d},{d} reached prey {any} {d}. -> Attacking.", .{ bear_ptr.x, bear_ptr.y, target_prey.entity_type, target_idx });
                            bear_ptr.current_action = .Attacking;
                            bear_ptr.attack_cooldown = 0;
                            bear_ptr.pathing_attempts_to_current_target = 0;
                        } else {
                            animal_ai_utils.attemptMoveTowardsWanderTarget(bear_ptr, world_ptr, prng);
                        }
                    } else {
                        log.debug("Bear {d},{d} target prey {d} invalid/dead while Hunting. -> Re-evaluate.", .{ bear_ptr.x, bear_ptr.y, target_idx });
                        bear_ptr.target_entity_idx = null;
                        bear_ptr.pathing_attempts_to_current_target = 0;
                        if (is_very_hungry_for_anything) {
                            bear_ptr.current_action = .SeekingFood;
                        } else {
                            bear_ptr.current_action = .Idle;
                        }
                    }
                } else {
                    log.warn("Bear {d},{d} target_entity_idx {d} out of bounds while Hunting. -> Re-evaluate.", .{ bear_ptr.x, bear_ptr.y, target_idx });
                    bear_ptr.target_entity_idx = null;
                    bear_ptr.pathing_attempts_to_current_target = 0;
                    if (is_very_hungry_for_anything) {
                        bear_ptr.current_action = .SeekingFood;
                    } else {
                        bear_ptr.current_action = .Idle;
                    }
                }
            } else {
                log.warn("Bear {d},{d} in Hunting state with no target. -> Re-evaluate.", .{ bear_ptr.x, bear_ptr.y });
                bear_ptr.pathing_attempts_to_current_target = 0;
                if (is_very_hungry_for_anything) {
                    bear_ptr.current_action = .SeekingFood;
                } else {
                    bear_ptr.current_action = .Idle;
                }
            }
        },
        .Attacking => {
            bear_ptr.must_complete_wander_step = false;
            if (bear_ptr.attack_cooldown == 0) {
                if (bear_ptr.target_entity_idx) |target_idx| {
                    if (target_idx < world_ptr.entities.items.len) {
                        const target_prey_ptr = &world_ptr.entities.items[target_idx];
                        if ((target_prey_ptr.entity_type == .Sheep or target_prey_ptr.entity_type == .Player) and target_prey_ptr.current_hp > 0) {
                            const dx_prey_attack = animal_ai_utils.absInt(bear_ptr.x - target_prey_ptr.x);
                            const dy_prey_attack = animal_ai_utils.absInt(bear_ptr.y - target_prey_ptr.y);
                            if (dx_prey_attack <= 1 and dy_prey_attack <= 1) { // Re-check adjacency
                                log.debug("Bear {d},{d} attacking {any} {d}.", .{ bear_ptr.x, bear_ptr.y, target_prey_ptr.entity_type, target_idx });
                                combat.resolveAttack(bear_ptr, target_prey_ptr, world_ptr, prng);
                                bear_ptr.pathing_attempts_to_current_target = 0;
                                if (target_prey_ptr.current_hp == 0) {
                                    log.info("Bear at {d},{d} killed {any} at {d},{d}. -> SeekingFood (for meat).", .{ bear_ptr.x, bear_ptr.y, target_prey_ptr.entity_type, target_prey_ptr.x, target_prey_ptr.y });
                                    bear_ptr.target_entity_idx = null;
                                    bear_ptr.current_action = .SeekingFood;
                                } else {
                                    bear_ptr.attack_cooldown = config.attack_cooldown_ticks;
                                }
                            } else {
                                log.debug("Bear {d},{d} in Attacking, but no longer adjacent to prey {d}. -> Hunting.", .{ bear_ptr.x, bear_ptr.y, target_idx });
                                bear_ptr.current_action = .Hunting;
                                bear_ptr.pathing_attempts_to_current_target = 0;
                            }
                        } else {
                            log.debug("Bear {d},{d} in Attacking, target prey {d} invalid/dead. -> Re-evaluate.", .{ bear_ptr.x, bear_ptr.y, target_idx });
                            bear_ptr.target_entity_idx = null;
                            bear_ptr.pathing_attempts_to_current_target = 0;
                            if (is_very_hungry_for_anything) {
                                bear_ptr.current_action = .SeekingFood;
                            } else {
                                bear_ptr.current_action = .Idle;
                            }
                        }
                    } else {
                        log.warn("Bear {d},{d} in Attacking, target_idx {d} out of bounds. -> Re-evaluate.", .{ bear_ptr.x, bear_ptr.y, target_idx });
                        bear_ptr.target_entity_idx = null;
                        bear_ptr.pathing_attempts_to_current_target = 0;
                        if (is_very_hungry_for_anything) {
                            bear_ptr.current_action = .SeekingFood;
                        } else {
                            bear_ptr.current_action = .Idle;
                        }
                    }
                } else {
                    log.warn("Bear {d},{d} in Attacking with no target. -> Re-evaluate.", .{ bear_ptr.x, bear_ptr.y });
                    bear_ptr.pathing_attempts_to_current_target = 0;
                    if (is_very_hungry_for_anything) {
                        bear_ptr.current_action = .SeekingFood;
                    } else {
                        bear_ptr.current_action = .Idle;
                    }
                }
            }
            // If attack_cooldown > 0, the bear is waiting. Cooldown was decremented at the top.
        },
        .Eating => {
            if (bear_ptr.current_action_timer == 0) {
                bear_ptr.current_action = .Idle;
                bear_ptr.must_complete_wander_step = false;
            }
        },
        .Fleeing => {
            animal_ai_utils.chooseNewWanderTarget(bear_ptr, prng, world_ptr.width, world_ptr.height, false);
            bear_ptr.current_action = .Wandering;
            bear_ptr.must_complete_wander_step = false;
        },
    }
}
