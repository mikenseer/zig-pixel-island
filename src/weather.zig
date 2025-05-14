// src/weather.zig
// Manages individual cloud entities.
const std_full = @import("std");
const math = std_full.math;
const log = std_full.log;
const ray = @import("raylib");

const DefaultPrng = std_full.Random.DefaultPrng;
const RandomInterface = std_full.Random;

const config = @import("config.zig");
const types = @import("types.zig");
const ArrayList = std_full.ArrayList;
const art = @import("art.zig");

pub const CloudSystem = struct {
    allocator: std_full.mem.Allocator,
    clouds: ArrayList(types.Cloud),
    world_width: u32,
    world_height: u32,

    pub fn init(world_width_param: u32, world_height_param: u32, allocator: std_full.mem.Allocator, prng: *RandomInterface) !CloudSystem {
        var cloud_list = ArrayList(types.Cloud).init(allocator);
        errdefer cloud_list.deinit();

        log.info("Initializing CloudSystem with individual cloud entities...", .{});

        // Spawn Small Clouds
        for (0..config.num_small_clouds) |_| {
            const start_x = prng.float(f32) * @as(f32, @floatFromInt(world_width_param));
            // Distribute Y more evenly across the world height, accounting for cloud height
            const start_y = prng.float(f32) * (@as(f32, @floatFromInt(world_height_param)) - art.cloud_small_height);
            const speed = config.cloud_min_speed_x + prng.float(f32) * (config.cloud_max_speed_x - config.cloud_min_speed_x);
            try cloud_list.append(types.Cloud{
                .x = start_x,
                .y = start_y,
                .cloud_type = .SmallWhispey,
                .speed_x = speed,
            });
        }

        // Spawn Medium Clouds
        for (0..config.num_medium_clouds) |_| {
            const start_x = prng.float(f32) * @as(f32, @floatFromInt(world_width_param));
            const start_y = prng.float(f32) * (@as(f32, @floatFromInt(world_height_param)) - art.cloud_medium_height);
            const speed = config.cloud_min_speed_x + prng.float(f32) * (config.cloud_max_speed_x - config.cloud_min_speed_x) * 0.8;
            try cloud_list.append(types.Cloud{
                .x = start_x,
                .y = start_y,
                .cloud_type = .MediumFluffy,
                .speed_x = speed,
            });
        }

        // Spawn Large Clouds
        for (0..config.num_large_clouds) |_| {
            const start_x = prng.float(f32) * @as(f32, @floatFromInt(world_width_param));
            const start_y = prng.float(f32) * (@as(f32, @floatFromInt(world_height_param)) - art.cloud_large_height);
            const speed = config.cloud_min_speed_x + prng.float(f32) * (config.cloud_max_speed_x - config.cloud_min_speed_x) * 0.6;
            try cloud_list.append(types.Cloud{
                .x = start_x,
                .y = start_y,
                .cloud_type = .LargeThick,
                .speed_x = speed,
            });
        }

        log.info("CloudSystem initialized with {d} clouds.", .{cloud_list.items.len});

        return CloudSystem{
            .allocator = allocator,
            .clouds = cloud_list,
            .world_width = world_width_param,
            .world_height = world_height_param,
        };
    }

    pub fn deinit(self: *CloudSystem) void {
        self.clouds.deinit();
    }

    pub fn update(self: *CloudSystem) void {
        for (self.clouds.items) |*cloud| {
            cloud.x += cloud.speed_x;

            var cloud_art_width: f32 = 100;
            switch (cloud.cloud_type) {
                .SmallWhispey => cloud_art_width = @as(f32, @floatFromInt(art.cloud_small_width)),
                .MediumFluffy => cloud_art_width = @as(f32, @floatFromInt(art.cloud_medium_width)),
                .LargeThick => cloud_art_width = @as(f32, @floatFromInt(art.cloud_large_width)),
            }

            if (cloud.speed_x > 0 and cloud.x > @as(f32, @floatFromInt(self.world_width))) {
                cloud.x = -cloud_art_width;
            } else if (cloud.speed_x < 0 and cloud.x < -cloud_art_width) {
                cloud.x = @as(f32, @floatFromInt(self.world_width));
            }
        }
    }
};
