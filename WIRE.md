# WIRE.md — the formats a second implementation has to match

Everything here is a contract. Third-party bots and any SDK that is not the
Dart one read this file, and `test/wire_vectors.json` is the same contract as
numbers you can check against.

Nothing here is a *decision* — the reasoning for all of it is in
`ARCHITECTURE.md` §1 and §4, and this document deliberately does not repeat it.
This is the part somebody porting the client has to get byte-identical.

## Why the vectors exist

Two implementations of a canonical payload are two things that can disagree,
and the disagreement does not look like an error. A message signed over a
payload that differs by one character stores fine, verifies as false, and
renders as nothing — the sender sees it send, and nobody else ever sees it.

So the format is frozen as data. The vectors were generated from the Dart
implementation and then checked in, which means they **catch drift, not
original error**: they cannot tell you the format was right on the day it was
written. What they can tell you is that it has not moved since, and that a
second implementation agrees with the first — which is the failure that
actually happens.

`test/wire_test.dart` checks the app against them on every run.

---

## 1. Encodings

| Where | Encoding |
|---|---|
| Keys, signatures, nonces, ciphertext on the wire | **base64**, standard alphabet, padded (`dart:convert` `base64Encode`) |
| The SIWS address only | **base58**, Bitcoin/Solana alphabet, leading zero bytes each emitted as `1` |
| Everything hashed or signed | **UTF-8** bytes of the string given |

## 2. The key ladder

One 32-byte master seed. Everything else is `HMAC-SHA256(seed, context)`, where
the context string is domain-separating and the output is 32 bytes.

```
vaultKey     = HMAC-SHA256(seed, "vault:v1")
serverSeed   = HMAC-SHA256(seed, "<scope>:<version>")     → Ed25519 seed
stableId     = HMAC-SHA256(seed, "<scope>:identity")      → base64, as-is
chatSeed     = HMAC-SHA256(seed, "<host>:chat:<version>") → X25519 seed
```

`<scope>` is `"<host>:<serverId>"` for a self-hosted server and bare `"<host>"`
for the central host. `<version>` is `v1`.

Two things a port gets wrong:

- **`host` is the URL's host only** — no scheme, no port, no path.
  `http://192.168.1.6:8000` gives `192.168.1.6`.
- **The chat identity is not scoped to a server.** It is per host and pinned at
  `v1` while the auth identity carries a rotating version. Scoping it would
  change the X25519 key on every auth rotation and make old messages
  unreadable.

An Ed25519 or X25519 keypair is built from those 32 bytes as a **seed**, not as
a private scalar — RFC 8032 for Ed25519, RFC 7748 clamping for X25519. Most
libraries call this `fromSeed` or `newKeyPairFromSeed`.

## 3. The signed payload

Every message carries an Ed25519 signature over exactly this string:

```
chatmsg:v1:<contextId>:<keyVersion>:<nonce>:<ciphertext>
```

Joined with `:` and nothing else — no length prefixes, no canonical JSON. The
fields are the base64 strings as they appear on the row, not the bytes they
decode to.

`contextId` is:

| Kind | contextId |
|---|---|
| Channel message | the channel's UUID |
| DM | `dm:<idA>:<idB>`, the two user ids **sorted lexicographically** |

The sort is what lets both sides derive the same context without agreeing on
anything first, and what stops an envelope being replayed into a different
conversation.

A message a bot writes is **signed but not sealed**: `keyVersion` is `0`, the
nonce is the empty string, and `ciphertext` holds plaintext. The payload is
built the same way — `chatmsg:v1:<channel>:0::<text>` — with an empty field
between the two colons.

Clients drop what they cannot verify, so an unsigned or wrongly-signed message
is an invisible one.

## 4. Sign-in

`login` takes a SIWS message and its base64 signature. The message is built
from a fixed template:

```
localhost wants you to sign in with your Solana account:
<base58 public key>

Sign in to Rift.

URI: http://localhost
Version: 1
Chain ID: solana:mainnet
Nonce: <alphanumeric>
Issued At: <ISO-8601 UTC>
```

`localhost` and `http://localhost` are **constants, not the server's address**,
for the reason in `crypto_repository_identity.dart`: GoTrue's web3 grant
refuses most real addresses, and these two fields exist so a wallet can tell
you which site is asking — Rift has no wallet. The key is derived per
`(host, serverId)` and posted only to the host it was derived for.

`Nonce` is any alphanumeric string; `Issued At` is the current UTC time. Both
vary per login, which is why this one has no vector — what is frozen is the
template, and `wire_vectors.json` pins the address encoding it embeds.

## 5. Panels

`messages.blocks` holds `{"v":1,"blocks":[…]}`. Each block is an object with a
`type`, and **anything not in this list is not drawn** — that is the safety
property, not a limitation of the first version. A bot never controls a pixel,
only a structure.

| `type` | Fields | Draws |
|---|---|---|
| `heading` | `text` | a title line |
| `text` | `text` | a paragraph |
| `fields` | `items: [{label, value}]` | key/value rows |
| `progress` | `value` (0–1, clamped), `text` | a bar with a caption |
| `divider` | — | a rule |
| `actions` | `items: [{label, action, style?}]` | a row of buttons |
| `select` | `action`, `text?`, `options: [{label, value?}]` | a menu |

`style` is `primary`, `danger`, or absent. It is a **weight, not a colour** —
a bot cannot paint a button into looking like part of Rift's own chrome.

A button with no `label` or no `action` is dropped rather than half-drawn, and
a block with nothing in it is dropped too: an empty row reads as a bug.

Pressing one writes a row addressed to the bot with `is_interaction` true,
`reply_to` naming the panel, `action_id` the button's own id and `action_value`
a menu option's value. It is signed like a command, because it is attributed —
the bot is told who pressed. It is **not a message**: no view renders it, no
phone rings for it, and it does not count as unread.

The bot redraws by writing `blocks` again on the same row and ringing
`message_changed` with its id. Ringing `new_message` makes clients fetch what is
*newer* than they have, and a redraw is not newer than anything.

`image` is deliberately absent from v1 — see BOTS.md §13 item 8.

---

## Out of scope

Key wrapping (`wrap:v1`), the channel keyring and the DM key derivation are
between clients that hold keys, and a bot never holds one. They are in
`ARCHITECTURE.md` §4 and are not frozen here yet; the moment a non-Dart client
needs to *read* a channel rather than be spoken to, they belong in this file
too.
