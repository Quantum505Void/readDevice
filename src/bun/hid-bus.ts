/**
 * hid-bus.ts — 跨平台 HID 总线类型检测
 *
 * node-hid 3.x 预编译 .node 未暴露 hidapi bus_type 字段。
 * 本文件参照 hidapi 官方各平台源码还原检测逻辑：
 *
 * Windows (windows/hid.c: hid_internal_detect_bus_type)
 *   - path 含 BTHENUM / BTHLEDEVICE → BT Classic
 *   - path 含 BT HID Service UUID 00001812-... → BT LE
 *
 * macOS (mac/hid.c: kIOHIDTransportKey)
 *   - path 含 "Bluetooth" → Bluetooth
 *
 * Linux (linux/hid.c: parse_hid_vid_pid_from_uevent)
 *   - /sys/class/hidraw/<dev>/device/uevent HID_ID 字段
 *   - BUS_BLUETOOTH=0x0005, BUS_USB=0x0003, BUS_I2C=0x0018
 */

import { readFileSync, existsSync } from "fs";

const LINUX_BUS_BT  = new Set([0x0002, 0x0004, 0x0005]);
const LINUX_BUS_USB = new Set([0x0001, 0x0003]);

function readLinuxBusInfo(devPath: string): { label: string; isBluetooth: boolean } | null {
  const name = devPath.split("/").pop();
  if (!name) return null;
  const uevent = `/sys/class/hidraw/${name}/device/uevent`;
  if (!existsSync(uevent)) return null;
  try {
    const m = readFileSync(uevent, "utf8").match(/^HID_ID=([0-9A-Fa-f]{4}):/m);
    if (!m) return null;
    const id = parseInt(m[1], 16);
    if (LINUX_BUS_BT.has(id))  return { label: "Bluetooth", isBluetooth: true };
    if (id === 0x0018)          return { label: "I2C",       isBluetooth: false };
    if (id === 0x001c)          return { label: "SPI",       isBluetooth: false };
    return { label: "USB", isBluetooth: false };
  } catch { return null; }
}

/**
 * 检测 HID 设备总线类型，与 hidapi 官方各平台实现对齐。
 */
export function getBusInfo(path?: string, _serial?: string): { label: string; isBluetooth: boolean } {
  const p = path ?? "";

  if (process.platform === "linux" && p) {
    const info = readLinuxBusInfo(p);
    if (info) return info;
  } else if (process.platform === "win32" && p) {
    const up = p.toUpperCase();
    if (up.includes("00001812-0000-1000-8000-00805F9B34FB") ||
        up.includes("BTHENUM") || up.includes("BTHLEDEVICE")) {
      return { label: "Bluetooth", isBluetooth: true };
    }
    if (up.includes("PNP0C50") || up.includes("I2CHID")) return { label: "I2C", isBluetooth: false };
    if (up.includes("PNP0C51"))                           return { label: "SPI", isBluetooth: false };
    return { label: "USB", isBluetooth: false };
  } else if (process.platform === "darwin" && p) {
    const lp = p.toLowerCase();
    if (lp.includes("bluetooth")) return { label: "Bluetooth", isBluetooth: true };
    if (lp.includes("i2c"))       return { label: "I2C",       isBluetooth: false };
    if (lp.includes("spi"))       return { label: "SPI",       isBluetooth: false };
    return { label: "USB", isBluetooth: false };
  }

  return { label: "USB", isBluetooth: false };
}

/**
 * 去重 key：Linux 用 path（hidrawX），其他平台用 VID:PID:serial
 */
export function getDedupeKey(vendorId: number, productId: number, serialNumber?: string, path?: string): string {
  if (process.platform === "linux" && path) return path;
  return `${vendorId}:${productId}:${serialNumber?.trim() || ""}`;
}
