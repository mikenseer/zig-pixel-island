// src/ui.zig
// Handles drawing the User Interface elements.
const std_full = @import("std");
const fmt = std_full.fmt;
const ray = @import("raylib");
const config = @import("config.zig");
const types = @import("types.zig");
const atlas_manager = @import("atlas_manager.zig");
const log = std_full.log;

const ui_padding: c_int = 10;
const font_size: c_int = 10;
const line_spacing: c_int = 15;
const text_icon_spacing: c_int = 5;

fn drawResourceLine(
    allocator: std_full.mem.Allocator,
    label_start_x: c_int,
    current_y: *c_int,
    value: u32,
    icon_sprite_id: atlas_manager.SpriteId,
    am: *const atlas_manager.AtlasManager,
) void {
    const value_str = fmt.allocPrintZ(allocator, "{d}", .{value}) catch "OOM";
    defer allocator.free(value_str);

    const text_width = ray.measureText(value_str, font_size);

    var icon_width: c_int = 0;
    var icon_height: c_int = 0;
    var icon_dest_pos = ray.Vector2.zero();
    var icon_source_rect: ?ray.Rectangle = null;

    if (am.getSpriteInfo(icon_sprite_id)) |sprite_info| {
        icon_width = @as(c_int, @intFromFloat(sprite_info.source_rect.width));
        icon_height = @as(c_int, @intFromFloat(sprite_info.source_rect.height));
        icon_source_rect = sprite_info.source_rect;
    } else {
        log.warn("Icon sprite info not found for {any}", .{icon_sprite_id});
    }

    const block_width = text_width + text_icon_spacing + icon_width;
    const text_x = label_start_x - block_width;
    const icon_x = text_x + text_width + text_icon_spacing;
    const icon_y = current_y.* + @divTrunc((line_spacing - icon_height), 2);
    icon_dest_pos = .{ .x = @as(f32, @floatFromInt(icon_x)), .y = @as(f32, @floatFromInt(icon_y)) };

    ray.drawText(value_str, text_x, current_y.*, font_size, ray.Color.white);
    if (icon_source_rect) |src_rect| {
        ray.drawTextureRec(am.atlas_texture, src_rect, icon_dest_pos, ray.Color.white);
    }

    current_y.* += line_spacing;
}

fn drawTextLine(
    allocator: std_full.mem.Allocator,
    label_start_x: c_int,
    current_y: *c_int,
    comptime fmt_str: []const u8,
    args: anytype,
) void {
    const text_str = fmt.allocPrintZ(allocator, fmt_str, args) catch "OOM";
    defer allocator.free(text_str);
    ray.drawText(text_str, label_start_x, current_y.*, font_size, ray.Color.white);
    current_y.* += line_spacing;
}

pub fn drawUI(
    allocator: std_full.mem.Allocator,
    atlas_manager_ptr: *const atlas_manager.AtlasManager,
    world: *const types.GameWorld,
    collected_wood: u32,
    collected_rocks: u32,
    collected_brush_items: u32,
    is_music_muted: bool,
    audio_stream_loaded: bool,
) void {
    var current_y_pos_resources: c_int = ui_padding;
    const resource_label_x = config.screen_width - ui_padding;

    drawResourceLine(allocator, resource_label_x, &current_y_pos_resources, collected_wood, .WoodIcon, atlas_manager_ptr);
    drawResourceLine(allocator, resource_label_x, &current_y_pos_resources, collected_rocks, .RockIcon, atlas_manager_ptr);
    drawResourceLine(allocator, resource_label_x, &current_y_pos_resources, collected_brush_items, .BrushItemIcon, atlas_manager_ptr);

    var current_y_pos_entities: c_int = ui_padding;
    const entity_label_x = ui_padding;

    var peon_count: u32 = 0;
    var tree_count: u32 = 0;
    var rock_cluster_count: u32 = 0;
    var brush_count: u32 = 0;
    var sheep_count: u32 = 0; // New counter
    var bear_count: u32 = 0; // New counter

    for (world.entities.items) |entity_item| {
        switch (entity_item.entity_type) {
            .Player => peon_count += 1,
            .Tree => tree_count += 1,
            .RockCluster => rock_cluster_count += 1,
            .Brush => brush_count += 1,
            .Sheep => sheep_count += 1, // Count sheep
            .Bear => bear_count += 1, // Count bears
        }
    }

    drawTextLine(allocator, entity_label_x, &current_y_pos_entities, "Peons: {d}", .{peon_count});
    drawTextLine(allocator, entity_label_x, &current_y_pos_entities, "Trees: {d}", .{tree_count});
    drawTextLine(allocator, entity_label_x, &current_y_pos_entities, "Rocks: {d}", .{rock_cluster_count});
    drawTextLine(allocator, entity_label_x, &current_y_pos_entities, "Brush: {d}", .{brush_count});
    drawTextLine(allocator, entity_label_x, &current_y_pos_entities, "Sheep: {d}", .{sheep_count}); // Display sheep count
    drawTextLine(allocator, entity_label_x, &current_y_pos_entities, "Bears: {d}", .{bear_count}); // Display bear count
    drawTextLine(allocator, entity_label_x, &current_y_pos_entities, "Total: {d}", .{world.entities.items.len});

    if (audio_stream_loaded) {
        const speaker_sprite_id = if (is_music_muted) atlas_manager.SpriteId.SpeakerMuted else atlas_manager.SpriteId.SpeakerUnmuted;
        if (atlas_manager_ptr.getSpriteInfo(speaker_sprite_id)) |sprite_info| {
            const icon_height = @as(c_int, @intFromFloat(sprite_info.source_rect.height));
            const icon_x = ui_padding;
            const icon_y = config.screen_height - ui_padding - icon_height;
            const dest_pos = ray.Vector2{ .x = @as(f32, @floatFromInt(icon_x)), .y = @as(f32, @floatFromInt(icon_y)) };
            ray.drawTextureRec(atlas_manager_ptr.atlas_texture, sprite_info.source_rect, dest_pos, ray.Color.white);
        } else {
            log.warn("Speaker icon sprite info not found for {any}", .{speaker_sprite_id});
        }
    }

    const current_fps = ray.getFPS();
    const fps_text = fmt.allocPrintZ(allocator, "FPS: {d}", .{current_fps}) catch "FPS: OOM";
    defer allocator.free(fps_text);

    const fps_text_width_val = ray.measureText(fps_text, font_size);
    const fps_x_pos = config.screen_width - ui_padding - fps_text_width_val;
    const fps_y_pos = config.screen_height - ui_padding - font_size;
    ray.drawText(fps_text, fps_x_pos, fps_y_pos, font_size, ray.Color.white);
}

pub fn checkMuteButtonClick(am: *const atlas_manager.AtlasManager, mouse_pos: ray.Vector2) bool {
    if (am.getSpriteInfo(.SpeakerUnmuted)) |sprite_info| {
        const icon_width = @as(c_int, @intFromFloat(sprite_info.source_rect.width));
        const icon_height = @as(c_int, @intFromFloat(sprite_info.source_rect.height));
        const icon_x = ui_padding;
        const icon_y = config.screen_height - ui_padding - icon_height;

        const icon_rect = ray.Rectangle{
            .x = @as(f32, @floatFromInt(icon_x)),
            .y = @as(f32, @floatFromInt(icon_y)),
            .width = @as(f32, @floatFromInt(icon_width)),
            .height = @as(f32, @floatFromInt(icon_height)),
        };
        return ray.checkCollisionPointRec(mouse_pos, icon_rect);
    }
    return false;
}
