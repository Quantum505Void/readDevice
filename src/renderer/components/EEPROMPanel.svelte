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

  let activeTab = $state<"data" | "log">("data");
  let logEl = $state<HTMLElement | null>(null);
  let autoScroll = $state(true);

  $effect(() => {
    if (autoScroll && logEl && logs.length) {
      logEl.scrollTop = logEl.scrollHeight;
    }
  });

  const EEP_SIZE = 4096;
</script>

<div class="panel">
  <!-- 顶部工具栏 -->
  <div class="toolbar">
    <div class="device-badge">
      {#if device}
        <span class="device-label">{device.vendor} {device.product}</span>
        <span class="device-vid">{device.vid}:{device.pid}</span>
        {#if device.supported}
          <span class="mode-badge">{device.mode === 1 ? "8系 逐字节" : "9系 批量"}</span>
        {:else}
          <span class="unsupported-badge">不支持</span>
        {/if}
      {:else}
        <span class="no-device">← 从左侧选择设备</span>
      {/if}
    </div>

    <div class="toolbar-actions">
      {#if !isReading}
        <button
          class="btn-primary"
          disabled={!device?.supported}
          onclick={onStart}
        >
          <svg viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z"/></svg>
          开始读取
        </button>
      {:else}
        <button class="btn-danger" onclick={onStop}>
          <svg viewBox="0 0 24 24" fill="currentColor"><path d="M6 6h12v12H6z"/></svg>
          停止
        </button>
      {/if}

      <button
        class="btn-secondary"
        disabled={rows.length === 0}
        onclick={onExport}
      >
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/>
          <polyline points="7 10 12 15 17 10"/>
          <line x1="12" y1="15" x2="12" y2="3"/>
        </svg>
        导出
      </button>
    </div>
  </div>

  <!-- 进度条 -->
  <div class="progress-bar-wrap">
    <div class="progress-info">
      <span>EEPROM 读取进度</span>
      <span class="progress-nums">
        {progress.address} / {EEP_SIZE} bytes
        · {progress.percent.toFixed(1)}%
        {#if readDone}· <span class="done-text">完成</span>{/if}
      </span>
    </div>
    <div class="progress-track">
      <div class="progress-fill" style="width: {progress.percent}%"></div>
    </div>
    {#if currentFilename}
      <div class="filename-hint">💾 {currentFilename}</div>
    {/if}
  </div>

  <!-- Tabs -->
  <div class="tabs">
    <button class="tab" class:active={activeTab === "data"} onclick={() => activeTab = "data"}>
      数据 <span class="tab-count">{rows.length}</span>
    </button>
    <button class="tab" class:active={activeTab === "log"} onclick={() => activeTab = "log"}>
      日志 <span class="tab-count">{logs.length}</span>
    </button>
    {#if activeTab === "log"}
      <label class="auto-scroll-label">
        <input type="checkbox" bind:checked={autoScroll} />
        自动滚动
      </label>
    {/if}
  </div>

  <!-- 内容区 -->
  <div class="content-area">
    {#if activeTab === "data"}
      {#if rows.length === 0}
        <div class="empty-state">
          <svg viewBox="0 0 64 64" fill="none" stroke="#374151" stroke-width="2">
            <rect x="8" y="16" width="48" height="36" rx="4"/>
            <path d="M20 28h24M20 36h16"/>
          </svg>
          <p>暂无数据</p>
          <p class="empty-hint">选择支持的设备后点击「开始读取」</p>
        </div>
      {:else}
        <div class="data-table-wrap">
          <table class="data-table">
            <thead>
              <tr>
                <th>地址</th>
                <th>十六进制数据 (32 bytes)</th>
              </tr>
            </thead>
            <tbody>
              {#each rows as row (row.address)}
                <tr>
                  <td class="addr-cell">0x{row.address.toString(16).padStart(4, "0").toUpperCase()}</td>
                  <td class="hex-cell">{row.hex}</td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
      {/if}
    {:else}
      <div class="log-area" bind:this={logEl}>
        {#if logs.length === 0}
          <div class="log-empty">日志为空</div>
        {:else}
          {#each logs as log, i (i)}
            <div class="log-line" class:error={log.includes("❌")} class:success={log.includes("✅")}>
              {log}
            </div>
          {/each}
        {/if}
      </div>
    {/if}
  </div>
</div>

<style>
  .panel {
    display: flex;
    flex-direction: column;
    height: 100%;
    background: #0d0d12;
  }

  /* ── 工具栏 ── */
  .toolbar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 12px 20px;
    border-bottom: 1px solid #1e1f26;
    background: #111118;
    gap: 12px;
  }
  .device-badge {
    display: flex;
    align-items: center;
    gap: 8px;
    min-width: 0;
  }
  .device-label {
    font-size: 14px;
    font-weight: 600;
    color: #e5e7eb;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    max-width: 300px;
  }
  .device-vid {
    font-size: 12px;
    color: #4b5563;
    font-family: monospace;
  }
  .mode-badge {
    font-size: 11px;
    font-weight: 600;
    color: #818cf8;
    background: #1e1b4b;
    border-radius: 4px;
    padding: 2px 7px;
  }
  .unsupported-badge {
    font-size: 11px;
    color: #f87171;
    background: #2d1a1a;
    border-radius: 4px;
    padding: 2px 7px;
  }
  .no-device {
    font-size: 13px;
    color: #4b5563;
  }
  .toolbar-actions {
    display: flex;
    gap: 8px;
    flex-shrink: 0;
  }

  /* ── 按钮 ── */
  button {
    display: flex; align-items: center; gap: 6px;
    border: none; cursor: pointer;
    font-size: 13px; font-weight: 500;
    border-radius: 8px; padding: 6px 14px;
    transition: background 0.15s, opacity 0.15s;
  }
  button svg { width: 14px; height: 14px; }
  button:disabled { opacity: 0.35; cursor: not-allowed; }

  .btn-primary {
    background: linear-gradient(135deg, #6366f1, #8b5cf6);
    color: #fff;
  }
  .btn-primary:hover:not(:disabled) { opacity: 0.88; }
  .btn-danger { background: #7f1d1d; color: #fca5a5; }
  .btn-danger:hover:not(:disabled) { background: #991b1b; }
  .btn-secondary { background: #1e1f26; color: #9ca3af; }
  .btn-secondary:hover:not(:disabled) { background: #25262f; color: #e5e7eb; }

  /* ── 进度条 ── */
  .progress-bar-wrap {
    padding: 10px 20px 8px;
    border-bottom: 1px solid #1e1f26;
    background: #0f0f16;
  }
  .progress-info {
    display: flex;
    justify-content: space-between;
    font-size: 11px;
    color: #4b5563;
    margin-bottom: 5px;
  }
  .progress-nums { color: #6b7280; }
  .done-text { color: #22c55e; font-weight: 600; }
  .progress-track {
    height: 4px;
    background: #1e1f26;
    border-radius: 2px;
    overflow: hidden;
  }
  .progress-fill {
    height: 100%;
    background: linear-gradient(90deg, #6366f1, #8b5cf6);
    border-radius: 2px;
    transition: width 0.3s ease;
  }
  .filename-hint {
    font-size: 11px;
    color: #374151;
    margin-top: 4px;
    font-family: monospace;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  /* ── Tabs ── */
  .tabs {
    display: flex;
    align-items: center;
    gap: 2px;
    padding: 8px 16px 0;
    border-bottom: 1px solid #1e1f26;
    background: #111118;
  }
  .tab {
    background: transparent;
    border: none;
    border-bottom: 2px solid transparent;
    border-radius: 0;
    padding: 6px 12px 8px;
    font-size: 13px;
    color: #6b7280;
    cursor: pointer;
    display: flex; align-items: center; gap: 6px;
    transition: color 0.15s;
  }
  .tab:hover { color: #d1d5db; }
  .tab.active { color: #818cf8; border-bottom-color: #818cf8; }
  .tab-count {
    font-size: 11px;
    background: #1e1f26;
    color: #6b7280;
    border-radius: 8px;
    padding: 1px 5px;
  }
  .tab.active .tab-count { background: #1e1b4b; color: #818cf8; }
  .auto-scroll-label {
    margin-left: auto;
    font-size: 12px;
    color: #4b5563;
    display: flex;
    align-items: center;
    gap: 4px;
    cursor: pointer;
    user-select: none;
  }

  /* ── 内容区 ── */
  .content-area {
    flex: 1;
    overflow: hidden;
    display: flex;
    flex-direction: column;
  }

  /* ── 空状态 ── */
  .empty-state {
    flex: 1;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 8px;
    color: #374151;
  }
  .empty-state svg { width: 64px; height: 64px; }
  .empty-state p { margin: 0; font-size: 14px; color: #4b5563; }
  .empty-hint { font-size: 12px !important; color: #374151 !important; }

  /* ── 数据表格 ── */
  .data-table-wrap {
    flex: 1;
    overflow: auto;
  }
  .data-table {
    width: 100%;
    border-collapse: collapse;
    font-size: 12px;
    font-family: "JetBrains Mono", "Fira Code", monospace;
  }
  .data-table thead tr {
    position: sticky;
    top: 0;
    background: #111118;
    z-index: 1;
  }
  .data-table th {
    padding: 8px 16px;
    text-align: left;
    font-size: 11px;
    font-weight: 600;
    color: #4b5563;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    border-bottom: 1px solid #1e1f26;
  }
  .data-table tr:hover { background: #111118; }
  .data-table td { padding: 5px 16px; border-bottom: 1px solid #0f0f16; }
  .addr-cell { color: #818cf8; width: 90px; }
  .hex-cell { color: #9ca3af; letter-spacing: 0.04em; }

  /* ── 日志 ── */
  .log-area {
    flex: 1;
    overflow-y: auto;
    padding: 10px 16px;
    font-family: "JetBrains Mono", monospace;
    font-size: 12px;
  }
  .log-empty { color: #374151; padding: 20px 0; text-align: center; }
  .log-line {
    color: #6b7280;
    padding: 2px 0;
    line-height: 1.5;
    white-space: pre-wrap;
    word-break: break-all;
  }
  .log-line.error { color: #f87171; }
  .log-line.success { color: #22c55e; }
</style>
