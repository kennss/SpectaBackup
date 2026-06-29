# Encrypted Backup — Crypto & Key Management Design

Scope: **encryption is a per-job option for ALL backups** — local disk, **external drive**, NAS, and
cloud (an external/NAS drive can be lost or stolen too, not just the cloud). It is implemented by the
**dedup repo engine**: a job with encryption **OFF** uses the plaintext engine (clone / hardlink-tree
/ sparsebundle — Finder-browsable); a job with encryption **ON** uses the encrypted content-addressed
dedup repo on whatever backend (local / external / NAS / cloud). This document freezes the crypto so
the repo format can be versioned around it.

## Threat model
- The cloud provider and anyone who can read the repo objects must learn **nothing** about file
  contents, names, or sizes beyond unavoidable metadata (object count, total bytes, timing).
- An attacker must not be able to **forge or tamper** with objects undetectably.
- **Key loss must not be a single hardware failure away** — losing the only Mac must not lose the backup.
- Dedup must still work **within a repo**, but the provider must not be able to **fingerprint** known
  files (confirmation-of-file attack) or correlate across repos.

## Key hierarchy (3 levels)

```
user secret (password OR recovery key)            ← L1, never stored in the repo
        │  argon2id(salt_slot, params)            ← L2 KDF
        ▼
   KEK (key-encryption key, per slot)
        │  AES-256-GCM unwrap
        ▼
 repo master keys (random at repo creation)       ← L3, stored only wrapped
   • masterEncKey   — derives per-blob data keys
   • chunkIDKey     — keyed chunk IDs (HMAC) + chunker fingerprint defense
```

- **Master keys are generated once** (CSPRNG) at repo init and **never change** (rotating them
  would re-encrypt everything). They live **only as wrapped blobs** in `keys/<slotID>`.
- **Key slots:** each slot wraps the *same* master keys under a different KEK → multiple unlock
  secrets. Slots: (1) primary password, (2) **recovery key**, (3) optional per-machine password.
  Adding/removing a slot never touches data objects.
- **`config`** holds: format version, `argon2` params, per-slot `salt`, the **per-repo chunker seed**
  (random — so chunk boundaries differ per repo), and feature flags. `config` is plaintext-readable
  metadata (no secrets) but integrity-protected (MAC) so it can't be silently altered.

## Per-blob encryption (the hot path)

For each chunk (after content-defined chunking + optional LZFSE compression):

```
plaintext            = compress(chunk)            // LZFSE; skip if incompressible (flag byte)
blobID               = HMAC-SHA256(chunkIDKey, chunk_plaintext)   // KEYED → dedup + no fingerprinting
objectKey            = HKDF-SHA256(masterEncKey, info: blobID)    // unique per distinct content
nonce                = fixed (96-bit zero)                        // SAFE: objectKey is unique per blob
ciphertext‖tag       = AES-256-GCM(objectKey, nonce, plaintext)
```

Why this is safe and deliberate:
- **No nonce-reuse risk, no cross-device coordination.** Because `objectKey` is derived from
  `blobID` (the content), two *distinct* plaintexts never share `(key, nonce)`. A fixed nonce is
  therefore safe — this sidesteps the catastrophic GCM nonce-reuse problem that a single master key
  + random 96-bit nonces would hit at our blob volume, and needs **no counter** (counters break when
  two iCloud-synced Macs both write).
- **Keyed chunk IDs** (HMAC, not bare SHA-256) mean the provider can't hash known files to prove we
  store them, and the random chunker seed stops cross-repo correlation. (With encryption *off* for
  local/NAS, we fall back to plain SHA-256 and accept the leak — that path is not in the cloud repo.)
- **Encrypt per-blob, then pack.** Blobs are individually AEAD-sealed *before* being concatenated
  into pack files, so a Range read of one blob is independently decryptable and integrity-checked.
  (Whole-pack AEAD would forbid per-blob Range reads.)

Integrity on read: verify the **GCM tag**, decrypt, then verify `HMAC-SHA256(chunkIDKey, plaintext)
== blobID` (defense in depth + bit-rot detection). `trees/` and `snapshots/` objects are encrypted
the same way (keyed by their own object IDs).

## Recovery key (mandatory)
- At repo creation, generate a high-entropy recovery key (256-bit → grouped base32, e.g.
  `XXXX-XXXX-…`), show it **once**, and require the user to confirm they saved it.
- It unlocks its own key slot, so a forgotten password (or a dead Mac) can still recover the repo.
- This is what restic/borg/Arq all do; without it, "the backup that survives a dead Mac" doesn't.

## Unattended / scheduled backups (Keychain as a cache, never the only copy)
- Scheduled passes can't prompt for a password. Cache the **password or unwrapped master keys** in
  the **Keychain** with `SecAccessControl`:
  - accessibility `kSecAttrAccessibleAfterFirstUnlock` (readable post-boot without interactive unlock),
  - ACL trusting the app/helper's **code-signing identity** (so macOS doesn't prompt every run — a
    classic non-sandboxed Developer ID footgun).
- The Keychain copy is a **convenience cache**; the authoritative wrapped keys are the `keys/` repo
  objects. Losing the Keychain never loses the repo (password or recovery key still works).

## Crypto primitives → swift-crypto / CryptoKit mapping
| Need | Primitive | Source |
|---|---|---|
| Random keys / IDs | `SystemRandomNumberGenerator` / `SymmetricKey(size:)` | CryptoKit |
| KDF (master→object) | `HKDF<SHA256>` | swift-crypto / CryptoKit ✓ |
| Keyed chunk ID | `HMAC<SHA256>` | ✓ |
| AEAD | `AES.GCM` (256-bit) | ✓ |
| Password KDF | **argon2id** | **NOT in swift-crypto** → see decision |

**Decision needed — password KDF:**
- **(recommended) argon2id via vendored `libargon2`** (reference C, public-domain, tiny — a small SPM
  C target). Memory-hard, the modern standard. Adds one vendored dependency.
- Alternative: **PBKDF2-HMAC-SHA256** via CommonCrypto (`CCKeyDerivationPBKDF`) — zero dependency,
  already on macOS, but weaker against GPU/ASIC; would need a very high iteration count and is a
  known compromise. Acceptable only as a v1 stopgap with a format flag to migrate later.

## Two engines (encryption is the switch)
- **Plaintext engine** (existing): clone (APFS) / hardlink-tree / sparsebundle. Finder-browsable, APFS
  clone sharing. Used when a job's encryption is **OFF**.
- **Encrypted dedup repo engine** (this design): content-addressed chunks, per-blob AEAD, pack files.
  Used when encryption is **ON** — on ANY backend via a backend abstraction: **LocalBackend** (local /
  external disk, mounted NAS) and cloud backends (GDrive / iCloud / S3). NOT Finder-browsable (an
  opaque encrypted repo). A job selects an engine via its encryption flag + destination capabilities.

## Module shape (proposed)
A self-contained `RepoCrypto` component, independently testable before the rest of the dedup engine:
- `RepoKeys` — generate master keys; create/unlock slots; wrap/unwrap with a KEK.
- `PasswordKDF` — argon2id (or PBKDF2) → KEK.
- `BlobCipher` — `seal(plaintext) -> (blobID, ciphertext)` and `open(blobID, ciphertext) -> plaintext`
  with both GCM-tag and keyed-ID verification.
- `RecoveryKey` — generate / format / parse.
- Keychain caching with the ACL policy above.
Tests: round-trip seal/open, tamper detection (flip a byte → fail), wrong-key fails, deterministic
blobID for identical content (dedup), recovery-key unlock, slot add/remove, format-version compat
(carry the `ConfigCompatTests` discipline).

## Consistency with the Specta family
SpectaLing (Flutter) has no encryption yet (M0); the family's crypto reference is **SpectaloWhisper's
`VAULT_DESIGN.md`**. We match it: **AES-256-GCM**, **HKDF-SHA256**, **Argon2id (m≥256MiB, t≥3, p=1)**,
CryptoKit, libargon2. Intentional differences — because a backup is a **chunk-dedup repo**, not a
per-item vault:
- **Key model:** VAULT uses a random per-item DEK (enables crypto-shred). We derive per-blob keys from
  the master key by blobID — required because deduplicated blobs are shared across snapshots, so a
  per-item DEK can't be shared.
- **Nonce:** VAULT uses a random 96-bit GCM nonce (safe with single-use random DEKs); we use a fixed
  nonce — safe because the per-blob key is unique per content, and deterministic encryption is
  mandatory for dedup.
- **Deletion:** VAULT crypto-shreds by destroying a DEK; our dedup repo reclaims via refcount / prune-GC.
- **Escrow:** VAULT has Tier C (iCloud Keychain escrow) / Tier F (passphrase); we use a repo passphrase
  + forced recovery key + Keychain cache (no OS key escrow).

## Decisions (resolved)
1. **Password KDF: argon2id** (vendored `libargon2`).
2. **Encryption scope: per-job option for ALL backups** (local / external / NAS / cloud) — external
   and NAS drives can be lost/stolen, not just cloud. Encryption ON ⇒ the dedup repo engine runs on
   that backend.

**Implication for backend phasing:** the dedup engine's **LocalBackend is the first target** — an
encrypted external-drive backup is both immediately useful (lost-drive protection) and the ideal
engine *reference* (local filesystem = strong consistency, isolating engine bugs from cloud quirks).
Then Google Drive, then iCloud (CloudKit).
