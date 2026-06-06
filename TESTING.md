# Testing Notes

Last checked: 2026-06-06

## Automated Checks

```bash
dfx build
```

Result: passes.

Known warning: `Cycles.add` is deprecated in the current Motoko compiler. The replacement `with cycles` syntax is recommended by the warning, but this project currently targets `dfx 0.25.0`, whose `moc` rejected that syntax during testing. The project keeps `Cycles.add` for build compatibility.

```bash
cd src/docucollab_frontend
npx svelte-check --tsconfig ./tsconfig.json
```

Result: passes with 0 errors and 0 warnings.

```bash
npm run build
```

Result: passes.

Known warning: Vite/SvelteKit emits dependency export warnings related to the installed SvelteKit/Svelte combination. These warnings were present before the grant-readiness changes and do not fail the production build.

## Browser Smoke Test

Local URL: `http://127.0.0.1:5178/`

Checked:

- Page title is `DocuCollab - Decentralized Document Collaboration`.
- Landing headline is visible.
- Updated labels `On-Chain Hash` and `ICP Native` are visible.
- Old claims `2 GB` and `Certified Integrity` are not visible.
- Browser console has 0 errors on initial load.
