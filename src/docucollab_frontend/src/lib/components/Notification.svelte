<script>
  import { notification } from "$lib/stores/app";

  $: tint = $notification?.type === "success" ? "var(--green)"
    : $notification?.type === "error" ? "var(--red)"
    : $notification?.type === "warning" ? "var(--amber)"
    : "var(--icp-cyan)";
</script>

{#if $notification}
  <div class="fixed bottom-6 left-1/2 -translate-x-1/2 scale-in" style="z-index: 200;">
    <div class="glass flex items-center gap-3 px-4 py-3 max-w-[460px]"
      style="border-radius: 14px; border-color: color-mix(in srgb, {tint} 36%, transparent); box-shadow: 0 16px 50px -12px rgba(0,0,0,0.6);">
      <span class="grid place-items-center flex-shrink-0" style="color: {tint};">
        {#if $notification.type === "success"}
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18z M8.5 12l2.5 2.5 4.5-5" /></svg>
        {:else if $notification.type === "error"}
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M6 6l12 12 M18 6L6 18" /></svg>
        {:else}
          <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor" stroke="none"><path d="M13 2L4.5 13.5H11l-1 8.5L19.5 10H13z" /></svg>
        {/if}
      </span>
      <span class="text-sm font-medium" style="color: var(--text);">{$notification.message}</span>
    </div>
  </div>
{/if}
