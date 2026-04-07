# Database Schema

## Tables

### servers

| Column             | Type        | Constraints                 | Description                              |
|--------------------|-------------|-----------------------------|------------------------------------------|
| id                 | uuid        | Primary Key, Auto-generated | Unique server identifier                 |
| created_at         | timestamptz | Auto-created                | Timestamp of server creation             |
| name               | text        | Required                    | Server name                              |
| icon_url           | text        | Optional                    | URL to server icon                       |
| livekit_url        | text        | Required                    | LiveKit server URL                       |
| livekit_api_key    | text        | Required                    | LiveKit API key                          |
| livekit_secret_key | text        | Required                    | LiveKit secret key                       |
| seeding_secret     | text        | Required                    | Secret used for generating access tokens |

### users

| Column             | Type        | Constraints                        | Description                                      |
|--------------------|-------------|------------------------------------|-------------------------------------------------|
| id                 | uuid        | Primary Key, Auto-generated        | Unique user identifier                           |
| created_at         | timestamptz | Auto-created                       | Timestamp of user creation                       |
| server_id          | uuid        | Required, Foreign Key → servers.id | The server this user is registered on            |
| username           | text        | Required, Unique                   | Unique username                                  |
| display_name       | text        | Required                           | User's display name                              |
| public_key         | text        | Unique, Not Null                   | Ed25519 public key (base64). Updates on rotation |
| stable_id          | text        | Unique, Not Null                   | Permanent HMAC identity hash. Never changes      |
| is_banned          | boolean     | Default: false                     | If true, all logins/rotations are rejected       |
| is_server_admin    | boolean     | Default: false                     | Whether user has server admin privileges         |
| is_channel_manager | boolean     | Default: false                     | Whether user can manage channels                 |
| can_create_tokens  | boolean     | Default: false                     | Whether user can create invites                  |

### channels

| Column       | Type         | Constraints                        | Description                     |
|--------------|--------------|------------------------------------|---------------------------------|
| id           | uuid         | Primary Key, Auto-generated        | Unique channel identifier       |
| created_at   | timestamptz  | Auto-created                       | Timestamp of channel creation   |
| server_id    | uuid         | Required, Foreign Key → servers.id | Reference to associated server  |
| name         | text         | Required                           | Channel name                    |
| channel_type | channel_type | Required                           | Type of channel (voice or text) |

### tokens

Pure auth credentials — always linked to a user.

| Column    | Type        | Constraints                        | Description                    |
|-----------|-------------|------------------------------------|--------------------------------|
| id        | uuid        | Primary Key, Auto-generated        | Unique token identifier        |
| created_at| timestamptz | Auto-created                       | Timestamp of token creation    |
| server_id | uuid        | Required, Foreign Key → servers.id | Reference to associated server |
| token     | text        | Required, Unique                   | Auth token value               |
| user_id   | uuid        | Foreign Key → users.id             | Reference to associated user   |

### invites

Permission grants with reuse support — used to register new users.

| Column             | Type        | Constraints                        | Description                                    |
|--------------------|-------------|------------------------------------|-------------------------------------------------|
| id                 | uuid        | Primary Key, Auto-generated        | Unique invite identifier                        |
| created_at         | timestamptz | Auto-created                       | Timestamp of invite creation                    |
| server_id          | uuid        | Required, Foreign Key → servers.id | Reference to associated server                  |
| code               | text        | Required, Unique                   | Invite code value                               |
| is_server_admin    | boolean     | Default: false                     | Grant server admin to registrant                |
| is_channel_manager | boolean     | Default: false                     | Grant channel manager to registrant             |
| can_create_tokens  | boolean     | Default: false                     | Grant invite creation to registrant             |
| max_uses           | integer     | Nullable                           | Max uses (NULL = unlimited)                     |
| uses               | integer     | Default: 0                         | Current use count                               |

### auth_challenges

| Column     | Type          | Constraints | Description                                |
|------------|---------------|-------------|--------------------------------------------|
| nonce      | text          | Primary Key | Random challenge string                    |
| expires_at | timestamptz   | Not Null    | Set to NOW() + INTERVAL '60 seconds'       |

*Note: Create a Postgres CRON job or trigger to sweep expired nonces every few minutes.*

## Enums

### channel_type

- `voice` - Voice channel
- `text` - Text channel

## Storage Buckets

### servers

- **Access**: Public
- **Purpose**: Storage for server-related assets (e.g., icons)
