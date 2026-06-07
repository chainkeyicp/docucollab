# DocuCollab Grant Proposal

## Summary

DocuCollab is an ICP-native document sharing and collaboration MVP. It stores encrypted document chunks in a Motoko backend canister, serves the frontend through an asset canister, authenticates users with Internet Identity, and uses a dedicated AI canister for automatic encrypted document summaries, chat, key point extraction, and categorization.

Live demo: https://ppfr3-2aaaa-aaaau-agw6q-cai.icp0.io/

## Why ICP

DocuCollab is built around capabilities that are specific to the Internet Computer:

- Canisters host both application logic and document state.
- Internet Identity provides passwordless authentication without a separate auth server.
- The reverse gas model lets end users upload and share documents without wallet prompts.
- The AI canister uses `mo:llm` for on-chain document assistance, with optional HTTPS outcalls for premium AI providers.
- Document integrity hashes are computed and stored by the backend canister.
- The frontend is served from certified assets instead of a Web2 hosting service.

## Current MVP

- Mainnet deployment with backend, AI, and frontend canisters.
- Client-side AES-GCM document encryption.
- RSA-OAEP document key wrapping for registered recipients.
- Chunked upload and download.
- Principal and username-based sharing.
- Document previews for text, images, and PDFs.
- Version history.
- Per-user activity log.
- Client-side AI-readable text extraction for TXT/MD/JSON/HTML, PDF, DOCX, CSV, and XLSX.
- Browser-side OCR via Tesseract.js for images and scanned PDFs, with English and Bulgarian OCR runtime/language assets served from the frontend asset canister.
- Automatic encrypted AI summaries, document chat, key points, and categorization over extracted text.
- AI summaries are encrypted in the browser with the document key before canister storage.
- Search across document names and locally decrypted AI-generated summaries.
- On-chain SHA-256 integrity hash checks.

## Known MVP Boundaries

- This is an MVP, not an audited secure document vault.
- Current upload guardrails are set to 50 MB per document and 1 MB chunks.
- `mo:llm` accepts text input, so non-text documents are converted to extracted text before AI analysis.
- Images and scanned PDFs are OCR-processed client-side via Tesseract.js. This extracts visible text; AI vision for describing non-text image content depends on future ICP LLM multimodal support.
- Plain extracted document text is transient in the browser and is not stored in the backend canister. For AI-readable files, DocuCollab generates a summary by default after upload, then encrypts that generated summary locally with the document key before canister storage. The canister stores summary ciphertext and nonce; owners and shared recipients can decrypt summaries only when they have the document key.
- Integrity verification is a canister-computed SHA-256 hash checked by the client. A future milestone can add a Merkle witness flow for stronger per-document certified proofs.
- Real-time collaborative editing is out of scope for the current MVP. The current collaboration model is sharing, access control, versioning, and audit history.

The repository includes `THREAT_MODEL.md` with the MVP privacy boundaries, metadata model, and reviewer checklist.

## Proposed Grant Scope

### Milestone 1: Hardened Sharing and Versioning

Deliverables:

- Reliable encrypted sharing between two Internet Identity users.
- Recipient-side key unwrap and preview/download flow.
- Encrypted version upload with updated integrity hash.
- Duplicate-share and self-share prevention.
- Username uniqueness and backend upload guardrails.

Verification:

- Demo video with two users: upload, share, recipient open, update version, verify hash.
- Public source and deployed canisters.

### Milestone 2: Reviewer-Ready Security and Test Pass

Deliverables:

- Smoke test script for register, upload, share, revoke, version, delete.
- Documented threat model and MVP limitations.
- Public activity log removed or restricted to admin.
- AI input limits and clearer premium outcall configuration.

Verification:

- `dfx build`
- `npm run build`
- `svelte-check`
- Test transcript in repository.

### Milestone 3: Multi-format AI Readiness

Deliverables:

- Browser-side extraction for PDF, DOCX, CSV, XLSX, and plain-text formats.
- Browser-side OCR for images and scanned PDFs via self-hosted Tesseract.js WebAssembly assets.
- Automatic encrypted AI summary generation on upload for extracted and OCR-processed text.
- Document chat, key points, and categorization over extracted text.
- Search across document names and locally decrypted AI-generated summaries.
- No unencrypted extracted text or new plaintext summaries stored in the backend canister; generated summaries are stored encrypted.

Verification:

- Demo upload of PDF, DOCX, XLSX/CSV, and image files.
- Generated summary or AI actions for readable formats.
- OCR text extraction from image uploads and scanned PDFs.
- Search returning results by decrypted summary content, not just filename.

### Milestone 4: Collaboration Layer

Deliverables:

- Document comments or annotations.
- Approval/review status per document.
- Activity filtering by document.
- Exportable audit trail.

Verification:

- Demo showing a shared document review workflow between two users.

## Requested Funding

Recommended first request: $5,000 micro grant for Milestones 1, 2, and 3.

Follow-up request: $25,000 grant for Milestone 4, AI vision support (pending ICP LLM multimodal), and a stronger certified integrity design using Merkle witnesses.
