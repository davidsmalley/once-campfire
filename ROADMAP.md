# Campfire Fork - Project Roadmap

## Overview

This is a fork of 37signals' open-source Campfire chat application. The goals are:

1. **Maintain and improve the web application** - fix bugs, add features for our group
2. **Build a native iOS app** - push notifications, native UX, offline support
3. **Add end-to-end encryption** - using the Signal Protocol (Double Ratchet + X3DH)
4. **Expose a JSON API** - shared backend for web and mobile clients

---

## Architecture Summary (Current State)

| Layer | Technology |
|-------|-----------|
| Framework | Rails (edge/main branch) |
| Database | SQLite |
| Real-time | ActionCable (WebSockets) via Turbo Streams |
| Background jobs | Resque + Redis |
| Assets | Propshaft + Importmap |
| Frontend | Hotwire (Turbo + Stimulus) |
| Push notifications | Web Push (VAPID) |
| Authentication | Cookie-based sessions + bcrypt passwords |
| File storage | ActiveStorage (local disk) |
| Search | SQLite FTS5 |
| Deployment | Docker, single-machine, Puma + Thruster |

---

## Phase 1: JSON API Layer

The existing app is Hotwire-driven (HTML-over-the-wire). The iOS app needs a proper JSON API. Rather than a separate API-only app, we add an `Api::` namespace to the existing Rails app.

### API Design

**Authentication**: Token-based (bearer tokens). Reuse the existing `sessions` table — the `token` column already stores unique session tokens. The mobile client sends `Authorization: Bearer <token>` on every request.

**Endpoints** (v1):

```
POST   /api/v1/auth/sign_in          # email + password -> session token
DELETE /api/v1/auth/sign_out          # destroy session

GET    /api/v1/rooms                  # list rooms (open, closed, direct)
GET    /api/v1/rooms/:id              # room details + members
POST   /api/v1/rooms                  # create room

GET    /api/v1/rooms/:room_id/messages             # paginated messages
POST   /api/v1/rooms/:room_id/messages             # send message
GET    /api/v1/rooms/:room_id/messages/:id          # single message
PUT    /api/v1/rooms/:room_id/messages/:id          # edit message
DELETE /api/v1/rooms/:room_id/messages/:id          # delete message

POST   /api/v1/messages/:message_id/boosts          # add reaction
DELETE /api/v1/messages/:message_id/boosts/:id       # remove reaction

GET    /api/v1/users/me                              # current user profile
PUT    /api/v1/users/me                              # update profile
GET    /api/v1/users/:id                             # view user

POST   /api/v1/push_subscriptions                    # register device for push (APNs)
DELETE /api/v1/push_subscriptions/:id                # unregister

GET    /api/v1/rooms/:room_id/involvement            # notification preferences
PUT    /api/v1/rooms/:room_id/involvement            # update preferences

POST   /api/v1/searches                              # search messages
```

**Real-time**: ActionCable already supports WebSocket connections. The iOS app connects via WebSocket to receive Turbo Stream broadcasts. We also add JSON-formatted ActionCable channels for native clients.

### Implementation Tasks

- [x] Add `Api::V1::BaseController` with token auth
- [x] Add API routes under `/api/v1`
- [x] Add JSON serialization (inline `*_json` helpers)
- [x] Add API-specific ActionCable authentication (token in connection params)
- [x] Add request specs for all API endpoints
- [x] Add rate limiting (auth endpoint)
- [x] Add API versioning strategy (v1 namespace)

---

## Phase 2: iOS App (Swift/SwiftUI)

### Technology Choices

| Concern | Choice | Rationale |
|---------|--------|-----------|
| UI Framework | SwiftUI | Modern, declarative, less code |
| Networking | URLSession + async/await | No dependencies needed |
| WebSocket | URLSessionWebSocketTask | Native, no dependencies |
| Local storage | SwiftData | Apple's modern persistence layer |
| Push notifications | APNs (Apple Push Notification service) | Required for iOS |
| Keychain | Security framework | Store auth tokens and encryption keys |
| Image loading | AsyncImage + custom cache | Minimal dependencies |

### App Structure

```
CampfireApp/
├── App/
│   ├── CampfireApp.swift              # App entry point
│   └── AppState.swift                 # Global state / DI
├── Models/
│   ├── Room.swift
│   ├── Message.swift
│   ├── User.swift
│   └── Boost.swift
├── Networking/
│   ├── APIClient.swift                # HTTP client
│   ├── WebSocketClient.swift          # ActionCable client
│   └── Endpoints.swift                # API endpoint definitions
├── Features/
│   ├── Auth/
│   │   ├── SignInView.swift
│   │   └── AuthViewModel.swift
│   ├── Rooms/
│   │   ├── RoomListView.swift
│   │   ├── RoomDetailView.swift
│   │   └── RoomViewModel.swift
│   ├── Messages/
│   │   ├── MessageListView.swift
│   │   ├── MessageComposerView.swift
│   │   ├── MessageBubbleView.swift
│   │   └── MessagesViewModel.swift
│   ├── Profile/
│   │   ├── ProfileView.swift
│   │   └── ProfileViewModel.swift
│   └── Settings/
│       └── SettingsView.swift
├── Services/
│   ├── NotificationService.swift      # APNs registration
│   ├── KeychainService.swift          # Secure storage
│   └── PushHandler.swift              # Handle incoming pushes
├── Encryption/                        # Phase 3
│   ├── SignalProtocol/
│   └── EncryptionService.swift
└── Utilities/
    ├── Extensions/
    └── Constants.swift
```

### Key Features

- **Offline support**: Cache rooms and recent messages in SwiftData. Show cached content while loading.
- **Push notifications**: Register APNs device token with the server. Display rich notifications with message previews.
- **Background refresh**: Use BGAppRefreshTask to sync unread counts.
- **Deep linking**: Tap a notification to navigate directly to the room/message.
- **Haptic feedback**: Subtle haptics on send, receive, and reactions.
- **Share extension**: Share images/files from other apps into Campfire rooms.

### Implementation Tasks

- [ ] Set up Xcode project with SwiftUI lifecycle
- [ ] Implement APIClient with token auth
- [ ] Implement ActionCable WebSocket client in Swift
- [ ] Build authentication flow (sign in, token storage)
- [ ] Build room list with unread indicators
- [ ] Build message list with pagination (load-more on scroll)
- [ ] Build message composer (text + attachments)
- [ ] Implement push notification registration and handling
- [ ] Add offline caching with SwiftData
- [ ] Add rich link previews
- [ ] Add reaction/boost support
- [ ] Add search
- [ ] Add user profile views
- [ ] Add share extension

---

## Phase 3: End-to-End Encryption (E2EE)

### Protocol: Signal Protocol (Double Ratchet)

The Signal Protocol (formerly Axolotl/TextSecure, used by Signal, WhatsApp, etc.) is the right choice for E2EE in a chat app. Here's why and how it applies:

### Why Signal Protocol

- **Forward secrecy**: Compromising a key doesn't reveal past messages
- **Post-compromise security**: The ratchet "heals" after a compromise
- **Well-studied**: Formally verified, widely deployed, battle-tested
- **Group support**: Sender Keys extension handles group chats efficiently
- **Open source**: libsignal is available under AGPL-3.0

### How It Works (Simplified)

1. **X3DH (Extended Triple Diffie-Hellman)**: Key agreement protocol for establishing shared secrets between two parties, even when one is offline.
   - Each user generates: Identity Key (long-term), Signed Pre-Key (medium-term), One-Time Pre-Keys (single use)
   - Pre-keys are uploaded to the server
   - When Alice wants to message Bob, she downloads Bob's pre-keys and performs X3DH to derive a shared secret

2. **Double Ratchet**: After X3DH establishes a shared secret, the Double Ratchet provides ongoing message encryption:
   - **Diffie-Hellman ratchet**: New DH keys exchanged with each message turn
   - **Symmetric ratchet**: KDF chain derives per-message keys
   - Each message has a unique encryption key

3. **Sender Keys** (for groups): Rather than pairwise encryption for every group member, each sender maintains a single "sender key" that all group members can decrypt. More efficient for groups.

### Key Terminology Note

You mentioned "Whisper protocol" — this is the same thing. The protocol was originally called the "Axolotl Ratchet" or "TextSecure Protocol", developed by Open Whisper Systems (Moxie Marlinspike's organization, which later became Signal). The names are interchangeable:

- **Open Whisper Systems** → now **Signal Foundation**
- **TextSecure Protocol** → now **Signal Protocol**
- **Axolotl Ratchet** → now **Double Ratchet Algorithm**

### Architecture Changes

#### Server-Side Changes (Rails)

The server becomes an **untrusted relay** for E2EE messages. It stores ciphertext but cannot read content.

```
New tables:

identity_keys
  - user_id (FK)
  - public_key (binary)        # Long-term identity key
  - created_at

signed_pre_keys
  - user_id (FK)
  - key_id (integer)
  - public_key (binary)
  - signature (binary)         # Signed by identity key
  - created_at

one_time_pre_keys
  - user_id (FK)
  - key_id (integer)
  - public_key (binary)
  - used (boolean)

sender_keys (for group encryption)
  - user_id (FK)
  - room_id (FK)
  - distribution_id (string)
  - key_data (binary, encrypted)

encrypted_messages
  - message_id (FK)
  - recipient_id (FK)          # For 1:1 DMs
  - ciphertext (binary)
  - message_type (integer)     # PreKey message vs normal
  - sender_key_distribution (binary, nullable)  # For group messages
```

Additional API endpoints:
```
PUT    /api/v1/keys/identity            # upload identity key
PUT    /api/v1/keys/signed_pre_key      # upload signed pre-key
POST   /api/v1/keys/one_time_pre_keys   # upload batch of one-time pre-keys
GET    /api/v1/users/:id/keys           # fetch a user's pre-key bundle
```

#### Client-Side (iOS)

- Use **libsignal-client** (Swift package) — Signal's official library
- Store private keys in the iOS Keychain (hardware-backed on devices with Secure Enclave)
- Key generation happens on-device, private keys never leave the device
- Implement `SignalProtocolStore` protocol for persisting session state

#### Migration Strategy

E2EE is opt-in per room initially:
1. Existing rooms remain unencrypted (backward compatible with web)
2. New "encrypted rooms" can be created from the iOS app
3. Web client can later add E2EE support via libsignal-protocol-javascript
4. Direct messages (1:1) are the first candidate for default encryption

### Implementation Tasks

- [ ] Add key management tables and migrations
- [ ] Add key distribution API endpoints
- [ ] Integrate libsignal-client Swift package
- [ ] Implement SignalProtocolStore (backed by Keychain + SwiftData)
- [ ] Implement X3DH key exchange for DMs
- [ ] Implement Double Ratchet for ongoing DM encryption
- [ ] Implement Sender Keys for group rooms
- [ ] Add encrypted room type and UI indicators
- [ ] Add key verification (QR code / safety numbers)
- [ ] Add multi-device support (key synchronization)
- [ ] Add web client E2EE support (libsignal-protocol-javascript)

---

## Phase 4: Push Notifications (APNs)

The current web app uses Web Push (VAPID). For iOS, we need Apple Push Notification service (APNs).

### Server-Side Changes

- Add `apns_device_token` column to push_subscriptions (or a new device_registrations table)
- Add APNs provider using the `apnotic` or `houston` gem (HTTP/2 provider API)
- When a message is created, send push to both Web Push subscribers and APNs subscribers
- Include room ID and message preview in push payload for deep linking

### Push Payload Format

```json
{
  "aps": {
    "alert": {
      "title": "Room Name",
      "subtitle": "Sender Name",
      "body": "Message preview..."
    },
    "badge": 3,
    "sound": "default",
    "thread-id": "room-42",
    "category": "MESSAGE"
  },
  "room_id": 42,
  "message_id": 123
}
```

### Implementation Tasks

- [ ] Add APNs gem and configuration
- [ ] Add device token registration endpoint
- [ ] Modify `Room::PushMessageJob` to support APNs
- [ ] Add Notification Service Extension (iOS) for rich notifications
- [ ] Add notification actions (reply, mark as read)
- [ ] Handle notification grouping by room (thread-id)

---

## Phase 5: Web App Improvements

### Bug Fixes and Enhancements (to be triaged)

- [ ] Audit and fix any issues from the 37signals issue tracker
- [ ] Review open PRs from the community
- [ ] Add message threading / replies
- [ ] Add typing indicators
- [ ] Add read receipts
- [ ] Add message pinning
- [ ] Improve mobile web experience
- [ ] Add dark mode improvements
- [ ] Add file preview improvements (PDF, code, etc.)

---

## Development Priorities

1. **API layer** (Phase 1) — required before anything else
2. **iOS app basics** (Phase 2) — auth, rooms, messages, push
3. **APNs integration** (Phase 4) — critical for mobile UX
4. **E2EE for DMs** (Phase 3, partial) — start with 1:1 encryption
5. **Web improvements** (Phase 5) — ongoing
6. **E2EE for groups** (Phase 3, complete) — after DMs are solid

---

## Technical Decisions

### Why not just use the PWA?

Campfire already has a web manifest and service worker for PWA support. However:
- **Push notifications**: Web Push on iOS (via Safari) is unreliable and limited compared to APNs
- **Background execution**: Native apps can sync in the background; PWAs cannot
- **Keychain**: E2EE requires secure key storage that only native apps can provide
- **UX**: Native navigation, haptics, share sheets, and widgets aren't available to PWAs
- **Offline**: SwiftData provides much richer offline support than service worker caches

### Why Signal Protocol over alternatives?

| Alternative | Issue |
|------------|-------|
| Simple AES encryption | No forward secrecy, no key rotation |
| Matrix/Olm | Designed for Matrix's federation model, more complex |
| MLS (Messaging Layer Security) | IETF standard, but younger and less battle-tested |
| Custom protocol | Security anti-pattern |

Signal Protocol is the gold standard for chat E2EE. It's what WhatsApp, Signal, and Facebook Messenger use. The libsignal library handles the hard parts.

### Why SQLite?

Campfire already uses SQLite, which is actually well-suited for this use case:
- Single-tenant deployment (one instance per group)
- Excellent read performance
- Zero administration
- Works great for small-to-medium groups
- Litestream can be used for replication/backups if needed
