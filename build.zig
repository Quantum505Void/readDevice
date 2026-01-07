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

    // Windows 下隐藏控制台窗口
    if (target.result.os.tag == .windows) {
        exe.subsystem = .Windows;
    }

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

    // 根据目标平台链接对应的 hidapi 库
    const target_os = target.result.os.tag;
    switch (target_os) {
        .linux => {
            // Linux: 使用 hidapi-hidraw（推荐）或 hidapi-libusb
            exe.linkSystemLibrary("hidapi-hidraw");
        },
        .windows => {
            // Windows: 使用 vcpkg 安装的 hidapi
            const vcpkg_root = "E:\\GitFile\\vcpkg-master\\installed\\x64-windows";

            // 增加 include 搜索目录
            exe.addIncludePath(.{ .cwd_relative = vcpkg_root ++ "\\include" });
            // 增加 lib 搜索目录
            exe.addLibraryPath(.{ .cwd_relative = vcpkg_root ++ "\\lib" });
            // 链接第三方库 hidapi
            exe.linkSystemLibrary("hidapi");

            // 自动复制 DLL 到输出目录
            const dll_path = vcpkg_root ++ "\\bin\\hidapi.dll";
            const install_dll = b.addInstallBinFile(.{ .cwd_relative = dll_path }, "hidapi.dll");
            b.getInstallStep().dependOn(&install_dll.step);

            // 复制静态资源文件到输出目录
            const install_assets = b.addInstallDirectory(.{
                .source_dir = b.path("src/assets"),
                .install_dir = .bin,
                .install_subdir = "assets",
            });
            b.getInstallStep().dependOn(&install_assets.step);
        },
        .macos => {
            // macOS: 使用 hidapi（基于 IOHidManager）
            exe.linkSystemLibrary("hidapi");
            // macOS 可能还需要链接系统框架
            exe.linkFramework("IOKit");
            exe.linkFramework("CoreFoundation");
        },
        else => {
            // 其他平台尝试通用链接
            exe.linkSystemLibrary("hidapi");
        },
    }

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
