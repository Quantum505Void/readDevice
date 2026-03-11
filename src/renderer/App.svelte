<script lang="ts">
  import { onMount } from "svelte";
  import { electroview, setLogHandler, setDataRowHandler, setProgressHandler, setReadCompleteHandler, setReadErrorHandler } from "./main.ts";
  import type { HIDDevice, EEPROMRow } from "../shared/types";
  import DeviceList from "./components/DeviceList.svelte";
  import EEPROMPanel from "./components/EEPROMPanel.svelte";

  // ─── 状态 ─────────────────────────────────────────────────────────────────
  let devices = $state<HIDDevice[]>([]);
  let selectedDevice = $state<HIDDevice | null>(null);
  let isScanning = $state(false);
  let isReading = $state(false);
  let logs = $state<string[]>([]);
  let rows = $state<EEPROMRow[]>([]);
  let progress = $state({ address: 0, totalBytes: 0, percent: 0 });
  let currentFilename = $state("");
  let readDone = $state(false);

  let usbDevices = $derived(devices.filter(d => !d.isBluetooth));
  let btDevices  = $derived(devices.filter(d => d.isBluetooth));
  let supportedCount = $derived(devices.filter(d => d.supported).length);

  function addLog(msg: string) {
    const t = new Date().toLocaleTimeString("zh-CN", { hour12: false });
    logs = [...logs.slice(-999), `[${t}] ${msg}`];
  }

  // ─── RPC 回调 ──────────────────────────────────────────────────────────────
  setLogHandler(msg => addLog(msg));
  setDataRowHandler((address, hex) => { rows = [...rows, { address, hex }]; });
  setProgressHandler((address, totalBytes, percent) => {
    progress = { address, totalBytes, percent };
  });
  setReadCompleteHandler((totalBytes, filename) => {
    isReading = false;
    readDone = true;
    currentFilename = filename;
    progress = { address: 4096, totalBytes, percent: 100 };
    addLog(`✅ 读取完成，共 ${totalBytes} 字节`);
  });
  setReadErrorHandler(msg => {
    isReading = false;
    addLog(`❌ ${msg}`);
  });

  // ─── 扫描 ─────────────────────────────────────────────────────────────────
  async function scanDevices() {
    isScanning = true;
    try {
      devices = await electroview.rpc.request.scanDevices({});
      addLog(`🔍 扫描完成：${devices.length} 个设备，${supportedCount} 个可读取`);
    } catch (e) {
      addLog(`❌ 扫描失败: ${e}`);
    } finally {
      isScanning = false;
    }
  }

  // ─── 读取 ─────────────────────────────────────────────────────────────────
  async function startReading() {
    if (!selectedDevice || isReading) return;
    rows = []; logs = []; readDone = false; currentFilename = "";
    progress = { address: 0, totalBytes: 0, percent: 0 };
    isReading = true;
    addLog(`🚀 开始读取：${selectedDevice.vendor} ${selectedDevice.product} (${selectedDevice.vid}:${selectedDevice.pid})`);
    try {
      const res = await electroview.rpc.request.startReading({
        path: selectedDevice.path,
        vid: selectedDevice.vid,
        pid: selectedDevice.pid,
      });
      if (!res.success) { isReading = false; addLog(`❌ ${res.error}`); }
    } catch (e) {
      isReading = false; addLog(`❌ 启动失败: ${e}`);
    }
  }

  async function stopReading() {
    await electroview.rpc.request.stopReading({});
    isReading = false;
    addLog("⏸️ 已停止");
  }

  function exportData() {
    if (!rows.length) return;
    const content = rows.map(r => `0x${r.address.toString(16).padStart(4, "0").toUpperCase()}: ${r.hex}`).join("\n");
    const a = Object.assign(document.createElement("a"), {
      href: URL.createObjectURL(new Blob([content], { type: "text/plain" })),
      download: `eeprom_${Date.now()}.hid`,
    });
    a.click();
    URL.revokeObjectURL(a.href);
    addLog(`📤 已导出 ${rows.length} 行数据`);
  }

  onMount(() => scanDevices());
</script>

<div class="shell">
  <!-- ── 顶栏 ─────────────────────────────────────────────────────────────── -->
  <header class="topbar">
    <div class="topbar-brand">
      <svg class="brand-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
        <rect x="2" y="7" width="20" height="14" rx="2"/>
        <path d="M16 3H8l-2 4h12z"/>
        <circle cx="8" cy="14" r="1" fill="currentColor"/>
        <circle cx="12" cy="14" r="1" fill="currentColor"/>
        <circle cx="16" cy="14" r="1" fill="currentColor"/>
      </svg>
      <span class="brand-name">HID Device Reader</span>
      <span class="brand-version">v1.0</span>
    </div>
    <div class="topbar-stats">
      {#if devices.length > 0}
        <span class="stat"><span class="stat-num">{devices.length}</span> 设备</span>
        {#if supportedCount > 0}
          <span class="stat supported-stat"><span class="stat-num">{supportedCount}</span> 可读取</span>
        {/if}
      {/if}
    </div>
    <button class="refresh-btn" onclick={scanDevices} disabled={isScanning} title="刷新 (F5)">
      <svg class:spin={isScanning} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <path d="M1 4v6h6M23 20v-6h-6"/>
        <path d="M20.49 9A9 9 0 0 0 5.64 5.64L1 10m22 4l-4.64 4.36A9 9 0 0 1 3.51 15"/>
      </svg>
      {isScanning ? "扫描中…" : "刷新"}
    </button>
  </header>

  <div class="body">
    <!-- ── 侧栏 ──────────────────────────────────────────────────────────── -->
    <aside class="sidebar">
      {#if devices.length === 0 && !isScanning}
        <div class="empty-sidebar">
          <svg viewBox="0 0 48 48" fill="none" stroke="#374151" stroke-width="1.5">
            <rect x="4" y="12" width="40" height="28" rx="3"/>
            <path d="M16 8h16l2 4H14z"/>
          </svg>
          <p>未发现设备</p>
          <button class="btn-link" onclick={scanDevices}>重新扫描</button>
        </div>
      {:else}
        <DeviceList label="USB 设备" list={usbDevices} bind:selected={selectedDevice} />
        <DeviceList label="蓝牙设备" list={btDevices}  bind:selected={selectedDevice} />
      {/if}
    </aside>

    <!-- ── 主区 ──────────────────────────────────────────────────────────── -->
    <main class="main">
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
    </main>
  </div>
</div>

<svelte:window onkeydown={e => { if (e.key === "F5") { e.preventDefault(); scanDevices(); }}} />

<style>
  @import "tailwindcss";

  :global(*) { box-sizing: border-box; }

  :global(body) {
    margin: 0; padding: 0;
    background: #0d0d12;
    color: #e2e3ea;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Noto Sans SC", sans-serif;
    height: 100vh;
    overflow: hidden;
  }

  :global(::-webkit-scrollbar) { width: 6px; height: 6px; }
  :global(::-webkit-scrollbar-track) { background: transparent; }
  :global(::-webkit-scrollbar-thumb) { background: #2a2b36; border-radius: 3px; }
  :global(::-webkit-scrollbar-thumb:hover) { background: #3a3b48; }

  .shell { display: flex; flex-direction: column; height: 100vh; }

  /* ── 顶栏 ── */
  .topbar {
    height: 48px;
    background: #101018;
    border-bottom: 1px solid #1e1f2c;
    display: flex;
    align-items: center;
    padding: 0 16px;
    gap: 16px;
    flex-shrink: 0;
    -webkit-app-region: drag;
  }
  .topbar-brand { display: flex; align-items: center; gap: 8px; }
  .brand-icon {
    width: 20px; height: 20px;
    color: #818cf8;
    -webkit-app-region: no-drag;
  }
  .brand-name { font-size: 14px; font-weight: 600; color: #e2e3ea; }
  .brand-version {
    font-size: 11px; color: #4b5563;
    background: #1a1b26; padding: 1px 6px; border-radius: 4px;
  }
  .topbar-stats { display: flex; align-items: center; gap: 10px; margin-left: 8px; }
  .stat { font-size: 12px; color: #4b5563; }
  .stat-num { font-weight: 600; color: #6b7280; }
  .supported-stat .stat-num { color: #818cf8; }
  .refresh-btn {
    margin-left: auto;
    display: flex; align-items: center; gap: 6px;
    background: #1a1b26; border: 1px solid #2a2b36;
    color: #9ca3af; font-size: 13px;
    padding: 5px 12px; border-radius: 7px;
    cursor: pointer; transition: all 0.15s;
    -webkit-app-region: no-drag;
  }
  .refresh-btn:hover:not(:disabled) { background: #22233a; color: #e2e3ea; }
  .refresh-btn:disabled { opacity: 0.4; cursor: default; }
  .refresh-btn svg { width: 14px; height: 14px; }
  :global(.spin) { animation: spin 0.8s linear infinite; }
  @keyframes spin { to { transform: rotate(360deg); } }

  /* ── 主体 ── */
  .body { display: flex; flex: 1; overflow: hidden; }

  /* ── 侧栏 ── */
  .sidebar {
    width: 280px;
    min-width: 220px;
    background: #0f0f17;
    border-right: 1px solid #1e1f2c;
    display: flex;
    flex-direction: column;
    overflow-y: auto;
  }
  .empty-sidebar {
    flex: 1; display: flex; flex-direction: column;
    align-items: center; justify-content: center;
    gap: 8px; padding: 24px; color: #374151;
  }
  .empty-sidebar svg { width: 48px; height: 48px; }
  .empty-sidebar p { margin: 0; font-size: 13px; color: #4b5563; }
  .btn-link {
    background: none; border: none;
    color: #818cf8; font-size: 13px;
    cursor: pointer; padding: 4px 0;
    text-decoration: underline;
  }

  /* ── 主区 ── */
  .main { flex: 1; overflow: hidden; display: flex; flex-direction: column; }
</style>
