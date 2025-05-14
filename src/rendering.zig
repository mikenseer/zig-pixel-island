// src/rendering.zig
// Handles all drawing logic for the game world and entities.
const std_full = @import("std");
const ray = @import("raylib");
const types = @import("types.zig");
const config = @import("config.zig");
const art = @import("art.zig");
const math = std_full.math;
const sort_module = std_full.sort;
const ArrayList = std_full.ArrayList;
const Allocator = std_full.mem.Allocator;
const log = std_full.log;
const atlas_manager = @import("atlas_manager.zig");
const items = @import("items.zig");

fn terrainToRaylibColor(terrain: types.TerrainType, is_overlay: bool) ray.Color {
    _ = is_overlay;
    return switch (terrain) {
        .VeryDeepWater => config.very_deep_water_color,
        .DeepWater => config.deep_water_color,
        .ShallowWater => config.shallow_water_color,
        .Sand => config.sand_color,
        .Grass => config.grass_color,
        .Plains => config.plains_color,
        .Mountain => config.mountain_color,
        .Rock => config.rock_terrain_color,
        .DirtPath => config.dirt_path_color,
        .CobblestoneRoad => config.cobblestone_road_color,
    };
}

pub const EntityMetrics = struct {
    rect: ?ray.Rectangle,
    art_width: c_int,
    art_height: c_int,
    anchor_x_factor: f32,
    anchor_y_factor: f32,
};

pub fn getEntityMetrics(entity: types.Entity, am: *const atlas_manager.AtlasManager) EntityMetrics {
    var w: c_int = 0;
    var h: c_int = 0;
    var ax: f32 = 0.0;
    var ay: f32 = 0.0;

    const sprite_id_opt: ?atlas_manager.SpriteId = switch (entity.entity_type) {
        .Tree => switch (entity.growth_stage) {
            0 => .TreeSeedling,
            1 => .TreeSapling,
            2 => .TreeSmall,
            else => .TreeMature,
        },
        .RockCluster => .RockCluster,
        .Brush => .Brush,
        .Player => .Peon,
        .Sheep => .Sheep,
        .Bear => .Bear,
    };

    if (sprite_id_opt) |sprite_id| {
        if (am.getSpriteInfo(sprite_id)) |sprite_info| {
            w = @as(c_int, @intFromFloat(math.round(sprite_info.source_rect.width)));
            h = @as(c_int, @intFromFloat(math.round(sprite_info.source_rect.height)));
        } else {
            log.warn("SpriteInfo not found for {any} in getEntityMetrics, using fallback dimensions.", .{sprite_id});
            w = 1;
            h = 1;
        }
    } else {
        log.warn("Could not determine SpriteId for entity type {any} in getEntityMetrics.", .{entity.entity_type});
        w = 1;
        h = 1;
    }

    switch (entity.entity_type) {
        .Tree => {
            ax = 0.5;
            ay = 1.0;
        },
        .RockCluster, .Brush => {
            ax = 0.0;
            ay = 0.0;
        },
        .Player, .Sheep, .Bear => {
            ax = 0.5;
            ay = 1.0;
        },
    }

    const rect_x = @as(f32, @floatFromInt(entity.x)) - (@as(f32, @floatFromInt(w)) * ax);
    const rect_y = @as(f32, @floatFromInt(entity.y)) - (@as(f32, @floatFromInt(h)) * ay);

    const opt_rect = ray.Rectangle{
        .x = rect_x,
        .y = rect_y,
        .width = @as(f32, @floatFromInt(w)),
        .height = @as(f32, @floatFromInt(h)),
    };

    return EntityMetrics{
        .rect = opt_rect,
        .art_width = w,
        .art_height = h,
        .anchor_x_factor = ax,
        .anchor_y_factor = ay,
    };
}

pub fn redrawStaticWorldTexture(world: *const types.GameWorld, target_texture: ray.RenderTexture2D) void {
    ray.beginTextureMode(target_texture);
    defer ray.endTextureMode();
    ray.clearBackground(ray.Color.blank);
    for (0..world.height) |y_u32| {
        for (0..world.width) |x_u32| {
            const ix: c_int = @intCast(x_u32);
            const iy: c_int = @intCast(y_u32);
            if (world.getTile(ix, iy)) |tile| {
                ray.drawRectangle(ix, iy, 1, 1, terrainToRaylibColor(tile.base_terrain, false));
                if (tile.overlay) |overlay_type| {
                    ray.drawRectangle(ix, iy, 1, 1, terrainToRaylibColor(overlay_type, true));
                }
            }
        }
    }
}

fn drawEntityFromAtlas(entity: types.Entity, am: *const atlas_manager.AtlasManager, metrics: EntityMetrics) void {
    const sprite_id: ?atlas_manager.SpriteId = switch (entity.entity_type) {
        .Tree => switch (entity.growth_stage) {
            0 => .TreeSeedling,
            1 => .TreeSapling,
            2 => .TreeSmall,
            else => .TreeMature,
        },
        .RockCluster => .RockCluster,
        .Brush => .Brush,
        .Player => .Peon,
        .Sheep => .Sheep,
        .Bear => .Bear,
    };

    if (sprite_id) |id| {
        if (am.getSpriteInfo(id)) |sprite_info| {
            if (metrics.rect) |dest_rect| {
                const dest_pos = ray.Vector2{ .x = dest_rect.x, .y = dest_rect.y };
                ray.drawTextureRec(am.atlas_texture, sprite_info.source_rect, dest_pos, ray.Color.white);
            } else {
                log.warn("Metrics rect not found for drawing entity {any}", .{id});
            }
        } else {
            log.warn("SpriteInfo not found for SpriteId: {any}", .{id});
        }
    } else {
        log.warn("Could not determine SpriteId for entity type: {any}", .{entity.entity_type});
    }
}

pub fn drawItems(world: *const types.GameWorld, am: *const atlas_manager.AtlasManager) void {
    for (world.items.items) |item| {
        // CORRECTED: Call getSpriteIdForItem via the AtlasManager struct
        const sprite_id = atlas_manager.AtlasManager.getSpriteIdForItem(item.item_type);
        if (am.getSpriteInfo(sprite_id)) |sprite_info| {
            const item_w = sprite_info.source_rect.width;
            const item_h = sprite_info.source_rect.height;
            const dest_x = @as(f32, @floatFromInt(item.x)) + 0.5 - (item_w / 2.0);
            const dest_y = @as(f32, @floatFromInt(item.y)) + 0.5 - (item_h / 2.0);
            const dest_pos = ray.Vector2{ .x = dest_x, .y = dest_y };
            ray.drawTextureRec(am.atlas_texture, sprite_info.source_rect, dest_pos, ray.Color.white);
        } else {
            const fallback_color = switch (item.item_type) {
                .Meat => ray.Color.red,
                .BrushResource => ray.Color.yellow,
                .Log => ray.Color.brown,
                .RockItem => ray.Color.gray,
                .CorpseSheep, .CorpseBear => ray.Color.dark_gray,
            };
            ray.drawPixel(item.x, item.y, fallback_color);
            log.warn("SpriteInfo not found for item type {any}, drawing fallback pixel.", .{item.item_type});
        }
    }
}

pub const DrawableEntity = struct {
    entity_ptr: ?*const types.Entity = null,
    cloud_ptr: ?*const types.Cloud = null,
    sort_y: i32,
    layer: DrawLayer,
    is_cloud: bool,
    ground_elevation_normalized: f32 = 0.0,
    metrics: ?EntityMetrics = null,
};

const DrawLayer = enum(u8) {
    Rock,
    Brush,
    Tree,
    Sheep,
    Bear,
    Player,
    Cloud,
};

fn lessThanDrawableEntities(context: void, a: DrawableEntity, b: DrawableEntity) bool {
    _ = context;
    if (a.sort_y < b.sort_y) return true;
    if (a.sort_y > b.sort_y) return false;
    if (@intFromEnum(a.layer) < @intFromEnum(b.layer)) return true;
    if (@intFromEnum(a.layer) > @intFromEnum(b.layer)) return false;
    if (a.entity_ptr != null and b.entity_ptr != null) {
        return @intFromPtr(a.entity_ptr) < @intFromPtr(b.entity_ptr);
    } else if (a.cloud_ptr != null and b.cloud_ptr != null) {
        return @intFromPtr(a.cloud_ptr) < @intFromPtr(b.cloud_ptr);
    }
    return false;
}

pub fn drawDynamicElementsAndOverlays(
    world: *const types.GameWorld,
    camera_ptr: *const ray.Camera2D,
    hovered_entity_idx: ?usize,
    allocator: Allocator,
    atlas_manager_ptr: *const atlas_manager.AtlasManager,
    draw_list: *ArrayList(DrawableEntity),
) void {
    _ = allocator;
    draw_list.shrinkRetainingCapacity(0);

    for (world.entities.items) |*entity_ptr| {
        const entity = entity_ptr.*;
        const metrics = getEntityMetrics(entity, atlas_manager_ptr);
        var sort_y_val: i32 = entity.y;

        sort_y_val = entity.y + @as(i32, @intFromFloat(math.round(@as(f32, @floatFromInt(metrics.art_height)) * (1.0 - metrics.anchor_y_factor))));

        const layer_val: DrawLayer = switch (entity.entity_type) {
            .RockCluster => .Rock,
            .Brush => .Brush,
            .Tree => .Tree,
            .Player => .Player,
            .Sheep => .Sheep,
            .Bear => .Bear,
        };

        var entity_ground_elevation: f32 = 0.0;
        if (entity.x >= 0 and @as(u32, @intCast(entity.x)) < world.width and
            entity.y >= 0 and @as(u32, @intCast(entity.y)) < world.height)
        {
            const elevation_idx = @as(usize, @intCast(entity.y)) * world.width + @as(usize, @intCast(entity.x));
            if (elevation_idx < world.elevation_data.len) {
                entity_ground_elevation = world.elevation_data[elevation_idx];
            }
        }

        draw_list.append(.{
            .entity_ptr = entity_ptr,
            .cloud_ptr = null,
            .sort_y = sort_y_val,
            .layer = layer_val,
            .is_cloud = false,
            .ground_elevation_normalized = entity_ground_elevation,
            .metrics = metrics,
        }) catch |err| {
            log.err("Failed to append entity to draw_list: {s}", .{@errorName(err)});
        };
    }

    for (world.cloud_system.clouds.items) |*cloud_ptr| {
        const cloud = cloud_ptr.*;
        const cloud_art_height: c_int = switch (cloud.cloud_type) {
            .SmallWhispey => art.cloud_small_height,
            .MediumFluffy => art.cloud_medium_height,
            .LargeThick => art.cloud_large_height,
        };
        draw_list.append(.{
            .entity_ptr = null,
            .cloud_ptr = cloud_ptr,
            .sort_y = @as(i32, @intFromFloat(cloud.y)) + cloud_art_height - 1,
            .layer = .Cloud,
            .is_cloud = true,
            .ground_elevation_normalized = 1.0,
            .metrics = null,
        }) catch |err| {
            log.err("Failed to append cloud to draw_list: {s}", .{@errorName(err)});
        };
    }

    std_full.sort.pdq(DrawableEntity, draw_list.items, {}, lessThanDrawableEntities);

    for (draw_list.items) |drawable| {
        if (drawable.is_cloud) {
            if (drawable.cloud_ptr) |cloud| {
                const cloud_sprite_id: atlas_manager.SpriteId = switch (cloud.cloud_type) {
                    .SmallWhispey => .CloudSmall,
                    .MediumFluffy => .CloudMedium,
                    .LargeThick => .CloudLarge,
                };
                if (atlas_manager_ptr.getSpriteInfo(cloud_sprite_id)) |sprite_info| {
                    const dest_pos = ray.Vector2{ .x = cloud.x, .y = cloud.y };
                    ray.drawTextureRec(atlas_manager_ptr.atlas_texture, sprite_info.source_rect, dest_pos, ray.Color.white);
                }
            }
        } else if (drawable.entity_ptr) |entity_ref| {
            if (drawable.metrics) |metrics_val| {
                if (drawable.ground_elevation_normalized < config.cloud_render_height_threshold_normalized) {
                    drawEntityFromAtlas(entity_ref.*, atlas_manager_ptr, metrics_val);
                }
            }
        }
    }

    const view_buffer_mountain: i32 = config.cloud_offscreen_buffer;
    const cam_world_top_left_mountain = ray.getScreenToWorld2D(.{ .x = 0, .y = 0 }, camera_ptr.*);
    const cam_world_bottom_right_mountain = ray.getScreenToWorld2D(.{ .x = @as(f32, @floatFromInt(config.screen_width)), .y = @as(f32, @floatFromInt(config.screen_height)) }, camera_ptr.*);

    const start_draw_x_mountain = @max(0, @as(i32, @intFromFloat(cam_world_top_left_mountain.x)) - view_buffer_mountain);
    const end_draw_x_mountain = @min(@as(i32, @intCast(world.width)), @as(i32, @intFromFloat(cam_world_bottom_right_mountain.x)) + view_buffer_mountain);
    const start_draw_y_mountain = @max(0, @as(i32, @intFromFloat(cam_world_top_left_mountain.y)) - view_buffer_mountain);
    const end_draw_y_mountain = @min(@as(i32, @intCast(world.height)), @as(i32, @intFromFloat(cam_world_bottom_right_mountain.y)) + view_buffer_mountain);

    var iy_mountain: i32 = start_draw_y_mountain;
    while (iy_mountain < end_draw_y_mountain) : (iy_mountain += 1) {
        var ix_mountain: i32 = start_draw_x_mountain;
        while (ix_mountain < end_draw_x_mountain) : (ix_mountain += 1) {
            if (ix_mountain >= 0 and @as(u32, @intCast(ix_mountain)) < world.width and
                iy_mountain >= 0 and @as(u32, @intCast(iy_mountain)) < world.height)
            {
                const elevation_index = @as(usize, @intCast(iy_mountain)) * world.width + @as(usize, @intCast(ix_mountain));
                if (elevation_index < world.elevation_data.len) {
                    const elevation = world.elevation_data[elevation_index];
                    if (elevation >= config.cloud_render_height_threshold_normalized) {
                        if (world.getTile(ix_mountain, iy_mountain)) |tile| {
                            ray.drawRectangle(ix_mountain, iy_mountain, 1, 1, terrainToRaylibColor(tile.base_terrain, false));
                            if (tile.overlay) |overlay_type| {
                                ray.drawRectangle(ix_mountain, iy_mountain, 1, 1, terrainToRaylibColor(overlay_type, true));
                            }
                        }
                    }
                }
            }
        }
    }
    for (draw_list.items) |drawable| {
        if (!drawable.is_cloud and drawable.entity_ptr != null) {
            if (drawable.metrics) |metrics_val| {
                if (drawable.ground_elevation_normalized >= config.cloud_render_height_threshold_normalized) {
                    drawEntityFromAtlas(drawable.entity_ptr.?.*, atlas_manager_ptr, metrics_val);
                }
            }
        }
    }

    if (hovered_entity_idx) |h_idx| {
        if (h_idx < world.entities.items.len) {
            const entity = world.entities.items[h_idx];
            var metrics_for_hover: ?EntityMetrics = null;
            for (draw_list.items) |*item| {
                if (item.entity_ptr != null and @intFromPtr(item.entity_ptr) == @intFromPtr(&world.entities.items[h_idx])) {
                    metrics_for_hover = item.metrics;
                    break;
                }
            }
            if (metrics_for_hover == null) {
                metrics_for_hover = getEntityMetrics(entity, atlas_manager_ptr);
            }

            if (metrics_for_hover.?.rect) |entity_rect_for_hover| {
                var line_thickness: f32 = 1.0;
                if (camera_ptr.zoom != 0) {
                    line_thickness = 1.0 / camera_ptr.zoom;
                }
                const outline_color = switch (entity.entity_type) {
                    .Player, .Sheep, .Bear => config.ai_selection_outline_color,
                    .Tree, .RockCluster, .Brush => config.static_selection_outline_color,
                };
                ray.drawRectangleLinesEx(entity_rect_for_hover, line_thickness, outline_color);
            }
        }
    }
}
