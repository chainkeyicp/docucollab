<script>
  import { getBackend, getPrincipal } from "$lib/services/auth";
  import { notify } from "$lib/stores/app";
  import { getDocumentKey, encryptKeyForRecipient, importPublicKey } from "$lib/services/crypto";
  import { Principal } from "@dfinity/principal";
  import { createEventDispatcher } from "svelte";

  const dispatch = createEventDispatcher();

  export let doc;
  let principalText = "";
  let sharing = false;
  let validationError = "";
  let lookupResult = null;
  let lookupLoading = false;
  let searchMode = "principal"; // "principal" or "username"
  let usernameSearch = "";

  function validatePrincipal(text) {
    if (!text.trim()) {
      validationError = "";
      lookupResult = null;
      return;
    }
    try {
      const p = Principal.fromText(text.trim());
      if (p.toText() === getPrincipal()?.toText()) {
        validationError = "You cannot share with yourself";
        lookupResult = null;
        return;
      }
      validationError = "";
      lookupUser(p);
    } catch {
      validationError = "Invalid Principal ID format";
      lookupResult = null;
    }
  }

  $: validatePrincipal(principalText);

  async function lookupUser(p) {
    const backend = getBackend();
    if (!backend) return;
    lookupLoading = true;
    try {
      const user = await backend.getUser(p);
      lookupResult = user && user.length > 0 ? user[0] : null;
    } catch {
      lookupResult = null;
    } finally {
      lookupLoading = false;
    }
  }

  async function searchByUsername() {
    if (!usernameSearch.trim()) return;
    const backend = getBackend();
    if (!backend) return;
    lookupLoading = true;
    try {
      const user = await backend.getUserByName(usernameSearch.trim());
      if (user && user.length > 0) {
        lookupResult = user[0];
        principalText = user[0].principal.toText();
        validationError = "";
      } else {
        lookupResult = null;
        validationError = "User not found";
      }
    } catch {
      validationError = "Search failed";
    } finally {
      lookupLoading = false;
    }
  }

  async function handleShare() {
    if (!principalText.trim()) {
      notify("Enter a Principal ID", "error");
      return;
    }
    if (validationError) {
      notify(validationError, "error");
      return;
    }

    const backend = getBackend();
    if (!backend) return;

    sharing = true;
    try {
      const targetPrincipal = Principal.fromText(principalText.trim());

      // Encrypt AES key for recipient using their public key
      let encryptedAesKey = new Uint8Array(0);
      if (doc.isEncrypted && lookupResult && lookupResult.publicKey && lookupResult.publicKey.length > 0) {
        try {
          const aesKey = await getDocumentKey(Number(doc.id));
          if (aesKey) {
            const recipientPubKey = await importPublicKey(lookupResult.publicKey);
            encryptedAesKey = await encryptKeyForRecipient(aesKey, recipientPubKey);
          }
        } catch (e) {
          console.warn("Key exchange warning:", e);
        }
      }

      const result = await backend.shareDocument(doc.id, targetPrincipal, encryptedAesKey, []);

      if ("ok" in result) {
        notify(`Document shared with ${lookupResult?.username || principalText}!`, "success");
        dispatch("shared");
        dispatch("close");
      } else {
        notify(result.err, "error");
      }
    } catch (e) {
      notify("Share failed: " + e.message, "error");
    } finally {
      sharing = false;
    }
  }
</script>

<!-- svelte-ignore a11y-click-events-have-key-events -->
<!-- svelte-ignore a11y-no-static-element-interactions -->
<div class="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4" on:click|self={() => dispatch("close")}>
  <div class="bg-white dark:bg-gray-800 rounded-xl shadow-xl max-w-md w-full p-6">
    <h3 class="text-lg font-semibold text-gray-900 dark:text-white mb-4">Share "{doc.name}"</h3>

    <div class="space-y-4">
      <!-- Toggle search mode -->
      <div class="flex gap-1 bg-gray-100 dark:bg-gray-700 rounded-lg p-1">
        <button on:click={() => searchMode = "principal"}
          class="flex-1 px-3 py-1.5 text-xs font-medium rounded-md transition
            {searchMode === 'principal' ? 'bg-white dark:bg-gray-600 text-gray-900 dark:text-white shadow-sm' : 'text-gray-500'}">
          By Principal ID
        </button>
        <button on:click={() => searchMode = "username"}
          class="flex-1 px-3 py-1.5 text-xs font-medium rounded-md transition
            {searchMode === 'username' ? 'bg-white dark:bg-gray-600 text-gray-900 dark:text-white shadow-sm' : 'text-gray-500'}">
          By Username
        </button>
      </div>

      {#if searchMode === "username"}
        <div>
          <label for="username" class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
            Search by Username
          </label>
          <div class="flex gap-2">
            <input
              id="username"
              type="text"
              bind:value={usernameSearch}
              placeholder="Enter username"
              class="flex-1 px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700 text-gray-900 dark:text-white text-sm focus:ring-2 focus:ring-primary-500 focus:border-transparent"
              on:keydown={(e) => e.key === "Enter" && searchByUsername()}
            />
            <button on:click={searchByUsername} disabled={lookupLoading}
              class="px-3 py-2 text-sm font-medium text-white bg-primary-600 rounded-lg hover:bg-primary-700 disabled:opacity-50 transition">
              {lookupLoading ? "..." : "Find"}
            </button>
          </div>
        </div>
      {:else}
        <div>
          <label for="principal" class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
            Recipient Principal ID
          </label>
          <input
            id="principal"
            type="text"
            bind:value={principalText}
            placeholder="xxxxx-xxxxx-xxxxx-xxxxx-xxx"
            class="w-full px-3 py-2 border rounded-lg bg-white dark:bg-gray-700 text-gray-900 dark:text-white text-sm focus:ring-2 focus:ring-primary-500 focus:border-transparent
              {validationError ? 'border-red-400' : 'border-gray-300 dark:border-gray-600'}"
          />
        </div>
      {/if}

      {#if validationError}
        <p class="text-xs text-red-500">{validationError}</p>
      {/if}

      {#if lookupResult}
        <div class="flex items-center gap-3 p-3 bg-green-50 dark:bg-green-900/20 rounded-lg border border-green-200 dark:border-green-800">
          <div class="w-8 h-8 rounded-full bg-green-100 dark:bg-green-900/40 flex items-center justify-center text-green-600 font-bold text-sm">
            {lookupResult.username.charAt(0).toUpperCase()}
          </div>
          <div>
            <p class="text-sm font-medium text-gray-900 dark:text-white">{lookupResult.username}</p>
            <p class="text-xs text-gray-500 truncate max-w-[280px]">{lookupResult.principal.toText()}</p>
          </div>
        </div>
      {:else if principalText.trim() && !validationError && !lookupLoading}
        <p class="text-xs text-yellow-600 dark:text-yellow-400">User not registered on DocuCollab. They can still receive the document.</p>
      {/if}

      <div class="flex justify-end gap-2 pt-2">
        <button on:click={() => dispatch("close")}
          class="px-4 py-2 text-sm font-medium text-gray-700 dark:text-gray-300 bg-gray-100 dark:bg-gray-700 rounded-lg hover:bg-gray-200 dark:hover:bg-gray-600 transition">
          Cancel
        </button>
        <button on:click={handleShare} disabled={sharing || !!validationError || !principalText.trim()}
          class="px-4 py-2 text-sm font-medium text-white bg-primary-600 rounded-lg hover:bg-primary-700 disabled:opacity-50 transition">
          {sharing ? "Sharing..." : "Share"}
        </button>
      </div>
    </div>
  </div>
</div>
