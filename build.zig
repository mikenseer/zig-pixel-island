const std = @import("std");

pub fn build(b: *std.Build) void {
    // Standard target options (e.g., native, wasm32-wasi)
    const target = b.standardTargetOptions(.{});

    // Standard optimization options (e.g., Debug, ReleaseSafe, ReleaseFast)
    const optimize = b.standardOptimizeOption(.{});

    // Add the raylib-zig package from build.zig.zon
    // Simplified key to "raylibzig" to match the .zon file
    const raylib_dep = b.dependency("raylibzig", .{
        .target = target,
        .optimize = optimize,
    });

    // Get the modules and artifact from the raylib-zig dependency
    const raylib_module = raylib_dep.module("raylib"); // main raylib module
    const raylib_c_artifact = raylib_dep.artifact("raylib"); // raylib C library

    // Create the executable for your game
    const exe = b.addExecutable(.{
        .name = "zig_pixel_island", 
        .root_source_file = b.path("src/main.zig"), 
        .target = target,
        .optimize = optimize,
    });

    // Make the raylib module available for @import("raylib") in your game code.
    exe.root_module.addImport("raylib", raylib_module);

    // Link against the Raylib C library artifact provided by raylib-zig
    exe.linkLibrary(raylib_c_artifact);

    // System libraries that Raylib depends on
    switch (target.result.os.tag) {
        .windows => {
            exe.linkSystemLibrary("opengl32");
            exe.linkSystemLibrary("gdi32");
            exe.linkSystemLibrary("winmm");
        },
        .linux => {
            exe.linkSystemLibrary("GL");
            exe.linkSystemLibrary("m");
            exe.linkSystemLibrary("pthread");
            exe.linkSystemLibrary("dl");
            exe.linkSystemLibrary("X11");
        },
        .macos => {
            exe.linkFramework("OpenGL");
            exe.linkFramework("Cocoa");
            exe.linkFramework("IOKit");
            exe.linkFramework("CoreAudio");
            exe.linkFramework("CoreVideo");
        },
        else => {},
    }

    // Install the executable
    b.installArtifact(exe);

    // Create a 'run' step: `zig build run`
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep()); 

    if (b.args) |args| {
        run_cmd.addArgs(args); 
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
