<script>
  import { notification } from "$lib/stores/app";
</script>

{#if $notification}
  <div class="fixed top-4 right-4 z-50 animate-slide-in">
    <div class="px-4 py-3 rounded-lg shadow-lg text-sm font-medium
      {$notification.type === 'error' ? 'bg-red-500 text-white' :
       $notification.type === 'success' ? 'bg-green-500 text-white' :
       'bg-primary-500 text-white'}">
      {$notification.message}
    </div>
  </div>
{/if}

<style>
  @keyframes slide-in {
    from { transform: translateX(100%); opacity: 0; }
    to { transform: translateX(0); opacity: 1; }
  }
  .animate-slide-in {
    animation: slide-in 0.3s ease-out;
  }
</style>
