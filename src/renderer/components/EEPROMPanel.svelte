<script lang="ts">
  import type { HIDDevice, EEPROMRow } from "../../shared/types";

  let {
    device,
    isReading,
    readDone,
    progress,
    rows,
    logs,
    currentFilename,
    onStart,
    onStop,
    onExport,
  }: {
    device: HIDDevice | null;
    isReading: boolean;
    readDone: boolean;
    progress: { address: number; totalBytes: number; percent: number };
    rows: EEPROMRow[];
    logs: string[];
    currentFilename: string;
    onStart: () => void;
    onStop: () => void;
    onExport: () => void;
  } = $props();

  const EEP_SIZE = 4096;
  let activeTab = $state<"data" | "log">("data");
  let logEl = $state<HTMLElement | null>(null);
  let dataEl = $state<HTMLElement | null>(null);
  let autoScroll = $state(true);
  let copiedAddr = $state<number | null>(null);

  // ── 跳转 ──
  let jumpInput = $state("");
  let jumpError = $state("");
  let hexTableWrap = $state<HTMLElement | null>(null);

  function jumpToAddr() {
    const v = parseInt(jumpInput.replace(/^0x/i, ""), 16);
    if (isNaN(v)) { jumpError = "?"; setTimeout(() => jumpError = "", 1200); return; }
    if (!hexTableWrap) return;
    const el = hexTableWrap.querySelector(`[data-addr="${v}"]`) as HTMLElement | null;
    if (!el) { jumpError = "不存在"; setTimeout(() => jumpError = "", 1200); return; }
    el.scrollIntoView({ block: "center", behavior: "smooth" });
    el.classList.add("jump-flash");
    setTimeout(() => el.classList.remove("jump-flash"), 900);
    jumpError = "";
  }

  // 计时器
  let elapsed = $state(0);
  let timerHandle = $state<ReturnType<typeof setInterval> | null>(null);
  let startTime = $state<number>(0);

  $effect(() => {
    if (isReading && !timerHandle) {
      startTime = Date.now();
      elapsed = 0;
      timerHandle = setInterval(() => { elapsed = (Date.now() - startTime) / 1000; }, 200);
    }
    if (!isReading && timerHandle) {
      clearInterval(timerHandle);
      timerHandle = null;
    }
  });

  $effect(() => {
    if (logs.length && autoScroll && logEl) logEl.scrollTop = logEl.scrollHeight;
  });
  $effect(() => {
    if (rows.length && activeTab === "data" && hexTableWrap) {
      hexTableWrap.scrollTop = hexTableWrap.scrollHeight;
    }
  });

  function copyHex(row: EEPROMRow) {
    const text = `0x${row.address.toString(16).padStart(4, "0").toUpperCase()}: ${row.hex}`;
    navigator.clipboard.writeText(text).then(() => {
      copiedAddr = row.address;
      setTimeout(() => { copiedAddr = null; }, 1200);
    });
  }

  function hexColor(byte: string): string {
    const v = parseInt(byte, 16);
    if (v === 0x00) return "zero";
    if (v === 0xFF) return "ff";
    if (v >= 0x80) return "hi";
    return "lo";
  }

  function splitHex(hex: string): string[] {
    return hex.trim().split(/\s+/).filter(Boolean);
  }

  // 把 hex 行转为可打印 ASCII 字符串
  function toAscii(hex: string): string {
    return splitHex(hex).map(b => {
      const v = parseInt(b, 16);
      return v >= 0x20 && v <= 0x7e ? String.fromCharCode(v) : "·";
    }).join("");
  }

  function fmtElapsed(s: number): string {
    if (s < 60) return `${s.toFixed(1)}s`;
    return `${Math.floor(s / 60)}m ${(s % 60).toFixed(0)}s`;
  }
</script>

<div class="panel">
  <!-- ── 工具栏 ──────────────────────────────────────────────────────── -->
  <div class="toolbar">
    <div class="dev-info">
      {#if device}
        <div class="dev-main">
          <span class="dev-name">{device.product}</span>
          <span class="dev-vid">{device.vid}:{device.pid}</span>
        </div>
        {#if device.supported}
          <span class="mode-chip">{device.mode === 1 ? "8系 · 逐字节" : "9系 · 批量32B"}</span>
        {:else}
          <span class="unsupported-chip">⚠ 不在白名单</span>
        {/if}
      {:else}
        <span class="no-dev">从左侧选择支持的设备开始读取</span>
      {/if}
    </div>

    <div class="actions">
      {#if !isReading}
        <button class="btn btn-start" disabled={!device?.supported || isReading} onclick={onStart}>
          <svg viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z"/></svg>
          开始读取
        </button>
      {:else}
        <div class="reading-indicator">
          <span class="pulse-dot"></span>
          <span>读取中…</span>
          <span class="timer">{fmtElapsed(elapsed)}</span>
        </div>
        <button class="btn btn-stop" onclick={onStop}>
          <svg viewBox="0 0 24 24" fill="currentColor"><rect x="6" y="6" width="12" height="12" rx="2"/></svg>
          停止
        </button>
      {/if}
      <button class="btn btn-export" disabled={rows.length === 0} onclick={onExport}>
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/>
          <polyline points="7 10 12 15 17 10"/>
          <line x1="12" y1="15" x2="12" y2="3"/>
        </svg>
        导出
      </button>
    </div>
  </div>

  <!-- ── 进度区 ───────────────────────────────────────────────────────── -->
  <div class="progress-area">
    <div class="progress-header">
      <div class="progress-title">
        EEPROM 进度
        {#if readDone}
          <span class="done-badge">✓ 完成</span>
        {/if}
      </div>
      <div class="progress-meta">
        <span class="mono">{progress.address.toString().padStart(4, "0")}</span>
        <span class="slash">/</span>
        <span class="mono">{EEP_SIZE}</span>
        <span class="bytes-label">bytes</span>
        <span class="pct">{progress.percent.toFixed(1)}%</span>
      </div>
    </div>

    <div class="progress-track">
      <div class="progress-fill" class:done={readDone} style="width: {progress.percent}%"></div>
      {#each [1024, 2048, 3072] as mark}
        <div class="tick" style="left: {(mark / EEP_SIZE) * 100}%"></div>
      {/each}
    </div>

    {#if currentFilename}
      <div class="filename">
        <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5">
          <path d="M9 2H4a1 1 0 0 0-1 1v10a1 1 0 0 0 1 1h8a1 1 0 0 0 1-1V6z"/>
          <path d="M9 2v4h4"/>
        </svg>
        {currentFilename}
      </div>
    {/if}
  </div>

  <!-- ── Tabs ──────────────────────────────────────────────────────────── -->
  <div class="tabs">
    <button class="tab" class:active={activeTab === "data"} onclick={() => activeTab = "data"}>
      数据
      {#if rows.length > 0}
        <span class="tab-badge">{rows.length}</span>
      {/if}
    </button>
    <button class="tab" class:active={activeTab === "log"} onclick={() => activeTab = "log"}>
      日志
      {#if logs.length > 0}
        <span class="tab-badge">{logs.length}</span>
      {/if}
    </button>
    {#if activeTab === "log"}
      <label class="auto-scroll">
        <input type="checkbox" bind:checked={autoScroll} />
        自动滚动
      </label>
    {/if}
    {#if activeTab === "data" && rows.length > 0}
      <div class="jump-box" class:err={!!jumpError}>
        <span class="jump-pfx">0x</span>
        <input
          class="jump-input"
          type="text"
          placeholder="0100"
          maxlength="4"
          bind:value={jumpInput}
          onkeydown={(e) => e.key === "Enter" && jumpToAddr()}
          title="输入地址跳转，按 Enter"
        />
        <button class="jump-btn" onclick={jumpToAddr} title="跳转">→</button>
        {#if jumpError}<span class="jump-err">{jumpError}</span>{/if}
      </div>
    {/if}
  </div>

  <!-- ── 内容区 ─────────────────────────────────────────────────────────── -->
  <div class="content">
    {#if activeTab === "data"}
      {#if rows.length === 0}
        <div class="empty">
          <svg viewBox="0 0 64 64" fill="none" stroke="#2a2b36" stroke-width="1.5">
            <rect x="8" y="16" width="48" height="34" rx="3"/>
            <path d="M18 8h28l4 8H14z"/>
            <path d="M20 30h24M20 38h14"/>
          </svg>
          {#if device?.supported}
            <p>点击「开始读取」读取 EEPROM 数据</p>
          {:else if device}
            <p>该设备不在支持白名单中</p>
            <p class="sub">仅支持 VID=30FA 的 A8xx/A9xx 系列</p>
          {:else}
            <p>从左侧选择设备</p>
          {/if}
        </div>
      {:else}
        <div class="hex-table-wrap" bind:this={hexTableWrap}>
          <table class="hex-table">
            <thead>
              <tr>
                <th class="th-addr">地址</th>
                <th class="th-hex">十六进制（32 bytes）</th>
                <th class="th-ascii">ASCII</th>
                <th class="th-action"></th>
              </tr>
            </thead>
            <tbody>
              {#each rows as row (row.address)}
                <tr class="hex-row" data-addr={row.address}>
                  <td class="td-addr">
                    0x{row.address.toString(16).padStart(4, "0").toUpperCase()}
                  </td>
                  <td class="td-hex">
                    {#each splitHex(row.hex) as byte, i}
                      <span class="byte {hexColor(byte)}">{byte}</span>
                      {#if i === 7 || i === 15 || i === 23}
                        <span class="hex-gap"></span>
                      {/if}
                    {/each}
                  </td>
                  <td class="td-ascii">{toAscii(row.hex)}</td>
                  <td class="td-action">
                    <button
                      class="copy-btn"
                      class:copied={copiedAddr === row.address}
                      onclick={() => copyHex(row)}
                      title="复制此行"
                    >
                      {#if copiedAddr === row.address}
                        <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2">
                          <polyline points="2 8 6 12 14 4"/>
                        </svg>
                      {:else}
                        <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5">
                          <rect x="5" y="5" width="9" height="9" rx="1"/>
                          <path d="M11 5V3a1 1 0 0 0-1-1H3a1 1 0 0 0-1 1v7a1 1 0 0 0 1 1h2"/>
                        </svg>
                      {/if}
                    </button>
                  </td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
      {/if}
    {:else}
      <div class="log-wrap" bind:this={logEl}>
        {#if logs.length === 0}
          <div class="log-empty">暂无日志</div>
        {:else}
          {#each logs as line, i (i)}
            <div
              class="log-line"
              class:err={line.includes("❌")}
              class:ok={line.includes("✅")}
              class:warn={line.includes("⚠")}
              class:info={line.includes("🔍") || line.includes("📁") || line.includes("🚀") || line.includes("📊")}
            >{line}</div>
          {/each}
        {/if}
      </div>
    {/if}
  </div>

  <!-- ── 状态栏 ─────────────────────────────────────────────────────────── -->
  <div class="statusbar">
    <div class="sb-left">
      {#if device}
        <span class="sb-item">
          <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5">
            <rect x="1" y="5" width="14" height="9" rx="1.5"/>
            <path d="M5 3h6l1 2H4z"/>
          </svg>
          {device.vendor !== "未知厂商" ? device.vendor : device.vid}
        </span>
        <span class="sb-sep">·</span>
        <span class="sb-item">{device.product}</span>
      {:else}
        <span class="sb-item muted">无设备</span>
      {/if}
    </div>
    <div class="sb-right">
      {#if rows.length > 0}
        <span class="sb-item">
          <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5">
            <rect x="2" y="2" width="12" height="12" rx="1.5"/>
            <path d="M5 6h6M5 9h4"/>
          </svg>
          {rows.length * 32} bytes
        </span>
        <span class="sb-sep">·</span>
        <span class="sb-item">{rows.length} 行</span>
      {/if}
      {#if readDone && elapsed > 0}
        <span class="sb-sep">·</span>
        <span class="sb-item ok-text">
          <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5">
            <circle cx="8" cy="8" r="6"/>
            <polyline points="5 8 7 10 11 6"/>
          </svg>
          {fmtElapsed(elapsed)}
        </span>
      {/if}
      {#if isReading}
        <span class="sb-item pulse-text">
          {progress.percent.toFixed(0)}% · {fmtElapsed(elapsed)}
        </span>
      {/if}
    </div>
  </div>
</div>

<style>
  .panel { display: flex; flex-direction: column; height: 100%; }

  /* ── 工具栏 ── */
  .toolbar {
    display: flex; align-items: center; justify-content: space-between;
    padding: 12px 20px;
    background: #101018;
    border-bottom: 1px solid #1e1f2c;
    gap: 12px;
    flex-shrink: 0;
  }
  .dev-info { display: flex; align-items: center; gap: 10px; min-width: 0; flex: 1; }
  .dev-main { display: flex; align-items: baseline; gap: 8px; min-width: 0; }
  .dev-name {
    font-size: 14px; font-weight: 600; color: #e2e3ea;
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 280px;
  }
  .dev-vid { font-size: 12px; color: #374151; font-family: monospace; flex-shrink: 0; }
  .mode-chip {
    font-size: 11px; font-weight: 600;
    color: #818cf8; background: #16193a;
    border: 1px solid #2a2b4a;
    border-radius: 5px; padding: 2px 8px; flex-shrink: 0;
  }
  .unsupported-chip {
    font-size: 11px; color: #f87171; background: #2d1a1a;
    border-radius: 5px; padding: 2px 8px;
  }
  .no-dev { font-size: 13px; color: #374151; }

  .actions { display: flex; align-items: center; gap: 8px; flex-shrink: 0; }
  .reading-indicator {
    display: flex; align-items: center; gap: 6px;
    font-size: 13px; color: #818cf8;
  }
  .timer { font-family: monospace; font-size: 12px; color: #6366f1; }
  .pulse-dot {
    width: 7px; height: 7px; border-radius: 50%;
    background: #818cf8;
    animation: pulse 1.2s ease-in-out infinite;
  }
  @keyframes pulse {
    0%, 100% { opacity: 1; transform: scale(1); }
    50% { opacity: 0.4; transform: scale(0.7); }
  }

  .btn {
    display: flex; align-items: center; gap: 6px;
    padding: 7px 14px; border-radius: 8px; border: none;
    font-size: 13px; font-weight: 500; cursor: pointer;
    transition: all 0.14s;
  }
  .btn:disabled { opacity: 0.35; cursor: not-allowed; }
  .btn svg { width: 14px; height: 14px; }
  .btn-start {
    background: linear-gradient(135deg, #4f46e5, #7c3aed);
    color: #fff;
  }
  .btn-start:hover:not(:disabled) {
    background: linear-gradient(135deg, #4338ca, #6d28d9);
    box-shadow: 0 0 12px 2px #6366f133;
  }
  .btn-stop { background: #3b1f1f; color: #fca5a5; border: 1px solid #5c2626; }
  .btn-stop:hover { background: #4c2020; }
  .btn-export { background: #1a1b26; color: #9ca3af; border: 1px solid #2a2b36; }
  .btn-export:hover:not(:disabled) { background: #22233a; color: #e2e3ea; }

  /* ── 进度区 ── */
  .progress-area {
    padding: 10px 20px 9px;
    background: #0d0d15;
    border-bottom: 1px solid #1e1f2c;
    flex-shrink: 0;
  }
  .progress-header {
    display: flex; align-items: center; justify-content: space-between;
    margin-bottom: 6px;
  }
  .progress-title {
    font-size: 11px; font-weight: 600;
    text-transform: uppercase; letter-spacing: 0.06em;
    color: #374151;
    display: flex; align-items: center; gap: 6px;
  }
  .done-badge {
    font-size: 10px; color: #22c55e; background: #0d2418;
    border: 1px solid #166534; border-radius: 4px; padding: 1px 6px;
  }
  .progress-meta {
    display: flex; align-items: center; gap: 4px;
    font-size: 11px; color: #374151;
  }
  .mono { font-family: monospace; color: #6b7280; }
  .slash { color: #2a2b36; }
  .bytes-label { color: #2a2b36; }
  .pct { color: #818cf8; font-weight: 600; margin-left: 6px; }

  .progress-track {
    position: relative;
    height: 5px; background: #1a1b26; border-radius: 3px; overflow: hidden;
  }
  .progress-fill {
    height: 100%;
    background: linear-gradient(90deg, #4f46e5, #8b5cf6);
    border-radius: 3px;
    transition: width 0.25s ease;
  }
  .progress-fill.done { background: linear-gradient(90deg, #059669, #22c55e); }
  .tick {
    position: absolute; top: 0; bottom: 0;
    width: 1px; background: #0d0d15;
    pointer-events: none;
  }
  .filename {
    display: flex; align-items: center; gap: 5px;
    margin-top: 5px;
    font-size: 11px; color: #374151;
    font-family: monospace;
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
  }
  .filename svg { width: 12px; height: 12px; flex-shrink: 0; color: #4b5563; }

  /* ── Tabs ── */
  .tabs {
    display: flex; align-items: center; gap: 2px;
    padding: 0 16px;
    background: #101018;
    border-bottom: 1px solid #1e1f2c;
    flex-shrink: 0;
  }
  .tab {
    display: flex; align-items: center; gap: 5px;
    background: transparent; border: none;
    border-bottom: 2px solid transparent;
    padding: 8px 10px 9px;
    font-size: 13px; color: #4b5563;
    cursor: pointer; transition: color 0.12s;
  }
  .tab:hover { color: #9ca3af; }
  .tab.active { color: #818cf8; border-bottom-color: #6366f1; }
  .tab-badge {
    font-size: 10px; background: #1a1b26; color: #4b5563;
    border-radius: 8px; padding: 1px 5px;
  }
  .tab.active .tab-badge { background: #16193a; color: #818cf8; }
  .auto-scroll {
    margin-left: auto;
    display: flex; align-items: center; gap: 5px;
    font-size: 12px; color: #374151; cursor: pointer;
  }
  /* ── 跳转 ── */
  .jump-box {
    margin-left: auto;
    display: flex; align-items: center; gap: 0;
    background: #1a1b26; border: 1px solid #2a2b36;
    border-radius: 6px; overflow: hidden;
    font-size: 12px;
    transition: border-color .1s;
  }
  .jump-box.err { border-color: #5c2626; }
  .jump-pfx { padding: 0 4px 0 8px; color: #374151; font-family: monospace; }
  .jump-input {
    width: 52px; background: transparent; border: none;
    color: #a5b4fc; font-family: monospace; font-size: 12px;
    padding: 4px 2px; outline: none;
  }
  .jump-btn {
    padding: 4px 8px; background: #22233a; border: none;
    color: #6b7280; cursor: pointer; font-size: 12px;
    transition: all .1s;
  }
  .jump-btn:hover { background: #4f46e5; color: #fff; }
  .jump-err { padding: 0 6px; color: #f87171; font-size: 11px; }

  :global(.jump-flash) {
    animation: jumphl .7s ease-out;
  }
  @keyframes jumphl {
    0%   { background: rgba(99,102,241,.35); }
    100% { background: transparent; }
  }

  /* ── 内容区 ── */
  .content { flex: 1; overflow: hidden; display: flex; flex-direction: column; }

  /* ── 空状态 ── */
  .empty {
    flex: 1; display: flex; flex-direction: column;
    align-items: center; justify-content: center;
    gap: 6px;
  }
  .empty svg { width: 60px; height: 60px; }
  .empty p { margin: 0; font-size: 13px; color: #374151; }
  .empty .sub { font-size: 11px; color: #2a2b36; }

  /* ── HEX 表格 ── */
  .hex-table-wrap {
    flex: 1; overflow: auto;
    scrollbar-width: thin;
    scrollbar-color: #1e1f2c #0d0d12;
  }
  .hex-table-wrap::-webkit-scrollbar { width: 6px; height: 6px; }
  .hex-table-wrap::-webkit-scrollbar-track { background: #0d0d12; }
  .hex-table-wrap::-webkit-scrollbar-thumb { background: #1e1f2c; border-radius: 3px; }
  .hex-table-wrap::-webkit-scrollbar-thumb:hover { background: #2a2b36; }
  .hex-table { width: 100%; border-collapse: collapse; }
  .hex-table thead { position: sticky; top: 0; z-index: 1; background: #101018; }
  .th-addr, .th-hex, .th-ascii, .th-action {
    padding: 7px 12px;
    font-size: 10.5px; font-weight: 700; text-transform: uppercase;
    letter-spacing: 0.06em; color: #374151;
    border-bottom: 1px solid #1e1f2c;
    text-align: left;
  }
  .th-addr { width: 80px; }
  .th-ascii { width: 200px; color: #2d3748; }
  .th-action { width: 36px; }

  .hex-row { transition: background 0.08s; }
  .hex-row:hover { background: #111119; }
  .hex-row:hover .copy-btn { opacity: 1; }

  .td-addr {
    padding: 5px 12px;
    font-family: "JetBrains Mono", "Cascadia Code", monospace;
    font-size: 12px; color: #6366f1;
    border-bottom: 1px solid #0f1018;
    white-space: nowrap;
  }
  .td-hex {
    padding: 5px 12px;
    border-bottom: 1px solid #0f1018;
    font-family: "JetBrains Mono", "Cascadia Code", monospace;
    font-size: 12px;
    display: flex; align-items: center; flex-wrap: wrap; gap: 2px;
  }
  .td-ascii {
    padding: 5px 12px;
    border-bottom: 1px solid #0f1018;
    font-family: "JetBrains Mono", "Cascadia Code", monospace;
    font-size: 11px;
    color: #3d4566;
    letter-spacing: 0.04em;
    white-space: nowrap;
    border-left: 1px solid #1a1b26;
  }
  .hex-row:hover .td-ascii { color: #5a6080; }
  .td-action { padding: 5px 8px; border-bottom: 1px solid #0f1018; }

  /* 字节颜色 */
  .byte {
    display: inline-block; min-width: 22px;
    text-align: center; border-radius: 3px; padding: 0 1px;
  }
  .byte.zero { color: #2a2b36; }
  .byte.ff { color: #f59e0b; }
  .byte.hi { color: #9ca3af; }
  .byte.lo { color: #6b7280; }
  .hex-gap { display: inline-block; width: 6px; }

  .copy-btn {
    opacity: 0;
    width: 24px; height: 24px;
    display: flex; align-items: center; justify-content: center;
    background: transparent; border: none;
    color: #4b5563; cursor: pointer; border-radius: 4px;
    transition: background 0.1s, color 0.1s, opacity 0.1s;
  }
  .copy-btn:hover { background: #1a1b26; color: #9ca3af; }
  .copy-btn.copied { color: #22c55e; opacity: 1; }
  .copy-btn svg { width: 12px; height: 12px; }

  /* ── 日志 ── */
  .log-wrap {
    flex: 1; overflow-y: auto;
    padding: 10px 14px;
    font-family: "JetBrains Mono", "Cascadia Code", monospace;
    font-size: 12px;
    scrollbar-width: thin;
    scrollbar-color: #1e1f2c #0d0d12;
  }
  .log-wrap::-webkit-scrollbar { width: 6px; }
  .log-wrap::-webkit-scrollbar-track { background: #0d0d12; }
  .log-wrap::-webkit-scrollbar-thumb { background: #1e1f2c; border-radius: 3px; }
  .log-wrap::-webkit-scrollbar-thumb:hover { background: #2a2b36; }
  .log-empty { color: #2a2b36; text-align: center; padding: 24px; }
  .log-line {
    color: #4b5563; padding: 2px 0; line-height: 1.6;
    white-space: pre-wrap; word-break: break-all;
  }
  .log-line.err  { color: #ef4444; }
  .log-line.ok   { color: #22c55e; }
  .log-line.warn { color: #f59e0b; }
  .log-line.info { color: #818cf8; }

  /* ── 状态栏 ── */
  .statusbar {
    display: flex; align-items: center; justify-content: space-between;
    height: 24px; padding: 0 14px;
    background: #090910;
    border-top: 1px solid #16161f;
    flex-shrink: 0;
    font-size: 11px;
  }
  .sb-left, .sb-right { display: flex; align-items: center; gap: 6px; }
  .sb-item {
    display: flex; align-items: center; gap: 4px;
    color: #2d3748;
  }
  .sb-item svg { width: 11px; height: 11px; }
  .sb-sep { color: #1e1f2c; }
  .sb-item.muted { color: #1e1f2c; }
  .ok-text { color: #16a34a; }
  .pulse-text {
    color: #6366f1;
    animation: textpulse 1.4s ease-in-out infinite;
  }
  @keyframes textpulse {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.5; }
  }
</style>
