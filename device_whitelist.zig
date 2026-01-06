// ============ 设备白名单配置 ============
const DeviceConfig = struct {
    vid: []const u8,
    pid: []const u8,
    mode: u8, // 1=8系(逐字节), 2=9系(32字节批量)
    name: ?[]const u8 = null, // 可选设备名称
};

// 支持的设备白名单
pub const DEVICE_WHITELIST = [_]DeviceConfig{
    // A8xx 系列设备 (逐字节读取)
    .{ .vid = "30FA", .pid = "1440", .mode = 1 },
    .{ .vid = "30FA", .pid = "1540", .mode = 1 },
    .{ .vid = "30FA", .pid = "1E01", .mode = 1 },
    .{ .vid = "30FA", .pid = "1040", .mode = 1 },
    .{ .vid = "30FA", .pid = "1201", .mode = 1 },
    .{ .vid = "30FA", .pid = "1140", .mode = 1 },
    .{ .vid = "30FA", .pid = "1D01", .mode = 1 },
    .{ .vid = "30FA", .pid = "1340", .mode = 1 },
    .{ .vid = "30FA", .pid = "1901", .mode = 1 },

    // A9xx 系列设备 (32字节批量读取)
    .{ .vid = "30FA", .pid = "1150", .mode = 2 },
    .{ .vid = "30FA", .pid = "1450", .mode = 2 },
    .{ .vid = "30FA", .pid = "1550", .mode = 2 },
};

/// 检查设备是否在白名单中
pub fn isDeviceSupported(vid: []const u8, pid: []const u8) ?DeviceConfig {
    for (DEVICE_WHITELIST) |config| {
        if (std.mem.eql(u8, config.vid, vid) and std.mem.eql(u8, config.pid, pid)) {
            return config;
        }
    }
    return null;
}

/// 获取设备的读取模式
pub fn getDeviceMode(vid: []const u8, pid: []const u8) ?u8 {
    if (isDeviceSupported(vid, pid)) |config| {
        return config.mode;
    }
    return null;
}

const std = @import("std");
