// src/noise_utils.zig
// Noise generation utilities including FBM.

const std = @import("std");
const math = std.math;
const log = std.log;
const Random = std.Random;
const Allocator = std.mem.Allocator;

pub const NoiseGridCell = struct {
    value: f32,
};

fn initRawNoiseGrid(grid_width_points: u32, grid_height_points: u32, prng: *Random.DefaultPrng, allocator: Allocator) ![]NoiseGridCell {
    if (grid_width_points == 0 or grid_height_points == 0) return error.InvalidGridDimensions;
    const grid = try allocator.alloc(NoiseGridCell, grid_width_points * grid_height_points);

    var random_iface = prng.random();

    for (grid) |*cell| {
        cell.value = (random_iface.float(f32) * 2.0) - 1.0;
    }
    return grid;
}

fn lerp(a: f32, b: f32, t: f32) f32 {
    return a + t * (b - a);
}

fn getValueFromGrid(
    x: f32,
    y: f32,
    grid: []const NoiseGridCell,
    grid_w_pts: u32,
    grid_h_pts: u32,
) f32 {
    const gx: f32 = x;
    const gy: f32 = y;

    const gxi: i32 = @intFromFloat(math.floor(gx));
    const gyi: i32 = @intFromFloat(math.floor(gy));

    const tx: f32 = gx - @as(f32, @floatFromInt(gxi));
    const ty: f32 = gy - @as(f32, @floatFromInt(gyi));

    if (grid_w_pts == 0 or grid_h_pts == 0) return 0.0;

    const N_w_i32 = @as(i32, @intCast(grid_w_pts));
    const N_h_i32 = @as(i32, @intCast(grid_h_pts));

    const x0_idx_i32: i32 = @mod(gxi, N_w_i32);
    const x1_idx_i32: i32 = @mod(gxi + 1, N_w_i32);
    const y0_idx_i32: i32 = @mod(gyi, N_h_i32);
    const y1_idx_i32: i32 = @mod(gyi + 1, N_h_i32);

    const x0_idx = @as(u32, @intCast(x0_idx_i32));
    const x1_idx = @as(u32, @intCast(x1_idx_i32));
    const y0_idx = @as(u32, @intCast(y0_idx_i32));
    const y1_idx = @as(u32, @intCast(y1_idx_i32));

    const stride = grid_w_pts;

    const idx00 = y0_idx * stride + x0_idx;
    const idx10 = y0_idx * stride + x1_idx;
    const idx01 = y1_idx * stride + x0_idx;
    const idx11 = y1_idx * stride + x1_idx;

    if (idx00 >= grid.len or idx10 >= grid.len or idx01 >= grid.len or idx11 >= grid.len) {
        log.warn("Noise grid index out of bounds. gxi:{d}, gyi:{d}, x0:{d},y0:{d},x1:{d},y1:{d}, w:{d},h:{d}, gridlen:{d}", .{ gxi, gyi, x0_idx, y0_idx, x1_idx, y1_idx, grid_w_pts, grid_h_pts, grid.len });
        return 0.0;
    }

    const c00 = grid[@as(usize, idx00)].value;
    const c10 = grid[@as(usize, idx10)].value;
    const c01 = grid[@as(usize, idx01)].value;
    const c11 = grid[@as(usize, idx11)].value;

    const nx0 = lerp(c00, c10, tx);
    const nx1 = lerp(c01, c11, tx);

    return lerp(nx0, nx1, ty);
}

pub const NoiseGenerator = struct {
    allocator: Allocator,
    noise_grid: []NoiseGridCell,
    grid_cell_size: u32, // This specific generator's cell size for scaling
    grid_width_points: u32,
    grid_height_points: u32,

    // Modified init to accept cell_size
    pub fn init(seed: u64, allocator_param: Allocator, cell_size_param: u32, world_render_width: u32, world_render_height: u32) NoiseGenerator {
        // Grid points determined by how many cells fit into the render area
        const grid_points_w: u32 = (world_render_width / cell_size_param) + 2;
        const grid_points_h: u32 = (world_render_height / cell_size_param) + 2;

        var prng_instance = Random.DefaultPrng.init(seed);

        const grid = initRawNoiseGrid(grid_points_w, grid_points_h, &prng_instance, allocator_param) catch |err| {
            log.err("Failed to initialize noise grid in NoiseGenerator: {s}", .{@errorName(err)});
            return NoiseGenerator{
                .allocator = allocator_param,
                .noise_grid = &.{},
                .grid_cell_size = cell_size_param, // Store the passed cell_size
                .grid_width_points = 0,
                .grid_height_points = 0,
            };
        };

        return NoiseGenerator{
            .allocator = allocator_param,
            .noise_grid = grid,
            .grid_cell_size = cell_size_param, // Store the passed cell_size
            .grid_width_points = grid_points_w,
            .grid_height_points = grid_points_h,
        };
    }

    pub fn deinit(self: *NoiseGenerator) void {
        if (self.noise_grid.len > 0) {
            self.allocator.free(self.noise_grid);
        }
    }

    // Output range is approximately -1.0 to 1.0
    pub fn fbm(self: *const NoiseGenerator, x: f32, y: f32, octaves: u32, persistence: f32, lacunarity: f32) f32 {
        var total: f32 = 0.0;
        var frequency: f32 = 1.0;
        var amplitude: f32 = 1.0;
        var max_value: f32 = 0.0;

        const effective_octaves = if (octaves == 0) 1 else octaves;

        for (0..effective_octaves) |_| {
            // x and y are world coordinates. Scale them by frequency, then divide by this generator's cell_size.
            const scaled_x = (x * frequency) / @as(f32, @floatFromInt(self.grid_cell_size));
            const scaled_y = (y * frequency) / @as(f32, @floatFromInt(self.grid_cell_size));

            total += getValueFromGrid(scaled_x, scaled_y, self.noise_grid, self.grid_width_points, self.grid_height_points) * amplitude;

            max_value += amplitude;
            amplitude *= persistence;
            frequency *= lacunarity;
        }

        if (max_value == 0.0) return 0.0;
        return total / max_value;
    }
};
