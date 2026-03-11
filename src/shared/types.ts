import type { RPCSchema } from "electrobun/bun";

// 设备白名单配置
export type DeviceMode = 1 | 2; // 1=8系(逐字节), 2=9系(32字节批量)

export type WhitelistDevice = {
  vid: string;
  pid: string;
  mode: DeviceMode;
  name?: string;
};

// HID 设备扫描结果
export type HIDDevice = {
  vid: string;
  pid: string;
  vendor: string;
  product: string;
  serial: string;
  isBluetooth: boolean;
  path: string;
  usagePage: number;
  usage: number;
  rawInfo: string;
  supported: boolean;
  mode?: DeviceMode;
};

// EEPROM 数据行
export type EEPROMRow = {
  address: number;
  hex: string;
};

// Diff 结果行
export type DiffRow = {
  address: number;
  hexA: string;   // 文件 A 的 hex（空字符串表示该地址 A 没有数据）
  hexB: string;   // 文件 B 的 hex
  diffMask: boolean[]; // 逐字节差异掩码
  hasDiff: boolean;
};

export type AppRPCType = {
  bun: RPCSchema<{
    requests: {
      scanDevices: {
        params: Record<string, never>;
        response: HIDDevice[];
      };
      startReading: {
        params: { path: string; vid: string; pid: string };
        response: { success: boolean; error?: string };
      };
      stopReading: {
        params: Record<string, never>;
        response: { success: boolean };
      };
      openFileForDiff: {
        params: Record<string, never>;
        response: { success: boolean; filename: string; rows: EEPROMRow[]; error?: string };
      };
      saveDiffReport: {
        params: { content: string; filename: string };
        response: { success: boolean; savedPath?: string; error?: string };
      };
    };
    messages: Record<string, never>;
  }>;
  webview: RPCSchema<{
    requests: Record<string, never>;
    messages: {
      log: { message: string };
      dataRow: { address: number; hex: string };
      progress: { address: number; totalBytes: number; percent: number };
      readComplete: { totalBytes: number; filename: string };
      readError: { message: string };
    };
  }>;
};
