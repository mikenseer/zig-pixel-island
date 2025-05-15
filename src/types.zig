// src/types.zig
// Defines core data structures for the game.
const std_full = @import("std");
const config = @import("config.zig");
const weather = @import("weather.zig");
// const art = @import("art.zig"); // No longer directly needed for art dimensions here
const items_module = @import("items.zig"); // Renamed to avoid conflict
const inventory = @import("inventory.zig");
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
    SeekingFood,
    Hunting,
    Attacking,
    Eating,
    PickingUpItem,
    Fleeing,
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
    current_action_timer: u16 = 0,
    attack_cooldown: u16 = 0,
    target_entity_idx: ?usize = null,
    target_item_idx: ?usize = null,
    wander_target_x: i32 = 0,
    wander_target_y: i32 = 0,
    wander_steps_total: u8 = 0,
    wander_steps_taken: u8 = 0,
    hp_decay_timer: u16 = 0,
    inventory: [config.max_carry_slots]inventory.CarriedItemSlot,
    processed_death_drops: bool = false,
    must_complete_wander_step: bool = false,

    pub fn newPlayer(x_pos: i32, y_pos: i32) Entity {
        var e = Entity{
            .x = x_pos,
            .y = y_pos,
            .entity_type = .Player,
            .current_hp = config.peon_initial_hp,
            .max_hp = config.peon_initial_hp,
            .hp_decay_timer = config.hp_decay_interval,
            .inventory = undefined,
            .processed_death_drops = false,
            .must_complete_wander_step = false,
        };
        for (&e.inventory) |*slot| {
            slot.* = .{};
        }
        return e;
    }

    pub fn newTree(x_pos: i32, y_pos: i32, initial_growth_stage: u8) Entity {
        var e = Entity{
            .x = x_pos,
            .y = y_pos,
            .entity_type = .Tree,
            .current_hp = config.default_tree_hp,
            .max_hp = config.default_tree_hp,
            .growth_stage = initial_growth_stage,
            .time_to_next_growth = if (initial_growth_stage < config.max_growth_stage_tree) config.tree_growth_interval else 0,
            .inventory = undefined,
            .processed_death_drops = false,
            .must_complete_wander_step = false,
        };
        for (&e.inventory) |*slot| {
            slot.* = .{};
        }
        return e;
    }

    pub fn newRockCluster(x_pos: i32, y_pos: i32) Entity {
        var e = Entity{
            .x = x_pos,
            .y = y_pos,
            .entity_type = .RockCluster,
            .current_hp = config.default_rock_cluster_hp,
            .max_hp = config.default_rock_cluster_hp,
            .inventory = undefined,
            .processed_death_drops = false,
            .must_complete_wander_step = false,
        };
        for (&e.inventory) |*slot| {
            slot.* = .{};
        }
        return e;
    }

    pub fn newBrush(x_pos: i32, y_pos: i32) Entity {
        var e = Entity{
            .x = x_pos,
            .y = y_pos,
            .entity_type = .Brush,
            .current_hp = config.brush_initial_hp,
            .max_hp = config.brush_initial_hp,
            .growth_stage = 1,
            .inventory = undefined,
            .processed_death_drops = false,
            .must_complete_wander_step = false,
        };
        for (&e.inventory) |*slot| {
            slot.* = .{};
        }
        return e;
    }

    pub fn newSheep(x_pos: i32, y_pos: i32) Entity {
        var e = Entity{
            .x = x_pos,
            .y = y_pos,
            .entity_type = .Sheep,
            .current_hp = config.sheep_hp,
            .max_hp = config.sheep_hp,
            .hp_decay_timer = config.hp_decay_interval,
            .inventory = undefined,
            .processed_death_drops = false,
            .must_complete_wander_step = false,
        };
        for (&e.inventory) |*slot| {
            slot.* = .{};
        }
        return e;
    }

    pub fn newBear(x_pos: i32, y_pos: i32) Entity {
        var e = Entity{
            .x = x_pos,
            .y = y_pos,
            .entity_type = .Bear,
            .current_hp = config.bear_hp,
            .max_hp = config.bear_hp,
            .hp_decay_timer = config.hp_decay_interval,
            .inventory = undefined,
            .processed_death_drops = false,
            .must_complete_wander_step = false,
        };
        for (&e.inventory) |*slot| {
            slot.* = .{};
        }
        return e;
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

pub const WorldPos = struct { x: i32, y: i32 };

pub const GameWorld = struct {
    width: u32,
    height: u32,
    tiles: []Tile,
    entities: std_full.ArrayList(Entity),
    items: std_full.ArrayList(items_module.Item), // Using items_module.Item
    allocator: std_full.mem.Allocator,
    elevation_data: []f32 = &.{},
    cloud_system: weather.CloudSystem = undefined,

    pub fn init(allocator_param: std_full.mem.Allocator, w: u32, h: u32, prng: *RandomInterface) !GameWorld {
        const num_tiles = w * h;
        if (num_tiles == 0 and (w != 0 or h != 0)) return error.Overflow;
        if (w != 0 and num_tiles / w != h) return error.Overflow;

        const tile_slice = try allocator_param.alloc(Tile, num_tiles);
        errdefer allocator_param.free(tile_slice);

        const elevation_slice = try allocator_param.alloc(f32, num_tiles);
        errdefer allocator_param.free(elevation_slice);

        for (tile_slice) |*tile| {
            tile.* = Tile{ .base_terrain = .VeryDeepWater, .fertility = 128 };
        }
        @memset(elevation_slice, @as(f32, 0.0));

        const cloud_sys = try weather.CloudSystem.init(w, h, allocator_param, prng);

        return GameWorld{
            .width = w,
            .height = h,
            .tiles = tile_slice,
            .entities = std_full.ArrayList(Entity).init(allocator_param),
            .items = std_full.ArrayList(items_module.Item).init(allocator_param),
            .allocator = allocator_param,
            .elevation_data = elevation_slice,
            .cloud_system = cloud_sys,
        };
    }

    pub fn deinit(self: *GameWorld) void {
        self.cloud_system.deinit();
        self.entities.deinit();
        self.items.deinit();
        self.allocator.free(self.tiles);
        if (self.elevation_data.len > 0) self.allocator.free(self.elevation_data);
        self.tiles = &.{};
        self.elevation_data = &.{};
    }

    pub fn spawnItem(self: *GameWorld, item_type: items_module.ItemType, x_pos: i32, y_pos: i32) void {
        const new_item = items_module.Item{
            .x = x_pos,
            .y = y_pos,
            .item_type = item_type,
            .hp = items_module.Item.getInitialHp(item_type),
            .decay_timer = items_module.Item.getDecayRateTicks(item_type),
        };
        self.items.append(new_item) catch |err| {
            log.err("Failed to spawn item {any} at {d},{d}: {s}", .{ item_type, x_pos, y_pos, @errorName(err) });
        };
    }

    pub fn findRandomAdjacentEmptyTile(
        self: *const GameWorld,
        center_x: i32,
        center_y: i32,
        max_attempts_per_spot: u32,
        prng: *RandomInterface,
    ) ?WorldPos {
        const offsets = [_]WorldPos{
            .{ .x = -1, .y = -1 }, .{ .x = 0, .y = -1 }, .{ .x = 1, .y = -1 },
            .{ .x = -1, .y = 0 },  .{ .x = 1, .y = 0 },  .{ .x = -1, .y = 1 },
            .{ .x = 0, .y = 1 },   .{ .x = 1, .y = 1 },
        };

        var shuffled_offsets = offsets;
        prng.shuffle(WorldPos, &shuffled_offsets);

        var attempts: u32 = 0;
        while (attempts < max_attempts_per_spot and attempts < shuffled_offsets.len) {
            const offset = shuffled_offsets[attempts];
            const try_x = center_x + offset.x;
            const try_y = center_y + offset.y;

            if (try_x < 0 or @as(u32, @intCast(try_x)) >= self.width or
                try_y < 0 or @as(u32, @intCast(try_y)) >= self.height)
            {
                attempts += 1;
                continue;
            }

            if (!self.isTileOccupiedByStaticEntity(try_x, try_y)) {
                if (self.getTile(try_x, try_y)) |tile| {
                    switch (tile.base_terrain) {
                        .VeryDeepWater, .DeepWater, .Mountain => {
                            attempts += 1;
                            continue;
                        },
                        else => return WorldPos{ .x = try_x, .y = try_y },
                    }
                }
            }
            attempts += 1;
        }
        return null;
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
        entity_art_height: u32, // This is the art height, not config.player_height_pixels directly
    ) TerrainMovementRules {
        var rules: TerrainMovementRules = .{ .can_pass = false, .speed_modifier = 1.0 };

        const target_tile_opt = self.getTile(target_tile_x, target_tile_y);
        if (target_tile_opt == null) return rules;
        const target_terrain = target_tile_opt.?.base_terrain;

        if (self.isTileOccupiedByStaticEntity(target_tile_x, target_tile_y)) {
            // Allow movement on paths/roads even if a static entity (like a dropped item, not a tree) is there.
            // This check might need refinement if static entities can block paths.
            if (entity_type == .Player and (target_terrain == .DirtPath or target_terrain == .CobblestoneRoad)) {} else {
                return rules;
            }
        }

        // Check based on the foot of the entity if its art is taller than 1 pixel
        if (entity_art_height > 1) {
            // The foot_y calculation should be relative to the entity's origin (y),
            // not target_tile_y, if entity_art_height is used for collision.
            // However, for simple tile-based movement, target_tile_y is the tile we are checking.
            // If entity_art_height is the visual height, and y is the base, then foot is at y.
            // Let's assume target_tile_y is the tile the entity's base wants to move to.
            // The check here is more about whether the *type* of entity can traverse the *type* of terrain.
            // The art_height parameter is more for visual alignment or complex collision later.
            // For now, the terrain type of the target_tile_y is the primary concern.
            // The original logic for foot_y was: target_tile_y + @as(i32, @intCast(entity_art_height)) - 1;
            // This assumes y is the top of the sprite. If y is the bottom, it's just target_tile_y.
            // Let's assume y is the base/foot of the entity for now.
            const foot_terrain_to_check = target_terrain; // Check the terrain of the tile the entity's base will be on.

            switch (entity_type) {
                .Player => if (foot_terrain_to_check == .VeryDeepWater or foot_terrain_to_check == .DeepWater or foot_terrain_to_check == .Mountain or foot_terrain_to_check == .Rock) return rules,
                .Sheep => if (foot_terrain_to_check == .VeryDeepWater or foot_terrain_to_check == .DeepWater or foot_terrain_to_check == .ShallowWater or foot_terrain_to_check == .Rock or foot_terrain_to_check == .Mountain) return rules, // Sheep avoid mountains too
                .Bear => if (foot_terrain_to_check == .Mountain or foot_terrain_to_check == .Rock) return rules, // Bears might be okay in shallow/deep water
                else => {},
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
                    .VeryDeepWater, .Mountain, .Rock => false, // Bears avoid very deep water, mountains, rocks
                    else => true,
                };
                if (rules.can_pass and (target_terrain == .DeepWater or target_terrain == .ShallowWater)) { // Bears slowed in any water
                    rules.speed_modifier = config.bear_deep_water_speed_modifier; // Assuming this modifier applies to any water for bears
                }
            },
            .Tree, .RockCluster, .Brush => rules.can_pass = false, // Static entities cannot "pass"
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
                // Get art height from config for consistency in spawning logic
                const art_h_for_check: u32 = switch (entity_type) {
                    .Player => config.player_height_pixels,
                    .Sheep => config.sheep_art_height, // Using config
                    .Bear => config.bear_art_height, // Using config
                    // For static entities, art height for collision might not be relevant for basic spawn check,
                    // but if it were, they'd also be in config. For now, assume 1 for simplicity if not Player/Sheep/Bear.
                    .Tree => config.seedling_art_height, // Example: use smallest tree height
                    .RockCluster => config.rock_cluster_art_height,
                    .Brush => config.brush_art_height,
                };
                const rules = self.getTerrainMovementRules(entity_type, try_x, try_y, art_h_for_check);
                switch (entity_type) {
                    .Player, .Sheep, .Bear => {
                        if (rules.can_pass) { // Movement rules already check terrain passability
                            can_spawn_here = true;
                        }
                    },
                    .Tree => {
                        // Trees can spawn on Grass, not on occupied tiles.
                        can_spawn_here = (tile_at_spawn.base_terrain == .Grass and !self.isTileOccupiedByStaticEntity(try_x, try_y));
                    },
                    .RockCluster => {
                        // Rocks can spawn on various non-water, non-occupied tiles.
                        can_spawn_here = (tile_at_spawn.base_terrain != .DeepWater and
                            tile_at_spawn.base_terrain != .ShallowWater and
                            tile_at_spawn.base_terrain != .VeryDeepWater and
                            !self.isTileOccupiedByStaticEntity(try_x, try_y));
                    },
                    .Brush => {
                        // Brush can spawn on Plains, Grass, Sand, not on occupied tiles.
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
