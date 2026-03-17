/**
 * hid-bus.ts — 跨平台 HID 总线类型检测
 *
 * node-hid 3.x 的 C 层未暴露 hidapi 的 bus_type 字段到 JS。
 * 各平台检测策略：
 *   Linux  → /sys/class/hidraw/<dev>/device/uevent 的 HID_ID 字段（内核正式接口）
 *   其他   → 序列号 MAC 地址格式 + 路径关键词 fallback
 */

import { readFileSync, existsSync } from "fs";

// Linux BUS_* 常量（来自 <linux/input.h>）
const BUS_LABELS: Record<number, string> = {
  0x0001: "USB",
  0x0002: "Bluetooth",
  0x0003: "USB",
  0x0004: "Bluetooth",   // BT LE
  0x0005: "Bluetooth",   // Linux BUS_BLUETOOTH
  0x0006: "Virtual",
  0x0018: "I2C",
  0x001c: "SPI",
};

const BT_BUS_IDS = new Set([0x0002, 0x0004, 0x0005]);
const MAC_PATTERN = /^([0-9a-f]{2}:){5}[0-9a-f]{2}$/i;

function readLinuxBusInfo(devPath: string): { label: string; isBluetooth: boolean } | null {
  const devName = devPath.split("/").pop();
  if (!devName) return null;

  const ueventPath = `/sys/class/hidraw/${devName}/device/uevent`;
  if (!existsSync(ueventPath)) return null;

  try {
    const content = readFileSync(ueventPath, "utf8");
    const match = content.match(/^HID_ID=([0-9A-Fa-f]{4}):/m);
    if (!match) return null;
    const busId = parseInt(match[1], 16);
    const label = BUS_LABELS[busId] ?? `Bus(0x${busId.toString(16)})`;
    return { label, isBluetooth: BT_BUS_IDS.has(busId) };
  } catch {
    return null;
  }
}

/**
 * 检测 HID 设备总线类型。
 * @param path   node-hid 返回的 dev.path
 * @param serial node-hid 返回的 dev.serialNumber
 */
export function getBusInfo(path?: string, serial?: string): { label: string; isBluetooth: boolean } {
  // Linux: sysfs 精确检测
  if (process.platform === "linux" && path) {
    const info = readLinuxBusInfo(path);
    if (info) return info;
  }

  const lp = (path ?? "").toLowerCase();

  // Windows: BT HID Service UUID 在 path 里
  // 例：\\?\HID#{00001812-0000-1000-8000-00805f9b34fb}_Dev_VID&...
  if (lp.includes("00001812-0000-1000-8000-00805f9b34fb")) {
    return { label: "Bluetooth", isBluetooth: true };
  }
  // 路径关键词（macOS/Linux fallback）
  if (lp.includes("bluetooth") || lp.includes("bth") || lp.includes("rfcomm")) {
    return { label: "Bluetooth", isBluetooth: true };
  }
  // Fallback: MAC 地址格式 serial
  if (serial && MAC_PATTERN.test(serial.trim())) {
    return { label: "Bluetooth", isBluetooth: true };
  }

  return { label: "USB", isBluetooth: false };
}

/**
 * 同一物理设备去重 key。
 * Linux 每个 hidrawX 是独立接口，用 path 去重。
 * Windows/macOS 多 interface 共享 VID:PID:serial，用后者去重。
 */
export function getDedupeKey(vendorId: number, productId: number, serialNumber?: string, path?: string): string {
  if (process.platform === "linux" && path) return path;
  const serial = serialNumber?.trim() || "";
  return `${vendorId}:${productId}:${serial}`;
}
