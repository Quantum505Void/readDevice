<script lang="ts">
  import type { HIDDevice } from "../../shared/types";

  let {
    label,
    list,
    selected = $bindable(),
  }: {
    label: string;
    list: HIDDevice[];
    selected: HIDDevice | null;
  } = $props();
</script>

{#if list.length > 0}
  <section class="group">
    <div class="group-header">
      <span class="group-label">{label}</span>
      <span class="group-count">{list.length}</span>
    </div>

    {#each list as dev (dev.vid + dev.pid + dev.serial + dev.path + dev.usagePage)}
      <button
        class="card"
        class:active={selected?.path === dev.path && selected?.usagePage === dev.usagePage}
        class:supported={dev.supported}
        onclick={() => selected = dev}
      >
        <!-- 图标 -->
        <div class="card-icon" class:icon-supported={dev.supported} class:icon-bt={dev.isBluetooth}>
          {#if dev.isBluetooth}
            <svg viewBox="0 0 24 24" fill="currentColor">
              <path d="M17.71 7.71L12 2h-1v7.59L6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 11 14.41V22h1l5.71-5.71-4.3-4.29 4.3-4.29zM13 5.83l1.88 1.88L13 9.59V5.83zm1.88 10.46L13 18.17v-3.76l1.88 1.88z"/>
            </svg>
          {:else}
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8">
              <rect x="2" y="7" width="20" height="13" rx="2"/>
              <path d="M15 3H9l-2 4h10z"/>
            </svg>
          {/if}
        </div>

        <!-- 信息 -->
        <div class="card-body">
          <div class="card-name">{dev.product}</div>
          <div class="card-sub">
            <span class="vid-pid">{dev.vid}:{dev.pid}</span>
            {#if dev.vendor && dev.vendor !== "未知厂商"}
              <span class="dot">·</span>
              <span class="vendor">{dev.vendor}</span>
            {/if}
          </div>
        </div>

        <!-- 徽标 -->
        {#if dev.supported}
          <span class="badge badge-mode">{dev.mode === 1 ? "8系" : "9系"}</span>
        {/if}

        <!-- 选中指示线 -->
        {#if selected?.path === dev.path && selected?.usagePage === dev.usagePage}
          <span class="active-bar"></span>
        {/if}
      </button>
    {/each}
  </section>
{/if}

<style>
  .group { padding: 6px 0; }

  .group-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 6px 14px 4px;
  }
  .group-label {
    font-size: 10.5px;
    font-weight: 700;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    color: #374151;
  }
  .group-count {
    font-size: 10px;
    color: #374151;
    background: #1a1b26;
    border-radius: 8px;
    padding: 1px 6px;
    font-weight: 600;
  }

  .card {
    position: relative;
    width: 100%;
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 9px 14px 9px 12px;
    background: transparent;
    border: none;
    cursor: pointer;
    text-align: left;
    color: #9ca3af;
    transition: background 0.1s;
    border-radius: 0;
  }
  .card:hover { background: #13141e; color: #d1d5db; }
  .card.active { background: #15162a; color: #e2e3ea; }

  .card-icon {
    width: 32px;
    height: 32px;
    border-radius: 8px;
    background: #1a1b26;
    display: flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
    color: #4b5563;
    transition: background 0.1s, color 0.1s;
  }
  .card:hover .card-icon,
  .card.active .card-icon { color: #6b7280; }
  .card-icon.icon-supported { background: #16193a; color: #6366f1; }
  .card.active .card-icon.icon-supported { background: #1e1b4b; color: #818cf8; }
  .card-icon.icon-bt { background: #1a1326; color: #7c3aed; }
  .card-icon svg { width: 16px; height: 16px; }

  .card-body { flex: 1; min-width: 0; }
  .card-name {
    font-size: 13px;
    font-weight: 500;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    color: inherit;
  }
  .card.active .card-name { color: #e2e3ea; }
  .card-sub {
    display: flex;
    align-items: center;
    gap: 4px;
    margin-top: 2px;
  }
  .vid-pid {
    font-size: 10.5px;
    font-family: "JetBrains Mono", "Cascadia Code", monospace;
    color: #374151;
  }
  .dot { font-size: 10px; color: #2a2b36; }
  .vendor { font-size: 10.5px; color: #374151; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 80px; }

  .badge {
    font-size: 10px;
    font-weight: 700;
    padding: 2px 6px;
    border-radius: 5px;
    flex-shrink: 0;
  }
  .badge-mode { background: #16193a; color: #818cf8; border: 1px solid #2a2b4a; }
  .card.active .badge-mode { background: #1e1b4b; color: #a5b4fc; }

  .active-bar {
    position: absolute;
    left: 0; top: 6px; bottom: 6px;
    width: 3px;
    background: linear-gradient(180deg, #6366f1, #8b5cf6);
    border-radius: 0 2px 2px 0;
  }
</style>
