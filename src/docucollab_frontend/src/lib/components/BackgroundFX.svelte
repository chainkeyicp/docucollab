<script>
  export let intense = false;
</script>

<div class="fixed inset-0 overflow-hidden pointer-events-none" style="z-index: 0;">
  <!-- gradient orbs -->
  <div class="orb orb-purple" style="top: -18%; left: -8%; width: 620px; height: 620px;
    background: radial-gradient(circle, rgba(123,63,228,0.30), transparent 62%);"></div>
  <div class="orb orb-pink" style="top: 8%; right: -12%; width: 560px; height: 560px;
    background: radial-gradient(circle, rgba(224,53,154,0.26), transparent 62%);"></div>
  <div class="orb orb-cyan" style="bottom: -20%; left: 30%; width: 600px; height: 600px;
    background: radial-gradient(circle, rgba(41,197,246,0.22), transparent 62%);"></div>
  <!-- grid -->
  <div class="grid-overlay" style="opacity: {intense ? 0.5 : 0.28};"></div>
</div>

<style>
  .orb {
    position: absolute;
    border-radius: 50%;
    filter: blur(40px);
  }
  .orb-purple { animation: float-orb 22s ease-in-out infinite; }
  .orb-pink { animation: float-orb 26s ease-in-out infinite reverse; filter: blur(44px); }
  .orb-cyan { animation: float-orb 30s ease-in-out infinite; filter: blur(48px); }

  .grid-overlay {
    position: absolute;
    inset: 0;
    background-image:
      linear-gradient(rgba(255,255,255,0.04) 1px, transparent 1px),
      linear-gradient(90deg, rgba(255,255,255,0.04) 1px, transparent 1px);
    background-size: 54px 54px;
    -webkit-mask-image: radial-gradient(ellipse 80% 60% at 50% 30%, #000 40%, transparent 100%);
    mask-image: radial-gradient(ellipse 80% 60% at 50% 30%, #000 40%, transparent 100%);
  }
</style>
