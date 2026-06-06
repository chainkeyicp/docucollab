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
    return new Date(ms).toLocaleDateString("en-US", {
      month: "short", day: "numeric",
      hour: "2-digit", minute: "2-digit",
    });
  }

  function actionLabel(action) {
    if ("upload" in action) return "Uploaded";
    if ("download" in action) return "Downloaded";
    if ("share" in action) return "Shared";
    if ("revoke" in action) return "Revoked access";
    if ("delete" in action) return "Deleted";
    if ("summary" in action) return "AI Summary";
    return "Action";
  }

  function actionIcon(action) {
    if ("upload" in action) return "⬆";
    if ("download" in action) return "⬇";
    if ("share" in action) return "🔗";
    if ("revoke" in action) return "🚫";
    if ("delete" in action) return "🗑";
    if ("summary" in action) return "🤖";
    return "•";
  }

  function actionColor(action) {
    if ("upload" in action) return "text-green-500";
    if ("share" in action) return "text-blue-500";
    if ("revoke" in action) return "text-orange-500";
    if ("delete" in action) return "text-red-500";
    if ("summary" in action) return "text-purple-500";
    return "text-gray-500";
  }
</script>

<div class="bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 p-4">
  <h3 class="text-sm font-semibold text-gray-900 dark:text-white mb-3 flex items-center gap-2">
    <svg class="w-4 h-4 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
    </svg>
    Recent Activity
  </h3>

  {#if loading}
    <div class="flex justify-center py-6">
      <div class="w-5 h-5 border-2 border-primary-200 border-t-primary-600 rounded-full animate-spin"></div>
    </div>
  {:else if activities.length === 0}
    <p class="text-sm text-gray-400 text-center py-6">No activity yet</p>
  {:else}
    <div class="space-y-3 max-h-[400px] overflow-auto">
      {#each activities as entry}
        <div class="flex items-start gap-3 text-sm">
          <span class="{actionColor(entry.action)} text-lg leading-none mt-0.5">{actionIcon(entry.action)}</span>
          <div class="flex-1 min-w-0">
            <p class="text-gray-800 dark:text-gray-200">
              <span class="font-medium">{actionLabel(entry.action)}</span>
              <span class="text-gray-500 dark:text-gray-400 truncate"> {entry.documentName}</span>
            </p>
            {#if entry.targetUser && entry.targetUser.length > 0}
              <p class="text-xs text-gray-400 truncate">→ {entry.targetUser[0].toText()}</p>
            {/if}
          </div>
          <span class="text-xs text-gray-400 whitespace-nowrap">{formatDate(entry.timestamp)}</span>
        </div>
      {/each}
    </div>
  {/if}
</div>
