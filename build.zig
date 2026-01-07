const std = @import("std");

// 在 Windows 上自动搜索 vcpkg 安装目录
fn findVcpkgRoot(b: *std.Build) ?[]const u8 {
    // 尝试使用 PowerShell 查找 vcpkg.exe
    const result = std.process.Child.run(.{
        .allocator = b.allocator,
        .argv = &[_][]const u8{
            "powershell.exe",
            "-NoProfile",
            "-Command",
            "Get-Command vcpkg -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source",
        },
    }) catch return null;

    defer {
        b.allocator.free(result.stdout);
        b.allocator.free(result.stderr);
    }

    if (result.term.Exited != 0 or result.stdout.len == 0) {
        // 尝试直接用 where 命令
        const where_result = std.process.Child.run(.{
            .allocator = b.allocator,
            .argv = &[_][]const u8{ "where", "vcpkg" },
        }) catch return null;

        defer {
            b.allocator.free(where_result.stdout);
            b.allocator.free(where_result.stderr);
        }

        if (where_result.term.Exited != 0 or where_result.stdout.len == 0) {
            return null;
        }

        // 从 vcpkg.exe 路径推断安装目录
        const vcpkg_exe = std.mem.trim(u8, where_result.stdout, &std.ascii.whitespace);
        return extractVcpkgRoot(b, vcpkg_exe);
    }

    const vcpkg_exe = std.mem.trim(u8, result.stdout, &std.ascii.whitespace);
    return extractVcpkgRoot(b, vcpkg_exe);
}

fn extractVcpkgRoot(b: *std.Build, vcpkg_exe: []const u8) ?[]const u8 {
    // vcpkg.exe 通常在 vcpkg 根目录
    // installed 目录在 vcpkg/installed/x64-windows
    if (std.mem.lastIndexOf(u8, vcpkg_exe, "\\")) |last_sep| {
        const vcpkg_dir = vcpkg_exe[0..last_sep];
        const installed_path = b.fmt("{s}\\installed\\x64-windows", .{vcpkg_dir});

        // 验证路径存在
        std.fs.cwd().access(installed_path, .{}) catch return null;

        std.debug.print("✓ 自动找到 vcpkg: {s}\n", .{installed_path});
        return installed_path;
    }
    return null;
}

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
            // Windows: 自动搜索 vcpkg 安装目录
            var vcpkg_root: []const u8 = "";

            // 1. 尝试环境变量 VCPKG_ROOT
            if (std.process.getEnvVarOwned(b.allocator, "VCPKG_ROOT")) |env_root| {
                vcpkg_root = env_root;
                std.debug.print("✓ 使用 VCPKG_ROOT 环境变量: {s}\n", .{vcpkg_root});
            } else |_| {
                // 2. 自动搜索 vcpkg 安装目录
                std.debug.print("⚠ 未设置 VCPKG_ROOT，自动搜索 vcpkg...\n", .{});

                if (findVcpkgRoot(b)) |found_root| {
                    vcpkg_root = found_root;
                } else {
                    std.debug.print("\n❌ 无法自动找到 vcpkg 安装目录！\n\n", .{});
                    std.debug.print("解决方案:\n", .{});
                    std.debug.print("  1. 安装 vcpkg: git clone https://github.com/microsoft/vcpkg\n", .{});
                    std.debug.print("  2. 安装 hidapi: vcpkg install hidapi:x64-windows\n", .{});
                    std.debug.print("  3. 将 vcpkg.exe 添加到系统 PATH\n", .{});
                    std.debug.print("  或设置环境变量: set VCPKG_ROOT=C:\\path\\to\\vcpkg\\installed\\x64-windows\n", .{});
                    @panic("vcpkg 未找到");
                }
            }

            // 配置 vcpkg 路径
            const include_path = b.fmt("{s}\\include", .{vcpkg_root});
            const lib_path = b.fmt("{s}\\lib", .{vcpkg_root});
            const dll_path = b.fmt("{s}\\bin\\hidapi.dll", .{vcpkg_root});

            exe.addIncludePath(.{ .cwd_relative = include_path });
            exe.addLibraryPath(.{ .cwd_relative = lib_path });
            exe.linkSystemLibrary("hidapi");

            // 复制 DLL 到输出目录
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
