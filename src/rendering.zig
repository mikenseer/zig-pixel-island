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

// Converts terrain type to its corresponding color.
fn terrainToRaylibColor(terrain: types.TerrainType, is_overlay: bool) ray.Color {
    _ = is_overlay;
    return switch (terrain) {
        .VeryDeepWater => config.very_deep_water_color, // Added case
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
};

pub fn getEntityMetrics(entity: types.Entity) EntityMetrics {
    var w: c_int = 0;
    var h: c_int = 0;
    var make_rect = true;

    switch (entity.entity_type) {
        .Tree => {
            w = switch (entity.growth_stage) {
                0 => @as(c_int, config.seedling_art_width),
                1 => @as(c_int, config.sapling_art_width),
                2 => @as(c_int, art.small_tree_art_width),
                else => @as(c_int, art.mature_tree_art_width),
            };
            h = switch (entity.growth_stage) {
                0 => @as(c_int, config.seedling_art_height),
                1 => @as(c_int, config.sapling_art_height),
                2 => @as(c_int, art.small_tree_art_height),
                else => @as(c_int, art.mature_tree_art_height),
            };
        },
        .RockCluster => {
            w = config.rock_cluster_art_width;
            h = config.rock_cluster_art_height;
        },
        .Brush => {
            w = config.brush_art_width;
            h = config.brush_art_height;
        },
        .Player => {
            w = art.peon_art_width;
            h = art.peon_art_height;
            make_rect = false;
        },
        .Sheep => {
            w = art.sheep_art_width;
            h = art.sheep_art_height;
            make_rect = false;
        },
        .Bear => {
            w = art.bear_art_width;
            h = art.bear_art_height;
            make_rect = false;
        },
    }

    var opt_rect: ?ray.Rectangle = null;
    if (make_rect) {
        const anchor_x_offset = switch (entity.entity_type) {
            .Tree => -@divTrunc(w, 2),
            else => 0,
        };
        const anchor_y_offset = switch (entity.entity_type) {
            .Tree => -h + 1,
            else => 0,
        };
        opt_rect = ray.Rectangle{
            .x = @as(f32, @floatFromInt(entity.x + anchor_x_offset)),
            .y = @as(f32, @floatFromInt(entity.y + anchor_y_offset)),
            .width = @as(f32, @floatFromInt(w)),
            .height = @as(f32, @floatFromInt(h)),
        };
    }

    return EntityMetrics{
        .rect = opt_rect,
        .art_width = w,
        .art_height = h,
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

fn drawEntityFromAtlas(entity: types.Entity, am: *const atlas_manager.AtlasManager) void {
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
            //const metrics = getEntityMetrics(entity);

            var dest_x_f32: f32 = @as(f32, @floatFromInt(entity.x));
            var dest_y_f32: f32 = @as(f32, @floatFromInt(entity.y));

            switch (entity.entity_type) {
                .Tree => {
                    dest_x_f32 = @as(f32, @floatFromInt(entity.x)) - (sprite_info.source_rect.width / 2.0);
                    dest_y_f32 = @as(f32, @floatFromInt(entity.y)) - sprite_info.source_rect.height + 1.0;
                },
                .RockCluster, .Brush, .Player, .Sheep, .Bear => {},
            }

            const dest_pos = ray.Vector2{ .x = dest_x_f32, .y = dest_y_f32 };
            ray.drawTextureRec(am.atlas_texture, sprite_info.source_rect, dest_pos, ray.Color.white);
        } else {
            log.warn("SpriteInfo not found for SpriteId: {any}", .{id});
        }
    } else {
        log.warn("Could not determine SpriteId for entity type: {any}", .{entity.entity_type});
    }
}

pub const DrawableEntity = struct {
    entity_ptr: ?*const types.Entity = null,
    cloud_ptr: ?*const types.Cloud = null,
    sort_y: i32,
    layer: DrawLayer,
    is_cloud: bool,
    ground_elevation_normalized: f32 = 0.0,
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
        const metrics = getEntityMetrics(entity);
        var sort_y_val: i32 = entity.y;

        switch (entity.entity_type) {
            .Tree => {
                sort_y_val = entity.y;
            },
            .RockCluster, .Brush => {
                sort_y_val = entity.y + metrics.art_height - 1;
            },
            .Player, .Sheep, .Bear => {
                sort_y_val = entity.y + metrics.art_height - 1;
            },
        }

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
            drawEntityFromAtlas(entity_ref.*, atlas_manager_ptr);
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

    if (hovered_entity_idx) |h_idx| {
        if (h_idx < world.entities.items.len) {
            const entity = world.entities.items[h_idx];
            if (entity.entity_type != .Player and entity.entity_type != .Sheep and entity.entity_type != .Bear) {
                const metrics = getEntityMetrics(entity);
                if (metrics.rect) |entity_rect_for_hover| {
                    ray.drawRectangleLinesEx(entity_rect_for_hover, 1.0 / camera_ptr.zoom, ray.Color.white);
                }
            }
        }
    }
}
