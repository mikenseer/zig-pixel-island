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
const animal_ai_utils = @import("animal_ai.zig");
const sheep_ai = @import("sheep_ai.zig");
const bear_ai = @import("bear_ai.zig");
const items_module = @import("items.zig");
const combat = @import("combat.zig");
const entity_processing = @import("entity_processing.zig");
const inventory = @import("inventory.zig");

// --- Game State ---
var gpa = heap.GeneralPurposeAllocator(.{}){};
var game_prng_instance: DefaultPrng = undefined;
var game_prng_iface: RandomInterface = undefined;
var world: types.GameWorld = undefined;
var atlas_manager_instance: ?atlas_manager.AtlasManager = null;
var drawable_entity_list: ArrayList(rendering.DrawableEntity) = undefined;
var ziggy_logo_texture: ?ray.Texture2D = null;
var is_game_paused: bool = false;
const base_target_fps: c_int = 60;
var game_speed_multiplier: f32 = 1.0;

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
var hovered_item_idx: ?usize = null;
var current_mouse_screen_pos: ray.Vector2 = .{ .x = 0, .y = 0 };
var followed_entity_idx: ?usize = null;
var followed_item_idx: ?usize = null;

// --- Rendering ---
var static_world_texture: ray.RenderTexture2D = undefined;
var static_world_needs_redraw: bool = true;

// --- Audio ---
var ogg_file_data: []u8 = undefined;
var ogg_wave_info: ray.Wave = undefined;
var background_audio_stream: ray.AudioStream = undefined;
var audio_stream_loaded: bool = false;
var audio_stream_cursor: u64 = 0;
var is_music_muted: bool = false;
var music_volume: f32 = 1.0;
const dummy_audio_byte: u8 = 0;

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

fn initGame(allocator: std_full.mem.Allocator) !void {
    updateAndDrawLoadingStatus("Loading Audio...", .{});
    ogg_file_data = ray.loadFileData("audio/zigisland.ogg") catch |err| blk: {
        log.warn("Failed to load OGG file data ('audio/zigisland.ogg'): {s}. Audio will be disabled.", .{@errorName(err)});
        audio_stream_loaded = false;
        break :blk &.{};
    };

    if (ogg_file_data.len > 0) {
        errdefer if (ogg_file_data.len > 0) {
            ray.unloadFileData(ogg_file_data);
        };

        ogg_wave_info = ray.loadWaveFromMemory(".ogg", ogg_file_data) catch |err| blk: {
            log.warn("Failed to load wave info: {s}", .{@errorName(err)});
            audio_stream_loaded = false;
            break :blk ray.Wave{
                .frameCount = 0,
                .sampleRate = 0,
                .sampleSize = 0,
                .channels = 0,
                .data = @as(*anyopaque, @ptrCast(@constCast(&dummy_audio_byte))),
            };
        };

        if (ogg_wave_info.frameCount > 0) {
            errdefer if (ogg_wave_info.frameCount > 0) {
                ray.unloadWave(ogg_wave_info);
            };

            background_audio_stream = ray.loadAudioStream(ogg_wave_info.sampleRate, ogg_wave_info.sampleSize, ogg_wave_info.channels) catch |err_stream| {
                log.warn("Failed to load audio stream: {s}. Audio will be disabled.", .{@errorName(err_stream)});
                audio_stream_loaded = false;
                return err_stream;
            };
            audio_stream_loaded = true;

            errdefer if (audio_stream_loaded) {
                ray.unloadAudioStream(background_audio_stream);
            };

            ray.setAudioStreamCallback(background_audio_stream, audioStreamCallback);
            ray.playAudioStream(background_audio_stream);
            ray.setAudioStreamVolume(background_audio_stream, if (is_music_muted) 0.0 else music_volume);
            log.info("Audio Initialized and Playing.", .{});
        } else {
            audio_stream_loaded = false;
            log.warn("Audio wave info not valid (frameCount is 0). Audio will be disabled.", .{});
        }
    } else {
        audio_stream_loaded = false;
        log.warn("OGG file data not loaded. Audio will be disabled.", .{});
    }
    updateAndDrawLoadingStatus("Setting up Game Systems...", .{});
    ray.setTargetFPS(base_target_fps);

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

    updateAndDrawLoadingStatus("Creating Texture Atlas...", .{});
    atlas_manager_instance = try atlas_manager.AtlasManager.init(allocator);
    errdefer if (atlas_manager_instance) |*am| {
        am.deinit();
    };

    drawable_entity_list = ArrayList(rendering.DrawableEntity).init(allocator);
    errdefer drawable_entity_list.deinit();

    updateAndDrawLoadingStatus("Spawning Entities...", .{});
    entity_spawner.spawnInitialEntities(&world, &game_prng_iface);
    log.info("Initial Entities Spawned.", .{});
}

fn shutdownGame(allocator: std_full.mem.Allocator) void {
    _ = allocator;
    log.info("Shutting down game systems...", .{});

    if (ziggy_logo_texture) |tex| {
        ray.unloadTexture(tex);
        ziggy_logo_texture = null;
    }

    if (drawable_entity_list.items.len > 0) {
        drawable_entity_list.deinit();
    }

    if (atlas_manager_instance) |*am| {
        am.deinit();
        atlas_manager_instance = null;
    }

    if (static_world_texture.id > 0) {
        ray.unloadRenderTexture(static_world_texture);
    }

    if (world.tiles.len > 0) {
        world.deinit();
    }

    if (audio_stream_loaded) {
        ray.stopAudioStream(background_audio_stream);
        ray.unloadAudioStream(background_audio_stream);
    }
    if (ogg_wave_info.frameCount > 0) {
        ray.unloadWave(ogg_wave_info);
    }
    if (ogg_file_data.len > 0) {
        ray.unloadFileData(ogg_file_data);
    }
    log.info("Game systems shut down.", .{});
}

// Main game update logic.
fn updateGame(allocator: std_full.mem.Allocator) void {
    _ = allocator;

    if (ray.isKeyPressed(ray.KeyboardKey.space)) {
        is_game_paused = !is_game_paused;
        log.info("Game Paused: {any}", .{is_game_paused});
    }

    var new_target_fps: c_int = base_target_fps; // Start with current target
    var speed_changed = false;

    if (ray.isKeyPressed(ray.KeyboardKey.one)) {
        game_speed_multiplier = 0.25;
        is_game_paused = false;
        speed_changed = true;
    }
    if (ray.isKeyPressed(ray.KeyboardKey.two)) {
        game_speed_multiplier = 0.5;
        is_game_paused = false;
        speed_changed = true;
    }
    if (ray.isKeyPressed(ray.KeyboardKey.three)) {
        game_speed_multiplier = 1.0;
        is_game_paused = false;
        speed_changed = true;
    }

    if (speed_changed) {
        new_target_fps = @max(15, @as(c_int, @intFromFloat(math.round(@as(f32, @floatFromInt(base_target_fps)) * game_speed_multiplier))));
        ray.setTargetFPS(new_target_fps);
        log.info("Game Speed: x{d:.2} (Target FPS: {d})", .{ game_speed_multiplier, new_target_fps });
    }

    current_mouse_screen_pos = ray.getMousePosition();
    const mouse_world_pos = ray.getScreenToWorld2D(current_mouse_screen_pos, camera);

    if (!is_game_paused) {
        var i_entity: usize = 0;
        while (i_entity < world.entities.items.len) {
            const entity_ptr = &world.entities.items[i_entity];
            switch (entity_ptr.entity_type) {
                .Player => peon_ai.updatePeon(entity_ptr, &world, &game_prng_iface),
                .Sheep => sheep_ai.updateSheep(entity_ptr, &world, &game_prng_iface),
                .Bear => bear_ai.updateBear(entity_ptr, &world, &game_prng_iface),
                .Tree, .RockCluster, .Brush => {},
            }

            if (entity_ptr.current_hp == 0) {
                if (!entity_ptr.processed_death_drops) {
                    entity_processing.processEntityDeath(entity_ptr, &world, &game_prng_iface);
                }
                _ = world.entities.orderedRemove(i_entity);
                if (hovered_entity_idx) |h_idx| {
                    if (h_idx == i_entity) {
                        hovered_entity_idx = null;
                    } else if (h_idx > i_entity) hovered_entity_idx.? -= 1;
                }
                if (followed_entity_idx != null and followed_entity_idx.? == i_entity) {
                    followed_entity_idx = null;
                } else if (followed_entity_idx != null and followed_entity_idx.? > i_entity) {
                    followed_entity_idx.? -= 1;
                }
                continue;
            }
            i_entity += 1;
        }

        var i_item: usize = 0;
        while (i_item < world.items.items.len) {
            var item_ptr = &world.items.items[i_item];
            item_ptr.decay_timer -%= 1;
            if (item_ptr.decay_timer == 0) {
                if (item_ptr.hp > 1) {
                    item_ptr.hp -= 1;
                    item_ptr.decay_timer = items_module.Item.getDecayRateTicks(item_ptr.item_type);
                } else {
                    item_ptr.hp = 0;
                }
            }
            if (item_ptr.hp == 0) {
                _ = world.items.orderedRemove(i_item);
                if (hovered_item_idx) |h_idx_item| {
                    if (h_idx_item == i_item) {
                        hovered_item_idx = null;
                    } else if (h_idx_item > i_item) hovered_item_idx.? -= 1;
                }
                if (followed_item_idx != null and followed_item_idx.? == i_item) {
                    followed_item_idx = null;
                } else if (followed_item_idx != null and followed_item_idx.? > i_item) {
                    followed_item_idx.? -= 1;
                }
                continue;
            }
            i_item += 1;
        }
        world.cloud_system.update();
    }

    hovered_entity_idx = null;
    hovered_item_idx = null;

    var i_hover_entity: usize = world.entities.items.len;
    while (i_hover_entity > 0) {
        const current_entity_idx = i_hover_entity - 1;
        if (current_entity_idx < world.entities.items.len) {
            const entity = world.entities.items[current_entity_idx];
            if (atlas_manager_instance) |am_instance| {
                const entity_metrics = rendering.getEntityMetrics(entity, &am_instance);
                if (entity_metrics.rect) |rect| {
                    if (ray.checkCollisionPointRec(mouse_world_pos, rect)) {
                        hovered_entity_idx = current_entity_idx;
                        break;
                    }
                }
            }
        }
        i_hover_entity -= 1;
    }

    if (hovered_entity_idx == null) {
        var i_hover_item: usize = world.items.items.len;
        while (i_hover_item > 0) {
            const current_item_idx = i_hover_item - 1;
            if (current_item_idx < world.items.items.len) {
                const item = world.items.items[current_item_idx];
                if (atlas_manager_instance) |am_instance| {
                    if (rendering.getItemScreenRect(item, &am_instance)) |item_rect| {
                        if (ray.checkCollisionPointRec(mouse_world_pos, item_rect)) {
                            hovered_item_idx = current_item_idx;
                            break;
                        }
                    }
                }
            }
            i_hover_item -= 1;
        }
    }

    const wheel_move = ray.getMouseWheelMove();
    if (wheel_move != 0) {
        const mouse_world_pos_before_zoom = ray.getScreenToWorld2D(current_mouse_screen_pos, camera);
        camera.zoom += wheel_move * camera.zoom * zoom_speed_factor;
        camera.zoom = math.clamp(camera.zoom, min_zoom, max_zoom);
        const mouse_world_pos_after_zoom = ray.getScreenToWorld2D(current_mouse_screen_pos, camera);
        camera.target.x += mouse_world_pos_before_zoom.x - mouse_world_pos_after_zoom.x;
        camera.target.y += mouse_world_pos_before_zoom.y - mouse_world_pos_after_zoom.y;
    }
    if (followed_entity_idx == null and followed_item_idx == null and ray.isMouseButtonDown(ray.MouseButton.middle)) {
        const delta = ray.getMouseDelta();
        camera.target.x -= delta.x / camera.zoom;
        camera.target.y -= delta.y / camera.zoom;
    }

    if (ray.isMouseButtonPressed(ray.MouseButton.left)) {
        var ui_interacted_this_click = false;
        if (atlas_manager_instance) |am_instance| {
            if (ui.checkMuteButtonClick(&am_instance, current_mouse_screen_pos)) {
                is_music_muted = !is_music_muted;
                if (audio_stream_loaded) {
                    ray.setAudioStreamVolume(background_audio_stream, if (is_music_muted) 0.0 else music_volume);
                }
                ui_interacted_this_click = true;
            }
        }

        if (!ui_interacted_this_click) {
            if (hovered_entity_idx) |h_idx| {
                if (followed_entity_idx != null and followed_entity_idx.? == h_idx) {
                    followed_entity_idx = null;
                } else {
                    followed_entity_idx = h_idx;
                    followed_item_idx = null;
                }
            } else if (hovered_item_idx) |h_item_idx| {
                if (followed_item_idx != null and followed_item_idx.? == h_item_idx) {
                    followed_item_idx = null;
                } else {
                    followed_item_idx = h_item_idx;
                    followed_entity_idx = null;
                }
            } else {
                followed_entity_idx = null;
                followed_item_idx = null;
            }
        }
    }

    if (followed_entity_idx) |idx| {
        if (idx < world.entities.items.len) {
            const entity_to_follow = world.entities.items[idx];
            if (atlas_manager_instance) |am| {
                const metrics = rendering.getEntityMetrics(entity_to_follow, &am);
                if (metrics.rect) |rect| {
                    camera.target.x = rect.x + rect.width / 2.0;
                    camera.target.y = rect.y + rect.height / 2.0;
                } else {
                    camera.target.x = @as(f32, @floatFromInt(entity_to_follow.x));
                    camera.target.y = @as(f32, @floatFromInt(entity_to_follow.y));
                }
            } else {
                camera.target.x = @as(f32, @floatFromInt(entity_to_follow.x));
                camera.target.y = @as(f32, @floatFromInt(entity_to_follow.y));
            }
        } else {
            followed_entity_idx = null;
        }
    } else if (followed_item_idx) |idx| {
        if (idx < world.items.items.len) {
            const item_to_follow = world.items.items[idx];
            if (atlas_manager_instance) |am| {
                if (rendering.getItemScreenRect(item_to_follow, &am)) |rect| {
                    camera.target.x = rect.x + rect.width / 2.0;
                    camera.target.y = rect.y + rect.height / 2.0;
                } else {
                    camera.target.x = @as(f32, @floatFromInt(item_to_follow.x)) + 0.5;
                    camera.target.y = @as(f32, @floatFromInt(item_to_follow.y)) + 0.5;
                }
            } else {
                camera.target.x = @as(f32, @floatFromInt(item_to_follow.x)) + 0.5;
                camera.target.y = @as(f32, @floatFromInt(item_to_follow.y)) + 0.5;
            }
        } else {
            followed_item_idx = null;
        }
    }

    if (static_world_needs_redraw and !is_game_paused) {
        rendering.redrawStaticWorldTexture(&world, static_world_texture);
        static_world_needs_redraw = false;
    }
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
        rendering.drawItems(&world, &am_instance, hovered_item_idx, &camera);
    }

    if (atlas_manager_instance) |am_instance| {
        rendering.drawDynamicElementsAndOverlays(&world, &camera, hovered_entity_idx, followed_entity_idx, allocator, &am_instance, &drawable_entity_list);
    }

    if (atlas_manager_instance) |am_instance| {
        rendering.drawCarriedItems(&world, &am_instance);
    }

    ray.endMode2D();

    if (atlas_manager_instance) |am_instance| {
        ui.drawUI(
            allocator,
            &am_instance,
            &world,
            is_music_muted,
            audio_stream_loaded,
            hovered_entity_idx,
            hovered_item_idx,
            current_mouse_screen_pos,
            is_game_paused,
            followed_entity_idx,
            followed_item_idx,
            game_speed_multiplier,
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
    var i: u8 = 0;
    while (i < 5) : (i += 1) {
        if (ray.windowShouldClose()) {
            if (ziggy_logo_texture) |tex| ray.unloadTexture(tex);
            return;
        }
        updateAndDrawLoadingStatus("Initializing...", .{});
    }

    initGame(allocator) catch |err| {
        log.err("Failed to initialize game: {s}. Shutting down.", .{@errorName(err)});
        shutdownGame(allocator);
        return;
    };

    updateAndDrawLoadingStatus("Initialization Complete!", .{});
    const frames_to_show_complete: u32 = 30;
    var frame_count: u32 = 0;
    while (frame_count < frames_to_show_complete) : (frame_count += 1) {
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
