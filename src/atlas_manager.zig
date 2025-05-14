// src/atlas_manager.zig
// Manages the creation and querying of a texture atlas for game sprites.
const std = @import("std");
const ray = @import("raylib");
const types = @import("types.zig");
const art = @import("art.zig");
const config = @import("config.zig");
const log = std.log;

pub const SpriteId = enum {
    TreeSeedling,
    TreeSapling,
    TreeSmall,
    TreeMature,
    RockCluster,
    Brush,
    Peon,

    CloudSmall,
    CloudMedium,
    CloudLarge,

    SpeakerUnmuted,
    SpeakerMuted,
    WoodIcon,
    RockIcon,
    BrushItemIcon,
    // ZiggyLogo removed

    Sheep, // Added
    Bear, // Added
};

pub const SpriteInfo = struct {
    source_rect: ray.Rectangle,
};

pub const AtlasManager = struct {
    atlas_texture: ray.Texture2D,
    sprite_map: std.HashMap(SpriteId, SpriteInfo, std.hash_map.AutoContext(SpriteId), std.hash_map.default_max_load_percentage),

    const ArtPieceMetadata = struct {
        id: SpriteId,
        width: c_int,
        height: c_int,
    };

    pub fn init(allocator: std.mem.Allocator) !AtlasManager {
        var self: AtlasManager = .{
            .atlas_texture = undefined,
            .sprite_map = std.HashMap(SpriteId, SpriteInfo, std.hash_map.AutoContext(SpriteId), std.hash_map.default_max_load_percentage).init(allocator),
        };

        const art_pieces_meta = [_]ArtPieceMetadata{
            .{ .id = .TreeSeedling, .width = config.seedling_art_width, .height = config.seedling_art_height },
            .{ .id = .TreeSapling, .width = config.sapling_art_width, .height = config.sapling_art_height },
            .{ .id = .TreeSmall, .width = art.small_tree_art_width, .height = art.small_tree_art_height },
            .{ .id = .TreeMature, .width = art.mature_tree_art_width, .height = art.mature_tree_art_height },
            .{ .id = .RockCluster, .width = config.rock_cluster_art_width, .height = config.rock_cluster_art_height },
            .{ .id = .Brush, .width = config.brush_art_width, .height = config.brush_art_height },
            .{ .id = .Peon, .width = art.peon_art_width, .height = art.peon_art_height },
            .{ .id = .CloudSmall, .width = art.cloud_small_width, .height = art.cloud_small_height },
            .{ .id = .CloudMedium, .width = art.cloud_medium_width, .height = art.cloud_medium_height },
            .{ .id = .CloudLarge, .width = art.cloud_large_width, .height = art.cloud_large_height },
            .{ .id = .SpeakerUnmuted, .width = art.speaker_icon_width, .height = art.speaker_icon_height },
            .{ .id = .SpeakerMuted, .width = art.speaker_icon_width, .height = art.speaker_icon_height },
            .{ .id = .WoodIcon, .width = art.mature_tree_art_width, .height = art.mature_tree_art_height },
            .{ .id = .RockIcon, .width = config.rock_cluster_art_width, .height = config.rock_cluster_art_height },
            .{ .id = .BrushItemIcon, .width = config.brush_art_width, .height = config.brush_art_height },
            .{ .id = .Sheep, .width = art.sheep_art_width, .height = art.sheep_art_height }, // Added Sheep
            .{ .id = .Bear, .width = art.bear_art_width, .height = art.bear_art_height }, // Added Bear
        };

        const atlas_width_cint: c_int = 1024;
        const atlas_height_cint: c_int = 1024;
        var atlas_image = ray.genImageColor(atlas_width_cint, atlas_height_cint, ray.Color.blank);
        defer ray.unloadImage(atlas_image);

        var current_x: c_int = 0;
        var current_y: c_int = 0;
        var max_row_height: c_int = 0;
        const padding: c_int = 1;

        for (art_pieces_meta) |piece_meta| {
            if (piece_meta.width == 0 or piece_meta.height == 0) {
                log.warn("Skipping zero-dimension art piece: {any}", .{piece_meta.id});
                continue;
            }

            if (current_x + piece_meta.width + padding > atlas_width_cint) {
                current_x = 0;
                current_y += max_row_height + padding;
                max_row_height = 0;
            }

            if (current_y + piece_meta.height + padding > atlas_height_cint) {
                log.err("Atlas ran out of space for sprite {any}! Increase atlas size or use a better packer.", .{piece_meta.id});
                return error.AtlasOutOfSpace;
            }

            copyArtToAtlas(&atlas_image, current_x, current_y, piece_meta);

            try self.sprite_map.put(piece_meta.id, .{
                .source_rect = .{
                    .x = @as(f32, @floatFromInt(current_x)),
                    .y = @as(f32, @floatFromInt(current_y)),
                    .width = @as(f32, @floatFromInt(piece_meta.width)),
                    .height = @as(f32, @floatFromInt(piece_meta.height)),
                },
            });

            current_x += piece_meta.width + padding;
            if (piece_meta.height > max_row_height) {
                max_row_height = piece_meta.height;
            }
        }

        self.atlas_texture = try ray.loadTextureFromImage(atlas_image);
        log.info("Texture atlas generated successfully.", .{});
        return self;
    }

    fn copyArtToAtlas(image: *ray.Image, dest_x: c_int, dest_y: c_int, piece_meta: ArtPieceMetadata) void {
        switch (piece_meta.id) {
            .TreeSeedling => drawSpecificArt(image, dest_x, dest_y, config.seedling_art_height, config.seedling_art_width, art.seedling_pixels),
            .TreeSapling => drawSpecificArt(image, dest_x, dest_y, config.sapling_art_height, config.sapling_art_width, art.sapling_pixels),
            .TreeSmall => drawSpecificArt(image, dest_x, dest_y, art.small_tree_art_height, art.small_tree_art_width, art.small_tree_pixels),
            .TreeMature => drawSpecificArt(image, dest_x, dest_y, art.mature_tree_art_height, art.mature_tree_art_width, art.mature_tree_pixels),
            .RockCluster => drawSpecificArt(image, dest_x, dest_y, config.rock_cluster_art_height, config.rock_cluster_art_width, art.basic_rock_cluster_pixels),
            .Brush => drawSpecificArt(image, dest_x, dest_y, config.brush_art_height, config.brush_art_width, art.basic_brush_pixels),
            .Peon => drawSpecificArt(image, dest_x, dest_y, art.peon_art_height, art.peon_art_width, art.peon_pixels),
            .CloudSmall => drawSpecificArt(image, dest_x, dest_y, art.cloud_small_height, art.cloud_small_width, art.cloud_small_pixels),
            .CloudMedium => drawSpecificArt(image, dest_x, dest_y, art.cloud_medium_height, art.cloud_medium_width, art.cloud_medium_pixels),
            .CloudLarge => drawSpecificArt(image, dest_x, dest_y, art.cloud_large_height, art.cloud_large_width, art.cloud_large_pixels),
            .SpeakerUnmuted => drawSpecificArt(image, dest_x, dest_y, art.speaker_icon_height, art.speaker_icon_width, art.speaker_unmuted_pixels),
            .SpeakerMuted => drawSpecificArt(image, dest_x, dest_y, art.speaker_icon_height, art.speaker_icon_width, art.speaker_muted_pixels),
            .WoodIcon => drawSpecificArt(image, dest_x, dest_y, art.mature_tree_art_height, art.mature_tree_art_width, art.mature_tree_pixels),
            .RockIcon => drawSpecificArt(image, dest_x, dest_y, config.rock_cluster_art_height, config.rock_cluster_art_width, art.basic_rock_cluster_pixels),
            .BrushItemIcon => drawSpecificArt(image, dest_x, dest_y, config.brush_art_height, config.brush_art_width, art.basic_brush_pixels),
            .Sheep => drawSpecificArt(image, dest_x, dest_y, art.sheep_art_height, art.sheep_art_width, art.sheep_pixels), // Added Sheep
            .Bear => drawSpecificArt(image, dest_x, dest_y, art.bear_art_height, art.bear_art_width, art.bear_pixels), // Added Bear
        }
    }

    fn drawSpecificArt(
        image: *ray.Image,
        dest_x: c_int,
        dest_y: c_int,
        comptime art_h: comptime_int,
        comptime art_w: comptime_int,
        pixels: [art_h][art_w]?types.PixelColor,
    ) void {
        for (pixels, 0..) |row, y_offset_usize| {
            const y_offset: c_int = @intCast(y_offset_usize);
            for (row, 0..) |pixel_opt, x_offset_usize| {
                const x_offset: c_int = @intCast(x_offset_usize);
                if (pixel_opt) |px_color| {
                    ray.imageDrawPixel(image, dest_x + x_offset, dest_y + y_offset, px_color);
                }
            }
        }
    }

    pub fn deinit(self: *AtlasManager) void {
        self.sprite_map.deinit();
        ray.unloadTexture(self.atlas_texture);
    }

    pub fn getSpriteInfo(self: *const AtlasManager, id: SpriteId) ?SpriteInfo {
        return self.sprite_map.get(id);
    }
};
