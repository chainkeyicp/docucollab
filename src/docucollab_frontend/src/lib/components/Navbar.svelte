<script>
  import { isAuthenticated, userProfile, darkMode } from "$lib/stores/app";
  import { login, logout } from "$lib/services/auth";

  async function handleLogin() {
    try {
      await login();
      $isAuthenticated = true;
    } catch (e) {
      console.error("Login failed:", e);
    }
  }

  async function handleLogout() {
    await logout();
    $isAuthenticated = false;
    $userProfile = null;
  }

  function toggleDark() {
    $darkMode = !$darkMode;
    document.documentElement.classList.toggle("dark", $darkMode);
  }
</script>

<nav class="bg-white dark:bg-gray-900 border-b border-gray-200 dark:border-gray-800 px-4 py-3">
  <div class="max-w-7xl mx-auto flex items-center justify-between">
    <a href="/" class="flex items-center gap-2">
      <svg class="w-8 h-8 text-primary-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
      </svg>
      <span class="text-xl font-bold text-gray-900 dark:text-white">DocuCollab</span>
    </a>

    <div class="flex items-center gap-3">
      <button on:click={toggleDark} class="p-2 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-800 text-gray-600 dark:text-gray-400">
        {#if $darkMode}
          <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 3v1m0 16v1m9-9h-1M4 12H3m15.364 6.364l-.707-.707M6.343 6.343l-.707-.707m12.728 0l-.707.707M6.343 17.657l-.707.707M16 12a4 4 0 11-8 0 4 4 0 018 0z" /></svg>
        {:else}
          <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20.354 15.354A9 9 0 018.646 3.646 9.003 9.003 0 0012 21a9.003 9.003 0 008.354-5.646z" /></svg>
        {/if}
      </button>

      {#if $isAuthenticated}
        <span class="text-sm text-gray-600 dark:text-gray-400 hidden sm:inline">
          {$userProfile?.username || "User"}
        </span>
        <button on:click={handleLogout} class="px-3 sm:px-4 py-2 text-sm font-medium text-gray-700 dark:text-gray-300 bg-gray-100 dark:bg-gray-800 rounded-lg hover:bg-gray-200 dark:hover:bg-gray-700 transition">
          Logout
        </button>
      {:else}
        <button on:click={handleLogin} class="px-3 sm:px-4 py-2 text-sm font-medium text-white bg-primary-600 rounded-lg hover:bg-primary-700 transition">
          <span class="hidden sm:inline">Login with Internet Identity</span>
          <span class="sm:hidden">Login</span>
        </button>
      {/if}
    </div>
  </div>
</nav>
