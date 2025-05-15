// src/combat.zig
// Handles combat mechanics and harvesting interactions between entities.
const std = @import("std");
const types = @import("types.zig");
const config = @import("config.zig");
const log = std.log;
const RandomInterface = std.Random;

pub fn resolveAttack(
    attacker: *types.Entity,
    defender: *types.Entity,
    world: *types.GameWorld, // May not be needed for basic attack, but good to have for future (e.g. terrain effects)
    prng: *RandomInterface, // For future randomness (e.g., critical hits, misses)
) void {
    _ = world; // Unused for now
    _ = prng; // Unused for now

    // Check if attacker is on cooldown.
    // This is a general attack cooldown. Specific action cooldowns (like harvesting)
    // are managed by the AI calling this function by resetting attacker.attack_cooldown AFTER this call.
    if (attacker.attack_cooldown > 0) {
        // log.debug("Attacker {any} on general attack cooldown, {d} ticks left.", .{ attacker.entity_type, attacker.attack_cooldown });
        return;
    }
    if (defender.current_hp == 0) {
        // log.debug("Defender {any} is already dead/destroyed.", .{defender.entity_type});
        return;
    }

    var damage: i16 = 0;

    // Determine damage based on attacker and defender types
    switch (attacker.entity_type) {
        .Player => { // Peon attacking
            damage = switch (defender.entity_type) {
                .Sheep => config.peon_damage_vs_sheep,
                .Bear => config.peon_damage_vs_bear,
                // TODO: Add cases for Peon attacking/harvesting Tree, RockCluster, Brush if desired
                // For example, if a Peon harvests Brush:
                // .Brush => config.peon_damage_vs_brush, // Define this in config.zig
                else => 0,
            };
        },
        .Bear => { // Bear attacking
            damage = switch (defender.entity_type) {
                .Player => config.bear_damage_vs_peon,
                .Sheep => config.bear_damage_vs_sheep,
                else => 0, // Bears only attack Peons and Sheep for now
            };
        },
        .Sheep => { // Sheep "attacking" (e.g., harvesting)
            damage = switch (defender.entity_type) {
                .Brush => config.sheep_damage_vs_brush, // Sheep harvests Brush
                else => 0, // Sheep don't attack other entities in combat
            };
        },
        // Static entities like Tree, RockCluster, Brush don't initiate attacks themselves.
        .Tree, .RockCluster, .Brush => {
            damage = 0;
        },
    }

    if (damage > 0) {
        if (defender.entity_type == .Brush and attacker.entity_type == .Sheep) {
            log.debug("Sheep harvesting {any} at {d},{d} for {d} 'damage'. Current HP: {d}", .{ defender.entity_type, defender.x, defender.y, damage, defender.current_hp });
        } else {
            log.debug("{any} at {d},{d} attacks {any} at {d},{d} for {d} damage. Defender HP: {d}", .{ attacker.entity_type, attacker.x, attacker.y, defender.entity_type, defender.x, defender.y, damage, defender.current_hp });
        }

        if (defender.current_hp > damage) {
            defender.current_hp -= damage;
        } else {
            defender.current_hp = 0; // Target dies or is destroyed
            if (defender.entity_type == .Brush and attacker.entity_type == .Sheep) {
                log.info("Sheep at {d},{d} harvested/destroyed {any} at {d},{d}.", .{ attacker.x, attacker.y, defender.entity_type, defender.x, defender.y });
            } else {
                log.info("{any} at {d},{d} killed {any} at {d},{d}.", .{ attacker.entity_type, attacker.x, attacker.y, defender.entity_type, defender.x, defender.y });
            }
            // Note: Item drops are handled by entity_processing when main loop detects HP is 0.
        }
        // Set a general attack cooldown.
        // The calling AI (e.g. sheep harvesting) is responsible for setting a more specific
        // cooldown (like harvest_brush_cooldown_ticks) AFTER this function returns if needed.
        attacker.attack_cooldown = config.attack_cooldown_ticks;
    } else {
        // log.debug("{any} attempted to interact with {any} but dealt no damage (or not a valid target for this interaction).", .{ attacker.entity_type, defender.entity_type });
    }
}
