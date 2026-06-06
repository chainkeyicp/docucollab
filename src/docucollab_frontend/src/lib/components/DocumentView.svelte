<script>
  import { getBackend, getAI } from "$lib/services/auth";
  import { notify, isLoading } from "$lib/stores/app";
  import { getDocumentKey, saveDocumentKey, encryptDocument, decryptDocument, decryptKeyWithPrivateKey, getPrivateKey } from "$lib/services/crypto";
  import { describeExtraction, extractTextFromBytes, isAiReadable } from "$lib/services/fileTextExtractors";
  import ShareModal from "./ShareModal.svelte";
  import { createEventDispatcher, onDestroy } from "svelte";

  const dispatch = createEventDispatcher();

  export let doc;
  let showShareModal = false;
  let textPreviewContent = null;
  let aiDocumentContent = null;
  let extractionInfo = null;
  let extractionLoading = false;
  let imageUrl = null;
  let pdfUrl = null;
  let accessList = [];
  let usernames = {};
  let versions = [];
  let activeLoadId = 0;
  let cachedDecryptedData = null;

  // AI Chat
  let chatMessages = [];
  let chatInput = "";
  let chatLoading = false;
  let keyPoints = null;
  let category = null;
  let aiMode = "onchain"; // "onchain" or "premium"

  // Integrity
  let docHashHex = null;
  let verifying = false;

  $: if (doc) loadDocument();

  onDestroy(() => {
    if (imageUrl) URL.revokeObjectURL(imageUrl);
    if (pdfUrl) URL.revokeObjectURL(pdfUrl);
  });

  async function resolveDocumentKey(candidateAccessList = accessList) {
    let aesKey = await getDocumentKey(Number(doc.id));
    if (aesKey) return aesKey;

    const privateKey = await getPrivateKey();
    if (!privateKey) return null;

    let candidates = candidateAccessList || [];
    if (candidates.length === 0) {
      const backend = getBackend();
      if (backend) {
        const docResult = await backend.getDocument(doc.id);
        if ("ok" in docResult) {
          candidates = docResult.ok.accessList;
          accessList = candidates;
        }
      }
    }

    for (const acc of candidates) {
      const wrappedKey = acc.encryptedKey ? new Uint8Array(acc.encryptedKey) : new Uint8Array(0);
      if (wrappedKey.length === 0) continue;
      try {
        aesKey = await decryptKeyWithPrivateKey(wrappedKey, privateKey);
        await saveDocumentKey(Number(doc.id), aesKey);
        return aesKey;
      } catch {}
    }

    return null;
  }

  function resetLoadedContent() {
    if (imageUrl) URL.revokeObjectURL(imageUrl);
    if (pdfUrl) URL.revokeObjectURL(pdfUrl);
    textPreviewContent = null;
    aiDocumentContent = null;
    extractionInfo = null;
    extractionLoading = false;
    cachedDecryptedData = null;
    imageUrl = null;
    pdfUrl = null;
    docHashHex = null;
    keyPoints = null;
    category = null;
    chatMessages = [];
  }

  function applyExtraction(extraction) {
    extractionInfo = extraction;
    if (isAiReadable(extraction)) {
      aiDocumentContent = extraction.text;
      if (!imageUrl && !pdfUrl) {
        textPreviewContent = extraction.text;
      }
    }
  }

  async function loadDocument() {
    const backend = getBackend();
    if (!backend || !doc) return;
    const loadId = ++activeLoadId;
    resetLoadedContent();

    try {
      const result = await backend.getDocument(doc.id);
      if ("ok" in result) {
        accessList = result.ok.accessList;
        // Resolve usernames
        for (const acc of accessList) {
          const pid = acc.grantedTo.toText();
          if (!usernames[pid]) {
            try {
              const u = await backend.getUser(acc.grantedTo);
              if (u && u.length > 0) usernames[pid] = u[0].username;
            } catch {}
          }
        }
        usernames = usernames; // trigger reactivity
      }

      // Load version history
      try {
        versions = await backend.getVersions(doc.id);
      } catch { versions = []; }

      // Load document hash
      try {
        const hashResult = await backend.getDocumentHashHex(doc.id);
        if ("ok" in hashResult) docHashHex = hashResult.ok;
      } catch { docHashHex = null; }

      // Load and preview content based on file type
      const allChunks = [];
      for (let i = 0; i < Number(doc.totalChunks); i++) {
        const chunkResult = await backend.downloadChunk(doc.id, i);
        if ("ok" in chunkResult) {
          allChunks.push(chunkResult.ok);
        }
      }
      const combined = new Uint8Array(allChunks.reduce((acc, c) => acc + c.length, 0));
      let offset = 0;
      for (const chunk of allChunks) {
        combined.set(new Uint8Array(chunk), offset);
        offset += chunk.length;
      }

      // Decrypt if encrypted
      let finalData = combined;
      if (doc.isEncrypted) {
        try {
          const aesKey = await resolveDocumentKey(accessList);
          if (aesKey) {
            const decrypted = await decryptDocument(combined, aesKey);
            finalData = new Uint8Array(decrypted);
          } else {
            notify("Cannot decrypt: encryption key not available", "error");
            return;
          }
        } catch (e) {
          console.error("Decryption error:", e);
          notify("Decryption failed: " + e.message, "error");
          return;
        }
      }

      if (loadId !== activeLoadId) return;
      cachedDecryptedData = finalData.slice();

      const previewBytes = finalData.slice();

      if (doc.mimeType.startsWith("image/")) {
        const blob = new Blob([previewBytes], { type: doc.mimeType });
        imageUrl = URL.createObjectURL(blob);
      } else if (doc.mimeType === "application/pdf" || doc.name.toLowerCase().endsWith(".pdf")) {
        const blob = new Blob([previewBytes], { type: "application/pdf" });
        pdfUrl = URL.createObjectURL(blob);
      }

      extractionLoading = true;
      try {
        const extraction = await extractTextFromBytes(finalData.slice(), {
          name: doc.name,
          mimeType: doc.mimeType,
        });
        if (loadId !== activeLoadId) return;
        applyExtraction(extraction);
      } catch (extractErr) {
        console.warn("Text extraction failed, preview unaffected:", extractErr);
      }
    } catch (e) {
      console.error("Load error:", e);
    } finally {
      if (loadId === activeLoadId) extractionLoading = false;
    }
  }

  async function downloadFile() {
    const backend = getBackend();
    if (!backend) return;

    $isLoading = true;
    try {
      let finalData = cachedDecryptedData;

      if (!finalData) {
        const chunks = [];
        for (let i = 0; i < Number(doc.totalChunks); i++) {
          const result = await backend.downloadChunk(doc.id, i);
          if ("ok" in result) {
            chunks.push(result.ok);
          }
        }
        const combined = new Uint8Array(chunks.reduce((acc, c) => acc + c.length, 0));
        let offset = 0;
        for (const chunk of chunks) {
          combined.set(new Uint8Array(chunk), offset);
          offset += chunk.length;
        }

        finalData = combined;
        if (doc.isEncrypted) {
          const aesKey = await resolveDocumentKey(accessList);
          if (aesKey) {
            finalData = new Uint8Array(await decryptDocument(combined, aesKey));
          } else {
            notify("Cannot decrypt: encryption key not available", "error");
            return;
          }
        }
      }

      const blob = new Blob([new Uint8Array(finalData)], { type: doc.mimeType });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = doc.name;
      a.style.display = "none";
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      setTimeout(() => URL.revokeObjectURL(url), 60000);
    } catch (e) {
      notify("Download failed: " + e.message, "error");
    } finally {
      $isLoading = false;
    }
  }

  let versionFileInput;

  async function uploadNewVersion(e) {
    const file = e.target.files[0];
    if (!file) return;
    const backend = getBackend();
    if (!backend) return;

    $isLoading = true;
    try {
      const arrayBuffer = await file.arrayBuffer();
      const CHUNK_SIZE = 1024 * 1024;
      let uploadData = new Uint8Array(arrayBuffer);
      let textContent = null;

      const extraction = await extractTextFromBytes(arrayBuffer.slice(0), {
        name: file.name,
        mimeType: file.type,
      });
      const extractionDetail = describeExtraction(extraction);
      if (isAiReadable(extraction)) textContent = extraction.text;

      if (doc.isEncrypted) {
        const aesKey = await resolveDocumentKey(accessList);
        if (!aesKey) {
          notify("Cannot update encrypted document: owner encryption key is not available", "error");
          return;
        }
        uploadData = await encryptDocument(arrayBuffer, aesKey);
      }

      const totalChunks = Math.ceil(uploadData.byteLength / CHUNK_SIZE);

      const result = await backend.uploadNewVersion(doc.id, uploadData.byteLength, totalChunks);
      if ("err" in result) {
        notify(result.err, "error");
        return;
      }

      for (let i = 0; i < totalChunks; i++) {
        const start = i * CHUNK_SIZE;
        const end = Math.min(start + CHUNK_SIZE, uploadData.byteLength);
        const chunk = new Uint8Array(uploadData.slice(start, end));
        const chunkResult = await backend.uploadChunk(doc.id, i, chunk);
        if ("err" in chunkResult) {
          notify(`Chunk upload failed: ${chunkResult.err}`, "error");
          return;
        }
      }

      try {
        await backend.finalizeDocument(doc.id);
      } catch (e) {
        console.warn("Finalize warning:", e);
      }

      let summaryUpdated = false;
      if (textContent) {
        try {
          const ai = getAI();
          if (ai) {
            const summary = await ai.summarizeText(textContent);
            if ("ok" in summary) {
              await backend.setSummary(doc.id, summary.ok);
              summaryUpdated = true;
            }
          }
        } catch (e) {
          console.warn("Summary refresh warning:", e);
        }
      }

      notify(
        summaryUpdated
          ? `Version ${Number(result.ok)} uploaded and AI summary refreshed.`
          : `Version ${Number(result.ok)} uploaded. ${textContent ? "AI summary refresh skipped." : extractionDetail}`,
        summaryUpdated || textContent ? "success" : "info"
      );
      dispatch("close");
    } catch (e) {
      notify("Version upload failed: " + e.message, "error");
    } finally {
      $isLoading = false;
    }
  }

  async function sendChat() {
    if (!chatInput.trim() || !aiDocumentContent) return;
    const ai = getAI();
    if (!ai) return;

    const question = chatInput.trim();
    chatMessages = [...chatMessages, { role: "user", text: question }];
    chatInput = "";
    chatLoading = true;

    try {
      const result = await ai.chatWithDocument(aiDocumentContent, question);
      if ("ok" in result) {
        chatMessages = [...chatMessages, { role: "ai", text: result.ok }];
      } else {
        chatMessages = [...chatMessages, { role: "ai", text: "Error: " + result.err }];
      }
    } catch (e) {
      chatMessages = [...chatMessages, { role: "ai", text: "Error: " + e.message }];
    } finally {
      chatLoading = false;
    }
  }

  async function fetchKeyPoints() {
    if (!aiDocumentContent) return;
    const ai = getAI();
    if (!ai) return;

    chatLoading = true;
    try {
      const result = await ai.extractKeyPoints(aiDocumentContent);
      if ("ok" in result) keyPoints = result.ok;
      else notify("Failed: " + result.err, "error");
    } catch (e) {
      notify("Error: " + e.message, "error");
    } finally {
      chatLoading = false;
    }
  }

  async function fetchCategory() {
    if (!aiDocumentContent) return;
    const ai = getAI();
    if (!ai) return;

    chatLoading = true;
    try {
      const result = await ai.categorizeDocument(aiDocumentContent);
      if ("ok" in result) category = result.ok.trim();
      else notify("Failed: " + result.err, "error");
    } catch (e) {
      notify("Error: " + e.message, "error");
    } finally {
      chatLoading = false;
    }
  }

  async function verifyIntegrity() {
    if (!doc) return;
    const backend = getBackend();
    if (!backend) return;

    verifying = true;
    try {
      // Download all chunks and compute SHA-256 client-side
      const allChunks = [];
      for (let i = 0; i < Number(doc.totalChunks); i++) {
        const chunkResult = await backend.downloadChunk(doc.id, i);
        if ("ok" in chunkResult) allChunks.push(new Uint8Array(chunkResult.ok));
      }
      const combined = new Uint8Array(allChunks.reduce((acc, c) => acc + c.length, 0));
      let offset = 0;
      for (const chunk of allChunks) {
        combined.set(chunk, offset);
        offset += chunk.length;
      }
      const hashBuffer = await crypto.subtle.digest("SHA-256", combined);
      const hashArray = Array.from(new Uint8Array(hashBuffer));
      const clientHash = hashArray.map(b => b.toString(16).padStart(2, "0")).join("");

      if (clientHash === docHashHex) {
        notify("Document integrity verified! SHA-256 hash matches.", "success");
      } else {
        notify("WARNING: Document integrity check FAILED! Hash mismatch.", "error");
      }
    } catch (e) {
      notify("Verification error: " + e.message, "error");
    } finally {
      verifying = false;
    }
  }

  async function regenerateSummary() {
    if (!aiDocumentContent) return;
    const ai = getAI();
    const backend = getBackend();
    if (!ai || !backend) return;

    chatLoading = true;
    try {
      const result = aiMode === "premium"
        ? await ai.summarizeTextPremium(aiDocumentContent)
        : await ai.summarizeOnChain(aiDocumentContent);
      if ("ok" in result) {
        await backend.setSummary(doc.id, result.ok);
        doc.summary = [result.ok];
        notify("Summary regenerated!", "success");
      } else {
        notify("Failed: " + result.err, "error");
      }
    } catch (e) {
      notify("Error: " + e.message, "error");
    } finally {
      chatLoading = false;
    }
  }

  function formatDate(nanoseconds) {
    const ms = Number(nanoseconds) / 1_000_000;
    return new Date(ms).toLocaleDateString("en-US", {
      year: "numeric", month: "short", day: "numeric",
      hour: "2-digit", minute: "2-digit",
    });
  }

  function formatSize(bytes) {
    if (bytes < 1024) return bytes + " B";
    if (bytes < 1048576) return (bytes / 1024).toFixed(1) + " KB";
    return (bytes / 1048576).toFixed(1) + " MB";
  }

  function close() {
    dispatch("close");
  }
</script>

<div class="bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 overflow-hidden">
  <!-- Header -->
  <div class="border-b border-gray-200 dark:border-gray-700 p-4 flex items-center justify-between">
    <div class="flex items-center gap-3">
      <button on:click={close} class="p-1 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700">
        <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
        </svg>
      </button>
      <div>
        <h2 class="font-semibold text-gray-900 dark:text-white">{doc.name}</h2>
        <p class="text-xs text-gray-500">{formatSize(Number(doc.size))} &middot; {formatDate(doc.updatedAt)}</p>
      </div>
    </div>
    <div class="flex items-center gap-2">
      <input type="file" bind:this={versionFileInput} on:change={uploadNewVersion} class="hidden" />
      <button on:click={() => versionFileInput.click()}
        class="px-3 py-1.5 text-sm font-medium text-gray-600 dark:text-gray-400 bg-gray-100 dark:bg-gray-700 rounded-lg hover:bg-gray-200 dark:hover:bg-gray-600 transition">
        Update
      </button>
      <button on:click={() => showShareModal = true}
        class="px-3 py-1.5 text-sm font-medium text-primary-600 bg-primary-50 dark:bg-primary-900/20 rounded-lg hover:bg-primary-100 dark:hover:bg-primary-900/40 transition">
        Share
      </button>
      <button on:click={downloadFile}
        class="px-3 py-1.5 text-sm font-medium text-white bg-primary-600 rounded-lg hover:bg-primary-700 transition">
        Download
      </button>
    </div>
  </div>

  <div class="grid grid-cols-1 lg:grid-cols-3 divide-y lg:divide-y-0 lg:divide-x divide-gray-200 dark:divide-gray-700">
    <!-- Content -->
    <div class="lg:col-span-2 p-4 min-h-[200px] sm:min-h-[300px] max-h-[400px] sm:max-h-[600px] overflow-auto">
      {#if textPreviewContent !== null}
        <pre class="text-sm text-gray-800 dark:text-gray-200 whitespace-pre-wrap font-mono">{textPreviewContent}</pre>
      {:else if imageUrl}
        <div class="flex items-center justify-center h-full">
          <img src={imageUrl} alt={doc.name} class="max-w-full max-h-[580px] rounded-lg object-contain" />
        </div>
      {:else if pdfUrl}
        <iframe src={pdfUrl} title={doc.name} class="w-full h-full min-h-[580px] rounded-lg border-0"></iframe>
      {:else}
        <div class="flex items-center justify-center h-full text-gray-400">
          <p>Preview not available for this file type. Click Download to view.</p>
        </div>
      {/if}
    </div>

    <!-- AI Summary & Info Panel -->
    <div class="p-4 space-y-4">
      <!-- AI Mode Toggle -->
      <div class="flex items-center gap-2">
        <button on:click={() => aiMode = "onchain"}
          class="flex-1 px-2 py-1 text-xs font-medium rounded-lg transition {aiMode === 'onchain' ? 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400' : 'text-gray-500 hover:bg-gray-100 dark:hover:bg-gray-700'}">
          On-Chain AI
        </button>
        <button on:click={() => aiMode = "premium"}
          class="flex-1 px-2 py-1 text-xs font-medium rounded-lg transition {aiMode === 'premium' ? 'bg-purple-100 text-purple-700 dark:bg-purple-900/30 dark:text-purple-400' : 'text-gray-500 hover:bg-gray-100 dark:hover:bg-gray-700'}">
          Premium AI
        </button>
      </div>

      <!-- AI Summary -->
      <div>
        <div class="flex items-center justify-between mb-2">
          <h3 class="text-sm font-semibold text-gray-900 dark:text-white">AI Summary</h3>
          {#if aiDocumentContent}
            <button on:click={regenerateSummary} disabled={chatLoading}
              class="text-xs text-primary-600 hover:text-primary-700 disabled:opacity-50">
              {chatLoading ? "..." : "Regenerate"}
            </button>
          {/if}
        </div>
        {#if doc.summary && doc.summary.length > 0 && doc.summary[0]}
          <p class="text-sm text-gray-600 dark:text-gray-400 leading-relaxed whitespace-pre-line">{doc.summary[0]}</p>
        {:else}
          <p class="text-sm text-gray-400 italic">No summary yet — it may still be generating.</p>
        {/if}
      </div>

      {#if extractionLoading}
        <div class="text-xs text-gray-500 dark:text-gray-400 bg-gray-50 dark:bg-gray-700/50 rounded-lg p-2">
          Extracting AI-readable text...
        </div>
      {:else if extractionInfo}
        <div class="text-xs text-gray-500 dark:text-gray-400 bg-gray-50 dark:bg-gray-700/50 rounded-lg p-2 space-y-1">
          <p class="font-medium text-gray-700 dark:text-gray-300">AI Source</p>
          <p>{describeExtraction(extractionInfo)}</p>
          {#if extractionInfo.text && extractionInfo.warnings.length > 0}
            <p>{extractionInfo.warnings[0]}</p>
          {/if}
        </div>
      {/if}

      <!-- Category Badge -->
      {#if category}
        <div class="flex items-center gap-2">
          <span class="text-xs font-medium text-gray-500">Category:</span>
          <span class="px-2 py-0.5 text-xs font-medium bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400 rounded-full">{category}</span>
        </div>
      {/if}

      <!-- AI Quick Actions -->
      {#if aiDocumentContent}
        <div class="flex gap-2">
          <button on:click={fetchKeyPoints} disabled={chatLoading}
            class="flex-1 px-2 py-1.5 text-xs font-medium text-gray-600 dark:text-gray-400 bg-gray-100 dark:bg-gray-700 rounded-lg hover:bg-gray-200 dark:hover:bg-gray-600 transition disabled:opacity-50">
            Key Points
          </button>
          <button on:click={fetchCategory} disabled={chatLoading}
            class="flex-1 px-2 py-1.5 text-xs font-medium text-gray-600 dark:text-gray-400 bg-gray-100 dark:bg-gray-700 rounded-lg hover:bg-gray-200 dark:hover:bg-gray-600 transition disabled:opacity-50">
            Categorize
          </button>
        </div>
      {/if}

      <!-- Key Points -->
      {#if keyPoints}
        <div>
          <h3 class="text-sm font-semibold text-gray-900 dark:text-white mb-2">Key Points</h3>
          <p class="text-sm text-gray-600 dark:text-gray-400 leading-relaxed whitespace-pre-line">{keyPoints}</p>
        </div>
      {/if}

      <!-- AI Chat -->
      {#if aiDocumentContent}
        <div>
          <h3 class="text-sm font-semibold text-gray-900 dark:text-white mb-2">Ask AI about this document</h3>
          <div class="space-y-2 max-h-[200px] overflow-auto mb-2">
            {#each chatMessages as msg}
              <div class="text-xs p-2 rounded-lg {msg.role === 'user' ? 'bg-primary-50 dark:bg-primary-900/20 text-primary-700 dark:text-primary-300 ml-4' : 'bg-gray-50 dark:bg-gray-700/50 text-gray-600 dark:text-gray-400 mr-4'}">
                {msg.text}
              </div>
            {/each}
            {#if chatLoading}
              <div class="text-xs text-gray-400 animate-pulse p-2">Thinking...</div>
            {/if}
          </div>
          <form on:submit|preventDefault={sendChat} class="flex gap-2">
            <input bind:value={chatInput} placeholder="Ask a question..."
              class="flex-1 px-3 py-1.5 text-sm rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white focus:ring-1 focus:ring-primary-500 focus:border-primary-500" />
            <button type="submit" disabled={chatLoading || !chatInput.trim()}
              class="px-3 py-1.5 text-sm font-medium text-white bg-primary-600 rounded-lg hover:bg-primary-700 transition disabled:opacity-50">
              Send
            </button>
          </form>
        </div>
      {/if}

      {#if accessList.length > 0}
        <div>
          <h3 class="text-sm font-semibold text-gray-900 dark:text-white mb-2">Shared With</h3>
          <div class="space-y-2">
            {#each accessList as acc}
              <div class="flex items-center justify-between text-xs">
                <span class="text-gray-600 dark:text-gray-400 truncate" title={acc.grantedTo.toText()}>
                  {usernames[acc.grantedTo.toText()] || acc.grantedTo.toText().slice(0, 20) + "..."}
                </span>
                <span class="text-gray-400">{formatDate(acc.grantedAt)}</span>
              </div>
            {/each}
          </div>
        </div>
      {/if}

      <div>
        <h3 class="text-sm font-semibold text-gray-900 dark:text-white mb-2">Details</h3>
        <dl class="space-y-1 text-xs">
          <div class="flex justify-between">
            <dt class="text-gray-500">Type</dt>
            <dd class="text-gray-700 dark:text-gray-300">{doc.mimeType}</dd>
          </div>
          <div class="flex justify-between">
            <dt class="text-gray-500">Created</dt>
            <dd class="text-gray-700 dark:text-gray-300">{formatDate(doc.createdAt)}</dd>
          </div>
          <div class="flex justify-between">
            <dt class="text-gray-500">Encrypted</dt>
            <dd class="text-gray-700 dark:text-gray-300">{doc.isEncrypted ? "Yes" : "No"}</dd>
          </div>
          <div class="flex justify-between">
            <dt class="text-gray-500">Version</dt>
            <dd class="text-gray-700 dark:text-gray-300">v{Number(doc.version || 1)}</dd>
          </div>
          <div class="flex justify-between items-center">
            <dt class="text-gray-500">Integrity</dt>
            <dd>
              {#if docHashHex}
                <span class="inline-flex items-center gap-1 px-2 py-0.5 text-xs font-medium bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400 rounded-full">
                  <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M10 1a4.5 4.5 0 00-4.5 4.5V9H5a2 2 0 00-2 2v6a2 2 0 002 2h10a2 2 0 002-2v-6a2 2 0 00-2-2h-.5V5.5A4.5 4.5 0 0010 1zm3 8V5.5a3 3 0 10-6 0V9h6z" clip-rule="evenodd" /></svg>
                  Hash stored
                </span>
              {:else}
                <span class="text-gray-400 text-xs">Not certified</span>
              {/if}
            </dd>
          </div>
        </dl>

        {#if docHashHex}
          <div class="mt-2 p-2 bg-gray-50 dark:bg-gray-700/50 rounded-lg">
            <p class="text-xs text-gray-500 mb-1">SHA-256 Hash:</p>
            <p class="text-xs font-mono text-gray-600 dark:text-gray-400 break-all">{docHashHex}</p>
            <button on:click={verifyIntegrity} disabled={verifying}
              class="mt-2 w-full px-2 py-1 text-xs font-medium text-green-700 dark:text-green-400 bg-green-50 dark:bg-green-900/20 rounded hover:bg-green-100 dark:hover:bg-green-900/30 transition disabled:opacity-50">
              {verifying ? "Verifying..." : "Verify Integrity"}
            </button>
          </div>
        {/if}
      </div>

      {#if versions.length > 0}
        <div>
          <h3 class="text-sm font-semibold text-gray-900 dark:text-white mb-2">Version History</h3>
          <div class="space-y-2">
            <div class="flex items-center justify-between text-xs p-2 bg-primary-50 dark:bg-primary-900/20 rounded">
              <span class="font-medium text-primary-700 dark:text-primary-400">v{Number(doc.version || 1)} (current)</span>
              <span class="text-gray-400">{formatSize(Number(doc.size))}</span>
            </div>
            {#each [...versions].reverse() as ver}
              <div class="flex items-center justify-between text-xs p-2 bg-gray-50 dark:bg-gray-700/50 rounded">
                <span class="text-gray-600 dark:text-gray-400">v{Number(ver.version)}</span>
                <span class="text-gray-400">{formatSize(Number(ver.size))} &middot; {formatDate(ver.updatedAt)}</span>
              </div>
            {/each}
          </div>
        </div>
      {/if}
    </div>
  </div>
</div>

{#if showShareModal}
  <ShareModal {doc} on:close={() => showShareModal = false} on:shared={loadDocument} />
{/if}
