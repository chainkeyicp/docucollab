<script>
  import "../app.css";
  import Navbar from "$lib/components/Navbar.svelte";
  import Notification from "$lib/components/Notification.svelte";
  import { onMount } from "svelte";
  import { initAuth } from "$lib/services/auth";
  import { isAuthenticated } from "$lib/stores/app";

  onMount(async () => {
    const authClient = await initAuth();
    $isAuthenticated = await authClient.isAuthenticated();
  });
</script>

<div class="min-h-screen flex flex-col">
  <Navbar />
  <main class="flex-1">
    <slot />
  </main>
  <Notification />
</div>
