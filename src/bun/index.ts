import { BrowserWindow, BrowserView, Tray, Utils, GlobalShortcut } from "electrobun/bun";
import type { AppRPCType, HIDDevice, WhitelistDevice, DeviceMode } from "../shared/types";
import { join } from "path";
import net from "net";
import fs from "fs";

const { showNotification, paths, quit } = Utils;

// ─── 设备白名单 ───────────────────────────────────────────────────────────────
const DEVICE_WHITELIST: WhitelistDevice[] = [
  // A8xx 系列（8系，逐字节读取）
  { vid: "30FA", pid: "1440", mode: 1 },
  { vid: "30FA", pid: "1540", mode: 1 },
  { vid: "30FA", pid: "1E01", mode: 1 },
  { vid: "30FA", pid: "1040", mode: 1 },
  { vid: "30FA", pid: "1201", mode: 1 },
  { vid: "30FA", pid: "1140", mode: 1 },
  { vid: "30FA", pid: "1D01", mode: 1 },
  { vid: "30FA", pid: "1340", mode: 1 },
  { vid: "30FA", pid: "1901", mode: 1 },
  // A9xx 系列（9系，32字节批量读取）
  { vid: "30FA", pid: "1150", mode: 2 },
  { vid: "30FA", pid: "1450", mode: 2 },
  { vid: "30FA", pid: "1550", mode: 2 },
];

function findWhitelist(vid: string, pid: string): WhitelistDevice | undefined {
  return DEVICE_WHITELIST.find(
    (w) => w.vid.toUpperCase() === vid.toUpperCase() && w.pid.toUpperCase() === pid.toUpperCase()
  );
}

// ─── 单实例互斥 ───────────────────────────────────────────────────────────────
const SINGLE_INSTANCE_PORT = 47295;

async function setupSingleInstance(): Promise<boolean> {
  return new Promise((resolve) => {
    const probe = net.createConnection(SINGLE_INSTANCE_PORT, "127.0.0.1");
    probe.once("connect", () => {
      probe.write("focus\n");
      probe.end();
      probe.once("close", () => resolve(false));
    });
    probe.once("error", () => {
      probe.destroy();
      const server = net.createServer((socket) => {
        socket.on("data", (data) => {
          if (data.toString().includes("focus")) showWindow();
        });
        socket.on("error", () => {});
      });
      server.listen(SINGLE_INSTANCE_PORT, "127.0.0.1", () => resolve(true));
      server.on("error", () => resolve(true));
    });
  });
}

if (!await setupSingleInstance()) {
  process.exit(0);
}

// ─── HID ──────────────────────────────────────────────────────────────────────
let hidModule: typeof import("node-hid") | null = null;
async function loadHID() {
  if (!hidModule) {
    try { hidModule = await import("node-hid"); }
    catch { console.error("node-hid 加载失败"); }
  }
  return hidModule;
}

const VENDOR_NAMES: Record<number, string> = {
  0x046d: "Logitech", 0x045e: "Microsoft", 0x05ac: "Apple",
  0x04d9: "Holtek",   0x0483: "STMicro",   0x1532: "Razer",
  0x1b1c: "Corsair",  0x046a: "Cherry",    0x17ef: "Lenovo",
  0x0b05: "ASUS",     0x03f0: "HP",        0x04ca: "Lite-On",
  0x30fa: "Shenzhen Jingli",
};

function isBT(dev: Record<string, unknown>): boolean {
  if (dev.busType === 2) return true;
  const p = typeof dev.path === "string" ? dev.path.toLowerCase() : "";
  return p.includes("bluetooth") || p.includes("bth");
}

function vendor(dev: Record<string, unknown>): string {
  const m = (dev.manufacturer as string)?.trim();
  return (m && m !== "Unknown") ? m : (VENDOR_NAMES[dev.vendorId as number] ?? "未知厂商");
}

function buildRawInfo(dev: Record<string, unknown>): string {
  return [
    `供应商ID (VID): ${((dev.vendorId as number) ?? 0).toString(16).padStart(4, "0").toUpperCase()}`,
    `产品ID (PID): ${((dev.productId as number) ?? 0).toString(16).padStart(4, "0").toUpperCase()}`,
    `制造商: ${vendor(dev)}`,
    `产品名称: ${dev.product ?? "未知"}`,
    `序列号: ${dev.serialNumber ?? "N/A"}`,
    `连接方式: ${isBT(dev) ? "蓝牙HID设备" : "USB有线连接"}`,
    `设备路径: ${dev.path ?? "N/A"}`,
    `HID使用页: 0x${((dev.usagePage as number) ?? 0).toString(16).padStart(4, "0").toUpperCase()}`,
    `HID使用ID: 0x${((dev.usage as number) ?? 0).toString(16).padStart(4, "0").toUpperCase()}`,
  ].join("\n");
}

// 从同 vid:pid 的所有接口中挑最佳（Feature Report 接口，非标准鼠标/键盘接口）
function pickBestInterface(devs: Record<string, unknown>[]): Record<string, unknown> {
  // usagePage=0xFF00 通用厂商接口 > usagePage≠1 > 其余
  const vendor = devs.find(d => (d.usagePage as number) >= 0xFF00);
  if (vendor) return vendor;
  const nonInput = devs.find(d => (d.usagePage as number) !== 1);
  if (nonInput) return nonInput;
  // 同 usagePage=1 时，优先选非 mouse(2)/keyboard(6)
  const nonMK = devs.find(d => (d.usage as number) !== 2 && (d.usage as number) !== 6);
  if (nonMK) return nonMK;
  return devs[0];
}

async function scanDevices(): Promise<HIDDevice[]> {
  const hid = await loadHID();
  if (!hid) return [];

  // 按 vid:pid:serial:isBT 分组，同一物理设备的多个接口合并
  const groups = new Map<string, Record<string, unknown>[]>();
  for (const dev of hid.devices() as Record<string, unknown>[]) {
    const vid = ((dev.vendorId as number) ?? 0).toString(16).padStart(4, "0").toUpperCase();
    const pid = ((dev.productId as number) ?? 0).toString(16).padStart(4, "0").toUpperCase();
    if (vid === "0000" && pid === "0000") continue;
    const serial = (dev.serialNumber as string)?.trim() || "N/A";
    const bt = isBT(dev) ? "bt" : "usb";
    const groupKey = `${vid}:${pid}:${serial}:${bt}`;
    if (!groups.has(groupKey)) groups.set(groupKey, []);
    groups.get(groupKey)!.push(dev);
  }

  const result: HIDDevice[] = [];
  for (const devs of groups.values()) {
    const best = pickBestInterface(devs);
    const vid = ((best.vendorId as number) ?? 0).toString(16).padStart(4, "0").toUpperCase();
    const pid = ((best.productId as number) ?? 0).toString(16).padStart(4, "0").toUpperCase();
    const serial = (best.serialNumber as string)?.trim() || "N/A";
    const wl = findWhitelist(vid, pid);
    result.push({
      vid, pid,
      vendor: vendor(best),
      product: ((best.product as string)?.trim()) || `HID ${vid}:${pid}`,
      serial,
      isBluetooth: isBT(best),
      path: (best.path as string) ?? "",
      usagePage: (best.usagePage as number) ?? 0,
      usage: (best.usage as number) ?? 0,
      rawInfo: buildRawInfo(best),
      supported: !!wl,
      mode: wl?.mode,
    });
  }
  result.sort((a, b) => {
    if (a.isBluetooth !== b.isBluetooth) return a.isBluetooth ? 1 : -1;
    if (a.supported !== b.supported) return a.supported ? -1 : 1;
    return `${a.vid}${a.pid}`.localeCompare(`${b.vid}${b.pid}`);
  });
  return result;
}

// ─── EEPROM 读取 ──────────────────────────────────────────────────────────────
let isReading = false;
let stopFlag = false;
const EEP_RW_CMD = 0x18;
const READ_SIZE = 32;
const EEP_SIZE = 4096;

/** 扫描设备支持的 Feature Report IDs (0x00-0xFF) */
async function scanFeatureReports(device: import("node-hid").HID): Promise<number[]> {
  const supported: number[] = [];
  for (let id = 0; id <= 0xff; id++) {
    try {
      const buf = Buffer.alloc(9, 0);
      buf[0] = id;
      device.getFeatureReport(id, 9);
      supported.push(id);
    } catch {
      // 不支持该 report ID
    }
    if (id % 16 === 0) await Bun.sleep(1); // 避免阻塞
  }
  return supported;
}

/** 8系读取方法（逐字节） */
async function readDeviceType8(device: import("node-hid").HID, onData: (addr: number, data: Buffer) => void, onProgress: (addr: number, total: number, pct: number) => void) {
  let address = 0;
  let totalBytes = 0;

  while (!stopFlag && address < EEP_SIZE) {
    // 初始化寄存器（READ_SIZE 次）
    for (let i = 0; i < READ_SIZE; i++) {
      const report = Buffer.alloc(8, 0);
      report[0] = 0x07;
      report[1] = EEP_RW_CMD;
      report[2] = 0x03; // usbRegWEn + softCtrlEppEn
      report[3] = i;
      report[4] = address % 256;
      report[5] = Math.floor(address / 256);
      report[6] = 0;
      report[7] = READ_SIZE - 1;
      try { device.sendFeatureReport([...report]); } catch { return; }
      await Bun.sleep(2);
    }

    // 清除控制位
    const clr = Buffer.alloc(8, 0);
    clr[0] = 0x07; clr[1] = EEP_RW_CMD; clr[2] = 0x00;
    try { device.sendFeatureReport([...clr]); } catch {}
    await Bun.sleep(2);

    // 逐字节读取
    const pageData = Buffer.alloc(READ_SIZE, 0);
    for (let i = 0; i < READ_SIZE; i++) {
      if (stopFlag) break;
      const report = Buffer.alloc(8, 0);
      report[0] = 0x07;
      report[1] = EEP_RW_CMD;
      report[2] = 0x05; // eepREn + softCtrlEppEn
      report[3] = i;
      report[4] = address % 256;
      report[5] = Math.floor(address / 256);
      report[6] = 0;
      report[7] = READ_SIZE - 1;
      try { device.sendFeatureReport([...report]); } catch { continue; }
      await Bun.sleep(2);

      // 读取数据
      const recv = Buffer.alloc(8, 0);
      recv[0] = 0x07;
      try {
        const raw = device.getFeatureReport(0x07, 9);
        pageData[i] = raw[2] ?? 0; // byte[1] is report id echo, [2] is data
      } catch { continue; }
    }

    // 清除控制位
    try { device.sendFeatureReport([...clr]); } catch {}
    await Bun.sleep(2);

    totalBytes += READ_SIZE;
    onData(address, pageData);
    address += READ_SIZE;
    onProgress(address, totalBytes, (address / EEP_SIZE) * 100);
    await Bun.sleep(100);
  }
  return totalBytes;
}

/** 9系读取方法（32字节批量） */
async function readDeviceType9(device: import("node-hid").HID, onData: (addr: number, data: Buffer) => void, onProgress: (addr: number, total: number, pct: number) => void) {
  let address = 0;
  let totalBytes = 0;

  while (!stopFlag && address < EEP_SIZE) {
    const LENGTH_BYTE = READ_SIZE - 1 + 64 + 128;

    // 清空内部寄存器
    const init = Buffer.alloc(50, 0);
    init[0] = 0x07; init[1] = EEP_RW_CMD; init[2] = 0x03;
    init[3] = 0; init[4] = address % 256; init[5] = Math.floor(address / 256);
    init[6] = 0; init[7] = LENGTH_BYTE;
    try { device.sendFeatureReport([...init]); } catch { return; }
    await Bun.sleep(1);

    // 发送批量读取命令
    const cmd = Buffer.alloc(50, 0);
    cmd[0] = 0x07; cmd[1] = EEP_RW_CMD; cmd[2] = 0x05;
    cmd[3] = 0; cmd[4] = address % 256; cmd[5] = Math.floor(address / 256);
    cmd[6] = 0; cmd[7] = LENGTH_BYTE;
    try { device.sendFeatureReport([...cmd]); } catch { return; }
    await Bun.sleep(5);

    // 获取32字节数据（数据从 byte[1] 开始）
    try {
      const raw = device.getFeatureReport(0x07, 34); // report_id + 32 bytes + 1 spare
      const pageData = Buffer.from(raw.slice(1, READ_SIZE + 1));
      totalBytes += READ_SIZE;
      onData(address, pageData);
      address += READ_SIZE;
      onProgress(address, totalBytes, (address / EEP_SIZE) * 100);
    } catch {
      address += READ_SIZE; // skip failed page
    }
    await Bun.sleep(100);
  }
  return totalBytes;
}

// ─── 状态 ─────────────────────────────────────────────────────────────────────
let win: BrowserWindow | null = null;
let tray: Tray | null = null;
let isQuitting = false;

// ─── RPC ──────────────────────────────────────────────────────────────────────
const rpc = BrowserView.defineRPC<AppRPCType>({
  maxRequestTime: 10000,
  handlers: {
    requests: {
      scanDevices: async () => scanDevices(),

      startReading: async ({ path, vid, pid }) => {
        if (isReading) return { success: false, error: "Already reading" };

        const wl = findWhitelist(vid, pid);
        if (!wl) return { success: false, error: `设备 ${vid}:${pid} 不在白名单中` };

        const hid = await loadHID();
        if (!hid) return { success: false, error: "node-hid 不可用" };

        // 确保 data 目录存在
        try { fs.mkdirSync("data", { recursive: true }); } catch {}

        const ts = Date.now();
        const filename = `data/device_data_${ts}.hid`;

        // 通知前端文件名
        win?.webview.rpc.send.log({ message: `📁 数据将保存到: ${filename}` });
        win?.webview.rpc.send.log({ message: `📋 读取模式: ${wl.mode === 1 ? "8系（逐字节）" : "9系（32字节批量）"}` });

        isReading = true;
        stopFlag = false;

        // 在后台执行读取
        (async () => {
          let device: import("node-hid").HID | null = null;
          try {
            // 打开设备（按 VID/PID，选最佳接口）
            const allDevs = hid.devices().filter(
              d => d.vendorId === parseInt(vid, 16) && d.productId === parseInt(pid, 16)
            );
            // 优先选 usage page 非 mouse/keyboard 的接口
            const best = allDevs.find(d => d.usagePage !== 1 || (d.usage !== 2 && d.usage !== 6))
              ?? allDevs[0];
            if (!best?.path) throw new Error("找不到设备路径");

            device = new hid.HID(best.path);
            win?.webview.rpc.send.log({ message: "✅ 设备已打开" });

            // 扫描 Feature Reports
            win?.webview.rpc.send.log({ message: "🔍 扫描 Feature Report IDs..." });
            const supported = await scanFeatureReports(device);
            win?.webview.rpc.send.log({ message: `📊 支持 ${supported.length} 个 Feature Report IDs` });

            if (!supported.includes(0x07)) {
              throw new Error("设备不支持 EEPROM 访问（缺少 Report ID 0x07）");
            }

            // 数据文件句柄
            const fileStream = fs.createWriteStream(filename);

            const onData = (addr: number, data: Buffer) => {
              const hex = [...data].map(b => b.toString(16).padStart(2, "0")).join(" ");
              fileStream.write(`0x${addr.toString(16).padStart(4, "0")}: ${hex}\n`);
              win?.webview.rpc.send.dataRow({ address: addr, hex });
            };

            const onProgress = (addr: number, total: number, pct: number) => {
              win?.webview.rpc.send.progress({ address: addr, totalBytes: total, percent: Math.round(pct * 10) / 10 });
            };

            let totalBytes = 0;
            if (wl.mode === 1) {
              totalBytes = (await readDeviceType8(device, onData, onProgress)) ?? 0;
            } else {
              totalBytes = (await readDeviceType9(device, onData, onProgress)) ?? 0;
            }

            fileStream.end();
            win?.webview.rpc.send.readComplete({ totalBytes, filename });
            win?.webview.rpc.send.log({ message: `✅ 读取完成，共 ${totalBytes} 字节，已保存至 ${filename}` });
          } catch (e: unknown) {
            const msg = e instanceof Error ? e.message : String(e);
            win?.webview.rpc.send.readError({ message: msg });
            win?.webview.rpc.send.log({ message: `❌ 读取失败: ${msg}` });
          } finally {
            try { device?.close(); } catch {}
            isReading = false;
          }
        })();

        return { success: true };
      },

      stopReading: async () => {
        stopFlag = true;
        isReading = false;
        return { success: true };
      },
    },
    messages: {},
  },
});

// ─── 窗口管理 ─────────────────────────────────────────────────────────────────
function createWindow() {
  win = new BrowserWindow({
    title: "HID Device Reader",
    url: process.env.DEV_SERVER ?? "views://mainview/index.html",
    frame: { width: 1400, height: 900, minWidth: 1100, minHeight: 650 },
    rpc,
  });
  win.on("close", () => {
    if (isQuitting) return;
    win = null;
  });
}

function showWindow() {
  if (!win) { createWindow(); return; }
  try { win.unminimize(); win.focus(); } catch {}
}

function hideWindow() {
  if (!win) return;
  try { win.minimize(); } catch {}
}

function quitApp() {
  if (isQuitting) return;
  isQuitting = true;
  stopFlag = true;
  tray?.remove();
  quit();
}

process.on("SIGINT", () => quitApp());
process.on("SIGTERM", () => quitApp());

// ─── 托盘 ─────────────────────────────────────────────────────────────────────
try {
  tray = new Tray({ image: "views://mainview/tray-icon.svg", width: 22, height: 22 });
  tray.setMenu([
    { label: "HID Device Reader v1.0", enabled: false },
    { type: "separator" },
    { label: "显示窗口", action: "show" },
    { label: "隐藏窗口", action: "hide" },
    { type: "separator" },
    { label: "退出", action: "quit" },
  ]);
  tray.on("tray-clicked", (event: any) => {
    const action = event?.data?.action ?? event?.action ?? "";
    if      (action === "quit") quitApp();
    else if (action === "show") showWindow();
    else if (action === "hide") hideWindow();
    else {
      const hidden = !win || win.isMinimized();
      if (hidden) showWindow(); else hideWindow();
    }
  });
} catch (e) {
  console.warn("托盘初始化失败:", e);
}

// ─── 快捷键 ──────────────────────────────────────────────────────────────────
GlobalShortcut.register("F12", () => { win?.webview.toggleDevTools(); });

// ─── 启动 ─────────────────────────────────────────────────────────────────────
createWindow();
