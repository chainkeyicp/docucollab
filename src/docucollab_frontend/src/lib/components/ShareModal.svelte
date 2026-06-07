<script>
  import { getBackend, getPrincipal } from "$lib/services/auth";
  import { notify } from "$lib/stores/app";
  import { getDocumentKey, encryptKeyForRecipient, importPublicKey } from "$lib/services/crypto";
  import { Principal } from "@dfinity/principal";
  import { createEventDispatcher } from "svelte";

  const dispatch = createEventDispatcher();
  const NS_PER_MS = 1_000_000n;
  const DAY_NS = 24n * 60n * 60n * 1_000_000_000n;
  const EXPIRY_OPTIONS = [
    { value: "never", label: "No expiry", ns: 0n },
    { value: "1d", label: "24 hours", ns: DAY_NS },
    { value: "7d", label: "7 days", ns: 7n * DAY_NS },
    { value: "30d", label: "30 days", ns: 30n * DAY_NS },
  ];

  export let doc;
  let principalText = "";
  let sharing = false;
  let validationError = "";
  let lookupResult = null;
  let lookupLoading = false;
  let searchMode = "username"; // "principal" or "username"
  let usernameSearch = "";
  let expiryOption = "never";

  function selectedExpiresAt() {
    const selected = EXPIRY_OPTIONS.find(option => option.value === expiryOption);
    if (!selected || selected.ns === 0n) return [];
    return [BigInt(Date.now()) * NS_PER_MS + selected.ns];
  }

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

  $: if (searchMode === "principal") validatePrincipal(principalText);

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
      const hasRecipientKey = lookupResult?.publicKey && lookupResult.publicKey.length > 0;
      if (doc.isEncrypted && !hasRecipientKey) {
        notify("Encrypted documents can only be shared with registered DocuCollab users.", "error");
        return;
      }

      let encryptedAesKey = new Uint8Array(0);
      if (doc.isEncrypted && hasRecipientKey) {
        try {
          const aesKey = await getDocumentKey(Number(doc.id));
          if (aesKey) {
            const recipientPubKey = await importPublicKey(lookupResult.publicKey);
            encryptedAesKey = await encryptKeyForRecipient(aesKey, recipientPubKey);
          } else {
            notify("Cannot share: owner encryption key is not available in this browser.", "error");
            return;
          }
        } catch (e) {
          notify("Could not wrap the document key for this recipient: " + e.message, "error");
          return;
        }
      }

      const result = await backend.shareDocument(doc.id, targetPrincipal, encryptedAesKey, selectedExpiresAt());

      if ("ok" in result) {
        notify(`Shared with ${lookupResult?.username || principalText} — key wrapped to their public key`, "success");
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

  $: isPrincipalInput = searchMode === "principal" && principalText.length > 20 && principalText.includes("-");
</script>

<!-- svelte-ignore a11y-click-events-have-key-events -->
<!-- svelte-ignore a11y-no-static-element-interactions -->
<div class="fixed inset-0 fade-in flex items-center justify-center p-6"
  style="z-index: 120; background: rgba(4,4,10,0.7); backdrop-filter: blur(8px); -webkit-backdrop-filter: blur(8px);"
  on:click|self={() => dispatch("close")}>

  <div class="glass ring-border scale-in w-full max-w-[480px]" style="border-radius: var(--r-xl); padding: 26px; max-height: 90vh; overflow: auto;">
    <!-- Header -->
    <div class="flex items-center gap-3 mb-1.5">
      <div class="w-[42px] h-[42px] rounded-xl grid place-items-center"
        style="background: var(--grad-icp-soft); border: 1px solid var(--border); color: var(--icp-purple);">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M18 8a3 3 0 1 0 0-6 3 3 0 0 0 0 6z M6 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z M18 22a3 3 0 1 0 0-6 3 3 0 0 0 0 6z M8.6 13.5l6.8 4 M15.4 6.5l-6.8 4" /></svg>
      </div>
      <div class="flex-1 min-w-0">
        <h3 class="font-display text-[17px] font-semibold">Share document</h3>
        <p class="text-[12.5px] truncate max-w-[300px]" style="color: var(--text-3);">{doc.name}</p>
      </div>
      <button on:click={() => dispatch("close")} class="btn-ghost w-8 h-8 rounded-[9px] grid place-items-center p-0">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M6 6l12 12 M18 6L6 18" /></svg>
      </button>
    </div>

    <div class="mt-5">
      <!-- Mode toggle -->
      <div class="flex gap-1.5 rounded-[10px] p-1 mb-4" style="background: var(--bg-2);">
        <button on:click={() => searchMode = "username"}
          class="flex-1 px-3 py-2 rounded-[7px] text-xs font-semibold transition-all"
          style="color: {searchMode === 'username' ? 'var(--text)' : 'var(--text-3)'}; background: {searchMode === 'username' ? 'var(--surface-hi)' : 'transparent'};">
          By Username
        </button>
        <button on:click={() => searchMode = "principal"}
          class="flex-1 px-3 py-2 rounded-[7px] text-xs font-semibold transition-all"
          style="color: {searchMode === 'principal' ? 'var(--text)' : 'var(--text-3)'}; background: {searchMode === 'principal' ? 'var(--surface-hi)' : 'transparent'};">
          By Principal ID
        </button>
      </div>

      <!-- SHARE WITH -->
      <label for={searchMode === "username" ? "share-username" : "share-principal"} class="text-xs font-bold" style="color: var(--text-3); letter-spacing: 0.03em;">SHARE WITH</label>

      {#if searchMode === "username"}
        <div class="glass flex items-center gap-2.5 px-3.5 py-2.5 rounded-xl mt-2">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" style="color: var(--text-4);"><path d="M11 19a8 8 0 1 0 0-16 8 8 0 0 0 0 16z M21 21l-4.3-4.3" /></svg>
          <input
            id="share-username"
            bind:value={usernameSearch}
            placeholder="Username..."
            on:keydown={(e) => e.key === "Enter" && searchByUsername()}
            class="flex-1 bg-transparent border-none outline-none text-[13.5px]" style="color: var(--text);" />
          {#if lookupResult}
            <span style="color: var(--green);">
              <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18z M8.5 12l2.5 2.5 4.5-5" /></svg>
            </span>
          {/if}
          <button on:click={searchByUsername} disabled={lookupLoading || !usernameSearch.trim()}
            class="btn-grad px-3 py-1.5 text-xs disabled:opacity-40">
            {lookupLoading ? "..." : "Find"}
          </button>
        </div>
      {:else}
        <div class="glass flex items-center gap-2.5 px-3.5 py-2.5 rounded-xl mt-2">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" style="color: var(--text-4);"><path d="M12 11a2 2 0 0 1 2 2c0 2.5-.5 4.5-1.5 6 M8.5 7.5A5 5 0 0 1 17 11c0 1-.1 2-.3 3 M5.5 11a6.5 6.5 0 0 1 3-5.5 M7 16c.8-1.2 1-2.6 1-3 M12 13c0 3-1 5.5-2.5 7.5" /></svg>
          <input
            id="share-principal"
            bind:value={principalText}
            placeholder="xxxxx-xxxxx-xxxxx-xxxxx-xxx"
            class="flex-1 bg-transparent border-none outline-none text-[13.5px] font-mono" style="color: var(--text);" />
          {#if lookupResult || isPrincipalInput}
            <span style="color: var(--green);">
              <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18z M8.5 12l2.5 2.5 4.5-5" /></svg>
            </span>
          {/if}
        </div>
      {/if}

      {#if validationError}
        <p class="text-xs mt-2" style="color: var(--red);">{validationError}</p>
      {/if}

      <div class="mt-4">
        <label for="share-expiry" class="text-xs font-bold" style="color: var(--text-3); letter-spacing: 0.03em;">ACCESS EXPIRES</label>
        <div class="glass flex items-center gap-2.5 px-3.5 py-2.5 rounded-xl mt-2">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" style="color: var(--text-4);"><path d="M12 8v5l3 2 M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20z" /></svg>
          <select
            id="share-expiry"
            bind:value={expiryOption}
            class="flex-1 bg-transparent border-none outline-none text-[13.5px]"
            style="color: var(--text);">
            {#each EXPIRY_OPTIONS as option}
              <option value={option.value}>{option.label}</option>
            {/each}
          </select>
        </div>
      </div>

      <!-- User match -->
      {#if lookupResult}
        <div class="glass scale-in rounded-xl mt-2 p-3 flex items-center gap-3">
          <div class="w-[30px] h-[30px] rounded-full grid place-items-center text-xs font-bold font-display text-white"
            style="background: linear-gradient(135deg, var(--icp-purple), color-mix(in srgb, var(--icp-purple) 55%, #000));">
            {lookupResult.username.charAt(0).toUpperCase()}
          </div>
          <div class="flex-1 min-w-0">
            <div class="text-[13px] font-semibold">{lookupResult.username}</div>
            <div class="text-[11px] font-mono truncate" style="color: var(--text-4);">{lookupResult.principal.toText()}</div>
          </div>
        </div>
      {/if}

      <!-- Security info -->
      <div class="flex items-center gap-2 mt-4 p-3 rounded-[10px]"
        style="background: color-mix(in srgb, var(--green) 8%, transparent); border: 1px solid color-mix(in srgb, var(--green) 22%, transparent);">
        <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" style="color: var(--green); flex-shrink: 0;"><path d="M5 11h14a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1v-8a1 1 0 0 1 1-1z M8 11V7a4 4 0 0 1 8 0v4" /></svg>
        <span class="text-[11.5px] leading-snug" style="color: var(--text-2);">The AES key is re-wrapped to the recipient's public key. The document is never decrypted on any server.</span>
      </div>

      <!-- Share button -->
      <button on:click={handleShare} disabled={(!lookupResult && !isPrincipalInput) || sharing || !!validationError}
        class="btn-grad w-full mt-4 py-3 text-[14.5px] flex items-center justify-center gap-2.5 disabled:opacity-40">
        {#if sharing}
          <div class="w-4 h-4 rounded-full anim-spin" style="border: 2px solid rgba(255,255,255,0.4); border-top-color: #fff;"></div>
          Wrapping key & granting access...
        {:else}
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M18 8a3 3 0 1 0 0-6 3 3 0 0 0 0 6z M6 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z M18 22a3 3 0 1 0 0-6 3 3 0 0 0 0 6z M8.6 13.5l6.8 4 M15.4 6.5l-6.8 4" /></svg>
          Grant access
        {/if}
      </button>
    </div>
  </div>
</div>
