<script>
  import { getBackend, getAI } from "$lib/services/auth";
  import { notify, isLoading, userProfile } from "$lib/stores/app";
  import { getDocumentKey, saveDocumentKey, encryptDocument, decryptDocument, encryptText, decryptText, decryptKeyWithPrivateKey, getPrivateKey, importPublicKey, encryptKeyForRecipient } from "$lib/services/crypto";
  import { describeExtraction, extractTextFromBytes, isAiReadable } from "$lib/services/fileTextExtractors";
  import ShareModal from "./ShareModal.svelte";
  import IntegrityProof from "./IntegrityProof.svelte";
  import { createEventDispatcher, onDestroy } from "svelte";

  const dispatch = createEventDispatcher();
  const MAX_ORIGINAL_FILE_SIZE = 50 * 1024 * 1024 - 1024; // leave room for AES-GCM overhead

  export let doc;
  export let isOwner = true;
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
  let decryptedSummary = null;
  let hasEncryptedSummary = false;
  let summaryLoading = false;

  // AI Chat
  let chatMessages = [];
  let chatInput = "";
  let chatLoading = false;
  let keyPoints = null;
  let category = null;
  let aiMode = "onchain";

  // Integrity
  let docHashHex = null;
  let verifying = false;
  let showIntegrityProof = false;

  // Tabs
  let leftTab = "preview"; // "preview" or "details"

  $: if (doc) loadDocument();
  $: legacySummary = doc?.summary && doc.summary.length > 0 && doc.summary[0] ? doc.summary[0] : null;
  $: displayedSummary = decryptedSummary || legacySummary;

  onDestroy(() => {
    if (imageUrl) URL.revokeObjectURL(imageUrl);
    if (pdfUrl) URL.revokeObjectURL(pdfUrl);
  });

  // --- file type glyph ---
  function fileTypeMeta(name, mime) {
    const ext = (name || "").split(".").pop().toLowerCase();
    if (["jpg","jpeg","png","gif","svg","webp","bmp"].includes(ext) || (mime && mime.startsWith("image/")))
      return { color: "var(--green)", label: "Image", icon: "image" };
    if (ext === "pdf" || mime === "application/pdf")
      return { color: "#fb6a6a", label: "PDF", icon: "doc" };
    if (["doc","docx"].includes(ext)) return { color: "var(--icp-blue)", label: "Word", icon: "doc" };
    if (["xls","xlsx","csv"].includes(ext)) return { color: "var(--green)", label: "Spreadsheet", icon: "doc" };
    if (["ppt","pptx"].includes(ext)) return { color: "var(--amber)", label: "Presentation", icon: "doc" };
    if (["txt","md","json","xml","yaml","yml","toml"].includes(ext)) return { color: "var(--icp-cyan)", label: "Text", icon: "doc" };
    if (["js","ts","py","rs","go","sol","mo","java","c","cpp","h"].includes(ext)) return { color: "var(--icp-purple)", label: "Code", icon: "code" };
    if (["zip","tar","gz","rar","7z"].includes(ext)) return { color: "var(--amber)", label: "Archive", icon: "archive" };
    return { color: "var(--text-3)", label: mime || "File", icon: "doc" };
  }

  $: fileMeta = fileTypeMeta(doc?.name, doc?.mimeType);

  async function resolveDocumentKey(candidateAccessList = accessList) {
    let aesKey = await getDocumentKey(Number(doc.id));
    if (aesKey) return aesKey;

    const privateKey = await getPrivateKey();
    if (!privateKey) return null;

    const backend = getBackend();

    // Try owner-wrapped key first (for cross-browser recovery)
    if (backend) {
      try {
        const ownerKeyResult = await backend.getOwnerWrappedKey(doc.id);
        if ("ok" in ownerKeyResult) {
          const wrappedKey = new Uint8Array(ownerKeyResult.ok);
          if (wrappedKey.length > 0) {
            aesKey = await decryptKeyWithPrivateKey(wrappedKey, privateKey);
            await saveDocumentKey(Number(doc.id), aesKey);
            return aesKey;
          }
        }
      } catch {}
    }

    // Try recipient access list
    let candidates = candidateAccessList || [];
    if (candidates.length === 0 && backend) {
      const docResult = await backend.getDocument(doc.id);
      if ("ok" in docResult) {
        candidates = docResult.ok.accessList;
        accessList = candidates;
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
    decryptedSummary = null;
    hasEncryptedSummary = false;
    summaryLoading = false;
    imageUrl = null;
    pdfUrl = null;
    docHashHex = null;
    keyPoints = null;
    category = null;
    chatMessages = [];
  }

  async function loadEncryptedSummary(candidateAccessList = accessList) {
    const backend = getBackend();
    if (!backend || !doc) return;

    summaryLoading = true;
    decryptedSummary = null;
    hasEncryptedSummary = false;
    try {
      const result = await backend.getEncryptedSummary(doc.id);
      if ("ok" in result) {
        hasEncryptedSummary = true;
        const aesKey = await resolveDocumentKey(candidateAccessList);
        if (!aesKey) return;
        decryptedSummary = await decryptText(result.ok.ciphertext, result.ok.iv, aesKey);
      }
    } catch (e) {
      console.warn("Encrypted summary warning:", e);
    } finally {
      summaryLoading = false;
    }
  }

  async function saveEncryptedSummaryText(summaryText, aesKey = null) {
    const backend = getBackend();
    if (!backend) throw new Error("Backend not available");
    const key = aesKey || await resolveDocumentKey(accessList);
    if (!key) throw new Error("Document encryption key is not available");

    const encryptedSummary = await encryptText(summaryText, key);
    const saveResult = await backend.setEncryptedSummary(doc.id, encryptedSummary.encrypted, encryptedSummary.iv);
    if ("err" in saveResult) throw new Error(saveResult.err);

    decryptedSummary = summaryText;
    hasEncryptedSummary = true;
    doc.summary = [];
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

  async function downloadStoredBytes(backend, targetDoc = doc) {
    const totalChunks = Number(targetDoc.totalChunks);
    const allChunks = [];

    for (let i = 0; i < totalChunks; i++) {
      const chunkResult = await backend.downloadChunk(targetDoc.id, i);
      if ("err" in chunkResult) {
        throw new Error(`Chunk ${i + 1}/${totalChunks} unavailable: ${chunkResult.err}`);
      }
      allChunks.push(new Uint8Array(chunkResult.ok));
    }

    if (allChunks.length !== totalChunks) {
      throw new Error(`Expected ${totalChunks} chunks, received ${allChunks.length}`);
    }

    const combined = new Uint8Array(allChunks.reduce((acc, c) => acc + c.length, 0));
    let offset = 0;
    for (const chunk of allChunks) {
      combined.set(chunk, offset);
      offset += chunk.length;
    }
    return combined;
  }

  async function hashStoredBytes(backend) {
    const combined = await downloadStoredBytes(backend, doc);
    const hashBuffer = await crypto.subtle.digest("SHA-256", combined);
    const hashArray = Array.from(new Uint8Array(hashBuffer));
    return hashArray.map(b => b.toString(16).padStart(2, "0")).join("");
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
        for (const acc of accessList) {
          const pid = acc.grantedTo.toText();
          if (!usernames[pid]) {
            try {
              const u = await backend.getUser(acc.grantedTo);
              if (u && u.length > 0) usernames[pid] = u[0].username;
            } catch {}
          }
        }
        usernames = usernames;
      }

      await loadEncryptedSummary(accessList);

      try {
        versions = await backend.getVersions(doc.id);
      } catch { versions = []; }

      try {
        const hashResult = await backend.getDocumentHashHex(doc.id);
        if ("ok" in hashResult) docHashHex = hashResult.ok;
      } catch { docHashHex = null; }

      const combined = await downloadStoredBytes(backend, doc);

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
        const combined = await downloadStoredBytes(backend, doc);

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
    if (file.size > MAX_ORIGINAL_FILE_SIZE) {
      notify("Files must be slightly under 50 MB so encrypted storage stays within the canister limit.", "error");
      e.target.value = "";
      return;
    }

    $isLoading = true;
    let pendingStarted = false;
    try {
      const arrayBuffer = await file.arrayBuffer();
      const CHUNK_SIZE = 1024 * 1024;
      let uploadData = new Uint8Array(arrayBuffer);
      let textContent = null;
      let documentKey = null;

      const extraction = await extractTextFromBytes(arrayBuffer.slice(0), {
        name: file.name,
        mimeType: file.type,
      });
      const extractionDetail = describeExtraction(extraction);
      if (isAiReadable(extraction)) textContent = extraction.text;

      if (doc.isEncrypted) {
        documentKey = await resolveDocumentKey(accessList);
        if (!documentKey) {
          notify("Cannot update encrypted document: owner encryption key is not available", "error");
          return;
        }
        uploadData = await encryptDocument(arrayBuffer, documentKey);
      }

      const totalChunks = Math.ceil(uploadData.byteLength / CHUNK_SIZE);

      const result = await backend.uploadNewVersion(doc.id, uploadData.byteLength, totalChunks);
      if ("err" in result) {
        notify(result.err, "error");
        return;
      }
      pendingStarted = true;

      for (let i = 0; i < totalChunks; i++) {
        const start = i * CHUNK_SIZE;
        const end = Math.min(start + CHUNK_SIZE, uploadData.byteLength);
        const chunk = new Uint8Array(uploadData.slice(start, end));
        const chunkResult = await backend.uploadChunk(doc.id, i, chunk);
        if ("err" in chunkResult) {
          notify(`Chunk upload failed: ${chunkResult.err}`, "error");
          await cleanupPendingVersion(backend, doc.id);
          pendingStarted = false;
          return;
        }
      }

      const finalizeResult = await backend.finalizeDocument(doc.id);
      if ("err" in finalizeResult) {
        notify(`Version finalize failed: ${finalizeResult.err}`, "error");
        await cleanupPendingVersion(backend, doc.id);
        pendingStarted = false;
        return;
      }
      pendingStarted = false;

      // Store owner-wrapped key for new version (cross-browser recovery)
      if (documentKey) {
        try {
          if ($userProfile && $userProfile.publicKey) {
            const ownerPubKey = await importPublicKey(new Uint8Array($userProfile.publicKey));
            const wrappedForOwner = await encryptKeyForRecipient(documentKey, ownerPubKey);
            const wrapResult = await backend.setOwnerWrappedKey(doc.id, wrappedForOwner);
            if ("err" in wrapResult) throw new Error(wrapResult.err);
          } else {
            notify("Warning: owner recovery key could not be stored (public key unavailable).", "warning");
          }
        } catch (e) {
          notify("Warning: failed to store owner recovery key — " + e.message, "warning");
        }
      }

      const shouldRefreshSummary = !!textContent;
      let summaryUpdated = false;
      if (shouldRefreshSummary) {
        try {
          const ai = getAI();
          if (ai) {
            const summary = await ai.summarizeText(textContent);
            if ("ok" in summary) {
              await saveEncryptedSummaryText(summary.ok, documentKey);
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
          : `Version ${Number(result.ok)} uploaded. ${textContent ? "No encrypted summary was added." : extractionDetail}`,
        summaryUpdated || textContent ? "success" : "info"
      );
      dispatch("close");
    } catch (e) {
      if (pendingStarted) {
        await cleanupPendingVersion(backend, doc.id);
      }
      notify("Version upload failed: " + e.message, "error");
    } finally {
      $isLoading = false;
      e.target.value = "";
    }
  }

  async function cleanupPendingVersion(backend, docId) {
    try {
      await backend.cancelPendingVersion(docId);
    } catch (e) {
      console.warn("Pending version cleanup warning:", e);
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
      const clientHash = await hashStoredBytes(backend);

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

  async function verifyIntegrityForProof() {
    const backend = getBackend();
    if (!backend) throw new Error("Backend not available");

    const clientHash = await hashStoredBytes(backend);

    return { clientHash, match: clientHash === docHashHex };
  }

  async function regenerateSummary() {
    if (!aiDocumentContent) return;
    const ai = getAI();
    const backend = getBackend();
    if (!ai || !backend) return;

    chatLoading = true;
    try {
      const result = await ai.summarizeOnChain(aiDocumentContent);
      if ("ok" in result) {
        await saveEncryptedSummaryText(result.ok);
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

  function relTime(nanoseconds) {
    const ms = Number(nanoseconds) / 1_000_000;
    const diff = (Date.now() - ms) / 1000;
    if (diff < 3600) return Math.max(1, Math.floor(diff / 60)) + "m ago";
    if (diff < 86400) return Math.floor(diff / 3600) + "h ago";
    if (diff < 86400 * 30) return Math.floor(diff / 86400) + "d ago";
    return new Date(ms).toLocaleDateString("en-US", { month: "short", day: "numeric" });
  }

  function formatSize(bytes) {
    const b = Number(bytes);
    if (b < 1024) return b + " B";
    if (b < 1048576) return (b / 1024).toFixed(1) + " KB";
    return (b / 1048576).toFixed(1) + " MB";
  }

  function close() {
    dispatch("close");
  }
</script>

<div style="max-width: 1140px; margin: 0 auto; padding: 24px 28px 80px; position: relative; z-index: 2;">
  <!-- Header -->
  <div class="flex items-center justify-between mb-[18px] gap-3.5 flex-wrap">
    <div class="flex items-center gap-3.5 min-w-0">
      <button on:click={close} class="btn-ghost w-[38px] h-[38px] rounded-[11px] grid place-items-center p-0 flex-shrink-0" aria-label="Back to documents" title="Back">
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M15 18l-6-6 6-6"/></svg>
      </button>
      <!-- FileGlyph -->
      <div class="w-[46px] h-[46px] rounded-[14px] grid place-items-center flex-shrink-0"
        style="color: {fileMeta.color}; background: color-mix(in srgb, {fileMeta.color} 13%, transparent); border: 1px solid color-mix(in srgb, {fileMeta.color} 26%, transparent);">
        <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M14 3v4a1 1 0 0 0 1 1h4 M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/></svg>
      </div>
      <div class="min-w-0">
        <div class="flex items-center gap-2.5">
          <h1 class="font-display text-[19px] font-semibold truncate max-w-[460px]">{doc.name}</h1>
          {#if Number(doc.version || 1) > 1}
            <span class="mono text-[11px] font-semibold px-2 py-0.5 rounded-full"
              style="color: var(--icp-cyan); background: color-mix(in srgb, var(--icp-cyan) 12%, transparent);">v{Number(doc.version || 1)}</span>
          {/if}
        </div>
        <div class="text-[12.5px] mt-0.5" style="color: var(--text-3);">
          {formatSize(doc.size)} · {fileMeta.label} · updated {relTime(doc.updatedAt)}
        </div>
      </div>
    </div>
    <div class="flex gap-2.5 flex-shrink-0">
      <input type="file" bind:this={versionFileInput} on:change={uploadNewVersion} class="hidden" />
      {#if isOwner}
      <button on:click={() => versionFileInput.click()}
        class="btn-ghost px-[15px] py-[9px] text-[13px] flex items-center gap-[7px]">
        <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 20h9 M16.5 3.5a2.121 2.121 0 1 1 3 3L7 19l-4 1 1-4z"/></svg>
        Update
      </button>
      <button on:click={() => showShareModal = true}
        class="btn-ghost px-[15px] py-[9px] text-[13px] flex items-center gap-[7px]">
        <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M18 8a3 3 0 1 0 0-6 3 3 0 0 0 0 6z M6 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z M18 22a3 3 0 1 0 0-6 3 3 0 0 0 0 6z M8.6 13.5l6.8 4 M15.4 6.5l-6.8 4"/></svg>
        Share
      </button>
      {/if}
      <button on:click={downloadFile}
        class="btn-grad px-[16px] py-[9px] text-[13px] flex items-center gap-[7px]">
        <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 4v12 M7 11l5 5 5-5 M5 20h14"/></svg>
        Download
      </button>
    </div>
  </div>

  <!-- 2-column layout -->
  <div class="grid grid-cols-1 lg:grid-cols-[1.55fr_1fr] gap-[18px] items-start">
    <!-- LEFT: Preview + Details -->
    <div class="glass rounded-[var(--r-lg)] overflow-hidden" style="min-height: 560px;">
      <!-- Tab bar -->
      <div class="flex" style="border-bottom: 1px solid var(--border); padding: 0 8px;">
        <button on:click={() => leftTab = "preview"}
          class="px-4 py-3.5 text-[13px] font-semibold flex items-center gap-[7px]"
          style="color: {leftTab === 'preview' ? 'var(--text)' : 'var(--text-3)'}; border-bottom: 2px solid {leftTab === 'preview' ? 'var(--icp-pink)' : 'transparent'}; margin-bottom: -1px;">
          <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z M12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6z"/></svg>
          Preview
        </button>
        <button on:click={() => leftTab = "details"}
          class="px-4 py-3.5 text-[13px] font-semibold flex items-center gap-[7px]"
          style="color: {leftTab === 'details' ? 'var(--text)' : 'var(--text-3)'}; border-bottom: 2px solid {leftTab === 'details' ? 'var(--icp-pink)' : 'transparent'}; margin-bottom: -1px;">
          <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg>
          Details & integrity
        </button>
      </div>

      {#if leftTab === "preview"}
        <div class="overflow-auto" style="height: 512px;">
          {#if textPreviewContent !== null}
            <pre class="m-0 p-[22px] text-[12.5px] leading-[1.7] whitespace-pre-wrap break-words" style="font-family: var(--font-mono); color: var(--text-2);">{textPreviewContent}</pre>
          {:else if imageUrl}
            <div class="flex items-center justify-center h-full p-5" style="background: radial-gradient(circle at 50% 40%, rgba(123,63,228,0.08), transparent 70%);">
              <img src={imageUrl} alt={doc.name} class="max-w-full max-h-[480px] rounded-xl object-contain" />
            </div>
          {:else if pdfUrl}
            <iframe src={pdfUrl} title={doc.name} class="w-full h-full border-0" style="min-height: 510px;"></iframe>
          {:else if extractionLoading}
            <div class="flex items-center justify-center h-full" style="color: var(--text-4);">
              <div class="text-center space-y-3">
                <div class="w-5 h-5 rounded-full mx-auto anim-spin" style="border: 2px solid var(--surface-hi); border-top-color: var(--icp-pink);"></div>
                <p class="text-sm">Loading preview...</p>
              </div>
            </div>
          {:else}
            <div class="flex items-center justify-center h-full" style="color: var(--text-4);">
              <div class="text-center space-y-3 p-5">
                <div class="w-[80px] h-[80px] rounded-[20px] grid place-items-center mx-auto" style="background: var(--surface); border: 1px solid var(--border); color: {fileMeta.color};">
                  <svg width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M14 3v4a1 1 0 0 0 1 1h4 M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/></svg>
                </div>
                <p class="text-[13px]">Preview not available for this file type</p>
                <p class="text-[12px]" style="color: var(--text-4);">Click Download to view the file</p>
              </div>
            </div>
          {/if}
        </div>
      {:else}
        <!-- Details panel -->
        <div class="p-[22px]">
          <!-- Metadata grid -->
          <div class="grid grid-cols-2 gap-x-6 gap-y-3 mb-[22px]">
            {#each [
              ["Type", fileMeta.label],
              ["Size", formatSize(doc.size)],
              ["Chunks", Number(doc.totalChunks) + " × 1 MB"],
              ["Encrypted", doc.isEncrypted ? "AES-256-GCM" : "No"],
              ["Version", "v" + Number(doc.version || 1)],
              ["Created", formatDate(doc.createdAt)]
            ] as [label, value]}
              <div class="flex justify-between pb-[9px]" style="border-bottom: 1px solid var(--border);">
                <span class="text-[12.5px]" style="color: var(--text-4);">{label}</span>
                <span class="text-[12.5px] font-semibold" style="color: var(--text-2);">{value}</span>
              </div>
            {/each}
          </div>

          <!-- Integrity section -->
          <div class="ring-border rounded-[16px] p-[18px]" style="background: var(--grad-icp-soft);">
            <div class="flex items-center gap-2.5 mb-2.5">
              <span style="color: var(--green);">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 11a2 2 0 0 1 2 2c0 2.5-.5 4.5-1.5 6 M8.5 7.5A5 5 0 0 1 17 11c0 1-.1 2-.3 3 M5.5 11a6.5 6.5 0 0 1 3-5.5 M7 16c.8-1.2 1-2.6 1-3 M12 13c0 3-1 5.5-2.5 7.5"/></svg>
              </span>
              <h3 class="text-[14.5px] font-semibold">On-chain integrity</h3>
              {#if docHashHex}
                <span class="ml-auto text-[11px] font-semibold px-2 py-0.5 rounded-full flex items-center gap-1"
                  style="color: var(--green); background: color-mix(in srgb, var(--green) 14%, transparent);">
                  <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6L9 17l-5-5"/></svg>
                  hash stored
                </span>
              {/if}
            </div>
            {#if docHashHex}
              <div class="text-[10.5px] font-semibold mb-1.5" style="color: var(--text-4); letter-spacing: 0.03em;">SHA-256 · COMPUTED IN BACKEND CANISTER</div>
              <div class="mono text-[11px] break-all leading-[1.6] p-[10px_12px] rounded-[10px]"
                style="color: var(--text-2); background: var(--bg-2); border: 1px solid var(--border);">{docHashHex}</div>
              <button on:click={() => showIntegrityProof = true}
                class="btn-ghost w-full mt-3 py-[11px] text-[13px] flex items-center justify-center gap-2"
                style="color: var(--green); border-color: color-mix(in srgb, var(--green) 30%, transparent);">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z M9 12l2 2 4-4"/></svg>
                Verify integrity now
              </button>
            {:else}
              <p class="text-[12px]" style="color: var(--text-4);">No integrity hash stored for this document.</p>
            {/if}
          </div>

          <!-- Shared with -->
          {#if accessList.length > 0}
            <div class="mt-[22px]">
              <h3 class="text-[13.5px] font-semibold mb-3">Shared with {accessList.length}</h3>
              <div class="flex flex-col gap-2.5">
                {#each accessList as acc}
                  {@const pid = acc.grantedTo.toText()}
                  <div class="flex items-center gap-2.5">
                    <div class="w-[30px] h-[30px] rounded-full grid place-items-center text-[11px] font-bold font-display text-white"
                      style="background: linear-gradient(135deg, var(--icp-purple), color-mix(in srgb, var(--icp-purple) 55%, #000));">
                      {(usernames[pid] || pid).charAt(0).toUpperCase()}
                    </div>
                    <div class="flex-1 min-w-0">
                      <div class="text-[13px] font-semibold">{usernames[pid] || pid.slice(0, 20) + "..."}</div>
                      <div class="text-[11px] mono truncate" style="color: var(--text-4);">{pid}</div>
                    </div>
                    <span class="text-[11px] mono" style="color: var(--text-4);">{relTime(acc.grantedAt)}</span>
                  </div>
                {/each}
              </div>
            </div>
          {/if}

          <!-- Version history -->
          {#if versions.length > 0}
            <div class="mt-[22px]">
              <h3 class="text-[13.5px] font-semibold mb-3">Version history</h3>
              <div class="flex flex-col gap-[7px]">
                <div class="flex justify-between p-[9px_12px] rounded-[9px]"
                  style="background: color-mix(in srgb, var(--icp-cyan) 10%, transparent); border: 1px solid color-mix(in srgb, var(--icp-cyan) 24%, transparent);">
                  <span class="text-[12.5px] font-semibold" style="color: var(--icp-cyan);">v{Number(doc.version || 1)} · current</span>
                  <span class="text-[12px]" style="color: var(--text-3);">{formatSize(doc.size)}</span>
                </div>
                {#each [...versions].reverse() as ver}
                  <div class="flex justify-between p-[9px_12px] rounded-[9px]"
                    style="background: var(--surface); border: 1px solid var(--border);">
                    <span class="text-[12.5px]" style="color: var(--text-3);">v{Number(ver.version)}</span>
                    <span class="text-[12px]" style="color: var(--text-4);">{formatSize(ver.size)} · {relTime(ver.updatedAt)}</span>
                  </div>
                {/each}
              </div>
            </div>
          {/if}
        </div>
      {/if}
    </div>

    <!-- RIGHT: AI panel -->
    <div class="flex flex-col gap-3.5">
      <!-- AI assistant card -->
      <div class="glass rounded-[var(--r-lg)] p-4">
        <div class="flex items-center gap-2 mb-3.5">
          <span style="color: var(--icp-pink);">
            <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v3 M12 18v3 M5.6 5.6l2.1 2.1 M16.3 16.3l2.1 2.1 M3 12h3 M18 12h3 M5.6 18.4l2.1-2.1 M16.3 7.7l2.1-2.1"/></svg>
          </span>
          <h3 class="text-[15px] font-semibold">AI assistant</h3>
          {#if category}
            <span class="ml-auto text-[11px] font-semibold px-2 py-0.5 rounded-full"
              style="color: var(--icp-purple); background: color-mix(in srgb, var(--icp-purple) 14%, transparent);">{category}</span>
          {/if}
        </div>

        <!-- On-chain AI badge -->
        <div class="flex items-center gap-1.5 mb-3.5 px-2.5 py-1.5 rounded-[8px] text-[11px] font-semibold" style="color: var(--green); background: color-mix(in srgb, var(--green) 10%, transparent); border: 1px solid color-mix(in srgb, var(--green) 22%, transparent); width: fit-content;">
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M21 16V8a2 2 0 0 0-1-1.7l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.7l7 4a2 2 0 0 0 2 0l7-4a2 2 0 0 0 1-1.7z M3.3 7L12 12l8.7-5 M12 22V12"/></svg>
          On-chain · mo:llm
        </div>

        <!-- Summary -->
        <div class="flex justify-between items-center mb-2">
          <span class="text-[12px] font-bold" style="color: var(--text-3); letter-spacing: 0.03em;">SUMMARY</span>
          {#if aiDocumentContent}
            <button on:click={regenerateSummary} disabled={chatLoading}
              class="text-[11.5px] font-semibold flex items-center gap-1.5 disabled:opacity-50"
              style="color: var(--icp-cyan);">
              {#if chatLoading}
                <div class="w-[11px] h-[11px] rounded-full anim-spin" style="border: 1.5px solid var(--surface-hi); border-top-color: var(--icp-cyan);"></div>
                ...
              {:else}
                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M23 4v6h-6 M1 20v-6h6 M3.5 9a9 9 0 0 1 14.9-3.5L23 10 M1 14l4.6 4.5A9 9 0 0 0 20.5 15"/></svg>
                Regenerate
              {/if}
            </button>
          {/if}
        </div>

        {#if displayedSummary}
          <p class="text-[13px] leading-[1.6] whitespace-pre-line m-0" style="color: var(--text-2);">{displayedSummary}</p>
        {:else if summaryLoading}
          <p class="text-[13px] italic" style="color: var(--text-4);">Decrypting summary...</p>
        {:else if hasEncryptedSummary}
          <p class="text-[13px] italic" style="color: var(--text-4);">Encrypted summary available, but key not in this browser.</p>
        {:else}
          <p class="text-[13px] italic" style="color: var(--text-4);">No summary yet — it may still be generating.</p>
        {/if}

        <div class="flex items-center gap-1.5 mt-2.5 text-[10.5px]" style="color: var(--text-4);">
          <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 11h14a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1v-8a1 1 0 0 1 1-1z M8 11V7a4 4 0 0 1 8 0v4"/></svg>
          Summary encrypted with the document key before storage
        </div>

        {#if extractionLoading}
          <div class="text-[12px] mt-3 p-2 rounded-lg" style="color: var(--text-4); background: var(--surface);">
            Extracting AI-readable text...
          </div>
        {:else if extractionInfo}
          <div class="text-[12px] mt-3 p-2 rounded-lg space-y-1" style="color: var(--text-4); background: var(--surface);">
            <p class="font-semibold" style="color: var(--text-3);">AI Source</p>
            <p>{describeExtraction(extractionInfo)}</p>
            {#if extractionInfo.text && extractionInfo.warnings.length > 0}
              <p>{extractionInfo.warnings[0]}</p>
            {/if}
          </div>
        {/if}

        <!-- Quick actions -->
        {#if aiDocumentContent}
          <div class="flex gap-2 mt-3.5">
            <button on:click={fetchKeyPoints} disabled={chatLoading}
              class="btn-ghost flex-1 py-[9px] text-[12px] flex items-center justify-center gap-1.5 disabled:opacity-50">
              {#if chatLoading}
                <div class="w-[13px] h-[13px] rounded-full anim-spin" style="border: 2px solid var(--surface-hi); border-top-color: var(--icp-pink);"></div>
              {:else}
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M8 6h13 M8 12h13 M8 18h13 M3 6h.01 M3 12h.01 M3 18h.01"/></svg>
              {/if}
              Key points
            </button>
            <button on:click={fetchCategory} disabled={chatLoading}
              class="btn-ghost flex-1 py-[9px] text-[12px] flex items-center justify-center gap-1.5 disabled:opacity-50">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 9h16 M4 15h16 M10 3v18 M14 3v18"/></svg>
              Categorize
            </button>
          </div>
        {/if}

        <!-- Key points -->
        {#if keyPoints}
          <div class="fade-in mt-3.5 pt-3.5" style="border-top: 1px solid var(--border);">
            <span class="text-[12px] font-bold" style="color: var(--text-3);">KEY POINTS</span>
            <p class="text-[12.5px] leading-[1.6] whitespace-pre-line mt-2" style="color: var(--text-2);">{keyPoints}</p>
          </div>
        {/if}
      </div>

      <!-- Chat card -->
      {#if aiDocumentContent}
        <div class="glass rounded-[var(--r-lg)] p-4 flex flex-col" style="height: 380px;">
          <div class="flex items-center gap-2 mb-3">
            <span style="color: var(--icp-cyan);">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/></svg>
            </span>
            <h3 class="text-[14px] font-semibold">Chat with document</h3>
          </div>

          <!-- Messages -->
          <div class="flex-1 overflow-y-auto flex flex-col gap-3 pr-1" style="min-height: 0;">
            {#if chatMessages.length === 0}
              <div class="text-center py-5" style="color: var(--text-4);">
                <div class="w-[42px] h-[42px] rounded-xl grid place-items-center mx-auto mb-3"
                  style="background: var(--grad-icp-soft); border: 1px solid var(--border); color: var(--icp-pink);">
                  <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/></svg>
                </div>
                <div class="text-[13px] leading-[1.5]">
                  Ask anything about this document.<br/>
                  Answers are generated on-chain by the ICP LLM canister.
                </div>
              </div>
            {/if}

            {#each chatMessages as msg}
              <div class="fade-in flex flex-col" style="align-items: {msg.role === 'user' ? 'flex-end' : 'flex-start'};">
                <div class="max-w-[86%] px-[13px] py-[10px] text-[13.5px] leading-[1.55] whitespace-pre-wrap"
                  style="{msg.role === 'user'
                    ? 'background: var(--grad-icp); color: #fff; border-radius: 14px 14px 4px 14px;'
                    : 'background: var(--surface-hi); color: var(--text-2); border: 1px solid var(--border); border-radius: 14px 14px 14px 4px;'}">
                  {msg.text}
                </div>
                {#if msg.role === "ai"}
                  <div class="text-[10px] mt-1 ml-1 flex items-center gap-1.5" style="color: var(--text-4);">
                    <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 16V8a2 2 0 0 0-1-1.7l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.7l7 4a2 2 0 0 0 2 0l7-4a2 2 0 0 0 1-1.7z"/></svg>
                    on-chain · mo:llm
                  </div>
                {/if}
              </div>
            {/each}

            {#if chatLoading}
              <div class="flex gap-1.5 p-[10px_13px]">
                {#each [0, 1, 2] as i}
                  <span class="w-1.5 h-1.5 rounded-full" style="background: var(--icp-pink); animation: pulse-soft 1s {i * 0.2}s infinite;"></span>
                {/each}
              </div>
            {/if}
          </div>

          <!-- Suggestion chips -->
          {#if chatMessages.length === 0}
            <div class="flex flex-wrap gap-[7px] my-3">
              {#each ["Summarize the key points", "How is this secured?", "What about cycles cost?"] as suggestion}
                <button on:click={() => { chatInput = suggestion; sendChat(); }}
                  class="btn-ghost px-[11px] py-[6px] text-[11.5px] rounded-full font-medium">{suggestion}</button>
              {/each}
            </div>
          {/if}

          <!-- Input -->
          <form on:submit|preventDefault={sendChat} class="flex gap-2 mt-3">
            <input bind:value={chatInput} placeholder="Ask about this document..."
              class="flex-1 px-3.5 py-[11px] rounded-xl text-[13.5px] outline-none"
              style="background: var(--bg-2); border: 1px solid var(--border-hi); color: var(--text);" />
            <button type="submit" disabled={chatLoading || !chatInput.trim()} aria-label="Send message" title="Send"
              class="btn-grad w-[44px] rounded-xl grid place-items-center disabled:opacity-50">
              <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M22 2L11 13 M22 2l-7 20-4-9-9-4z"/></svg>
            </button>
          </form>
        </div>
      {:else}
        <div class="glass rounded-[var(--r-lg)] p-[18px] text-center text-[12.5px] leading-[1.5]" style="color: var(--text-3);">
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" class="mx-auto mb-2" style="color: var(--text-4);"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z M12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6z"/></svg>
          {#if extractionLoading}
            Extracting text for AI analysis...
          {:else}
            AI chat is not available for this file type.
          {/if}
        </div>
      {/if}
    </div>
  </div>
</div>

{#if showShareModal}
  <ShareModal {doc} on:close={() => showShareModal = false} on:shared={loadDocument} />
{/if}

{#if showIntegrityProof && docHashHex}
  <IntegrityProof hash={docHashHex} onVerify={verifyIntegrityForProof} on:close={() => showIntegrityProof = false} />
{/if}
