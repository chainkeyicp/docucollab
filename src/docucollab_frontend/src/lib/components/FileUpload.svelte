<script>
  import { getBackend, getAI } from "$lib/services/auth";
  import { documents, notify, isLoading } from "$lib/stores/app";
  import { generateDocumentKey, encryptDocument, saveDocumentKey } from "$lib/services/crypto";
  import { createEventDispatcher } from "svelte";

  const dispatch = createEventDispatcher();
  const CHUNK_SIZE = 1024 * 1024; // 1MB chunks

  let dragOver = false;
  let uploadProgress = 0;

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

      // Extract text for AI BEFORE encryption
      let textContent = null;
      if (file.type.startsWith("text/") || file.name.endsWith(".md") || file.name.endsWith(".txt")) {
        textContent = new TextDecoder().decode(originalBuffer);
      }

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

      notify("Document uploaded & encrypted!", "success");
      dispatch("uploaded");

      // Trigger AI summary for text files (using pre-encryption content)
      if (textContent) {
        triggerSummary(docId, new TextEncoder().encode(textContent).buffer);
      }
    } catch (e) {
      console.error("Upload error:", e);
      notify("Upload failed: " + e.message, "error");
    } finally {
      $isLoading = false;
      uploadProgress = 0;
    }
  }

  async function triggerSummary(docId, arrayBuffer) {
    try {
      const ai = getAI();
      const backend = getBackend();
      if (!ai || !backend) return;

      const text = new TextDecoder().decode(arrayBuffer);
      const result = await ai.summarizeText(text);
      if ("ok" in result) {
        await backend.setSummary(docId, result.ok);
        dispatch("uploaded"); // refresh
        notify("AI summary generated!", "success");
      }
    } catch (e) {
      console.error("Summary error:", e);
    }
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

  {#if uploadProgress > 0}
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
    <label for="file-input" class="cursor-pointer space-y-3">
      <svg class="w-10 h-10 mx-auto text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12" />
      </svg>
      <p class="text-sm text-gray-600 dark:text-gray-400">
        <span class="font-semibold text-primary-600">Click to upload</span> or drag and drop
      </p>
      <p class="text-xs text-gray-500">Any file type supported</p>
    </label>
  {/if}
</div>
