<script>
  import { isAuthenticated, documents, sharedDocuments, userProfile, isLoading, notify } from "$lib/stores/app";
  import { getBackend, getPrincipal } from "$lib/services/auth";
  import { generateKeyPair, exportPublicKey, savePrivateKey, hasPrivateKey, exportRecoveryKey, importRecoveryKeyInMemory, persistRecoveryKey, validateKeyPair, getDocumentKey, importPublicKey, encryptKeyForRecipient } from "$lib/services/crypto";
  import FileUpload from "$lib/components/FileUpload.svelte";
  import DocumentList from "$lib/components/DocumentList.svelte";
  import DocumentView from "$lib/components/DocumentView.svelte";
  import ActivityLog from "$lib/components/ActivityLog.svelte";
  import ShareModal from "$lib/components/ShareModal.svelte";

  let activeTab = "my-docs";
  let viewingDoc = null;
  let showRegister = false;
  let username = "";
  let stats = { totalDocuments: 0, totalUsers: 0 };
  let batchShareIds = [];
  let showBatchShare = false;
  let batchShareIndex = 0;
  let hasLocalPrivateKey = false;
  let recoveryFileInput;
  let registering = false;

  import { onMount } from "svelte";

  onMount(loadStats);

  $: if ($isAuthenticated) {
    checkProfile();
  }

  async function loadStats() {
    try {
      const backend = getBackend();
      if (backend) {
        stats = await backend.getStats();
      }
    } catch (e) {}
  }

  async function checkProfile() {
    const backend = getBackend();
    if (!backend) return;
    try {
      const profile = await backend.getMyProfile();
      if (profile && profile.length > 0) {
        $userProfile = profile[0];
        hasLocalPrivateKey = await hasPrivateKey();
        loadDocuments();
      } else {
        showRegister = true;
      }
    } catch (e) {
      console.error("Profile check error:", e);
    }
  }

  async function registerUser() {
    if (!username.trim() || registering) return;
    const backend = getBackend();
    if (!backend) return;
    registering = true;
    try {
      const keyPair = await generateKeyPair();
      const publicKeyBytes = await exportPublicKey(keyPair.publicKey);

      const result = await backend.registerUser(username.trim(), publicKeyBytes);
      if ("ok" in result) {
        // Persist private key only after backend confirms registration
        await savePrivateKey(keyPair.privateKey);
        $userProfile = result.ok;
        hasLocalPrivateKey = true;
        showRegister = false;
        notify("Welcome to DocuCollab! Your encryption keys have been generated.", "success");
        loadDocuments();
      } else {
        notify(result.err, "error");
      }
    } catch (e) {
      notify("Registration failed: " + e.message, "error");
    } finally {
      registering = false;
    }
  }

  async function exportRecovery() {
    try {
      const keyBytes = await exportRecoveryKey();
      const principal = getPrincipal()?.toText() || "principal";
      const blob = new Blob([keyBytes], { type: "application/octet-stream" });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `docucollab-recovery-${principal.slice(0, 8)}.key`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
      notify("Recovery key exported.", "success");
    } catch (e) {
      notify("Recovery key export failed: " + e.message, "error");
    }
  }

  async function importRecovery(e) {
    const file = e.target.files?.[0];
    if (!file) return;
    try {
      const keyBytes = new Uint8Array(await file.arrayBuffer());

      // Import into memory only — do NOT persist yet
      const importedKey = await importRecoveryKeyInMemory(keyBytes);

      // Validate imported key matches the backend public key
      if ($userProfile && $userProfile.publicKey) {
        const pubKeyBytes = new Uint8Array($userProfile.publicKey);
        const valid = await validateKeyPair(pubKeyBytes, importedKey);
        if (!valid) {
          notify("Recovery key does not match your registered public key.", "error");
          return;
        }
      }

      // Validation passed — now persist
      await persistRecoveryKey(keyBytes);
      hasLocalPrivateKey = await hasPrivateKey();
      notify("Recovery key imported and validated.", "success");
    } catch (err) {
      notify("Recovery key import failed: " + err.message, "error");
    } finally {
      e.target.value = "";
    }
  }

  async function loadDocuments() {
    const backend = getBackend();
    if (!backend) return;
    $isLoading = true;
    try {
      $documents = await backend.getMyDocuments();
      const shared = await backend.getSharedWithMe();
      $sharedDocuments = shared.map(s => s.meta);
      stats = await backend.getStats();
    } catch (e) {
      console.error("Load error:", e);
    } finally {
      $isLoading = false;
    }
  }

  let backfilling = false;

  async function backfillOwnerKeys() {
    const backend = getBackend();
    if (!backend || !$userProfile || !$userProfile.publicKey) return;
    backfilling = true;
    let backfilled = 0, alreadyHad = 0, skippedNoKey = 0, failed = 0;
    try {
      const ownerPubKey = await importPublicKey(new Uint8Array($userProfile.publicKey));
      for (const doc of $documents) {
        const localKey = await getDocumentKey(Number(doc.id));
        if (!localKey) { skippedNoKey++; continue; }
        try {
          const existing = await backend.getOwnerWrappedKey(doc.id);
          if ("ok" in existing) { alreadyHad++; continue; }
        } catch {}
        try {
          const wrapped = await encryptKeyForRecipient(localKey, ownerPubKey);
          const r = await backend.setOwnerWrappedKey(doc.id, wrapped);
          if ("ok" in r) backfilled++; else failed++;
        } catch { failed++; }
      }
      const parts = [];
      if (backfilled > 0) parts.push(`${backfilled} backfilled`);
      if (alreadyHad > 0) parts.push(`${alreadyHad} already had keys`);
      if (skippedNoKey > 0) parts.push(`${skippedNoKey} skipped (no local key)`);
      if (failed > 0) parts.push(`${failed} failed`);
      const level = failed > 0 || skippedNoKey > 0 ? "warning" : "success";
      notify(`Recovery keys: ${parts.join(", ")}.`, level);
    } catch (e) {
      notify("Backfill failed: " + e.message, "error");
    } finally {
      backfilling = false;
    }
  }

  function copyText(text) {
    try {
      const ta = document.createElement("textarea");
      ta.value = text;
      ta.style.position = "fixed";
      ta.style.opacity = "0";
      document.body.appendChild(ta);
      ta.select();
      document.execCommand("copy");
      document.body.removeChild(ta);
      notify("Principal copied!", "success");
    } catch {
      notify("Copy failed", "error");
    }
  }

  function handleView(e) {
    viewingDoc = e.detail;
  }

  function handleBatchShare(e) {
    batchShareIds = e.detail;
    if (batchShareIds.length > 0) {
      batchShareIndex = 0;
      showBatchShare = true;
    }
  }

  function onBatchShared() {
    batchShareIndex++;
    if (batchShareIndex >= batchShareIds.length) {
      showBatchShare = false;
      batchShareIds = [];
      notify(`${batchShareIndex} documents shared!`, "success");
      loadDocuments();
    }
  }

  $: batchShareDoc = showBatchShare && batchShareIndex < batchShareIds.length
    ? $documents.find(d => Number(d.id) === batchShareIds[batchShareIndex])
    : null;

  $: storageBytes = $documents.reduce((sum, d) => sum + Number(d.size), 0);
  $: storagePct = Math.min(100, storageBytes / (50 * 1024 * 1024) * 100);
  $: storageLabel = storageBytes < 1024 ? storageBytes + " B"
    : storageBytes < 1048576 ? (storageBytes / 1024).toFixed(1) + " KB"
    : (storageBytes / 1048576).toFixed(1) + " MB";
</script>

{#if !$isAuthenticated}
  <!-- ====== LANDING PAGE ====== -->
  <div>
    <!-- HERO -->
    <section class="max-w-[1180px] mx-auto px-7 pt-[72px] pb-10">
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-14 items-center">
        <div class="rise">
          <!-- badge -->
          <span class="inline-flex items-center gap-1.5 px-3.5 py-1.5 rounded-full text-xs font-semibold mb-6"
            style="color: var(--icp-cyan); background: color-mix(in srgb, var(--icp-cyan) 14%, transparent); border: 1px solid color-mix(in srgb, var(--icp-cyan) 30%, transparent);">
            <span class="w-1.5 h-1.5 rounded-full" style="background: var(--green); box-shadow: 0 0 0 3px color-mix(in srgb, var(--green) 25%, transparent);"></span>
            Built entirely on the Internet Computer
          </span>

          <h1 class="font-display font-bold leading-[1.02] mb-6" style="font-size: clamp(32px, 5vw, 58px); letter-spacing: -0.035em;">
            Your documents,<br />
            <span class="grad-text">encrypted on-chain</span><br />
            — not held by a company.
          </h1>

          <p class="text-lg leading-relaxed mb-8 max-w-[520px]" style="color: var(--text-2);">
            DocuCollab is encrypted document collaboration with on-chain AI and canister-computed integrity. No application server, no external database, no document custodian — just your principal and the Internet Computer.
          </p>

          <div class="flex flex-wrap gap-3.5 items-center mb-10">
            <button on:click={() => { import('$lib/services/auth').then(m => m.login().then(() => { $isAuthenticated = true; })); }}
              class="btn-grad px-6 py-3.5 text-[15.5px] flex items-center gap-2.5">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                <path d="M12 11a2 2 0 0 1 2 2c0 2.5-.5 4.5-1.5 6 M8.5 7.5A5 5 0 0 1 17 11c0 1-.1 2-.3 3 M5.5 11a6.5 6.5 0 0 1 3-5.5 M7 16c.8-1.2 1-2.6 1-3 M12 13c0 3-1 5.5-2.5 7.5" />
              </svg>
              Login with Internet Identity
            </button>
          </div>

          <!-- stats -->
          <div class="flex gap-8">
            <div>
              <div class="font-display text-[28px] font-bold" style="letter-spacing: -0.03em;">{Number(stats.totalDocuments || 0).toLocaleString()}</div>
              <div class="text-xs font-semibold" style="color: var(--text-3);">Documents on-chain</div>
            </div>
            <div class="w-px" style="background: var(--border);"></div>
            <div>
              <div class="font-display text-[28px] font-bold" style="letter-spacing: -0.03em;">{Number(stats.totalUsers || 0)}</div>
              <div class="text-xs font-semibold" style="color: var(--text-3);">Principals</div>
            </div>
            <div class="w-px" style="background: var(--border);"></div>
            <div>
              <div class="font-display text-[28px] font-bold" style="letter-spacing: -0.03em;">0</div>
              <div class="text-xs font-semibold" style="color: var(--text-3);">App servers</div>
            </div>
          </div>
        </div>

        <!-- Architecture diagram -->
        <div class="rise hidden lg:block" style="animation-delay: 0.15s;">
          <div class="glass ring-border relative overflow-hidden" style="border-radius: var(--r-xl); padding: 26px; aspect-ratio: 1 / 0.92;">
            <div class="flex items-center gap-2 mb-1">
              <span class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-[10.5px] font-semibold"
                style="color: var(--icp-purple); background: color-mix(in srgb, var(--icp-purple) 14%, transparent); border: 1px solid color-mix(in srgb, var(--icp-purple) 30%, transparent);">
                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2.5l8 4.5v9l-8 4.5-8-4.5v-9z M12 2.5v19 M4 7l8 4.5L20 7" /></svg>
                Live topology
              </span>
              <span class="ml-auto text-[11.5px] font-mono" style="color: var(--text-4);">mainnet · ic0.app</span>
            </div>

            <!-- SVG connections -->
            <svg viewBox="0 0 100 100" class="absolute inset-0 w-full h-full pointer-events-none">
              <defs><linearGradient id="lg" x1="0" y1="0" x2="100" y2="100"><stop stop-color="#7b3fe4" /><stop offset="1" stop-color="#29c5f6" /></linearGradient></defs>
              <line x1="50" y1="18" x2="20" y2="70" stroke="url(#lg)" stroke-width="0.5" stroke-dasharray="2 3" style="animation: dash-travel 5s linear infinite;" />
              <line x1="50" y1="18" x2="80" y2="70" stroke="url(#lg)" stroke-width="0.5" stroke-dasharray="2 3" style="animation: dash-travel 6s linear infinite;" />
              <line x1="20" y1="70" x2="80" y2="70" stroke="url(#lg)" stroke-width="0.5" stroke-dasharray="2 3" style="animation: dash-travel 7s linear infinite;" />
            </svg>

            <!-- Nodes -->
            <div class="absolute inset-0">
              <!-- Frontend -->
              <div class="absolute text-center" style="left: 50%; top: 12%; transform: translate(-50%, -50%);">
                <div class="w-14 h-14 rounded-2xl grid place-items-center mx-auto"
                  style="background: color-mix(in srgb, #29c5f6 15%, var(--bg-2)); border: 1px solid color-mix(in srgb, #29c5f6 40%, transparent); color: #29c5f6; box-shadow: 0 8px 28px -10px color-mix(in srgb, #29c5f6 70%, transparent);">
                  <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18z M3 12h18 M12 3c2.5 2.5 3.8 5.7 3.8 9S14.5 18.5 12 21 8.2 15.3 8.2 12 9.5 5.5 12 3z" /></svg>
                </div>
                <div class="text-xs font-bold font-display mt-2" style="color: var(--text);">Frontend</div>
                <div class="text-[10px] font-mono" style="color: var(--text-4);">ppfr3...</div>
              </div>

              <!-- Backend -->
              <div class="absolute text-center" style="left: 17%; top: 70%; transform: translate(-50%, -50%);">
                <div class="w-14 h-14 rounded-2xl grid place-items-center mx-auto"
                  style="background: color-mix(in srgb, #7b3fe4 15%, var(--bg-2)); border: 1px solid color-mix(in srgb, #7b3fe4 40%, transparent); color: #7b3fe4; box-shadow: 0 8px 28px -10px color-mix(in srgb, #7b3fe4 70%, transparent);">
                  <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 8c4.4 0 8-1.3 8-3s-3.6-3-8-3-8 1.3-8 3 3.6 3 8 3z M4 5v14c0 1.7 3.6 3 8 3s8-1.3 8-3V5 M4 12c0 1.7 3.6 3 8 3s8-1.3 8-3" /></svg>
                </div>
                <div class="text-xs font-bold font-display mt-2" style="color: var(--text);">Backend</div>
                <div class="text-[10px] font-mono" style="color: var(--text-4);">piexp...</div>
              </div>

              <!-- AI Canister -->
              <div class="absolute text-center" style="left: 83%; top: 70%; transform: translate(-50%, -50%);">
                <div class="w-14 h-14 rounded-2xl grid place-items-center mx-auto"
                  style="background: color-mix(in srgb, #e0359a 15%, var(--bg-2)); border: 1px solid color-mix(in srgb, #e0359a 40%, transparent); color: #e0359a; box-shadow: 0 8px 28px -10px color-mix(in srgb, #e0359a 70%, transparent);">
                  <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v3 M12 18v3 M5.6 5.6l2.1 2.1 M16.3 16.3l2.1 2.1 M3 12h3 M18 12h3 M5.6 18.4l2.1-2.1 M16.3 7.7l2.1-2.1" /></svg>
                </div>
                <div class="text-xs font-bold font-display mt-2" style="color: var(--text);">AI Canister</div>
                <div class="text-[10px] font-mono" style="color: var(--text-4);">pgg2h...</div>
              </div>

              <!-- Internet Identity -->
              <div class="absolute" style="left: 50%; top: 50%; transform: translate(-50%, -50%);">
                <span class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-[10.5px] font-semibold"
                  style="color: var(--green); background: color-mix(in srgb, var(--green) 14%, transparent); border: 1px solid color-mix(in srgb, var(--green) 30%, transparent);">
                  <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                    <path d="M12 11a2 2 0 0 1 2 2c0 2.5-.5 4.5-1.5 6 M8.5 7.5A5 5 0 0 1 17 11c0 1-.1 2-.3 3 M5.5 11a6.5 6.5 0 0 1 3-5.5 M7 16c.8-1.2 1-2.6 1-3 M12 13c0 3-1 5.5-2.5 7.5" />
                  </svg>
                  Internet Identity
                </span>
              </div>
            </div>

            <div class="absolute bottom-3.5 left-6 right-6 text-[11px] text-center" style="color: var(--text-4);">
              No application server — frontend, state, and AI orchestration run from canisters.
            </div>
          </div>
        </div>
      </div>
    </section>

    <!-- Feature cards -->
    <section class="max-w-[1180px] mx-auto px-7 pb-7">
      <div class="grid grid-cols-2 lg:grid-cols-4 gap-4">
        {#each [
          { icon: "lock", tint: "var(--green)", label: "AES-256 encrypted", desc: "In your browser, before it ever leaves." },
          { icon: "spark", tint: "var(--icp-pink)", label: "On-chain AI", desc: "Summaries & chat via the ICP LLM canister." },
          { icon: "fingerprint", tint: "var(--icp-cyan)", label: "On-chain integrity", desc: "Canister hashes your browser can verify." },
          { icon: "globe", tint: "var(--icp-purple)", label: "No server", desc: "Certified assets served from canisters." },
        ] as f}
          <div class="glass fade-in" style="border-radius: var(--r-lg); padding: 20px;">
            <div class="w-[38px] h-[38px] rounded-[11px] grid place-items-center mb-3.5"
              style="color: {f.tint}; background: color-mix(in srgb, {f.tint} 14%, transparent); border: 1px solid color-mix(in srgb, {f.tint} 28%, transparent);">
              {#if f.icon === "lock"}
                <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M5 11h14a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1v-8a1 1 0 0 1 1-1z M8 11V7a4 4 0 0 1 8 0v4" /></svg>
              {:else if f.icon === "spark"}
                <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v3 M12 18v3 M5.6 5.6l2.1 2.1 M16.3 16.3l2.1 2.1 M3 12h3 M18 12h3 M5.6 18.4l2.1-2.1 M16.3 7.7l2.1-2.1" /></svg>
              {:else if f.icon === "fingerprint"}
                <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 11a2 2 0 0 1 2 2c0 2.5-.5 4.5-1.5 6 M8.5 7.5A5 5 0 0 1 17 11c0 1-.1 2-.3 3 M5.5 11a6.5 6.5 0 0 1 3-5.5 M7 16c.8-1.2 1-2.6 1-3 M12 13c0 3-1 5.5-2.5 7.5" /></svg>
              {:else}
                <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18z M3 12h18 M12 3c2.5 2.5 3.8 5.7 3.8 9S14.5 18.5 12 21 8.2 15.3 8.2 12 9.5 5.5 12 3z" /></svg>
              {/if}
            </div>
            <div class="font-bold text-[14.5px] font-display mb-1">{f.label}</div>
            <div class="text-[12.5px] leading-relaxed" style="color: var(--text-3);">{f.desc}</div>
          </div>
        {/each}
      </div>
    </section>

    <!-- HOW IT WORKS -->
    <section class="max-w-[1180px] mx-auto px-7 py-16">
      <div class="text-center mb-12">
        <span class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-semibold mb-4"
          style="color: var(--icp-pink); background: color-mix(in srgb, var(--icp-pink) 14%, transparent); border: 1px solid color-mix(in srgb, var(--icp-pink) 30%, transparent);">
          How it works
        </span>
        <h2 class="font-display text-[38px] font-bold" style="letter-spacing: -0.03em;">Three steps. Zero servers.</h2>
      </div>
      <div class="grid grid-cols-1 md:grid-cols-3 gap-5">
        {#each [
          { n: "01", title: "Upload", tint: "#29c5f6", desc: "Drag in any file. It's chunked into 1 MB pieces, encrypted in your browser, and written to ICP canisters.", icon: "upload" },
          { n: "02", title: "Analyze", tint: "#e0359a", desc: "On-chain AI summarizes, extracts key points, categorizes, and chats with your document — no data leaves the chain by default.", icon: "spark" },
          { n: "03", title: "Share", tint: "#7b3fe4", desc: "Grant access to any principal or username. The AES key is wrapped to their public key. Every action is on the audit trail.", icon: "share" },
        ] as s}
          <div class="glass relative overflow-hidden" style="border-radius: var(--r-xl); padding: 28px;">
            <div class="absolute -top-2.5 right-3.5 font-display font-bold text-[78px]" style="color: var(--surface-hi); letter-spacing: -0.04em;">{s.n}</div>
            <div class="w-[50px] h-[50px] rounded-[14px] grid place-items-center mb-4 relative"
              style="color: {s.tint}; background: color-mix(in srgb, {s.tint} 14%, transparent); border: 1px solid color-mix(in srgb, {s.tint} 30%, transparent);">
              {#if s.icon === "upload"}
                <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 16V4 M7 9l5-5 5 5 M5 20h14" /></svg>
              {:else if s.icon === "spark"}
                <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v3 M12 18v3 M5.6 5.6l2.1 2.1 M16.3 16.3l2.1 2.1 M3 12h3 M18 12h3 M5.6 18.4l2.1-2.1 M16.3 7.7l2.1-2.1" /></svg>
              {:else}
                <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M18 8a3 3 0 1 0 0-6 3 3 0 0 0 0 6z M6 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z M18 22a3 3 0 1 0 0-6 3 3 0 0 0 0 6z M8.6 13.5l6.8 4 M15.4 6.5l-6.8 4" /></svg>
              {/if}
            </div>
            <h3 class="font-display text-[21px] font-semibold mb-2">{s.title}</h3>
            <p class="text-sm leading-relaxed" style="color: var(--text-3);">{s.desc}</p>
          </div>
        {/each}
      </div>
    </section>

    <!-- WHY ICP -->
    <section class="max-w-[1180px] mx-auto px-7 mb-20">
      <div class="ring-border relative overflow-hidden" style="border-radius: var(--r-xl); padding: 48px 44px; background: var(--grad-icp-soft);">
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-11 items-center">
          <div>
            <h2 class="font-display text-[34px] font-bold mb-4 leading-tight" style="letter-spacing: -0.03em;">
              Why the <span class="grad-text">Internet Computer?</span>
            </h2>
            <p class="text-[15.5px] leading-relaxed mb-6" style="color: var(--text-2);">
              Smart contracts that orchestrate AI and external API calls — with no application server in between. That's a capability unique to ICP, and it's the foundation DocuCollab is built on.
            </p>
            <button on:click={() => { import('$lib/services/auth').then(m => m.login().then(() => { $isAuthenticated = true; })); }}
              class="btn-grad px-5 py-3 text-[14.5px] inline-flex items-center gap-2">
              Start collaborating
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14 M13 6l6 6-6 6" /></svg>
            </button>
          </div>
          <div class="flex flex-col gap-3">
            {#each [
              ["On-chain AI via mo:llm", "Default summaries & chat run in a canister; premium HTTPS outcalls are optional."],
              ["On-chain integrity hashes", "SHA-256 computed in the backend canister, verifiable by any client."],
              ["AES-256 + RSA key-wrapping", "Client-side encryption with secure key exchange for sharing."],
              ["Internet Identity", "Passwordless, principal-based, privacy-preserving auth."],
            ] as [t, d]}
              <div class="flex gap-3 items-start rounded-[14px] p-3.5" style="background: var(--surface); border: 1px solid var(--border);">
                <span class="mt-0.5 flex-shrink-0" style="color: var(--green);">
                  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18z M8.5 12l2.5 2.5 4.5-5" /></svg>
                </span>
                <div>
                  <div class="font-bold text-[13.5px] mb-0.5">{t}</div>
                  <div class="text-[12.5px] leading-relaxed" style="color: var(--text-3);">{d}</div>
                </div>
              </div>
            {/each}
          </div>
        </div>
      </div>
    </section>

    <!-- Footer -->
    <footer class="py-7 px-7 text-center text-[12.5px]" style="border-top: 1px solid var(--border); color: var(--text-4);">
      <div class="flex justify-center mb-2.5">
        <span class="font-display font-bold text-base" style="color: var(--text);">
          Docu<span class="grad-text">Collab</span>
        </span>
      </div>
      Decentralized document collaboration · MIT licensed · Running on ICP mainnet
    </footer>
  </div>

{:else if showRegister}
  <!-- ====== REGISTRATION ====== -->
  <div class="min-h-[calc(100vh-64px)] grid place-items-center p-7">
    <div class="glass ring-border scale-in" style="border-radius: var(--r-xl); padding: 40px 44px; width: 460px; max-width: 100%;">
      <span class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-semibold mb-4"
        style="color: var(--green); background: color-mix(in srgb, var(--green) 14%, transparent); border: 1px solid color-mix(in srgb, var(--green) 30%, transparent);">
        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5l4.5 4.5L19 7" /></svg>
        Authenticated
      </span>
      <h2 class="font-display text-[26px] font-bold mb-2">Welcome to DocuCollab</h2>
      <p class="text-sm mb-6 leading-relaxed" style="color: var(--text-3);">Pick a username so teammates can find and share with you. We'll generate your encryption keys next.</p>
      <label for="register-username" class="text-xs font-bold" style="color: var(--text-3); letter-spacing: 0.03em;">USERNAME</label>
      <input
        id="register-username"
        type="text"
        bind:value={username}
        placeholder="e.g. lyra.kovac"
        on:keydown={(e) => e.key === "Enter" && registerUser()}
        class="w-full mt-2 mb-5 px-3.5 py-3 rounded-xl text-[15px] outline-none"
        style="background: var(--bg-2); border: 1px solid var(--border-hi); color: var(--text);"
      />
      <button on:click={registerUser}
        class="btn-grad w-full py-3.5 text-[15px]"
        style="opacity: {username.trim() && !registering ? 1 : 0.5};"
        disabled={!username.trim() || registering}>
        {registering ? "Generating keys..." : "Generate keys & continue"}
      </button>
    </div>
  </div>

{:else if viewingDoc}
  <DocumentView doc={viewingDoc} on:close={() => viewingDoc = null} />

{:else}
  <!-- ====== DASHBOARD ====== -->
  <div class="max-w-[1080px] mx-auto px-7 pt-8 pb-20">
    <!-- Stats -->
    <div class="grid grid-cols-2 sm:grid-cols-4 gap-3.5 mb-5">
      <div class="glass rounded-[var(--r-lg)] p-4 relative overflow-hidden" style="background: var(--grad-icp-soft);">
        <div class="flex justify-between items-start">
          <span class="text-[12.5px] font-semibold" style="color: var(--text-3);">My Documents</span>
          <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" style="color: var(--icp-cyan);"><path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" /></svg>
        </div>
        <div class="font-display text-[30px] font-bold mt-3" style="letter-spacing: -0.03em; line-height: 1;">{$documents.length}</div>
      </div>

      <div class="glass rounded-[var(--r-lg)] p-4">
        <div class="flex justify-between items-start">
          <span class="text-[12.5px] font-semibold" style="color: var(--text-3);">Shared with me</span>
          <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" style="color: var(--icp-purple);"><path d="M9 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8z M2.5 20a6.5 6.5 0 0 1 13 0 M16 4.2a4 4 0 0 1 0 7.6 M18 13.5a6.5 6.5 0 0 1 3.5 5.8" /></svg>
        </div>
        <div class="font-display text-[30px] font-bold mt-3" style="letter-spacing: -0.03em; line-height: 1;">{$sharedDocuments.length}</div>
      </div>

      <div class="glass rounded-[var(--r-lg)] p-4">
        <div class="flex justify-between items-start">
          <span class="text-[12.5px] font-semibold" style="color: var(--text-3);">Platform users</span>
          <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" style="color: var(--icp-pink);"><path d="M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18z M3 12h18 M12 3c2.5 2.5 3.8 5.7 3.8 9S14.5 18.5 12 21 8.2 15.3 8.2 12 9.5 5.5 12 3z" /></svg>
        </div>
        <div class="font-display text-[30px] font-bold mt-3" style="letter-spacing: -0.03em; line-height: 1;">{Number(stats.totalUsers || 0)}</div>
      </div>

      <div class="glass rounded-[var(--r-lg)] p-4">
        <div class="flex justify-between items-start">
          <span class="text-[12.5px] font-semibold" style="color: var(--text-3);">Storage used</span>
          <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" style="color: var(--green);"><path d="M12 8c4.4 0 8-1.3 8-3s-3.6-3-8-3-8 1.3-8 3 3.6 3 8 3z M4 5v14c0 1.7 3.6 3 8 3s8-1.3 8-3V5 M4 12c0 1.7 3.6 3 8 3s8-1.3 8-3" /></svg>
        </div>
        <div class="font-display text-[21px] font-bold mt-2.5 mb-2">
          {storageLabel} <span class="text-[11.5px] font-normal" style="color: var(--text-4);">/ 50 MB</span>
        </div>
        <div class="h-1.5 rounded-full overflow-hidden" style="background: var(--surface-hi);">
          <div class="h-full rounded-full transition-all" style="width: {storagePct.toFixed(2)}%; background: var(--grad-icp);"></div>
        </div>
      </div>
    </div>

    <!-- Header -->
    <input type="file" bind:this={recoveryFileInput} accept=".key,application/octet-stream" on:change={importRecovery} class="hidden" />
    <div class="flex items-center justify-between mb-4 gap-3 flex-wrap">
      <h1 class="font-display text-2xl font-bold">Documents</h1>
      <div class="flex items-center gap-2 flex-wrap justify-end">
        <button on:click={exportRecovery}
          disabled={!hasLocalPrivateKey}
          class="glass inline-flex items-center gap-2 px-3 py-1.5 rounded-full text-[12.5px] font-semibold transition-all hover:border-[var(--border-hi)]"
          style="color: var(--text-2); opacity: {hasLocalPrivateKey ? 1 : 0.45};" title="Export recovery key">
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" style="color: var(--text-4);"><path d="M12 3v12 M7 10l5 5 5-5 M5 21h14" /></svg>
          Export key
        </button>
        <button on:click={() => recoveryFileInput?.click()}
          class="glass inline-flex items-center gap-2 px-3 py-1.5 rounded-full text-[12.5px] font-semibold transition-all hover:border-[var(--border-hi)]"
          style="color: var(--text-2);" title="Import recovery key">
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" style="color: var(--text-4);"><path d="M12 21V9 M7 14l5-5 5 5 M5 3h14" /></svg>
          Import key
        </button>
        <button on:click={backfillOwnerKeys}
          disabled={backfilling || !hasLocalPrivateKey || $documents.length === 0}
          class="glass inline-flex items-center gap-2 px-3 py-1.5 rounded-full text-[12.5px] font-semibold transition-all hover:border-[var(--border-hi)]"
          style="color: var(--text-2); opacity: {hasLocalPrivateKey && $documents.length > 0 && !backfilling ? 1 : 0.45};" title="Store recovery keys for existing documents">
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" style="color: var(--text-4);"><path d="M5 11h14a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1v-8a1 1 0 0 1 1-1z M8 11V7a4 4 0 0 1 8 0v4" /></svg>
          {backfilling ? "Backfilling..." : "Backfill keys"}
        </button>
        <button on:click={() => copyText(getPrincipal()?.toText() || '')}
          class="glass inline-flex items-center gap-2 px-3 py-1.5 rounded-full font-mono text-[12.5px] transition-all hover:border-[var(--border-hi)]"
          style="color: var(--text-2);" title="Click to copy principal">
          <span class="font-body font-semibold" style="color: var(--text-4);">principal</span>
          <span>{getPrincipal()?.toText()?.slice(0, 8)}...{getPrincipal()?.toText()?.slice(-5)}</span>
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" style="color: var(--text-4);"><path d="M9 9h10a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H9a1 1 0 0 1-1-1V10a1 1 0 0 1 1-1z M5 15H4a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1h10a1 1 0 0 1 1 1v1" /></svg>
        </button>
      </div>
    </div>

    {#if !hasLocalPrivateKey}
      <div class="glass rounded-[var(--r-lg)] p-4 mb-4 flex flex-col sm:flex-row sm:items-center gap-3 justify-between">
        <div>
          <div class="text-[14px] font-semibold">Local encryption key missing</div>
          <div class="text-[12.5px] mt-0.5" style="color: var(--text-3);">Import your recovery key to decrypt existing encrypted documents in this browser.</div>
        </div>
        <button on:click={() => recoveryFileInput?.click()}
          class="btn-ghost px-[14px] py-[9px] text-[13px] flex items-center justify-center gap-[7px] flex-shrink-0">
          <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 21V9 M7 14l5-5 5 5 M5 3h14" /></svg>
          Import recovery key
        </button>
      </div>
    {/if}

    <!-- Upload -->
    <div class="mb-5">
      <FileUpload on:uploaded={loadDocuments} />
    </div>


    <!-- Tabs -->
    <div class="flex gap-1 rounded-xl p-1 mb-4" style="background: var(--surface); border: 1px solid var(--border);">
      <button
        on:click={() => activeTab = "my-docs"}
        class="flex-1 px-4 py-2 rounded-[9px] text-[13.5px] font-semibold transition-all"
        style="color: {activeTab === 'my-docs' ? 'var(--text)' : 'var(--text-3)'}; background: {activeTab === 'my-docs' ? 'var(--surface-hi)' : 'transparent'};">
        My Documents <span style="color: var(--text-4);">{$documents.length}</span>
      </button>
      <button
        on:click={() => activeTab = "shared"}
        class="flex-1 px-4 py-2 rounded-[9px] text-[13.5px] font-semibold transition-all"
        style="color: {activeTab === 'shared' ? 'var(--text)' : 'var(--text-3)'}; background: {activeTab === 'shared' ? 'var(--surface-hi)' : 'transparent'};">
        Shared With Me <span style="color: var(--text-4);">{$sharedDocuments.length}</span>
      </button>
    </div>

    {#if $isLoading}
      <div class="flex justify-center py-12">
        <div class="w-8 h-8 rounded-full border-2 anim-spin" style="border-color: var(--surface); border-top-color: var(--icp-pink);"></div>
      </div>
    {:else if activeTab === "my-docs"}
      <DocumentList on:view={handleView} on:refresh={loadDocuments} on:batchShare={handleBatchShare} />
    {:else}
      {#if $sharedDocuments.length === 0}
        <div class="glass rounded-[var(--r-lg)] py-11 text-center text-sm" style="color: var(--text-4);">No documents shared with you yet.</div>
      {:else}
        <div class="flex flex-col gap-2.5">
          {#each $sharedDocuments as doc}
            <button on:click={() => viewingDoc = doc}
              class="glass rounded-[var(--r-md)] p-3.5 flex items-center gap-3.5 cursor-pointer transition-all text-left w-full hover:border-[var(--border-hi)]">
              <div class="w-[42px] h-[42px] rounded-xl grid place-items-center flex-shrink-0"
                style="background: color-mix(in srgb, var(--icp-purple) 13%, transparent); border: 1px solid color-mix(in srgb, var(--icp-purple) 26%, transparent); color: var(--icp-purple);">
                <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M18 8a3 3 0 1 0 0-6 3 3 0 0 0 0 6z M6 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z M18 22a3 3 0 1 0 0-6 3 3 0 0 0 0 6z M8.6 13.5l6.8 4 M15.4 6.5l-6.8 4" /></svg>
              </div>
              <div class="flex-1 min-w-0">
                <div class="font-semibold text-[14.5px] truncate">{doc.name}</div>
                <div class="text-xs mt-0.5" style="color: var(--text-3);">Shared document</div>
              </div>
              <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" style="color: var(--text-4); flex-shrink: 0;"><path d="M9 6l6 6-6 6" /></svg>
            </button>
          {/each}
        </div>
      {/if}
    {/if}

    <!-- Activity -->
    <div class="mt-9">
      <ActivityLog />
    </div>
  </div>
{/if}

{#if showBatchShare && batchShareDoc}
  <ShareModal doc={batchShareDoc} on:close={() => { showBatchShare = false; batchShareIds = []; }} on:shared={onBatchShared} />
{/if}
