// src/bear_ai.zig
// Handles AI logic for Bear entities.
const std_full = @import("std");
const types = @import("types.zig");
const config = @import("config.zig");
// const art = @import("art.zig");
const animal_ai_utils = @import("animal_ai.zig");
const entity_processing = @import("entity_processing.zig"); // NEW

const log = std_full.log;
const math = std_full.math;
const RandomInterface = std_full.Random;

// Updates the AI state for a Bear entity
pub fn updateBear(bear_ptr: *types.Entity, world_ptr: *types.GameWorld, prng: *RandomInterface) void {
    if (bear_ptr.entity_type != .Bear) {
        return;
    }

    // Process HP decay first for this entity
    entity_processing.processHpDecay(bear_ptr); // NEW

    if (bear_ptr.current_hp == 0) { // Check if died from decay
        return;
    }

    switch (bear_ptr.current_action) {
        .Idle => {
            if (prng.float(f32) < config.bear_move_attempt_chance) {
                animal_ai_utils.chooseNewWanderTarget(bear_ptr, prng, world_ptr.width, world_ptr.height);
                bear_ptr.current_action = .Wandering;
                bear_ptr.must_complete_wander_step = false;
            }
        },
        .Wandering => {
            animal_ai_utils.attemptMoveTowardsWanderTarget(bear_ptr, world_ptr, prng);
        },
        else => {
            animal_ai_utils.chooseNewWanderTarget(bear_ptr, prng, world_ptr.width, world_ptr.height);
            bear_ptr.current_action = .Wandering;
            bear_ptr.must_complete_wander_step = false;
        },
    }
    if (bear_ptr.move_cooldown_ticks > 0) {
        bear_ptr.move_cooldown_ticks -= 1;
    }
}
