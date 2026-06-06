# DocuCollab

**Decentralized Document Sharing & Collaboration on the Internet Computer**

A fully on-chain document management platform with AI-powered summarization, built on ICP. No servers, no cloud storage -- everything runs in canisters.

**Live:** [https://ppfr3-2aaaa-aaaau-agw6q-cai.icp0.io/](https://ppfr3-2aaaa-aaaau-agw6q-cai.icp0.io/)

---

## Architecture

```
+------------------+     +-------------------+     +------------------+
|                  |     |                   |     |                  |
|  Frontend        |<--->|  Backend Canister  |<--->|  AI Canister     |
|  (Asset Canister)|     |  (Motoko)         |     |  (Motoko)        |
|  SvelteKit +     |     |                   |     |                  |
|  Tailwind CSS    |     |  - Documents      |     |  - HTTPS Outcalls|
|                  |     |  - Users          |     |  - Claude API    |
|  ppfr3-2aaaa...  |     |  - Access Control |     |  - Summarization |
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
| AI | `pgg2h-miaaa-aaaau-agw7a-cai` | AI summarization via HTTPS outcalls to Claude API |
| Frontend | `ppfr3-2aaaa-aaaau-agw6q-cai` | SvelteKit static app served as certified assets |

## Features

### Core Document Management
- **Chunked upload** -- 1MB chunks support large files on-chain
- **File preview** -- inline preview for text, images, and PDFs
- **Search & filter** -- search by name, sort by date/size/name
- **Batch operations** -- multi-select, batch delete, batch share

### AI Summarization (ICP HTTPS Outcalls)
- Automatic AI summary generation for text documents on upload
- Canister-to-canister call triggers HTTPS outcall to Claude API
- Summary displayed in document detail panel
- **Demonstrates ICP-unique capability**: smart contracts calling external APIs directly

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
- Storage quota progress bar (2 GB limit display)

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
| AI | HTTPS Outcalls to Claude API |
| Deployment | dfx SDK v0.25.0 |

## DocuCollab vs DocuTrack

| Feature | DocuTrack (DFINITY PoC) | DocuCollab |
|---------|------------------------|------------|
| AI Summarization | No | Yes (HTTPS Outcalls) |
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
- Node.js 18+
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
      main.mo                       # AI canister (HTTPS outcalls, summarization)
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
          stores/
            app.js                  # Svelte stores
      tailwind.config.js
      vite.config.js
```

## ICP-Unique Features Used

1. **HTTPS Outcalls** -- AI canister calls Claude API directly from a smart contract
2. **Internet Identity** -- Passwordless auth with privacy-preserving principals
3. **Certified Assets** -- Frontend served with cryptographic verification
4. **Stable Memory** -- Data persists across canister upgrades
5. **100% On-Chain** -- No servers, no databases, no cloud storage

## License

MIT
