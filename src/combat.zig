// src/combat.zig
// Handles combat mechanics between entities.
const std = @import("std");
const types = @import("types.zig");
const config = @import("config.zig");
const log = std.log;
const RandomInterface = std.Random; // If we add randomness to combat later

pub fn resolveAttack(
    attacker: *types.Entity,
    defender: *types.Entity,
    world: *types.GameWorld, // May not be needed for basic attack, but good to have for future (e.g. terrain effects)
    prng: *RandomInterface, // For future randomness (e.g., critical hits, misses)
) void {
    _ = world; // Unused for now
    _ = prng; // Unused for now

    if (attacker.attack_cooldown > 0) {
        // log.debug("Attacker {any} on cooldown, {d} ticks left.", .{ attacker.entity_type, attacker.attack_cooldown });
        return; // Attacker is on cooldown
    }
    if (defender.current_hp == 0) {
        // log.debug("Defender {any} is already dead.", .{defender.entity_type});
        return; // Target is already dead
    }

    var damage: i16 = 0;

    // Determine damage based on attacker and defender types
    switch (attacker.entity_type) {
        .Player => { // Peon attacking
            damage = switch (defender.entity_type) {
                .Sheep => config.peon_damage_vs_sheep,
                .Bear => config.peon_damage_vs_bear,
                else => 0, // Peons don't attack other things by default
            };
        },
        .Bear => { // Bear attacking
            damage = switch (defender.entity_type) {
                .Player => config.bear_damage_vs_peon,
                .Sheep => config.bear_damage_vs_sheep,
                else => 0, // Bears only attack Peons and Sheep
            };
        },
        .Sheep => { // Sheep don't attack
            damage = 0;
        },
        // Static entities don't attack
        .Tree, .RockCluster, .Brush => damage = 0,
    }

    if (damage > 0) {
        log.debug("{any} attacks {any} for {d} damage.", .{ attacker.entity_type, defender.entity_type, damage });
        if (defender.current_hp > damage) {
            defender.current_hp -= damage;
        } else {
            defender.current_hp = 0; // Target dies
            log.info("{any} killed {any}.", .{ attacker.entity_type, defender.entity_type });
        }
        attacker.attack_cooldown = config.attack_cooldown_ticks; // Set attacker's cooldown
    } else {
        // log.debug("{any} attempted to attack {any} but dealt no damage (or not a valid target).", .{ attacker.entity_type, defender.entity_type });
    }
}
