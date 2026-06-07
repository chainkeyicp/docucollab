<script>
  import { isAuthenticated, userProfile } from "$lib/stores/app";
  import { login, logout } from "$lib/services/auth";

  export let view = "landing"; // "landing" | "dashboard" | "activity"

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

  $: shortPrincipal = $userProfile?.principal
    ? (() => { const p = typeof $userProfile.principal === "string" ? $userProfile.principal : $userProfile.principal.toText(); return p.slice(0, 5) + "..." + p.slice(-7); })()
    : "";
  $: inApp = $isAuthenticated;
</script>

<nav class="sticky top-0" style="z-index: 60;">
  <div class="glass" style="border-left: none; border-right: none; border-top: none; background: color-mix(in srgb, var(--bg-0) 72%, transparent);">
    <div class="max-w-7xl mx-auto flex items-center justify-between px-6 h-16">
      <!-- Logo -->
      <a href="/" class="flex items-center gap-2.5">
        <svg width="30" height="30" viewBox="0 0 40 40" fill="none">
          <defs>
            <linearGradient id="logo-grad" x1="0" y1="0" x2="40" y2="40" gradientUnits="userSpaceOnUse">
              <stop stop-color="#7b3fe4" /><stop offset="0.5" stop-color="#e0359a" /><stop offset="1" stop-color="#29c5f6" />
            </linearGradient>
          </defs>
          <rect x="1" y="1" width="38" height="38" rx="11" fill="#0e0e1b" stroke="url(#logo-grad)" stroke-width="1.5" opacity="0.9" />
          <path d="M14 25c-3 0-5-2-5-5s2-5 5-5c2.4 0 3.8 1.6 6 4 2.2 2.4 3.6 4 6 4 3 0 5-2 5-5s-2-5-5-5"
            stroke="url(#logo-grad)" stroke-width="2.6" stroke-linecap="round" fill="none" />
        </svg>
        <span class="font-display font-bold text-xl tracking-tight" style="color: var(--text);">
          Docu<span class="grad-text">Collab</span>
        </span>
      </a>

      <!-- Center nav (authenticated) -->
      {#if inApp}
        <div class="hidden sm:flex gap-1 absolute left-1/2 -translate-x-1/2">
          <a href="/" class="flex items-center gap-2 px-4 py-2 rounded-full text-sm font-semibold transition-all"
            style="color: {view === 'dashboard' ? 'var(--text)' : 'var(--text-3)'}; background: {view === 'dashboard' ? 'var(--surface-hi)' : 'transparent'};">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" /></svg>
            Documents
          </a>
        </div>
      {/if}

      <!-- Right side -->
      <div class="flex items-center gap-3">
        {#if inApp}
          <div class="hidden sm:flex items-center gap-2.5">
            <!-- Avatar -->
            <div class="w-8 h-8 rounded-full flex items-center justify-center text-xs font-bold font-display text-white"
              style="background: linear-gradient(135deg, var(--icp-purple), color-mix(in srgb, var(--icp-purple) 55%, #000));">
              {($userProfile?.username || "U").slice(0, 2).toUpperCase()}
            </div>
            <div class="leading-tight text-right">
              <div class="text-sm font-semibold" style="color: var(--text);">{$userProfile?.username || "User"}</div>
              {#if shortPrincipal}
                <div class="text-[10.5px] font-mono" style="color: var(--text-4);">{shortPrincipal}</div>
              {/if}
            </div>
          </div>
          <button on:click={handleLogout} class="btn-ghost px-4 py-2 text-sm">
            Logout
          </button>
        {:else}
          <button on:click={handleLogin} class="btn-grad px-4 py-2.5 text-sm flex items-center gap-2">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
              <path d="M12 11a2 2 0 0 1 2 2c0 2.5-.5 4.5-1.5 6 M8.5 7.5A5 5 0 0 1 17 11c0 1-.1 2-.3 3 M5.5 11a6.5 6.5 0 0 1 3-5.5 M7 16c.8-1.2 1-2.6 1-3 M12 13c0 3-1 5.5-2.5 7.5" />
            </svg>
            <span class="hidden sm:inline">Login with Internet Identity</span>
            <span class="sm:hidden">Login</span>
          </button>
        {/if}
      </div>
    </div>
  </div>
</nav>
