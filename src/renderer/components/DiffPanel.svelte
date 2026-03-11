<script lang="ts">
  import type { EEPROMRow, DiffRow } from "../../shared/types";
  import { electroview } from "../main.ts";

  let {
    currentRows,
    currentFilename,
  }: {
    currentRows: EEPROMRow[];
    currentFilename: string;
  } = $props();

  // ── 文件 A/B 状态 ──
  let fileA = $state<{ name: string; rows: EEPROMRow[] } | null>(null);
  let fileB = $state<{ name: string; rows: EEPROMRow[] } | null>(null);
  let loadingA = $state(false);
  let loadingB = $state(false);
  let errorMsg = $state("");

  // ── 用当前读取结果作为 A ──
  function useCurrentAsA() {
    if (!currentRows.length) { errorMsg = "当前没有读取数据"; return; }
    fileA = { name: currentFilename || "当前读取", rows: currentRows };
    errorMsg = "";
  }

  // ── 加载文件 ──
  async function loadFile(side: "A" | "B") {
    if (side === "A") loadingA = true;
    else loadingB = true;
    errorMsg = "";
    try {
      const res = await electroview.rpc.request.openFileForDiff({});
      if (!res.success) { errorMsg = res.error ?? "打开失败"; return; }
      const data = { name: res.filename, rows: res.rows };
      if (side === "A") fileA = data;
      else fileB = data;
    } catch (e) {
      errorMsg = String(e);
    } finally {
      if (side === "A") loadingA = false;
      else loadingB = false;
    }
  }

  function swap() {
    const tmp = fileA;
    fileA = fileB;
    fileB = tmp;
  }

  // ── 计算 diff ──
  let diffRows = $derived((() => {
    if (!fileA || !fileB) return [];
    const mapA = new Map(fileA.rows.map(r => [r.address, r.hex]));
    const mapB = new Map(fileB.rows.map(r => [r.address, r.hex]));
    const allAddrs = [...new Set([...mapA.keys(), ...mapB.keys()])].sort((a, b) => a - b);

    return allAddrs.map(addr => {
      const hexA = mapA.get(addr) ?? "";
      const hexB = mapB.get(addr) ?? "";
      const bytesA = hexA.trim().split(/\s+/).filter(Boolean);
      const bytesB = hexB.trim().split(/\s+/).filter(Boolean);
      const len = Math.max(bytesA.length, bytesB.length);
      const diffMask = Array.from({ length: len }, (_, i) =>
        (bytesA[i] ?? "__") !== (bytesB[i] ?? "__")
      );
      return { address: addr, hexA, hexB, diffMask, hasDiff: diffMask.some(Boolean) } as DiffRow;
    });
  })());

  let diffOnlyRows = $state(false);

  let visibleRows = $derived(diffOnlyRows ? diffRows.filter(r => r.hasDiff) : diffRows);

  let stats = $derived((() => {
    if (!diffRows.length) return null;
    const diffCount = diffRows.filter(r => r.hasDiff).length;
    const totalBytes = diffRows.reduce((s, r) => s + r.diffMask.filter(Boolean).length, 0);
    return { diffCount, totalBytes, total: diffRows.length };
  })());

  // ── 渲染辅助 ──
  function splitHex(hex: string): string[] {
    return hex.trim().split(/\s+/).filter(Boolean);
  }

  function copyDiff() {
    if (!stats) return;
    const lines = diffRows
      .filter(r => r.hasDiff)
      .map(r => `0x${r.address.toString(16).padStart(4,"0").toUpperCase()}: A=[${r.hexA}] B=[${r.hexB}]`)
      .join("\n");
    navigator.clipboard.writeText(lines);
  }
</script>

<div class="diff-panel">
  <!-- ── 顶部控制栏 ── -->
  <div class="diff-toolbar">
    <!-- 文件 A -->
    <div class="file-slot" class:loaded={!!fileA}>
      <div class="slot-label">文件 A</div>
      <div class="slot-name" title={fileA?.name}>{fileA?.name ?? "未选择"}</div>
      <div class="slot-actions">
        {#if currentRows.length > 0}
          <button class="slot-btn btn-current" onclick={useCurrentAsA} title="使用当前读取结果">
            ↑ 当前数据
          </button>
        {/if}
        <button class="slot-btn" onclick={() => loadFile("A")} disabled={loadingA}>
          {loadingA ? "…" : "📂 打开"}
        </button>
      </div>
    </div>

    <!-- 对比统计 / swap -->
    <div class="diff-mid">
      {#if stats}
        <div class="diff-stats">
          <span class="stat-diff">{stats.diffCount} 行差异</span>
          <span class="stat-bytes">{stats.totalBytes} 字节不同</span>
          <span class="stat-pct">{((stats.diffCount / stats.total) * 100).toFixed(1)}%</span>
        </div>
      {:else}
        <div class="diff-hint">← 选择两个文件开始对比 →</div>
      {/if}
      <button class="swap-btn" onclick={swap} title="交换 A/B" disabled={!fileA && !fileB}>⇌</button>
    </div>

    <!-- 文件 B -->
    <div class="file-slot slot-b" class:loaded={!!fileB}>
      <div class="slot-label">文件 B</div>
      <div class="slot-name" title={fileB?.name}>{fileB?.name ?? "未选择"}</div>
      <div class="slot-actions">
        <button class="slot-btn" onclick={() => loadFile("B")} disabled={loadingB}>
          {loadingB ? "…" : "📂 打开"}
        </button>
      </div>
    </div>
  </div>

  {#if errorMsg}
    <div class="error-bar">{errorMsg}</div>
  {/if}

  <!-- ── 过滤 + 复制 ── -->
  {#if diffRows.length > 0}
    <div class="diff-subbar">
      <label class="filter-toggle">
        <input type="checkbox" bind:checked={diffOnlyRows} />
        只显示差异行
        {#if stats && diffOnlyRows}
          <span class="filter-count">{stats.diffCount}</span>
        {/if}
      </label>
      {#if stats && stats.diffCount > 0}
        <button class="copy-diff-btn" onclick={copyDiff}>📋 复制差异</button>
      {/if}
      <span class="row-count">{visibleRows.length} 行</span>
    </div>
  {/if}

  <!-- ── Diff 表格 ── -->
  <div class="diff-content">
    {#if !fileA || !fileB}
      <div class="diff-empty">
        <svg viewBox="0 0 64 64" fill="none" stroke="#2a2b36" stroke-width="1.5">
          <rect x="4" y="8" width="24" height="48" rx="3"/>
          <rect x="36" y="8" width="24" height="48" rx="3"/>
          <path d="M12 20h8M12 28h8M12 36h8" stroke-width="2"/>
          <path d="M44 20h8M44 28h8M44 36h6" stroke-width="2"/>
          <path d="M30 20 L34 24 L30 28M34 20 L30 24 L34 28" stroke="#374151" stroke-width="1.5"/>
        </svg>
        <p>选择 A、B 两个文件后显示 EEPROM 差异</p>
        <p class="sub">支持 .hid 格式（readDevice 导出的文件）</p>
      </div>
    {:else if diffRows.length === 0}
      <div class="diff-empty">
        <svg viewBox="0 0 64 64" fill="none">
          <circle cx="32" cy="32" r="24" stroke="#22c55e" stroke-width="2"/>
          <polyline points="20 32 28 40 44 24" stroke="#22c55e" stroke-width="2.5" stroke-linecap="round"/>
        </svg>
        <p style="color:#22c55e">两个文件完全一致</p>
      </div>
    {:else}
      <div class="diff-table-wrap">
        <table class="diff-table">
          <thead>
            <tr>
              <th class="th-addr">地址</th>
              <th class="th-hex">文件 A — {fileA.name}</th>
              <th class="th-hex">文件 B — {fileB.name}</th>
            </tr>
          </thead>
          <tbody>
            {#each visibleRows as row (row.address)}
              {@const bytesA = splitHex(row.hexA)}
              {@const bytesB = splitHex(row.hexB)}
              <tr class:has-diff={row.hasDiff}>
                <td class="td-addr">
                  0x{row.address.toString(16).padStart(4,"0").toUpperCase()}
                  {#if row.hasDiff}<span class="diff-dot"></span>{/if}
                </td>
                <!-- A -->
                <td class="td-hex side-a">
                  {#each Array.from({ length: Math.max(bytesA.length, bytesB.length) }, (_, i) => i) as i}
                    {@const b = bytesA[i] ?? "--"}
                    {@const isDiff = row.diffMask[i]}
                    <span class="byte" class:diff-byte={isDiff} class:missing={!bytesA[i]}>{b}</span>
                    {#if i === 7 || i === 15 || i === 23}<span class="hex-gap"></span>{/if}
                  {/each}
                </td>
                <!-- B -->
                <td class="td-hex side-b">
                  {#each Array.from({ length: Math.max(bytesA.length, bytesB.length) }, (_, i) => i) as i}
                    {@const b = bytesB[i] ?? "--"}
                    {@const isDiff = row.diffMask[i]}
                    <span class="byte" class:diff-byte={isDiff} class:missing={!bytesB[i]}>{b}</span>
                    {#if i === 7 || i === 15 || i === 23}<span class="hex-gap"></span>{/if}
                  {/each}
                </td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
    {/if}
  </div>

  <!-- ── 状态栏 ── -->
  {#if stats}
    <div class="diff-statusbar">
      <span class:ok={stats.diffCount === 0} class:bad={stats.diffCount > 0}>
        {stats.diffCount === 0 ? "✓ 完全一致" : `✗ ${stats.diffCount} 行 / ${stats.totalBytes} 字节存在差异`}
      </span>
    </div>
  {/if}
</div>

<style>
  .diff-panel {
    display: flex; flex-direction: column; height: 100%;
    background: #0d0d12;
  }

  /* ── 顶部控制栏 ── */
  .diff-toolbar {
    display: flex;
    align-items: stretch;
    gap: 0;
    background: #101018;
    border-bottom: 1px solid #1e1f2c;
    flex-shrink: 0;
    min-height: 64px;
  }

  .file-slot {
    flex: 1;
    display: flex;
    flex-direction: column;
    justify-content: center;
    gap: 4px;
    padding: 10px 16px;
    border-right: 1px solid #1e1f2c;
    min-width: 0;
  }
  .slot-b { border-right: none; border-left: 1px solid #1e1f2c; }
  .file-slot.loaded { background: #0f101a; }

  .slot-label {
    font-size: 10px; font-weight: 700;
    text-transform: uppercase; letter-spacing: 0.08em;
    color: #374151;
  }
  .file-slot.loaded .slot-label { color: #6366f1; }

  .slot-name {
    font-size: 12px; color: #6b7280;
    font-family: monospace;
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
    max-width: 260px;
  }
  .file-slot.loaded .slot-name { color: #a5b4fc; }

  .slot-actions { display: flex; align-items: center; gap: 6px; flex-wrap: wrap; }

  .slot-btn {
    font-size: 11px; padding: 3px 10px;
    background: #1a1b26; border: 1px solid #2a2b36;
    color: #9ca3af; border-radius: 5px;
    cursor: pointer; transition: all 0.12s;
  }
  .slot-btn:hover:not(:disabled) { background: #22233a; color: #e2e3ea; }
  .slot-btn:disabled { opacity: 0.4; cursor: default; }
  .btn-current {
    color: #818cf8; border-color: #2a2b4a; background: #14152a;
  }
  .btn-current:hover { background: #1e1b4b !important; }

  /* 中间区域 */
  .diff-mid {
    width: 160px;
    flex-shrink: 0;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 6px;
    padding: 8px;
  }
  .diff-stats {
    display: flex; flex-direction: column; align-items: center; gap: 2px;
  }
  .stat-diff { font-size: 13px; font-weight: 700; color: #f87171; }
  .stat-bytes { font-size: 11px; color: #6b7280; }
  .stat-pct { font-size: 11px; color: #4b5563; }
  .diff-hint { font-size: 11px; color: #2a2b36; text-align: center; }

  .swap-btn {
    font-size: 16px; padding: 4px 10px;
    background: #1a1b26; border: 1px solid #2a2b36;
    color: #6b7280; border-radius: 6px;
    cursor: pointer; transition: all 0.12s;
  }
  .swap-btn:hover:not(:disabled) { background: #22233a; color: #818cf8; border-color: #3f4169; }
  .swap-btn:disabled { opacity: 0.3; cursor: default; }

  /* ── 错误栏 ── */
  .error-bar {
    background: #2d1a1a; color: #f87171;
    font-size: 12px; padding: 6px 16px;
    border-bottom: 1px solid #5c2626;
    flex-shrink: 0;
  }

  /* ── 子操作栏 ── */
  .diff-subbar {
    display: flex; align-items: center; gap: 10px;
    padding: 6px 16px;
    background: #0f0f18;
    border-bottom: 1px solid #1a1b24;
    flex-shrink: 0;
  }
  .filter-toggle {
    display: flex; align-items: center; gap: 6px;
    font-size: 12px; color: #6b7280; cursor: pointer;
  }
  .filter-count {
    font-size: 10px; background: #3b1f1f; color: #f87171;
    border-radius: 8px; padding: 1px 6px;
  }
  .copy-diff-btn {
    font-size: 11px; padding: 3px 10px;
    background: #1a1b26; border: 1px solid #2a2b36;
    color: #9ca3af; border-radius: 5px; cursor: pointer;
    transition: all 0.12s;
  }
  .copy-diff-btn:hover { background: #22233a; color: #e2e3ea; }
  .row-count { margin-left: auto; font-size: 11px; color: #374151; }

  /* ── diff 内容区 ── */
  .diff-content {
    flex: 1; overflow: hidden; display: flex; flex-direction: column;
  }

  /* 空状态 */
  .diff-empty {
    flex: 1; display: flex; flex-direction: column;
    align-items: center; justify-content: center; gap: 8px;
  }
  .diff-empty svg { width: 60px; height: 60px; }
  .diff-empty p { margin: 0; font-size: 13px; color: #374151; }
  .diff-empty .sub { font-size: 11px; color: #2a2b36; }

  /* 表格 */
  .diff-table-wrap { flex: 1; overflow: auto; }
  .diff-table { width: 100%; border-collapse: collapse; }
  .diff-table thead {
    position: sticky; top: 0; z-index: 1;
    background: #101018;
  }
  .th-addr, .th-hex {
    padding: 6px 12px;
    font-size: 10.5px; font-weight: 700;
    text-transform: uppercase; letter-spacing: 0.06em;
    color: #374151;
    border-bottom: 1px solid #1e1f2c;
    text-align: left;
  }
  .th-addr { width: 90px; }

  tr { transition: background 0.06s; }
  tr:hover { background: #0f101a; }
  tr.has-diff { background: #130f0f; }
  tr.has-diff:hover { background: #1a0f0f; }

  .td-addr {
    padding: 4px 12px;
    font-family: monospace; font-size: 12px;
    color: #6366f1;
    border-bottom: 1px solid #0f1018;
    white-space: nowrap;
    position: relative;
  }
  .diff-dot {
    display: inline-block;
    width: 5px; height: 5px;
    background: #ef4444;
    border-radius: 50%;
    margin-left: 6px;
    vertical-align: middle;
  }

  .td-hex {
    padding: 4px 12px;
    border-bottom: 1px solid #0f1018;
    font-family: monospace; font-size: 12px;
    display: flex; align-items: center; flex-wrap: wrap; gap: 2px;
  }
  .side-a { border-right: 1px solid #1a1b24; }

  .byte {
    display: inline-block; min-width: 22px;
    text-align: center; border-radius: 3px; padding: 1px 1px;
    color: #6b7280;
  }
  .byte.diff-byte {
    background: rgba(239, 68, 68, 0.18);
    color: #fca5a5;
    font-weight: 600;
  }
  .byte.missing { color: #2a2b36; font-style: italic; }
  .hex-gap { display: inline-block; width: 6px; }

  /* ── 状态栏 ── */
  .diff-statusbar {
    height: 24px;
    display: flex; align-items: center;
    padding: 0 16px;
    background: #090910;
    border-top: 1px solid #16161f;
    font-size: 11px;
    flex-shrink: 0;
  }
  .ok { color: #22c55e; }
  .bad { color: #ef4444; }
</style>
