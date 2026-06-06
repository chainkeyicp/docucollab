# Tesseract OCR Assets

These files are served from the ICP frontend asset canister so browser OCR does not need jsDelivr or external language-data downloads at runtime.

- `worker.min.js` comes from the `tesseract.js` npm package.
- `core/*.wasm.js` comes from the `tesseract.js-core` npm package.
- `lang/eng.traineddata.gz` comes from `@tesseract.js-data/eng`.
- `lang/bul.traineddata.gz` comes from `@tesseract.js-data/bul`.

The runtime packages are declared in the frontend workspace dependencies. Refresh these copied assets after upgrading the OCR packages.

Licenses: `tesseract.js` and `tesseract.js-core` are Apache-2.0; `@tesseract.js-data/eng` and `@tesseract.js-data/bul` are MIT.
