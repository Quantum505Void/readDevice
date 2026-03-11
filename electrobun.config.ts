import type { ElectrobunConfig } from "electrobun";

export default {
  app: {
    name: "HID Device Reader",
    identifier: "com.waasstt.read-device",
    version: "1.0.0",
    description: "HID 设备 EEPROM 读取工具",
  },
  build: {
    bun: {
      entrypoint: "src/bun/index.ts",
    },
    copy: {
      "src/renderer-dist": "views/mainview",
      "tray-icon.svg": "views/mainview/tray-icon.svg",
      "tray-icon.png": "views/mainview/tray-icon.png",
    },
  },
  runtime: {
    exitOnLastWindowClosed: false,
  },
} satisfies ElectrobunConfig;
