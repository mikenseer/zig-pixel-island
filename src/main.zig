// src/main.zig
// Main application entry point, game loop, input handling.
const std_full = @import("std");

const time = std_full.time;
const heap = std_full.heap;
const log = std_full.log;
const mem = std_full.mem;
const fmt = std_full.fmt;
const math = std_full.math;
const ArrayList = std_full.ArrayList;

const DefaultPrng = std_full.Random.DefaultPrng;
const RandomInterface = std_full.Random;

const ray = @import("raylib");

// Project modules
const config = @import("config.zig");
const types = @import("types.zig");
const world_gen = @import("world_gen.zig");
const entity_spawner = @import("entity_spawner.zig");
const weather = @import("weather.zig");
const rendering = @import("rendering.zig");
const peon_ai = @import("peon_ai.zig");
const ui = @import("ui.zig");
const atlas_manager = @import("atlas_manager.zig");
const animal_ai = @import("animal_ai.zig");

// --- Game State ---
var gpa = heap.GeneralPurposeAllocator(.{}){};
var game_prng_instance: DefaultPrng = undefined;
var game_prng_iface: RandomInterface = undefined;
var world: types.GameWorld = undefined;
var atlas_manager_instance: ?atlas_manager.AtlasManager = null;
var drawable_entity_list: ArrayList(rendering.DrawableEntity) = undefined;
var ziggy_logo_texture: ?ray.Texture2D = null;

// --- Camera & Input ---
var camera = ray.Camera2D{
    .offset = .{ .x = 0.0, .y = 0.0 },
    .target = .{ .x = 0.0, .y = 0.0 },
    .rotation = 0.0,
    .zoom = 1.0,
};
const min_zoom: f32 = 1.0;
const max_zoom: f32 = @min(@as(f32, @floatFromInt(config.screen_width)), @as(f32, @floatFromInt(config.screen_height)));
const zoom_speed_factor: f32 = 0.1;
var hovered_entity_idx: ?usize = null;

// --- Rendering ---
var static_world_texture: ray.RenderTexture2D = undefined;
var static_world_needs_redraw: bool = true;

// --- Resources ---
var collected_wood: u32 = 0;
var collected_rocks: u32 = 0;
var collected_brush_items: u32 = 0;

// --- Audio ---
var ogg_file_data: []u8 = undefined;
var ogg_wave_info: ray.Wave = undefined;
var background_audio_stream: ray.AudioStream = undefined;
var audio_stream_loaded: bool = false;
var audio_stream_cursor: u64 = 0;
var is_music_muted: bool = false;
var music_volume: f32 = 1.0;

// --- Timing ---
var peon_move_timer: u32 = 0;
var animal_move_timer: u32 = 0;

// --- Loading Screen ---
var current_loading_status_buffer: [100]u8 = undefined;

fn audioStreamCallback(buffer_ptr: ?*anyopaque, frames_to_process: c_uint) callconv(.C) void {
    const buffer: [*]i16 = if (buffer_ptr) |ptr| @as([*]i16, @alignCast(@ptrCast(ptr))) else return;
    const samples_to_process = frames_to_process * @as(c_uint, ogg_wave_info.channels);
    var samples_processed: c_uint = 0;

    while (samples_processed < samples_to_process) {
        const total_ogg_samples = @as(u64, ogg_wave_info.frameCount) * @as(u64, ogg_wave_info.channels);
        const remaining_samples_in_ogg = total_ogg_samples - audio_stream_cursor;
        const samples_to_copy_u64 = @min(@as(u64, samples_to_process - samples_processed), remaining_samples_in_ogg);
        const samples_to_copy: c_uint = @truncate(samples_to_copy_u64);

        if (samples_to_copy > 0) {
            const src_ptr: [*]const i16 = @as([*]const i16, @alignCast(@ptrCast(ogg_wave_info.data))) + audio_stream_cursor;
            const dst_ptr = buffer + samples_processed;
            std_full.mem.copyForwards(i16, dst_ptr[0..samples_to_copy], src_ptr[0..samples_to_copy]);
            audio_stream_cursor += samples_to_copy;
            samples_processed += samples_to_copy;
        }

        if (audio_stream_cursor >= total_ogg_samples) {
            audio_stream_cursor = 0;
        }

        if (samples_to_copy == 0 and samples_processed < samples_to_process) {
            const remaining_buffer_samples = samples_to_process - samples_processed;
            const dst_ptr = buffer + samples_processed;
            @memset(dst_ptr[0..remaining_buffer_samples], @as(i16, 0));
            samples_processed += remaining_buffer_samples;
        }
    }
}

fn drawCurrentLoadingScreen(status_text_slice: [:0]const u8) void {
    if (ray.isWindowReady()) {
        ray.beginDrawing();
        defer ray.endDrawing();
        ray.clearBackground(ray.Color.black);

        var current_y_pos: c_int = @divTrunc(config.screen_height, 2) - 125;

        if (ziggy_logo_texture) |logo_tex| {
            const logo_w: c_int = logo_tex.width;
            const logo_h: c_int = logo_tex.height;
            const logo_x = @divTrunc(config.screen_width - logo_w, 2);
            ray.drawTexture(logo_tex, logo_x, current_y_pos, ray.Color.white);
            current_y_pos += logo_h + 15;
        } else {
            const logo_text_fallback = "ZIGGY";
            const logo_font_size_fallback: c_int = 50;
            const logo_text_width_fallback = ray.measureText(logo_text_fallback, logo_font_size_fallback);
            ray.drawText(logo_text_fallback, @divTrunc((config.screen_width - logo_text_width_fallback), 2), current_y_pos, logo_font_size_fallback, ray.Color.gold);
            current_y_pos += logo_font_size_fallback + 15;
        }

        const title_text = "PIXEL ISLAND";
        const title_font_size: c_int = 25;
        const title_text_width = ray.measureText(title_text, title_font_size);
        ray.drawText(title_text, @divTrunc((config.screen_width - title_text_width), 2), current_y_pos, title_font_size, ray.Color.white);
        current_y_pos += title_font_size + 20;

        const status_font_size: c_int = 18;
        const status_text_width = ray.measureText(status_text_slice, status_font_size);
        ray.drawText(status_text_slice, @divTrunc((config.screen_width - status_text_width), 2), current_y_pos, status_font_size, ray.Color.light_gray);
    }
}

fn updateAndDrawLoadingStatus(comptime status_fmt: []const u8, args: anytype) void {
    @memset(current_loading_status_buffer[0..], @as(u8, 0));
    const status_text_slice = fmt.bufPrintZ(&current_loading_status_buffer, status_fmt, args) catch |err| {
        log.err("Failed to format loading status: {s}", .{@errorName(err)});
        const fallback_msg = "Error formatting status...";
        var temp_fallback_buffer: [100]u8 = undefined;
        const fallback_slice_for_raylib = fmt.bufPrintZ(&temp_fallback_buffer, "{s}", .{fallback_msg}) catch fallback_msg[0..];
        drawCurrentLoadingScreen(fallback_slice_for_raylib);
        return;
    };
    drawCurrentLoadingScreen(status_text_slice);
}

// Initializes all game systems.
fn initGame(allocator: std_full.mem.Allocator) !void {
    updateAndDrawLoadingStatus("Loading Audio...", .{});
    ogg_file_data = ray.loadFileData("audio/zigisland.ogg") catch |err| {
        log.err("Failed to load OGG file data ('audio/zigisland.ogg'): {s}", .{@errorName(err)});
        return err;
    };
    errdefer ray.unloadFileData(ogg_file_data);

    ogg_wave_info = ray.loadWaveFromMemory(".ogg", ogg_file_data) catch |err| {
        log.err("Failed to load wave info from OGG data: {s}", .{@errorName(err)});
        return err;
    };
    errdefer ray.unloadWave(ogg_wave_info);

    background_audio_stream = try ray.loadAudioStream(ogg_wave_info.sampleRate, ogg_wave_info.sampleSize, ogg_wave_info.channels);
    audio_stream_loaded = true;
    errdefer { // Wrapped in a block for clarity with the conditional
        if (audio_stream_loaded) {
            ray.unloadAudioStream(background_audio_stream);
        }
    }

    ray.setAudioStreamCallback(background_audio_stream, audioStreamCallback);
    ray.playAudioStream(background_audio_stream);
    ray.setAudioStreamVolume(background_audio_stream, if (is_music_muted) 0.0 else music_volume);
    log.info("Audio Initialized.", .{});

    updateAndDrawLoadingStatus("Setting up Game Systems...", .{});
    ray.setTargetFPS(60);

    camera.target = .{ .x = @as(f32, @floatFromInt(config.screen_width)) / 2.0, .y = @as(f32, @floatFromInt(config.screen_height)) / 2.0 };
    camera.offset = .{ .x = @as(f32, @floatFromInt(config.screen_width)) / 2.0, .y = @as(f32, @floatFromInt(config.screen_height)) / 2.0 };
    camera.zoom = 1.0;

    const seed_value: u64 = @intCast(time.timestamp());
    game_prng_instance = DefaultPrng.init(seed_value);
    game_prng_iface = game_prng_instance.random();

    updateAndDrawLoadingStatus("Generating World (Seed: {d})...", .{seed_value});
    world = try types.GameWorld.init(allocator, config.screen_width, config.screen_height, &game_prng_iface);
    errdefer world.deinit();

    world_gen.generateSimpleIsland(&world, game_prng_iface.int(u64));
    log.info("World Terrain Generated.", .{});

    updateAndDrawLoadingStatus("Preparing Graphics...", .{});
    static_world_texture = try ray.loadRenderTexture(config.screen_width, config.screen_height);
    errdefer ray.unloadRenderTexture(static_world_texture);
    static_world_needs_redraw = true;

    updateAndDrawLoadingStatus("Creating Texture Atlas...", .{});
    atlas_manager_instance = try atlas_manager.AtlasManager.init(allocator);
    errdefer { // Wrapped in a block for clarity with the conditional
        if (atlas_manager_instance) |*am| {
            am.deinit();
        }
    }
    log.info("Atlas Created.", .{});

    drawable_entity_list = ArrayList(rendering.DrawableEntity).init(allocator);

    updateAndDrawLoadingStatus("Spawning Entities...", .{});
    entity_spawner.spawnInitialEntities(&world, &game_prng_iface);
    log.info("Initial Entities Spawned.", .{});
}

// Shuts down all game systems and frees resources.
fn shutdownGame(allocator: std_full.mem.Allocator) void {
    _ = allocator;
    log.info("Shutting down game systems...", .{});

    if (ziggy_logo_texture) |tex| {
        ray.unloadTexture(tex);
        ziggy_logo_texture = null;
    }
    drawable_entity_list.deinit();
    if (atlas_manager_instance) |*am| {
        am.deinit();
        atlas_manager_instance = null;
    }

    ray.unloadRenderTexture(static_world_texture);
    world.deinit();

    if (audio_stream_loaded) {
        ray.stopAudioStream(background_audio_stream);
        ray.unloadAudioStream(background_audio_stream);
        audio_stream_loaded = false;
    }
    ray.unloadWave(ogg_wave_info);
    if (ogg_file_data.len > 0) {
        ray.unloadFileData(ogg_file_data);
        ogg_file_data = &.{};
    }
    log.info("Game systems shut down.", .{});
}

// Main game update logic.
fn updateGame(allocator: std_full.mem.Allocator) void {
    _ = allocator;

    peon_move_timer += 1;
    animal_move_timer += 1;

    for (world.entities.items) |*entity| {
        if (peon_move_timer >= config.peon_move_interval and entity.entity_type == .Player) {
            peon_ai.updatePeon(entity, &world, &game_prng_iface);
        }
        if (animal_move_timer >= config.animal_move_interval_base) {
            switch (entity.entity_type) {
                .Sheep => animal_ai.updateSheep(entity, &world, &game_prng_iface),
                .Bear => animal_ai.updateBear(entity, &world, &game_prng_iface),
                else => {},
            }
        }
    }
    if (peon_move_timer >= config.peon_move_interval) {
        peon_move_timer = 0;
    }
    if (animal_move_timer >= config.animal_move_interval_base) {
        animal_move_timer = 0;
    }

    world.cloud_system.update();

    const mouse_screen_pos = ray.getMousePosition();
    const mouse_world_pos = ray.getScreenToWorld2D(mouse_screen_pos, camera);

    hovered_entity_idx = null;
    var i_hover: usize = world.entities.items.len;
    while (i_hover > 0) {
        const current_entity_idx = i_hover - 1;
        const entity = world.entities.items[current_entity_idx];
        const entity_metrics = rendering.getEntityMetrics(entity);
        const entity_rect = entity_metrics.rect;
        var is_collectible = false;

        switch (entity.entity_type) {
            .Tree, .RockCluster, .Brush => {
                is_collectible = true;
            },
            .Player, .Sheep, .Bear => {},
        }

        if (is_collectible) {
            if (entity_rect) |rect| {
                if (ray.checkCollisionPointRec(mouse_world_pos, rect)) {
                    hovered_entity_idx = current_entity_idx;
                    break;
                }
            }
        }
        i_hover -= 1;
    }

    const wheel_move = ray.getMouseWheelMove();
    if (wheel_move != 0) {
        const mouse_world_pos_before_zoom = ray.getScreenToWorld2D(mouse_screen_pos, camera);
        camera.zoom += wheel_move * camera.zoom * zoom_speed_factor;
        camera.zoom = math.clamp(camera.zoom, min_zoom, max_zoom);
        const mouse_world_pos_after_zoom = ray.getScreenToWorld2D(mouse_screen_pos, camera);
        camera.target.x += mouse_world_pos_before_zoom.x - mouse_world_pos_after_zoom.x;
        camera.target.y += mouse_world_pos_before_zoom.y - mouse_world_pos_after_zoom.y;
    }

    if (ray.isMouseButtonPressed(ray.MouseButton.left)) {
        var ui_interacted_this_click = false;
        if (atlas_manager_instance) |am_instance| {
            if (ui.checkMuteButtonClick(&am_instance, mouse_screen_pos)) {
                is_music_muted = !is_music_muted;
                if (audio_stream_loaded) {
                    ray.setAudioStreamVolume(background_audio_stream, if (is_music_muted) 0.0 else music_volume);
                }
                ui_interacted_this_click = true;
            }
        }

        if (!ui_interacted_this_click and hovered_entity_idx != null) {
            if (hovered_entity_idx) |entity_idx_to_collect| {
                if (entity_idx_to_collect < world.entities.items.len) {
                    const entity_to_collect = world.entities.items[entity_idx_to_collect];
                    var collected_this_frame = false;
                    switch (entity_to_collect.entity_type) {
                        .Tree => {
                            collected_wood += 1;
                            _ = world.entities.orderedRemove(entity_idx_to_collect);
                            collected_this_frame = true;
                        },
                        .RockCluster => {
                            collected_rocks += 1;
                            _ = world.entities.orderedRemove(entity_idx_to_collect);
                            collected_this_frame = true;
                        },
                        .Brush => {
                            collected_brush_items += 1;
                            _ = world.entities.orderedRemove(entity_idx_to_collect);
                            collected_this_frame = true;
                        },
                        .Player, .Sheep, .Bear => {},
                    }
                    if (collected_this_frame) {
                        hovered_entity_idx = null;
                    }
                } else {
                    hovered_entity_idx = null;
                }
            }
        }
    }
    if (ray.isMouseButtonDown(ray.MouseButton.middle)) {
        const delta = ray.getMouseDelta();
        camera.target.x -= delta.x / camera.zoom;
        camera.target.y -= delta.y / camera.zoom;
    }

    if (static_world_needs_redraw) {
        rendering.redrawStaticWorldTexture(&world, static_world_texture);
        static_world_needs_redraw = false;
    }
    // REMOVED: ray.updateAudioStream(background_audio_stream);
    // This call is not needed when using an audio callback with ray.setAudioStreamCallback.
    // The callback handles feeding data to the stream.
}

// Main game drawing logic.
fn drawGame(allocator: std_full.mem.Allocator) void {
    ray.beginDrawing();
    defer ray.endDrawing();
    ray.clearBackground(config.very_deep_water_color);

    ray.beginMode2D(camera);
    const src_rect = ray.Rectangle{ .x = 0, .y = 0, .width = @as(f32, @floatFromInt(static_world_texture.texture.width)), .height = -@as(f32, @floatFromInt(static_world_texture.texture.height)) };
    ray.drawTextureRec(static_world_texture.texture, src_rect, .{ .x = 0, .y = 0 }, ray.Color.white);

    if (atlas_manager_instance) |am_instance| {
        rendering.drawDynamicElementsAndOverlays(&world, &camera, hovered_entity_idx, allocator, &am_instance, &drawable_entity_list);
    }
    ray.endMode2D();

    if (atlas_manager_instance) |am_instance| {
        ui.drawUI(
            allocator,
            &am_instance,
            &world,
            collected_wood,
            collected_rocks,
            collected_brush_items,
            is_music_muted,
            audio_stream_loaded,
        );
    }
}

// Main application entry point.
pub fn main() !void {
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    ray.initWindow(config.screen_width, config.screen_height, "Zig Pixel Island - Loading...");
    ray.initAudioDevice();
    defer ray.closeAudioDevice();
    defer ray.closeWindow();

    if (ray.loadImage("art/ziggy_pixel_256.png")) |loaded_image| {
        defer ray.unloadImage(loaded_image);
        if (ray.loadTextureFromImage(loaded_image)) |loaded_texture| {
            ziggy_logo_texture = loaded_texture;
        } else |err_tex| {
            log.warn("Failed to create texture from Ziggy logo image: {s}", .{@errorName(err_tex)});
        }
    } else |err_img| {
        log.warn("Failed to load Ziggy logo image ('art/ziggy_pixel_256.png'): {s}", .{@errorName(err_img)});
    }

    updateAndDrawLoadingStatus("Initializing...", .{});
    for (0..5) |_| {
        if (ray.windowShouldClose()) {
            return;
        }
        updateAndDrawLoadingStatus("Initializing...", .{});
    }

    try initGame(allocator);

    updateAndDrawLoadingStatus("Initialization Complete!", .{});
    const frames_to_show_complete: u32 = 30;
    for (0..frames_to_show_complete) |_| {
        if (ray.windowShouldClose()) {
            shutdownGame(allocator);
            return;
        }
        updateAndDrawLoadingStatus("Initialization Complete!", .{});
    }

    ray.setWindowTitle("Zig Pixel Island");

    while (!ray.windowShouldClose()) {
        updateGame(allocator);
        drawGame(allocator);
    }
    shutdownGame(allocator);
}
