<script>
  import { createEventDispatcher, onMount, onDestroy } from "svelte";

  const dispatch = createEventDispatcher();

  export let fileName = "";
  export let totalChunks = 4;
  export let uploadProgress = 0; // 0-100 from real upload
  export let hashHex = "";       // real hash when available
  export let summaryPhase = "idle"; // "idle" | "generating" | "done" | "failed" | "unavailable"

  let phase = 0; // 0=split, 1=encrypt, 2=store, 3=hash, 4=summary, 5=done
  let storedChunks = 0;
  let hashChars = "";
  let cancelled = false;

  const placeholderHash = "9f2c1a7e4b8d0c3f6a5e9d2b1c4f7a8e0d3b6c9f2a5e8d1b4c7f0a3e6d9b2c5f";

  // Map real upload progress to visualization phases
  $: {
    if (uploadProgress > 0 && uploadProgress <= 5) {
      phase = 0; // splitting
    } else if (uploadProgress > 5 && uploadProgress <= 15) {
      phase = 1; // encrypting
    } else if (uploadProgress > 15 && uploadProgress < 95) {
      phase = 2; // storing
      storedChunks = Math.min(totalChunks, Math.floor((uploadProgress - 15) / 80 * totalChunks) + 1);
    } else if (uploadProgress >= 95 && uploadProgress < 100) {
      phase = 3; // hashing
      storedChunks = totalChunks;
      const displayHash = hashHex || placeholderHash;
      hashChars = displayHash;
    } else if (uploadProgress >= 100) {
      // Upload done, now waiting for summary
      storedChunks = totalChunks;
      hashChars = hashHex || placeholderHash;
      if (summaryPhase === "done" || summaryPhase === "failed" || summaryPhase === "unavailable") {
        phase = 5; // all done
      } else {
        phase = 4; // summary generating or about to start
      }
    }
  }

  // When no real progress, run demo animation
  let demoMode = false;
  onMount(() => {
    if (uploadProgress === 0) {
      demoMode = true;
      runDemo();
    }
  });

  onDestroy(() => { cancelled = true; });

  function wait(ms) {
    return new Promise(r => setTimeout(r, ms));
  }

  async function runDemo() {
    await wait(550); if (cancelled) return; phase = 1;
    await wait(750); if (cancelled) return; phase = 2;
    for (let i = 1; i <= totalChunks; i++) {
      await wait(420); if (cancelled) return; storedChunks = i;
    }
    await wait(300); if (cancelled) return; phase = 3;
    const hash = hashHex || placeholderHash;
    for (let i = 1; i <= hash.length; i++) {
      await wait(14); if (cancelled) return; hashChars = hash.slice(0, i);
    }
    await wait(450); if (cancelled) return; phase = 4;
    await wait(1200); if (cancelled) return; phase = 5;
    await wait(900); if (cancelled) return; dispatch("done");
  }

  $: steps = [
    { label: "Splitting into 1 MB chunks", icon: "layers", done: phase > 0, active: phase === 0 },
    { label: "Encrypting · AES-256-GCM", icon: "lock", done: phase > 1, active: phase === 1 },
    { label: "Storing to backend canister", icon: "database", done: phase > 2, active: phase === 2 },
    { label: "Computing SHA-256 integrity hash", icon: "fingerprint", done: phase > 3, active: phase === 3 },
    {
      label: summaryPhase === "failed" ? "AI summary failed — regenerate later"
           : summaryPhase === "unavailable" ? "AI summary unavailable for this file type"
           : "Generating AI summary",
      icon: "spark",
      done: summaryPhase === "done" || summaryPhase === "failed" || summaryPhase === "unavailable",
      active: phase === 4 && summaryPhase !== "failed" && summaryPhase !== "unavailable",
      failed: summaryPhase === "failed",
      skipped: summaryPhase === "unavailable",
    },
  ];
</script>

<!-- svelte-ignore a11y-click-events-have-key-events -->
<!-- svelte-ignore a11y-no-static-element-interactions -->
<div class="fixed inset-0 fade-in flex items-center justify-center p-6"
  style="z-index: 130; background: rgba(4,4,10,0.8); backdrop-filter: blur(12px); -webkit-backdrop-filter: blur(12px);">

  <div class="glass ring-border scale-in w-full max-w-[480px]" style="border-radius: var(--r-xl); padding: 30px; max-height: 90vh; overflow: auto;">
    <div class="scale-in" style="padding: 8px 4px;">
      <!-- Header -->
      <div class="text-center mb-[22px]">
        <div class="text-[13px] font-semibold mb-1" style="color: var(--text-3);">Writing to the Internet Computer</div>
        <div class="font-display font-semibold text-[16px]">{fileName}</div>
      </div>

      <!-- Chunk row -->
      <div class="flex justify-center gap-[9px] mb-[26px]" style="min-height: 56px;">
        {#each Array(totalChunks) as _, i}
          {@const isStored = phase >= 2 && i < storedChunks}
          {@const isEncrypting = phase === 1 || (phase === 2 && i === storedChunks)}
          {@const active = phase >= 1}
          <div style="position: relative; transition: all .4s cubic-bezier(.2,.8,.2,1); transform: {isStored ? 'translateY(-6px)' : 'none'};">
            <div class="w-[46px] h-[56px] rounded-[10px] grid place-items-center"
              style="background: {isStored ? 'var(--grad-icp)' : active ? 'var(--surface-hi)' : 'var(--surface)'};
                border: 1px solid {isStored ? 'transparent' : 'var(--border)'};
                color: {isStored ? '#fff' : isEncrypting ? 'var(--icp-pink)' : 'var(--text-4)'};
                box-shadow: {isStored ? '0 8px 22px -8px rgba(224,53,154,0.6)' : 'none'};
                transition: all .4s;">
              {#if isStored}
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M21 16V8a2 2 0 0 0-1-1.7l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.7l7 4a2 2 0 0 0 2 0l7-4a2 2 0 0 0 1-1.7z M3.3 7L12 12l8.7-5 M12 22V12"/></svg>
              {:else if isEncrypting}
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" style="animation: pulse-soft 1s infinite;"><path d="M5 11h14a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1v-8a1 1 0 0 1 1-1z M8 11V7a4 4 0 0 1 8 0v4"/></svg>
              {:else}
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M14 3v4a1 1 0 0 0 1 1h4 M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/></svg>
              {/if}
            </div>
            <div class="text-center mt-[5px] mono" style="font-size: 9.5px; color: var(--text-4);">1 MB</div>
          </div>
        {/each}
      </div>

      <!-- Steps checklist -->
      <div class="flex flex-col gap-[11px] max-w-[340px] mx-auto">
        {#each steps as step, i}
          <div class="flex items-center gap-3" style="opacity: {step.done || step.active || phase >= i ? 1 : 0.32}; transition: opacity .3s;">
            <div class="w-[30px] h-[30px] rounded-[9px] grid place-items-center flex-shrink-0"
              style="background: {step.failed ? 'color-mix(in srgb, var(--amber) 16%, transparent)' : step.skipped ? 'color-mix(in srgb, var(--text-3) 12%, transparent)' : step.done ? 'color-mix(in srgb, var(--green) 16%, transparent)' : step.active ? 'var(--surface-hi)' : 'var(--surface)'};
                color: {step.failed ? 'var(--amber)' : step.skipped ? 'var(--text-3)' : step.done ? 'var(--green)' : step.active ? 'var(--icp-pink)' : 'var(--text-4)'};
                border: 1px solid {step.failed ? 'color-mix(in srgb, var(--amber) 30%, transparent)' : step.skipped ? 'var(--border)' : step.done ? 'color-mix(in srgb, var(--green) 30%, transparent)' : 'var(--border)'};">
              {#if step.failed}
                <!-- warning -->
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 9v4 M12 17h.01 M10.3 3.2L1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.2a2 2 0 0 0-3.4 0z"/></svg>
              {:else if step.skipped}
                <!-- dash/skip -->
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14"/></svg>
              {:else if step.done}
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6L9 17l-5-5"/></svg>
              {:else if step.active}
                <div class="w-3.5 h-3.5 rounded-full anim-spin" style="border: 2px solid var(--surface-hi); border-top-color: var(--icp-pink);"></div>
              {:else if step.icon === "layers"}
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2L2 7l10 5 10-5-10-5z M2 17l10 5 10-5 M2 12l10 5 10-5"/></svg>
              {:else if step.icon === "lock"}
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M5 11h14a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1v-8a1 1 0 0 1 1-1z M8 11V7a4 4 0 0 1 8 0v4"/></svg>
              {:else if step.icon === "database"}
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><ellipse cx="12" cy="5" rx="9" ry="3"/><path d="M21 12c0 1.7-4 3-9 3s-9-1.3-9-3 M3 5v14c0 1.7 4 3 9 3s9-1.3 9-3V5"/></svg>
              {:else if step.icon === "fingerprint"}
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 11a2 2 0 0 1 2 2c0 2.5-.5 4.5-1.5 6 M8.5 7.5A5 5 0 0 1 17 11c0 1-.1 2-.3 3 M5.5 11a6.5 6.5 0 0 1 3-5.5 M7 16c.8-1.2 1-2.6 1-3 M12 13c0 3-1 5.5-2.5 7.5"/></svg>
              {:else}
                <!-- spark -->
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v3 M12 18v3 M5.6 5.6l2.1 2.1 M16.3 16.3l2.1 2.1 M3 12h3 M18 12h3 M5.6 18.4l2.1-2.1 M16.3 7.7l2.1-2.1"/></svg>
              {/if}
            </div>
            <span class="text-[13.5px] font-medium"
              style="color: {step.failed ? 'var(--amber)' : step.skipped ? 'var(--text-3)' : step.done ? 'var(--text-2)' : step.active ? 'var(--text)' : 'var(--text-3)'};">{step.label}</span>
          </div>
        {/each}
      </div>

      <!-- Hash reveal -->
      {#if phase >= 3}
        <div class="fade-in mx-auto mt-[22px] p-[12px_14px] rounded-xl max-w-[380px]"
          style="background: var(--bg-2); border: 1px solid var(--border);">
          <div class="text-[10.5px] font-semibold mb-[5px]" style="color: var(--text-4); letter-spacing: 0.04em;">SHA-256 · COMPUTED IN-CANISTER</div>
          <div class="mono text-[11.5px] break-all leading-[1.6]" style="color: var(--green);">
            {hashChars}{#if hashChars.length < (hashHex || placeholderHash).length}<span style="animation: blink 1s infinite;">▋</span>{/if}
          </div>
        </div>
      {/if}

      <!-- Done state -->
      {#if phase >= 5}
        <div class="scale-in text-center mt-[18px] font-semibold text-[14px] flex items-center justify-center gap-2"
          style="color: {summaryPhase === 'failed' ? 'var(--amber)' : 'var(--green)'};">
          {#if summaryPhase === "failed"}
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 9v4 M12 17h.01 M10.3 3.2L1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.2a2 2 0 0 0-3.4 0z"/></svg>
            Stored on-chain · summary failed
          {:else if summaryPhase === "unavailable"}
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18z M8.5 12l2.5 2.5 4.5-5"/></svg>
            Stored on-chain & certified
          {:else}
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18z M8.5 12l2.5 2.5 4.5-5"/></svg>
            Stored on-chain & AI summary ready
          {/if}
        </div>
      {/if}
    </div>
  </div>
</div>
