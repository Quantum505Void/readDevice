# HID 设备读取器 (Zig 版本)

这是一个使用 **Zig** 编写的现代化 HID 设备读取工具，采用 **WebUI** 技术将浏览器作为原生 GUI。

## ✨ 特性

- 🚀 **高性能**: 使用 Zig 语言编写，性能优异
- 🌐 **WebUI**: 使用 [zig-webui](https://github.com/webui-dev/zig-webui) 将浏览器作为原生 GUI
- 🔌 **跨平台**: 支持 Linux、Windows 和 macOS（基于 hidapi）
- 📡 **实时数据**: Zig 后端实时读取 HID 设备数据并推送到前端
- 💾 **自动保存**: 每次读取的数据自动保存到带时间戳的 .hid 文件
- 🎨 **美观界面**: 渐变色设计，响应式布局，基于 Vue 3 + Naive UI
- 🔗 **双向通信**: JavaScript 可调用 Zig 函数，Zig 可调用 JavaScript 函数
- 📊 **数据对比**: 支持字节级数据对比和导出功能
- 🖥️ **规范显示**: 数据以十六进制格式规范显示，每16字节一行，易于阅读
- 🔐 **白名单机制**: 自动识别支持的设备，智能选择读取模式
- 🔥 **热插拔监听**: 实时检测设备连接和断开

## 🆕 最新改进 (v3.0)

### 1. � 智能 vcpkg 自动搜索（Windows）
- ✅ **零配置**: 自动查找 vcpkg 安装位置，无需设置环境变量
- ✅ **多路径检测**: 使用 PowerShell 和 where 命令自动定位 vcpkg.exe
- ✅ **智能推断**: 从 vcpkg.exe 路径自动推断 installed 目录
- ✅ **友好提示**: 找不到时提供详细的安装指引
- ✅ **环境变量支持**: 可选手动指定 VCPKG_ROOT 覆盖自动搜索

### 2. 🔐 设备白名单系统
- ✅ **自动识别**: 根据 VID/PID 自动识别支持的设备
- ✅ **智能模式**: 自动选择正确的读取模式（A8xx 逐字节 / A9xx 32字节批量）
- ✅ **可视化标识**: 设备列表中清晰标识"✓ 可读取"和"⚠ 仅查看"
- ✅ **按钮智能**: 选中不支持的设备时读取按钮自动禁用
- ✅ **集中配置**: 白名单配置集中在 `device_whitelist.zig` 中，易于维护
- ✅ **多层验证**: 前端、后端多层白名单验证，确保安全

### 3. 📊 增强的数据显示
- ✅ **代码风格显示**: 使用类似 IDE 的暗色主题显示数据
- ✅ **表格格式**: 每16字节一行，字节之间用空格分隔
- ✅ **丰富提示**: 鼠标悬停显示地址、十六进制、十进制、二进制、ASCII 等信息
- ✅ **字节级对比**: 数据对比时精确到每个字节，颜色高亮差异
- ✅ **滚动同步**: 对比窗口左右滚动自动同步

### 4. 💾 统一文件格式
- ✅ **.hid 格式**: 所有数据文件统一使用 .hid 扩展名
- ✅ **毫秒时间戳**: 文件名格式为 `device_data_时间戳.hid`
- ✅ **自动保存**: 读取过程中实时写入文件
- ✅ **导入导出**: 支持 .hid 文件的导入和对比

### 5. 🔥 热插拔检测
- ✅ **自动刷新**: 每2秒自动检测设备变化
- ✅ **智能通知**: 设备连接/断开时显示通知（按设备去重）
- ✅ **完整显示**: 显示所有连接的设备，包括不在白名单中的

## 🛠️ 技术栈

- **后端**: Zig 0.13.0 + [zig-webui](https://github.com/webui-dev/zig-webui) v2.5.0-beta.2 + [hidapi](https://github.com/libusb/hidapi)
- **前端**: Vue 3 (UMD) + Naive UI + HTML5 + CSS3
- **数据存储**: 文本文件（`data/device_data_*.hid`，每次读取独立文件）
- **设备接口**: hidapi（跨平台 HID 库）
  - Linux: hidapi-hidraw
  - Windows: Windows HID API
  - macOS: IOHidManager (IOKit)

### ⚠️ 为什么不能直接使用 .vue 和 .ts 文件？

**原因**:
1. **无构建环境**: Zig 项目没有 Node.js / npm，无法运行 Vite/Webpack
2. **@embedFile 限制**: HTML 在编译时嵌入二进制文件，必须是可直接运行的 JS
3. **WebUI 架构**: 使用轻量级 WebView，不支持模块热更新和打包

**当前方案 (推荐)**:
- ✅ Vue 3 UMD 版本 (通过 `<script>` 标签加载)
- ✅ Naive UI UMD 版本
- ✅ 所有代码在 `index.html` 中 (零构建步骤)
- ✅ 单个可执行文件，易于分发

**如需使用 .vue/.ts**:
1. 创建独立的 Vite 项目 → 构建 → 将 `dist/` 复制到 `src/assets/`
2. 或者考虑使用 **Tauri** (Rust + 完整前端工具链)

详细说明请参考项目 Wiki。

## 📦 依赖项

### Windows

**✨ 自动搜索 vcpkg** - 构建系统会自动查找 vcpkg 安装位置，无需手动配置！

```powershell
# 1. 安装 vcpkg (如果还没有)
git clone https://github.com/microsoft/vcpkg
cd vcpkg
.\bootstrap-vcpkg.bat

# 2. 安装 hidapi
.\vcpkg install hidapi:x64-windows

# 3. 将 vcpkg.exe 添加到 PATH（推荐）
# 或者设置环境变量（可选）
$env:VCPKG_ROOT = "C:\path\to\vcpkg\installed\x64-windows"
```

**自动搜索机制**：
1. ✅ 首先检查环境变量 `VCPKG_ROOT`
2. ✅ 自动执行 `where vcpkg` 或 PowerShell 查找 vcpkg.exe
3. ✅ 从 vcpkg.exe 路径推断 `installed\x64-windows` 目录
4. ✅ 完全自动配置，零手动操作

**手动指定路径（可选）**：
```powershell
# 永久设置环境变量
[Environment]::SetEnvironmentVariable("VCPKG_ROOT", "C:\vcpkg\installed\x64-windows", "User")

# 或临时设置（当前会话）
$env:VCPKG_ROOT = "C:\vcpkg\installed\x64-windows"
```

### Linux
```bash
# Debian/Ubuntu
sudo apt install libhidapi-dev

# Fedora/RHEL
sudo dnf install hidapi-devel

# Arch Linux
sudo pacman -S hidapi
```

**权限设置**: 创建 udev 规则以允许非 root 用户访问 HID 设备
```bash
sudo nano /etc/udev/rules.d/99-hidraw-permissions.rules
```
添加：
```
KERNEL=="hidraw*", MODE="0666"
```
然后重新加载：
```bash
sudo udevadm control --reload-rules
sudo udevadm trigger
```

### macOS
```bash
# 使用 Homebrew
brew install hidapi
```

> 📚 **详细的平台特定说明请参考 [PLATFORM_SUPPORT.md](PLATFORM_SUPPORT.md)**

## 🚀 构建和运行

1. **安装 Zig** (需要 0.13.0 或更高版本)
```bash
# 从 https://ziglang.org/download/ 下载安装
```

2. **构建项目**
```bash
zig build
```

3. **运行应用**
```bash
zig build run
```

程序会自动打开浏览器窗口显示 UI 界面！

## 📖 使用说明

1. 运行程序后，会自动打开浏览器窗口
2. 点击"刷新设备列表"按钮来检测已连接的 HID 设备
3. 选择要监控的设备（点击设备卡片）
   - **✓ 可读取**: 设备在白名单中，可以执行数据读取
   - **⚠ 仅查看**: 设备不在白名单中，只能查看设备信息
4. **自动模式选择**: 系统根据设备 VID/PID 自动选择最佳读取模式
   - **A8xx 系列**: 自动使用逐字节读取模式
   - **A9xx 系列**: 自动使用 32字节批量读取模式
5. 点击"开始读取"按钮开始读取设备数据（仅白名单设备可读取）
6. 实时数据将显示在日志区域，并自动保存到 `data/device_data_时间戳.hid` 文件
7. 点击"停止读取"停止数据采集
8. 点击"查看数据"可查看以美观格式显示的完整数据
   - 鼠标悬停在字节上可查看详细信息（十六进制、十进制、二进制、ASCII）
9. 点击"导出数据"可将数据导出为格式化的 .hid 文件
10. 使用"数据对比"功能可以对比不同读取的数据或导入 .hid 文件进行对比
    - 支持字节级精确对比
    - 绿色表示相同，红色表示不同
    - 左右窗口滚动自动同步

### 🔐 设备白名单配置

白名单配置位于 `device_whitelist.zig` 文件中，支持的设备列表：

```zig
pub const DEVICE_WHITELIST = [_]DeviceConfig{
    // A8xx 系列 - 逐字节读取模式
    .{ .vid = "30FA", .pid = "0842", .mode = 1 },
    .{ .vid = "30FA", .pid = "1440", .mode = 1 },
    .{ .vid = "30FA", .pid = "1550", .mode = 1 },
    // ... 更多 A8xx 设备

    // A9xx 系列 - 32字节批量读取模式
    .{ .vid = "30FA", .pid = "0943", .mode = 2 },
    .{ .vid = "30FA", .pid = "0944", .mode = 2 },
    .{ .vid = "30FA", .pid = "0945", .mode = 2 },
};
```

**添加新设备到白名单**：
1. 打开 `device_whitelist.zig`
2. 在 `DEVICE_WHITELIST` 数组中添加新条目
3. 指定 `vid`（厂商ID）、`pid`（产品ID）和 `mode`（1或2）
4. 重新编译项目

### 📁 数据存储

每次读取的数据自动保存到带毫秒时间戳的独立文件：

**文件命名格式**:
```
data/device_data_1704614445123.hid  (2024-01-07 14:30:45.123)
```

> 💡 文件名使用毫秒级时间戳，确保每次读取都是唯一的文件名
> 💡 统一使用 .hid 扩展名，方便管理和识别

**文件内容格式**:
```
0x0000: 01 23 45 67 89 AB CD EF 01 23 45 67 89 AB CD EF
0x0010: FE DC BA 98 76 54 32 10 FE DC BA 98 76 54 32 10
0x0020: AA BB CC DD EE FF 00 11 AA BB CC DD EE FF 00 11
...
```

**特点**:
- ✅ 每次读取生成独立文件，保留完整历史记录
- ✅ 文件名包含毫秒级时间戳，易于追溯和排序
- ✅ 格式标准，易于其他程序解析
- ✅ 实时写入，读取过程中随时可以查看文件内容
- ✅ 统一 .hid 扩展名，便于文件管理和导入

### 📊 功能说明

- **设备管理**:
  - 自动检测所有 HID 设备
  - 白名单设备标记为"✓ 可读取"
  - 非白名单设备标记为"⚠ 仅查看"
  - 热插拔实时检测（每2秒）
  - 双击设备查看详细信息

- **数据读取**:
  - 自动选择最佳读取模式（基于白名单配置）
  - 实时显示读取进度
  - 数据自动保存到 .hid 文件
  - 支持停止和继续

- **数据查看**:
  - 表格化显示（每16字节一行）
  - 鼠标悬停显示详细信息：
    - 📍 地址（十六进制和十进制）
    - 🔢 十六进制值
    - 🔢 十进制值
    - 💾 二进制值
    - 📝 ASCII 字符
    - 📊 行列位置
  - 复制所有数据到剪贴板
  - 导出为格式化的 .hid 文件

- **数据对比**:
  - 支持加载当前读取数据
  - 支持导入 .hid 文件
  - 字节级精确对比
  - 颜色高亮差异（绿色相同，红色不同）
  - 左右窗口滚动自动同步
  - 显示差异统计

- **日志功能**:
  - 实时显示操作日志
  - 自动记录设备事件
  - 导出日志到 .hid 文件
  - 最多保留 100 条日志

## 🔑 权限设置 (Linux)

在 Linux 上，需要设置 udev 规则以允许普通用户访问 HID 设备：

```bash
# 创建 udev 规则
sudo tee /etc/udev/rules.d/99-hidraw.rules << EOF
KERNEL=="hidraw*", SUBSYSTEM=="hidraw", MODE="0666"
EOF

# 重新加载 udev 规则
sudo udevadm control --reload-rules
sudo udevadm trigger
```

## 📂 项目结构

```
readDevice/
├── build.zig              # 构建配置文件
├── build.zig.zon          # 依赖管理 (webui)
├── device_whitelist.zig   # 设备白名单配置（VID/PID/读取模式）
├── src/
│   ├── main.zig           # 主程序入口 & WebUI 集成 & 白名单验证
│   ├── hid.zig            # HID 设备操作模块 (Linux/Windows)
│   ├── index.html         # Web UI 界面 (Vue 3 + Naive UI，@embedFile 内嵌)
│   └── assets/
│       └── js/
│           ├── vue.global.prod.js   # Vue 3 UMD
│           └── naive-ui.js          # Naive UI UMD
├── data/
│   └── device_data_*.hid  # 读取数据文件（自动生成，毫秒时间戳）
└── zig-out/
    └── bin/
        └── readDevice     # 编译后的可执行文件
```

## 🔐 白名单机制说明

### 工作流程

1. **前端显示**: 所有连接的设备都会显示，但带有支持标识
   - ✓ 可读取：设备在白名单中
   - ⚠ 仅查看：设备不在白名单中

2. **前端验证**:
   - 选中白名单设备：读取按钮可用
   - 选中非白名单设备：读取按钮禁用
   - 点击读取前再次检查 `device.supported` 字段

3. **后端验证**:
   - 接收读取请求时验证 VID/PID
   - 从白名单查询设备配置
   - 自动设置正确的读取模式
   - 不在白名单中的设备直接拒绝

### 安全保障

- ✅ 多层验证（UI 层 + 前端验证 + 后端验证）
- ✅ 只有白名单内的设备才能执行读取操作
- ✅ 自动模式选择，避免错误配置
- ✅ 集中配置，易于维护和扩展

## 🔗 Zig ↔ JavaScript 通信

### JavaScript 调用 Zig 函数
```javascript
// 在 JavaScript 中
const result = await webui.call('getDevices');
const devices = JSON.parse(result);
```

### Zig 调用 JavaScript 函数
```zig
// 在 Zig 中
_ = main_window.run("addLogFromBackend('" ++ data ++ "')");
```

## 🌟 WebUI 的优势

## 🌟 WebUI 的优势

相比传统 HTTP 服务器方案（如 zap）：

1. ✅ **无需端口管理**: 不需要担心端口占用或防火墙问题
2. ✅ **自动启动浏览器**: 程序自动打开 GUI 窗口
3. ✅ **原生集成**: Zig 和 JavaScript 可以直接互相调用函数
4. ✅ **更简单部署**: 单一可执行文件，无需配置
5. ✅ **更快启动**: 无需启动完整的 HTTP 服务器
6. ✅ **多浏览器支持**: 自动选择系统可用的浏览器

## 🔧 开发

### 运行测试
```bash
zig build test
```

### 开发模式 (自动重载)
```bash
# 需要安装 watchexec
watchexec -r -e zig 'zig build run'
```

## 📝 对比原 C++ 版本的改进

1. ✅ **跨平台**: 不依赖 MFC，可在 Linux/Windows/macOS 运行
2. ✅ **现代 UI**: Web 界面替代传统 Windows 窗口
3. ✅ **零配置构建** (Windows): 自动搜索 vcpkg，无需手动设置环境变量
4. ✅ **白名单机制**: 自动识别支持的设备，智能选择读取模式
5. ✅ **自动模式**: 无需手动选择读取模式，降低操作错误
6. ✅ **数据持久化**: 自动保存到 .hid 文件，带时间戳管理
7. ✅ **热插拔检测**: 自动监听设备连接和断开
8. ✅ **更易维护**: Zig 代码更简洁，无需管理复杂的 Win32 API
9. ✅ **内存安全**: Zig 提供编译时内存安全保证
10. ✅ **易于部署**: 单一可执行文件，HTML 内嵌其中
11. ✅ **双向通信**: 前后端可以轻松互相调用函数
12. ✅ **字节级对比**: 数据对比精确到每个字节
13. ✅ **丰富提示**: 悬停显示十六进制、十进制、二进制、ASCII 等信息

## 📝 对比 HTTP 服务器方案（zap）的改进

1. ✅ **更简单**: 无需管理 HTTP 服务器和路由
2. ✅ **更快**: 直接通信，无 HTTP 开销
3. ✅ **更安全**: 不暴露网络端口
4. ✅ **更原生**: 像桌面应用一样使用
5. ✅ **更易用**: 自动打开窗口，用户体验更好
6. ✅ **轻量存储**: 使用 .hid 文本文件，无外部依赖
7. ✅ **白名单保护**: 只允许读取预先配置的设备

## 📄 许可证

MIT License

## 🤝 贡献

欢迎提交 Issue 和 Pull Request!

## 🔗 参考资源

- [Zig 语言圣经 - 第三方库](https://course.ziglang.cc/appendix/well-known-lib)
- [zig-webui - 官方仓库](https://github.com/webui-dev/zig-webui)
- [WebUI 文档](https://webui.me/)
- [Zig 官方文档](https://ziglang.org/documentation/master/)
