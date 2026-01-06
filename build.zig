const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 创建主程序可执行文件
    const exe = b.addExecutable(.{
        .name = "readDevice",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // 添加 zig-webui 依赖
    const webui = b.dependency("webui", .{
        .target = target,
        .optimize = optimize,
        .enable_tls = false,
    });
    exe.root_module.addImport("webui", webui.module("webui"));

    // 添加 device_whitelist 模块
    const whitelist_module = b.addModule("device_whitelist", .{
        .root_source_file = b.path("device_whitelist.zig"),
    });
    exe.root_module.addImport("device_whitelist", whitelist_module);

    // 需要链接 C 标准库
    exe.linkLibC();

    b.installArtifact(exe);

    // 运行命令
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "运行应用程序");
    run_step.dependOn(&run_cmd.step);

    // 测试
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "运行单元测试");
    test_step.dependOn(&run_unit_tests.step);
}
