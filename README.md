# DocuCollab

**Decentralized Document Sharing & Collaboration on the Internet Computer**

A decentralized document management platform with encrypted on-chain storage and AI-powered document assistance, built on ICP. No application servers, no external database -- the frontend, backend state, access control, and AI orchestration run in canisters.

**Live:** [https://ppfr3-2aaaa-aaaau-agw6q-cai.icp0.io/](https://ppfr3-2aaaa-aaaau-agw6q-cai.icp0.io/)

---

## Architecture

```
+------------------+     +-------------------+     +------------------+
|                  |     |                   |     |                  |
|  Frontend        |<--->|  Backend Canister  |<--->|  AI Canister     |
|  (Asset Canister)|     |  (Motoko)         |     |  (Motoko)        |
|  SvelteKit +     |     |                   |     |                  |
|  Tailwind CSS    |     |  - Documents      |     |  - ICP LLM       |
|                  |     |  - Users          |     |  - Optional      |
|  ppfr3-2aaaa...  |     |  - Access Control |     |    HTTPS Outcalls|
|                  |     |  - Activity Log   |     |                  |
+------------------+     |  - Versioning     |     |  pgg2h-miaaa...  |
         |                |                   |     +------------------+
         |                |  piexp-xyaaa...   |
         |                +-------------------+
         |
         v
+------------------+
|  Internet        |
|  Identity (id.ai)|
|  Authentication  |
+------------------+
```

### Canisters (Mainnet)

| Canister | ID | Purpose |
|----------|-----|---------|
| Backend | `piexp-xyaaa-aaaau-agw6a-cai` | Document storage, access control, versioning, activity log |
| AI | `pgg2h-miaaa-aaaau-agw7a-cai` | On-chain AI assistance via `mo:llm`, with optional premium HTTPS outcall support |
| Frontend | `ppfr3-2aaaa-aaaau-agw6q-cai` | SvelteKit static app served as certified assets |

## Features

### Core Document Management
- **Chunked upload** -- 1MB chunks support large files on-chain
- **File preview** -- inline preview for text, images, and PDFs
- **Search & filter** -- search by name, sort by date/size/name
- **Batch operations** -- multi-select, batch delete, batch share

### AI Summarization & Document Chat
- Automatic AI summary generation for AI-readable documents on upload
- Client-side text extraction for TXT/MD/JSON/HTML, PDF, DOCX, CSV, and XLSX before encryption
- Default AI path uses the ICP LLM canister through `mo:llm`
- Document chat, key point extraction, and categorization over extracted document text
- Images and scanned PDFs are detected as OCR-required instead of being misrepresented as LLM-readable
- Optional premium mode can call an external Claude API through HTTPS outcalls when configured
- **Demonstrates ICP-unique capability**: smart contracts can orchestrate AI and external API calls without an application server

### Access Control & Sharing
- Share documents by Principal ID or username search
- Real-time principal validation with user lookup
- Owner-only operations (upload, delete, share, revoke)
- Access expiration support

### Document Versioning
- Upload new versions of existing documents
- Full version history with size and timestamp tracking
- Version badges in document list (v1, v2, v3...)

### Activity Log (Audit Trail)
- Every action recorded: upload, share, revoke, delete, AI summary
- Tamper-proof -- stored in canister stable memory
- Timeline view with icons and timestamps
- Per-user activity filtering

### Storage & Stats
- Dashboard with document count, shared count, storage used
- Platform-wide stats (total users, total documents)
- MVP upload guardrails: 50 MB max document size, 1 MB chunks

### Authentication
- Internet Identity via id.ai -- passwordless, privacy-preserving
- Principal-based identity with username registration
- 24-hour idle timeout, 7-day delegation

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Backend | Motoko |
| Frontend | SvelteKit + Tailwind CSS |
| Auth | Internet Identity (id.ai) |
| AI | ICP LLM canister via `mo:llm`; optional Claude HTTPS outcalls |
| File Text Extraction | `pdfjs-dist`, `mammoth`, `read-excel-file` |
| Deployment | dfx SDK v0.25.0 |

## DocuCollab vs DocuTrack

| Feature | DocuTrack (DFINITY PoC) | DocuCollab |
|---------|------------------------|------------|
| AI Summarization | No | Yes (`mo:llm`, optional HTTPS outcalls) |
| Document Versioning | No | Yes |
| Activity / Audit Log | No | Yes |
| File Preview (img/pdf) | No | Yes |
| Search & Filter | No | Yes |
| Batch Operations | No | Yes |
| Username-based Sharing | No | Yes |
| Storage Quota Display | No | Yes |
| Mobile Responsive | Basic | Full |
| Tech Stack | Rust + SvelteKit | Motoko + SvelteKit |

## Quick Start

### Prerequisites
- [dfx SDK](https://internetcomputer.org/docs/current/developer-docs/setup/install) v0.25.0+
- Node.js 20.19+
- pnpm

### Local Development

```bash
# Start local replica
dfx start --background

# Deploy all canisters
dfx deploy

# Frontend dev server
cd src/docucollab_frontend
pnpm install
pnpm run dev
```

### Mainnet Deployment

```bash
# Ensure you have cycles
dfx cycles balance --network ic

# Deploy
export DFX_WARNING=-mainnet_plaintext_identity
dfx deploy --network ic
```

## Project Structure

```
docucollab/
  dfx.json                          # Canister configuration
  src/
    docucollab_backend/
      main.mo                       # Backend canister (documents, users, access, versioning, activity)
    docucollab_ai/
      main.mo                       # AI canister (on-chain LLM, optional HTTPS outcalls)
    docucollab_frontend/
      src/
        routes/+page.svelte         # Main page (landing, dashboard)
        lib/
          components/
            ActivityLog.svelte      # Activity timeline
            DocumentList.svelte     # Document grid with search/filter/batch
            DocumentView.svelte     # Document viewer with preview/versioning
            FileUpload.svelte       # Drag & drop chunked upload
            Navbar.svelte           # Navigation with dark mode
            ShareModal.svelte       # Share by principal/username
            Notification.svelte     # Toast notifications
          services/
            auth.js                 # Internet Identity auth service
            fileTextExtractors.js   # Client-side AI-readable text extraction
          stores/
            app.js                  # Svelte stores
      tailwind.config.js
      vite.config.js
```

## ICP-Unique Features Used

1. **On-chain AI** -- AI canister uses the ICP LLM package for document summaries, chat, key points, and categorization
2. **Internet Identity** -- Passwordless auth with privacy-preserving principals
3. **Certified Assets** -- Frontend served with cryptographic verification
4. **Stable Memory** -- Data persists across canister upgrades
5. **On-chain SHA-256 integrity checks** -- document chunk hashes are computed in the backend canister and can be verified by the client
6. **Client-side extraction before encrypted storage** -- AI-readable text is derived in the browser so plaintext document text is not stored unencrypted in the backend canister
7. **Optional HTTPS Outcalls** -- premium AI mode can call an external API directly from a canister when configured

## License

MIT
