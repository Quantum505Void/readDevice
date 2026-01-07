const std = @import("std");

// ============ hidapi C 库绑定 ============
// 使用 @cImport 方式导入 hidapi 头文件
// 参考: https://course.ziglang.cc/advanced/interact-with-c

/// 使用 @cImport 自动翻译 hidapi C 头文件
/// 这是 Zig 官方推荐的方式，利用 translate-c 功能自动转换 C 代码
pub const c = @cImport({
    @cInclude("hidapi/hidapi.h");
});

// 为了保持 API 兼容性，创建类型别名
pub const hid_device = c.hid_device;
pub const hid_device_info = c.struct_hid_device_info;

// ============ HID 设备类型定义 ============

/// HID 设备类型枚举
/// 用于标识设备是鼠标、键盘、蓝牙还是其他类型
pub const DeviceType = enum(u8) {
    mouse = 0, // 鼠标设备
    keyboard = 1, // 键盘设备
    other = 2, // 其他 HID 设备
    bluetooth = 3, // 蓝牙设备
};

/// HID Report 类型
pub const ReportType = enum(u8) {
    input = 1, // Input Report
    output = 2, // Output Report
    feature = 3, // Feature Report
};

/// HID Report 信息
pub const ReportInfo = struct {
    report_id: u8, // Report ID
    report_type: ReportType, // Report 类型
    report_size: u16, // Report 大小（字节）
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

// ============ 辅助函数 ============

/// 转换宽字符串（UTF-16）为 UTF-8
fn wcharToUtf8(allocator: std.mem.Allocator, wstr: [*:0]const u16) ![]const u8 {
    if (wstr[0] == 0) return try allocator.dupe(u8, "");

    // 计算长度
    var len: usize = 0;
    while (wstr[len] != 0) : (len += 1) {}

    if (len == 0) return try allocator.dupe(u8, "");

    // 创建切片
    const slice = wstr[0..len];

    // 计算需要的 UTF-8 缓冲区大小
    const utf8_str = std.unicode.utf16LeToUtf8AllocZ(allocator, slice) catch |err| {
        std.debug.print("警告: UTF-16 转换失败: {}\n", .{err});
        return try allocator.dupe(u8, "");
    };
    defer allocator.free(utf8_str);

    // utf16LeToUtf8AllocZ 返回的 [:0]u8 类型，len 不包含 null 终止符，直接使用完整长度
    return try allocator.dupe(u8, utf8_str);
}

/// 从已打开的设备获取完整的字符串信息
/// 参考 hidapi 文档和 WebHID API，enumerate 返回的字符串可能被截断
/// 需要打开设备后使用 hid_get_*_string 函数获取完整信息
fn getDeviceStrings(allocator: std.mem.Allocator, device: *hid_device) !struct {
    product: []const u8,
    manufacturer: []const u8,
    serial: []const u8,
} {
    // 缓冲区大小：根据 USB HID 规范，字符串描述符最大 255 字符
    const MAX_STR: usize = 256;

    // 获取产品名称
    var product_name: []const u8 = "";
    {
        var wstr_buf: [MAX_STR]u16 = [_]u16{0} ** MAX_STR;
        const product_result = c.hid_get_product_string(device, &wstr_buf, MAX_STR);
        if (product_result == 0 and wstr_buf[0] != 0) {
            // 找到字符串结束位置
            var len: usize = 0;
            while (len < MAX_STR and wstr_buf[len] != 0) : (len += 1) {}
            if (len > 0) {
                const slice = wstr_buf[0..len :0];
                product_name = wcharToUtf8(allocator, @ptrCast(slice.ptr)) catch "";
            }
        }
    }

    // 获取制造商名称
    var manufacturer_name: []const u8 = "";
    {
        var wstr_buf: [MAX_STR]u16 = [_]u16{0} ** MAX_STR;
        const mfg_result = c.hid_get_manufacturer_string(device, &wstr_buf, MAX_STR);
        if (mfg_result == 0 and wstr_buf[0] != 0) {
            var len: usize = 0;
            while (len < MAX_STR and wstr_buf[len] != 0) : (len += 1) {}
            if (len > 0) {
                const slice = wstr_buf[0..len :0];
                manufacturer_name = wcharToUtf8(allocator, @ptrCast(slice.ptr)) catch "";
            }
        }
    }

    // 获取序列号
    var serial_number: []const u8 = "";
    {
        var wstr_buf: [MAX_STR]u16 = [_]u16{0} ** MAX_STR;
        const serial_result = c.hid_get_serial_number_string(device, &wstr_buf, MAX_STR);
        if (serial_result == 0 and wstr_buf[0] != 0) {
            var len: usize = 0;
            while (len < MAX_STR and wstr_buf[len] != 0) : (len += 1) {}
            if (len > 0) {
                const slice = wstr_buf[0..len :0];
                serial_number = wcharToUtf8(allocator, @ptrCast(slice.ptr)) catch "";
            }
        }
    }

    return .{
        .product = product_name,
        .manufacturer = manufacturer_name,
        .serial = serial_number,
    };
}

/// 根据 Usage Page 和 Usage 检测设备类型（仅依赖 HID 规范标准值）
fn detectDeviceType(usage_page: u16, usage: u16, product_name: []const u8) DeviceType {
    _ = product_name; // 不使用产品名称，仅依赖 HID 标准值

    // 严格按照 HID Usage Tables 规范判断
    // 参考: https://usb.org/sites/default/files/hut1_21.pdf
    switch (usage_page) {
        0x0001 => { // Generic Desktop Page
            switch (usage) {
                0x02 => return .mouse, // Mouse
                0x06 => return .keyboard, // Keyboard
                else => return .other, // Joystick, Gamepad, etc.
            }
        },
        0x0007 => return .keyboard, // Keyboard/Keypad Page
        else => return .other, // 其他所有情况（包括 Consumer, Vendor-defined 等）
    }
}

// ============ HID API 实现 ============

/// 初始化 hidapi 库
/// 必须在使用其他 hidapi 函数之前调用
pub fn init() !void {
    const result = c.hid_init();
    if (result != 0) {
        return error.InitFailed;
    }
}

/// 清理 hidapi 库
/// 程序结束时调用以释放资源
pub fn exit() !void {
    const result = c.hid_exit();
    if (result != 0) {
        return error.ExitFailed;
    }
}

/// 枚举当前系统中的所有 HID 设备
pub fn enumerateDevices(allocator: std.mem.Allocator) !std.ArrayList(HidDevice) {
    var devices = std.ArrayList(HidDevice).init(allocator);
    errdefer devices.deinit();

    // 枚举所有 HID 设备 (0, 0 表示所有设备)
    const dev_list = c.hid_enumerate(0, 0);
    defer c.hid_free_enumeration(dev_list);

    if (dev_list == null) {
        return devices; // 没有设备
    }

    var current: ?*hid_device_info = dev_list;
    while (current) |info| : (current = info.next) {
        // 转换 VID/PID 为十六进制字符串
        var vid_buf: [4]u8 = undefined;
        var pid_buf: [4]u8 = undefined;
        const vid_str = try std.fmt.bufPrint(&vid_buf, "{X:0>4}", .{info.vendor_id});
        const pid_str = try std.fmt.bufPrint(&pid_buf, "{X:0>4}", .{info.product_id});

        // 尝试打开设备以获取完整的字符串信息
        // 根据 hidapi 和 WebHID 规范，enumerate 返回的字符串可能被截断
        var product_name: []const u8 = "";
        var manufacturer: []const u8 = "";
        var serial_number: []const u8 = "";
        var got_strings = false;

        const device_handle = c.hid_open_path(info.path);
        if (device_handle) |handle| {
            // 设备打开成功，尝试获取完整字符串
            defer c.hid_close(handle);
            if (getDeviceStrings(allocator, handle)) |strings| {
                product_name = strings.product;
                manufacturer = strings.manufacturer;
                serial_number = strings.serial;
                got_strings = true;
            } else |_| {
                // 获取失败，后面使用 enumerate 返回的信息
            }
        }

        // 如果没有通过打开设备获取到字符串，使用 enumerate 返回的信息
        if (!got_strings) {
            product_name = try wcharToUtf8(allocator, info.product_string);
            manufacturer = try wcharToUtf8(allocator, info.manufacturer_string);
            serial_number = try wcharToUtf8(allocator, info.serial_number);
        }
        errdefer {
            allocator.free(product_name);
            allocator.free(manufacturer);
            allocator.free(serial_number);
        }

        // 复制设备路径
        const path_len = std.mem.len(info.path);
        const device_path = try allocator.alloc(u8, path_len);
        errdefer allocator.free(device_path);
        @memcpy(device_path, info.path[0..path_len]);

        // 检测设备类型
        const device_type = detectDeviceType(info.usage_page, info.usage, product_name);

        try devices.append(.{
            .vid = try allocator.dupe(u8, vid_str),
            .pid = try allocator.dupe(u8, pid_str),
            .product_name = product_name,
            .manufacturer = manufacturer,
            .serial_number = serial_number,
            .device_path = device_path,
            .device_type = device_type,
            .usage_page = info.usage_page,
            .usage = info.usage,
        });
    }

    return devices;
}

/// 打开指定路径的 HID 设备
pub fn openDevice(device_path: []const u8) !*anyopaque {
    // 创建以 null 结尾的字符串
    var path_buffer: [512]u8 = undefined;
    if (device_path.len >= path_buffer.len) {
        return error.PathTooLong;
    }
    @memcpy(path_buffer[0..device_path.len], device_path);
    path_buffer[device_path.len] = 0;

    const device = c.hid_open_path(@ptrCast(&path_buffer));
    if (device == null) {
        return error.OpenFailed;
    }

    return @ptrCast(device);
}

/// 打开指定 VID/PID 的最佳设备接口
/// 自动选择正确的 HID 接口:
/// - 优先选择 usage_page == 0xFF00 (vendor-specific interface)
/// - 其次选择 DeviceType.other
/// - 对于相同优先级，选择路径编号较大的 (input2 > input1 > input0)
pub fn openDeviceByVidPid(allocator: std.mem.Allocator, vid: []const u8, pid: []const u8) !*anyopaque {
    const devices = try enumerateDevices(allocator);
    defer {
        for (devices.items) |*dev| {
            dev.deinit(allocator);
        }
        devices.deinit();
    }

    var best_path: ?[]const u8 = null;
    var best_priority: u16 = 65535;

    // 转换 VID/PID 为数字进行比较
    const target_vid = std.fmt.parseInt(u16, vid, 16) catch return error.InvalidVid;
    const target_pid = std.fmt.parseInt(u16, pid, 16) catch return error.InvalidPid;

    for (devices.items) |dev| {
        const dev_vid = std.fmt.parseInt(u16, dev.vid, 16) catch continue;
        const dev_pid = std.fmt.parseInt(u16, dev.pid, 16) catch continue;

        if (dev_vid == target_vid and dev_pid == target_pid) {
            // 参考 WebHID 的接口选择逻辑:
            // WebHID 会将同一设备的所有接口都暴露给用户
            // 在命令行环境中，我们需要自动选择最合适的接口

            var priority: u16 = 5000; // 基础优先级

            // 优先选择厂商自定义接口（通常是 EEPROM 控制接口）
            if (dev.usage_page == 0xFF01) {
                // 0xFF01 通常是 Feature Report 控制接口
                priority = 1000; // 最高优先级
            } else if (dev.usage_page == 0xFF00) {
                // 0xFF00 是备选厂商接口
                priority = 1100;
            } else if (dev.usage_page >= 0xFF02) {
                // 其他厂商接口
                priority = 1200;
            } else if (dev.usage_page == 0x0001) {
                // Generic Desktop Controls
                if (dev.usage == 0x0002) {
                    // Mouse - 排除
                    priority = 9000;
                } else if (dev.usage == 0x0006) {
                    // Keyboard - 排除
                    priority = 9100;
                } else {
                    // Other generic desktop
                    priority = 3000;
                }
            } else if (dev.usage_page == 0x000C) {
                // Consumer Control - 可能是数据接口
                priority = 2000;
            } else {
                // Other usage pages
                priority = 3000;
            }

            // 关键：对于多接口设备，接口编号较大的通常是数据接口
            // 从 /dev/hidrawN 提取 N，编号越大优先级越高
            if (std.mem.lastIndexOf(u8, dev.device_path, "hidraw")) |idx| {
                const num_start = idx + 6; // "hidraw".len
                if (num_start < dev.device_path.len) {
                    const num_str = dev.device_path[num_start..];
                    if (std.fmt.parseInt(u8, num_str, 10)) |num| {
                        // 接口编号作为主要优先级因子
                        // 编号大的接口优先（通常 input2 > input1 > input0）
                        priority = priority -| (num * 10);
                    } else |_| {}
                }
            }

            if (priority < best_priority) {
                best_priority = priority;
                best_path = dev.device_path;
            }
        }
    }

    if (best_path) |path| {
        std.debug.print("🔧 为 VID={s} PID={s} 选择接口: {s} (优先级={})\n", .{ vid, pid, path, best_priority });
        return try openDevice(path);
    }

    return error.DeviceNotFound;
}

/// 关闭 HID 设备
pub fn closeDevice(handle: *anyopaque) void {
    const device: *hid_device = @ptrCast(@alignCast(handle));
    c.hid_close(device);
}

/// 从 HID 设备读取数据
pub fn readDevice(handle: *anyopaque, buffer: []u8) !usize {
    const device: *hid_device = @ptrCast(@alignCast(handle));
    const result = c.hid_read(device, buffer.ptr, buffer.len);
    if (result < 0) {
        return error.ReadFailed;
    }
    return @intCast(result);
}

/// 从 HID 设备读取数据（带超时）
pub fn readDeviceTimeout(handle: *anyopaque, buffer: []u8, timeout_ms: i32) !usize {
    const device: *hid_device = @ptrCast(@alignCast(handle));
    const result = c.hid_read_timeout(device, buffer.ptr, buffer.len, timeout_ms);
    if (result < 0) {
        return error.ReadFailed;
    }
    return @intCast(result);
}

/// 向 HID 设备写入数据
pub fn writeDevice(handle: *anyopaque, data: []const u8) !usize {
    const device: *hid_device = @ptrCast(@alignCast(handle));
    const result = c.hid_write(device, data.ptr, data.len);
    if (result < 0) {
        return error.WriteFailed;
    }
    return @intCast(result);
}

/// 发送 Feature Report
pub fn sendFeatureReport(handle: *anyopaque, data: []const u8) !usize {
    const device: *hid_device = @ptrCast(@alignCast(handle));
    const result = c.hid_send_feature_report(device, data.ptr, data.len);
    if (result < 0) {
        return error.SendFeatureFailed;
    }
    return @intCast(result);
}

/// 获取 Feature Report
pub fn getFeatureReport(handle: *anyopaque, buffer: []u8) !usize {
    const device: *hid_device = @ptrCast(@alignCast(handle));
    const result = c.hid_get_feature_report(device, buffer.ptr, buffer.len);
    if (result < 0) {
        return error.GetFeatureFailed;
    }
    return @intCast(result);
}

/// 读取数据(使用 hid_read,带超时)
pub fn readTimeout(handle: *anyopaque, buffer: []u8, timeout_ms: c_int) !usize {
    const device: *hid_device = @ptrCast(@alignCast(handle));
    const result = c.hid_read_timeout(device, buffer.ptr, buffer.len, timeout_ms);
    if (result < 0) {
        return error.ReadFailed;
    }
    return @intCast(result);
}

/// 获取最后的错误信息
pub fn getError(handle: *anyopaque) []const u8 {
    const device: *hid_device = @ptrCast(@alignCast(handle));
    const err_str = c.hid_error(device);
    const len = std.mem.len(err_str);
    return err_str[0..len];
}

/// 获取 Report Descriptor（原始字节）
pub fn getReportDescriptor(handle: *anyopaque, buffer: []u8) !usize {
    const device: *hid_device = @ptrCast(@alignCast(handle));
    const result = c.hid_get_report_descriptor(device, buffer.ptr, buffer.len);
    if (result < 0) {
        return error.GetDescriptorFailed;
    }
    return @intCast(result);
}

/// 检测指定 Report ID 是否支持 Feature Report
/// 通过尝试读取来检测（类似 WebHID 的方式）
pub fn hasFeatureReport(handle: *anyopaque, report_id: u8) bool {
    var test_buffer: [256]u8 = undefined;
    test_buffer[0] = report_id;

    const device: *hid_device = @ptrCast(@alignCast(handle));
    const result = c.hid_get_feature_report(device, &test_buffer, test_buffer.len);

    return result > 0;
}

/// 扫描设备支持的 Feature Report IDs（0x00-0xFF）
pub fn scanFeatureReports(allocator: std.mem.Allocator, handle: *anyopaque) ![]u8 {
    var supported_ids = std.ArrayList(u8).init(allocator);
    errdefer supported_ids.deinit();

    std.debug.print("🔍 扫描支持的 Feature Report IDs...\n", .{});

    // 扫描所有可能的 Report ID
    var report_id: u16 = 0;
    while (report_id <= 255) : (report_id += 1) {
        const id: u8 = @intCast(report_id);

        if (hasFeatureReport(handle, id)) {
            try supported_ids.append(id);
            std.debug.print("  ✓ Report ID 0x{x:0>2} 支持 Feature Report\n", .{id});
        }
    }

    std.debug.print("✅ 扫描完成，找到 {} 个支持的 Report ID\n", .{supported_ids.items.len});

    return supported_ids.toOwnedSlice();
}
