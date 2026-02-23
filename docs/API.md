# Campfire API v1 Specification

Base URL: `https://<your-campfire-host>/api/v1`

---

## Authentication

All endpoints (except sign-in) require a bearer token in the `Authorization` header:

```
Authorization: Bearer <token>
```

Tokens are obtained by signing in with email and password. Each token corresponds to a `Session` record on the server and remains valid until explicitly destroyed (sign out) or the user is deactivated.

### Error Responses

All endpoints return errors in a consistent format:

```json
{ "error": "Human-readable error message" }
```

| Status | Meaning |
|--------|---------|
| 401 | Missing or invalid token |
| 403 | Authenticated but not authorized for this action |
| 404 | Resource not found or not accessible to current user |
| 422 | Validation error or invalid parameters |
| 429 | Rate limit exceeded |

---

## Endpoints

### Auth

#### POST /auth/sign_in

Authenticate with email and password. Returns a session token and user profile. Rate limited to 10 requests per 3 minutes per IP.

**Request:**

```json
{
  "email_address": "user@example.com",
  "password": "secret123456"
}
```

**Response:** `201 Created`

```json
{
  "token": "AxJs94fteQ5Autv2VrKsH68c",
  "user": {
    "id": 1,
    "name": "David",
    "email_address": "user@example.com",
    "bio": "Designer",
    "role": "administrator",
    "avatar_url": "https://host/rails/active_storage/blobs/..."
  }
}
```

**Errors:**
- `401` — Invalid email or password
- `429` — Too many requests

---

#### DELETE /auth/sign_out

Destroy the current session. The token becomes invalid immediately.

**Response:** `204 No Content`

---

### Rooms

#### GET /rooms

List all rooms the current user is a member of, ordered alphabetically.

**Response:** `200 OK`

```json
[
  {
    "id": 1,
    "name": "All Pets",
    "type": "open",
    "created_at": "2025-01-15T10:30:00.000Z",
    "updated_at": "2025-06-20T14:22:00.000Z",
    "unread": true,
    "involvement": "everything"
  },
  {
    "id": 2,
    "name": "Designers",
    "type": "closed",
    "created_at": "2025-01-15T10:30:00.000Z",
    "updated_at": "2025-06-20T12:00:00.000Z",
    "unread": false,
    "involvement": "mentions"
  },
  {
    "id": 5,
    "name": null,
    "type": "direct",
    "created_at": "2025-03-01T09:00:00.000Z",
    "updated_at": "2025-06-21T08:15:00.000Z",
    "unread": false,
    "involvement": "everything"
  }
]
```

**Room types:**
- `open` — Visible to all users on the account. New users automatically join.
- `closed` — Only explicitly invited members can see and access the room.
- `direct` — 1:1 or group DM between specific users. Name is `null` (derive display name from members on the client).

**Involvement levels:**
- `invisible` — User is hidden from the room (won't appear in member lists)
- `nothing` — No notifications
- `mentions` — Notified only on @mentions (default for open/closed rooms)
- `everything` — Notified on every message (default for direct rooms)

---

#### GET /rooms/:id

Get room details including member list.

**Response:** `200 OK`

```json
{
  "id": 1,
  "name": "All Pets",
  "type": "open",
  "created_at": "2025-01-15T10:30:00.000Z",
  "updated_at": "2025-06-20T14:22:00.000Z",
  "unread": false,
  "involvement": "everything",
  "members": [
    { "id": 1, "name": "David" },
    { "id": 2, "name": "Jason" },
    { "id": 3, "name": "JZ" }
  ]
}
```

**Errors:**
- `404` — Room not found or user is not a member

---

#### POST /rooms

Create a new room. Requires `administrator` role for open/closed rooms (unless the account setting `restrict_room_creation_to_administrators` is false). Anyone can create direct rooms.

**Request (open room):**

```json
{
  "name": "New Room",
  "type": "open"
}
```

**Request (closed room with specific members):**

```json
{
  "name": "Secret Project",
  "type": "closed",
  "user_ids": [2, 3, 4]
}
```

The current user is always added as a member automatically. `user_ids` specifies additional members.

**Request (direct room):**

```json
{
  "type": "direct",
  "user_ids": [2]
}
```

Direct rooms are singletons — if a direct room already exists between the same set of users, the existing room is returned. `name` is ignored for direct rooms.

**Response:** `201 Created`

Returns the full room object with members (same shape as `GET /rooms/:id`).

**Errors:**
- `403` — User lacks permission to create rooms
- `422` — Invalid room type (must be `open`, `closed`, or `direct`)

---

### Messages

#### GET /rooms/:room_id/messages

List messages in a room, paginated. Returns up to 40 messages per page, ordered by `created_at` ascending (oldest first within a page).

**Query parameters:**

| Param | Description |
|-------|-------------|
| (none) | Returns the last (most recent) page of messages |
| `before` | Message ID — returns the page of messages before this message |
| `after` | Message ID — returns the page of messages after this message |

**Response:** `200 OK`

```json
[
  {
    "id": 42,
    "client_message_id": "550e8400-e29b-41d4-a716-446655440000",
    "body": "Hello everyone!",
    "body_html": "<div class=\"trix-content\">Hello everyone!</div>",
    "content_type": "text",
    "created_at": "2025-06-20T14:22:00.000Z",
    "updated_at": "2025-06-20T14:22:00.000Z",
    "creator": {
      "id": 1,
      "name": "David"
    },
    "boosts": [
      { "id": 1, "content": "🎉", "booster_id": 2 }
    ]
  }
]
```

**Content types:**
- `text` — Regular text message
- `attachment` — File/image attachment
- `sound` — Sound effect (e.g. `/play rimshot`)

**Pagination strategy (cursor-based):**

To load initial messages for a room, call without parameters (returns the most recent page). To load older messages (scroll up), pass `before=<id of oldest message you have>`. To load newer messages (catch up after backgrounding), pass `after=<id of newest message you have>`.

If the returned array has fewer than 40 items, you've reached the beginning (for `before`) or the end (for `after`) of the conversation.

---

#### GET /rooms/:room_id/messages/:id

Get a single message.

**Response:** `200 OK` — Same shape as a single item in the messages array above.

---

#### POST /rooms/:room_id/messages

Send a message to a room. The message is broadcast to all connected WebSocket clients.

**Request (text):**

```json
{
  "message": {
    "body": "Hello from the iOS app!",
    "client_message_id": "optional-uuid-for-deduplication"
  }
}
```

**Request (attachment):**

Use `multipart/form-data` with:
- `message[body]` — Optional text body
- `message[attachment]` — The file (image, video, etc.)
- `message[client_message_id]` — Optional UUID

**Response:** `201 Created`

```json
{
  "id": 43,
  "client_message_id": "550e8400-e29b-41d4-a716-446655440000",
  "body": "Hello from the iOS app!",
  "body_html": "<div class=\"trix-content\">Hello from the iOS app!</div>",
  "content_type": "text",
  "created_at": "2025-06-20T14:23:00.000Z",
  "updated_at": "2025-06-20T14:23:00.000Z",
  "creator": {
    "id": 1,
    "name": "David"
  },
  "boosts": []
}
```

**Notes:**
- `client_message_id` is auto-generated (UUID) if not provided. Use it for optimistic UI — send the message, display it immediately with the client_message_id, then reconcile when the server response arrives.
- The server broadcasts the message via ActionCable after creation. WebSocket subscribers will receive a Turbo Stream append event.

---

#### PUT /rooms/:room_id/messages/:id

Edit a message. Only the message creator or an administrator can edit.

**Request:**

```json
{
  "message": {
    "body": "Updated message text"
  }
}
```

**Response:** `200 OK` — Returns the updated message object.

**Errors:**
- `403` — Not the creator and not an administrator

---

#### DELETE /rooms/:room_id/messages/:id

Delete a message. Only the message creator or an administrator can delete.

**Response:** `204 No Content`

**Errors:**
- `403` — Not the creator and not an administrator

---

### Boosts (Reactions)

#### POST /messages/:message_id/boosts

Add an emoji reaction to a message.

**Request:**

```json
{
  "boost": {
    "content": "🎉"
  }
}
```

**Response:** `201 Created`

```json
{
  "id": 5,
  "content": "🎉",
  "created_at": "2025-06-20T14:25:00.000Z",
  "booster": {
    "id": 1,
    "name": "David"
  },
  "message_id": 42
}
```

**Notes:**
- `content` is limited to 16 characters (typically a single emoji or short string)
- The message must be in a room the current user is a member of

---

#### DELETE /messages/:message_id/boosts/:id

Remove your own reaction from a message.

**Response:** `204 No Content`

**Notes:**
- You can only remove your own boosts. Attempting to remove another user's boost returns `404`.

---

### Users

#### GET /users/me

Get the current user's full profile.

**Response:** `200 OK`

```json
{
  "id": 1,
  "name": "David",
  "bio": "Designer",
  "avatar_url": "https://host/rails/active_storage/blobs/...",
  "email_address": "david@example.com",
  "role": "administrator"
}
```

**Roles:**
- `member` — Standard user
- `administrator` — Can manage rooms, users, and account settings

---

#### PUT /users/me

Update the current user's profile.

**Request (JSON):**

```json
{
  "user": {
    "name": "David H",
    "bio": "Product designer",
    "email_address": "newemail@example.com"
  }
}
```

All fields are optional — include only the fields you want to change.

**Request (avatar upload):** Use `multipart/form-data` with `user[avatar]` as the file field.

**Accepted fields:** `name`, `bio`, `email_address`, `password`, `avatar`

**Response:** `200 OK` — Returns the updated full user profile (same shape as `GET /users/me`).

---

#### GET /users/:id

View another user's public profile.

**Response:** `200 OK`

```json
{
  "id": 2,
  "name": "Jason",
  "bio": "Programmer",
  "avatar_url": "https://host/rails/active_storage/blobs/..."
}
```

**Notes:**
- Does **not** include `email_address` or `role` (those are private to the user themselves)
- Only returns active users. Deactivated/banned users return `404`.

---

### Involvements (Notification Preferences)

#### GET /rooms/:room_id/involvement

Get the current user's notification involvement level for a room.

**Response:** `200 OK`

```json
{
  "room_id": 1,
  "involvement": "everything"
}
```

---

#### PUT /rooms/:room_id/involvement

Update notification preferences for a room.

**Request:**

```json
{
  "involvement": "mentions"
}
```

**Valid values:** `invisible`, `nothing`, `mentions`, `everything`

**Response:** `200 OK`

```json
{
  "room_id": 1,
  "involvement": "mentions"
}
```

---

### Search

#### POST /searches

Full-text search across all messages in rooms the current user has access to. Uses SQLite FTS5 with Porter stemming, so partial word matches and stemmed variants work. Returns up to 100 results.

The search query is recorded for the user's recent searches (the server keeps the last 10).

**Request:**

```json
{
  "q": "design meeting"
}
```

**Response:** `200 OK`

```json
{
  "query": "design meeting",
  "messages": [
    {
      "id": 42,
      "body": "Let's schedule the design meeting for Thursday",
      "created_at": "2025-06-20T14:22:00.000Z",
      "room": {
        "id": 2,
        "name": "Designers"
      },
      "creator": {
        "id": 1,
        "name": "David"
      }
    }
  ]
}
```

**Notes:**
- Non-word characters in the query are replaced with spaces
- An empty query returns `422 Unprocessable Entity`

---

## WebSocket (ActionCable)

The server uses Rails ActionCable for real-time communication. Native clients connect via WebSocket.

### Connecting

**URL:** `wss://<your-campfire-host>/cable?token=<session-token>`

The token is passed as a query parameter. This is the same token obtained from `POST /auth/sign_in`.

**ActionCable protocol:** The client must speak the ActionCable WebSocket subprotocol (`actioncable-v1-json`). Each frame is a JSON object with a `command` field.

### Channels

After connecting, subscribe to channels by sending:

```json
{
  "command": "subscribe",
  "identifier": "{\"channel\":\"ChannelName\",\"param\":\"value\"}"
}
```

The `identifier` is a JSON-encoded string (double-encoded in the outer frame).

#### RoomChannel

Subscribe to receive new messages, edits, and deletions for a specific room.

**Subscribe:** `{ "channel": "RoomChannel", "room_id": 42 }`

**Incoming data:** Turbo Stream HTML fragments:
- **New message:** `<turbo-stream action="append" target="room_42_messages">...</turbo-stream>`
- **Edited message:** `<turbo-stream action="replace" ...>...</turbo-stream>`
- **Deleted message:** `<turbo-stream action="remove" ...>...</turbo-stream>`

**Note for iOS:** The Turbo Stream payloads contain HTML partials designed for the web client. The iOS app should parse these to extract the message data, or alternatively re-fetch the message via the REST API when a broadcast is received. A future enhancement could add a JSON-only broadcast channel.

---

#### PresenceChannel

Track when users enter and leave a room. Subscribing marks your membership as "connected" (present). Unsubscribing marks it as "disconnected".

**Subscribe:** `{ "channel": "PresenceChannel", "room_id": 42 }`

**Actions:**
- `refresh` — Call periodically to keep the connection alive (connection TTL is 60 seconds)

**Side effects:**
- Subscribing clears the room's unread status for the current user
- Subscribing broadcasts a "read" event to the `ReadRoomsChannel`

---

#### TypingNotificationsChannel

Broadcast and receive typing indicators for a room.

**Subscribe:** `{ "channel": "TypingNotificationsChannel", "room_id": 42 }`

**Send (user starts typing):**

```json
{
  "command": "message",
  "identifier": "{\"channel\":\"TypingNotificationsChannel\",\"room_id\":42}",
  "data": "{\"action\":\"start\"}"
}
```

**Send (user stops typing):**

```json
{
  "command": "message",
  "identifier": "{\"channel\":\"TypingNotificationsChannel\",\"room_id\":42}",
  "data": "{\"action\":\"stop\"}"
}
```

**Incoming data:**

```json
{
  "action": "start",
  "user": { "id": 2, "name": "Jason" }
}
```

---

#### UnreadRoomsChannel

Receive notifications when any room gets a new message (for updating unread badges).

**Subscribe:** `{ "channel": "UnreadRoomsChannel" }`

**Incoming data:**

```json
{ "roomId": 42 }
```

The iOS app should update the unread badge for room 42 when this is received (unless the user is currently viewing that room).

---

#### ReadRoomsChannel

Receive notifications when the current user reads a room (for syncing read state across devices).

**Subscribe:** `{ "channel": "ReadRoomsChannel" }`

**Incoming data:**

```json
{ "room_id": 42 }
```

---

#### HeartbeatChannel

Keep-alive channel. Subscribe to prevent the WebSocket connection from being closed by proxies/load balancers.

**Subscribe:** `{ "channel": "HeartbeatChannel" }`

---

## Data Types Reference

### Room

| Field | Type | Description |
|-------|------|-------------|
| `id` | integer | Unique ID |
| `name` | string? | Room name (`null` for direct rooms) |
| `type` | string | `"open"`, `"closed"`, or `"direct"` |
| `created_at` | ISO 8601 | When the room was created |
| `updated_at` | ISO 8601 | When the room was last updated |
| `unread` | boolean | Whether the room has unread messages for the current user |
| `involvement` | string | Current user's notification level |
| `members` | [User]? | Only present in `GET /rooms/:id` and `POST /rooms` responses |

### Message

| Field | Type | Description |
|-------|------|-------------|
| `id` | integer | Unique ID |
| `client_message_id` | string | UUID for client-side deduplication |
| `body` | string | Plain text content |
| `body_html` | string | HTML content (Action Text / Trix format) |
| `content_type` | string | `"text"`, `"attachment"`, or `"sound"` |
| `created_at` | ISO 8601 | When the message was created |
| `updated_at` | ISO 8601 | When the message was last updated |
| `creator` | {id, name} | The message author |
| `boosts` | [{id, content, booster_id}] | Emoji reactions on this message |

### User (public)

| Field | Type | Description |
|-------|------|-------------|
| `id` | integer | Unique ID |
| `name` | string | Display name |
| `bio` | string? | User bio |
| `avatar_url` | string? | URL to avatar image (or `null`) |

### User (full — only for `/users/me`)

Includes all public fields plus:

| Field | Type | Description |
|-------|------|-------------|
| `email_address` | string | User's email |
| `role` | string | `"member"` or `"administrator"` |

### Boost

| Field | Type | Description |
|-------|------|-------------|
| `id` | integer | Unique ID |
| `content` | string | Emoji or short text (max 16 chars) |
| `created_at` | ISO 8601 | When the boost was created |
| `booster` | {id, name} | Who reacted |
| `message_id` | integer | The message this boost is on |

### Involvement

| Field | Type | Description |
|-------|------|-------------|
| `room_id` | integer | Room ID |
| `involvement` | string | One of: `invisible`, `nothing`, `mentions`, `everything` |

### Search Result

| Field | Type | Description |
|-------|------|-------------|
| `query` | string | The sanitized search query |
| `messages` | [SearchMessage] | Matching messages (max 100) |

### SearchMessage

| Field | Type | Description |
|-------|------|-------------|
| `id` | integer | Message ID |
| `body` | string | Plain text content |
| `created_at` | ISO 8601 | When the message was created |
| `room` | {id, name} | The room containing this message |
| `creator` | {id, name} | The message author |
