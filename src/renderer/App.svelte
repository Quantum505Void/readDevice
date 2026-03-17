<script lang="ts">
  import { onMount } from "svelte";
  import { electroview, setLogHandler, setDataRowHandler, setProgressHandler, setReadCompleteHandler, setReadErrorHandler, setDeviceChangedHandler } from "./main.ts";
  import type { HIDDevice, EEPROMRow } from "../shared/types";
  import DeviceList from "./components/DeviceList.svelte";
  import EEPROMPanel from "./components/EEPROMPanel.svelte";
  import DiffPanel from "./components/DiffPanel.svelte";

  // ─── 状态 ─────────────────────────────────────────────────────────────────
  let devices = $state<HIDDevice[]>([]);
  let selectedDevice = $state<HIDDevice | null>(null);
  let isScanning = $state(false);
  let isReading = $state(false);
  let logs = $state<string[]>([]);
  let rows = $state<EEPROMRow[]>([]);
  let progress = $state({ address: 0, totalBytes: 0, percent: 0 });
  let activeTab = $state<"read" | "diff">("read");
  let diffBadge = $state(0);
  let currentFilename = $state("");
  let readDone = $state(false);
  let saveDir = $state("");

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
  async function changeSaveDir() {
    const res = await electroview.rpc.request.chooseSaveDir({});
    if (res.success) {
      saveDir = res.dir;
      addLog(`📁 存储目录已更改为：${res.dir}`);
    }
  }

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

  onMount(async () => {
    await scanDevices();
    const cfg = await electroview.rpc.request.getSaveDir({});
    saveDir = cfg.dir;
    setDeviceChangedHandler(async ({ added, removed, addedIds, removedIds }) => {
      console.log("[renderer] devicesUpdated", { added, removed });
      devices = await electroview.rpc.request.scanDevices({});
      if (added > 0) addLog(`🔌 +${added} 设备插入`);
      if (removed > 0) {
        addLog(`🔌 -${removed} 设备移除`);
        // 被移除的设备如果正在读取，停止
        if (selectedDevice && removedIds.includes(`${selectedDevice.vid}:${selectedDevice.pid}:${selectedDevice.path}`)) {
          if (isReading) await electroview.rpc.request.stopReading({});
          selectedDevice = null;
          addLog("⚠️ 当前设备已断开");
        }
      }
    });
    await electroview.rpc.request.webviewReady({});
  });

  // ── Sidebar resize ──
  let sidebarWidth = $state(280);
  const SIDEBAR_MIN = 200;
  const SIDEBAR_MAX = 420;
  let isResizing = $state(false);

  function startResize(e: MouseEvent) {
    isResizing = true;
    const startX = e.clientX;
    const startW = sidebarWidth;
    const onMove = (ev: MouseEvent) => {
      sidebarWidth = Math.min(SIDEBAR_MAX, Math.max(SIDEBAR_MIN, startW + ev.clientX - startX));
    };
    const onUp = () => {
      isResizing = false;
      window.removeEventListener("mousemove", onMove);
      window.removeEventListener("mouseup", onUp);
    };
    window.addEventListener("mousemove", onMove);
    window.addEventListener("mouseup", onUp);
  }
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
    <div class="topbar-tabs">
      <button class="topbar-tab" class:active={activeTab === "read"} onclick={() => activeTab = "read"}>
        读取
      </button>
      <button class="topbar-tab" class:active={activeTab === "diff"} onclick={() => activeTab = "diff"}>
        对比
        {#if diffBadge > 0}
          <span class="tab-badge-red">{diffBadge}</span>
        {:else if rows.length > 0}
          <span class="tab-dot"></span>
        {/if}
      </button>
    </div>
    <button class="refresh-btn" onclick={scanDevices} disabled={isScanning} title="刷新 (F5)">
      <svg class:spin={isScanning} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <path d="M1 4v6h6M23 20v-6h-6"/>
        <path d="M20.49 9A9 9 0 0 0 5.64 5.64L1 10m22 4l-4.64 4.36A9 9 0 0 1 3.51 15"/>
      </svg>
      {isScanning ? "扫描中…" : "刷新"}
    </button>
    <!-- 存储目录 -->
    <div class="savedir-bar" title={saveDir}>
      <span class="savedir-label">📁</span>
      <span class="savedir-path">{saveDir || "…"}</span>
      <button class="savedir-btn" onclick={changeSaveDir} title="更改存储目录">更改</button>
    </div>
  </header>

  <div class="body">
    <!-- ── 侧栏 ──────────────────────────────────────────────────────────── -->
    <aside class="sidebar" style="width:{sidebarWidth}px">
      {#if devices.length === 0 && !isScanning}
        <div class="empty-sidebar">
          <svg viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg">
            <rect x="18" y="8" width="28" height="18" rx="4" fill="#1a1b26" stroke="#2a2b36" stroke-width="1.5"/>
            <circle cx="22" cy="17" r="2" fill="#2a2b36"/>
            <circle cx="28" cy="17" r="2" fill="#2a2b36"/>
            <circle cx="34" cy="17" r="2" fill="#2a2b36"/>
            <rect x="10" y="28" width="44" height="28" rx="5" fill="#111119" stroke="#1e1f2c" stroke-width="1.5"/>
            <line x1="32" y1="26" x2="32" y2="28" stroke="#2a2b36" stroke-width="2"/>
            <rect x="16" y="36" width="32" height="3" rx="1.5" fill="#1e1f2c"/>
            <rect x="16" y="43" width="20" height="3" rx="1.5" fill="#1e1f2c"/>
          </svg>
          <p>未发现 HID 设备</p>
          <span class="empty-hint">连接设备后按 <kbd>F5</kbd> 刷新</span>
          <button class="btn-link" onclick={scanDevices}>立即扫描</button>
        </div>
      {:else}
        <DeviceList label="USB 设备" list={usbDevices} bind:selected={selectedDevice} />
        <DeviceList label="蓝牙设备" list={btDevices}  bind:selected={selectedDevice} />
      {/if}
    </aside>

    <!-- ── Resize handle ── -->
    <!-- svelte-ignore a11y_no_static_element_interactions -->
    <div
      class="resize-handle"
      class:active={isResizing}
      onmousedown={startResize}
    ></div>

    <!-- ── 主区 ──────────────────────────────────────────────────────────── -->
    <main class="main">
      {#if activeTab === "read"}
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
      {:else}
        <DiffPanel currentRows={rows} currentFilename={currentFilename} onDiffCount={(n) => diffBadge = n} />
      {/if}
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
    height: 100%;
    overflow: hidden;
  }

  :global(::-webkit-scrollbar) { width: 6px; height: 6px; }
  :global(::-webkit-scrollbar-track) { background: transparent; }
  :global(::-webkit-scrollbar-thumb) { background: #2a2b36; border-radius: 3px; }
  :global(::-webkit-scrollbar-thumb:hover) { background: #3a3b48; }

  .shell { display: flex; flex-direction: column; height: 100%; }

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
  /* ── topbar tabs ── */
  .topbar-tabs {
    display: flex;
    align-items: center;
    gap: 2px;
    margin-left: 16px;
  }
  .topbar-tab {
    display: flex; align-items: center; gap: 5px;
    padding: 5px 14px;
    background: transparent;
    border: 1px solid transparent;
    border-radius: 7px;
    font-size: 13px; color: #4b5563;
    cursor: pointer; transition: all 0.12s;
  }
  .topbar-tab:hover { color: #9ca3af; background: #111119; }
  .topbar-tab.active {
    color: #e2e3ea;
    background: #1a1b26;
    border-color: #2a2b36;
  }
  .tab-dot {
    display: inline-block;
    width: 5px; height: 5px;
    background: #6366f1;
    border-radius: 50%;
  }
  .tab-badge-red {
    font-size: 10px; background: #3b1f1f; color: #f87171;
    border-radius: 8px; padding: 1px 6px;
    font-weight: 600;
  }

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

  /* ── 存储目录 ── */
  .savedir-bar {
    display: flex; align-items: center; gap: 6px;
    max-width: 320px; min-width: 0;
    background: #0f0f18; border: 1px solid #1e1f2c;
    border-radius: 6px; padding: 0 8px 0 10px; height: 28px;
    overflow: hidden;
  }
  .savedir-label { font-size: 12px; flex-shrink: 0; }
  .savedir-path {
    font-size: 11px; font-family: monospace; color: #4b5563;
    flex: 1; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
    direction: rtl; text-align: left;
  }
  .savedir-btn {
    font-size: 11px; padding: 2px 8px; flex-shrink: 0;
    background: #1a1b26; border: 1px solid #2a2b36;
    color: #6b7280; border-radius: 4px; cursor: pointer; transition: all .1s;
  }
  .savedir-btn:hover { background: #22233a; color: #818cf8; border-color: #4f46e5; }
  :global(.spin) { animation: spin 0.8s linear infinite; }
  @keyframes spin { to { transform: rotate(360deg); } }

  /* ── 主体 ── */
  .body { display: flex; flex: 1; overflow: hidden; }

  /* ── 侧栏 ── */
  .sidebar {
    flex-shrink: 0;
    min-width: 200px;
    max-width: 420px;
    background: #0f0f17;
    border-right: none;
    display: flex;
    flex-direction: column;
    overflow-y: auto;
  }
  .resize-handle {
    width: 4px;
    background: #1a1b24;
    cursor: col-resize;
    flex-shrink: 0;
    transition: background 0.15s;
    position: relative;
  }
  .resize-handle::after {
    content: "";
    position: absolute;
    top: 50%;
    left: 50%;
    transform: translate(-50%, -50%);
    width: 2px;
    height: 40px;
    border-radius: 2px;
    background: #2a2b36;
    transition: background 0.15s;
  }
  .resize-handle:hover,
  .resize-handle.active { background: #22233a; }
  .resize-handle:hover::after,
  .resize-handle.active::after { background: #6366f1; }

  .empty-sidebar {
    flex: 1; display: flex; flex-direction: column;
    align-items: center; justify-content: center;
    gap: 10px; padding: 24px; color: #374151;
  }
  .empty-sidebar svg { width: 64px; height: 64px; opacity: 0.5; }
  .empty-sidebar p { margin: 0; font-size: 14px; font-weight: 600; color: #4b5563; }
  .empty-hint { font-size: 12px; color: #2a2b36; }
  .empty-hint kbd {
    display: inline-block;
    font-size: 11px;
    font-family: monospace;
    background: #1a1b26;
    border: 1px solid #2a2b35;
    border-radius: 4px;
    padding: 1px 5px;
    color: #6b7280;
  }
  .btn-link {
    background: none; border: none;
    color: #6366f1; font-size: 12px;
    cursor: pointer; padding: 4px 10px;
    border: 1px solid #2a2b4a;
    border-radius: 6px;
    transition: background 0.12s, color 0.12s;
  }
  .btn-link:hover { background: #16193a; color: #818cf8; }

  /* ── 主区 ── */
  .main { flex: 1; overflow: hidden; display: flex; flex-direction: column; }
</style>
