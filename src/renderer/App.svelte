<script lang="ts">
  import { onMount } from "svelte";
  import { electroview, setLogHandler, setDataRowHandler, setProgressHandler, setReadCompleteHandler, setReadErrorHandler } from "./main.ts";
  import type { HIDDevice, EEPROMRow } from "../shared/types";
  import DeviceList from "./components/DeviceList.svelte";
  import EEPROMPanel from "./components/EEPROMPanel.svelte";

  // ─── 状态 ───────────────────────────────────────────────────────────────────
  let devices = $state<HIDDevice[]>([]);
  let selectedDevice = $state<HIDDevice | null>(null);
  let isScanning = $state(false);
  let isReading = $state(false);
  let logs = $state<string[]>([]);
  let rows = $state<EEPROMRow[]>([]);
  let progress = $state({ address: 0, totalBytes: 0, percent: 0 });
  let currentFilename = $state("");
  let readDone = $state(false);

  // ─── 派生 ───────────────────────────────────────────────────────────────────
  let usbDevices = $derived(devices.filter(d => !d.isBluetooth));
  let btDevices = $derived(devices.filter(d => d.isBluetooth));

  // ─── RPC 回调 ────────────────────────────────────────────────────────────────
  setLogHandler((msg) => {
    logs = [...logs.slice(-500), `[${now()}] ${msg}`];
  });
  setDataRowHandler((address, hex) => {
    rows = [...rows, { address, hex }];
  });
  setProgressHandler((address, totalBytes, percent) => {
    progress = { address, totalBytes, percent };
  });
  setReadCompleteHandler((totalBytes, filename) => {
    isReading = false;
    readDone = true;
    currentFilename = filename;
    progress = { address: 4096, totalBytes, percent: 100 };
    addLog(`✅ 读取完成！共 ${totalBytes} 字节`);
  });
  setReadErrorHandler((msg) => {
    isReading = false;
    addLog(`❌ 错误: ${msg}`);
  });

  function addLog(msg: string) {
    logs = [...logs.slice(-500), `[${now()}] ${msg}`];
  }

  function now() {
    return new Date().toLocaleTimeString("zh-CN");
  }

  // ─── 扫描设备 ────────────────────────────────────────────────────────────────
  async function scanDevices() {
    isScanning = true;
    try {
      const result = await electroview.rpc.bun.scanDevices({});
      devices = result;
      addLog(`🔍 扫描完成，发现 ${result.length} 个设备`);
    } catch (e) {
      addLog(`❌ 扫描失败: ${e}`);
    } finally {
      isScanning = false;
    }
  }

  // ─── 开始读取 ────────────────────────────────────────────────────────────────
  async function startReading() {
    if (!selectedDevice) return;
    if (isReading) return;
    rows = [];
    logs = [];
    readDone = false;
    currentFilename = "";
    progress = { address: 0, totalBytes: 0, percent: 0 };
    isReading = true;
    addLog(`🚀 开始读取 ${selectedDevice.vendor} ${selectedDevice.product}`);
    try {
      const res = await electroview.rpc.bun.startReading({
        path: selectedDevice.path,
        vid: selectedDevice.vid,
        pid: selectedDevice.pid,
      });
      if (!res.success) {
        isReading = false;
        addLog(`❌ ${res.error}`);
      }
    } catch (e) {
      isReading = false;
      addLog(`❌ 启动读取失败: ${e}`);
    }
  }

  // ─── 停止读取 ────────────────────────────────────────────────────────────────
  async function stopReading() {
    await electroview.rpc.bun.stopReading({});
    isReading = false;
    addLog("⏸️ 已停止读取");
  }

  // ─── 导出 ────────────────────────────────────────────────────────────────────
  function exportData() {
    if (rows.length === 0) return;
    const content = rows
      .map(r => `0x${r.address.toString(16).padStart(4, "0")}: ${r.hex}`)
      .join("\n");
    const blob = new Blob([content], { type: "text/plain" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `eeprom_${Date.now()}.hid`;
    a.click();
    URL.revokeObjectURL(url);
  }

  onMount(() => {
    scanDevices();
  });
</script>

<main class="app-root">
  <!-- 左侧：设备列表 -->
  <aside class="sidebar">
    <div class="sidebar-header">
      <span class="sidebar-title">HID 设备</span>
      <button class="btn-icon" onclick={scanDevices} disabled={isScanning} title="刷新设备列表">
        <svg class:spin={isScanning} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <path d="M1 4v6h6M23 20v-6h-6"/>
          <path d="M20.49 9A9 9 0 0 0 5.64 5.64L1 10m22 4l-4.64 4.36A9 9 0 0 1 3.51 15"/>
        </svg>
      </button>
    </div>

    <DeviceList
      label="USB 设备"
      {devices}
      list={usbDevices}
      bind:selected={selectedDevice}
    />
    <DeviceList
      label="蓝牙设备"
      {devices}
      list={btDevices}
      bind:selected={selectedDevice}
    />
  </aside>

  <!-- 右侧：EEPROM 读取面板 -->
  <section class="main-panel">
    <EEPROMPanel
      device={selectedDevice}
      {isReading}
      {readDone}
      {progress}
      {rows}
      {logs}
      {currentFilename}
      onStart={startReading}
      onStop={stopReading}
      onExport={exportData}
    />
  </section>
</main>

<style>
  @import "tailwindcss";

  :global(body) {
    margin: 0;
    padding: 0;
    background: #0d0d12;
    color: #e5e7eb;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    height: 100vh;
    overflow: hidden;
  }

  .app-root {
    display: flex;
    height: 100vh;
    gap: 0;
  }

  .sidebar {
    width: 300px;
    min-width: 240px;
    background: #111118;
    border-right: 1px solid #1e1f26;
    display: flex;
    flex-direction: column;
    overflow: hidden;
  }

  .sidebar-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 16px 16px 12px;
    border-bottom: 1px solid #1e1f26;
  }

  .sidebar-title {
    font-size: 13px;
    font-weight: 600;
    color: #9ca3af;
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  .btn-icon {
    width: 28px;
    height: 28px;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 6px;
    border: none;
    background: transparent;
    color: #6b7280;
    cursor: pointer;
    transition: background 0.15s, color 0.15s;
  }
  .btn-icon:hover:not(:disabled) {
    background: #1e1f26;
    color: #e5e7eb;
  }
  .btn-icon:disabled { opacity: 0.4; cursor: not-allowed; }
  .btn-icon svg { width: 16px; height: 16px; }

  :global(.spin) {
    animation: spin 1s linear infinite;
  }
  @keyframes spin { to { transform: rotate(360deg); } }

  .main-panel {
    flex: 1;
    overflow: hidden;
    display: flex;
    flex-direction: column;
  }
</style>
