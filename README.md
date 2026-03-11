# HID Device Reader

> 基于 Electrobun + Svelte 5 的跨平台 HID 设备 EEPROM 读取工具

## ✨ 特性

- 🔌 **设备枚举**：实时扫描系统 HID 设备（USB + 蓝牙）
- 📋 **白名单管理**：自动识别 A8xx/A9xx 系列设备，标注读取模式
- 🔍 **Feature Report 扫描**：自动检测设备支持的 Report IDs（0x00–0xFF）
- 📖 **双模式读取**：8系逐字节 / 9系 32 字节批量 EEPROM 读取
- 🎨 **现代 UI**：深色极简风格，Hex 语法高亮，行内一键复制
- 💾 **自动保存**：数据实时写入 `data/` 目录（`.hid` 格式）

## 🚀 快速开始

```bash
bun install
bun start        # 开发模式
bun run build    # 构建发布
```

## 📁 项目结构

```
readDevice/
├── src/
│   ├── bun/index.ts          # 主进程（HID 扫描、EEPROM 读取、RPC）
│   ├── renderer/             # Svelte 5 前端
│   │   ├── App.svelte
│   │   ├── main.ts
│   │   └── components/
│   │       ├── DeviceList.svelte
│   │       └── EEPROMPanel.svelte
│   └── shared/types.ts       # 共享 RPC 类型
├── electrobun.config.ts
├── vite.config.ts
└── data/                     # 读取结果自动保存
```

## 🛠 技术栈

- **运行时**：[Electrobun](https://electrobun.dev) + Bun
- **UI**：Svelte 5 (Runes) + Tailwind CSS v4
- **HID**：[node-hid](https://github.com/node-hid/node-hid) v3

## 📋 支持设备

| 系列 | VID | PID | 模式 |
|---|---|---|---|
| A8xx | 30FA | 1040/1140/1201/1340/1440/1540/1901/1D01/1E01 | 逐字节 |
| A9xx | 30FA | 1150/1450/1550 | 32 字节批量 |
