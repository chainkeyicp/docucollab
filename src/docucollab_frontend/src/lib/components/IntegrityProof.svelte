<script>
  import { createEventDispatcher, onMount, onDestroy } from "svelte";

  const dispatch = createEventDispatcher();

  export let hash = "";
  export let onVerify = null; // async function that returns { clientHash, match }

  let stage = 0; // 0=idle, 1=fetching, 2=computing, 3=comparing, 4=match, 5=mismatch
  let localHash = "";
  let cancelled = false;

  onMount(() => { run(); });
  onDestroy(() => { cancelled = true; });

  function wait(ms) {
    return new Promise(r => setTimeout(r, ms));
  }

  async function run() {
    stage = 1; localHash = "";
    await wait(700); if (cancelled) return;

    stage = 2;

    if (onVerify) {
      // Real verification
      try {
        const result = await onVerify();
        if (cancelled) return;
        localHash = result.clientHash;
        await wait(400); if (cancelled) return;
        stage = 3;
        await wait(900); if (cancelled) return;
        stage = result.match ? 4 : 5;
      } catch {
        if (cancelled) return;
        stage = 5;
      }
    } else {
      // Demo: animate hash character by character
      for (let i = 1; i <= hash.length; i++) {
        await wait(10); if (cancelled) return;
        localHash = hash.slice(0, i);
      }
      await wait(400); if (cancelled) return;
      stage = 3;
      await wait(900); if (cancelled) return;
      stage = 4;
    }
  }
</script>

<!-- svelte-ignore a11y-click-events-have-key-events -->
<!-- svelte-ignore a11y-no-static-element-interactions -->
<div class="fixed inset-0 fade-in flex items-center justify-center p-6"
  style="z-index: 140; background: rgba(4,4,10,0.8); backdrop-filter: blur(12px); -webkit-backdrop-filter: blur(12px);"
  on:click|self={() => dispatch("close")}>

  <div class="glass ring-border scale-in w-full max-w-[620px]" style="border-radius: var(--r-xl); padding: 30px; max-height: 90vh; overflow: auto;">
    <!-- Header -->
    <div class="flex items-center gap-3 mb-5">
      <div class="w-[42px] h-[42px] rounded-xl grid place-items-center"
        style="background: color-mix(in srgb, var(--green) 12%, transparent); border: 1px solid color-mix(in srgb, var(--green) 26%, transparent); color: var(--green);">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z M9 12l2 2 4-4"/></svg>
      </div>
      <div class="flex-1">
        <h3 class="font-display text-[17px] font-semibold">Verify document integrity</h3>
        <p class="text-[12.5px]" style="color: var(--text-3);">Compare on-chain hash with locally recomputed hash</p>
      </div>
      <button on:click={() => dispatch("close")} class="btn-ghost w-8 h-8 rounded-[9px] grid place-items-center p-0" aria-label="Close integrity proof" title="Close">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M6 6l12 12 M18 6L6 18"/></svg>
      </button>
    </div>

    <!-- Side-by-side comparison -->
    <div class="flex gap-3.5 items-stretch flex-wrap">
      <!-- Canister hash -->
      <div class="flex-1 min-w-[200px]">
        <div class="flex items-center gap-[7px] mb-[7px]">
          <span class="text-[11px] font-bold" style="color: var(--text-3); letter-spacing: 0.03em;">CANISTER HASH</span>
          <span class="text-[10px] font-semibold px-2 py-0.5 rounded-full"
            style="color: var(--icp-purple); background: color-mix(in srgb, var(--icp-purple) 14%, transparent); border: 1px solid color-mix(in srgb, var(--icp-purple) 30%, transparent);">on-chain</span>
        </div>
        <div class="mono text-[11px] break-all leading-[1.65] p-[10px_12px] rounded-[10px]"
          style="background: var(--bg-2); border: 1px solid var(--border); min-height: 62px; transition: color .4s;
            color: {stage >= 4 ? 'var(--green)' : 'var(--text-2)'};">
          {#if hash}
            {hash}
          {:else}
            <span style="color: var(--text-4);">—</span>
          {/if}
        </div>
      </div>

      <!-- Center match indicator -->
      <div class="grid place-items-center" style="min-width: 40px;">
        <div class="w-10 h-10 rounded-full grid place-items-center"
          style="background: {stage >= 4 ? 'var(--green)' : stage === 5 ? 'var(--red)' : 'var(--surface-hi)'};
            color: {stage >= 4 ? '#06060c' : stage === 5 ? '#fff' : 'var(--text-3)'};
            transition: all .4s;
            box-shadow: {stage >= 4 ? '0 0 0 6px color-mix(in srgb, var(--green) 18%, transparent)' : stage === 5 ? '0 0 0 6px color-mix(in srgb, var(--red) 18%, transparent)' : 'none'};">
          {#if stage >= 4}
            <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6L9 17l-5-5"/></svg>
          {:else if stage === 5}
            <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M6 6l12 12 M18 6L6 18"/></svg>
          {:else if stage >= 1 && stage < 4}
            <div class="w-4 h-4 rounded-full anim-spin" style="border: 2px solid var(--surface); border-top-color: var(--icp-pink);"></div>
          {:else}
            <span class="text-lg font-bold">=</span>
          {/if}
        </div>
      </div>

      <!-- Recomputed locally -->
      <div class="flex-1 min-w-[200px]">
        <div class="flex items-center gap-[7px] mb-[7px]">
          <span class="text-[11px] font-bold" style="color: var(--text-3); letter-spacing: 0.03em;">RECOMPUTED LOCALLY</span>
          <span class="text-[10px] font-semibold px-2 py-0.5 rounded-full"
            style="color: var(--icp-cyan); background: color-mix(in srgb, var(--icp-cyan) 14%, transparent); border: 1px solid color-mix(in srgb, var(--icp-cyan) 30%, transparent);">your browser</span>
        </div>
        <div class="mono text-[11px] break-all leading-[1.65] p-[10px_12px] rounded-[10px]"
          style="background: var(--bg-2); border: 1px solid var(--border); min-height: 62px; transition: color .4s;
            color: {stage >= 4 ? 'var(--green)' : 'var(--text-2)'};">
          {#if localHash}
            {localHash}{#if localHash.length < hash.length}<span style="animation: blink 1s infinite;">▋</span>{/if}
          {:else}
            <span style="color: var(--text-4);">—</span>
          {/if}
        </div>
      </div>
    </div>

    <!-- Status message -->
    <div class="text-center mt-[18px]" style="min-height: 28px;">
      {#if stage === 1}
        <span class="text-[13px]" style="color: var(--text-3);">Fetching stored hash from canister...</span>
      {:else if stage === 2}
        <span class="text-[13px]" style="color: var(--text-3);">Downloading chunks & recomputing SHA-256 in your browser...</span>
      {:else if stage === 3}
        <span class="text-[13px]" style="color: var(--text-3);">Comparing...</span>
      {:else if stage === 4}
        <div class="scale-in inline-flex items-center gap-2.5 font-bold text-[15px]" style="color: var(--green);">
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z M9 12l2 2 4-4"/></svg>
          Integrity verified — the bytes are exactly what was stored
        </div>
      {:else if stage === 5}
        <div class="scale-in inline-flex items-center gap-2.5 font-bold text-[15px]" style="color: var(--red);">
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M6 6l12 12 M18 6L6 18"/></svg>
          Integrity check FAILED — hash mismatch detected
        </div>
      {/if}
    </div>
  </div>
</div>
