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

    // --- Define Hunger States for Bear ---
    const eat_opportunistic_hp_threshold = @as(i16, @intFromFloat(@as(f32, @floatFromInt(bear_ptr.max_hp)) * config.bear_hp_eat_opportunistic_threshold_percent)); // 80%
    const seek_meat_actively_hp_threshold = @as(i16, @intFromFloat(@as(f32, @floatFromInt(bear_ptr.max_hp)) * config.bear_hp_seek_meat_actively_threshold_percent)); // 60%
    const hunt_sheep_hp_threshold = @as(i16, @intFromFloat(@as(f32, @floatFromInt(bear_ptr.max_hp)) * config.bear_hp_hunt_sheep_threshold_percent)); // 50%
    const hunt_peon_hp_threshold = @as(i16, @intFromFloat(@as(f32, @floatFromInt(bear_ptr.max_hp)) * config.bear_hp_hunt_peon_threshold_percent)); // 40%

    const is_opportunistically_hungry = bear_ptr.current_hp <= eat_opportunistic_hp_threshold;
    const is_actively_seeking_meat = bear_ptr.current_hp < seek_meat_actively_hp_threshold;
    const is_hunting_sheep_hungry = bear_ptr.current_hp < hunt_sheep_hp_threshold;
    const is_hunting_peon_hungry = bear_ptr.current_hp < hunt_peon_hp_threshold;

    const is_very_hungry_for_anything = is_actively_seeking_meat or is_hunting_sheep_hungry or is_hunting_peon_hungry;

    // --- Eating Timer ---
    if (bear_ptr.current_action == .Eating) {
        if (bear_ptr.current_action_timer > 0) {
            bear_ptr.current_action_timer -= 1;
            if (bear_ptr.current_action_timer == 0) {
                log.debug("Bear at {d},{d} finished eating. HP: {d}/{d}", .{ bear_ptr.x, bear_ptr.y, bear_ptr.current_hp, bear_ptr.max_hp });
                bear_ptr.current_action = .Idle;
                bear_ptr.must_complete_wander_step = false;
            }
        }
        return;
    }

    // --- Attack Cooldown ---
    if (bear_ptr.attack_cooldown > 0) {
        bear_ptr.attack_cooldown -= 1;
    }

    // --- Initial hunger check if Idle ---
    if (is_very_hungry_for_anything and bear_ptr.current_action == .Idle) {
        log.debug("Bear {d},{d} is Idle and very hungry. -> SeekingFood.", .{ bear_ptr.x, bear_ptr.y });
        bear_ptr.current_action = .SeekingFood;
        bear_ptr.target_entity_idx = null;
        bear_ptr.target_item_idx = null;
        bear_ptr.must_complete_wander_step = false;
    }

    switch (bear_ptr.current_action) {
        .Idle => {
            if (!is_very_hungry_for_anything) { // If not very hungry, check for opportunistic meat or wander
                var closest_meat_idx: ?usize = null;
                var min_dist_sq_meat: i64 = -1;
                if (is_opportunistically_hungry) { // Only look if at least 80% hungry
                    for (world_ptr.items.items, 0..) |*item, idx| {
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
                }
                if (closest_meat_idx) |target_idx| {
                    bear_ptr.target_item_idx = target_idx;
                    bear_ptr.wander_target_x = world_ptr.items.items[target_idx].x;
                    bear_ptr.wander_target_y = world_ptr.items.items[target_idx].y;
                    bear_ptr.current_action = .PickingUpItem;
                } else if (prng.float(f32) < config.bear_move_attempt_chance) {
                    animal_ai_utils.chooseNewWanderTarget(bear_ptr, prng, world_ptr.width, world_ptr.height);
                    bear_ptr.current_action = .Wandering;
                    bear_ptr.must_complete_wander_step = false;
                }
            }
            // If very hungry, the check above the switch already transitioned to SeekingFood.
        },
        .Wandering => {
            if (bear_ptr.must_complete_wander_step) {
                animal_ai_utils.attemptMoveTowardsWanderTarget(bear_ptr, world_ptr, prng);
            } else if (is_very_hungry_for_anything) {
                bear_ptr.current_action = .SeekingFood;
                bear_ptr.target_entity_idx = null;
                bear_ptr.target_item_idx = null;
            } else if (is_opportunistically_hungry) { // Check for opportunistic meat while wandering
                var closest_meat_idx: ?usize = null;
                var min_dist_sq_meat: i64 = -1;
                for (world_ptr.items.items, 0..) |*item, idx| {
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
                    bear_ptr.wander_target_x = world_ptr.items.items[target_idx].x;
                    bear_ptr.wander_target_y = world_ptr.items.items[target_idx].y;
                    bear_ptr.current_action = .PickingUpItem;
                } else {
                    animal_ai_utils.attemptMoveTowardsWanderTarget(bear_ptr, world_ptr, prng);
                }
            } else {
                animal_ai_utils.attemptMoveTowardsWanderTarget(bear_ptr, world_ptr, prng);
            }
        },
        .SeekingFood => { // Actively seeking food when very hungry
            var found_target_this_tick = false;
            bear_ptr.must_complete_wander_step = false;

            // Priority 1: Hunt Peons if hungry enough
            if (!found_target_this_tick and is_hunting_peon_hungry and bear_ptr.target_entity_idx == null) {
                // ... (Find closest Peon within bear_hunt_target_sight_radius) ...
                // if found: set target_entity_idx, set wander_target, current_action = .Hunting, found_target_this_tick = true
            }
            // Priority 2: Hunt Sheep if hungry enough
            if (!found_target_this_tick and is_hunting_sheep_hungry and bear_ptr.target_entity_idx == null) {
                // ... (Find closest Sheep within bear_hunt_target_sight_radius) ...
                // if found: set target_entity_idx, set wander_target, current_action = .Hunting, found_target_this_tick = true
            }
            // Priority 3: Seek Meat on ground if actively seeking meat
            if (!found_target_this_tick and is_actively_seeking_meat and bear_ptr.target_item_idx == null) {
                var closest_meat_idx: ?usize = null;
                var min_dist_sq_meat: i64 = -1;
                for (world_ptr.items.items, 0..) |*item, idx| {
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
                    bear_ptr.target_item_idx = target_idx;
                    bear_ptr.wander_target_x = world_ptr.items.items[target_idx].x;
                    bear_ptr.wander_target_y = world_ptr.items.items[target_idx].y;
                    bear_ptr.current_action = .PickingUpItem;
                    found_target_this_tick = true;
                }
            }

            if (found_target_this_tick) {
                if (bear_ptr.current_action == .PickingUpItem or bear_ptr.current_action == .Hunting) {
                    animal_ai_utils.attemptMoveTowardsWanderTarget(bear_ptr, world_ptr, prng);
                }
            } else {
                log.debug("Bear {d},{d} no food/hunt targets in SeekingFood. -> Wandering (forced step).", .{ bear_ptr.x, bear_ptr.y });
                animal_ai_utils.chooseNewWanderTarget(bear_ptr, prng, world_ptr.width, world_ptr.height);
                bear_ptr.current_action = .Wandering;
                bear_ptr.must_complete_wander_step = true;
            }
        },
        .PickingUpItem => { // Bear picking up meat
            bear_ptr.must_complete_wander_step = false;
            if (bear_ptr.target_item_idx) |target_idx| {
                if (target_idx < world_ptr.items.items.len) {
                    const target_item = world_ptr.items.items[target_idx];
                    if (target_item.item_type == .Meat) {
                        if (bear_ptr.x == target_item.x and bear_ptr.y == target_item.y) {
                            _ = world_ptr.items.orderedRemove(target_idx);
                            bear_ptr.target_item_idx = null;
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
                        if (is_very_hungry_for_anything) {
                            bear_ptr.current_action = .SeekingFood;
                        } else {
                            bear_ptr.current_action = .Idle;
                        }
                    }
                } else {
                    bear_ptr.target_item_idx = null;
                    if (is_very_hungry_for_anything) {
                        bear_ptr.current_action = .SeekingFood;
                    } else {
                        bear_ptr.current_action = .Idle;
                    }
                }
            } else {
                if (is_very_hungry_for_anything) {
                    bear_ptr.current_action = .SeekingFood;
                } else {
                    bear_ptr.current_action = .Idle;
                }
            }
        },
        .Hunting => { // Moving towards a Sheep or Peon
            bear_ptr.must_complete_wander_step = false;
            if (bear_ptr.target_entity_idx) |target_idx| {
                if (target_idx < world_ptr.entities.items.len) {
                    const target_prey = world_ptr.entities.items[target_idx];
                    // Ensure target is still valid prey type and alive
                    if ((target_prey.entity_type == .Sheep or target_prey.entity_type == .Player) and target_prey.current_hp > 0) {
                        if (animal_ai_utils.absInt(bear_ptr.x - target_prey.x) <= 1 and animal_ai_utils.absInt(bear_ptr.y - target_prey.y) <= 1 and
                            (animal_ai_utils.absInt(bear_ptr.x - target_prey.x) + animal_ai_utils.absInt(bear_ptr.y - target_prey.y) <= 1 or (animal_ai_utils.absInt(bear_ptr.x - target_prey.x) == 1 and animal_ai_utils.absInt(bear_ptr.y - target_prey.y) == 1)))
                        {
                            bear_ptr.current_action = .Attacking;
                            bear_ptr.attack_cooldown = 0;
                        } else {
                            bear_ptr.wander_target_x = target_prey.x;
                            bear_ptr.wander_target_y = target_prey.y;
                            animal_ai_utils.attemptMoveTowardsWanderTarget(bear_ptr, world_ptr, prng);
                        }
                    } else { // Target is no longer valid prey
                        bear_ptr.target_entity_idx = null;
                        if (is_very_hungry_for_anything) {
                            bear_ptr.current_action = .SeekingFood;
                        } else {
                            bear_ptr.current_action = .Idle;
                        }
                    }
                } else { // Target index out of bounds
                    bear_ptr.target_entity_idx = null;
                    if (is_very_hungry_for_anything) {
                        bear_ptr.current_action = .SeekingFood;
                    } else {
                        bear_ptr.current_action = .Idle;
                    }
                }
            } else { // No target while Hunting
                if (is_very_hungry_for_anything) {
                    bear_ptr.current_action = .SeekingFood;
                } else {
                    bear_ptr.current_action = .Idle;
                }
            }
        },
        .Attacking => { // Bear attacking Sheep or Peon
            bear_ptr.must_complete_wander_step = false;
            if (bear_ptr.attack_cooldown == 0) {
                if (bear_ptr.target_entity_idx) |target_idx| {
                    if (target_idx < world_ptr.entities.items.len) {
                        const target_prey_ptr = &world_ptr.entities.items[target_idx];
                        if ((target_prey_ptr.entity_type == .Sheep or target_prey_ptr.entity_type == .Player) and target_prey_ptr.current_hp > 0) {
                            if (animal_ai_utils.absInt(bear_ptr.x - target_prey_ptr.x) <= 1 and animal_ai_utils.absInt(bear_ptr.y - target_prey_ptr.y) <= 1 and
                                (animal_ai_utils.absInt(bear_ptr.x - target_prey_ptr.x) + animal_ai_utils.absInt(bear_ptr.y - target_prey_ptr.y) <= 1 or (animal_ai_utils.absInt(bear_ptr.x - target_prey_ptr.x) == 1 and animal_ai_utils.absInt(bear_ptr.y - target_prey_ptr.y) == 1)))
                            {
                                combat.resolveAttack(bear_ptr, target_prey_ptr, world_ptr, prng);
                                if (target_prey_ptr.current_hp == 0) {
                                    bear_ptr.target_entity_idx = null;
                                    // After a kill, might look for the corpse (meat) or just become idle/seek other food
                                    bear_ptr.current_action = .SeekingFood; // To look for the dropped meat
                                } else {
                                    bear_ptr.attack_cooldown = config.attack_cooldown_ticks; // General attack cooldown
                                }
                            } else { // No longer adjacent
                                bear_ptr.current_action = .Hunting;
                            }
                        } else { // Target invalid
                            bear_ptr.target_entity_idx = null;
                            if (is_very_hungry_for_anything) {
                                bear_ptr.current_action = .SeekingFood;
                            } else {
                                bear_ptr.current_action = .Idle;
                            }
                        }
                    } else { // Index out of bounds
                        bear_ptr.target_entity_idx = null;
                        if (is_very_hungry_for_anything) {
                            bear_ptr.current_action = .SeekingFood;
                        } else {
                            bear_ptr.current_action = .Idle;
                        }
                    }
                } else { // No target
                    if (is_very_hungry_for_anything) {
                        bear_ptr.current_action = .SeekingFood;
                    } else {
                        bear_ptr.current_action = .Idle;
                    }
                }
            }
        },
        .Eating => {
            if (bear_ptr.current_action_timer == 0) {
                bear_ptr.current_action = .Idle;
                bear_ptr.must_complete_wander_step = false;
            }
        },
        .Fleeing => {
            animal_ai_utils.chooseNewWanderTarget(bear_ptr, prng, world_ptr.width, world_ptr.height);
            bear_ptr.current_action = .Wandering;
            bear_ptr.must_complete_wander_step = false;
        },
    }
}
