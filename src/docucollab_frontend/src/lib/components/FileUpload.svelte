<script>
  import { getBackend, getAI } from "$lib/services/auth";
  import { notify, isLoading } from "$lib/stores/app";
  import { generateDocumentKey, encryptDocument, encryptText, saveDocumentKey } from "$lib/services/crypto";
  import { describeExtraction, extractTextFromBytes, isAiReadable } from "$lib/services/fileTextExtractors";
  import OnChainUploadViz from "./OnChainUploadViz.svelte";
  import { createEventDispatcher } from "svelte";

  const dispatch = createEventDispatcher();
  const CHUNK_SIZE = 1024 * 1024; // 1MB chunks
  const MAX_ORIGINAL_FILE_SIZE = 50 * 1024 * 1024 - 1024; // leave room for AES-GCM overhead

  let dragOver = false;
  let uploadProgress = 0;
  let extractionStatus = "";
  let extractionDetail = "";
  let showUploadViz = false;
  let uploadFileName = "";
  let uploadTotalChunks = 1;
  let summaryPhase = "idle"; // "idle" | "generating" | "done" | "failed" | "unavailable"

  function handleDragOver(e) {
    e.preventDefault();
    dragOver = true;
  }

  function handleDragLeave() {
    dragOver = false;
  }

  function handleDrop(e) {
    e.preventDefault();
    dragOver = false;
    const files = e.dataTransfer.files;
    if (files.length > 0) uploadFile(files[0]);
  }

  function handleFileSelect(e) {
    const file = e.target.files[0];
    if (file) uploadFile(file);
  }

  async function uploadFile(file) {
    const backend = getBackend();
    if (!backend) return;
    if (file.size > MAX_ORIGINAL_FILE_SIZE) {
      notify("Files must be slightly under 50 MB so encrypted storage stays within the canister limit.", "error");
      return;
    }

    $isLoading = true;
    uploadProgress = 0;
    uploadFileName = file.name;
    showUploadViz = true;
    summaryPhase = "idle";
    let createdDocId = null;
    let shouldCleanupDoc = false;

    try {
      const originalBuffer = await file.arrayBuffer();

      // Always extract text for AI summary
      extractionStatus = "Extracting AI-readable text...";
      extractionDetail = "";
      let textContent = null;

      const extraction = await extractTextFromBytes(originalBuffer.slice(0), {
        name: file.name,
        mimeType: file.type,
        onProgress: (msg) => { extractionStatus = msg; },
      });

      extractionDetail = describeExtraction(extraction);
      if (isAiReadable(extraction)) {
        textContent = extraction.text;
        extractionStatus = "AI text ready";
      } else {
        extractionStatus = "AI text unavailable";
      }

      await tickOnce();
      extractionStatus = "Encrypting document...";

      // Encrypt the document
      const aesKey = await generateDocumentKey();
      const encryptedData = await encryptDocument(originalBuffer, aesKey);

      const totalChunks = Math.ceil(encryptedData.byteLength / CHUNK_SIZE);
      uploadTotalChunks = totalChunks;

      // Create document record (encrypted)
      const result = await backend.createDocument(
        file.name,
        file.type || "application/octet-stream",
        encryptedData.byteLength,
        totalChunks,
        true
      );

      if ("err" in result) {
        notify(result.err, "error");
        return;
      }

      const docId = result.ok;
      createdDocId = docId;
      shouldCleanupDoc = true;

      // Save AES key in IndexedDB
      await saveDocumentKey(Number(docId), aesKey);

      // Upload encrypted chunks
      for (let i = 0; i < totalChunks; i++) {
        const start = i * CHUNK_SIZE;
        const end = Math.min(start + CHUNK_SIZE, encryptedData.byteLength);
        const chunk = new Uint8Array(encryptedData.slice(start, end));

        const chunkResult = await backend.uploadChunk(docId, i, chunk);
        if ("err" in chunkResult) {
          notify(`Chunk upload failed: ${chunkResult.err}`, "error");
          await cleanupCreatedDocument(backend, createdDocId);
          shouldCleanupDoc = false;
          return;
        }
        uploadProgress = Math.round(((i + 1) / totalChunks) * 100);
      }

      // Finalize document (compute SHA-256 hash for integrity verification)
      const finalizeResult = await backend.finalizeDocument(docId);
      if ("err" in finalizeResult) {
        notify(`Finalize failed: ${finalizeResult.err}`, "error");
        await cleanupCreatedDocument(backend, createdDocId);
        shouldCleanupDoc = false;
        return;
      }
      shouldCleanupDoc = false;

      // Generate AI summary inline — wait for it to complete
      summaryPhase = "generating";
      await tickOnce(); // let viz react to summaryPhase change

      if (textContent) {
        try {
          const ai = getAI();
          if (ai) {
            const summaryResult = await ai.summarizeText(textContent);
            if ("ok" in summaryResult) {
              const encSummary = await encryptText(summaryResult.ok, aesKey);
              const saveResult = await backend.setEncryptedSummary(docId, encSummary.encrypted, encSummary.iv);
              if ("err" in saveResult) throw new Error(saveResult.err);
              summaryPhase = "done";
            } else {
              summaryPhase = "failed";
            }
          } else {
            summaryPhase = "failed";
          }
        } catch (e) {
          console.error("Summary error:", e);
          summaryPhase = "failed";
        }
      } else {
        summaryPhase = "unavailable";
      }

      await tickOnce(); // let viz react to final summaryPhase
      dispatch("uploaded");

      if (summaryPhase === "done") {
        notify("Document uploaded, encrypted & AI summary generated.", "success");
      } else if (summaryPhase === "failed") {
        notify("Document uploaded & encrypted. AI summary failed — you can regenerate it later.", "warning");
      } else {
        notify(`Document uploaded & encrypted. ${extractionDetail}`, "info");
      }

      // Give user time to see the final state
      await new Promise(r => setTimeout(r, 2000));
    } catch (e) {
      console.error("Upload error:", e);
      if (shouldCleanupDoc && createdDocId !== null) {
        await cleanupCreatedDocument(backend, createdDocId);
      }
      notify("Upload failed: " + e.message, "error");
    } finally {
      $isLoading = false;
      showUploadViz = false;
      uploadProgress = 0;
      extractionStatus = "";
      extractionDetail = "";
      summaryPhase = "idle";
    }
  }

  async function cleanupCreatedDocument(backend, docId) {
    if (docId === null || docId === undefined) return;
    try {
      await backend.deleteDocument(docId);
    } catch (e) {
      console.warn("Upload cleanup warning:", e);
    }
  }

  function tickOnce() {
    return new Promise((resolve) => requestAnimationFrame(resolve));
  }
</script>

<div
  class="rounded-[var(--r-lg)] p-6 sm:p-8 text-center cursor-pointer transition-all"
  style="border: 1.5px dashed {dragOver ? 'var(--icp-pink)' : 'var(--border-hi)'};
    background: {dragOver ? 'var(--grad-icp-soft)' : 'var(--surface)'};
    transform: {dragOver ? 'scale(1.005)' : 'none'};"
  on:dragover={handleDragOver}
  on:dragleave={handleDragLeave}
  on:drop={handleDrop}
  role="button"
  tabindex="0"
>
  <input type="file" on:change={handleFileSelect} class="hidden" id="file-input" />

  {#if extractionStatus && uploadProgress === 0}
    <div class="space-y-3">
      <div class="w-11 h-11 rounded-[13px] grid place-items-center mx-auto" style="background: var(--surface-hi); border: 1px solid var(--border); color: var(--icp-pink); animation: pulse-soft 1.2s infinite;">
        <svg width="21" height="21" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M14 3v4a1 1 0 0 0 1 1h4 M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z" /></svg>
      </div>
      <p class="text-sm" style="color: var(--text-3);">{extractionStatus}</p>
      {#if extractionDetail}
        <p class="text-xs" style="color: var(--text-4);">{extractionDetail}</p>
      {/if}
    </div>
  {:else if uploadProgress > 0}
    <div class="space-y-3">
      <div class="w-11 h-11 rounded-[13px] grid place-items-center mx-auto" style="background: var(--surface-hi); border: 1px solid var(--border); color: var(--icp-cyan); animation: pulse-soft 1s infinite;">
        <svg width="21" height="21" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 16V4 M7 9l5-5 5 5 M5 20h14" /></svg>
      </div>
      <p class="text-sm" style="color: var(--text-3);">Uploading... {uploadProgress}%</p>
      <div class="w-full h-1.5 rounded-full overflow-hidden" style="background: var(--surface-hi);">
        <div class="h-full rounded-full transition-all" style="width: {uploadProgress}%; background: var(--grad-icp);"></div>
      </div>
    </div>
  {:else}
    <div class="space-y-4">
      <label for="file-input" class="block cursor-pointer">
        <div class="inline-flex items-center gap-3.5">
          <div class="w-11 h-11 rounded-[13px] grid place-items-center" style="background: var(--surface-hi); border: 1px solid var(--border); color: {dragOver ? 'var(--icp-pink)' : 'var(--icp-cyan)'};">
            <svg width="21" height="21" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 16V4 M7 9l5-5 5 5 M5 20h14" /></svg>
          </div>
          <div class="text-left">
            <div class="font-bold text-[14.5px]">Drop a file to encrypt & store on-chain</div>
            <div class="text-[12.5px]" style="color: var(--text-3);">Chunked at 1 MB · AES-256 in your browser · AI summary included</div>
          </div>
        </div>
      </label>
    </div>
  {/if}
</div>

{#if showUploadViz}
  <OnChainUploadViz
    fileName={uploadFileName}
    totalChunks={uploadTotalChunks}
    uploadProgress={uploadProgress}
    {summaryPhase}
    on:done={() => showUploadViz = false} />
{/if}
