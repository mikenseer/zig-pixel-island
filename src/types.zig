// src/types.zig
// Defines core data structures for the game.
const std_full = @import("std");
const config = @import("config.zig");
const weather = @import("weather.zig");
const art = @import("art.zig");
const log = std_full.log;

const RandomInterface = std_full.Random;
const ray = @import("raylib");

pub const PixelColor = ray.Color;

pub const TerrainType = enum {
    VeryDeepWater,
    DeepWater,
    ShallowWater,
    Sand,
    Grass,
    Plains,
    Mountain,
    Rock,
    DirtPath,
    CobblestoneRoad,
};

pub const Tile = struct {
    base_terrain: TerrainType,
    overlay: ?TerrainType = null,
    path_wear: u8 = 0,
    fertility: u8 = 128,
};

pub const EntityType = enum {
    Player, // Peon
    Tree,
    RockCluster,
    Brush,
    Sheep,
    Bear,
};

pub const TerrainMovementRules = struct {
    can_pass: bool,
    speed_modifier: f32,
};

pub const EntityAction = enum {
    Idle,
    Wandering,
};

pub const Entity = struct {
    x: i32,
    y: i32,
    entity_type: EntityType,
    current_hp: i16 = 0,
    max_hp: i16 = 0,
    growth_stage: u8 = 0,
    time_to_next_growth: u16 = 0,
    move_cooldown_ticks: u16 = 0,
    current_action: EntityAction = .Idle,
    wander_target_x: i32 = 0,
    wander_target_y: i32 = 0,
    wander_steps_total: u8 = 0,
    wander_steps_taken: u8 = 0,

    pub fn newPlayer(x_pos: i32, y_pos: i32) Entity {
        return Entity{
            .x = x_pos,
            .y = y_pos,
            .entity_type = .Player,
            .current_hp = 1,
            .max_hp = 1,
        };
    }

    pub fn newTree(x_pos: i32, y_pos: i32, initial_growth_stage: u8) Entity {
        return Entity{
            .x = x_pos,
            .y = y_pos,
            .entity_type = .Tree,
            .current_hp = config.default_tree_hp,
            .max_hp = config.default_tree_hp,
            .growth_stage = initial_growth_stage,
            .time_to_next_growth = if (initial_growth_stage < config.max_growth_stage_tree) config.tree_growth_interval else 0,
        };
    }

    pub fn newRockCluster(x_pos: i32, y_pos: i32) Entity {
        return Entity{
            .x = x_pos,
            .y = y_pos,
            .entity_type = .RockCluster,
            .current_hp = config.default_rock_cluster_hp,
            .max_hp = config.default_rock_cluster_hp,
        };
    }

    pub fn newBrush(x_pos: i32, y_pos: i32) Entity {
        return Entity{
            .x = x_pos,
            .y = y_pos,
            .entity_type = .Brush,
            .current_hp = 10,
            .max_hp = 10,
            .growth_stage = 1,
        };
    }

    pub fn newSheep(x_pos: i32, y_pos: i32) Entity {
        return Entity{
            .x = x_pos,
            .y = y_pos,
            .entity_type = .Sheep,
            .current_hp = config.sheep_hp,
            .max_hp = config.sheep_hp,
        };
    }

    pub fn newBear(x_pos: i32, y_pos: i32) Entity {
        return Entity{
            .x = x_pos,
            .y = y_pos,
            .entity_type = .Bear,
            .current_hp = config.bear_hp,
            .max_hp = config.bear_hp,
        };
    }
};

pub const CloudType = enum {
    SmallWhispey,
    MediumFluffy,
    LargeThick,
};

pub const Cloud = struct {
    x: f32,
    y: f32,
    cloud_type: CloudType,
    speed_x: f32,
};

pub const GameWorld = struct {
    width: u32,
    height: u32,
    tiles: []Tile,
    entities: std_full.ArrayList(Entity),
    allocator: std_full.mem.Allocator,
    elevation_data: []f32 = &.{}, // Normalized elevation [0,1] for each tile

    // Baked noise maps REMOVED:
    // forest_density_map: []f32 = &.{},
    // deforestation_map: []f32 = &.{},
    // rockiness_map: []f32 = &.{},
    // brushiness_map: []f32 = &.{},

    cloud_system: weather.CloudSystem = undefined,

    pub fn init(allocator_param: std_full.mem.Allocator, w: u32, h: u32, prng: *RandomInterface) !GameWorld {
        const num_tiles = w * h;
        if (num_tiles == 0 and (w != 0 or h != 0)) return error.Overflow;
        if (w != 0 and num_tiles / w != h) return error.Overflow;

        const tile_slice = try allocator_param.alloc(Tile, num_tiles);
        errdefer allocator_param.free(tile_slice);

        const elevation_slice = try allocator_param.alloc(f32, num_tiles);
        errdefer allocator_param.free(elevation_slice);

        // Baked noise map allocations REMOVED
        // const forest_density_slice = try allocator_param.alloc(f32, num_tiles);
        // errdefer allocator_param.free(forest_density_slice);
        // const deforestation_slice = try allocator_param.alloc(f32, num_tiles);
        // errdefer allocator_param.free(deforestation_slice);
        // const rockiness_slice = try allocator_param.alloc(f32, num_tiles);
        // errdefer allocator_param.free(rockiness_slice);
        // const brushiness_slice = try allocator_param.alloc(f32, num_tiles);
        // errdefer allocator_param.free(brushiness_slice);

        for (tile_slice) |*tile| {
            tile.* = Tile{ .base_terrain = .VeryDeepWater, .fertility = 128 };
        }
        @memset(elevation_slice, @as(f32, 0.0));
        // Baked noise map memset REMOVED
        // @memset(forest_density_slice, @as(f32, 0.0));
        // @memset(deforestation_slice, @as(f32, 0.0));
        // @memset(rockiness_slice, @as(f32, 0.0));
        // @memset(brushiness_slice, @as(f32, 0.0));

        const cloud_sys = try weather.CloudSystem.init(w, h, allocator_param, prng);

        return GameWorld{
            .width = w,
            .height = h,
            .tiles = tile_slice,
            .entities = std_full.ArrayList(Entity).init(allocator_param),
            .allocator = allocator_param,
            .elevation_data = elevation_slice,
            // Baked noise map fields REMOVED
            // .forest_density_map = forest_density_slice,
            // .deforestation_map = deforestation_slice,
            // .rockiness_map = rockiness_slice,
            // .brushiness_map = brushiness_slice,
            .cloud_system = cloud_sys,
        };
    }

    pub fn deinit(self: *GameWorld) void {
        self.cloud_system.deinit();
        self.entities.deinit();
        self.allocator.free(self.tiles);
        if (self.elevation_data.len > 0) self.allocator.free(self.elevation_data);
        // Baked noise map deallocations REMOVED
        // if (self.forest_density_map.len > 0) self.allocator.free(self.forest_density_map);
        // if (self.deforestation_map.len > 0) self.allocator.free(self.deforestation_map);
        // if (self.rockiness_map.len > 0) self.allocator.free(self.rockiness_map);
        // if (self.brushiness_map.len > 0) self.allocator.free(self.brushiness_map);

        self.tiles = &.{};
        self.elevation_data = &.{};
        // Baked noise map resets REMOVED
        // self.forest_density_map = &.{};
        // self.deforestation_map = &.{};
        // self.rockiness_map = &.{};
        // self.brushiness_map = &.{};
    }

    pub fn getTile(self: *const GameWorld, x: i32, y: i32) ?*const Tile {
        if (x < 0 or @as(u32, @intCast(x)) >= self.width or
            y < 0 or @as(u32, @intCast(y)) >= self.height)
        {
            return null;
        }
        return &self.tiles[@as(usize, @intCast(y)) * self.width + @as(usize, @intCast(x))];
    }

    pub fn getTileMutable(self: *GameWorld, x: i32, y: i32) ?*Tile {
        if (x < 0 or @as(u32, @intCast(x)) >= self.width or
            y < 0 or @as(u32, @intCast(y)) >= self.height)
        {
            return null;
        }
        return &self.tiles[@as(usize, @intCast(y)) * self.width + @as(usize, @intCast(x))];
    }

    pub fn getTerrainMovementRules(
        self: *const GameWorld,
        entity_type: EntityType,
        target_tile_x: i32,
        target_tile_y: i32,
        entity_art_height: u32,
    ) TerrainMovementRules {
        var rules: TerrainMovementRules = .{ .can_pass = false, .speed_modifier = 1.0 };

        const target_tile_opt = self.getTile(target_tile_x, target_tile_y);
        if (target_tile_opt == null) return rules;
        const target_terrain = target_tile_opt.?.base_terrain;

        if (self.isTileOccupiedByStaticEntity(target_tile_x, target_tile_y)) {
            if (entity_type == .Player and (target_terrain == .DirtPath or target_terrain == .CobblestoneRoad)) {} else {
                return rules;
            }
        }

        if (entity_art_height > 1) {
            const foot_y = target_tile_y + @as(i32, @intCast(entity_art_height)) - 1;
            if (self.getTile(target_tile_x, foot_y)) |foot_tile| {
                const foot_terrain = foot_tile.base_terrain;
                switch (entity_type) {
                    .Player => if (foot_terrain == .VeryDeepWater or foot_terrain == .DeepWater or foot_terrain == .Mountain or foot_terrain == .Rock) return rules,
                    .Sheep => if (foot_terrain == .VeryDeepWater or foot_terrain == .DeepWater or foot_terrain == .ShallowWater or foot_terrain == .Rock) return rules,
                    .Bear => if (foot_terrain == .Mountain or foot_terrain == .Rock) return rules,
                    else => {},
                }
            } else {
                return rules;
            }
        }

        switch (entity_type) {
            .Player => {
                rules.can_pass = switch (target_terrain) {
                    .VeryDeepWater, .DeepWater, .Mountain, .Rock => false,
                    else => true,
                };
                if (rules.can_pass and target_terrain == .ShallowWater) {
                    rules.speed_modifier = config.peon_shallows_speed_modifier;
                }
            },
            .Sheep => {
                rules.can_pass = switch (target_terrain) {
                    .VeryDeepWater, .DeepWater, .ShallowWater, .Rock, .Mountain => false,
                    else => true,
                };
            },
            .Bear => {
                rules.can_pass = switch (target_terrain) {
                    .VeryDeepWater, .Mountain, .Rock => false,
                    else => true,
                };
                if (rules.can_pass and target_terrain == .DeepWater) {
                    rules.speed_modifier = config.bear_deep_water_speed_modifier;
                }
            },
            .Tree, .RockCluster, .Brush => rules.can_pass = false,
        }
        return rules;
    }

    pub fn isTileOccupiedByStaticEntity(self: *const GameWorld, x: i32, y: i32) bool {
        for (self.entities.items) |entity| {
            if (entity.x == x and entity.y == y) {
                switch (entity.entity_type) {
                    .Tree, .RockCluster, .Brush => return true,
                    else => {},
                }
            }
        }
        return false;
    }

    pub fn addEntityRandomSpawn(
        self: *GameWorld,
        entity_type: EntityType,
        prng: *RandomInterface,
        initial_growth_stage_opt: ?u8,
    ) !void {
        var spawn_x: i32 = -1;
        var spawn_y: i32 = -1;
        var attempts: u32 = 0;
        const max_attempts: u32 = (self.width * self.height / 2) + 200;

        while (attempts < max_attempts) : (attempts += 1) {
            const try_x = prng.intRangeAtMost(i32, 0, @as(i32, @intCast(self.width)) - 1);
            const try_y = prng.intRangeAtMost(i32, 0, @as(i32, @intCast(self.height)) - 1);

            var can_spawn_here = false;
            if (self.getTile(try_x, try_y)) |tile_at_spawn| {
                const art_h_for_check: u32 = switch (entity_type) {
                    .Player => config.player_height_pixels,
                    .Sheep => art.sheep_art_height,
                    .Bear => art.bear_art_height,
                    else => 1,
                };
                const rules = self.getTerrainMovementRules(entity_type, try_x, try_y, art_h_for_check);
                switch (entity_type) {
                    .Player, .Sheep, .Bear => {
                        if (rules.can_pass) {
                            can_spawn_here = switch (tile_at_spawn.base_terrain) {
                                .Grass, .Sand, .Plains => true,
                                else => false,
                            };
                        }
                    },
                    .Tree => {
                        can_spawn_here = (tile_at_spawn.base_terrain == .Grass and !self.isTileOccupiedByStaticEntity(try_x, try_y));
                    },
                    .RockCluster => {
                        can_spawn_here = (tile_at_spawn.base_terrain != .DeepWater and
                            tile_at_spawn.base_terrain != .ShallowWater and
                            tile_at_spawn.base_terrain != .VeryDeepWater and
                            !self.isTileOccupiedByStaticEntity(try_x, try_y));
                    },
                    .Brush => {
                        can_spawn_here = (tile_at_spawn.base_terrain == .Plains or
                            tile_at_spawn.base_terrain == .Grass or
                            tile_at_spawn.base_terrain == .Sand) and
                            !self.isTileOccupiedByStaticEntity(try_x, try_y);
                    },
                }
            }

            if (can_spawn_here) {
                spawn_x = try_x;
                spawn_y = try_y;
                break;
            }
        }

        if (spawn_x == -1) {
            log.warn("addEntityRandomSpawn: No spawn location found for {any} after {d} attempts.", .{ entity_type, max_attempts });
            return error.NoSpawnLocationFound;
        }

        const new_entity = switch (entity_type) {
            .Player => Entity.newPlayer(spawn_x, spawn_y),
            .Tree => Entity.newTree(spawn_x, spawn_y, initial_growth_stage_opt orelse 0),
            .RockCluster => Entity.newRockCluster(spawn_x, spawn_y),
            .Brush => Entity.newBrush(spawn_x, spawn_y),
            .Sheep => Entity.newSheep(spawn_x, spawn_y),
            .Bear => Entity.newBear(spawn_x, spawn_y),
        };
        try self.entities.append(new_entity);
    }
};
