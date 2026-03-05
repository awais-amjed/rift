# Rift Edge Functions API Documentation

This document provides comprehensive documentation for all Supabase Edge Functions in the Rift application.

## Base URL

All functions are deployed under the Supabase Functions endpoint:
```
https://<project-ref>.supabase.co/functions/v1/
```

For local development:
```
http://127.0.0.1:54321/functions/v1/
```

## Response Format

All functions return a consistent JSON response format:

**Success Response:**
```json
{
  "success": true,
  "data": { ... }
}
```

**Error Response:**
```json
{
  "success": false,
  "error": "Error message"
}
```

All responses have HTTP status code 200. The `success` field indicates whether the operation was successful.

---

## Functions

### 1. Create Server

**Endpoint:** `/create_server`

**Method:** `POST`

**Description:** Creates a new server with LiveKit configuration, generates a unique seeding secret for token generation, and automatically creates an admin token with full permissions (is_server_admin, is_channel_manager, can_create_tokens).

**Input Parameters:**
```json
{
  "name": "string (required)",
  "icon_url": "string (optional)",
  "livekit_url": "string (required)",
  "livekit_api_key": "string (required)",
  "livekit_secret_key": "string (required)"
}
```

**Output:**
```json
{
  "success": true,
  "data": {
    "server": {
      "id": "uuid",
      "created_at": "timestamp",
      "name": "string",
      "icon_url": "string | null",
      "livekit_url": "string",
      "livekit_api_key": "string",
      "livekit_secret_key": "string",
      "seeding_secret": "string"
    },
    "token": "string - Admin access token with all permissions"
  }
}
```

**Permissions Required:** None (public endpoint for creating new servers)

**Notes:**
- The returned token has full admin permissions: `is_server_admin`, `is_channel_manager`, and `can_create_tokens` all set to `true`
- This token can be used immediately to manage the server, create channels, and generate additional access tokens

---

### 2. Create Access Token

**Endpoint:** `/create_access_token`

**Method:** `POST`

**Description:** Generates a new access token for a server with specified permissions. The calling user must have `can_create_tokens` permission. Uses the server's seeding secret to generate a secure HMAC-SHA256 token.

**Input Parameters:**
```json
{
  "token": "string (required) - Caller's access token",
  "is_server_admin": "boolean (optional, default: false)",
  "is_channel_manager": "boolean (optional, default: false)",
  "can_create_tokens": "boolean (optional, default: false)"
}
```

**Output:**
```json
{
  "success": true,
  "data": {
    "token": "string - New access token",
    "livekit_url": "string - Server's LiveKit URL"
  }
}
```

**Permissions Required:** `can_create_tokens` (checked from the caller's token)

---

### 3. Join Server

**Endpoint:** `/join_server`

**Method:** `POST`

**Description:** Creates a new user account and links it to an existing token. The token must not already be linked to a user. The username must be unique across all users.

**Input Parameters:**
```json
{
  "token": "string (required) - Access token to link",
  "username": "string (required) - Unique username",
  "display_name": "string (required) - User's display name"
}
```

**Output:**
```json
{
  "success": true,
  "data": {
    "user_id": "uuid",
    "username": "string",
    "display_name": "string"
  }
}
```

**Permissions Required:** Valid token that is not yet linked to a user

**Validation:**
- Token must exist and not be linked to a user
- Username must be unique

---

### 4. Is Username Available

**Endpoint:** `/is_username_available`

**Method:** `POST`

**Description:** Checks if a username is available for registration.

**Input Parameters:**
```json
{
  "username": "string (required)"
}
```

**Output:**
```json
{
  "success": true,
  "data": {
    "username": "string",
    "available": "boolean"
  }
}
```

**Permissions Required:** None (public endpoint)

---

### 5. Get Server Details

**Endpoint:** `/get_server_details`

**Method:** `POST`

**Description:** Retrieves server information, user details (if linked to the token) with their permissions, and a list of all channels in the server.

**Input Parameters:**
```json
{
  "token": "string (required)"
}
```

**Output:**
```json
{
  "success": true,
  "data": {
    "name": "string - Server name",
    "icon_url": "string | null - Server icon URL",
    "livekit_url": "string - LiveKit server URL",
    "user": {
      "id": "uuid",
      "username": "string",
      "display_name": "string",
      "permissions": {
        "is_server_admin": "boolean",
        "is_channel_manager": "boolean",
        "can_create_tokens": "boolean"
      }
    } | null,
    "channels": [
      {
        "id": "uuid",
        "name": "string",
        "channel_type": "voice | text"
      }
    ]
  }
}
```

**Permissions Required:** Valid token

**Notes:**
- `user` field is `null` if the token is not linked to a user yet
- `permissions` object shows the user's current permissions for this server

---

### 6. Update Server

**Endpoint:** `/update_server`

**Method:** `POST`

**Description:** Updates server details. At least one field must be provided for update. Only server admins can update server details.

**Input Parameters:**
```json
{
  "token": "string (required)",
  "name": "string (optional)",
  "icon_url": "string (optional)",
  "livekit_api_key": "string (optional)",
  "livekit_secret_key": "string (optional)"
}
```

**Output:**
```json
{
  "success": true,
  "data": {
    "name": "string",
    "icon_url": "string | null",
    "livekit_api_key": "string",
    "livekit_secret_key": "string"
  }
}
```

**Permissions Required:** `is_server_admin`

**Validation:**
- At least one field to update must be provided

---

### 7. Create Channel

**Endpoint:** `/create_channel`

**Method:** `POST`

**Description:** Creates a new channel in the server. Channel names must be unique within a server. Only channel managers can create channels.

**Input Parameters:**
```json
{
  "token": "string (required)",
  "name": "string (required) - Channel name",
  "channel_type": "voice | text (required)"
}
```

**Output:**
```json
{
  "success": true,
  "data": {
    "id": "uuid",
    "name": "string",
    "channel_type": "voice | text",
    "created_at": "timestamp"
  }
}
```

**Permissions Required:** `is_channel_manager`

**Validation:**
- `channel_type` must be either "voice" or "text"
- Channel name must be unique within the server

---

### 8. Delete Channel

**Endpoint:** `/delete_channel`

**Method:** `POST`

**Description:** Deletes a channel from the server. Only channel managers can delete channels, and the channel must belong to the same server as the token.

**Input Parameters:**
```json
{
  "token": "string (required)",
  "channel_id": "uuid (required)"
}
```

**Output:**
```json
{
  "success": true,
  "data": {
    "message": "Channel deleted successfully",
    "channel_id": "uuid"
  }
}
```

**Permissions Required:** `is_channel_manager`

**Validation:**
- Channel must exist
- Channel must belong to the same server as the token

---

### 9. Get Channel Token

**Endpoint:** `/get_channel_token`

**Method:** `POST`

**Description:** Generates a LiveKit JWT token for joining a specific voice/text channel. The token includes appropriate permissions based on the user's role. The user must be linked to the token (have a user account).

**Input Parameters:**
```json
{
  "token": "string (required) - Access token",
  "channel_id": "uuid (required) - Channel to join"
}
```

**Output:**
```json
{
  "success": true,
  "data": {
    "token": "string - LiveKit JWT token"
  }
}
```

**Permissions Required:** Valid token linked to a user

**LiveKit Token Grants:**
- `roomCreate`: true
- `roomJoin`: true
- `room`: channel_id (the channel ID is used as the room name)
- `canPublish`: true
- `canSubscribe`: true
- `roomAdmin`: Based on `is_channel_manager` permission
- `identity`: user_id
- `name`: display_name
- `ttl`: 1 hour

**Validation:**
- Token must be linked to a user
- Channel must exist
- User information must be present in the database

---

## Permission Levels

### Token Permissions

Each access token can have the following permissions:

| Permission | Description |
|------------|-------------|
| `is_server_admin` | Can update server settings (name, icon, LiveKit credentials) |
| `is_channel_manager` | Can create and delete channels, gets `roomAdmin` in LiveKit |
| `can_create_tokens` | Can generate new access tokens with custom permissions |

### Permission Hierarchy

- **Server Admin**: Can modify server-level settings but doesn't automatically get channel or token creation permissions
- **Channel Manager**: Can manage channels and has elevated permissions in LiveKit rooms
- **Token Creator**: Can generate new access tokens for inviting users with specific permissions

---

## Authentication Flow

1. **Create Server** → Get server details
2. **Create Access Token** → Generate first token (with elevated permissions)
3. **Join Server** → Link token to user account (username + display_name)
4. **Get Channel Token** → Generate LiveKit token for voice/video communication

---

## Error Handling

Common error responses:

| Error | Description |
|-------|-------------|
| `Missing required field: <field>` | A required input parameter is missing |
| `Invalid token provided` | The provided token doesn't exist in the database |
| `Unauthorized: <reason>` | The user lacks required permissions |
| `<Resource> not found` | The requested resource doesn't exist |
| `Username already taken` | The username is not available |
| `A channel with this name already exists` | Duplicate channel name in server |
| `Token is already linked to a user` | Cannot join server with an already-linked token |

---

## Development

### Local Testing

1. Start Supabase locally:
```bash
supabase start
```

2. Test function locally:
```bash
curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/<function_name>' \
  --header 'Authorization: Bearer <anon_key>' \
  --header 'Content-Type: application/json' \
  --data '{"key":"value"}'
```

### Deployment

Deploy all functions:
```bash
supabase functions deploy
```

Deploy a specific function:
```bash
supabase functions deploy <function_name>
```

---

## Database Schema

For detailed database schema information, see [schema.md](./supabase/schema/schema.md).

### Key Tables

- **servers**: Server configuration and LiveKit settings
- **users**: User accounts (username, display_name)
- **channels**: Voice and text channels
- **tokens**: Access tokens with permissions

---

## Security Notes

1. All functions use `SUPABASE_SERVICE_ROLE_KEY` for database operations
2. Tokens are generated using HMAC-SHA256 with server-specific seeding secrets
3. LiveKit tokens have a 1-hour TTL
4. All responses use HTTP 200 status code with a `success` field for consistency
5. Permission checks are performed server-side for all privileged operations

---

## Support

For issues or questions, please refer to the project documentation or contact the development team.

