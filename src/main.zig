const std = @import("std");
const webui = @import("webui");
const hid = @import("hid.zig");
const whitelist = @import("device_whitelist");
const builtin = @import("builtin");

// Windows API（仅在Windows平台上可用）
const windows_mutex = if (builtin.target.os.tag == .windows) struct {
    const windows = std.os.windows;
    const HANDLE = windows.HANDLE;
    const DWORD = windows.DWORD;
    const BOOL = windows.BOOL;
    const LPCWSTR = windows.LPCWSTR;

    extern "kernel32" fn CreateMutexW(lpMutexAttributes: ?*anyopaque, bInitialOwner: BOOL, lpName: LPCWSTR) callconv(windows.WINAPI) ?HANDLE;
    extern "kernel32" fn ReleaseMutex(hMutex: HANDLE) callconv(windows.WINAPI) BOOL;
    extern "kernel32" fn CloseHandle(hObject: HANDLE) callconv(windows.WINAPI) BOOL;
    extern "kernel32" fn GetLastError() callconv(windows.WINAPI) DWORD;

    const ERROR_ALREADY_EXISTS: DWORD = 183;
} else struct {};

// ============================================================================
// HID Device Reader - 基于 WebHID 规范的通用 HID 设备读取程序
// ============================================================================
//
// 本程序采用符合 WebHID 规范的通用方法进行 HID 设备访问：
//
// 1. 【通用层】接口识别和选择：
//    - 基于 HID Usage Page/Usage 自动识别设备功能
//    - 智能选择最佳接口（排除 Mouse/Keyboard，优先 Consumer/Vendor）
//    - 参考：WebHID API - HIDDevice.collections[].usagePage/usage
//
// 2. 【通用层】Report Descriptor 扫描：
//    - 扫描所有支持的 Feature Report IDs (0x00-0xFF)
//    - 验证所需 Report ID 的可用性
//    - 参考：WebHID API - HIDDevice.collections[].featureReports
//
// 3. 【应用层】设备特定协议：
//    - EEPROM 读取命令（厂商自定义，非 HID 标准）
//    - 两种读取模式：8系（逐字节）和 9系（32字节批量）
//
// 相关规范：
// - WebHID API: https://wicg.github.io/webhid/
// - USB HID Usage Tables: https://www.usb.org/document-library/hid-usage-tables-122
// - USB HID Class Definition: https://www.usb.org/document-library/device-class-definition-hid-111
//
// ============================================================================

// 全局内存分配器
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

// ============ 全局状态变量 ============
// 标记是否正在读取设备数据
var is_reading = std.atomic.Value(bool).init(false);
// 设备列表访问互斥锁，保护多线程访问
var device_mutex = std.Thread.Mutex{};
// WebUI 主窗口实例
var main_window: webui = undefined;
// 当前读取的设备路径
var current_device_path: ?[]const u8 = null;
// 设备路径访问互斥锁
var device_path_mutex = std.Thread.Mutex{};
// 当前设备的读取模式
var current_device_mode: u8 = 2; // 默认9系
// 当前读取的文件名
var current_filename: ?[]const u8 = null;
var filename_mutex = std.Thread.Mutex{};

// 内嵌的 HTML 界面文件
// @embedFile 会在编译时加载文件内容，路径相对于当前 .zig 文件
const html_content = @embedFile("index.html");

// ============ JSON 辅助函数 ============

/// 转义 JSON 字符串中的特殊字符
/// 处理: " \ / \b \f \n \r \t 以及其他控制字符
fn escapeJsonString(alloc: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = std.ArrayList(u8).init(alloc);
    errdefer result.deinit();

    for (input) |ch| {
        switch (ch) {
            '"' => try result.appendSlice("\\\""),
            '\\' => try result.appendSlice("\\\\"),
            '\n' => try result.appendSlice("\\n"), // 0x0A
            '\r' => try result.appendSlice("\\r"), // 0x0D
            '\t' => try result.appendSlice("\\t"), // 0x09
            '\x08' => try result.appendSlice("\\b"), // backspace 0x08
            '\x0C' => try result.appendSlice("\\f"), // form feed 0x0C
            // 其他控制字符: 0x00-0x07, 0x0B, 0x0E-0x1F
            0x00...0x07, 0x0B, 0x0E...0x1F => {
                try result.writer().print("\\u{x:0>4}", .{ch});
            },
            else => try result.append(ch),
        }
    }

    return result.toOwnedSlice();
}

// ============ WebUI 回调函数 ============

/// 获取设备列表的回调函数
/// 该函数会被前端 JavaScript 通过 webui.call('getDevices') 调用
/// 返回 JSON 格式的设备列表
fn getDevices(e: *webui.Event) void {
    // 加锁保护设备列表访问
    device_mutex.lock();
    defer device_mutex.unlock();

    // 枚举所有 HID 设备
    var devices = hid.enumerateDevices(allocator) catch {
        // 枚举失败，返回错误 JSON
        e.returnString("{\"error\":\"Failed to enumerate devices\"}");
        return;
    };
    defer devices.deinit();

    // 构建 JSON 响应字符串
    var json_str = std.ArrayList(u8).init(allocator);
    defer json_str.deinit();

    const writer = json_str.writer();
    writer.writeAll("[") catch return;

    // 遍历所有设备，只返回白名单中的设备
    var device_count: usize = 0;
    for (devices.items) |device| {
        // 返回所有设备，但标识是否在白名单中
        const is_supported = whitelist.isDeviceSupported(device.vid, device.pid) != null;

        if (device_count > 0) writer.writeAll(",") catch return;

        // 转义设备路径中的反斜杠（Windows 路径）
        var escaped_path = std.ArrayList(u8).init(allocator);
        defer escaped_path.deinit();
        for (device.device_path) |ch| {
            if (ch == '\\') {
                escaped_path.appendSlice("\\\\") catch continue;
            } else {
                escaped_path.append(ch) catch continue;
            }
        }

        // 转义 JSON 字符串字段
        const escaped_name = escapeJsonString(allocator, device.product_name) catch {
            std.debug.print("警告: 无法转义产品名称\n", .{});
            continue;
        };
        defer allocator.free(escaped_name);

        const escaped_manufacturer = escapeJsonString(allocator, device.manufacturer) catch {
            std.debug.print("警告: 无法转义制造商名称\n", .{});
            continue;
        };
        defer allocator.free(escaped_manufacturer);

        const escaped_serial = escapeJsonString(allocator, device.serial_number) catch {
            std.debug.print("警告: 无法转义序列号\n", .{});
            continue;
        };
        defer allocator.free(escaped_serial);

        // 格式化单个设备信息为 JSON 对象，添加 supported 字段标识是否可读取
        std.fmt.format(writer, "{{\"vid\":\"{s}\",\"pid\":\"{s}\",\"name\":\"{s}\",\"manufacturer\":\"{s}\",\"serial\":\"{s}\",\"type\":{d},\"path\":\"{s}\",\"usagePage\":\"0x{X:0>4}\",\"usage\":\"0x{X:0>2}\",\"supported\":{s}}}", .{
            device.vid,
            device.pid,
            escaped_name,
            escaped_manufacturer,
            escaped_serial,
            @intFromEnum(device.device_type),
            escaped_path.items,
            device.usage_page,
            device.usage,
            if (is_supported) "true" else "false",
        }) catch return;
        device_count += 1;
    }
    writer.writeAll("]") catch return;

    // 将 JSON 字符串返回给前端
    // 需要添加空终止符，因为 returnString 需要 [:0]const u8 类型
    json_str.append(0) catch return;
    const json_with_sentinel: [:0]const u8 = json_str.items[0 .. json_str.items.len - 1 :0];
    e.returnString(json_with_sentinel);
}

/// 开始读取设备数据的回调函数
fn startReading(e: *webui.Event) void {
    if (is_reading.load(.acquire)) {
        std.debug.print("已经在读取中\n", .{});
        e.returnString("{\"error\":\"Already reading\"}");
        return;
    }

    const params_json = e.getString();
    if (params_json.len > 0) {
        std.debug.print("📱 读取参数: {s}\n", .{params_json});

        // 简单解析 JSON 提取设备路径和VID/PID
        var device_path: ?[]const u8 = null;
        var device_vid: ?[]const u8 = null;
        var device_pid: ?[]const u8 = null;

        if (std.mem.indexOf(u8, params_json, "\"path\":\"")) |start_idx| {
            const path_start = start_idx + "\"path\":\"".len;
            if (std.mem.indexOfPos(u8, params_json, path_start, "\"")) |end_idx| {
                device_path = params_json[path_start..end_idx];
            }
        }

        if (std.mem.indexOf(u8, params_json, "\"vid\":\"")) |start_idx| {
            const vid_start = start_idx + "\"vid\":\"".len;
            if (std.mem.indexOfPos(u8, params_json, vid_start, "\"")) |end_idx| {
                device_vid = params_json[vid_start..end_idx];
            }
        }

        if (std.mem.indexOf(u8, params_json, "\"pid\":\"")) |start_idx| {
            const pid_start = start_idx + "\"pid\":\"".len;
            if (std.mem.indexOfPos(u8, params_json, pid_start, "\"")) |end_idx| {
                device_pid = params_json[pid_start..end_idx];
            }
        }

        if (device_path != null and device_vid != null and device_pid != null) {
            // 检查设备是否在白名单中，并获取读取模式
            if (whitelist.isDeviceSupported(device_vid.?, device_pid.?)) |config| {
                // 释放旧的设备路径
                device_path_mutex.lock();
                defer device_path_mutex.unlock();
                if (current_device_path) |old_path| {
                    allocator.free(old_path);
                }
                // 保存 VID/PID 而不是路径，稍后根据VID/PID选择最佳接口
                const vid_pid = std.fmt.allocPrint(allocator, "{s}:{s}", .{ device_vid.?, device_pid.? }) catch null;
                current_device_path = vid_pid;

                const mode_name = if (config.mode == 1) "A8xx/8系 (逐字节)" else "A9xx/9系 (32字节批量)";
                std.debug.print("💿 设备 VID:PID={s}\n", .{vid_pid.?});
                std.debug.print("📋 自动选择读取模式: {s}\n", .{mode_name});

                // 将读取模式存储到全局变量中供读取线程使用
                // 创建一个新的全局变量来存储当前设备的读取模式
                current_device_mode = config.mode;
            } else {
                std.debug.print("❌ 设备 {s}:{s} 不在白名单中，无法读取\n", .{ device_vid.?, device_pid.? });
                e.returnString("{\"error\":\"Device not supported\"}");
                return;
            }
        } else {
            std.debug.print("❌ 解析设备参数失败\n", .{});
            e.returnString("{\"error\":\"Invalid device parameters\"}");
            return;
        }
    }

    is_reading.store(true, .release);

    const thread = std.Thread.spawn(.{}, readDeviceThread, .{}) catch {
        is_reading.store(false, .release);
        e.returnString("{\"error\":\"Failed to start thread\"}");
        return;
    };
    thread.detach();

    std.debug.print("✅ 开始读取设备\n", .{});
    e.returnString("{\"success\":true}");
}

/// 停止读取设备数据的回调函数
/// 被前端 JavaScript 通过 webui.call('stopReading') 调用
fn stopReading(e: *webui.Event) void {
    _ = e; // 未使用的参数

    // 清除读取标志，通知读取线程停止
    is_reading.store(false, .release);
    std.debug.print("⏸️ 停止读取设备\n", .{});
}

/// 将数据保存到文件
fn saveDataToFile(address: u32, raw_data: []const u8, hex_data: []const u8) void {
    // 获取当前文件名
    filename_mutex.lock();
    const filename = current_filename;
    filename_mutex.unlock();

    if (filename == null) {
        std.debug.print("⚠️  文件名未设置\n", .{});
        return;
    }

    // 如果是第一次读取（地址为0），则清空文件
    const should_truncate = (address == 0);

    // 确保数据目录存在
    std.fs.cwd().makeDir("data") catch |err| {
        if (err != error.PathAlreadyExists) {
            std.debug.print("⚠️  创建data目录失败: {}\n", .{err});
            return;
        }
    };

    // 打开或创建文件（第一次读取时截断，后续追加）
    const file = std.fs.cwd().createFile(filename.?, .{ .truncate = should_truncate }) catch |err| {
        std.debug.print("⚠️  创建数据文件失败: {}\n", .{err});
        return;
    };
    defer file.close();

    // 如果不是截断模式，移到文件末尾
    if (!should_truncate) {
        file.seekFromEnd(0) catch {};
    }

    // 写入数据
    const writer = file.writer();
    std.fmt.format(writer, "0x{x:0>4}: {s}\n", .{ address, hex_data }) catch |err| {
        std.debug.print("⚠️  写入数据文件失败: {}\n", .{err});
    };

    _ = raw_data; // 避免未使用变量警告
}

// 历史记录功能已移除，数据自动保存到文件
fn saveHistoryRecord(e: *webui.Event) void {
    e.returnString("{\"success\":true}");
}

// 历史记录功能已移除
fn getHistoryRecords(e: *webui.Event) void {
    e.returnString("[]");
}

// 历史记录功能已移除
fn deleteHistoryRecord(e: *webui.Event) void {
    e.returnString("{\"success\":false,\"error\":\"Feature removed\"}");
}

// 历史记录功能已移除
fn clearAllHistory(e: *webui.Event) void {
    e.returnString("{\"success\":false,\"error\":\"Feature removed\"}");
}

/// 清理资源的回调函数
/// 在窗口关闭时被调用，用于清理所有服务和资源
fn cleanup(e: *webui.Event) void {
    std.debug.print("🧹 清理资源和服务...\n", .{});
    cleanupResources();
    std.debug.print("✅ 清理完成\n", .{});
    e.returnString("{\"success\":true}");
}

/// 窗口事件处理器
/// 监听窗口关闭事件，立即退出程序
fn handleWindowEvents(e: *webui.Event) void {
    if (e.event_type == .EVENT_DISCONNECTED) {
        std.debug.print("❌ 窗口关闭事件，立即退出\n", .{});
        cleanupResources();
        webui.exit();
    }
}

/// 清理所有资源
fn cleanupResources() void {
    // 停止读取
    is_reading.store(false, .release);

    // 释放设备路径内存
    device_path_mutex.lock();
    if (current_device_path) |path| {
        allocator.free(path);
        current_device_path = null;
    }
    device_path_mutex.unlock();

    // 释放文件名内存
    filename_mutex.lock();
    if (current_filename) |fname| {
        allocator.free(fname);
        current_filename = null;
    }
    filename_mutex.unlock();
}

/// 设备读取线程函数
/// 在后台持续读取真实 HID 设备数据并推送到前端，同时保存到文件
fn readDeviceThread() void {
    device_path_mutex.lock();
    const vid_pid_copy = if (current_device_path) |p| allocator.dupe(u8, p) catch null else null;
    device_path_mutex.unlock();

    const vid_pid = vid_pid_copy orelse {
        std.debug.print("❌ 未设置设备 VID:PID\n", .{});
        is_reading.store(false, .release);
        return;
    };
    defer allocator.free(vid_pid);

    // 解析 VID:PID
    const colon_pos = std.mem.indexOf(u8, vid_pid, ":") orelse {
        std.debug.print("❌ VID:PID 格式错误\n", .{});
        is_reading.store(false, .release);
        return;
    };
    const vid = vid_pid[0..colon_pos];
    const pid = vid_pid[colon_pos + 1 ..];

    const mode = current_device_mode;
    const mode_name = if (mode == 1) "8系(逐字节)" else "9系(32字节批量)";
    std.debug.print("📖 打开设备: VID={s} PID={s} [模式: {s}]\n", .{ vid, pid, mode_name });

    // 生成带时间戳的文件名
    const timestamp = std.time.milliTimestamp();
    const filename = std.fmt.allocPrint(allocator, "data/device_data_{d}.hid", .{timestamp}) catch {
        std.debug.print("❌ 无法生成文件名\n", .{});
        is_reading.store(false, .release);
        return;
    };
    defer allocator.free(filename);

    // 保存文件名到全局变量
    filename_mutex.lock();
    if (current_filename) |old_fname| {
        allocator.free(old_fname);
    }
    current_filename = allocator.dupe(u8, filename) catch null;
    filename_mutex.unlock();

    std.debug.print("📁 数据将保存到: {s}\n", .{filename});

    // 通知前端文件名
    const filename_msg = std.fmt.allocPrintZ(allocator, "setCurrentFilename('{s}')", .{filename}) catch null;
    if (filename_msg) |msg| {
        defer allocator.free(msg);
        _ = main_window.run(msg);
    }

    // ============ 通用方法 1: 智能接口选择 ============
    // 基于 WebHID 规范，使用 Usage Page/Usage 自动选择最佳接口
    // 优先级算法：
    // 1. 排除标准输入设备 (Mouse/Keyboard)
    // 2. 优先选择 Consumer Control (0x000C) 或 Vendor-Defined (0xFF00+)
    // 3. 接口编号大的优先 (通常数据接口编号较大)
    std.debug.print("🔧 使用智能接口选择算法（基于 Usage Page/Usage）...\n", .{});
    const device_handle = hid.openDeviceByVidPid(allocator, vid, pid) catch |err| {
        std.debug.print("❌ 无法打开设备: {}\n", .{err});
        const error_msg = std.fmt.allocPrintZ(allocator, "addLogFromBackend('❌ 无法打开设备: {}')", .{err}) catch {
            is_reading.store(false, .release);
            return;
        };
        defer allocator.free(error_msg);
        _ = main_window.run(error_msg);
        is_reading.store(false, .release);
        return;
    };
    defer hid.closeDevice(device_handle);

    std.debug.print("✅ 设备已打开（自动选择了最佳接口）\n", .{});

    // ============ 通用方法 2: 扫描 Feature Reports ============
    // 符合 WebHID Report Descriptor 解析规范
    // 扫描设备支持的所有 Feature Report IDs (0x00-0xFF)
    // 类似于 WebHID 的 device.collections[].featureReports
    std.debug.print("🔍 扫描设备支持的 Feature Report IDs（WebHID 规范）...\n", .{});
    const supported_reports = hid.scanFeatureReports(allocator, device_handle) catch |err| {
        std.debug.print("❌ 扫描 Feature Reports 失败: {}\n", .{err});
        const error_msg = std.fmt.allocPrintZ(allocator, "addLogFromBackend('❌ 设备不支持 Feature Report 扫描')", .{}) catch {
            is_reading.store(false, .release);
            return;
        };
        defer allocator.free(error_msg);
        _ = main_window.run(error_msg);
        is_reading.store(false, .release);
        return;
    };
    defer allocator.free(supported_reports);

    // 显示支持的 Report IDs
    std.debug.print("📊 设备支持 {} 个 Feature Report IDs: ", .{supported_reports.len});
    for (supported_reports) |report_id| {
        std.debug.print("0x{X:0>2} ", .{report_id});
    }
    std.debug.print("\n", .{});

    // ============ 通用方法 3: 验证 Report ID 支持 ============
    // 检查是否支持所需的 Report ID (EEPROM 访问需要 0x07)
    // 而不是通过"读取非零数据"来判断接口是否正确
    var supports_0x07 = false;
    for (supported_reports) |report_id| {
        if (report_id == 0x07) {
            supports_0x07 = true;
            break;
        }
    }

    if (!supports_0x07) {
        std.debug.print("❌ 设备不支持 Report ID 0x07，无法进行 EEPROM 读取\n", .{});
        const error_msg = std.fmt.allocPrintZ(allocator, "addLogFromBackend('❌ 设备不支持 EEPROM 访问 (缺少 Report ID 0x07)')", .{}) catch {
            is_reading.store(false, .release);
            return;
        };
        defer allocator.free(error_msg);
        _ = main_window.run(error_msg);
        is_reading.store(false, .release);
        return;
    }

    std.debug.print("✅ 设备支持 EEPROM 访问，开始读取数据...\n", .{});

    // ============ 设备特定协议层 ============
    // 以下代码使用设备特定的 EEPROM 读取协议
    // 注意：这不是 HID 标准的一部分，而是硬件厂商自定义的应用层协议
    // 通用的部分（接口选择、Report 扫描）已经在上面完成

    // 测试 JavaScript 回调是否可用
    std.debug.print("🧪 测试 JavaScript 回调函数...\n", .{});
    main_window.run("testCallback()");
    std.debug.print("🧪 已调用 testCallback()\n", .{});

    // 根据模式选择读取方法（设备特定）
    if (mode == 1) {
        readDeviceType8(device_handle);
    } else {
        readDeviceType9(device_handle);
    }

    std.debug.print("✅ 设备读取线程退出\n", .{});
}

/// 8系读取方法 (EEPROMPageRead) - 逐字节读取
fn readDeviceType8(device_handle: *anyopaque) void {
    var address: u32 = 0;
    var total_bytes: u64 = 0;

    var feature_report: [8]u8 = undefined;
    const EEP_RW_CMD: u8 = 0x18;
    const READ_SIZE: usize = 32;
    const EEP_SIZE: u32 = 4096;

    while (is_reading.load(.acquire) and address < EEP_SIZE) {
        // 初始化寄存器
        for (0..READ_SIZE) |i| {
            @memset(&feature_report, 0);
            feature_report[0] = 0x07;
            feature_report[1] = EEP_RW_CMD;
            feature_report[2] = 0x03; // usbRegWEn + softCtrlEppEn
            feature_report[3] = @intCast(i);
            feature_report[4] = @intCast(address % 256);
            feature_report[5] = @intCast(address / 256);
            feature_report[6] = 0;
            feature_report[7] = @intCast(READ_SIZE - 1);

            _ = hid.sendFeatureReport(device_handle, &feature_report) catch |err| {
                std.debug.print("❌ 初始化寄存器失败: {}\n", .{err});
                return;
            };
            std.time.sleep(2 * std.time.ns_per_ms);
        }

        // 清除控制位
        @memset(&feature_report, 0);
        feature_report[0] = 0x07;
        feature_report[1] = EEP_RW_CMD;
        feature_report[2] = 0x00;
        _ = hid.sendFeatureReport(device_handle, &feature_report) catch {};
        std.time.sleep(2 * std.time.ns_per_ms);

        // 逐字节读取数据
        var page_data: [READ_SIZE]u8 = undefined;
        for (0..READ_SIZE) |i| {
            if (!is_reading.load(.acquire)) break;

            // 发送读取命令
            @memset(&feature_report, 0);
            feature_report[0] = 0x07;
            feature_report[1] = EEP_RW_CMD;
            feature_report[2] = 0x05; // eepREn + softCtrlEppEn
            feature_report[3] = @intCast(i);
            feature_report[4] = @intCast(address % 256);
            feature_report[5] = @intCast(address / 256);
            feature_report[6] = 0;
            feature_report[7] = @intCast(READ_SIZE - 1);

            _ = hid.sendFeatureReport(device_handle, &feature_report) catch |err| {
                std.debug.print("❌ 读取命令失败: {}\n", .{err});
                continue;
            };
            std.time.sleep(2 * std.time.ns_per_ms);

            // 获取数据 - 使用 getFeatureReport (Feature Report 已确认支持)
            @memset(&feature_report, 0);
            feature_report[0] = 0x07;
            const read_bytes = hid.getFeatureReport(device_handle, &feature_report) catch |err| {
                std.debug.print("❌ 获取数据失败: {}\n", .{err});
                continue;
            };

            if (i == 0) {
                std.debug.print("🔍 读取到 {} 字节，数据: [{x:0>2}] {x:0>2} {x:0>2} {x:0>2} {x:0>2} {x:0>2} {x:0>2} {x:0>2}\n", .{
                    read_bytes,
                    feature_report[0],
                    feature_report[1],
                    feature_report[2],
                    feature_report[3],
                    feature_report[4],
                    feature_report[5],
                    feature_report[6],
                    feature_report[7],
                });
            }

            page_data[i] = feature_report[1];
        }

        // 清除控制位
        @memset(&feature_report, 0);
        feature_report[0] = 0x07;
        feature_report[1] = EEP_RW_CMD;
        feature_report[2] = 0x00;
        _ = hid.sendFeatureReport(device_handle, &feature_report) catch {};
        std.time.sleep(2 * std.time.ns_per_ms);

        sendDataToFrontend(address, &page_data, &total_bytes);
        address += @as(u32, @intCast(READ_SIZE));
        updateProgress(address, total_bytes, EEP_SIZE);
        std.time.sleep(100 * std.time.ns_per_ms);
    }

    // 设置读取完成标志
    is_reading.store(false, .release);
    std.debug.print("🛑 8系读取完成，设置 is_reading = false\n", .{});
    notifyReadComplete(total_bytes);
}

/// 9系读取方法 (EEPROMPageRead32) - 32字节批量读取
fn readDeviceType9(device_handle: *anyopaque) void {
    var address: u32 = 0;
    var total_bytes: u64 = 0;

    var feature_report: [50]u8 = undefined; // 9系需要50字节
    const EEP_RW_CMD: u8 = 0x18;
    const READ_SIZE: usize = 32;
    const EEP_SIZE: u32 = 4096;

    while (is_reading.load(.acquire) and address < EEP_SIZE) {
        // 清空内部寄存器
        @memset(&feature_report, 0);
        feature_report[0] = 0x07;
        feature_report[1] = EEP_RW_CMD;
        feature_report[2] = 0x03; // usbRegWEn + softCtrlEppEn
        feature_report[3] = 0;
        feature_report[4] = @intCast(address % 256);
        feature_report[5] = @intCast(address / 256);
        feature_report[6] = 0;
        feature_report[7] = @intCast(READ_SIZE - 1 + 64 + 128); // Length

        _ = hid.sendFeatureReport(device_handle, &feature_report) catch |err| {
            std.debug.print("❌ 清空寄存器失败: {}\n", .{err});
            return;
        };
        std.time.sleep(1 * std.time.ns_per_ms);

        // 发送批量读取命令
        @memset(&feature_report, 0);
        feature_report[0] = 0x07;
        feature_report[1] = EEP_RW_CMD;
        feature_report[2] = 0x05; // eepREn + softCtrlEppEn
        feature_report[3] = 0;
        feature_report[4] = @intCast(address % 256);
        feature_report[5] = @intCast(address / 256);
        feature_report[6] = 0;
        feature_report[7] = @intCast(READ_SIZE - 1 + 64 + 128);

        _ = hid.sendFeatureReport(device_handle, &feature_report) catch |err| {
            std.debug.print("❌ 读取命令失败: {}\n", .{err});
            return;
        };
        std.time.sleep(5 * std.time.ns_per_ms);

        // 获取32字节数据
        @memset(&feature_report, 0);
        feature_report[0] = 0x07;
        _ = hid.getFeatureReport(device_handle, &feature_report) catch |err| {
            std.debug.print("❌ 获取数据失败: {}\n", .{err});
            continue;
        };

        // 数据从第2个字节开始（第1个是ReportID）
        var page_data: [READ_SIZE]u8 = undefined;
        for (0..READ_SIZE) |i| {
            page_data[i] = feature_report[i + 1];
        }

        sendDataToFrontend(address, &page_data, &total_bytes);
        address += @as(u32, @intCast(READ_SIZE));
        updateProgress(address, total_bytes, EEP_SIZE);
        std.time.sleep(100 * std.time.ns_per_ms);
    }

    // 设置读取完成标志
    is_reading.store(false, .release);
    std.debug.print("🛑 设置 is_reading = false\n", .{});
    notifyReadComplete(total_bytes);
}

/// 发送数据到前端
fn sendDataToFrontend(address: u32, page_data: []const u8, total_bytes: *u64) void {
    // 构建十六进制数据字符串
    var hex_data = std.ArrayList(u8).init(allocator);
    defer hex_data.deinit();

    for (page_data) |byte| {
        std.fmt.format(hex_data.writer(), "{x:0>2} ", .{byte}) catch continue;
    }

    // 保存到文件
    saveDataToFile(address, page_data, hex_data.items);

    // 发送数据到前端（包含完整数据）
    const js_code = std.fmt.allocPrintZ(allocator, "onDataReceived({d}, '{s}')", .{ address, hex_data.items }) catch return;
    defer allocator.free(js_code);
    _ = main_window.run(js_code);

    total_bytes.* += page_data.len;
}

/// 更新进度
fn updateProgress(address: u32, total_bytes: u64, eep_size: u32) void {
    const progress_percent = @as(f64, @floatFromInt(address)) / @as(f64, @floatFromInt(eep_size)) * 100.0;
    const progress_msg = std.fmt.allocPrintZ(allocator, "updateProgress({d}, {d}, {d:.1})", .{ address, total_bytes, progress_percent }) catch return;
    defer allocator.free(progress_msg);
    _ = main_window.run(progress_msg);
}

/// 通知读取完成
fn notifyReadComplete(total_bytes: u64) void {
    std.debug.print("📢 [notifyReadComplete] 准备通知前端，总字节数: {d}\n", .{total_bytes});
    const complete_msg = std.fmt.allocPrintZ(allocator, "onReadComplete({d})", .{total_bytes}) catch |err| {
        std.debug.print("❌ 构建完成消息失败: {}\n", .{err});
        return;
    };
    defer allocator.free(complete_msg);

    std.debug.print("📤 发送完成消息到前端: {s}\n", .{complete_msg});
    main_window.run(complete_msg);
    std.debug.print("✅ 已调用 window.run()，消息已发送\n", .{});
}

/// 主函数入口
pub fn main() !void {
    // 程序退出时清理内存分配器
    defer _ = gpa.deinit();

    // 创建全局锁，防止程序多开（跨平台实现）
    const lock_file_path = if (builtin.target.os.tag == .windows)
        "C:\\ProgramData\\ReadDeviceApp.lock"
    else
        "/tmp/readdevice.lock";

    const lock_file = std.fs.cwd().createFile(lock_file_path, .{
        .read = true,
        .truncate = false,
    }) catch |err| {
        std.debug.print("⚠️  无法创建锁文件: {}\n", .{err});
        std.time.sleep(2 * std.time.ns_per_s);
        return;
    };
    defer lock_file.close();

    // 尝试获取独占锁
    lock_file.lock(.exclusive) catch {
        std.debug.print("⚠️  程序已在运行，请勿重复打开！\n", .{});
        std.time.sleep(2 * std.time.ns_per_s);
        return;
    };
    defer lock_file.unlock();

    std.debug.print("🚀 HID Device Reader 启动中...\n", .{});
    std.debug.print("📱 使用 WebUI 技术栈\n", .{});
    std.debug.print("📁 数据将自动保存到 data/ 目录\n", .{});

    // 初始化 hidapi
    hid.init() catch |err| {
        std.debug.print("❌ 初始化 hidapi 失败: {}\n", .{err});
        return err;
    };
    defer {
        hid.exit() catch |err| {
            std.debug.print("⚠️  退出 hidapi 失败: {}\n", .{err});
        };
    }

    std.debug.print("✅ hidapi 已初始化\n", .{});

    // 确保数据目录存在
    std.fs.cwd().makeDir("data") catch |err| {
        if (err != error.PathAlreadyExists) {
            std.debug.print("⚠️  创建 data 目录失败: {}\n", .{err});
        }
    };

    // 创建 WebUI 窗口实例
    main_window = webui.newWindow();

    // 根据assets目录位置自动选择根目录
    // Debug模式(zig build run): 使用src/作为根目录
    // Release模式(直接运行exe): 使用exe所在目录
    const exe_path = std.fs.selfExePathAlloc(allocator) catch |err| {
        std.debug.print("❌ 无法获取可执行文件路径: {}\n", .{err});
        return err;
    };
    defer allocator.free(exe_path);

    const exe_dir = std.fs.path.dirname(exe_path) orelse ".";

    // 检查exe所在目录是否有assets文件夹（Release模式）
    const assets_in_exe_dir = blk: {
        const test_path = std.fs.path.join(allocator, &[_][]const u8{ exe_dir, "assets" }) catch break :blk false;
        defer allocator.free(test_path);

        std.debug.print("🔍 检测资源目录: {s}\n", .{test_path});
        std.fs.accessAbsolute(test_path, .{}) catch |err| {
            std.debug.print("  ❌ 不存在: {}\n", .{err});
            break :blk false;
        };
        std.debug.print("  ✅ 存在\n", .{});
        break :blk true;
    };

    const root_folder = if (assets_in_exe_dir) exe_dir else "src";
    const root_folder_z = allocator.dupeZ(u8, root_folder) catch |err| {
        std.debug.print("❌ 无法复制路径: {}\n", .{err});
        return err;
    };
    defer allocator.free(root_folder_z);

    std.debug.print("📂 静态资源根目录: {s}\n", .{root_folder_z});
    _ = main_window.setRootFolder(root_folder_z);

    // 设置窗口大小和位置
    _ = main_window.setSize(1400, 900);
    _ = main_window.setPosition(100, 50);

    // 将 Zig 函数绑定到 JavaScript，使前端可以通过 webui.call() 调用
    // bind() 返回绑定 ID (usize)，0 表示绑定失败
    _ = main_window.bind("getDevices", getDevices);
    _ = main_window.bind("startReading", startReading);
    _ = main_window.bind("stopReading", stopReading);
    _ = main_window.bind("cleanup", cleanup);

    // 绑定空事件处理器，监听窗口关闭事件
    _ = main_window.bind("", handleWindowEvents);

    // 显示窗口，加载内嵌的 HTML 内容
    // show() 返回 bool，true 表示成功，false 表示失败
    if (!main_window.show(html_content)) {
        std.debug.print("❌ 无法显示窗口\n", .{});
        return;
    }

    std.debug.print("✅ 窗口已打开\n", .{});
    std.debug.print("🎨 等待用户交互...\n", .{});

    // 设置超时时间（单位：秒），0 表示永不超时
    webui.setTimeout(0); // 永不超时，直到用户关闭窗口

    // 阻塞主线程，等待所有 WebUI 窗口关闭
    webui.wait();

    std.debug.print("🔄 正在清理资源...\n", .{});

    // 清理所有资源
    cleanupResources();

    // 删除浏览器配置文件
    webui.deleteAllProfiles();

    // 清理 WebUI 资源
    webui.clean();

    std.debug.print("👋 程序退出\n", .{});

    // 确保程序完全退出
    std.process.exit(0);
}
