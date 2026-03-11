<script lang="ts">
  import type { HIDDevice } from "../../shared/types";

  let {
    label,
    devices,
    list,
    selected = $bindable(),
  }: {
    label: string;
    devices: HIDDevice[];
    list: HIDDevice[];
    selected: HIDDevice | null;
  } = $props();
</script>

{#if list.length > 0}
  <div class="group">
    <div class="group-label">{label} <span class="count">{list.length}</span></div>
    {#each list as dev (dev.vid + dev.pid + dev.serial + dev.path)}
      <button
        class="device-item"
        class:selected={selected?.path === dev.path}
        class:supported={dev.supported}
        onclick={() => selected = dev}
      >
        <div class="device-icon">
          {#if dev.isBluetooth}
            <svg viewBox="0 0 24 24" fill="currentColor">
              <path d="M17.71 7.71L12 2h-1v7.59L6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 11 14.41V22h1l5.71-5.71-4.3-4.29 4.3-4.29zM13 5.83l1.88 1.88L13 9.59V5.83zm1.88 10.46L13 18.17v-3.76l1.88 1.88z"/>
            </svg>
          {:else}
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
              <path d="M7 17H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2h-3"/>
              <path d="M12 17v4M8 21h8"/>
            </svg>
          {/if}
        </div>
        <div class="device-info">
          <div class="device-name">{dev.product}</div>
          <div class="device-meta">
            <span class="vid-pid">{dev.vid}:{dev.pid}</span>
            {#if dev.supported}
              <span class="badge-supported">
                {dev.mode === 1 ? "8系" : "9系"}
              </span>
            {/if}
          </div>
        </div>
      </button>
    {/each}
  </div>
{/if}

<style>
  .group {
    padding: 8px 0;
    border-bottom: 1px solid #1a1b22;
  }
  .group-label {
    font-size: 11px;
    font-weight: 600;
    color: #4b5563;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    padding: 4px 16px 6px;
    display: flex;
    align-items: center;
    gap: 6px;
  }
  .count {
    background: #1e1f26;
    color: #6b7280;
    border-radius: 10px;
    padding: 1px 6px;
    font-size: 10px;
  }
  .device-item {
    width: 100%;
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 8px 16px;
    background: transparent;
    border: none;
    cursor: pointer;
    text-align: left;
    color: #d1d5db;
    transition: background 0.12s;
    border-radius: 0;
  }
  .device-item:hover { background: #16171f; }
  .device-item.selected { background: #1a1b2e; }
  .device-icon {
    width: 28px;
    height: 28px;
    border-radius: 6px;
    background: #1e1f26;
    display: flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
    color: #6b7280;
  }
  .device-item.supported .device-icon {
    background: #1e1b4b;
    color: #818cf8;
  }
  .device-icon svg { width: 15px; height: 15px; }
  .device-info { min-width: 0; flex: 1; }
  .device-name {
    font-size: 13px;
    font-weight: 500;
    color: #e5e7eb;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .device-meta {
    display: flex;
    align-items: center;
    gap: 6px;
    margin-top: 2px;
  }
  .vid-pid {
    font-size: 11px;
    color: #4b5563;
    font-family: "JetBrains Mono", monospace;
  }
  .badge-supported {
    font-size: 10px;
    font-weight: 600;
    color: #818cf8;
    background: #1e1b4b;
    border-radius: 4px;
    padding: 1px 5px;
  }
</style>
