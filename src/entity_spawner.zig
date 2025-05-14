// src/entity_spawner.zig
// Handles the spawning of all initial entities in the game world.
// This module now initializes and manages its own noise generators.
const std_full = @import("std");
const types = @import("types.zig");
const config = @import("config.zig");
const noise_utils = @import("noise_utils.zig"); // For NoiseGenerator
const math = std_full.math;
const log = std_full.log;
const RandomInterface = std_full.Random;

// Helper function to check for nearby sand tiles
fn isCoastalGrass(world: *const types.GameWorld, x: i32, y: i32, max_dist: u32) bool {
    if (world.getTile(x, y)) |current_tile| {
        if (current_tile.base_terrain != .Grass) return false; // Only apply to grass tiles
    } else return false; // Current tile out of bounds

    var dist: u32 = 1;
    while (dist <= max_dist) : (dist += 1) {
        // Check cardinal directions
        if (world.getTile(x, y - @as(i32, @intCast(dist)))) |n_tile| {
            if (n_tile.base_terrain == .Sand) return true;
        }
        if (world.getTile(x, y + @as(i32, @intCast(dist)))) |s_tile| {
            if (s_tile.base_terrain == .Sand) return true;
        }
        if (world.getTile(x - @as(i32, @intCast(dist)), y)) |w_tile| {
            if (w_tile.base_terrain == .Sand) return true;
        }
        if (world.getTile(x + @as(i32, @intCast(dist)), y)) |e_tile| {
            if (e_tile.base_terrain == .Sand) return true;
        }
        // Check diagonal directions
        if (world.getTile(x - @as(i32, @intCast(dist)), y - @as(i32, @intCast(dist)))) |nw_tile| {
            if (nw_tile.base_terrain == .Sand) return true;
        }
        if (world.getTile(x + @as(i32, @intCast(dist)), y - @as(i32, @intCast(dist)))) |ne_tile| {
            if (ne_tile.base_terrain == .Sand) return true;
        }
        if (world.getTile(x - @as(i32, @intCast(dist)), y + @as(i32, @intCast(dist)))) |sw_tile| {
            if (sw_tile.base_terrain == .Sand) return true;
        }
        if (world.getTile(x + @as(i32, @intCast(dist)), y + @as(i32, @intCast(dist)))) |se_tile| {
            if (se_tile.base_terrain == .Sand) return true;
        }
    }
    return false;
}

// Spawns all initial static and dynamic entities in the world.
pub fn spawnInitialEntities(
    world: *types.GameWorld,
    island_random_iface: *RandomInterface, // For random decisions in spawning
) void {
    log.info("Initializing noise generators for entity spawning...", .{});
    var forest_core_noise = noise_utils.NoiseGenerator.init(island_random_iface.int(u64), world.allocator, config.grid_cell_size_forest_core, world.width, world.height);
    defer forest_core_noise.deinit();
    var deforestation_noise = noise_utils.NoiseGenerator.init(island_random_iface.int(u64), world.allocator, config.grid_cell_size_deforestation, world.width, world.height);
    defer deforestation_noise.deinit();
    var rock_noise = noise_utils.NoiseGenerator.init(island_random_iface.int(u64), world.allocator, config.grid_cell_size_rock, world.width, world.height);
    defer rock_noise.deinit();
    var brush_noise = noise_utils.NoiseGenerator.init(island_random_iface.int(u64), world.allocator, config.grid_cell_size_brush, world.width, world.height);
    defer brush_noise.deinit();
    log.info("Entity noise generators initialized.", .{});

    log.info("Placing static entities (trees, rocks, brush)...", .{});
    var tree_spawn_attempts: u32 = 0;
    var trees_actually_spawned: u32 = 0;
    var rocks_actually_spawned: u32 = 0;
    var brush_actually_spawned: u32 = 0;

    for (0..world.height) |y_idx| {
        for (0..world.width) |x_idx| {
            const x_u32_cast: u32 = @intCast(x_idx);
            const y_u32_cast: u32 = @intCast(y_idx);

            if (world.getTile(@as(i32, @intCast(x_u32_cast)), @as(i32, @intCast(y_u32_cast)))) |tile| {
                const fx = @as(f32, @floatFromInt(x_u32_cast));
                const fy = @as(f32, @floatFromInt(y_u32_cast));
                const current_elevation = world.elevation_data[y_idx * world.width + x_idx];

                const forest_core_raw = forest_core_noise.fbm(fx, fy, config.forest_core_octaves, config.forest_core_persistence, config.forest_core_lacunarity);
                const forest_core_norm = (forest_core_raw + 1.0) / 2.0;

                const deforestation_raw = deforestation_noise.fbm(fx, fy, config.deforestation_octaves, config.deforestation_persistence, config.deforestation_lacunarity);
                const deforestation_norm = (deforestation_raw + 1.0) / 2.0;

                const rock_raw = rock_noise.fbm(fx, fy, config.rock_octaves, config.rock_persistence, config.rock_lacunarity);
                const rock_norm = (rock_raw + 1.0) / 2.0;

                const brush_raw = brush_noise.fbm(fx, fy, config.brush_octaves, config.brush_persistence, config.brush_lacunarity);
                const brush_norm = (brush_raw + 1.0) / 2.0;

                const processed_forest_core_val = math.pow(f32, forest_core_norm, config.forest_core_processing_power);
                const processed_deforestation_val = math.pow(f32, deforestation_norm, config.deforestation_processing_power);

                var tree_placed_on_tile = false; // Flag to prevent brush if tree is placed

                // --- Tree Placement ---
                if (tile.base_terrain == .Grass) {
                    const deforestation_factor = processed_deforestation_val;

                    var spawn_density_raw = processed_forest_core_val * (1.0 - deforestation_factor);
                    spawn_density_raw = math.clamp(spawn_density_raw, 0.0, 1.0);

                    const spawn_density_shaped = math.pow(f32, spawn_density_raw, config.tree_spawn_density_power);
                    const spawn_density_capped = @min(spawn_density_shaped, config.max_tree_spawn_density_cap);

                    var age_determining_density = processed_forest_core_val;
                    age_determining_density *= (1.0 - deforestation_factor * 0.5);
                    age_determining_density = math.clamp(age_determining_density, 0.0, 1.0);

                    if (spawn_density_capped > config.tree_density_threshold) {
                        tree_spawn_attempts += 1;
                        if (island_random_iface.float(f32) < (config.grass_tree_base_probability * spawn_density_capped)) {
                            const max_s = config.max_growth_stage_tree;
                            const ideal_stage_float = age_determining_density * @as(f32, @floatFromInt(max_s + 1)) - config.tree_age_noise_offset;

                            const stage_random_factor = (island_random_iface.float(f32) - 0.5) * config.tree_age_random_spread;
                            const s1_raw = ideal_stage_float - config.tree_age_range_radius + stage_random_factor;
                            const s2_raw = ideal_stage_float + config.tree_age_range_radius + stage_random_factor;

                            const s1 = @max(0, @as(i16, @intFromFloat(math.floor(s1_raw))));
                            const s2 = @min(max_s, @as(u8, @intFromFloat(math.ceil(s2_raw))));
                            var stage_to_spawn = island_random_iface.intRangeAtMost(u8, @as(u8, @intCast(s1)), s2);
                            if (s1 > s2) {
                                stage_to_spawn = @as(u8, @intCast(s1));
                            }

                            if (!world.isTileOccupiedByStaticEntity(@as(i32, @intCast(x_u32_cast)), @as(i32, @intCast(y_u32_cast)))) {
                                const tree_entity = types.Entity.newTree(@as(i32, @intCast(x_u32_cast)), @as(i32, @intCast(y_u32_cast)), stage_to_spawn);
                                world.entities.append(tree_entity) catch |err| {
                                    log.err("CRITICAL: Failed to append tree on grass at {d},{d}: {s}", .{ x_u32_cast, y_u32_cast, @errorName(err) });
                                };
                                trees_actually_spawned += 1;
                                tree_placed_on_tile = true;
                            }
                        }
                    }
                } else if (tile.base_terrain == .Plains and current_elevation < (config.plains_elevation_threshold - 0.08)) {
                    if (forest_core_norm > config.plains_tree_core_threshold and island_random_iface.float(f32) < config.plains_tree_base_probability) {
                        if (!world.isTileOccupiedByStaticEntity(@as(i32, @intCast(x_u32_cast)), @as(i32, @intCast(y_u32_cast)))) {
                            const tree_entity = types.Entity.newTree(@as(i32, @intCast(x_u32_cast)), @as(i32, @intCast(y_u32_cast)), 0);
                            world.entities.append(tree_entity) catch |err| {
                                log.err("CRITICAL: Failed to append tree on plains at {d},{d}: {s}", .{ x_u32_cast, y_u32_cast, @errorName(err) });
                            };
                            trees_actually_spawned += 1;
                            tree_placed_on_tile = true;
                        }
                    }
                }

                // --- Rock Placement ---
                var spawn_rock = false;
                var rock_spawn_prob: f32 = 0.0;
                var rock_noise_thresh: f32 = 1.1;

                if (tile.base_terrain == .Plains) {
                    if (current_elevation >= (config.plains_elevation_threshold - config.plains_upper_edge_factor)) {
                        rock_spawn_prob = config.upper_plains_rock_probability;
                        rock_noise_thresh = config.upper_plains_rock_noise_thresh;
                    } else {
                        rock_spawn_prob = config.mid_plains_rock_probability;
                        rock_noise_thresh = config.mid_plains_rock_noise_thresh;
                    }
                } else if (tile.base_terrain == .Grass) {
                    rock_spawn_prob = config.grass_rock_probability;
                    rock_noise_thresh = config.grass_rock_noise_thresh;
                } else if (tile.base_terrain == .Sand) {
                    rock_spawn_prob = config.sand_rock_probability;
                    rock_noise_thresh = config.sand_rock_noise_thresh;
                } else if (tile.base_terrain == .ShallowWater) {
                    rock_spawn_prob = config.shallow_water_rock_probability;
                    rock_noise_thresh = config.shallow_water_rock_noise_thresh;
                }

                if (rock_norm > rock_noise_thresh and island_random_iface.float(f32) < rock_spawn_prob) {
                    spawn_rock = true;
                }

                if (spawn_rock) {
                    if (!world.isTileOccupiedByStaticEntity(@as(i32, @intCast(x_u32_cast)), @as(i32, @intCast(y_u32_cast)))) {
                        const rock_entity = types.Entity.newRockCluster(@as(i32, @intCast(x_u32_cast)), @as(i32, @intCast(y_u32_cast)));
                        world.entities.append(rock_entity) catch |err| {
                            log.warn("Rock append fail ({s}): {s}", .{ @tagName(tile.base_terrain), @errorName(err) });
                        };
                        rocks_actually_spawned += 1;
                    }
                }

                // --- Brush Placement ---
                if (!tree_placed_on_tile) { // Only consider brush if a tree wasn't placed on this exact tile
                    const brush_density_mod = 1.0 - math.pow(f32, deforestation_norm, config.brush_deforestation_power_factor);
                    var base_brush_prob: f32 = 0.0;
                    var base_brush_thresh: f32 = 1.1;
                    var is_coastal_grass_for_brush = false;

                    if (tile.base_terrain == .Grass and isCoastalGrass(world, @as(i32, @intCast(x_u32_cast)), @as(i32, @intCast(y_u32_cast)), config.coastal_grass_brush_max_dist_to_sand)) {
                        base_brush_prob = config.coastal_grass_brush_probability;
                        base_brush_thresh = config.coastal_grass_brush_noise_thresh;
                        is_coastal_grass_for_brush = true;
                    } else if (tile.base_terrain == .Plains) {
                        base_brush_prob = config.plains_brush_probability;
                        base_brush_thresh = config.plains_brush_noise_thresh;
                        if (current_elevation < (config.sand_elevation_threshold + config.plains_brush_sand_transition_factor)) {
                            base_brush_prob *= config.brush_sand_transition_prob_multiplier;
                            base_brush_thresh = config.plains_near_sand_brush_noise_thresh;
                        }
                    } else if (tile.base_terrain == .Grass and !is_coastal_grass_for_brush) { // Regular grass (not coastal)
                        base_brush_prob = config.grass_brush_probability;
                        base_brush_thresh = config.grass_brush_noise_thresh;
                        if (current_elevation < (config.sand_elevation_threshold + config.grass_brush_sand_transition_factor)) {
                            base_brush_prob *= config.brush_sand_transition_prob_multiplier;
                            base_brush_thresh = config.grass_near_sand_brush_noise_thresh;
                        }
                    } else if (tile.base_terrain == .Sand) {
                        base_brush_prob = config.sand_brush_probability;
                        base_brush_thresh = config.sand_brush_noise_thresh;
                    }

                    const effective_brush_probability = base_brush_prob * brush_density_mod;

                    if (effective_brush_probability > 0) {
                        if (brush_norm > base_brush_thresh and island_random_iface.float(f32) < effective_brush_probability) {
                            if (!world.isTileOccupiedByStaticEntity(@as(i32, @intCast(x_u32_cast)), @as(i32, @intCast(y_u32_cast)))) {
                                const brush_entity = types.Entity.newBrush(@as(i32, @intCast(x_u32_cast)), @as(i32, @intCast(y_u32_cast)));
                                world.entities.append(brush_entity) catch |err| {
                                    log.warn("Brush append ({s}) fail: {s}", .{ @tagName(tile.base_terrain), @errorName(err) });
                                };
                                brush_actually_spawned += 1;
                            }
                        }
                    }
                } // end if !tree_placed_on_tile
            } // end if tile
        } // end for x_idx
    } // end for y_idx

    log.info("--- Static Entity Spawn Summary ---", .{});
    log.info("Tree spawn attempts (density OK): {d}", .{tree_spawn_attempts});
    log.info("Trees actually spawned: {d}", .{trees_actually_spawned});
    log.info("Rocks actually spawned: {d}", .{rocks_actually_spawned});
    log.info("Brush actually spawned: {d}", .{brush_actually_spawned});
    log.info("--- End Static Entity Summary ---", .{});
    log.info("Static entities placed.", .{});

    // --- Spawn Initial Dynamic Entities (Peons, Sheep, Bears) ---
    log.info("Spawning initial Peons...", .{});
    var peons_spawned: u32 = 0;
    while (peons_spawned < config.num_initial_peons) : (peons_spawned += 1) {
        world.addEntityRandomSpawn(.Player, island_random_iface, null) catch |err| {
            log.warn("Failed to spawn initial peon {d}: {s}", .{ peons_spawned, @errorName(err) });
        };
    }
    log.info("Peons Spawned: {d}", .{config.num_initial_peons});

    log.info("Herding initial Sheep...", .{});
    var sheep_spawned: u32 = 0;
    while (sheep_spawned < config.num_sheep) : (sheep_spawned += 1) {
        world.addEntityRandomSpawn(.Sheep, island_random_iface, null) catch |err| {
            log.warn("Failed to spawn sheep {d}: {s}", .{ sheep_spawned, @errorName(err) });
        };
    }
    log.info("Sheep Herded: {d}", .{config.num_sheep});

    log.info("Waking initial Bears...", .{});
    var bears_spawned: u32 = 0;
    while (bears_spawned < config.num_bears) : (bears_spawned += 1) {
        world.addEntityRandomSpawn(.Bear, island_random_iface, null) catch |err| {
            log.warn("Failed to spawn bear {d}: {s}", .{ bears_spawned, @errorName(err) });
        };
    }
    log.info("Bears Awakened: {d}", .{config.num_bears});
    log.info("All initial entities spawned.", .{});
    log.info("Entity noise generators deinitialized by defer.", .{});
}
