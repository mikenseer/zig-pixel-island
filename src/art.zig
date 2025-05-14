// src/art.zig
// Defines pixel data for game assets.
const types_module = @import("types.zig");
const config_module = @import("config.zig");
const ray = @import("raylib");
const math = @import("std").math;

const PixelColor = types_module.PixelColor;
const N = null; // Transparent

// ... (Peon, Sheep, Bear, Tree art definitions remain the same) ...
pub const peon_art_width: c_int = 1;
pub const peon_art_height: c_int = config_module.player_height_pixels;
pub const peon_pixels: [peon_art_height][peon_art_width]?PixelColor = .{
    .{config_module.player_pixel_1_color},
    .{config_module.player_pixel_2_color},
};
pub const sheep_art_width: c_int = 3;
pub const sheep_art_height: c_int = 2;
const SHEEP_WHITE = ray.Color.white;
const SHEEP_HEAD = ray.Color.dark_gray;
const SHEEP_BODY_LIGHT_GRAY = ray.Color{ .r = 200, .g = 200, .b = 200, .a = 255 };
const SHEEP_HEAD_DARK_GRAY = ray.Color{ .r = 100, .g = 100, .b = 100, .a = 255 };
pub const sheep_pixels: [sheep_art_height][sheep_art_width]?PixelColor = .{
    .{ SHEEP_HEAD, SHEEP_WHITE, SHEEP_WHITE },
    .{ SHEEP_WHITE, SHEEP_WHITE, SHEEP_WHITE },
};
pub const bear_art_width: c_int = 4;
pub const bear_art_height: c_int = 3;
const BEAR_BODY_BROWN = ray.Color{ .r = 100, .g = 70, .b = 40, .a = 255 };
const BEAR_HEAD_BROWN = ray.Color{ .r = 70, .g = 50, .b = 25, .a = 255 };
const BEAR_CORPSE_BODY_BROWN = ray.Color{ .r = 80, .g = 60, .b = 30, .a = 255 };
const BEAR_CORPSE_HEAD_BROWN = ray.Color{ .r = 60, .g = 40, .b = 20, .a = 255 };
pub const bear_pixels: [bear_art_height][bear_art_width]?PixelColor = .{
    .{ BEAR_HEAD_BROWN, BEAR_BODY_BROWN, BEAR_BODY_BROWN, BEAR_BODY_BROWN },
    .{ BEAR_BODY_BROWN, BEAR_BODY_BROWN, BEAR_BODY_BROWN, BEAR_BODY_BROWN },
    .{ BEAR_BODY_BROWN, N, N, BEAR_BODY_BROWN },
};
pub const mature_tree_art_width: c_int = 5;
pub const mature_tree_art_height: c_int = 10;
pub const mature_tree_pixels: [mature_tree_art_height][mature_tree_art_width]?PixelColor = .{
    .{ N, N, config_module.tree_leaf_color, N, N },
    .{ N, config_module.tree_leaf_color, config_module.tree_leaf_highlight_color, config_module.tree_leaf_color, N },
    .{ config_module.tree_leaf_color, config_module.tree_leaf_highlight_color, config_module.tree_leaf_highlight_color, config_module.tree_leaf_highlight_color, config_module.tree_leaf_color },
    .{ config_module.tree_leaf_color, config_module.tree_leaf_highlight_color, config_module.tree_leaf_color, config_module.tree_leaf_highlight_color, config_module.tree_leaf_color },
    .{ N, config_module.tree_leaf_color, config_module.tree_leaf_highlight_color, config_module.tree_leaf_color, N },
    .{ N, N, config_module.tree_leaf_color, N, N },
    .{ N, N, config_module.tree_trunk_color, N, N },
    .{ N, N, config_module.tree_trunk_color, N, N },
    .{ N, N, config_module.tree_trunk_color, N, N },
    .{ N, N, config_module.tree_trunk_color, N, N },
};
pub const small_tree_art_width: c_int = 3;
pub const small_tree_art_height: c_int = 7;
pub const small_tree_pixels: [small_tree_art_height][small_tree_art_width]?PixelColor = .{
    .{ N, config_module.tree_leaf_color, N },
    .{ config_module.tree_leaf_color, config_module.tree_leaf_highlight_color, config_module.tree_leaf_color },
    .{ N, config_module.tree_leaf_highlight_color, N },
    .{ N, config_module.tree_leaf_color, N },
    .{ N, config_module.tree_trunk_color, N },
    .{ N, config_module.tree_trunk_color, N },
    .{ N, config_module.tree_trunk_color, N },
};
pub const sapling_art_width: c_int = config_module.sapling_art_width;
pub const sapling_art_height: c_int = config_module.sapling_art_height;
pub const sapling_pixels: [sapling_art_height][sapling_art_width]?PixelColor = .{
    .{ N, config_module.seedling_color, N },
    .{ N, config_module.tree_leaf_color, N },
    .{ config_module.tree_leaf_color, config_module.tree_trunk_color, config_module.tree_leaf_color },
    .{ N, config_module.tree_trunk_color, N },
    .{ N, config_module.tree_trunk_color, N },
};
pub const seedling_art_width: c_int = config_module.seedling_art_width;
pub const seedling_art_height: c_int = config_module.seedling_art_height;
pub const seedling_pixels: [seedling_art_height][seedling_art_width]?PixelColor = .{
    .{config_module.seedling_color},
    .{config_module.tree_trunk_color},
};
const R_B_local = config_module.rock_body_color;
const R_H_local = config_module.rock_highlight_color;
const R_S_local = config_module.rock_shadow_color;
pub const basic_rock_cluster_pixels: [config_module.rock_cluster_art_height][config_module.rock_cluster_art_width]?PixelColor = .{
    .{ N, N, N, R_S_local, R_S_local, N },
    .{ N, N, R_S_local, R_B_local, R_H_local, R_S_local },
    .{ N, R_S_local, R_B_local, R_H_local, R_B_local, R_S_local },
    .{ R_S_local, R_B_local, R_H_local, R_B_local, R_H_local, R_S_local },
    .{ N, R_S_local, R_B_local, R_S_local, R_B_local, R_S_local },
    .{ N, N, R_S_local, R_S_local, R_S_local, N },
};
const BR_M_local = config_module.brush_color_main;
const BR_H_local = config_module.brush_color_highlight;
pub const basic_brush_pixels: [config_module.brush_art_height][config_module.brush_art_width]?PixelColor = .{
    .{ N, BR_H_local, BR_M_local, BR_H_local, N },
    .{ BR_M_local, BR_H_local, BR_M_local, BR_M_local, BR_H_local },
};

// --- Item Art ---
pub const meat_item_art_width: c_int = 1;
pub const meat_item_art_height: c_int = 1;
const MEAT_PINK = ray.Color{ .r = 255, .g = 105, .b = 180, .a = 255 };
pub const meat_item_pixels: [meat_item_art_height][meat_item_art_width]?PixelColor = .{
    .{MEAT_PINK},
};

pub const brush_resource_item_art_width: c_int = 2;
pub const brush_resource_item_art_height: c_int = 2;
pub const brush_resource_item_pixels: [brush_resource_item_art_height][brush_resource_item_art_width]?PixelColor = .{
    .{ N, BR_H_local },
    .{ BR_M_local, BR_H_local },
};

// Log Item (e.g., 3x1 pixels) - Already defined
pub const log_item_art_width: c_int = 3;
pub const log_item_art_height: c_int = 1;
const LOG_BROWN_DARK = config_module.tree_trunk_color;
const LOG_BROWN_LIGHT = ray.Color{ .r = LOG_BROWN_DARK.r + 20, .g = LOG_BROWN_DARK.g + 20, .b = LOG_BROWN_DARK.b + 20, .a = 255 };
pub const log_item_pixels: [log_item_art_height][log_item_art_width]?PixelColor = .{
    .{ LOG_BROWN_DARK, LOG_BROWN_LIGHT, LOG_BROWN_DARK },
};

// Rock Item (e.g., 2x2 pixels) - Already defined
pub const rock_item_art_width: c_int = 2;
pub const rock_item_art_height: c_int = 2;
pub const rock_item_pixels: [rock_item_art_height][rock_item_art_width]?PixelColor = .{
    .{ N, R_S_local },
    .{ R_B_local, R_H_local },
};

// Corpse Sheep Item
pub const corpse_sheep_item_art_width: c_int = sheep_art_width;
pub const corpse_sheep_item_art_height: c_int = sheep_art_height;
pub const corpse_sheep_item_pixels: [corpse_sheep_item_art_height][corpse_sheep_item_art_width]?PixelColor = .{
    .{ SHEEP_BODY_LIGHT_GRAY, SHEEP_BODY_LIGHT_GRAY, SHEEP_BODY_LIGHT_GRAY },
    .{ SHEEP_HEAD_DARK_GRAY, SHEEP_BODY_LIGHT_GRAY, SHEEP_BODY_LIGHT_GRAY },
};

// Corpse Bear Item
pub const corpse_bear_item_art_width: c_int = bear_art_width;
pub const corpse_bear_item_art_height: c_int = bear_art_height;
pub const corpse_bear_item_pixels: [corpse_bear_item_art_height][corpse_bear_item_art_width]?PixelColor = .{
    .{ BEAR_CORPSE_BODY_BROWN, N, N, BEAR_CORPSE_BODY_BROWN },
    .{ BEAR_CORPSE_BODY_BROWN, BEAR_CORPSE_BODY_BROWN, BEAR_CORPSE_BODY_BROWN, BEAR_CORPSE_BODY_BROWN },
    .{ BEAR_CORPSE_HEAD_BROWN, BEAR_CORPSE_BODY_BROWN, BEAR_CORPSE_BODY_BROWN, BEAR_CORPSE_BODY_BROWN },
};

// Grain Item Art (1x1 pixel, bright yellow)
pub const grain_item_art_width: c_int = 1;
pub const grain_item_art_height: c_int = 1;
const GRAIN_YELLOW_BRIGHT = ray.Color{ .r = 255, .g = 215, .b = 0, .a = 255 };
pub const grain_item_pixels: [grain_item_art_height][grain_item_art_width]?PixelColor = .{
    .{GRAIN_YELLOW_BRIGHT},
};

// --- UI Icons ---
// ... (UI Icons remain the same) ...
pub const speaker_icon_width: c_int = 13;
pub const speaker_icon_height: c_int = 13;
// ... (rest of art.zig, including cloud art functions and definitions) ...
const SPEAKER_W = ray.Color.white;
const SPEAKER_B = ray.Color.black;
const SPEAKER_R = ray.Color.red;

pub const speaker_unmuted_pixels: [speaker_icon_height][speaker_icon_width]?PixelColor = .{
    .{ SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W },
    .{ SPEAKER_W, N, N, N, N, N, N, N, N, N, N, N, SPEAKER_W },
    .{ SPEAKER_W, N, N, SPEAKER_B, SPEAKER_B, N, N, N, SPEAKER_B, SPEAKER_B, N, N, SPEAKER_W },
    .{ SPEAKER_W, N, SPEAKER_B, SPEAKER_W, SPEAKER_W, SPEAKER_B, SPEAKER_B, SPEAKER_B, SPEAKER_W, SPEAKER_W, SPEAKER_B, N, SPEAKER_W },
    .{ SPEAKER_W, N, SPEAKER_B, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_B, N, SPEAKER_W },
    .{ SPEAKER_W, N, SPEAKER_B, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_B, N, SPEAKER_W },
    .{ SPEAKER_W, N, SPEAKER_B, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_B, N, SPEAKER_W },
    .{ SPEAKER_W, N, SPEAKER_B, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_B, N, SPEAKER_W },
    .{ SPEAKER_W, N, SPEAKER_B, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_B, N, SPEAKER_W },
    .{ SPEAKER_W, N, SPEAKER_B, SPEAKER_W, SPEAKER_W, SPEAKER_B, SPEAKER_B, SPEAKER_B, SPEAKER_W, SPEAKER_W, SPEAKER_B, N, SPEAKER_W },
    .{ SPEAKER_W, N, N, SPEAKER_B, SPEAKER_B, N, N, N, SPEAKER_B, SPEAKER_B, N, N, SPEAKER_W },
    .{ SPEAKER_W, N, N, N, N, N, N, N, N, N, N, N, SPEAKER_W },
    .{ SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W },
};

pub const speaker_muted_pixels: [speaker_icon_height][speaker_icon_width]?PixelColor = .{
    .{ SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W },
    .{ SPEAKER_W, N, SPEAKER_R, N, N, N, N, N, N, N, SPEAKER_R, N, SPEAKER_W },
    .{ SPEAKER_W, N, N, SPEAKER_R, N, N, N, N, N, SPEAKER_R, N, N, SPEAKER_W },
    .{ SPEAKER_W, N, N, SPEAKER_B, SPEAKER_B, SPEAKER_R, N, SPEAKER_R, SPEAKER_B, SPEAKER_B, N, N, SPEAKER_W },
    .{ SPEAKER_W, N, SPEAKER_B, SPEAKER_W, SPEAKER_W, N, SPEAKER_R, N, SPEAKER_W, SPEAKER_W, SPEAKER_B, N, SPEAKER_W },
    .{ SPEAKER_W, N, SPEAKER_B, SPEAKER_W, SPEAKER_W, SPEAKER_R, N, SPEAKER_R, SPEAKER_W, SPEAKER_W, SPEAKER_B, N, SPEAKER_W },
    .{ SPEAKER_W, N, SPEAKER_B, SPEAKER_W, SPEAKER_W, N, SPEAKER_R, N, SPEAKER_W, SPEAKER_W, SPEAKER_B, N, SPEAKER_W },
    .{ SPEAKER_W, N, SPEAKER_B, SPEAKER_W, SPEAKER_W, SPEAKER_R, N, SPEAKER_R, SPEAKER_W, SPEAKER_W, SPEAKER_B, N, SPEAKER_W },
    .{ SPEAKER_W, N, N, SPEAKER_B, SPEAKER_B, N, SPEAKER_R, N, SPEAKER_B, SPEAKER_B, N, N, SPEAKER_W },
    .{ SPEAKER_W, N, N, N, SPEAKER_R, N, N, N, N, N, SPEAKER_R, N, SPEAKER_W },
    .{ SPEAKER_W, N, SPEAKER_R, N, N, N, N, N, N, N, SPEAKER_R, N, SPEAKER_W },
    .{ SPEAKER_W, N, N, N, N, N, N, N, N, N, N, N, SPEAKER_W },
    .{ SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W, SPEAKER_W },
};

const CLOUD_BASE_COLOR = ray.Color{ .r = 220, .g = 225, .b = 230, .a = 255 };
const CLOUD_HIGHLIGHT_COLOR = ray.Color{ .r = 250, .g = 250, .b = 255, .a = 255 };
const CLOUD_SHADOW_COLOR = ray.Color{ .r = 180, .g = 185, .b = 190, .a = 255 };
const MAX_CLOUD_ALPHA: u8 = 170;
const MIN_CLOUD_ALPHA: u8 = 25;

fn comptime_rand(seed: *u32) u32 {
    seed.* = (seed.* *% 1664525 +% 1013904223);
    return seed.*;
}

fn comptime_value_noise(fx: f32, fy: f32, seed_offset: u32) f32 {
    const ix: i32 = @intFromFloat(math.floor(fx));
    const iy: i32 = @intFromFloat(math.floor(fy));
    const frac_x = fx - @as(f32, @floatFromInt(ix));
    const frac_y = fy - @as(f32, @floatFromInt(iy));
    const s_base: u32 = seed_offset;
    var s00_seed = s_base +% @as(u32, @intCast(ix)) +% (@as(u32, @intCast(iy)) *% 313);
    const n00 = @as(f32, @floatFromInt(comptime_rand(&s00_seed) % 256)) / 255.0;
    var s10_seed = s_base +% @as(u32, @intCast(ix + 1)) +% (@as(u32, @intCast(iy)) *% 313);
    const n10 = @as(f32, @floatFromInt(comptime_rand(&s10_seed) % 256)) / 255.0;
    var s01_seed = s_base +% @as(u32, @intCast(ix)) +% (@as(u32, @intCast(iy + 1)) *% 313);
    const n01 = @as(f32, @floatFromInt(comptime_rand(&s01_seed) % 256)) / 255.0;
    var s11_seed = s_base +% @as(u32, @intCast(ix + 1)) +% (@as(u32, @intCast(iy + 1)) *% 313);
    const n11 = @as(f32, @floatFromInt(comptime_rand(&s11_seed) % 256)) / 255.0;

    const wx = frac_x * frac_x * (3.0 - 2.0 * frac_x);
    const wy = frac_y * frac_y * (3.0 - 2.0 * frac_y);

    const ix0 = n00 * (1.0 - wx) + n10 * wx;
    const ix1 = n01 * (1.0 - wx) + n11 * wx;
    return ix0 * (1.0 - wy) + ix1 * wy;
}

fn comptime_fbm(fx: f32, fy: f32, octaves: u32, persistence: f32, lacunarity: f32, initial_seed: u32) f32 {
    var total: f32 = 0.0;
    var frequency: f32 = 1.0;
    var amplitude: f32 = 1.0;
    var max_value: f32 = 0.0;
    var current_seed = initial_seed;
    const effective_octaves = if (octaves == 0) 1 else octaves;

    for (0..effective_octaves) |_| {
        total += comptime_value_noise(fx * frequency, fy * frequency, current_seed + @as(u32, @intFromFloat(frequency * 100.0))) * amplitude;
        current_seed +%= (123 + @as(u32, @intFromFloat(frequency * 10)));
        max_value += amplitude;
        amplitude *= persistence;
        frequency *= lacunarity;
    }

    if (max_value == 0) return 0.0;
    return math.clamp(total / max_value, 0.0, 1.0);
}

fn generateProceduralCloud(
    comptime width: c_int,
    comptime height: c_int,
    comptime seed: u32,
    comptime base_noise_scale: f32,
    comptime edge_noise_scale: f32,
    comptime shape_distort_scale: f32,
    comptime shape_distort_strength: f32,
    comptime octaves: u32,
    comptime density_power: f32,
    comptime falloff_power: f32,
    comptime edge_strength: f32,
) [height][width]?PixelColor {
    @setEvalBranchQuota(width * height * octaves * 300 + 200000);
    var pixels: [height][width]?PixelColor = undefined;
    const center_x: f32 = @as(f32, @floatFromInt(width)) / 2.0;
    const center_y: f32 = @as(f32, @floatFromInt(height)) / 2.0;

    for (0..height) |y_idx| {
        const y_cint: c_int = @intCast(y_idx);
        for (0..width) |x_idx| {
            const x_cint: c_int = @intCast(x_idx);

            const x_offset_noise = (comptime_fbm(@as(f32, @floatFromInt(x_cint)) * shape_distort_scale, @as(f32, @floatFromInt(y_cint)) * shape_distort_scale, 2, 0.45, 2.1, seed + 3000) * 2.0 - 1.0);
            const y_offset_noise = (comptime_fbm(@as(f32, @floatFromInt(x_cint)) * shape_distort_scale, @as(f32, @floatFromInt(y_cint)) * shape_distort_scale, 2, 0.45, 2.1, seed + 4000) * 2.0 - 1.0);

            const dx = (@as(f32, @floatFromInt(x_cint)) + x_offset_noise * shape_distort_strength * center_x * 0.7) - center_x;
            const dy = (@as(f32, @floatFromInt(y_cint)) + y_offset_noise * shape_distort_strength * center_y * 0.5) - center_y;

            const elliptical_dist_sq = math.pow(f32, dx / center_x, 2) + math.pow(f32, dy / (center_y * 0.7), 2);
            const base_mask: f32 = math.clamp(1.0 - math.pow(f32, math.clamp(elliptical_dist_sq, 0.0, 1.0), falloff_power), 0.0, 1.0);

            const density_noise = comptime_fbm(@as(f32, @floatFromInt(x_cint)) * base_noise_scale, @as(f32, @floatFromInt(y_cint)) * base_noise_scale, octaves, 0.5, 2.0, seed);
            const edge_noise = comptime_fbm(@as(f32, @floatFromInt(x_cint)) * edge_noise_scale, @as(f32, @floatFromInt(y_cint)) * edge_noise_scale, @max(1, octaves - 1), 0.55, 2.1, seed + 777);

            var final_density = base_mask * math.pow(f32, density_noise, density_power);
            final_density = final_density * (1.0 - (edge_noise * edge_strength));
            final_density = math.clamp(final_density, 0.0, 1.0);

            const visibility_threshold: f32 = 0.18;

            if (final_density > visibility_threshold) {
                const alpha_factor = (final_density - visibility_threshold) / (1.0 - visibility_threshold);
                var alpha_val_f: f32 = @as(f32, @floatFromInt(MIN_CLOUD_ALPHA)) + (@as(f32, @floatFromInt(MAX_CLOUD_ALPHA - MIN_CLOUD_ALPHA)) * math.pow(f32, alpha_factor, 0.65));
                alpha_val_f = math.clamp(alpha_val_f, 0.0, @as(f32, @floatFromInt(MAX_CLOUD_ALPHA)));
                const alpha_val = @as(u8, @intFromFloat(alpha_val_f));

                if (alpha_val > MIN_CLOUD_ALPHA / 3) {
                    var color = CLOUD_BASE_COLOR;
                    if (density_noise > 0.65) {
                        color = CLOUD_HIGHLIGHT_COLOR;
                    } else if (density_noise < 0.45) {
                        color = CLOUD_SHADOW_COLOR;
                    }
                    pixels[y_idx][x_idx] = ray.Color{ .r = color.r, .g = color.g, .b = color.b, .a = alpha_val };
                } else {
                    pixels[y_idx][x_idx] = N;
                }
            } else {
                pixels[y_idx][x_idx] = N;
            }
        }
    }
    return pixels;
}

pub const cloud_small_height: c_int = 30;
pub const cloud_small_width: c_int = 100;
pub const cloud_small_pixels = blk: {
    @setEvalBranchQuota(7_000_000);
    break :blk generateProceduralCloud(cloud_small_width, cloud_small_height, 123, 0.05, 0.1, 0.07, 0.3, 3, 1.0, 0.8, 0.3);
};

pub const cloud_medium_height: c_int = 50;
pub const cloud_medium_width: c_int = 160;
pub const cloud_medium_pixels = blk: {
    @setEvalBranchQuota(15_000_000);
    break :blk generateProceduralCloud(cloud_medium_width, cloud_medium_height, 456, 0.03, 0.08, 0.06, 0.35, 4, 1.1, 1.0, 0.4);
};

pub const cloud_large_height: c_int = 70;
pub const cloud_large_width: c_int = 240;
pub const cloud_large_pixels = blk: {
    @setEvalBranchQuota(30_000_000);
    break :blk generateProceduralCloud(cloud_large_width, cloud_large_height, 789, 0.022, 0.06, 0.04, 0.4, 4, 1.2, 1.2, 0.5);
};
