<script>
  import { isAuthenticated, documents, sharedDocuments, userProfile, isLoading, notify } from "$lib/stores/app";
  import { getBackend, getPrincipal } from "$lib/services/auth";
  import { generateKeyPair, exportPublicKey, savePrivateKey, hasPrivateKey, exportRecoveryKey, importRecoveryKey } from "$lib/services/crypto";
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
        loadDocuments();
      } else {
        showRegister = true;
      }
    } catch (e) {
      console.error("Profile check error:", e);
    }
  }

  async function registerUser() {
    if (!username.trim()) return;
    const backend = getBackend();
    if (!backend) return;
    try {
      // Generate RSA keypair for E2E encryption
      const keyPair = await generateKeyPair();
      const publicKeyBytes = await exportPublicKey(keyPair.publicKey);
      await savePrivateKey(keyPair.privateKey);

      const result = await backend.registerUser(username.trim(), publicKeyBytes);
      if ("ok" in result) {
        $userProfile = result.ok;
        showRegister = false;
        notify("Welcome to DocuCollab! Your encryption keys have been generated.", "success");
        loadDocuments();
      } else {
        notify(result.err, "error");
      }
    } catch (e) {
      notify("Registration failed: " + e.message, "error");
    }
  }

  async function downloadRecoveryKey() {
    try {
      const pkcs8 = await exportRecoveryKey();
      const blob = new Blob([pkcs8], { type: "application/octet-stream" });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = "docucollab-recovery-key.bin";
      a.click();
      URL.revokeObjectURL(url);
      notify("Recovery key downloaded! Keep it safe.", "success");
    } catch (e) {
      notify("No recovery key found: " + e.message, "error");
    }
  }

  async function uploadRecoveryKey(e) {
    const file = e.target.files[0];
    if (!file) return;
    try {
      const bytes = new Uint8Array(await file.arrayBuffer());
      await importRecoveryKey(bytes);
      notify("Recovery key imported successfully!", "success");
    } catch (e) {
      notify("Invalid recovery key: " + e.message, "error");
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
</script>

<div class="max-w-5xl mx-auto px-4 py-8">
  {#if !$isAuthenticated}
    <!-- Landing -->
    <div class="text-center py-20">
      <h1 class="text-4xl font-bold text-gray-900 dark:text-white mb-4">
        Secure Document Collaboration
      </h1>
      <p class="text-lg text-gray-600 dark:text-gray-400 mb-8 max-w-2xl mx-auto">
        Share and collaborate on documents with end-to-end encryption.
        Powered by the Internet Computer &mdash; fully on-chain, no servers.
      </p>
      <!-- Platform Stats -->
      <div class="flex flex-wrap justify-center gap-6 mb-8 text-sm text-gray-500">
        <span><strong class="text-gray-900 dark:text-white">{Number(stats.totalDocuments || 0)}</strong> Documents</span>
        <span><strong class="text-gray-900 dark:text-white">{Number(stats.totalUsers || 0)}</strong> Users</span>
      </div>

      <div class="flex flex-wrap justify-center gap-3 mb-12">
        <div class="flex items-center gap-2 px-4 py-2 bg-white dark:bg-gray-800 rounded-lg shadow-sm border border-gray-200 dark:border-gray-700">
          <svg class="w-5 h-5 text-green-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
          </svg>
          <span class="text-sm font-medium text-gray-700 dark:text-gray-300">AES-256 Encrypted</span>
        </div>
        <div class="flex items-center gap-2 px-4 py-2 bg-white dark:bg-gray-800 rounded-lg shadow-sm border border-gray-200 dark:border-gray-700">
          <svg class="w-5 h-5 text-purple-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9.663 17h4.673M12 3v1m6.364 1.636l-.707.707M21 12h-1M4 12H3m3.343-5.657l-.707-.707m2.828 9.9a5 5 0 117.072 0l-.548.547A3.374 3.374 0 0014 18.469V19a2 2 0 11-4 0v-.531c0-.895-.356-1.754-.988-2.386l-.548-.547z" />
          </svg>
          <span class="text-sm font-medium text-gray-700 dark:text-gray-300">On-Chain AI</span>
        </div>
        <div class="flex items-center gap-2 px-4 py-2 bg-white dark:bg-gray-800 rounded-lg shadow-sm border border-gray-200 dark:border-gray-700">
          <svg class="w-5 h-5 text-blue-500" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M2.166 4.999A11.954 11.954 0 0010 1.944 11.954 11.954 0 0017.834 5c.11.65.166 1.32.166 2.001 0 5.225-3.34 9.67-8 11.317C5.34 16.67 2 12.225 2 7c0-.682.057-1.35.166-2.001zm11.541 3.708a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd" />
          </svg>
          <span class="text-sm font-medium text-gray-700 dark:text-gray-300">On-Chain Hash</span>
        </div>
        <div class="flex items-center gap-2 px-4 py-2 bg-white dark:bg-gray-800 rounded-lg shadow-sm border border-gray-200 dark:border-gray-700">
          <svg class="w-5 h-5 text-orange-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 12a9 9 0 01-9 9m9-9a9 9 0 00-9-9m9 9H3m9 9a9 9 0 01-9-9m9 9c1.657 0 3-4.03 3-9s-1.343-9-3-9m0 18c-1.657 0-3-4.03-3-9s1.343-9 3-9m-9 9a9 9 0 019-9" />
          </svg>
          <span class="text-sm font-medium text-gray-700 dark:text-gray-300">ICP Native</span>
        </div>
      </div>
      <p class="text-sm text-gray-400 mb-16">Login with Internet Identity to get started</p>

      <!-- How it works -->
      <div class="max-w-3xl mx-auto text-left mb-16">
        <h2 class="text-2xl font-bold text-gray-900 dark:text-white text-center mb-8">How It Works</h2>
        <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
          <div class="bg-white dark:bg-gray-800 rounded-xl p-6 border border-gray-200 dark:border-gray-700">
            <div class="w-10 h-10 rounded-full bg-primary-100 dark:bg-primary-900/30 flex items-center justify-center text-primary-600 font-bold mb-3">1</div>
            <h3 class="font-semibold text-gray-900 dark:text-white mb-1">Upload</h3>
            <p class="text-sm text-gray-500 dark:text-gray-400">Drag & drop any file. It's chunked, encrypted, and stored fully on-chain in ICP canisters.</p>
          </div>
          <div class="bg-white dark:bg-gray-800 rounded-xl p-6 border border-gray-200 dark:border-gray-700">
            <div class="w-10 h-10 rounded-full bg-primary-100 dark:bg-primary-900/30 flex items-center justify-center text-primary-600 font-bold mb-3">2</div>
            <h3 class="font-semibold text-gray-900 dark:text-white mb-1">AI Analyze</h3>
            <p class="text-sm text-gray-500 dark:text-gray-400">AI-powered analysis using ICP LLM by default, with optional premium HTTPS outcalls. Chat, summarize, extract key points.</p>
          </div>
          <div class="bg-white dark:bg-gray-800 rounded-xl p-6 border border-gray-200 dark:border-gray-700">
            <div class="w-10 h-10 rounded-full bg-primary-100 dark:bg-primary-900/30 flex items-center justify-center text-primary-600 font-bold mb-3">3</div>
            <h3 class="font-semibold text-gray-900 dark:text-white mb-1">Share</h3>
            <p class="text-sm text-gray-500 dark:text-gray-400">Share documents with any ICP principal. Access is controlled on-chain with full audit trail.</p>
          </div>
        </div>
      </div>

      <!-- Why ICP -->
      <div class="max-w-3xl mx-auto mb-16">
        <h2 class="text-2xl font-bold text-gray-900 dark:text-white text-center mb-8">Why Internet Computer?</h2>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div class="flex items-start gap-3 bg-white dark:bg-gray-800 rounded-lg p-4 border border-gray-200 dark:border-gray-700">
            <span class="text-green-500 mt-0.5">&#10003;</span>
            <div>
              <p class="font-medium text-gray-900 dark:text-white text-sm">On-Chain AI (icp_llm)</p>
              <p class="text-xs text-gray-500">AI inference runs fully on-chain via the LLM canister -- zero Web2 dependencies</p>
            </div>
          </div>
          <div class="flex items-start gap-3 bg-white dark:bg-gray-800 rounded-lg p-4 border border-gray-200 dark:border-gray-700">
            <span class="text-green-500 mt-0.5">&#10003;</span>
            <div>
              <p class="font-medium text-gray-900 dark:text-white text-sm">On-Chain Integrity Hashes</p>
              <p class="text-xs text-gray-500">SHA-256 document hashes are computed in the backend canister and verified by the client</p>
            </div>
          </div>
          <div class="flex items-start gap-3 bg-white dark:bg-gray-800 rounded-lg p-4 border border-gray-200 dark:border-gray-700">
            <span class="text-green-500 mt-0.5">&#10003;</span>
            <div>
              <p class="font-medium text-gray-900 dark:text-white text-sm">AES-256 + RSA Key Exchange</p>
              <p class="text-xs text-gray-500">Client-side encryption with secure key wrapping for document sharing</p>
            </div>
          </div>
          <div class="flex items-start gap-3 bg-white dark:bg-gray-800 rounded-lg p-4 border border-gray-200 dark:border-gray-700">
            <span class="text-green-500 mt-0.5">&#10003;</span>
            <div>
              <p class="font-medium text-gray-900 dark:text-white text-sm">Internet Identity + Optional Outcalls</p>
              <p class="text-xs text-gray-500">Passwordless auth, canister-hosted UI, and optional direct external API calls</p>
            </div>
          </div>
        </div>
      </div>
    </div>

  {:else if showRegister}
    <!-- Registration -->
    <div class="max-w-md mx-auto py-20">
      <h2 class="text-2xl font-bold text-gray-900 dark:text-white mb-2">Welcome!</h2>
      <p class="text-gray-600 dark:text-gray-400 mb-6">Choose a username to get started.</p>
      <div class="space-y-4">
        <input
          type="text"
          bind:value={username}
          placeholder="Your username"
          class="w-full px-4 py-3 border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-800 text-gray-900 dark:text-white focus:ring-2 focus:ring-primary-500"
          on:keydown={(e) => e.key === "Enter" && registerUser()}
        />
        <button on:click={registerUser}
          class="w-full px-4 py-3 text-white bg-primary-600 rounded-lg hover:bg-primary-700 font-medium transition">
          Create Account
        </button>
      </div>
    </div>

  {:else if viewingDoc}
    <DocumentView doc={viewingDoc} on:close={() => viewingDoc = null} />

  {:else}
    <!-- Dashboard -->
    <div class="space-y-6">
      <!-- Stats cards -->
      <div class="grid grid-cols-1 sm:grid-cols-4 gap-3">
        <div class="bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 p-4">
          <p class="text-xs text-gray-500 mb-1">My Documents</p>
          <p class="text-2xl font-bold text-gray-900 dark:text-white">{$documents.length}</p>
        </div>
        <div class="bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 p-4">
          <p class="text-xs text-gray-500 mb-1">Shared With Me</p>
          <p class="text-2xl font-bold text-gray-900 dark:text-white">{$sharedDocuments.length}</p>
        </div>
        <div class="bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 p-4">
          <p class="text-xs text-gray-500 mb-1">Platform Users</p>
          <p class="text-2xl font-bold text-gray-900 dark:text-white">{Number(stats.totalUsers || 0)}</p>
        </div>
        <div class="bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 p-4">
          <p class="text-xs text-gray-500 mb-1">Storage Used</p>
          <p class="text-lg font-bold text-gray-900 dark:text-white">{(() => {
            const bytes = $documents.reduce((sum, d) => sum + Number(d.size), 0);
            if (bytes < 1024) return bytes + " B";
            if (bytes < 1048576) return (bytes / 1024).toFixed(1) + " KB";
            return (bytes / 1048576).toFixed(1) + " MB";
          })()} <span class="text-xs font-normal text-gray-400">/ 50 MB MVP</span></p>
          <div class="mt-2 w-full bg-gray-200 dark:bg-gray-700 rounded-full h-1.5">
            <div class="bg-primary-500 h-1.5 rounded-full transition-all" style="width: {Math.min(100, $documents.reduce((sum, d) => sum + Number(d.size), 0) / (50 * 1024 * 1024) * 100).toFixed(2)}%"></div>
          </div>
        </div>
      </div>

      <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-2">
        <h1 class="text-2xl font-bold text-gray-900 dark:text-white">Documents</h1>
        <div class="flex items-center gap-2">
          <button on:click={downloadRecoveryKey} title="Export recovery key"
            class="p-1.5 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700 text-gray-400 hover:text-gray-600 transition">
            <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 7a2 2 0 012 2m4 0a6 6 0 01-7.743 5.743L11 17H9v2H7v2H4a1 1 0 01-1-1v-2.586a1 1 0 01.293-.707l5.964-5.964A6 6 0 1121 9z" /></svg>
          </button>
          <button on:click={() => copyText(getPrincipal()?.toText() || '')}
            class="text-sm text-gray-500 hover:text-primary-600 flex items-center gap-1 transition" title="Click to copy">
            <svg class="w-3.5 h-3.5 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z" /></svg>
            <code class="text-xs bg-gray-100 dark:bg-gray-800 px-2 py-1 rounded select-all truncate max-w-[200px] sm:max-w-none">{getPrincipal()?.toText()}</code>
          </button>
        </div>
      </div>

      <FileUpload on:uploaded={loadDocuments} />

      <!-- Tabs -->
      <div class="flex gap-1 bg-gray-100 dark:bg-gray-800 rounded-lg p-1">
        <button
          on:click={() => activeTab = "my-docs"}
          class="flex-1 px-4 py-2 text-sm font-medium rounded-md transition
            {activeTab === 'my-docs' ? 'bg-white dark:bg-gray-700 text-gray-900 dark:text-white shadow-sm' : 'text-gray-600 dark:text-gray-400 hover:text-gray-900'}">
          My Documents ({$documents.length})
        </button>
        <button
          on:click={() => activeTab = "shared"}
          class="flex-1 px-4 py-2 text-sm font-medium rounded-md transition
            {activeTab === 'shared' ? 'bg-white dark:bg-gray-700 text-gray-900 dark:text-white shadow-sm' : 'text-gray-600 dark:text-gray-400 hover:text-gray-900'}">
          Shared With Me ({$sharedDocuments.length})
        </button>
      </div>

      {#if $isLoading}
        <div class="flex justify-center py-12">
          <div class="w-8 h-8 border-4 border-primary-200 border-t-primary-600 rounded-full animate-spin"></div>
        </div>
      {:else if activeTab === "my-docs"}
        <DocumentList on:view={handleView} on:refresh={loadDocuments} on:batchShare={handleBatchShare} />
      {:else}
        {#if $sharedDocuments.length === 0}
          <div class="text-center py-12 text-gray-400">No documents shared with you yet.</div>
        {:else}
          <div class="grid gap-3">
            {#each $sharedDocuments as doc}
              <button on:click={() => viewingDoc = doc}
                class="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 p-4 hover:shadow-md transition-shadow text-left flex items-center gap-3">
                <div class="w-10 h-10 rounded-lg bg-purple-100 dark:bg-purple-900/30 flex items-center justify-center">
                  <svg class="w-5 h-5 text-purple-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8.684 13.342C8.886 12.938 9 12.482 9 12c0-.482-.114-.938-.316-1.342m0 2.684a3 3 0 110-2.684m0 2.684l6.632 3.316m-6.632-6l6.632-3.316m0 0a3 3 0 105.367-2.684 3 3 0 00-5.367 2.684zm0 9.316a3 3 0 105.368 2.684 3 3 0 00-5.368-2.684z" />
                  </svg>
                </div>
                <div>
                  <p class="font-medium text-gray-900 dark:text-white">{doc.name}</p>
                  <p class="text-xs text-gray-500">Shared document</p>
                </div>
              </button>
            {/each}
          </div>
        {/if}
      {/if}

      <ActivityLog />
    </div>
  {/if}
</div>

{#if showBatchShare && batchShareDoc}
  <ShareModal doc={batchShareDoc} on:close={() => { showBatchShare = false; batchShareIds = []; }} on:shared={onBatchShared} />
{/if}
