// src/config.zig
// Contains global configurations for the game.

const types = @import("types.zig");
const ray = @import("raylib");

pub const screen_width: c_int = 500;
pub const screen_height: c_int = 500;

// Terrain Colors
pub const very_deep_water_color: ray.Color = .{ .r = 0, .g = 50, .b = 130, .a = 255 };
pub const deep_water_color: ray.Color = .{ .r = 0, .g = 80, .b = 170, .a = 255 };
pub const shallow_water_color: ray.Color = .{ .r = 70, .g = 130, .b = 180, .a = 255 };
pub const sand_color: ray.Color = .{ .r = 244, .g = 164, .b = 96, .a = 255 };
pub const grass_color: ray.Color = .{ .r = 34, .g = 139, .b = 34, .a = 255 };
pub const plains_color: ray.Color = .{ .r = 138, .g = 154, .b = 91, .a = 255 };
pub const mountain_color: ray.Color = .{ .r = 139, .g = 137, .b = 137, .a = 255 };
pub const rock_terrain_color: ray.Color = .{ .r = 105, .g = 105, .b = 105, .a = 255 };
pub const dirt_path_color: ray.Color = .{ .r = 139, .g = 101, .b = 72, .a = 200 };
pub const cobblestone_road_color: ray.Color = .{ .r = 160, .g = 160, .b = 160, .a = 255 };

// Rock Entity Colors
pub const rock_body_color: ray.Color = .{ .r = 115, .g = 115, .b = 115, .a = 255 };
pub const rock_highlight_color: ray.Color = .{ .r = 130, .g = 130, .b = 130, .a = 255 };
pub const rock_shadow_color: ray.Color = .{ .r = 80, .g = 80, .b = 80, .a = 255 };

// Entity Colors
pub const player_pixel_1_color: ray.Color = .{ .r = 255, .g = 0, .b = 0, .a = 255 };
pub const player_pixel_2_color: ray.Color = .{ .r = 200, .g = 0, .b = 0, .a = 255 };

pub const tree_leaf_color: ray.Color = .{ .r = 0, .g = 100, .b = 0, .a = 255 };
pub const tree_leaf_highlight_color: ray.Color = .{ .r = 0, .g = 120, .b = 0, .a = 255 };
pub const tree_trunk_color: ray.Color = .{ .r = 139, .g = 69, .b = 19, .a = 255 };
pub const seedling_color: ray.Color = .{ .r = 60, .g = 150, .b = 60, .a = 255 };

pub const brush_color_main: ray.Color = .{ .r = 180, .g = 160, .b = 40, .a = 255 };
pub const brush_color_highlight: ray.Color = .{ .r = 210, .g = 190, .b = 90, .a = 255 };

// --- UI Specific Colors & Styles ---
pub const static_selection_outline_color: ray.Color = ray.Color.white;
pub const ai_selection_outline_color: ray.Color = ray.Color.lime;
pub const ui_panel_background_color: ray.Color = .{ .r = 20, .g = 20, .b = 20, .a = 210 };
pub const ui_panel_text_color: ray.Color = ray.Color.white;
pub const ui_panel_padding: c_int = 8;
pub const ui_panel_line_spacing: c_int = 14;
pub const ui_panel_font_size: c_int = 10;
pub const ui_panel_stat_value_color: ray.Color = ray.Color.gold;
pub const ui_panel_mouse_offset_x: c_int = 15;
pub const ui_panel_mouse_offset_y: c_int = 10;

// --- Cloud Entity Settings ---
pub const num_small_clouds: u32 = 10;
pub const num_medium_clouds: u32 = 7;
pub const num_large_clouds: u32 = 4;
pub const cloud_min_speed_x: f32 = 0.1;
pub const cloud_max_speed_x: f32 = 0.5;
pub const cloud_render_height_threshold_normalized: f32 = 800.0 / 1024.0;
pub const cloud_offscreen_buffer: i32 = 60;

pub const background_clear_color: ray.Color = .{ .r = 0, .g = 0, .b = 0, .a = 255 };

// Game specific constants
pub const player_height_pixels: u32 = 2;
pub const peon_move_interval: u32 = 10;
pub const num_initial_peons: u32 = 100;

// --- Animal Settings ---
pub const num_sheep: u32 = 100;
pub const num_bears: u32 = 10;
pub const sheep_hp: i16 = 10;
pub const bear_hp: i16 = 50;
pub const peon_initial_hp: i16 = 100;
pub const brush_initial_hp: i16 = 10;

pub const animal_move_interval_base: u32 = 15;
pub const peon_shallows_speed_modifier: f32 = 0.5;
pub const bear_deep_water_speed_modifier: f32 = 0.5;
pub const sheep_move_attempt_chance: f32 = 0.8;
pub const bear_move_attempt_chance: f32 = 0.4;

pub const min_wander_steps: u8 = 1;
pub const max_wander_steps: u8 = 10;

// --- Island Shape & Terrain Generation ---
pub const island_base_radius_factor: f32 = 0.68;
pub const island_falloff_exponent: f32 = 2.5;
pub const elevation_power_curve_exponent: f32 = 0.75;
pub const global_uplift_amount: f32 = 0.1;
pub const num_quantized_elevation_levels: u32 = 1025;

// --- Terrain Elevation Thresholds (Normalized 0.0 to 1.0) ---
pub const very_deep_water_elevation_threshold: f32 = 0.1;
pub const deep_water_elevation_threshold: f32 = 0.18;
pub const shallow_water_elevation_threshold: f32 = 0.24;
pub const sand_elevation_threshold: f32 = 0.32;
pub const grass_elevation_threshold: f32 = 0.55;
pub const plains_elevation_threshold: f32 = 0.69;

// --- Noise Grid Cell Sizes (for world_gen & entity_spawner) ---
pub const grid_cell_size_coarse_shape: u32 = 64;
pub const grid_cell_size_land_elev: u32 = 32;
pub const grid_cell_size_fine_detail: u32 = 16;
pub const grid_cell_size_forest_core: u32 = 72;
pub const grid_cell_size_deforestation: u32 = 80;
pub const grid_cell_size_rock: u32 = 56;
pub const grid_cell_size_brush: u32 = 40;

// --- Noise Parameters ---
pub const shape_octaves: u32 = 4;
pub const shape_persistence: f32 = 0.45;
pub const shape_lacunarity: f32 = 2.0;
pub const shape_distortion_strength: f32 = 0.75;
pub const land_elev_octaves: u32 = 5;
pub const land_elev_persistence: f32 = 0.5;
pub const land_elev_lacunarity: f32 = 2.0;
pub const fine_detail_octaves: u32 = 3;
pub const fine_detail_persistence: f32 = 0.4;
pub const fine_detail_lacunarity: f32 = 2.0;
pub const fine_detail_strength: f32 = 0.1;
pub const forest_core_octaves: u32 = 2;
pub const forest_core_persistence: f32 = 0.50;
pub const forest_core_lacunarity: f32 = 1.9;
pub const forest_core_processing_power: f32 = 1.05;
pub const deforestation_octaves: u32 = 3;
pub const deforestation_persistence: f32 = 0.50;
pub const deforestation_lacunarity: f32 = 2.0;
pub const deforestation_processing_power: f32 = 1.2;
pub const rock_octaves: u32 = 2;
pub const rock_persistence: f32 = 0.45;
pub const rock_lacunarity: f32 = 2.0;
pub const brush_octaves: u32 = 3;
pub const brush_persistence: f32 = 0.5;
pub const brush_lacunarity: f32 = 2.0;
pub const brush_deforestation_power_factor: f32 = 0.7;

// --- Entity Spawning Probabilities & Thresholds ---
pub const grass_tree_base_probability: f32 = 0.45;
pub const tree_density_threshold: f32 = 0.08;
pub const tree_spawn_density_power: f32 = 1.05;
pub const max_tree_spawn_density_cap: f32 = 0.30;
pub const tree_age_noise_offset: f32 = 0.05;
pub const tree_age_random_spread: f32 = 1.0;
pub const tree_age_range_radius: f32 = 0.4;
pub const plains_tree_base_probability: f32 = 0.004;
pub const plains_tree_core_threshold: f32 = 0.50;
pub const mountain_rock_probability: f32 = 0.0;
pub const mountain_rock_noise_thresh: f32 = 0.99;
pub const plains_upper_edge_factor: f32 = 0.07;
pub const upper_plains_rock_probability: f32 = 0.04;
pub const upper_plains_rock_noise_thresh: f32 = 0.55;
pub const mid_plains_rock_probability: f32 = 0.025;
pub const mid_plains_rock_noise_thresh: f32 = 0.55;
pub const grass_rock_probability: f32 = 0.01;
pub const grass_rock_noise_thresh: f32 = 0.58;
pub const sand_rock_probability: f32 = 0.005;
pub const sand_rock_noise_thresh: f32 = 0.60;
pub const shallow_water_rock_probability: f32 = 0.001;
pub const shallow_water_rock_noise_thresh: f32 = 0.66;
pub const plains_brush_probability: f32 = 0.20;
pub const plains_brush_noise_thresh: f32 = 0.45;
pub const plains_near_sand_brush_noise_thresh: f32 = 0.70;
pub const grass_brush_probability: f32 = 0.12;
pub const grass_brush_noise_thresh: f32 = 0.58;
pub const grass_near_sand_brush_noise_thresh: f32 = 0.85;
pub const plains_brush_sand_transition_factor: f32 = 0.045;
pub const grass_brush_sand_transition_factor: f32 = 0.035;
pub const brush_sand_transition_prob_multiplier: f32 = 0.1;
pub const sand_brush_probability: f32 = 0.03;
pub const sand_brush_noise_thresh: f32 = 0.78;
pub const coastal_grass_brush_max_dist_to_sand: u32 = 2;
pub const coastal_grass_brush_probability: f32 = 0.55;
pub const coastal_grass_brush_noise_thresh: f32 = 0.45;

// --- Static Entity Art Dimensions ---
pub const rock_cluster_art_width = 6;
pub const rock_cluster_art_height = 6;
pub const brush_art_width = 5;
pub const brush_art_height = 2;

// --- Tree Growth Settings ---
pub const max_growth_stage_tree: u8 = 3;
pub const tree_growth_interval: u16 = 600;
pub const seedling_art_width = 1;
pub const seedling_art_height = 2;
pub const sapling_art_width = 3;
pub const sapling_art_height = 5;

// --- Entity HP & Other ---
pub const default_tree_hp: i16 = 100;
pub const default_rock_cluster_hp: i16 = 150;
pub const entity_offscreen_buffer: i32 = 64;

// --- AI, Combat, Item, and Hunger Constants ---
pub const hp_decay_interval: u16 = 300;
pub const hp_decay_amount_peon: i16 = 1;
pub const hp_decay_amount_animal: i16 = 2;
pub const peon_hunger_threshold_percent: f32 = 0.50;
pub const animal_hunger_threshold_percent: f32 = 0.60;
pub const eating_duration_ticks: u16 = 60;
pub const attack_cooldown_ticks: u16 = 60;
pub const max_carry_slots: usize = 2;
pub const max_item_stack_size: u8 = 1;
pub const meat_initial_hp: i16 = 100;
pub const meat_decay_rate_ticks: u16 = 120;
pub const corpse_initial_hp: i16 = 50;
pub const corpse_decay_rate_ticks: u16 = 180;
pub const brush_resource_initial_hp: i16 = 20;
pub const brush_resource_decay_rate_ticks: u16 = 600;
pub const log_initial_hp: i16 = 200;
pub const log_decay_rate_ticks: u16 = 1200;
pub const rock_item_initial_hp: i16 = 1000;
// CORRECTED: Changed type from u16 to u32 for rock_item_decay_rate_ticks
pub const rock_item_decay_rate_ticks: u32 = 72000; // Effectively infinite for now

// HP Gains from Food
pub const meat_hp_gain_peon: i16 = 50;
pub const meat_hp_gain_bear: i16 = 20;
pub const brush_hp_gain_sheep: i16 = 30;

// Combat Damage
pub const peon_damage_vs_sheep: i16 = 3;
pub const peon_damage_vs_bear: i16 = 5;
pub const bear_damage_vs_peon: i16 = 20;
pub const bear_damage_vs_sheep: i16 = 10;

// Item Drop Quantities
pub const meat_drops_from_sheep: u8 = 4;
pub const meat_drops_from_bear: u8 = 8;

// AI Sensing Radii (in tiles/pixels)
pub const peon_food_sight_radius: f32 = 15.0;
pub const peon_hunt_sight_radius: f32 = 20.0;
pub const animal_food_sight_radius: f32 = 15.0;
pub const animal_threat_sight_radius: f32 = 12.0;
