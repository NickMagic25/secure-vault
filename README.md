# secure-vault

A macOS CLI and SwiftUI password/secrets manager backed by the Apple Secure
Enclave. Passwords and JSON secrets are stored in a local SQLite vault only
after being encrypted with a Secure Enclave public key. Reading, updating,
deleting, and applying stored values require Touch ID or Apple Watch
confirmation.

The vault database lives at:

```text
~/.secure-vault/vault.sqlite
```

The default directory is created with `0700` permissions and the database file
with `0600` permissions. SQLite is used instead of MySQL because SQLite embeds
directly into the app; modern MySQL is not a practical embedded database for a
local CLI vault.

For testing or advanced setups, set `SECURE_VAULT_DB_PATH` to point at another
SQLite file.

## Requirements

- macOS 13+
- Apple Silicon Mac or Intel Mac with T2 chip
- Xcode Command Line Tools (`xcode-select --install`)
- An Apple Developer account for signing Secure Enclave/keychain entitlements

## Build & Install

### Xcode build

When building from Xcode, open `secure-vault.xcodeproj`, not the Swift package
manifest. The Swift package remains the canonical source layout, but the Xcode
project gives Xcode a real macOS app target where automatic signing can create
and embed the provisioning profile required for `keychain-access-groups`.

The repository includes:

- `SecureVault.entitlements`
- `SecureVault.xcconfig`
- `secure-vault.xcodeproj`

In Xcode:

1. Open `secure-vault.xcodeproj`
2. Select the `secure-vault` project in the navigator
3. Select the `secure-vault` macOS app target
4. Create `SecureVault.local.xcconfig` with your local Team ID:

```text
DEVELOPMENT_TEAM = YOURTEAMID
```

5. Go to Signing & Capabilities
6. Keep Automatically manage signing enabled
7. Confirm the bundle identifier is `io.securevault`
8. Build once

Do not change the Team dropdown in Xcode unless you are willing to discard that
local `.pbxproj` edit. The Team ID is intentionally supplied by
`SecureVault.local.xcconfig`, which is ignored by git.

After rebuilding, verify the signed app has the expected entitlements:

```bash
codesign -d --entitlements - /path/to/SecureVault.app
```

You should see `com.apple.application-identifier`,
`com.apple.developer.team-identifier`, and `keychain-access-groups`.

### Makefile build

The `sign` target delegates to `xcodebuild` so Xcode's automatic signing can
create the provisioning profile required for Keychain/Secure Enclave access.

Find your Team ID:

```bash
security find-identity -v -p codesigning
# Look for:
# "Apple Development: Your Name (YOURTEAMID)"
```

Build, sign, and install:

```bash
make install DEVELOPMENT_TEAM=YOURTEAMID
```

If `SecureVault.local.xcconfig` exists, you can omit the command-line Team ID:

```bash
make install
```

Override the bundle ID if needed:

```bash
make install DEVELOPMENT_TEAM=YOURTEAMID BUNDLE_ID=com.example.vault
```

`make install` copies `SecureVault.app` to `/Applications` and installs a small
`secure-vault` wrapper that executes the signed CLI inside the app bundle. The
wrapper is installed to `/usr/local/bin` when that directory is writable, or
`~/.local/bin` otherwise.

## Usage

### Launch the GUI

The package now includes a native SwiftUI macOS app target. For a development
app bundle:

```bash
./script/build_and_run.sh
```

The GUI lists password app names, usernames, and secret names without
decrypting their values. Revealing a password or secret still performs the
Secure Enclave decrypt operation and prompts for Touch ID or Apple Watch.

Run the GUI-focused Swift Testing suite with:

```bash
swift test
```

The first password or secret write automatically creates the default Secure
Enclave key if it does not exist. You can also create it explicitly:

```bash
secure-vault keygen
```

### Store a Password

```bash
secure-vault encrypt-password --app github --username nick
```

The command authenticates with Touch ID or Apple Watch, then prompts for the
password without echoing it.

For scripts, read the password from stdin:

```bash
printf '%s' "$GITHUB_TOKEN" | secure-vault encrypt-password \
  --app github \
  --username nick \
  --password-stdin
```

`--password <value>` is also supported, but it can expose the password through
shell history or process listings.

### Get a Password

```bash
secure-vault get-password --app github --username nick
```

The command writes only the decrypted password to stdout, with no trailing
newline. Authentication/status messages go to stderr, so command substitution is
safe:

```bash
GITHUB_TOKEN="$(secure-vault get-password --app github --username nick)"
```

### Update a Password

```bash
secure-vault update-password --app github --username nick
```

This requires Touch ID or Apple Watch confirmation, then replaces the encrypted
password in the SQLite vault.

For scripts:

```bash
printf '%s' "$NEW_GITHUB_TOKEN" | secure-vault update-password \
  --app github \
  --username nick \
  --password-stdin
```

### Delete a Password

```bash
secure-vault delete-password --app github --username nick
```

Use `--force` to skip the text confirmation prompt. Touch ID or Apple Watch is
still required.

### Store a JSON Secret

Secrets are JSON objects with scalar key:value pairs. Values can be strings,
numbers, booleans, or null.

```bash
secure-vault make-secret \
  --name github-ci \
  --json '{"GITHUB_TOKEN":"ghp_example","RETRIES":3}'
```

For larger JSON, read from stdin:

```bash
printf '%s' '{"DB_USER":"app","DB_PASSWORD":"secret"}' | secure-vault make-secret \
  --name production-db \
  --json-stdin
```

Or read from a JSON file:

```bash
secure-vault make-secret \
  --name production-db \
  --json-file ./production-db.json
```

The command authenticates with Touch ID or Apple Watch before encrypting and
storing the secret.

### Update a JSON Secret

```bash
secure-vault update-secret \
  --name github-ci \
  --json '{"GITHUB_TOKEN":"ghp_rotated"}'
```

Updates are merged into the existing JSON object, so individual keys can be
changed without replacing the whole secret. The command checks that the secret
exists before asking for authentication.

### Get a JSON Secret

```bash
secure-vault get-secret --name github-ci
```

To print one key value only:

```bash
secure-vault get-secret --name github-ci --key GITHUB_TOKEN
```

The command checks that the secret exists before asking for authentication.

### Apply a JSON Secret

```bash
eval "$(secure-vault apply-secret --name github-ci)"
```

`apply-secret` prints shell `export KEY='value'` lines for each key:value pair.
A CLI process cannot mutate the parent shell directly, so use `eval` when you
want the variables applied to the current shell. Secret keys must be valid
environment variable names.

### Delete a JSON Secret

```bash
secure-vault delete-secret --name github-ci
```

Use `--force` to skip the text confirmation prompt. The command checks that the
secret exists before asking for authentication.

### Delete the Secure Enclave Key

```bash
secure-vault delete --tag io.securevault.password-manager
```

Deleting the key is irreversible. Existing vault rows encrypted by that key
cannot be decrypted afterward. This command also requires Touch ID or Apple
Watch confirmation, even with `--force`.

## Options Reference

```text
secure-vault encrypt-password --app <name>
                              --username <name>
                              [--password <value> | --password-stdin]
                              [--tag <key-tag>]

secure-vault get-password     --app <name>
                              --username <name>

secure-vault update-password  --app <name>
                              --username <name>
                              [--password <value> | --password-stdin]

secure-vault delete-password  --app <name>
                              --username <name>
                              [--force]

secure-vault make-secret      --name <name>
                              [--json <json> | --json-stdin | --json-file <file>]
                              [--tag <key-tag>]

secure-vault update-secret    --name <name>
                              [--json <json> | --json-stdin]

secure-vault get-secret       --name <name>
                              [--key <key>]

secure-vault apply-secret     --name <name>

secure-vault delete-secret    --name <name>
                              [--force]

secure-vault keygen           [--tag <key-tag>]
                              [--label <label>]

secure-vault delete           --tag <key-tag>
                              [--force]
```

Default key tag:

```text
io.securevault.password-manager
```

## How It Works

| Step | What happens |
|---|---|
| `encrypt-password` | Requires Touch ID or Apple Watch, creates the Secure Enclave key if needed, encrypts the password, and stores ciphertext in SQLite. |
| `get-password` | Loads ciphertext from SQLite and asks the Secure Enclave to decrypt it. The private key operation triggers Touch ID or Apple Watch. |
| `update-password` | Requires Touch ID or Apple Watch, encrypts the replacement password with the existing key tag, and updates the row. |
| `delete-password` | Requires Touch ID or Apple Watch, then deletes the credential row from SQLite. |
| `make-secret` | Requires Touch ID or Apple Watch, creates the Secure Enclave key if needed, encrypts a scalar JSON object, and stores ciphertext in SQLite. |
| `update-secret` | Checks that the secret exists, decrypts the existing JSON after auth, merges the provided keys, encrypts the result, and updates the row. |
| `get-secret` | Checks that the secret exists, decrypts after auth, and prints either the whole JSON object or one key value. |
| `apply-secret` | Checks that the secret exists, decrypts after auth, and prints shell export lines for each key:value pair. |
| `delete-secret` | Checks that the secret exists, requires Touch ID or Apple Watch, then deletes the secret row from SQLite. |
| `delete` | Requires Touch ID or Apple Watch, then deletes the Secure Enclave private key from the keychain. |

- Algorithm: `eciesEncryptionCofactorVariableIVX963SHA256AESGCM`
- Key storage: login keychain, identified by application tag
- Vault storage: SQLite database at `~/.secure-vault/vault.sqlite`

The database contains app names, usernames, secret names, key tags, timestamps,
and encrypted blobs. It does not store plaintext passwords or plaintext secret
JSON.

## Project Structure

```text
secure-vault/
├── Package.swift
├── Makefile
└── Sources/secure-vault/
    ├── SecureVault.swift
    ├── SecureEnclaveManager.swift
    ├── CredentialStore.swift
    ├── Utilities.swift
    └── Commands/
        ├── EncryptCommand.swift          encrypt-password
        ├── DecryptCommand.swift          get-password
        ├── ListCommand.swift             update-password
        ├── DeletePasswordCommand.swift   delete-password
        ├── SecretCommands.swift          make/update/get/apply/delete secret
        ├── KeygenCommand.swift           keygen
        └── DeleteCommand.swift           delete key
```

## Troubleshooting

### Binary is killed immediately

The `keychain-access-groups` entitlement requires a provisioning profile. Use
`make sign` or `make install`, which call `xcodebuild` with automatic signing,
rather than hand-running `codesign`.

### No valid identities found when signing

Open Xcode, go to Settings > Accounts, add your Apple ID, and download your
development certificate.

### Secure Enclave is not available

Your Mac must have Apple Silicon or a T2 chip. Older Intel Macs without T2 do
not have a Secure Enclave.

### Authentication prompt does not appear

Some terminal contexts cannot present the system auth dialog, especially remote
SSH sessions. Run from a local Terminal or iTerm2 session.

### Stored passwords stop decrypting

The Secure Enclave private key is non-exportable. If it is deleted or generated
under a differently signed app identity, existing vault rows encrypted to the
old key cannot be decrypted.
