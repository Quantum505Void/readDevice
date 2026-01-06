const std = @import("std");

// ============ HID 设备类型定义 ============

/// HID 设备类型枚举
/// 用于标识设备是鼠标、键盘、蓝牙还是其他类型
pub const DeviceType = enum(u8) {
    mouse = 0, // 鼠标设备
    keyboard = 1, // 键盘设备
    other = 2, // 其他 HID 设备
    bluetooth = 3, // 蓝牙设备
};

// ============ HID 设备信息结构 ============

/// HID 设备信息结构体
/// 包含设备的所有重要信息（VID、PID、名称等）
pub const HidDevice = struct {
    vid: []const u8, // 厂商 ID (Vendor ID)
    pid: []const u8, // 产品 ID (Product ID)
    product_name: []const u8, // 产品名称
    manufacturer: []const u8, // 制造商名称
    serial_number: []const u8, // 序列号
    device_path: []const u8, // 设备路径
    device_type: DeviceType, // 设备类型
    usage_page: u16 = 0, // HID Usage Page
    usage: u16 = 0, // HID Usage
    handle: ?*anyopaque = null, // 设备句柄（可选）

    /// 释放设备信息占用的内存
    pub fn deinit(self: *HidDevice, allocator: std.mem.Allocator) void {
        allocator.free(self.vid);
        allocator.free(self.pid);
        allocator.free(self.product_name);
        allocator.free(self.manufacturer);
        allocator.free(self.serial_number);
        allocator.free(self.device_path);
    }
};

// ============ Linux 平台 HID 实现 ============

/// Linux 平台的 HID 设备操作实现
/// 使用 hidraw 接口和 sysfs 文件系统
pub const LinuxHid = struct {
    /// 枚举所有 Linux HID 设备
    /// 扫描 /dev/hidraw* 设备并读取其信息
    pub fn enumerate(allocator: std.mem.Allocator) !std.ArrayList(HidDevice) {
        var devices = std.ArrayList(HidDevice).init(allocator);
        errdefer devices.deinit();

        // 打开 /dev 目录，查找所有 hidraw 设备
        var dir = try std.fs.openDirAbsolute("/dev", .{ .iterate = true });
        defer dir.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            // 只处理以 "hidraw" 开头的设备
            if (std.mem.startsWith(u8, entry.name, "hidraw")) {
                // 读取该设备的详细信息
                const device = try getDeviceInfo(allocator, entry.name);
                try devices.append(device);
            }
        }

        return devices;
    }

    /// 获取单个设备的详细信息
    /// 通过 sysfs 读取设备的 VID、PID、名称等信息
    fn getDeviceInfo(allocator: std.mem.Allocator, device_name: []const u8) !HidDevice {
        // 构建 sysfs 设备路径
        var path_buffer: [512]u8 = undefined;
        const sys_path = try std.fmt.bufPrint(&path_buffer, "/sys/class/hidraw/{s}/device", .{device_name});

        // 读取 uevent 文件获取设备信息
        const uevent_content = readSysfsFile(allocator, sys_path, "uevent") catch |err| blk: {
            std.debug.print("警告: 无法读取 {s} 的 uevent: {}\n", .{ device_name, err });
            break :blk null;
        };
        defer if (uevent_content) |content| allocator.free(content);

        var vid: []const u8 = "0000";
        var pid: []const u8 = "0000";
        var name: []const u8 = "Unknown Device";
        var usage_page: u16 = 0;
        var usage: u16 = 0;
        var bus_type: u16 = 0; // 总线类型（0005=蓝牙，0003=USB）

        // 用于存储大写的VID/PID
        var vid_buffer: [4]u8 = undefined;
        var pid_buffer: [4]u8 = undefined;

        // 解析 uevent 文件
        if (uevent_content) |content| {
            var lines = std.mem.splitScalar(u8, content, '\n');
            while (lines.next()) |line| {
                // 解析 HID_ID=0018:000004F3:0000317C 格式
                if (std.mem.startsWith(u8, line, "HID_ID=")) {
                    const id_part = line[7..]; // 跳过 "HID_ID="
                    // 格式: bus:vid:pid
                    var parts = std.mem.splitScalar(u8, id_part, ':');
                    if (parts.next()) |bus_hex| {
                        bus_type = std.fmt.parseInt(u16, bus_hex, 16) catch 0;
                    }
                    if (parts.next()) |vid_hex| {
                        if (vid_hex.len >= 8) {
                            for (vid_hex[4..8], 0..) |c, i| {
                                vid_buffer[i] = std.ascii.toUpper(c);
                            }
                            vid = &vid_buffer; // 取后4位并转大写
                        }
                    }
                    if (parts.next()) |pid_hex| {
                        if (pid_hex.len >= 8) {
                            for (pid_hex[4..8], 0..) |c, i| {
                                pid_buffer[i] = std.ascii.toUpper(c);
                            }
                            pid = &pid_buffer; // 取后4位并转大写
                        }
                    }
                }
                // 解析 HID_NAME=ELAN06FA:00 04F3:317C
                else if (std.mem.startsWith(u8, line, "HID_NAME=")) {
                    name = line[9..];
                }
                // 解析 MODALIAS=hid:b0018g0004v000004F3p0000317C
                // 格式: hid:bBUSgGROUPvVENDORpPRODUCT
                // 其中 GROUP 包含 Usage Page (高4位) 和 Usage (低4位)
                else if (std.mem.startsWith(u8, line, "MODALIAS=hid:")) {
                    const modalias = line[13..]; // 跳过 "MODALIAS=hid:"
                    // 查找 'g' 开始的部分
                    if (std.mem.indexOf(u8, modalias, "g")) |g_pos| {
                        if (modalias.len >= g_pos + 5) {
                            const group_str = modalias[g_pos + 1 .. g_pos + 5];
                            // group 的前两位是 usage page，后两位是 usage
                            usage_page = std.fmt.parseInt(u16, group_str[0..2], 16) catch 0;
                            usage = std.fmt.parseInt(u16, group_str[2..4], 16) catch 0;
                        }
                    }
                }
            }
        }

        // 构建设备路径
        const device_path = try std.fmt.allocPrint(allocator, "/dev/{s}", .{device_name});

        // 根据总线类型和 Usage Page/Usage 推测设备类型
        const device_type = detectDeviceType(bus_type, usage_page, usage, name);

        return HidDevice{
            .vid = try allocator.dupe(u8, vid),
            .pid = try allocator.dupe(u8, pid),
            .product_name = try allocator.dupe(u8, name),
            .manufacturer = try allocator.dupe(u8, "Unknown"),
            .serial_number = try allocator.dupe(u8, ""),
            .device_path = device_path,
            .device_type = device_type,
            .usage_page = usage_page,
            .usage = usage,
        };
    }

    /// 从 sysfs 文件读取内容
    fn readSysfsFile(allocator: std.mem.Allocator, base_path: []const u8, file_name: []const u8) !?[]const u8 {
        var path_buffer: [512]u8 = undefined;
        const file_path = try std.fmt.bufPrint(&path_buffer, "{s}/{s}", .{ base_path, file_name });

        // 打开并读取文件
        const file = std.fs.openFileAbsolute(file_path, .{}) catch {
            return null;
        };
        defer file.close();

        // 读取文件内容
        const content = file.readToEndAlloc(allocator, 4096) catch {
            return null;
        };

        // 去除换行符和空白字符
        const trimmed = std.mem.trim(u8, content, &std.ascii.whitespace);

        // 如果内容为空，返回 null
        if (trimmed.len == 0) {
            allocator.free(content);
            return null;
        }

        // 复制修剪后的内容
        const result = try allocator.dupe(u8, trimmed);
        allocator.free(content);
        return result;
    }

    /// 根据总线类型、Usage Page 和 Usage 检测设备类型
    /// bus_type: 0x0005 = Bluetooth, 0x0003 = USB, 0x0018 = I2C
    /// HID Usage Page 1 = Generic Desktop, Usage 2 = Mouse, Usage 6 = Keyboard
    fn detectDeviceType(bus_type: u16, usage_page: u16, usage: u16, product_name: []const u8) DeviceType {
        // 优先检测蓝牙设备（bus_type = 0x0005）
        if (bus_type == 0x0005) {
            return .bluetooth;
        }

        // 使用 Usage Page 和 Usage 判断
        if (usage_page == 1) { // Generic Desktop
            if (usage == 2) { // Mouse
                return .mouse;
            } else if (usage == 6) { // Keyboard
                return .keyboard;
            }
        }

        // 如果 Usage 信息不准确，再根据产品名称判断
        return detectDeviceTypeByName(product_name);
    }

    /// 根据产品名称检测设备类型（备用方案）
    fn detectDeviceTypeByName(product_name: []const u8) DeviceType {
        // 为避免修改原字符串，使用临时缓冲区
        var lower_buffer: [256]u8 = undefined;
        const lower_name = if (product_name.len <= lower_buffer.len)
            std.ascii.lowerString(&lower_buffer, product_name)
        else
            product_name; // 如果太长就不转换了

        // 检查是否包含鼠标关键词
        if (std.mem.indexOf(u8, lower_name, "mouse") != null or
            std.mem.indexOf(u8, lower_name, "mice") != null or
            std.mem.indexOf(u8, lower_name, "pointer") != null)
        {
            return .mouse;
        }

        // 检查是否包含键盘关键词
        if (std.mem.indexOf(u8, lower_name, "keyboard") != null or
            std.mem.indexOf(u8, lower_name, "kbd") != null)
        {
            return .keyboard;
        }

        return .other;
    }

    /// 打开 HID 设备进行读写
    pub fn open(device_path: []const u8) !std.fs.File {
        return try std.fs.openFileAbsolute(device_path, .{ .mode = .read_write });
    }

    /// 从 HID 设备读取数据
    pub fn read(file: std.fs.File, buffer: []u8) !usize {
        return try file.read(buffer);
    }

    /// 向 HID 设备写入数据
    pub fn write(file: std.fs.File, data: []const u8) !usize {
        return try file.write(data);
    }

    /// 使用 ioctl 设置 HID Feature Report
    pub fn setFeature(file: std.fs.File, report: []const u8) !void {
        const HIDIOCSFEATRE = 0xC0000000 | (@as(u32, @intCast(report.len)) << 16) | (@as(u32, 'H') << 8) | 0x06;
        const result = std.os.linux.ioctl(file.handle, HIDIOCSFEATRE, @intFromPtr(report.ptr));
        if (result < 0) {
            return error.IoctlFailed;
        }
    }

    /// 使用 ioctl 获取 HID Feature Report
    pub fn getFeature(file: std.fs.File, report: []u8) !usize {
        const HIDIOCGFEATRE = 0xC0000000 | (@as(u32, @intCast(report.len)) << 16) | (@as(u32, 'H') << 8) | 0x07;
        const result = std.os.linux.ioctl(file.handle, HIDIOCGFEATRE, @intFromPtr(report.ptr));
        if (result < 0) {
            return error.IoctlFailed;
        }
        return @intCast(result);
    }
};

// ============ Windows 平台 HID 实现 ============

/// Windows 平台的 HID 设备操作实现
/// 使用 Windows HID API (hid.lib 和 setupapi.lib)
const WindowsHid = struct {
    /// 枚举所有 Windows HID 设备
    /// 使用 SetupAPI 查询系统中的 HID 设备
    pub fn enumerate(allocator: std.mem.Allocator) !std.ArrayList(HidDevice) {
        var devices = std.ArrayList(HidDevice).init(allocator);
        errdefer devices.deinit();

        // TODO: 实现 Windows HID 设备枚举
        return devices;
    }

    /// 打开 Windows HID 设备
    pub fn open(device_path: []const u8) !*anyopaque {
        _ = device_path;
        return error.NotImplemented;
    }

    /// 从 Windows HID 设备读取数据
    pub fn read(handle: *anyopaque, buffer: []u8) !usize {
        _ = handle;
        _ = buffer;
        return error.NotImplemented;
    }

    /// 向 Windows HID 设备写入数据
    pub fn write(handle: *anyopaque, data: []const u8) !usize {
        _ = handle;
        _ = data;
        return error.NotImplemented;
    }
};

// ============ 跨平台公共 API ============

/// 枚举当前系统中的所有 HID 设备
/// 根据编译目标平台自动选择对应的实现
pub fn enumerateDevices(allocator: std.mem.Allocator) !std.ArrayList(HidDevice) {
    return switch (@import("builtin").os.tag) {
        .linux => LinuxHid.enumerate(allocator),
        .windows => WindowsHid.enumerate(allocator),
        else => error.UnsupportedPlatform,
    };
}

/// 打开指定路径的 HID 设备
pub fn openDevice(device_path: []const u8) !*anyopaque {
    return switch (@import("builtin").os.tag) {
        .linux => @ptrCast(try LinuxHid.open(device_path)),
        .windows => try WindowsHid.open(device_path),
        else => error.UnsupportedPlatform,
    };
}

/// 从 HID 设备读取数据
pub fn readDevice(handle: *anyopaque, buffer: []u8) !usize {
    return switch (@import("builtin").os.tag) {
        .linux => {
            const file: *std.fs.File = @ptrCast(@alignCast(handle));
            return try LinuxHid.read(file.*, buffer);
        },
        .windows => try WindowsHid.read(handle, buffer),
        else => error.UnsupportedPlatform,
    };
}

/// 向 HID 设备写入数据
pub fn writeDevice(handle: *anyopaque, data: []const u8) !usize {
    return switch (@import("builtin").os.tag) {
        .linux => {
            const file: *std.fs.File = @ptrCast(@alignCast(handle));
            return try LinuxHid.write(file.*, data);
        },
        .windows => try WindowsHid.write(handle, data),
        else => error.UnsupportedPlatform,
    };
}
