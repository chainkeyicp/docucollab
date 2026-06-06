# DocuCollab Grant Proposal

## Summary

DocuCollab is an ICP-native document sharing and collaboration MVP. It stores encrypted document chunks in a Motoko backend canister, serves the frontend through an asset canister, authenticates users with Internet Identity, and uses a dedicated AI canister for document summaries, chat, key point extraction, and categorization.

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
- AI summaries, document chat, key points, and categorization over extracted text.
- On-chain SHA-256 integrity hash checks.

## Known MVP Boundaries

- This is an MVP, not an audited secure document vault.
- Current upload guardrails are set to 50 MB per document and 1 MB chunks.
- `mo:llm` accepts text input, so non-text documents are converted to extracted text before AI analysis.
- Images and scanned PDFs require OCR and are treated as a follow-up milestone.
- Integrity verification is a canister-computed SHA-256 hash checked by the client. A future milestone can add a Merkle witness flow for stronger per-document certified proofs.
- Real-time collaborative editing is out of scope for the current MVP. The current collaboration model is sharing, access control, versioning, and audit history.

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
- AI summary generation on upload for extracted text.
- Document chat, key points, and categorization over extracted text.
- Clear OCR-required status for images and scanned PDFs.
- No unencrypted extracted text stored in the backend canister by default.

Verification:

- Demo upload of PDF, DOCX, XLSX/CSV, and image files.
- Generated summary or AI actions for readable formats.
- OCR-required message for image-only files.

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

Follow-up request: $25,000 grant for Milestone 4, OCR support, and a stronger certified integrity design using Merkle witnesses.
