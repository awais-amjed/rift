# Database Schema

## Tables

### servers
| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | uuid | Primary Key, Auto-generated | Unique server identifier |
| created_at | timestamptz | Auto-created | Timestamp of server creation |
| name | text | Required | Server name |
| icon_url | text | Optional | URL to server icon |
| livekit_url | text | Required | LiveKit server URL |
| livekit_api_key | text | Required | LiveKit API key |
| livekit_secret_key | text | Required | LiveKit secret key |
| seeding_secret | text | Required | Secret used for generating access tokens |

### users
| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | uuid | Primary Key, Auto-generated | Unique user identifier |
| created_at | timestamptz | Auto-created | Timestamp of user creation |
| username | text | Required, Unique | Unique username |
| display_name | text | Required | User's display name |

### channels
| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | uuid | Primary Key, Auto-generated | Unique channel identifier |
| created_at | timestamptz | Auto-created | Timestamp of channel creation |
| server_id | uuid | Required, Foreign Key → servers.id | Reference to associated server |
| name | text | Required | Channel name |
| channel_type | channel_type | Required | Type of channel (voice or text) |

### tokens
| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | uuid | Primary Key, Auto-generated | Unique token identifier |
| created_at | timestamptz | Auto-created | Timestamp of token creation |
| server_id | uuid | Required, Foreign Key → servers.id | Reference to associated server |
| token | text | Required | Token value |
| user_id | uuid | Nullable, Foreign Key → users.id | Reference to associated user |
| is_server_admin | boolean | Default: false | Whether user has server admin privileges |
| is_channel_manager | boolean | Default: false | Whether user can manage channels |
| can_create_tokens | boolean | Default: false | Whether user can create access tokens |

## Enums

### channel_type
- `voice` - Voice channel
- `text` - Text channel

## Storage Buckets

### servers
- **Access**: Public
- **Purpose**: Storage for server-related assets (e.g., icons)

