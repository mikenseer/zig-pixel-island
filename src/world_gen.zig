// src/world_gen.zig
// Handles procedural generation of the game world's terrain and elevation.
const std_full = @import("std");
const types = @import("types.zig");
const config = @import("config.zig");
const noise_utils = @import("noise_utils.zig");
const math = std_full.math;

const RandomInterface = std_full.Random;
const log = std_full.log;

// Assigns a terrain type to a tile based on its normalized elevation.
fn assignTerrainBasedOnElevation(world: *types.GameWorld, x: u32, y: u32, normalized_elevation: f32) void {
    if (world.getTileMutable(@as(i32, @intCast(x)), @as(i32, @intCast(y)))) |tile| {
        if (normalized_elevation < config.very_deep_water_elevation_threshold) {
            tile.base_terrain = .VeryDeepWater;
        } else if (normalized_elevation < config.deep_water_elevation_threshold) {
            tile.base_terrain = .DeepWater;
        } else if (normalized_elevation < config.shallow_water_elevation_threshold) {
            tile.base_terrain = .ShallowWater;
        } else if (normalized_elevation < config.sand_elevation_threshold) {
            tile.base_terrain = .Sand;
        } else if (normalized_elevation < config.grass_elevation_threshold) {
            tile.base_terrain = .Grass;
        } else if (normalized_elevation < config.plains_elevation_threshold) {
            tile.base_terrain = .Plains;
        } else {
            tile.base_terrain = .Mountain;
        }
    }
}

// Generates the island's terrain and elevation.
pub fn generateSimpleIsland(world: *types.GameWorld, seed: u64) void {
    log.info("Generating island terrain. Seed: {d}", .{seed});

    var island_prng = std_full.Random.DefaultPrng.init(seed);
    var island_random_iface = island_prng.random();

    const island_center_x: f32 = @as(f32, @floatFromInt(world.width)) / 2.0;
    const island_center_y: f32 = @as(f32, @floatFromInt(world.height)) / 2.0;

    // MODIFIED: Reduced base_radius_factor for a smaller island
    const base_max_radius: f32 = @min(island_center_x, island_center_y) * config.island_base_radius_factor;

    // --- Noise Grid Cell Sizes (from config) ---
    // MODIFIED: Potentially adjusted grid_cell_size_coarse_shape for more coastal detail
    const grid_cell_size_coarse: u32 = config.grid_cell_size_coarse_shape;
    const grid_cell_size_land_elev: u32 = config.grid_cell_size_land_elev;
    const grid_cell_size_fine_detail: u32 = config.grid_cell_size_fine_detail;

    var coarse_shape_noise = noise_utils.NoiseGenerator.init(island_random_iface.int(u64), world.allocator, grid_cell_size_coarse, world.width, world.height);
    defer coarse_shape_noise.deinit();
    var land_elev_noise = noise_utils.NoiseGenerator.init(island_random_iface.int(u64), world.allocator, grid_cell_size_land_elev, world.width, world.height);
    defer land_elev_noise.deinit();
    var fine_detail_noise = noise_utils.NoiseGenerator.init(island_random_iface.int(u64), world.allocator, grid_cell_size_fine_detail, world.width, world.height);
    defer fine_detail_noise.deinit();

    std_full.debug.assert(world.elevation_data.len == world.width * world.height);

    // --- Noise Parameters for Terrain Generation (from config) ---
    const shape_octaves: u32 = config.shape_octaves;
    const shape_persistence: f32 = config.shape_persistence;
    const shape_lacunarity: f32 = config.shape_lacunarity;
    // MODIFIED: Potentially increased shape_distortion_strength for more coastal variety
    const shape_distortion_strength: f32 = config.shape_distortion_strength;

    const land_elev_octaves: u32 = config.land_elev_octaves;
    const land_elev_persistence: f32 = config.land_elev_persistence;
    const land_elev_lacunarity: f32 = config.land_elev_lacunarity;

    const fine_detail_octaves: u32 = config.fine_detail_octaves;
    const fine_detail_persistence: f32 = config.fine_detail_persistence;
    const fine_detail_lacunarity: f32 = config.fine_detail_lacunarity;
    const fine_detail_strength: f32 = config.fine_detail_strength;

    log.info("Generating elevation map...", .{});
    for (0..world.height) |y_usize| {
        for (0..world.width) |x_usize| {
            const x_f = @as(f32, @floatFromInt(x_usize));
            const y_f = @as(f32, @floatFromInt(y_usize));
            const current_idx = y_usize * world.width + x_usize;

            const shape_distortion_noise_raw = coarse_shape_noise.fbm(x_f, y_f, shape_octaves, shape_persistence, shape_lacunarity);
            const effective_max_dist = base_max_radius * (1.0 + shape_distortion_noise_raw * shape_distortion_strength);

            const dx = x_f - island_center_x;
            const dy = y_f - island_center_y;
            const dist_from_center = math.sqrt(dx * dx + dy * dy);

            // MODIFIED: Using config.island_falloff_exponent for steeper falloff
            var radial_mask: f32 = 1.0 - math.pow(f32, dist_from_center / @max(1.0, effective_max_dist), config.island_falloff_exponent); // Ensure effective_max_dist is not zero
            radial_mask = math.clamp(radial_mask, 0.0, 1.0);

            const primary_elevation_raw = land_elev_noise.fbm(x_f, y_f, land_elev_octaves, land_elev_persistence, land_elev_lacunarity);
            const primary_elevation = (primary_elevation_raw + 1.0) / 2.0;
            var elevation_with_mask = primary_elevation * radial_mask;

            if (radial_mask > 0.01) {
                const fine_detail_raw = fine_detail_noise.fbm(x_f, y_f, fine_detail_octaves, fine_detail_persistence, fine_detail_lacunarity);
                elevation_with_mask += fine_detail_raw * fine_detail_strength * radial_mask * 0.5;
            }

            elevation_with_mask = math.clamp(elevation_with_mask, 0.0, 1.0);
            const power_curve_exponent: f32 = config.elevation_power_curve_exponent;
            elevation_with_mask = math.pow(f32, elevation_with_mask, power_curve_exponent);
            const global_uplift_amount: f32 = config.global_uplift_amount;
            elevation_with_mask = elevation_with_mask * (1.0 - global_uplift_amount) + global_uplift_amount;
            world.elevation_data[current_idx] = math.clamp(elevation_with_mask, 0.0, 1.0);
        }
    }
    log.info("Elevation map generated.", .{});

    log.info("Quantizing elevation and assigning terrain...", .{});
    const num_elevation_levels: u32 = config.num_quantized_elevation_levels;
    const denominator = @as(f32, @floatFromInt(num_elevation_levels - 1));
    for (world.elevation_data) |*elev| {
        elev.* = math.round(elev.* * denominator) / denominator;
        elev.* = math.clamp(elev.*, 0.0, 1.0);
    }

    for (0..world.height) |y_usize_terrain| {
        for (0..world.width) |x_usize_terrain| {
            const elevation = world.elevation_data[y_usize_terrain * world.width + x_usize_terrain];
            assignTerrainBasedOnElevation(world, @as(u32, @intCast(x_usize_terrain)), @as(u32, @intCast(y_usize_terrain)), elevation);
        }
    }
    log.info("Terrain assignment complete.", .{});
    log.info("Island terrain generation finished.", .{});
}
