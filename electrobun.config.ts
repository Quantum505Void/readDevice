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
      "dist/index.html": "views/mainview/index.html",
      "dist/assets": "views/mainview/assets",
      "tray-icon.svg": "views/mainview/tray-icon.svg",
      "icon.png": "views/mainview/icon.png",
    },
    watchIgnore: ["dist/**"],
    platforms: {
      mac: {
        icons: "icon.iconset",
      },
      win: {
        icon: "icon.ico",
      },
      linux: {
        icon: "icon.png",
      },
    },
  },
  runtime: {
    exitOnLastWindowClosed: false,
  },
} satisfies ElectrobunConfig;
