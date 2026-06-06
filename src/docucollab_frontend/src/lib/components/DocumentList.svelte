<script>
  import { getBackend, getAI } from "$lib/services/auth";
  import { documents, notify, isLoading } from "$lib/stores/app";
  import { getDocumentKey, decryptText } from "$lib/services/crypto";
  import { createEventDispatcher } from "svelte";

  const dispatch = createEventDispatcher();
  const AI_SEARCH_MAX_DOCS = 40;
  const AI_SEARCH_SUMMARY_CHARS = 220;

  let searchQuery = "";
  let sortBy = "date";
  let selectedIds = new Set();
  let selectMode = false;
  let aiSearching = false;
  let aiMatchedIds = null;
  let decryptedSummaries = {};
  let loadedSummaryIds = new Set();
  let summaryLoadToken = 0;

  $: loadSummariesForDocs($documents);

  $: filteredDocs = $documents
    .filter(d => {
      if (aiMatchedIds !== null) return aiMatchedIds.has(Number(d.id));
      const q = searchQuery.toLowerCase();
      if (!q) return true;
      if (d.name.toLowerCase().includes(q)) return true;
      const summary = summaryFor(d);
      if (summary && summary.toLowerCase().includes(q)) return true;
      return false;
    })
    .sort((a, b) => {
      if (sortBy === "name") return a.name.localeCompare(b.name);
      if (sortBy === "size") return Number(b.size) - Number(a.size);
      return Number(b.updatedAt) - Number(a.updatedAt);
    });

  async function aiSearch() {
    if (!searchQuery.trim() || aiSearching) return;
    const ai = getAI();
    if (!ai) { notify("AI not available", "error"); return; }

    const docsWithSummary = $documents
      .filter(d => summaryFor(d))
      .sort((a, b) => Number(b.updatedAt) - Number(a.updatedAt));
    if (docsWithSummary.length === 0) {
      notify("No documents with AI summaries to search", "info");
      return;
    }

    aiSearching = true;
    try {
      const catalogDocs = docsWithSummary.slice(0, AI_SEARCH_MAX_DOCS);
      const knownIds = new Set(catalogDocs.map(d => Number(d.id)));
      const catalog = catalogDocs.map(d =>
        JSON.stringify({
          id: Number(d.id),
          name: d.name,
          summary: summaryFor(d).slice(0, AI_SEARCH_SUMMARY_CHARS),
        })
      ).join("\n");

      const query = searchQuery.trim();
      const result = await ai.chatWithDocument(
        catalog,
        `Find documents matching this query: ${JSON.stringify(query)}. Return JSON only, in this exact shape: {"ids":[1,2]}. Use only IDs present in the catalog. Return {"ids":[]} if none match.`
      );

      if ("ok" in result) {
        aiMatchedIds = parseAiSearchIds(result.ok, knownIds);
        const cappedNote = docsWithSummary.length > catalogDocs.length
          ? ` Searched the ${catalogDocs.length} most recent summarized documents.`
          : "";
        notify(
          aiMatchedIds.size > 0
            ? `AI found ${aiMatchedIds.size} matching document${aiMatchedIds.size !== 1 ? 's' : ''}.${cappedNote}`
            : `AI found no matching documents.${cappedNote}`,
          aiMatchedIds.size > 0 ? "success" : "info"
        );
      } else {
        notify("AI search failed: " + result.err, "error");
      }
    } catch (e) {
      notify("AI search error: " + e.message, "error");
    } finally {
      aiSearching = false;
    }
  }

  function clearAiSearch() {
    aiMatchedIds = null;
    searchQuery = "";
  }

  function parseAiSearchIds(response, knownIds) {
    const trimmed = response.trim();
    if (!trimmed || /^none$/i.test(trimmed)) return new Set();

    const parsed = parseJsonIds(trimmed);
    const candidates = parsed || (trimmed.match(/\b\d+\b/g) || []).map(Number);
    return new Set(candidates.filter(id => knownIds.has(id)));
  }

  function parseJsonIds(text) {
    const snippets = [text];
    const objectMatch = text.match(/\{[\s\S]*\}/);
    const arrayMatch = text.match(/\[[\s\S]*\]/);
    if (objectMatch) snippets.push(objectMatch[0]);
    if (arrayMatch) snippets.push(arrayMatch[0]);

    for (const snippet of snippets) {
      try {
        const parsed = JSON.parse(snippet);
        const ids = Array.isArray(parsed) ? parsed : parsed?.ids;
        if (Array.isArray(ids)) return ids.map(Number).filter(Number.isFinite);
      } catch {}
    }

    return null;
  }

  function summaryFor(doc) {
    const id = Number(doc.id);
    if (decryptedSummaries[id]) return decryptedSummaries[id];
    if (doc.summary?.length > 0 && doc.summary[0]) return doc.summary[0];
    return null;
  }

  async function loadSummariesForDocs(docs) {
    const backend = getBackend();
    if (!backend || docs.length === 0) {
      decryptedSummaries = {};
      loadedSummaryIds = new Set();
      return;
    }

    const token = ++summaryLoadToken;
    const visibleIds = new Set(docs.map(d => Number(d.id)));
    loadedSummaryIds = new Set([...loadedSummaryIds].filter(id => visibleIds.has(id)));
    const keptSummaries = {};
    for (const id of visibleIds) {
      if (decryptedSummaries[id]) keptSummaries[id] = decryptedSummaries[id];
    }
    if (Object.keys(keptSummaries).length !== Object.keys(decryptedSummaries).length) {
      decryptedSummaries = keptSummaries;
    }

    for (const doc of docs) {
      const id = Number(doc.id);
      if (loadedSummaryIds.has(id)) continue;

      try {
        const result = await backend.getEncryptedSummary(doc.id);
        if (token !== summaryLoadToken) return;

        if ("ok" in result) {
          const aesKey = await getDocumentKey(id);
          if (!aesKey) continue;
          const summary = await decryptText(result.ok.ciphertext, result.ok.iv, aesKey);
          decryptedSummaries = { ...decryptedSummaries, [id]: summary };
        }
        loadedSummaryIds.add(id);
      } catch (e) {
        console.warn("Summary list decrypt warning:", e);
      }
    }
  }

  $: if (!selectMode) selectedIds = new Set();
  $: allSelected = selectMode && filteredDocs.length > 0 && filteredDocs.every(d => selectedIds.has(Number(d.id)));

  function toggleSelect(docId) {
    const id = Number(docId);
    if (selectedIds.has(id)) {
      selectedIds.delete(id);
    } else {
      selectedIds.add(id);
    }
    selectedIds = selectedIds;
  }

  function toggleAll() {
    if (allSelected) {
      selectedIds = new Set();
    } else {
      selectedIds = new Set(filteredDocs.map(d => Number(d.id)));
    }
  }

  function formatSize(bytes) {
    if (bytes < 1024) return bytes + " B";
    if (bytes < 1048576) return (bytes / 1024).toFixed(1) + " KB";
    return (bytes / 1048576).toFixed(1) + " MB";
  }

  function formatDate(nanoseconds) {
    const ms = Number(nanoseconds) / 1_000_000;
    return new Date(ms).toLocaleDateString("en-US", {
      year: "numeric",
      month: "short",
      day: "numeric",
      hour: "2-digit",
      minute: "2-digit",
    });
  }

  async function deleteDoc(docId) {
    const backend = getBackend();
    if (!backend) return;
    try {
      const result = await backend.deleteDocument(docId);
      if ("ok" in result) {
        notify("Document deleted", "success");
        dispatch("refresh");
      } else {
        notify(result.err, "error");
      }
    } catch (e) {
      notify("Delete failed: " + e.message, "error");
    }
  }

  async function batchDelete() {
    if (selectedIds.size === 0) return;
    const backend = getBackend();
    if (!backend) return;
    $isLoading = true;
    let deleted = 0;
    for (const id of selectedIds) {
      try {
        const result = await backend.deleteDocument(id);
        if ("ok" in result) deleted++;
      } catch {}
    }
    $isLoading = false;
    selectedIds = new Set();
    selectMode = false;
    notify(`${deleted} document${deleted !== 1 ? 's' : ''} deleted`, "success");
    dispatch("refresh");
  }

  function viewDoc(doc) {
    dispatch("view", doc);
  }

  function batchShare() {
    dispatch("batchShare", [...selectedIds]);
  }
</script>

{#if $documents.length === 0}
  <div class="text-center py-12">
    <svg class="w-16 h-16 mx-auto text-gray-300 dark:text-gray-700" fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10" />
    </svg>
    <p class="mt-4 text-gray-500 dark:text-gray-400">No documents yet. Upload your first file!</p>
  </div>
{:else}
  <div class="flex items-center gap-2 mb-3">
    <div class="relative flex-1">
      <svg class="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
      </svg>
      <input type="text" bind:value={searchQuery} on:input={() => { aiMatchedIds = null; }}
        placeholder={aiSearching ? "AI is searching..." : "Search or ask AI..."}
        on:keydown={(e) => { if (e.key === "Enter" && searchQuery.trim()) aiSearch(); }}
        class="w-full pl-9 pr-10 py-2 text-sm border border-gray-200 dark:border-gray-700 rounded-lg bg-white dark:bg-gray-800 text-gray-900 dark:text-white focus:ring-2 focus:ring-primary-500 focus:border-transparent" />
      {#if aiMatchedIds !== null}
        <button on:click={clearAiSearch} class="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-600" title="Clear AI search">
          <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" /></svg>
        </button>
      {/if}
    </div>
    <button on:click={aiSearch} disabled={aiSearching || !searchQuery.trim()}
      class="px-3 py-2 text-sm font-medium rounded-lg transition flex items-center gap-1.5
        {aiMatchedIds !== null ? 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400' : 'bg-purple-100 text-purple-700 dark:bg-purple-900/30 dark:text-purple-400 hover:bg-purple-200 dark:hover:bg-purple-900/50'}
        disabled:opacity-50 disabled:cursor-not-allowed"
      title="AI-powered semantic search across document summaries">
      {#if aiSearching}
        <svg class="w-4 h-4 animate-spin" fill="none" viewBox="0 0 24 24"><circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle><path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"></path></svg>
      {:else}
        <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z" /></svg>
      {/if}
      AI
    </button>
    <select bind:value={sortBy}
      class="px-3 py-2 text-sm border border-gray-200 dark:border-gray-700 rounded-lg bg-white dark:bg-gray-800 text-gray-700 dark:text-gray-300">
      <option value="date">Recent</option>
      <option value="name">Name</option>
      <option value="size">Size</option>
    </select>
    <button on:click={() => selectMode = !selectMode}
      class="px-3 py-2 text-sm font-medium rounded-lg transition
        {selectMode ? 'bg-primary-600 text-white' : 'bg-gray-100 dark:bg-gray-700 text-gray-600 dark:text-gray-300 hover:bg-gray-200 dark:hover:bg-gray-600'}">
      Select
    </button>
  </div>

  {#if aiMatchedIds !== null}
    <div class="flex items-center gap-2 mb-3 p-2.5 bg-purple-50 dark:bg-purple-900/20 rounded-lg border border-purple-200 dark:border-purple-800">
      <svg class="w-4 h-4 text-purple-500 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z" /></svg>
      <span class="text-sm text-purple-700 dark:text-purple-300 flex-1">
        AI found {aiMatchedIds.size} result{aiMatchedIds.size !== 1 ? 's' : ''} for "{searchQuery}"
      </span>
      <button on:click={clearAiSearch} class="text-xs text-purple-600 hover:text-purple-800 dark:text-purple-400 font-medium">Clear</button>
    </div>
  {/if}

  {#if selectMode && selectedIds.size > 0}
    <div class="flex items-center gap-2 mb-3 p-3 bg-primary-50 dark:bg-primary-900/20 rounded-lg border border-primary-200 dark:border-primary-800">
      <span class="text-sm font-medium text-primary-700 dark:text-primary-300 flex-1">
        {selectedIds.size} selected
      </span>
      <button on:click={batchShare}
        class="px-3 py-1.5 text-xs font-medium text-primary-700 bg-primary-100 dark:bg-primary-900/40 dark:text-primary-300 rounded-lg hover:bg-primary-200 transition">
        Share All
      </button>
      <button on:click={batchDelete}
        class="px-3 py-1.5 text-xs font-medium text-red-700 bg-red-100 dark:bg-red-900/30 dark:text-red-400 rounded-lg hover:bg-red-200 transition">
        Delete All
      </button>
      <button on:click={() => { selectedIds = new Set(); selectMode = false; }}
        class="px-3 py-1.5 text-xs font-medium text-gray-600 dark:text-gray-400 hover:text-gray-800 transition">
        Cancel
      </button>
    </div>
  {/if}

  {#if selectMode}
    <div class="flex items-center gap-2 mb-2 px-1">
      <button on:click={toggleAll} class="flex items-center gap-2 text-xs text-gray-500 hover:text-gray-700 dark:hover:text-gray-300 transition">
        <div class="w-4 h-4 rounded border-2 flex items-center justify-center transition
          {allSelected ? 'bg-primary-600 border-primary-600' : 'border-gray-300 dark:border-gray-600'}">
          {#if allSelected}
            <svg class="w-3 h-3 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="3" d="M5 13l4 4L19 7" /></svg>
          {/if}
        </div>
        Select all
      </button>
    </div>
  {/if}

  <div class="grid gap-3">
    {#each filteredDocs as doc}
      <div class="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 p-4 hover:shadow-md transition-shadow
        {selectMode && selectedIds.has(Number(doc.id)) ? 'ring-2 ring-primary-500' : ''}">
        <div class="flex items-center justify-between">
          {#if selectMode}
            <button on:click|stopPropagation={() => toggleSelect(doc.id)} class="mr-3 flex-shrink-0">
              <div class="w-5 h-5 rounded border-2 flex items-center justify-center transition
                {selectedIds.has(Number(doc.id)) ? 'bg-primary-600 border-primary-600' : 'border-gray-300 dark:border-gray-600'}">
                {#if selectedIds.has(Number(doc.id))}
                  <svg class="w-3 h-3 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="3" d="M5 13l4 4L19 7" /></svg>
                {/if}
              </div>
            </button>
          {/if}
          <button on:click={() => selectMode ? toggleSelect(doc.id) : viewDoc(doc)} class="flex items-center gap-3 flex-1 text-left">
            <div class="w-10 h-10 rounded-lg bg-primary-100 dark:bg-primary-900/30 flex items-center justify-center">
              <svg class="w-5 h-5 text-primary-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
              </svg>
            </div>
            <div class="min-w-0">
              <p class="font-medium text-gray-900 dark:text-white truncate">{doc.name}</p>
              <p class="text-xs text-gray-500 dark:text-gray-400">
                {formatSize(Number(doc.size))} &middot; {formatDate(doc.updatedAt)}
              </p>
            </div>
          </button>

          <div class="flex items-center gap-2">
            {#if Number(doc.version || 1) > 1}
              <span class="px-2 py-1 text-xs font-medium bg-blue-100 dark:bg-blue-900/30 text-blue-700 dark:text-blue-400 rounded-full">
                v{Number(doc.version)}
              </span>
            {/if}
            {#if doc.certifiedHash && doc.certifiedHash.length > 0 && doc.certifiedHash[0]}
              <span class="px-1.5 py-1 text-xs font-medium bg-green-100 dark:bg-green-900/30 text-green-700 dark:text-green-400 rounded-full" title="SHA-256 hash recorded on ICP">
                <svg class="w-3.5 h-3.5 inline" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M2.166 4.999A11.954 11.954 0 0010 1.944 11.954 11.954 0 0017.834 5c.11.65.166 1.32.166 2.001 0 5.225-3.34 9.67-8 11.317C5.34 16.67 2 12.225 2 7c0-.682.057-1.35.166-2.001zm11.541 3.708a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd" /></svg>
              </span>
            {/if}
            {#if summaryFor(doc)}
              <span class="px-2 py-1 text-xs font-medium bg-green-100 dark:bg-green-900/30 text-green-700 dark:text-green-400 rounded-full">
                AI Summary
              </span>
            {/if}
            {#if doc.isEncrypted}
              <svg class="w-4 h-4 text-yellow-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
              </svg>
            {/if}
            {#if !selectMode}
              <button on:click|stopPropagation={() => deleteDoc(doc.id)} class="p-1.5 rounded-lg hover:bg-red-50 dark:hover:bg-red-900/20 text-gray-400 hover:text-red-500 transition">
                <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                </svg>
              </button>
            {/if}
          </div>
        </div>
      </div>
    {/each}
  </div>
{/if}
