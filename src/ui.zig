// src/ui.zig
// Handles drawing the User Interface elements.
const std_full = @import("std");
const fmt = std_full.fmt;
const ray = @import("raylib");
const config = @import("config.zig");
const types = @import("types.zig");
const atlas_manager = @import("atlas_manager.zig");
const items_module = @import("items.zig");
const log = std_full.log;
const math = std_full.math;

const ui_padding: c_int = 10;
const font_size: c_int = 10;
const line_spacing: c_int = 15;
const text_icon_spacing: c_int = 5;

// Helper function to draw a simple line of text.
fn drawTextLine(
    allocator: std_full.mem.Allocator,
    label_start_x: c_int,
    current_y: *c_int,
    comptime fmt_str_arg: []const u8,
    args: anytype,
    color: ray.Color,
    size: c_int,
    spacing: c_int,
) void {
    var temp_buf: [128]u8 = undefined;
    const text_str = fmt.bufPrintZ(&temp_buf, fmt_str_arg, args) catch |err| {
        log.err("Failed to format text line (bufPrintZ): {s}", .{@errorName(err)});
        const alloc_text_str = fmt.allocPrintZ(allocator, fmt_str_arg, args) catch |alloc_err| {
            log.err("Failed to allocate string for text line: {s}", .{@errorName(alloc_err)});
            const oom_str = "OOM";
            ray.drawText(oom_str, label_start_x, current_y.*, size, ray.Color.red);
            current_y.* += spacing;
            return;
        };
        defer allocator.free(alloc_text_str);
        ray.drawText(alloc_text_str, label_start_x, current_y.*, size, color);
        current_y.* += spacing;
        return;
    };

    ray.drawText(text_str, label_start_x, current_y.*, size, color);
    current_y.* += spacing;
}

// Draws the stats panel for an entity.
// `is_pinned_top_right` determines if it's anchored or mouse-relative.
fn drawEntityStatsPanel(
    allocator: std_full.mem.Allocator,
    entity: types.Entity,
    mouse_screen_pos: ray.Vector2,
    is_pinned_top_right: bool,
) !void {
    const panel_padding = config.ui_panel_padding;
    const panel_font_size = config.ui_panel_font_size;
    const panel_line_spacing = config.ui_panel_line_spacing;
    const panel_bg_color = config.ui_panel_background_color;
    const panel_text_color = config.ui_panel_text_color;
    const panel_stat_value_color = config.ui_panel_stat_value_color;
    const panel_offset_x = config.ui_panel_mouse_offset_x;
    const panel_offset_y = config.ui_panel_mouse_offset_y;

    var text_lines = std_full.ArrayList([:0]const u8).init(allocator);
    defer {
        for (text_lines.items) |duped_line| {
            allocator.free(duped_line);
        }
        text_lines.deinit();
    }

    var temp_line_buf: [128]u8 = undefined;

    const type_name_str = @tagName(entity.entity_type);
    const line1 = fmt.bufPrintZ(&temp_line_buf, "{s}", .{type_name_str}) catch "Entity";
    try text_lines.append(try allocator.dupeZ(u8, line1));

    const line2 = fmt.bufPrintZ(&temp_line_buf, "HP: {d}/{d}", .{ entity.current_hp, entity.max_hp }) catch "HP: N/A";
    try text_lines.append(try allocator.dupeZ(u8, line2));

    if (entity.entity_type == .Tree) {
        const line3 = fmt.bufPrintZ(&temp_line_buf, "Age: {d}", .{entity.growth_stage}) catch "Age: N/A";
        try text_lines.append(try allocator.dupeZ(u8, line3));
    }
    const action_line = fmt.bufPrintZ(&temp_line_buf, "Action: {s}", .{@tagName(entity.current_action)}) catch "Action: N/A";
    try text_lines.append(try allocator.dupeZ(u8, action_line));
    if (entity.must_complete_wander_step) {
        const wander_flag_line = "MustWander: Yes";
        try text_lines.append(try allocator.dupeZ(u8, wander_flag_line));
    }
    if (entity.blocked_target_cooldown > 0) {
        const blocked_text = fmt.bufPrintZ(&temp_line_buf, "BlockedTgt: {?d} ({d})", .{ entity.blocked_target_idx, entity.blocked_target_cooldown }) catch "BlockedTgt: Yes";
        try text_lines.append(try allocator.dupeZ(u8, blocked_text));
    }

    var max_text_width: c_int = 0;
    for (text_lines.items) |line_text| {
        const w = ray.measureText(line_text, panel_font_size);
        if (w > max_text_width) {
            max_text_width = w;
        }
    }

    const panel_width = max_text_width + (panel_padding * 2);
    const panel_height = @as(c_int, @intCast(text_lines.items.len)) * panel_line_spacing - (panel_line_spacing - panel_font_size) + (panel_padding * 2);

    var panel_x: c_int = 0;
    var panel_y: c_int = 0;

    if (is_pinned_top_right) {
        panel_x = config.screen_width - panel_width - ui_padding;
        panel_y = ui_padding;
    } else {
        panel_x = @as(c_int, @intFromFloat(math.round(mouse_screen_pos.x))) + panel_offset_x;
        panel_y = @as(c_int, @intFromFloat(math.round(mouse_screen_pos.y))) + panel_offset_y;

        if (panel_x + panel_width > config.screen_width) {
            panel_x = @as(c_int, @intFromFloat(math.round(mouse_screen_pos.x))) - panel_width - panel_offset_x;
        }
        if (panel_y + panel_height > config.screen_height) {
            panel_y = @as(c_int, @intFromFloat(math.round(mouse_screen_pos.y))) - panel_height - panel_offset_y;
        }
    }
    if (panel_x < 0) panel_x = 0;
    if (panel_y < 0) panel_y = 0;
    if (panel_x + panel_width > config.screen_width) panel_x = config.screen_width - panel_width;
    if (panel_y + panel_height > config.screen_height) panel_y = config.screen_height - panel_height;

    ray.drawRectangle(panel_x, panel_y, panel_width, panel_height, panel_bg_color);
    ray.drawRectangleLines(panel_x, panel_y, panel_width, panel_height, ray.Color.dark_gray);

    var current_text_y = panel_y + panel_padding;
    var temp_draw_buf: [64]u8 = undefined;

    for (text_lines.items) |line_text_z| {
        if (std_full.mem.startsWith(u8, line_text_z, "HP:") or
            std_full.mem.startsWith(u8, line_text_z, "Age:") or
            std_full.mem.startsWith(u8, line_text_z, "Action:") or
            std_full.mem.startsWith(u8, line_text_z, "BlockedTgt:"))
        {
            if (std_full.mem.indexOfScalar(u8, line_text_z, ':')) |colon_idx| {
                const label_part_slice = line_text_z[0 .. colon_idx + 1];
                const label_draw_str = fmt.bufPrintZ(&temp_draw_buf, "{s}", .{label_part_slice}) catch |e| blk: {
                    log.err("fmt label: {s}", .{@errorName(e)});
                    break :blk line_text_z;
                };
                ray.drawText(label_draw_str, panel_x + panel_padding, current_text_y, panel_font_size, panel_text_color);

                const label_width = ray.measureText(label_draw_str, panel_font_size);

                const value_part_slice = line_text_z[colon_idx + 2 ..];
                const value_draw_str = fmt.bufPrintZ(&temp_draw_buf, "{s}", .{value_part_slice}) catch |e| blk: {
                    log.err("fmt value: {s}", .{@errorName(e)});
                    break :blk "";
                };
                ray.drawText(value_draw_str, panel_x + panel_padding + label_width + 2, current_text_y, panel_font_size, panel_stat_value_color);
            } else {
                ray.drawText(line_text_z, panel_x + panel_padding, current_text_y, panel_font_size, panel_text_color);
            }
        } else {
            ray.drawText(line_text_z, panel_x + panel_padding, current_text_y, panel_font_size, panel_text_color);
        }
        current_text_y += panel_line_spacing;
    }
}

// Draws the stats panel for an item.
// `is_pinned_top_right` determines if it's anchored or mouse-relative.
fn drawItemStatsPanel(
    allocator: std_full.mem.Allocator,
    item: items_module.Item,
    mouse_screen_pos: ray.Vector2,
    is_pinned_top_right: bool,
) !void {
    const panel_padding = config.ui_panel_padding;
    const panel_font_size = config.ui_panel_font_size;
    const panel_line_spacing = config.ui_panel_line_spacing;
    const panel_bg_color = config.ui_panel_background_color;
    const panel_text_color = config.ui_panel_text_color;
    const panel_stat_value_color = config.ui_panel_stat_value_color;
    const panel_offset_x = config.ui_panel_mouse_offset_x;
    const panel_offset_y = config.ui_panel_mouse_offset_y;

    var text_lines = std_full.ArrayList([:0]const u8).init(allocator);
    defer {
        for (text_lines.items) |duped_line| {
            allocator.free(duped_line);
        }
        text_lines.deinit();
    }
    var temp_line_buf: [128]u8 = undefined;

    const item_type_name = items_module.getItemTypeName(item.item_type);
    try text_lines.append(try allocator.dupeZ(u8, item_type_name));

    const hp_text = fmt.bufPrintZ(&temp_line_buf, "HP: {d}/{d}", .{ item.hp, items_module.Item.getInitialHp(item.item_type) }) catch "HP: N/A";
    try text_lines.append(try allocator.dupeZ(u8, hp_text));

    var max_text_width: c_int = 0;
    for (text_lines.items) |line_text| {
        const w = ray.measureText(line_text, panel_font_size);
        if (w > max_text_width) max_text_width = w;
    }

    const panel_width = max_text_width + (panel_padding * 2);
    const panel_height = @as(c_int, @intCast(text_lines.items.len)) * panel_line_spacing - (panel_line_spacing - panel_font_size) + (panel_padding * 2);

    var panel_x: c_int = 0;
    var panel_y: c_int = 0;

    if (is_pinned_top_right) {
        panel_x = config.screen_width - panel_width - ui_padding;
        panel_y = ui_padding;
    } else {
        panel_x = @as(c_int, @intFromFloat(math.round(mouse_screen_pos.x))) + panel_offset_x;
        panel_y = @as(c_int, @intFromFloat(math.round(mouse_screen_pos.y))) + panel_offset_y;

        if (panel_x + panel_width > config.screen_width) panel_x = @as(c_int, @intFromFloat(math.round(mouse_screen_pos.x))) - panel_width - panel_offset_x;
        if (panel_y + panel_height > config.screen_height) panel_y = @as(c_int, @intFromFloat(math.round(mouse_screen_pos.y))) - panel_height - panel_offset_y;
    }
    if (panel_x < 0) panel_x = 0;
    if (panel_y < 0) panel_y = 0;
    if (panel_x + panel_width > config.screen_width) panel_x = config.screen_width - panel_width;
    if (panel_y + panel_height > config.screen_height) panel_y = config.screen_height - panel_height;

    ray.drawRectangle(panel_x, panel_y, panel_width, panel_height, panel_bg_color);
    ray.drawRectangleLines(panel_x, panel_y, panel_width, panel_height, ray.Color.dark_gray);

    var current_text_y = panel_y + panel_padding;
    var temp_draw_buf_item: [64]u8 = undefined;

    for (text_lines.items) |line_text_z| {
        if (std_full.mem.startsWith(u8, line_text_z, "HP:")) {
            if (std_full.mem.indexOfScalar(u8, line_text_z, ':')) |colon_idx| {
                const label_part_slice = line_text_z[0 .. colon_idx + 1];
                const label_draw_str = fmt.bufPrintZ(&temp_draw_buf_item, "{s}", .{label_part_slice}) catch line_text_z;
                ray.drawText(label_draw_str, panel_x + panel_padding, current_text_y, panel_font_size, panel_text_color);
                const label_width = ray.measureText(label_draw_str, panel_font_size);
                const value_part_slice = line_text_z[colon_idx + 2 ..];
                const value_draw_str = fmt.bufPrintZ(&temp_draw_buf_item, "{s}", .{value_part_slice}) catch "";
                ray.drawText(value_draw_str, panel_x + panel_padding + label_width + 2, current_text_y, panel_font_size, panel_stat_value_color);
            } else {
                ray.drawText(line_text_z, panel_x + panel_padding, current_text_y, panel_font_size, panel_text_color);
            }
        } else {
            ray.drawText(line_text_z, panel_x + panel_padding, current_text_y, panel_font_size, panel_text_color);
        }
        current_text_y += panel_line_spacing;
    }
}

// Main function to draw all UI elements.
pub fn drawUI(
    allocator: std_full.mem.Allocator,
    atlas_manager_ptr: *const atlas_manager.AtlasManager,
    world: *const types.GameWorld,
    is_music_muted_val: bool,
    audio_stream_loaded_val: bool,
    hovered_entity_idx_val: ?usize,
    hovered_item_idx_val: ?usize,
    mouse_screen_pos_val: ray.Vector2,
    is_game_paused_val: bool,
    followed_entity_idx_val: ?usize,
    followed_item_idx_val: ?usize,
    game_speed_multiplier_val: f32,
) void {
    var current_y_pos_entities: c_int = ui_padding;
    const entity_label_x = ui_padding;

    var peon_count: u32 = 0;
    var tree_count: u32 = 0;
    var rock_cluster_count: u32 = 0;
    var brush_count: u32 = 0;
    var sheep_count: u32 = 0;
    var bear_count: u32 = 0;

    for (world.entities.items) |entity_item| {
        switch (entity_item.entity_type) {
            .Player => peon_count += 1,
            .Tree => tree_count += 1,
            .RockCluster => rock_cluster_count += 1,
            .Brush => brush_count += 1,
            .Sheep => sheep_count += 1,
            .Bear => bear_count += 1,
        }
    }

    drawTextLine(allocator, entity_label_x, &current_y_pos_entities, "Peons: {d}", .{peon_count}, config.ui_panel_text_color, font_size, line_spacing);
    drawTextLine(allocator, entity_label_x, &current_y_pos_entities, "Trees: {d}", .{tree_count}, config.ui_panel_text_color, font_size, line_spacing);
    drawTextLine(allocator, entity_label_x, &current_y_pos_entities, "Rocks: {d}", .{rock_cluster_count}, config.ui_panel_text_color, font_size, line_spacing);
    drawTextLine(allocator, entity_label_x, &current_y_pos_entities, "Brush: {d}", .{brush_count}, config.ui_panel_text_color, font_size, line_spacing);
    drawTextLine(allocator, entity_label_x, &current_y_pos_entities, "Sheep: {d}", .{sheep_count}, config.ui_panel_text_color, font_size, line_spacing);
    drawTextLine(allocator, entity_label_x, &current_y_pos_entities, "Bears: {d}", .{bear_count}, config.ui_panel_text_color, font_size, line_spacing);
    drawTextLine(allocator, entity_label_x, &current_y_pos_entities, "Items: {d}", .{world.items.items.len}, config.ui_panel_text_color, font_size, line_spacing);
    drawTextLine(allocator, entity_label_x, &current_y_pos_entities, "Total Entities: {d}", .{world.entities.items.len}, config.ui_panel_text_color, font_size, line_spacing);

    // Following Info Text (Top-left, below entity counts)
    var follow_text_y = current_y_pos_entities + line_spacing; // Start below last entity count
    if (followed_entity_idx_val) |fe_idx| {
        if (fe_idx < world.entities.items.len) {
            const followed_name = @tagName(world.entities.items[fe_idx].entity_type);
            drawTextLine(allocator, entity_label_x, &follow_text_y, "Follow: {s} [{d}]", .{ followed_name, fe_idx }, ray.Color.yellow, font_size, line_spacing);
        }
    } else if (followed_item_idx_val) |fi_idx| {
        if (fi_idx < world.items.items.len) {
            const followed_name = items_module.getItemTypeName(world.items.items[fi_idx].item_type);
            drawTextLine(allocator, entity_label_x, &follow_text_y, "Follow: {s} [{d}]", .{ followed_name, fi_idx }, ray.Color.yellow, font_size, line_spacing);
        }
    }

    // Game Speed Display (Below follow info)
    var speed_text_y = follow_text_y; // Continue from where follow text left off, or entity_counts if no follow
    if (followed_entity_idx_val == null and followed_item_idx_val == null) { // If nothing followed, start speed text after entity counts
        speed_text_y = current_y_pos_entities;
    }
    var speed_text_buf: [32]u8 = undefined;
    const speed_text = fmt.bufPrintZ(&speed_text_buf, "Speed: x{d:.2}", .{game_speed_multiplier_val}) catch "Speed: N/A";
    drawTextLine(allocator, entity_label_x, &speed_text_y, "{s}", .{speed_text}, ray.Color.sky_blue, font_size, line_spacing);

    if (audio_stream_loaded_val) {
        const speaker_sprite_id = if (is_music_muted_val) atlas_manager.SpriteId.SpeakerMuted else atlas_manager.SpriteId.SpeakerUnmuted;
        if (atlas_manager_ptr.getSpriteInfo(speaker_sprite_id)) |sprite_info| {
            const icon_height = @as(c_int, @intFromFloat(math.round(sprite_info.source_rect.height)));
            const icon_x = ui_padding;
            const icon_y = config.screen_height - ui_padding - icon_height;
            const dest_pos = ray.Vector2{ .x = @as(f32, @floatFromInt(icon_x)), .y = @as(f32, @floatFromInt(icon_y)) };
            ray.drawTextureRec(atlas_manager_ptr.atlas_texture, sprite_info.source_rect, dest_pos, ray.Color.white);
        } else {
            log.warn("Speaker icon sprite info not found for {any}", .{speaker_sprite_id});
        }
    }

    const current_fps = ray.getFPS();
    const fps_text_buf_size = 16;
    var fps_text_buf: [fps_text_buf_size]u8 = undefined;
    const fps_text_slice_z = fmt.bufPrintZ(&fps_text_buf, "FPS: {d}", .{current_fps}) catch "FPS: N/A";

    const fps_text_width_val = ray.measureText(fps_text_slice_z, font_size);
    const fps_x_pos = config.screen_width - ui_padding - fps_text_width_val;
    const fps_y_pos = config.screen_height - ui_padding - font_size;
    ray.drawText(fps_text_slice_z, fps_x_pos, fps_y_pos, font_size, ray.Color.white);

    if (is_game_paused_val) {
        const pause_text = "PAUSED (Spacebar)";
        const pause_font_size: c_int = 20;
        const pause_text_width = ray.measureText(pause_text, pause_font_size);
        const pause_x = @divTrunc(config.screen_width - pause_text_width, 2);
        const pause_y = @divTrunc(config.screen_height - pause_font_size, 2);
        ray.drawText(pause_text, pause_x, pause_y, pause_font_size, ray.Color.yellow);
    }

    // --- Draw Pinned Stats Panel for Followed Entity/Item (Top Right) ---
    if (followed_entity_idx_val) |fe_idx| {
        if (fe_idx < world.entities.items.len) {
            const entity = world.entities.items[fe_idx];
            drawEntityStatsPanel(allocator, entity, mouse_screen_pos_val, true) catch |err| { // true for pinned
                log.err("Failed to draw PINNED entity stats panel: {s}", .{@errorName(err)});
            };
        }
    } else if (followed_item_idx_val) |fi_idx| {
        if (fi_idx < world.items.items.len) {
            const item = world.items.items[fi_idx];
            drawItemStatsPanel(allocator, item, mouse_screen_pos_val, true) catch |err| { // true for pinned
                log.err("Failed to draw PINNED item stats panel: {s}", .{@errorName(err)});
            };
        }
    }

    // --- Draw Mouse-Relative Stats Panel for Hovered Entity/Item (if not the same as followed) ---
    if (hovered_entity_idx_val) |h_idx| {
        // Only draw if not currently following this specific entity (to avoid overlap if mouse is over followed entity)
        if (followed_entity_idx_val == null or followed_entity_idx_val.? != h_idx) {
            if (h_idx < world.entities.items.len) {
                const entity = world.entities.items[h_idx];
                drawEntityStatsPanel(allocator, entity, mouse_screen_pos_val, false) catch |err| { // false for mouse-relative
                    log.err("Failed to draw HOVERED entity stats panel: {s}", .{@errorName(err)});
                };
            }
        }
    } else if (hovered_item_idx_val) |item_idx| {
        // Only draw if not currently following this specific item
        if (followed_item_idx_val == null or followed_item_idx_val.? != item_idx) {
            if (item_idx < world.items.items.len) {
                const item = world.items.items[item_idx];
                drawItemStatsPanel(allocator, item, mouse_screen_pos_val, false) catch |err| { // false for mouse-relative
                    log.err("Failed to draw HOVERED item stats panel: {s}", .{@errorName(err)});
                };
            }
        }
    }
}

pub fn checkMuteButtonClick(am: *const atlas_manager.AtlasManager, mouse_pos: ray.Vector2) bool {
    if (am.getSpriteInfo(.SpeakerUnmuted)) |sprite_info| {
        const icon_width = @as(c_int, @intFromFloat(math.round(sprite_info.source_rect.width)));
        const icon_height = @as(c_int, @intFromFloat(math.round(sprite_info.source_rect.height)));
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
