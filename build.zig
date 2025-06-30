const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Native build
    const native_exe = b.addExecutable(.{
        .name = "native",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    native_exe.rdynamic = false; // Default
    //
    const httpz = b.dependency("httpz", .{
        .target = target,
        .optimize = optimize,
    });

    // the executable from your call to b.addExecutable(...)
    native_exe.root_module.addImport("httpz", httpz.module("httpz"));
    b.installArtifact(native_exe);

    // WASM build
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });

    const allocator = b.allocator;

    var dir = std.fs.cwd().openDir("src", .{ .iterate = true }) catch |err| {
        std.debug.print("failed to open src/: {s}\n", .{@errorName(err)});
        return;
    };
    defer dir.close();

    var walker = dir.walk(allocator) catch |err| {
        std.debug.print("failed to walk src/: {s}\n", .{@errorName(err)});
        return;
    };
    defer walker.deinit();

    var wasm_targets = std.ArrayList(*std.Build.Step).init(allocator);
    while (walker.next() catch null) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.basename, "wasm.zig")) continue;

        const rel_path = std.fs.path.join(allocator, &.{ "src", entry.path }) catch continue;
        const base_name = entry.path[0 .. entry.path.len - "wasm.zig".len];
        const exe_name = std.fmt.allocPrint(allocator, "wasm{s}", .{base_name}) catch continue;
        const sanitized_name = sanitizeName(allocator, exe_name) catch continue;

        const wasm_exe = b.addExecutable(.{
            .name = sanitized_name,
            .root_source_file = b.path(rel_path),
            .target = wasm_target,
            .optimize = optimize,
        });
        wasm_exe.entry = .disabled;
        wasm_exe.rdynamic = true;
        const install_step = b.addInstallArtifact(wasm_exe, .{});
        wasm_targets.append(&install_step.step) catch continue;
    }

    const wasm_group = b.step("wasm-group", "Install all WASM executables");
    for (wasm_targets.items) |install_step| {
        wasm_group.dependOn(install_step);
    }
    native_exe.step.dependOn(wasm_group);
}

fn sanitizeName(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    var list = std.ArrayList(u8).init(allocator);
    for (name) |c| {
        try list.append(switch (c) {
            '/', '\\', '.' => '_',
            else => c,
        });
    }
    return list.toOwnedSlice();
}
