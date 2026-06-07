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

  function relTime(nanoseconds) {
    const ms = Number(nanoseconds) / 1_000_000;
    const diff = (Date.now() - ms) / 1000;
    if (diff < 3600) return Math.max(1, Math.floor(diff / 60)) + "m ago";
    if (diff < 86400) return Math.floor(diff / 3600) + "h ago";
    if (diff < 86400 * 30) return Math.floor(diff / 86400) + "d ago";
    return new Date(ms).toLocaleDateString("en-US", { month: "short", day: "numeric" });
  }

  function fileTypeMeta(doc) {
    const ext = doc.name?.split('.').pop()?.toLowerCase() || '';
    const mime = doc.mimeType || '';
    if (ext === 'pdf' || mime.includes('pdf')) return { tint: '#fb6a6a', icon: 'pdf' };
    if (['png','jpg','jpeg','gif','webp','svg','bmp'].includes(ext) || mime.startsWith('image/')) return { tint: '#19e08a', icon: 'image' };
    if (['xlsx','xls','csv'].includes(ext) || mime.includes('sheet') || mime.includes('csv')) return { tint: '#19c08a', icon: 'table' };
    if (['doc','docx'].includes(ext) || mime.includes('word')) return { tint: '#3b82f6', icon: 'doc' };
    if (['md','markdown'].includes(ext)) return { tint: '#29c5f6', icon: 'doc' };
    if (['txt','text'].includes(ext) || mime.includes('text/plain')) return { tint: '#9b8bf0', icon: 'doc' };
    return { tint: '#7c7b90', icon: 'doc' };
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
  <div class="glass rounded-[var(--r-lg)] py-11 text-center" style="color: var(--text-4);">
    <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" class="mx-auto mb-4 opacity-40"><path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" /></svg>
    <p class="text-sm">No documents yet. Upload your first file!</p>
  </div>
{:else}
  <!-- Search + Controls -->
  <div class="flex items-center gap-2.5 mb-4 flex-wrap">
    <div class="glass flex items-center gap-2 px-3 py-2 rounded-[10px] flex-1 min-w-[200px]">
      <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" style="color: var(--text-4);"><path d="M11 19a8 8 0 1 0 0-16 8 8 0 0 0 0 16z M21 21l-4.3-4.3" /></svg>
      <input type="text" bind:value={searchQuery} on:input={() => { aiMatchedIds = null; }}
        placeholder={aiSearching ? "AI is searching..." : "Search name or AI summary..."}
        on:keydown={(e) => { if (e.key === "Enter" && searchQuery.trim()) aiSearch(); }}
        class="bg-transparent border-none outline-none text-[13px] w-full" style="color: var(--text);" />
      {#if aiMatchedIds !== null}
        <button on:click={clearAiSearch} style="color: var(--text-4);" title="Clear AI search">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M6 6l12 12 M18 6L6 18" /></svg>
        </button>
      {/if}
    </div>

    <button on:click={aiSearch} disabled={aiSearching || !searchQuery.trim()}
      class="btn-ghost px-3 py-2 text-[13px] flex items-center gap-1.5 disabled:opacity-40"
      style="color: {aiMatchedIds !== null ? 'var(--green)' : 'var(--icp-pink)'};"
      title="AI-powered semantic search">
      {#if aiSearching}
        <div class="w-3.5 h-3.5 rounded-full anim-spin" style="border: 1.5px solid var(--surface-hi); border-top-color: var(--icp-pink);"></div>
      {:else}
        <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor" stroke="none"><path d="M13 2L4.5 13.5H11l-1 8.5L19.5 10H13z" /></svg>
      {/if}
      AI
    </button>

    <select bind:value={sortBy}
      class="glass px-3 py-2 rounded-[10px] text-[13px] outline-none cursor-pointer" style="color: var(--text-2);">
      <option value="date" style="background: var(--bg-2);">Recent</option>
      <option value="name" style="background: var(--bg-2);">Name</option>
      <option value="size" style="background: var(--bg-2);">Size</option>
    </select>

    <button on:click={() => selectMode = !selectMode}
      class="{selectMode ? 'btn-grad' : 'btn-ghost'} px-3.5 py-2 text-[13px] flex items-center gap-1.5">
      <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5l4.5 4.5L19 7" /></svg>
      Select
    </button>
  </div>

  <!-- AI search results banner -->
  {#if aiMatchedIds !== null}
    <div class="glass scale-in flex items-center gap-2.5 p-3 rounded-xl mb-3.5"
      style="border-color: color-mix(in srgb, var(--icp-pink) 35%, transparent);">
      <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor" stroke="none" style="color: var(--icp-pink); flex-shrink: 0;"><path d="M13 2L4.5 13.5H11l-1 8.5L19.5 10H13z" /></svg>
      <span class="text-[13px] flex-1" style="color: var(--text-2);">
        AI found {aiMatchedIds.size} result{aiMatchedIds.size !== 1 ? 's' : ''} for "{searchQuery}"
      </span>
      <button on:click={clearAiSearch} class="text-xs font-semibold" style="color: var(--icp-cyan);">Clear</button>
    </div>
  {/if}

  <!-- Batch action bar -->
  {#if selectMode && selectedIds.size > 0}
    <div class="glass scale-in flex items-center justify-between p-3 rounded-xl mb-3.5"
      style="border-color: color-mix(in srgb, var(--icp-pink) 35%, transparent);">
      <span class="text-[13.5px] font-semibold">{selectedIds.size} selected</span>
      <div class="flex gap-2.5">
        <button on:click={batchShare} class="btn-ghost px-3.5 py-1.5 text-[13px] flex items-center gap-1.5">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M18 8a3 3 0 1 0 0-6 3 3 0 0 0 0 6z M6 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z M18 22a3 3 0 1 0 0-6 3 3 0 0 0 0 6z M8.6 13.5l6.8 4 M15.4 6.5l-6.8 4" /></svg>
          Share
        </button>
        <button on:click={batchDelete} class="btn-ghost px-3.5 py-1.5 text-[13px] flex items-center gap-1.5" style="color: var(--red);">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 7h16 M9 7V5a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2 M6 7l1 13a1 1 0 0 0 1 1h8a1 1 0 0 0 1-1l1-13 M10 11v6 M14 11v6" /></svg>
          Delete
        </button>
      </div>
    </div>
  {/if}

  <!-- Select all -->
  {#if selectMode}
    <div class="flex items-center gap-2 mb-2.5 px-1">
      <button on:click={toggleAll} class="flex items-center gap-2 text-xs transition" style="color: var(--text-3);">
        <div class="w-5 h-5 rounded-md grid place-items-center" style="background: {allSelected ? 'var(--grad-icp)' : 'var(--surface-hi)'}; border: 1px solid {allSelected ? 'transparent' : 'var(--border-hi)'}; color: #fff;">
          {#if allSelected}
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5l4.5 4.5L19 7" /></svg>
          {/if}
        </div>
        Select all
      </button>
    </div>
  {/if}

  <!-- Document list -->
  <div class="flex flex-col gap-2.5">
    {#each filteredDocs as doc}
      {@const meta = fileTypeMeta(doc)}
      {@const selected = selectedIds.has(Number(doc.id))}
      <div
        on:click={() => selectMode ? toggleSelect(doc.id) : viewDoc(doc)}
        on:keydown={(e) => e.key === 'Enter' && (selectMode ? toggleSelect(doc.id) : viewDoc(doc))}
        role="button"
        tabindex="0"
        class="glass rounded-[var(--r-md)] p-3.5 flex items-center gap-3.5 cursor-pointer transition-all"
        style="border-color: {selected ? 'color-mix(in srgb, var(--icp-pink) 45%, transparent)' : 'var(--border)'};
          background: {selected ? 'color-mix(in srgb, var(--icp-pink) 8%, var(--surface))' : 'var(--surface)'};"
      >
        {#if selectMode}
          <div class="w-5 h-5 rounded-md grid place-items-center flex-shrink-0"
            style="background: {selected ? 'var(--grad-icp)' : 'var(--surface-hi)'}; border: 1px solid {selected ? 'transparent' : 'var(--border-hi)'}; color: #fff;">
            {#if selected}
              <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5l4.5 4.5L19 7" /></svg>
            {/if}
          </div>
        {/if}

        <!-- File glyph -->
        <div class="w-[42px] h-[42px] rounded-xl grid place-items-center flex-shrink-0"
          style="background: color-mix(in srgb, {meta.tint} 13%, transparent); border: 1px solid color-mix(in srgb, {meta.tint} 26%, transparent); color: {meta.tint};">
          {#if meta.icon === 'pdf'}
            <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M14 3v4a1 1 0 0 0 1 1h4 M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z" /></svg>
          {:else if meta.icon === 'image'}
            <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 4h16a1 1 0 0 1 1 1v14a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1z M8.5 10a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3z M21 16l-5-5L5 21" /></svg>
          {:else if meta.icon === 'table'}
            <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 4h16a1 1 0 0 1 1 1v14a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1z M3 10h18 M3 15h18 M9 5v15 M15 5v15" /></svg>
          {:else}
            <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M14 3v4a1 1 0 0 0 1 1h4 M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z" /></svg>
          {/if}
        </div>

        <!-- Info -->
        <div class="flex-1 min-w-0">
          <div class="flex items-center gap-2.5">
            <span class="font-semibold text-[14.5px] truncate" style="color: var(--text);">{doc.name}</span>
            {#if Number(doc.version || 1) > 1}
              <span class="mono text-[10.5px] font-semibold flex-shrink-0 px-1.5 rounded-full"
                style="color: var(--icp-cyan); background: color-mix(in srgb, var(--icp-cyan) 12%, transparent);">v{Number(doc.version)}</span>
            {/if}
          </div>
          <div class="flex items-center gap-2.5 mt-0.5 text-xs whitespace-nowrap" style="color: var(--text-3);">
            <span>{formatSize(Number(doc.size))}</span>
            <span style="color: var(--text-4);">·</span>
            <span>{relTime(doc.updatedAt)}</span>
            {#if doc.isEncrypted}
              <span style="color: var(--text-4);">·</span>
              <span class="inline-flex items-center gap-1" style="color: var(--green);">
                <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M5 11h14a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1v-8a1 1 0 0 1 1-1z M8 11V7a4 4 0 0 1 8 0v4" /></svg>
                encrypted
              </span>
            {/if}
          </div>
        </div>

        <!-- Badges -->
        <div class="flex items-center gap-2 flex-shrink-0">
          {#if summaryFor(doc)}
            <span class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10.5px] font-semibold"
              style="color: var(--icp-pink); background: color-mix(in srgb, var(--icp-pink) 12%, transparent);">
              <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M12 3v3 M12 18v3 M5.6 5.6l2.1 2.1 M16.3 16.3l2.1 2.1 M3 12h3 M18 12h3 M5.6 18.4l2.1-2.1 M16.3 7.7l2.1-2.1" /></svg>
              AI
            </span>
          {/if}
          {#if doc.certifiedHash && doc.certifiedHash.length > 0 && doc.certifiedHash[0]}
            <span class="grid place-items-center" style="color: var(--green);" title="SHA-256 hash verified">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3l7 3v5c0 4.5-3 8.3-7 9.5C8 19.3 5 15.5 5 11V6z M9 11.5l2 2 4-4" /></svg>
            </span>
          {/if}
        </div>

        {#if !selectMode}
          <button on:click|stopPropagation={() => deleteDoc(doc.id)}
            class="p-1.5 rounded-lg transition opacity-40 hover:opacity-100 flex-shrink-0" style="color: var(--red);"
            title="Delete document">
            <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 7h16 M9 7V5a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2 M6 7l1 13a1 1 0 0 0 1 1h8a1 1 0 0 0 1-1l1-13 M10 11v6 M14 11v6" /></svg>
          </button>
          <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" class="flex-shrink-0" style="color: var(--text-4);"><path d="M9 6l6 6-6 6" /></svg>
        {/if}
      </div>
    {/each}
  </div>
{/if}
