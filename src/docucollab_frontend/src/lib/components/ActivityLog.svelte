<script>
  import { getBackend } from "$lib/services/auth";
  import { onMount } from "svelte";

  let activities = [];
  let loading = true;

  onMount(loadActivities);

  async function loadActivities() {
    const backend = getBackend();
    if (!backend) return;
    loading = true;
    try {
      activities = await backend.getActivities(50);
    } catch (e) {
      console.error("Activity load error:", e);
    } finally {
      loading = false;
    }
  }

  function formatDate(nanoseconds) {
    const ms = Number(nanoseconds) / 1_000_000;
    const diff = (Date.now() - ms) / 1000;
    if (diff < 3600) return Math.max(1, Math.floor(diff / 60)) + "m ago";
    if (diff < 86400) return Math.floor(diff / 3600) + "h ago";
    if (diff < 86400 * 30) return Math.floor(diff / 86400) + "d ago";
    return new Date(ms).toLocaleDateString("en-US", { month: "short", day: "numeric" });
  }

  function actionLabel(action) {
    if ("upload" in action) return "uploaded";
    if ("download" in action) return "downloaded";
    if ("share" in action) return "shared";
    if ("revoke" in action) return "revoked access to";
    if ("delete" in action) return "deleted";
    if ("summary" in action) return "AI summary generated for";
    return "action on";
  }

  function actionMeta(action) {
    if ("upload" in action) return { tint: "#29c5f6", icon: "upload" };
    if ("share" in action) return { tint: "#7b3fe4", icon: "share" };
    if ("revoke" in action) return { tint: "#fb6a6a", icon: "x" };
    if ("delete" in action) return { tint: "#fb6a6a", icon: "trash" };
    if ("summary" in action) return { tint: "#e0359a", icon: "spark" };
    if ("download" in action) return { tint: "#3b82f6", icon: "download" };
    return { tint: "#7c7b90", icon: "activity" };
  }
</script>

<div>
  <h2 class="font-display text-base font-semibold mb-3.5 flex items-center gap-2">
    <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" style="color: var(--icp-pink);"><path d="M3 12h4l3 8 4-16 3 8h4" /></svg>
    Recent activity
  </h2>

  {#if loading}
    <div class="flex justify-center py-6">
      <div class="w-5 h-5 rounded-full anim-spin" style="border: 2px solid var(--surface); border-top-color: var(--icp-pink);"></div>
    </div>
  {:else if activities.length === 0}
    <div class="glass rounded-[var(--r-lg)] py-8 text-center text-sm" style="color: var(--text-4);">No activity yet</div>
  {:else}
    <div class="glass rounded-[var(--r-lg)] p-5">
      <div class="flex flex-col max-h-[400px] overflow-auto">
        {#each activities as entry, i}
          {@const meta = actionMeta(entry.action)}
          {@const last = i === activities.length - 1}
          <div class="flex gap-3.5">
            <div class="flex flex-col items-center">
              <div class="w-[34px] h-[34px] rounded-[10px] grid place-items-center flex-shrink-0"
                style="color: {meta.tint}; background: color-mix(in srgb, {meta.tint} 13%, transparent); border: 1px solid color-mix(in srgb, {meta.tint} 26%, transparent);">
                {#if meta.icon === "upload"}
                  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 16V4 M7 9l5-5 5 5 M5 20h14" /></svg>
                {:else if meta.icon === "share"}
                  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M18 8a3 3 0 1 0 0-6 3 3 0 0 0 0 6z M6 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z M18 22a3 3 0 1 0 0-6 3 3 0 0 0 0 6z M8.6 13.5l6.8 4 M15.4 6.5l-6.8 4" /></svg>
                {:else if meta.icon === "spark"}
                  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v3 M12 18v3 M5.6 5.6l2.1 2.1 M16.3 16.3l2.1 2.1 M3 12h3 M18 12h3 M5.6 18.4l2.1-2.1 M16.3 7.7l2.1-2.1" /></svg>
                {:else if meta.icon === "x" || meta.icon === "trash"}
                  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M6 6l12 12 M18 6L6 18" /></svg>
                {:else if meta.icon === "download"}
                  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 4v12 M7 11l5 5 5-5 M5 20h14" /></svg>
                {:else}
                  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12h4l3 8 4-16 3 8h4" /></svg>
                {/if}
              </div>
              {#if !last}
                <div class="w-[1.5px] flex-1 min-h-[14px] my-1" style="background: var(--border);"></div>
              {/if}
            </div>
            <div class="flex-1" style="padding-bottom: {last ? '0' : '18px'};">
              <div class="text-[13.5px] leading-snug" style="color: var(--text-2);">
                <span class="font-bold" style="color: var(--text);">{entry.user || "You"}</span>
                <span style="color: var(--text-3);">{actionLabel(entry.action)}</span>
                <span class="font-medium" style="color: var(--text);">{entry.documentName}</span>
              </div>
              {#if entry.targetUser && entry.targetUser.length > 0}
                <div class="text-xs mt-0.5 font-mono" style="color: var(--text-4);">to {entry.targetUser[0].toText()}</div>
              {/if}
              <div class="text-[11.5px] mt-1 font-mono" style="color: var(--text-4);">{formatDate(entry.timestamp)}</div>
            </div>
          </div>
        {/each}
      </div>
    </div>
  {/if}
</div>
