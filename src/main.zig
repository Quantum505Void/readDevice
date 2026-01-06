const std = @import("std");
const webui = @import("webui");
const hid = @import("hid.zig");
const whitelist = @import("device_whitelist");

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
        // 格式化单个设备信息为 JSON 对象，添加 supported 字段标识是否可读取
        std.fmt.format(writer, "{{\"vid\":\"{s}\",\"pid\":\"{s}\",\"name\":\"{s}\",\"manufacturer\":\"{s}\",\"serial\":\"{s}\",\"type\":{d},\"path\":\"{s}\",\"usagePage\":\"0x{X:0>4}\",\"usage\":\"0x{X:0>2}\",\"supported\":{s}}}", .{
            device.vid,
            device.pid,
            device.product_name,
            device.manufacturer,
            device.serial_number,
            @intFromEnum(device.device_type),
            device.device_path,
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
                current_device_path = allocator.dupe(u8, device_path.?) catch null;

                const mode_name = if (config.mode == 1) "A8xx/8系 (逐字节)" else "A9xx/9系 (32字节批量)";
                std.debug.print("💿 设备路径: {s}\n", .{device_path.?});
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

    // 停止读取
    is_reading.store(false, .release);

    // 等待一小段时间确保读取线程退出
    std.time.sleep(100 * std.time.ns_per_ms);

    // 释放设备路径
    device_path_mutex.lock();
    defer device_path_mutex.unlock();
    if (current_device_path) |path| {
        allocator.free(path);
        current_device_path = null;
    }

    // 释放文件名
    filename_mutex.lock();
    if (current_filename) |fname| {
        allocator.free(fname);
        current_filename = null;
    }
    filename_mutex.unlock();

    std.debug.print("✅ 清理完成\n", .{});
    e.returnString("{\"success\":true}");
}

/// 设备读取线程函数
/// 在后台持续读取真实 HID 设备数据并推送到前端，同时保存到文件
fn readDeviceThread() void {
    device_path_mutex.lock();
    const path_copy = if (current_device_path) |p| allocator.dupe(u8, p) catch null else null;
    device_path_mutex.unlock();

    const path = path_copy orelse {
        std.debug.print("❌ 未设置设备路径\n", .{});
        is_reading.store(false, .release);
        return;
    };
    defer allocator.free(path);

    const mode = current_device_mode;
    const mode_name = if (mode == 1) "8系(逐字节)" else "9系(32字节批量)";
    std.debug.print("📖 打开设备: {s} [模式: {s}]\n", .{ path, mode_name });

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

    // 打开 HID 设备文件，使用读写模式以支持 Feature Report
    const device_file = std.fs.openFileAbsolute(path, .{ .mode = .read_write }) catch |err| {
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
    defer device_file.close();

    std.debug.print("✅ 设备已打开，开始读取数据...\n", .{});

    // 测试 JavaScript 回调是否可用
    std.debug.print("🧪 测试 JavaScript 回调函数...\n", .{});
    main_window.run("testCallback()");
    std.debug.print("🧪 已调用 testCallback()\n", .{});

    // 根据模式选择读取方法
    if (mode == 1) {
        readDeviceType8(device_file);
    } else {
        readDeviceType9(device_file);
    }

    std.debug.print("✅ 设备读取线程退出\n", .{});
}

/// 8系读取方法 (EEPROMPageRead) - 逐字节读取
fn readDeviceType8(device_file: std.fs.File) void {
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

            hid.LinuxHid.setFeature(device_file, &feature_report) catch |err| {
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
        hid.LinuxHid.setFeature(device_file, &feature_report) catch {};
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

            hid.LinuxHid.setFeature(device_file, &feature_report) catch |err| {
                std.debug.print("❌ 读取命令失败: {}\n", .{err});
                continue;
            };
            std.time.sleep(2 * std.time.ns_per_ms);

            // 获取数据
            @memset(&feature_report, 0);
            feature_report[0] = 0x07;
            _ = hid.LinuxHid.getFeature(device_file, &feature_report) catch |err| {
                std.debug.print("❌ 获取数据失败: {}\n", .{err});
                continue;
            };

            page_data[i] = feature_report[1];
        }

        // 清除控制位
        @memset(&feature_report, 0);
        feature_report[0] = 0x07;
        feature_report[1] = EEP_RW_CMD;
        feature_report[2] = 0x00;
        hid.LinuxHid.setFeature(device_file, &feature_report) catch {};
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
fn readDeviceType9(device_file: std.fs.File) void {
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

        hid.LinuxHid.setFeature(device_file, &feature_report) catch |err| {
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

        hid.LinuxHid.setFeature(device_file, &feature_report) catch |err| {
            std.debug.print("❌ 读取命令失败: {}\n", .{err});
            return;
        };
        std.time.sleep(5 * std.time.ns_per_ms);

        // 获取32字节数据
        @memset(&feature_report, 0);
        feature_report[0] = 0x07;
        _ = hid.LinuxHid.getFeature(device_file, &feature_report) catch |err| {
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

    std.debug.print("🚀 HID Device Reader 启动中...\n", .{});
    std.debug.print("📱 使用 WebUI 技术栈\n", .{});
    std.debug.print("📁 数据将自动保存到 data/ 目录\n", .{});

    // 确保数据目录存在
    std.fs.cwd().makeDir("data") catch |err| {
        if (err != error.PathAlreadyExists) {
            std.debug.print("⚠️  创建 data 目录失败: {}\n", .{err});
        }
    };

    // 创建 WebUI 窗口实例
    main_window = webui.newWindow();

    // 设置静态资源根目录为 src，这样可以访问 /assets/js/ 下的文件
    _ = main_window.setRootFolder("src");

    // 设置窗口大小和位置，避免闪烁
    _ = main_window.setSize(1400, 900);
    _ = main_window.setPosition(100, 50);

    // 设置窗口启动时隐藏，等资源加载完再显示
    _ = main_window.setHide(true);

    // 将 Zig 函数绑定到 JavaScript，使前端可以通过 webui.call() 调用
    // bind() 返回绑定 ID (usize)，0 表示绑定失败
    _ = main_window.bind("getDevices", getDevices);
    _ = main_window.bind("startReading", startReading);
    _ = main_window.bind("stopReading", stopReading);
    _ = main_window.bind("cleanup", cleanup);

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

    // 程序退出前的清理工作
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

    std.debug.print("👋 程序退出\n", .{});
}
