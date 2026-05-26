<script lang="ts">
  import type { EEPROMRow, DiffRow } from "../../shared/types";
  import { electroview } from "../main.ts";

  let {
    currentRows,
    currentFilename,
    onDiffCount,
  }: {
    currentRows: EEPROMRow[];
    currentFilename: string;
    onDiffCount?: (n: number) => void;
  } = $props();

  // ── 文件槽 ──
  let fileA = $state<{ name: string; rows: EEPROMRow[] } | null>(null);
  let fileB = $state<{ name: string; rows: EEPROMRow[] } | null>(null);
  let loadingA = $state(false);
  let loadingB = $state(false);
  let errorMsg = $state("");
  let saveMsg = $state("");

  function useCurrentAs(side: "A" | "B") {
    if (!currentRows.length) { errorMsg = "当前没有读取数据"; return; }
    const data = { name: currentFilename || "当前读取", rows: currentRows };
    if (side === "A") fileA = data;
    else fileB = data;
    errorMsg = "";
  }

  async function loadFile(side: "A" | "B") {
    if (side === "A") loadingA = true; else loadingB = true;
    errorMsg = "";
    try {
      const res = await electroview.rpc.request.openFileForDiff({});
      if (!res.success) {
        // 用户取消选择，不算错误
        if (!res.error || res.error === "未选择文件") return;
        errorMsg = res.error;
        return;
      }
      const data = { name: res.filename, rows: res.rows };
      if (side === "A") fileA = data; else fileB = data;
    } catch (e) {
      const msg = String(e);
      // RPC 超时 = 文件选择对话框被长时间搁置或取消，不报错
      if (msg.includes("timed out") || msg.includes("timeout")) return;
      errorMsg = msg;
    }
    finally { if (side === "A") loadingA = false; else loadingB = false; }
  }

  function swap() { const t = fileA; fileA = fileB; fileB = t; }

  // ── Diff 计算 ──
  let diffRows = $derived((() => {
    if (!fileA || !fileB) return [] as DiffRow[];
    const mapA = new Map(fileA.rows.map(r => [r.address, r.hex]));
    const mapB = new Map(fileB.rows.map(r => [r.address, r.hex]));
    const allAddrs = [...new Set([...mapA.keys(), ...mapB.keys()])].sort((a, b) => a - b);
    return allAddrs.map(addr => {
      const hexA = mapA.get(addr) ?? "";
      const hexB = mapB.get(addr) ?? "";
      const bA = hexA.trim().split(/\s+/).filter(Boolean);
      const bB = hexB.trim().split(/\s+/).filter(Boolean);
      const len = Math.max(bA.length, bB.length);
      const diffMask = Array.from({ length: len }, (_, i) => (bA[i] ?? "??") !== (bB[i] ?? "??"));
      return { address: addr, hexA, hexB, diffMask, hasDiff: diffMask.some(Boolean) } as DiffRow;
    });
  })());

  let stats = $derived((() => {
    if (!diffRows.length) return null;
    const diffCount = diffRows.filter(r => r.hasDiff).length;
    const totalBytes = diffRows.reduce((s, r) => s + r.diffMask.filter(Boolean).length, 0);
    return { diffCount, totalBytes, total: diffRows.length };
  })());

  // 通知父组件 badge 数字
  $effect(() => { onDiffCount?.(stats?.diffCount ?? 0); });

  // 热力图：连续差异区间密度
  let heatmap = $derived((() => {
    if (!diffRows.length) return new Map<number, number>();
    const m = new Map<number, number>();
    // 每16行为一格，计算差异比例
    for (let i = 0; i < diffRows.length; i += 16) {
      const chunk = diffRows.slice(i, i + 16);
      const ratio = chunk.filter(r => r.hasDiff).length / chunk.length;
      for (const r of chunk) m.set(r.address, ratio);
    }
    return m;
  })());

  function heatColor(addr: number): string {
    const v = heatmap.get(addr) ?? 0;
    if (v === 0) return "";
    if (v < 0.25) return "heat-low";
    if (v < 0.6)  return "heat-mid";
    return "heat-high";
  }

  // ── 显示控制 ──
  let diffOnlyRows = $state(false);
  let showAscii = $state(true);
  let curDiffIdx = $state(0);  // 当前高亮的差异行 index（在 diffOnlyList 里）
  let tableWrap = $state<HTMLElement | null>(null);
  // tooltip
  let tooltip = $state<{ x: number; y: number; byteA: string; byteB: string } | null>(null);

  let diffOnlyList = $derived(diffRows.filter(r => r.hasDiff));
  let visibleRows  = $derived(diffOnlyRows ? diffOnlyList : diffRows);

  function prevDiff() {
    if (!diffOnlyList.length) return;
    curDiffIdx = (curDiffIdx - 1 + diffOnlyList.length) % diffOnlyList.length;
    scrollToDiff(curDiffIdx);
  }
  function nextDiff() {
    if (!diffOnlyList.length) return;
    curDiffIdx = (curDiffIdx + 1) % diffOnlyList.length;
    scrollToDiff(curDiffIdx);
  }
  function scrollToDiff(idx: number) {
    if (!tableWrap) return;
    const addr = diffOnlyList[idx]?.address;
    if (addr == null) return;
    const row = tableWrap.querySelector(`[data-addr="${addr}"]`) as HTMLElement | null;
    row?.scrollIntoView({ block: "center", behavior: "smooth" });
  }

  // ── 工具函数 ──
  function splitHex(hex: string): string[] {
    return hex.trim().split(/\s+/).filter(Boolean);
  }
  function toAscii(hex: string): string {
    return splitHex(hex).map(b => {
      const v = parseInt(b, 16);
      return v >= 0x20 && v <= 0x7e ? String.fromCharCode(v) : "·";
    }).join("");
  }

  function showTooltip(e: MouseEvent, byteA: string, byteB: string) {
    if (byteA === byteB) return;
    tooltip = { x: e.clientX, y: e.clientY - 32, byteA, byteB };
  }
  function hideTooltip() { tooltip = null; }

  // ── 导出 ──
  async function copyDiff() {
    const lines = diffOnlyList
      .map(r => `0x${r.address.toString(16).padStart(4,"0").toUpperCase()}: A=[${r.hexA}] B=[${r.hexB}]`)
      .join("\n");
    await navigator.clipboard.writeText(lines);
  }

  async function saveDiffHtml() {
    if (!fileA || !fileB || !stats) return;
    saveMsg = "保存中…";
    const rows = diffOnlyList;
    const html = `<!DOCTYPE html>
<html lang="zh"><head><meta charset="utf-8">
<title>EEPROM Diff — ${fileA.name} vs ${fileB.name}</title>
<style>
body{background:#0d0d12;color:#e2e3ea;font-family:monospace;padding:24px}
h1{font-size:16px;color:#818cf8;margin-bottom:4px}
.meta{font-size:12px;color:#4b5563;margin-bottom:20px}
table{border-collapse:collapse;width:100%}
th{padding:6px 12px;font-size:11px;text-transform:uppercase;letter-spacing:.06em;color:#374151;border-bottom:1px solid #1e1f2c;text-align:left}
td{padding:4px 12px;font-size:12px;border-bottom:1px solid #0f1018}
.addr{color:#6366f1}.diff{background:rgba(239,68,68,.18);color:#fca5a5;font-weight:600;border-radius:3px;padding:0 2px}
.ok{color:#22c55e}
</style></head><body>
<h1>EEPROM Diff Report</h1>
<div class="meta">A: ${fileA.name} &nbsp;|&nbsp; B: ${fileB.name} &nbsp;|&nbsp; ${stats.diffCount} 行 ${stats.totalBytes} 字节差异 &nbsp;|&nbsp; ${new Date().toLocaleString()}</div>
${stats.diffCount === 0 ? '<p class="ok">✓ 两个文件完全一致</p>' : `
<table><thead><tr><th>地址</th><th>文件 A</th><th>文件 B</th></tr></thead><tbody>
${rows.map(r => {
  const bA = splitHex(r.hexA);
  const bB = splitHex(r.hexB);
  const len = Math.max(bA.length, bB.length);
  const renderBytes = (bytes: string[], other: string[]) =>
    Array.from({length:len},(_,i)=>{
      const b = bytes[i] ?? "--";
      const isDiff = r.diffMask[i];
      return isDiff ? `<span class="diff">${b}</span>` : b;
    }).join(" ");
  return `<tr><td class="addr">0x${r.address.toString(16).padStart(4,"0").toUpperCase()}</td><td>${renderBytes(bA,bB)}</td><td>${renderBytes(bB,bA)}</td></tr>`;
}).join("")}
</tbody></table>`}
</body></html>`;
    const filename = `diff_${Date.now()}.html`;
    const res = await electroview.rpc.request.saveDiffReport({ content: html, filename });
    saveMsg = res.success ? `✓ 已保存到 ${res.savedPath}` : `✗ ${res.error}`;
    setTimeout(() => saveMsg = "", 4000);
  }
</script>

<!-- ── tooltip ── -->
{#if tooltip}
  <div class="byte-tooltip" style="left:{tooltip.x}px;top:{tooltip.y}px">
    <span class="tt-a">A: {tooltip.byteA}</span>
    <span class="tt-arrow">→</span>
    <span class="tt-b">B: {tooltip.byteB}</span>
  </div>
{/if}

<div class="diff-panel">
  <!-- ── 头部：统计卡片 ── -->
  {#if stats}
    <div class="stats-bar">
      <div class="stat-card" class:has-diff={stats.diffCount > 0} class:no-diff={stats.diffCount === 0}>
        <div class="sc-value">{stats.diffCount}</div>
        <div class="sc-label">行差异</div>
      </div>
      <div class="stat-card" class:has-diff={stats.totalBytes > 0} class:no-diff={stats.totalBytes === 0}>
        <div class="sc-value">{stats.totalBytes}</div>
        <div class="sc-label">字节不同</div>
      </div>
      <div class="stat-card" class:has-diff={stats.diffCount > 0} class:no-diff={stats.diffCount === 0}>
        <div class="sc-value">{((stats.diffCount / stats.total) * 100).toFixed(1)}%</div>
        <div class="sc-label">修改率</div>
      </div>
      <div class="stat-card">
        <div class="sc-value">{stats.total}</div>
        <div class="sc-label">总行数</div>
      </div>
    </div>
  {/if}

  <!-- ── 顶部控制栏 ── -->
  <div class="diff-toolbar">
    <!-- 文件 A -->
    <div class="file-slot" class:loaded={!!fileA}>
      <div class="slot-label">A</div>
      <div class="slot-body">
        <div class="slot-name" title={fileA?.name}>{fileA?.name ?? "未选择文件"}</div>
        <div class="slot-actions">
          {#if currentRows.length > 0}
            <button class="slot-btn btn-cur" onclick={() => useCurrentAs("A")}>↑ 当前数据</button>
          {/if}
          <button class="slot-btn" onclick={() => loadFile("A")} disabled={loadingA}>
            {loadingA ? "…" : "📂 打开"}
          </button>
          {#if fileA}<button class="slot-btn btn-clear" onclick={() => fileA = null}>✕</button>{/if}
        </div>
      </div>
    </div>

    <!-- 中间 -->
    <div class="diff-mid">
      <button class="swap-btn" onclick={swap} title="交换 A/B" disabled={!fileA && !fileB}>⇌</button>
      {#if !stats}<div class="hint-text">选择两个文件</div>{/if}
    </div>

    <!-- 文件 B -->
    <div class="file-slot slot-b" class:loaded={!!fileB}>
      <div class="slot-label">B</div>
      <div class="slot-body">
        <div class="slot-name" title={fileB?.name}>{fileB?.name ?? "未选择文件"}</div>
        <div class="slot-actions">
          {#if currentRows.length > 0}
            <button class="slot-btn btn-cur" onclick={() => useCurrentAs("B")}>↑ 当前数据</button>
          {/if}
          <button class="slot-btn" onclick={() => loadFile("B")} disabled={loadingB}>
            {loadingB ? "…" : "📂 打开"}
          </button>
          {#if fileB}<button class="slot-btn btn-clear" onclick={() => fileB = null}>✕</button>{/if}
        </div>
      </div>
    </div>
  </div>

  {#if errorMsg}
    <div class="msg-bar err">{errorMsg} <button onclick={() => errorMsg = ""}>✕</button></div>
  {/if}
  {#if saveMsg}
    <div class="msg-bar" class:ok={saveMsg.startsWith("✓")} class:err={saveMsg.startsWith("✗")}>
      {saveMsg}
    </div>
  {/if}

  <!-- ── 子操作栏 ── -->
  {#if diffRows.length > 0}
    <div class="diff-subbar">
      <!-- 过滤 -->
      <label class="toggle-label">
        <input type="checkbox" bind:checked={diffOnlyRows} />
        只看差异
        {#if stats && stats.diffCount > 0}
          <span class="badge-red">{stats.diffCount}</span>
        {/if}
      </label>
      <!-- ASCII -->
      <label class="toggle-label">
        <input type="checkbox" bind:checked={showAscii} />
        ASCII
      </label>
      <!-- 导航 -->
      {#if diffOnlyList.length > 0}
        <div class="diff-nav">
          <button onclick={prevDiff} title="上一个差异 (↑)">↑</button>
          <span>{curDiffIdx + 1} / {diffOnlyList.length}</span>
          <button onclick={nextDiff} title="下一个差异 (↓)">↓</button>
        </div>
      {/if}
      <span class="row-count">{visibleRows.length} 行</span>
      <div class="subbar-right">
        {#if stats && stats.diffCount > 0}
          <button class="tool-btn" onclick={copyDiff} title="复制差异到剪贴板">📋 复制</button>
          <button class="tool-btn" onclick={saveDiffHtml} title="导出 HTML 报告">💾 报告</button>
        {/if}
      </div>
    </div>
  {/if}

  <!-- ── 内容区 ── -->
  <div class="diff-content">
    {#if !fileA || !fileB}
      <div class="diff-empty">
        <svg viewBox="0 0 80 64" fill="none">
          <rect x="2" y="8" width="30" height="48" rx="3" stroke="#1e1f2c" stroke-width="1.5"/>
          <rect x="48" y="8" width="30" height="48" rx="3" stroke="#1e1f2c" stroke-width="1.5"/>
          <path d="M10 22h14M10 30h14M10 38h10" stroke="#2a2b36" stroke-width="1.5" stroke-linecap="round"/>
          <path d="M56 22h14M56 30h14M56 38h10" stroke="#2a2b36" stroke-width="1.5" stroke-linecap="round"/>
          <circle cx="40" cy="32" r="6" stroke="#2a2b36" stroke-width="1.5"/>
          <path d="M37 32h6M40 29v6" stroke="#2a2b36" stroke-width="1.5" stroke-linecap="round"/>
        </svg>
        <p>选择 A 和 B 两个 .hid 文件开始对比</p>
        <p class="sub">
          {#if currentRows.length > 0}当前有读取数据，可直接用作 A 或 B{:else}支持从文件加载，或读取设备后使用当前数据{/if}
        </p>
        {#if currentRows.length > 0}
          <div class="empty-btns">
            <button class="slot-btn btn-cur" onclick={() => useCurrentAs("A")}>↑ 用作 A</button>
            <button class="slot-btn btn-cur" onclick={() => useCurrentAs("B")}>↑ 用作 B</button>
          </div>
        {/if}
      </div>
    {:else if diffRows.length === 0}
      <div class="diff-empty">
        <svg viewBox="0 0 64 64" fill="none">
          <circle cx="32" cy="32" r="24" stroke="#22c55e" stroke-width="2"/>
          <polyline points="20 32 28 40 44 24" stroke="#22c55e" stroke-width="2.5" stroke-linecap="round"/>
        </svg>
        <p class="ok-text">两个文件完全一致</p>
      </div>
    {:else}
      <div class="diff-table-wrap" bind:this={tableWrap}>
        <table class="diff-table">
          <thead>
            <tr>
              <th class="th-heat"></th>
              <th class="th-addr">地址</th>
              <th class="th-hex">A — {fileA.name}</th>
              <th class="th-hex th-b">B — {fileB.name}</th>
              {#if showAscii}<th class="th-ascii">ASCII A</th><th class="th-ascii">ASCII B</th>{/if}
            </tr>
          </thead>
          <tbody>
            {#each visibleRows as row (row.address)}
              {@const bA = splitHex(row.hexA)}
              {@const bB = splitHex(row.hexB)}
              {@const len = Math.max(bA.length, bB.length)}
              <tr class:has-diff={row.hasDiff} data-addr={row.address}>
                <!-- 热力条 -->
                <td class="td-heat">
                  <div class="heat-bar {heatColor(row.address)}" title={row.hasDiff ? "差异" : ""}></div>
                </td>
                <td class="td-addr {heatColor(row.address)}">
                  0x{row.address.toString(16).padStart(4,"0").toUpperCase()}
                </td>
                <!-- A -->
                <td class="td-hex">
                  {#each Array.from({length:len},(_,i)=>i) as i}
                    {@const b = bA[i] ?? "--"}
                    {@const isDiff = row.diffMask[i]}
                    <!-- svelte-ignore a11y_no_static_element_interactions -->
                    <span
                      class="byte"
                      class:diff-a={isDiff}
                      class:miss={!bA[i]}
                      onmouseenter={isDiff ? (e) => showTooltip(e as MouseEvent, bA[i] ?? "--", bB[i] ?? "--") : undefined}
                      onmouseleave={hideTooltip}
                    >{b}</span>
                    {#if i === 7 || i === 15 || i === 23}<span class="hex-gap"></span>{/if}
                  {/each}
                </td>
                <!-- B -->
                <td class="td-hex td-hex-b">
                  {#each Array.from({length:len},(_,i)=>i) as i}
                    {@const b = bB[i] ?? "--"}
                    {@const isDiff = row.diffMask[i]}
                    <!-- svelte-ignore a11y_no_static_element_interactions -->
                    <span
                      class="byte"
                      class:diff-b={isDiff}
                      class:miss={!bB[i]}
                      onmouseenter={isDiff ? (e) => showTooltip(e as MouseEvent, bA[i] ?? "--", bB[i] ?? "--") : undefined}
                      onmouseleave={hideTooltip}
                    >{b}</span>
                    {#if i === 7 || i === 15 || i === 23}<span class="hex-gap"></span>{/if}
                  {/each}
                </td>
                {#if showAscii}
                  <td class="td-ascii">{toAscii(row.hexA)}</td>
                  <td class="td-ascii td-ascii-b">{toAscii(row.hexB)}</td>
                {/if}
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
    {/if}
  </div>

  <!-- ── 状态栏 ── -->
  <div class="diff-statusbar">
    {#if stats}
      <span class:ok={stats.diffCount === 0} class:bad={stats.diffCount > 0}>
        {stats.diffCount === 0 ? "✓ 完全一致" : `✗ ${stats.diffCount} 行 · ${stats.totalBytes} 字节差异`}
      </span>
      {#if fileA && fileB}
        <span class="sb-files">{fileA.name} → {fileB.name}</span>
      {/if}
    {:else}
      <span class="sb-hint">选择 A、B 文件后开始对比</span>
    {/if}
  </div>
</div>

<style>
  /* ── tooltip ── */
  .byte-tooltip {
    position: fixed; z-index: 9999;
    background: #1a1b26; border: 1px solid #3f4169;
    border-radius: 6px; padding: 5px 10px;
    display: flex; align-items: center; gap: 6px;
    font-family: monospace; font-size: 12px;
    pointer-events: none;
    box-shadow: 0 4px 20px rgba(0,0,0,.5);
  }
  .tt-a { color: #fca5a5; }
  .tt-b { color: #86efac; }
  .tt-arrow { color: #4b5563; }

  /* ── panel ── */
  .diff-panel {
    display: flex; flex-direction: column; height: 100%;
    background: #0d0d12; overflow: hidden;
  }

  /* ── 统计卡片 ── */
  .stats-bar {
    display: flex; gap: 1px;
    background: #1e1f2c;
    border-bottom: 1px solid #1e1f2c;
    flex-shrink: 0;
  }
  .stat-card {
    flex: 1; display: flex; flex-direction: column;
    align-items: center; justify-content: center;
    padding: 8px 0;
    background: #101018;
    gap: 2px;
  }
  .stat-card.has-diff { background: #130f0f; }
  .stat-card.no-diff  { background: #0d1510; }
  .sc-value {
    font-size: 18px; font-weight: 700;
    font-variant-numeric: tabular-nums;
    color: #4b5563;
  }
  .stat-card.has-diff .sc-value { color: #f87171; }
  .stat-card.no-diff  .sc-value { color: #22c55e; }
  .sc-label { font-size: 10px; color: #2d3748; text-transform: uppercase; letter-spacing: .06em; }

  /* ── 控制栏 ── */
  .diff-toolbar {
    display: flex; align-items: stretch;
    background: #101018;
    border-bottom: 1px solid #1e1f2c;
    flex-shrink: 0;
    min-height: 58px;
  }
  .file-slot {
    flex: 1; display: flex; align-items: center; gap: 10px;
    padding: 10px 14px;
    border-right: 1px solid #1e1f2c;
    min-width: 0;
    transition: background .12s;
  }
  .slot-b { border-right: none; border-left: 1px solid #1e1f2c; }
  .file-slot.loaded { background: #0f101a; }

  .slot-label {
    font-size: 18px; font-weight: 800;
    color: #1e1f2c;
    flex-shrink: 0; width: 20px; text-align: center;
    font-family: monospace;
  }
  .file-slot.loaded .slot-label { color: #4f46e5; }

  .slot-body { display: flex; flex-direction: column; gap: 4px; min-width: 0; flex: 1; }
  .slot-name {
    font-size: 12px; font-family: monospace;
    color: #4b5563;
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
  }
  .file-slot.loaded .slot-name { color: #a5b4fc; }
  .slot-actions { display: flex; align-items: center; gap: 5px; flex-wrap: wrap; }

  .slot-btn {
    font-size: 11px; padding: 3px 9px;
    background: #1a1b26; border: 1px solid #2a2b36;
    color: #6b7280; border-radius: 5px; cursor: pointer;
    transition: all .1s;
  }
  .slot-btn:hover:not(:disabled) { background: #22233a; color: #e2e3ea; }
  .slot-btn:disabled { opacity: .4; cursor: default; }
  .btn-cur { color: #818cf8; border-color: #2a2b4a; background: #13142a; }
  .btn-cur:hover:not(:disabled) { background: #1e1b4b !important; }
  .btn-clear { color: #6b7280; border-color: #2a2b36; padding: 3px 7px; }
  .btn-clear:hover:not(:disabled) { color: #f87171 !important; border-color: #5c2626 !important; }

  .diff-mid {
    width: 60px; flex-shrink: 0;
    display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 4px;
  }
  .swap-btn {
    font-size: 16px; padding: 5px 8px;
    background: #1a1b26; border: 1px solid #2a2b36;
    color: #374151; border-radius: 6px; cursor: pointer; transition: all .1s;
  }
  .swap-btn:hover:not(:disabled) { background: #22233a; color: #818cf8; border-color: #4f46e5; }
  .swap-btn:disabled { opacity: .25; cursor: default; }
  .hint-text { font-size: 9px; color: #1e1f2c; text-align: center; }

  /* ── 消息栏 ── */
  .msg-bar {
    font-size: 12px; padding: 5px 14px;
    background: #1a1b26; color: #6b7280;
    border-bottom: 1px solid #2a2b36;
    display: flex; align-items: center; justify-content: space-between;
    flex-shrink: 0;
  }
  .msg-bar button { background: none; border: none; color: #4b5563; cursor: pointer; font-size: 12px; }
  .msg-bar.err { background: #2d1a1a; color: #f87171; border-color: #5c2626; }
  .msg-bar.ok  { background: #0d1f14; color: #22c55e; border-color: #166534; }

  /* ── 子操作栏 ── */
  .diff-subbar {
    display: flex; align-items: center; gap: 10px;
    padding: 5px 14px;
    background: #0f0f18; border-bottom: 1px solid #1a1b24;
    flex-shrink: 0; flex-wrap: wrap;
  }
  .toggle-label {
    display: flex; align-items: center; gap: 5px;
    font-size: 12px; color: #4b5563; cursor: pointer;
    user-select: none;
  }
  .toggle-label:hover { color: #9ca3af; }
  .badge-red {
    font-size: 10px; background: #3b1f1f; color: #f87171;
    border-radius: 8px; padding: 1px 6px;
  }
  .diff-nav {
    display: flex; align-items: center; gap: 4px;
    font-size: 11px; color: #4b5563;
  }
  .diff-nav button {
    background: #1a1b26; border: 1px solid #2a2b36;
    color: #6b7280; border-radius: 4px;
    padding: 1px 6px; cursor: pointer; font-size: 11px;
    transition: all .1s;
  }
  .diff-nav button:hover { background: #22233a; color: #e2e3ea; }
  .row-count { font-size: 11px; color: #2a2b36; }
  .subbar-right { margin-left: auto; display: flex; gap: 6px; }
  .tool-btn {
    font-size: 11px; padding: 3px 10px;
    background: #1a1b26; border: 1px solid #2a2b36;
    color: #6b7280; border-radius: 5px; cursor: pointer; transition: all .1s;
  }
  .tool-btn:hover { background: #22233a; color: #e2e3ea; }

  /* ── 内容区 ── */
  .diff-content { flex: 1; overflow: hidden; display: flex; flex-direction: column; }

  /* 空状态 */
  .diff-empty {
    flex: 1; display: flex; flex-direction: column;
    align-items: center; justify-content: center; gap: 10px;
  }
  .diff-empty svg { width: 80px; height: 64px; }
  .diff-empty p { margin: 0; font-size: 13px; color: #2a2b36; }
  .diff-empty .sub { font-size: 11px; color: #1e1f2c; }
  .empty-btns { display: flex; gap: 8px; margin-top: 4px; }
  .ok-text { color: #22c55e !important; font-size: 14px !important; }

  /* 表格 */
  .diff-table-wrap {
    flex: 1; overflow: auto;
    /* 自定义滚动条 */
    scrollbar-width: thin;
    scrollbar-color: #1e1f2c #0d0d12;
  }
  .diff-table-wrap::-webkit-scrollbar { width: 6px; height: 6px; }
  .diff-table-wrap::-webkit-scrollbar-track { background: #0d0d12; }
  .diff-table-wrap::-webkit-scrollbar-thumb { background: #1e1f2c; border-radius: 3px; }
  .diff-table-wrap::-webkit-scrollbar-thumb:hover { background: #2a2b36; }

  .diff-table { width: 100%; border-collapse: collapse; min-width: 800px; }
  .diff-table thead {
    position: sticky; top: 0; z-index: 2;
    background: #0d0d12;
  }
  th {
    padding: 6px 10px;
    font-size: 10px; font-weight: 700;
    text-transform: uppercase; letter-spacing: .06em;
    color: #2a2b36; border-bottom: 1px solid #1a1b24;
    text-align: left; white-space: nowrap;
  }
  .th-heat { width: 4px; padding: 0; }
  .th-addr { width: 80px; }
  .th-b { border-left: 1px solid #1a1b24; }
  .th-ascii { width: 160px; color: #1e1f2c; }

  tr { transition: background .06s; }
  tr:hover { background: #0f101a; }
  tr.has-diff { background: #110d0d; }
  tr.has-diff:hover { background: #180d0d; }

  /* 热力条 */
  .td-heat { padding: 0; width: 4px; }
  .heat-bar { width: 4px; height: 100%; min-height: 22px; }
  .heat-low  { background: rgba(251,146,60,.35); }
  .heat-mid  { background: rgba(239,68,68,.5); }
  .heat-high { background: rgba(239,68,68,.85); }

  .td-addr {
    padding: 4px 10px;
    font-family: monospace; font-size: 12px;
    color: #3f4169;
    border-bottom: 1px solid #0f1018;
    white-space: nowrap;
  }
  .td-addr.heat-low  { color: #b45309; }
  .td-addr.heat-mid  { color: #ef4444; }
  .td-addr.heat-high { color: #fca5a5; }

  .td-hex {
    padding: 4px 10px;
    border-bottom: 1px solid #0f1018;
    font-family: monospace; font-size: 12px;
    display: flex; align-items: center; flex-wrap: nowrap; gap: 2px;
    white-space: nowrap;
  }
  .td-hex-b { border-left: 1px solid #1a1b24; }

  .byte {
    display: inline-block; min-width: 20px;
    text-align: center; border-radius: 3px; padding: 0 1px;
    color: #374151;
  }
  .byte.diff-a {
    background: rgba(239,68,68,.2);
    color: #fca5a5; font-weight: 600;
    cursor: help;
  }
  .byte.diff-b {
    background: rgba(134,239,172,.15);
    color: #86efac; font-weight: 600;
    cursor: help;
  }
  .byte.miss { color: #1e1f2c; font-style: italic; }
  .hex-gap { display: inline-block; width: 5px; }

  .td-ascii {
    padding: 4px 10px;
    font-family: monospace; font-size: 11px;
    color: #2d3748; letter-spacing: .04em;
    border-bottom: 1px solid #0f1018;
    white-space: nowrap;
    border-left: 1px solid #1a1b24;
  }
  .td-ascii-b { border-left: 1px solid #1a1b24; }
  tr:hover .td-ascii { color: #4a5568; }

  /* ── 状态栏 ── */
  .diff-statusbar {
    height: 24px; display: flex; align-items: center; justify-content: space-between;
    padding: 0 14px;
    background: #090910; border-top: 1px solid #16161f;
    font-size: 11px; flex-shrink: 0;
    scrollbar-width: none;
  }
  .ok { color: #22c55e; }
  .bad { color: #ef4444; }
  .sb-files { color: #2d3748; font-family: monospace; font-size: 10px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 50%; }
  .sb-hint { color: #1e1f2c; }
</style>
