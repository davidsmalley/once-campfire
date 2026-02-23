# Cross-Platform E2EE Implementation Plan

## Architecture Overview

**Model: WhatsApp-style Multi-Device**

Each user device (iOS, web) has its own Signal Protocol identity and establishes
sessions independently. iOS is the primary device; web is a linked secondary
device provisioned by iOS via QR code.

```
 iOS Device (primary)           Web Device (linked)
 ┌────────────────────┐        ┌────────────────────┐
 │  libsignal-swift   │        │  signal-wasm (WASM) │
 │  Identity Key A    │        │  Identity Key B     │
 │  Sessions[...]     │        │  Sessions[...]      │
 └────────┬───────────┘        └────────┬────────────┘
          │                             │
          └──────────┐  ┌───────────────┘
                     ▼  ▼
              ┌──────────────┐
              │   Campfire   │
              │   Backend    │
              │              │
              │ devices      │  ← NEW: per-user device registry
              │ key_bundles  │  ← MODIFIED: per-device (not per-user)
              │ pre_keys     │  ← MODIFIED: per-device
              │ messages     │  ← body stores e2e:v1:... ciphertext
              └──────────────┘
```

**Wire format:** `e2e:v1:<base64(serialized SignalMessage protobuf)>`

**Key decisions:**
- Messages are encrypted per-recipient-device (sender encrypts N copies for N devices)
- The server stores one message row; encrypted body contains a JSON envelope with per-device ciphertexts
- Web requires iOS to provision it (device linking via QR code)
- Both platforms use the same underlying libsignal Rust code (Swift bindings on iOS, WASM on web)

---

## Current State

### What exists:
- `key_bundles` table: per-user (unique on user_id), stores identity_key, signed_pre_key, signature, signed_pre_key_id
- `pre_keys` table: per-user, stores key_id + public_key
- `KeyBundlesController`: create (upsert), show (fetch + consume pre-key), destroy
- `rooms.encrypted` boolean column
- Web: custom EncryptionManager (X3DH + AES-GCM, NOT libsignal-compatible)
- iOS: libsignal imported and passing tests, no integration yet

### What needs to change:
- Key bundles must become per-device (not per-user)
- Need a `devices` table to track each user's devices
- Need device linking endpoint for QR code provisioning
- Web crypto must be replaced with signal-wasm
- Message body format needs to support per-device ciphertexts
- iOS needs full EncryptionManager integration

---

## Stage 1: Backend Multi-Device Support
**Goal**: Refactor the backend from per-user to per-device key bundles, add device registration
**Success Criteria**: API supports registering devices, uploading per-device key bundles, fetching all devices for a user
**Status**: Not Started

### Database Changes

#### Migration: Create `devices` table
```ruby
create_table :devices do |t|
  t.references :user, null: false, foreign_key: true, index: true
  t.integer :device_id, null: false  # libsignal device ID (1 = primary iOS, 2+ = linked)
  t.string :name                      # "iPhone", "Web - Chrome", etc.
  t.string :platform                  # "ios", "web"
  t.datetime :last_active_at
  t.timestamps
end
add_index :devices, [:user_id, :device_id], unique: true
```

#### Migration: Add `device_id` to `key_bundles` and `pre_keys`
```ruby
# key_bundles: change unique index from user_id to [user_id, device_id]
add_column :key_bundles, :device_id, :integer, null: false, default: 1
remove_index :key_bundles, :user_id
add_index :key_bundles, [:user_id, :device_id], unique: true

# Also add registration_id (required by libsignal)
add_column :key_bundles, :registration_id, :integer, null: false, default: 0

# pre_keys: add device_id, update unique index
add_column :pre_keys, :device_id, :integer, null: false, default: 1
remove_index :pre_keys, [:user_id, :key_id]
add_index :pre_keys, [:user_id, :device_id, :key_id], unique: true
```

### API Changes

#### Device registration
```
POST   /api/v1/users/me/devices       → register a new device
GET    /api/v1/users/me/devices       → list my devices
DELETE /api/v1/users/me/devices/:id   → unlink a device
```

#### Key bundles become per-device
```
POST   /api/v1/users/me/devices/:device_id/keys   → upload keys for a device
GET    /api/v1/users/:user_id/devices              → list user's devices (public)
GET    /api/v1/users/:user_id/devices/:device_id/keys → fetch bundle for specific device
DELETE /api/v1/users/me/devices/:device_id/keys    → reset keys for a device
```

#### Backwards compatibility
Keep existing endpoints working during migration:
- `POST /api/v1/users/me/keys` → defaults to device_id=1
- `GET /api/v1/users/:id/keys` → returns device_id=1 bundle

### Models
- `Device` model: belongs_to :user, has_one :key_bundle, has_many :pre_keys
- `KeyBundle`: add device_id, belongs_to :device (optional, for migration)
- `PreKey`: add device_id

### Tests
- Register a device, verify it appears in device list
- Upload keys for specific device, fetch them back
- Fetch all devices for a user (returns device IDs + identity keys)
- Old single-device endpoints still work (backwards compat)
- Cannot register duplicate device_id for same user
- Unlinking a device removes its key bundle and pre-keys

---

## Stage 2: iOS E2EE Integration (EncryptionManager)
**Goal**: iOS app generates keys via libsignal, uploads to server, can encrypt/decrypt direct messages
**Success Criteria**: Two iOS devices can exchange encrypted messages in a direct room
**Status**: Not Started

### Components

#### SignalProtocolStore (implements libsignal store protocols)
Wraps Keychain/CoreData storage, implements:
- `IdentityKeyStore` — get/save identity key pair, trusted identities
- `PreKeyStore` — load/store/remove pre-keys
- `SignedPreKeyStore` — load/store/remove signed pre-keys
- `SessionStore` — load/store sessions per (address, device_id)
- `SenderKeyStore` — load/store sender keys (for future group encryption)

#### EncryptionManager
```swift
class EncryptionManager {
    let store: SignalProtocolStore
    let apiClient: CampfireAPIClient

    func initialize() async throws
    // Generate identity key, signed pre-key, 100 pre-keys
    // Upload to server via POST /api/v1/users/me/devices/:device_id/keys

    func encrypt(_ plaintext: String, for recipientUserId: Int) async throws -> String
    // 1. Fetch recipient's device list + key bundles
    // 2. For each device: processPreKeyBundle if no session, then signalEncrypt
    // 3. Return e2e:v1:<envelope JSON with per-device ciphertexts>

    func decrypt(_ body: String, from senderUserId: Int, senderDeviceId: Int) async throws -> String
    // 1. Parse e2e:v1: prefix, extract envelope
    // 2. Find ciphertext for our device_id
    // 3. signalDecrypt or signalDecryptPreKey
    // 4. Return plaintext
}
```

#### Wire Format (multi-device envelope)
```json
{
  "v": 1,
  "sender_device": 1,
  "payloads": {
    "3:1": "<base64 SignalMessage for user 3, device 1>",
    "3:2": "<base64 SignalMessage for user 3, device 2>"
  }
}
```
Stored as: `e2e:v1:<base64(JSON envelope)>`

#### Integration Points
- On login: call `encryptionManager.initialize()` to generate/upload keys
- In message composer: encrypt before sending
- In message list: decrypt when displaying
- Register device with `POST /api/v1/users/me/devices` on first launch

### Tests
- Key generation produces valid libsignal key bundle
- Upload keys to server, fetch them back, verify they match
- Two simulated users can perform X3DH and exchange messages
- Encrypted message round-trips through the server correctly
- Pre-key consumption works (first message establishes session)
- Subsequent messages use established session (no pre-key needed)

---

## Stage 3: Web Signal Protocol via WASM
**Goal**: Replace the custom Web Crypto encryption with signal-wasm, making web crypto interoperable with iOS libsignal
**Success Criteria**: Web client can generate valid libsignal key bundles and encrypt/decrypt messages
**Status**: Not Started

### Approach: Vendor @getmaapp/signal-wasm

1. Download the WASM binary + JS glue from the npm package
2. Place in `vendor/javascript/signal-wasm/`
3. Host `.wasm` file at `public/signal-wasm/signal_wasm_bg.wasm`
4. Pin JS entry point in importmap:
   ```ruby
   pin "signal-wasm", to: "signal-wasm/signal_wasm.js"
   ```

### Rewrite EncryptionManager
Replace `app/javascript/lib/encryption/encryption_manager.js`:
- Use `SignalClient` from signal-wasm instead of raw Web Crypto
- Same API surface: `initialize()`, `encryptForDirect()`, `decrypt()`, `isEncrypted()`
- IndexedDB key store adapts to signal-wasm's storage interface
- Key bundle service updated for per-device endpoints

### Key Changes
- `key_store.js`: Adapt IndexedDB stores to match signal-wasm's requirements
- `key_bundle_service.js`: Update endpoints to per-device URLs
- `encryption_manager.js`: Complete rewrite using signal-wasm API
- `composer_controller.js`: Update to use multi-device envelope format
- `messages_controller.js` (Stimulus): Update decrypt to parse envelope, find our device's ciphertext

### Tests
- signal-wasm loads and initializes in the browser
- Key generation produces keys in same format as iOS libsignal
- Web-generated key bundle can be fetched and used by iOS (and vice versa)
- Message encrypted by web can be decrypted by iOS
- Message encrypted by iOS can be decrypted by web

---

## Stage 4: Device Linking (QR Code Flow)
**Goal**: iOS can provision a web browser as a linked device via QR code scanning
**Success Criteria**: User scans QR code on iOS, web device is linked and can decrypt messages
**Status**: Not Started

### Protocol

```
Web Browser                    Server                     iOS App
    │                            │                           │
    │  1. Generate temp ECDH     │                           │
    │     key pair               │                           │
    │                            │                           │
    │  2. POST /api/v1/          │                           │
    │     device_links           │                           │
    │     {web_public_key}       │                           │
    │  ←── link_id + link_code   │                           │
    │                            │                           │
    │  3. Display QR code:       │                           │
    │     link_id + link_code    │                           │
    │     + web_public_key       │                           │
    │                            │                           │
    │                            │  4. Scan QR code          │
    │                            │                           │
    │                            │  5. PUT /api/v1/          │
    │                            │     device_links/:id      │
    │                            │     {ios_public_key,      │
    │                            │      encrypted_provision} │
    │                            │  ←── OK                   │
    │                            │                           │
    │  6. Poll GET /api/v1/      │                           │
    │     device_links/:id       │                           │
    │  ←── ios_public_key +      │                           │
    │      encrypted_provision   │                           │
    │                            │                           │
    │  7. ECDH → shared secret   │                           │
    │     Decrypt provision data │                           │
    │     (contains device_id,   │                           │
    │      identity key seed)    │                           │
    │                            │                           │
    │  8. Generate device keys   │                           │
    │     from seed              │                           │
    │                            │                           │
    │  9. Register device +      │                           │
    │     upload key bundle      │                           │
    │                            │                           │
    │  10. Device linked! ✓      │                           │
```

### Backend: DeviceLinksController
```
POST   /api/v1/device_links      → create link request (web initiates)
GET    /api/v1/device_links/:id  → poll for provisioning data (web polls)
PUT    /api/v1/device_links/:id  → complete link (iOS provides encrypted keys)
DELETE /api/v1/device_links/:id  → cancel link
```

#### Migration: Create `device_links` table
```ruby
create_table :device_links do |t|
  t.references :user, null: false, foreign_key: true
  t.string :link_code, null: false       # short code for QR
  t.binary :web_public_key, null: false   # temp ECDH public key from web
  t.binary :ios_public_key                # temp ECDH public key from iOS
  t.binary :encrypted_provision           # encrypted key material
  t.string :status, default: "pending"    # pending, completed, expired
  t.datetime :expires_at, null: false
  t.timestamps
end
add_index :device_links, :link_code, unique: true
```

### Provision Data (encrypted with ECDH shared secret)
```json
{
  "device_id": 2,
  "identity_key_seed": "<base64 seed for deterministic key generation>",
  "registration_id": 12345
}
```

The web device uses the seed to generate its own identity key pair deterministically,
so iOS knows the web's identity key without the web needing to send it back.

### Tests
- Create device link, verify link_code generated
- QR code contains correct data
- iOS can complete the link with encrypted provision
- Web can poll and receive provision data
- Web decrypts provision and generates valid keys
- Device link expires after timeout
- Cannot complete an already-completed link

---

## Stage 5: Multi-Device Message Delivery
**Goal**: Messages encrypted for all recipient devices, each device decrypts its own copy
**Success Criteria**: User with iOS + web receives and can read encrypted messages on both devices
**Status**: Not Started

### Message Body Format

For encrypted rooms, the message body stored in ActionText contains the envelope:
```
e2e:v1:<base64 of JSON envelope>
```

Envelope structure:
```json
{
  "v": 1,
  "sid": 5,          // sender user ID
  "sd": 1,           // sender device ID
  "p": {
    "3:1": "base64",  // recipient user_id:device_id → SignalMessage
    "3:2": "base64"   // same message encrypted for user 3's second device
  }
}
```

### Sender Flow (iOS or Web)
1. Get plaintext from composer
2. Fetch recipient's devices: `GET /api/v1/users/:id/devices`
3. For each device:
   a. Check if session exists locally
   b. If not, fetch key bundle: `GET /api/v1/users/:id/devices/:device_id/keys`
   c. Process pre-key bundle to establish session
   d. Encrypt plaintext → SignalMessage
4. Build envelope JSON with all per-device ciphertexts
5. POST message with `e2e:v1:<base64(envelope)>` as body

### Receiver Flow (iOS or Web)
1. Receive message (via ActionCable Turbo Stream or API poll)
2. Detect `e2e:v1:` prefix
3. Decode envelope JSON
4. Find entry for `myUserId:myDeviceId` in payloads
5. Decrypt using Signal session → plaintext
6. Display plaintext in UI

### Server Changes
- No server-side changes to message model needed (body is opaque text)
- The server never sees plaintext — it stores and delivers the envelope as-is
- Messages helper: update `message_encrypted_presentation` to include device info in data attributes

### Edge Cases
- New device added after messages were sent → cannot decrypt old messages (expected, same as Signal)
- Device removed → sender stops encrypting for that device on next message
- Pre-key exhaustion → server returns bundle without pre-key, sender uses signed pre-key only

### Tests
- Sender encrypts for multiple devices, each device can decrypt its portion
- Adding a new device: old messages show "encrypted, view on original device"
- Removing a device: subsequent messages no longer include that device
- Message from iOS decryptable on web (and vice versa)
- Pre-key is consumed on first message, subsequent messages use session

---

## Migration Path

### Phase A: Deploy Stage 1 (backend)
- Add devices table and per-device key bundles
- Old endpoints remain backwards-compatible (device_id defaults to 1)
- No client changes required

### Phase B: Deploy Stage 2 (iOS)
- iOS registers as device_id=1 on login
- iOS generates keys, uploads to new per-device endpoints
- iOS encrypts/decrypts in direct rooms marked as encrypted
- Web continues to work for non-encrypted rooms (no changes)

### Phase C: Deploy Stage 3 (web WASM)
- Replace web crypto with signal-wasm
- Web now speaks the same protocol as iOS
- Web cannot yet decrypt (no device keys provisioned)

### Phase D: Deploy Stage 4 (device linking)
- QR code flow enables web to become a linked device
- Web generates its own key bundle after provisioning
- Web can now send and receive encrypted messages

### Phase E: Deploy Stage 5 (multi-device delivery)
- Senders encrypt for all recipient devices
- Both iOS and web show decrypted messages
- Full E2EE operational across platforms

---

## Open Questions

1. **signal-wasm maturity**: v0.1.0 is very new. Should we evaluate it first with a
   standalone test before committing? Alternative: build our own WASM from Signal's
   Rust source.

2. **Group rooms**: This plan covers direct (1:1) rooms only. Group E2EE would use
   Sender Keys (libsignal supports this). Defer to a future stage.

3. **Key backup/recovery**: If a user loses their iOS device, all encrypted message
   history is lost. Do we need encrypted key backup? Defer for now.

4. **Pre-key replenishment**: When pre-keys run low, devices need to generate and
   upload more. Both clients need a background mechanism for this.

5. **Identity key verification**: Should users be able to verify each other's identity
   keys (safety numbers)? Nice-to-have for a future stage.
