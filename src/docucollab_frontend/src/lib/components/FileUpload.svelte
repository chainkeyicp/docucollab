<script>
  import { getBackend, getAI } from "$lib/services/auth";
  import { notify, isLoading } from "$lib/stores/app";
  import { generateDocumentKey, encryptDocument, encryptText, saveDocumentKey } from "$lib/services/crypto";
  import { describeExtraction, extractTextFromBytes, isAiReadable } from "$lib/services/fileTextExtractors";
  import { createEventDispatcher } from "svelte";

  const dispatch = createEventDispatcher();
  const CHUNK_SIZE = 1024 * 1024; // 1MB chunks

  let dragOver = false;
  let uploadProgress = 0;
  let extractionStatus = "";
  let extractionDetail = "";
  let generateAiSummary = false;

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

    $isLoading = true;
    uploadProgress = 0;

    try {
      const originalBuffer = await file.arrayBuffer();

      let textContent = null;

      if (generateAiSummary) {
        extractionStatus = "Extracting AI-readable text...";
        extractionDetail = "";

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
      } else {
        extractionStatus = "Preparing encrypted upload...";
        extractionDetail = "AI summary skipped. No summary will be stored.";
      }

      await tickOnce();
      extractionStatus = "Encrypting document...";

      // Encrypt the document
      const aesKey = await generateDocumentKey();
      const encryptedData = await encryptDocument(originalBuffer, aesKey);

      const totalChunks = Math.ceil(encryptedData.byteLength / CHUNK_SIZE);

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
          return;
        }
        uploadProgress = Math.round(((i + 1) / totalChunks) * 100);
      }

      // Finalize document (compute SHA-256 hash for integrity verification)
      try {
        await backend.finalizeDocument(docId);
      } catch (e) {
        console.warn("Finalize warning:", e);
      }

      notify(
        textContent
          ? "Document uploaded & encrypted. AI summary queued."
          : `Document uploaded & encrypted. ${extractionDetail}`,
        textContent ? "success" : "info"
      );
      dispatch("uploaded");

      // Trigger AI summary using text extracted before encryption.
      if (textContent) {
        triggerSummary(docId, textContent, aesKey);
      }
    } catch (e) {
      console.error("Upload error:", e);
      notify("Upload failed: " + e.message, "error");
    } finally {
      $isLoading = false;
      uploadProgress = 0;
      extractionStatus = "";
      extractionDetail = "";
    }
  }

  async function triggerSummary(docId, text, aesKey) {
    try {
      const ai = getAI();
      const backend = getBackend();
      if (!ai || !backend) return;

      const result = await ai.summarizeText(text);
      if ("ok" in result) {
        const encryptedSummary = await encryptText(result.ok, aesKey);
        const saveResult = await backend.setEncryptedSummary(docId, encryptedSummary.encrypted, encryptedSummary.iv);
        if ("err" in saveResult) throw new Error(saveResult.err);
        dispatch("uploaded"); // refresh
        notify("AI summary generated!", "success");
      }
    } catch (e) {
      console.error("Summary error:", e);
      notify("AI summary failed — you can regenerate it later.", "warning");
    }
  }

  function tickOnce() {
    return new Promise((resolve) => requestAnimationFrame(resolve));
  }
</script>

<div
  class="border-2 border-dashed rounded-xl p-6 sm:p-8 text-center transition-colors cursor-pointer
    {dragOver ? 'border-primary-500 bg-primary-50 dark:bg-primary-900/20' : 'border-gray-300 dark:border-gray-700 hover:border-primary-400'}"
  on:dragover={handleDragOver}
  on:dragleave={handleDragLeave}
  on:drop={handleDrop}
  role="button"
  tabindex="0"
>
  <input type="file" on:change={handleFileSelect} class="hidden" id="file-input" />

  {#if extractionStatus && uploadProgress === 0}
    <div class="space-y-3">
      <svg class="w-10 h-10 mx-auto text-primary-500 animate-pulse" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
      </svg>
      <p class="text-sm text-gray-600 dark:text-gray-400">{extractionStatus}</p>
      {#if extractionDetail}
        <p class="text-xs text-gray-500">{extractionDetail}</p>
      {/if}
    </div>
  {:else if uploadProgress > 0}
    <div class="space-y-3">
      <svg class="w-10 h-10 mx-auto text-primary-500 animate-pulse" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12" />
      </svg>
      <p class="text-sm text-gray-600 dark:text-gray-400">Uploading... {uploadProgress}%</p>
      <div class="w-full bg-gray-200 dark:bg-gray-700 rounded-full h-2">
        <div class="bg-primary-500 h-2 rounded-full transition-all" style="width: {uploadProgress}%"></div>
      </div>
    </div>
  {:else}
    <div class="space-y-4">
      <label for="file-input" class="block cursor-pointer space-y-3">
        <svg class="w-10 h-10 mx-auto text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12" />
        </svg>
        <p class="text-sm text-gray-600 dark:text-gray-400">
          <span class="font-semibold text-primary-600">Click to upload</span> or drag and drop
        </p>
        <p class="text-xs text-gray-500">Any file type supported</p>
      </label>
      <label for="ai-summary-toggle" class="mt-4 flex items-start gap-2 text-left max-w-sm mx-auto cursor-pointer">
        <input id="ai-summary-toggle" type="checkbox" bind:checked={generateAiSummary}
          class="mt-0.5 h-4 w-4 rounded border-gray-300 text-primary-600 focus:ring-primary-500" />
        <span class="text-xs text-gray-500">
          Generate AI summary after upload. The encrypted document stays private; the summary is stored encrypted too.
        </span>
      </label>
    </div>
  {/if}
</div>
