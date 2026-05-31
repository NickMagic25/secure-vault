# secure-vault

A macOS CLI tool that encrypts data using the **Secure Enclave**. Decryption requires authentication via **Touch ID or Apple Watch** — the private key never leaves the chip.

## Requirements

- macOS 13+
- Apple Silicon Mac (M-series) or Intel Mac with T2 chip
- Xcode Command Line Tools (`xcode-select --install`)
- An Apple Developer account (code signing is required for Secure Enclave access)

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
4. Go to **Signing & Capabilities**
5. Set Team to your Apple Developer account
6. Keep Automatically manage signing enabled
7. Confirm the bundle identifier is `io.securevault`
8. Build once

```text
PRODUCT_BUNDLE_IDENTIFIER = io.securevault
CODE_SIGN_ENTITLEMENTS = SecureVault.entitlements
ENABLE_HARDENED_RUNTIME = YES
DEVELOPMENT_TEAM = <your Apple Developer Team ID>
```

The app bundle contains the CLI at `SecureVault.app/Contents/MacOS/secure-vault`.
After rebuilding, verify the signed app has the expected entitlements:

```bash
codesign -d --entitlements - /path/to/SecureVault.app
```

You should see `com.apple.application-identifier`,
`com.apple.developer.team-identifier`, and `keychain-access-groups`.

### Makefile build

The `sign` target delegates to `xcodebuild` so Xcode's automatic signing can
create the provisioning profile required for Keychain/Secure Enclave access.

**1. Find your Team ID**
```bash
security find-identity -v -p codesigning
# Look for a line like:
# "Apple Development: Your Name (YOURTEAMID)"
#                                ^^^^^^^^^^^ this is your DEVELOPMENT_TEAM
```

**2. Build, sign, and install**
```bash
make install DEVELOPMENT_TEAM=YOURTEAMID
```

Override the bundle ID if needed:
```bash
make install DEVELOPMENT_TEAM=YOURTEAMID BUNDLE_ID=com.example.vault
```

Both variables can also be exported in your shell so you don't need to repeat them:
```bash
export DEVELOPMENT_TEAM=YOURTEAMID
make install
```

`make install` copies `SecureVault.app` to `/Applications` and installs a small
`secure-vault` wrapper in `/usr/local/bin` that executes the signed CLI inside
the app bundle. Keeping the executable inside the signed app bundle preserves the
embedded provisioning profile that backs the Keychain access group.

## Usage

### 1. Generate a key pair

Run this once. The private key is generated inside the Secure Enclave and never exported.

```bash
secure-vault keygen
# or with a custom tag and label:
secure-vault keygen --tag myapp --label "My project secrets"
```

### 2. Encrypt

No authentication required — encryption uses only the public key.

```bash
# Encrypt a file → binary output file
secure-vault encrypt --input secret.txt --output secret.enc

# Encrypt a file → base64 to stdout
secure-vault encrypt --input secret.txt

# Encrypt stdin → base64 to stdout
echo "my secret" | secure-vault encrypt
```

### 3. Decrypt

**Touch ID or Apple Watch prompt fires here.**

```bash
# Decrypt a binary file → file
secure-vault decrypt --input secret.enc --output secret.txt

# Decrypt a binary file → stdout
secure-vault decrypt --input secret.enc

# Pipe from encrypt
echo "my secret" | secure-vault encrypt | secure-vault decrypt

# Custom prompt message (shown in the Touch ID / Watch dialog)
secure-vault decrypt --input secret.enc --reason "Open project config"
```

### 4. Manage keys

```bash
# List all Secure Enclave keys in the keychain
secure-vault list

# Delete a key (irreversible)
secure-vault delete --tag myapp

# Delete without confirmation prompt
secure-vault delete --tag myapp --force
```

## How it works

| Step | What happens |
|---|---|
| `keygen` | Generates a P-256 key pair. Private key stays in the Secure Enclave, protected by `biometryAny OR watch` access control. |
| `encrypt` | Fetches the public key, encrypts with ECIES (P-256 + AES-GCM). No auth required. |
| `decrypt` | Fetches the private key reference. The Secure Enclave enforces Touch ID / Apple Watch auth before performing the decryption operation. |

**Algorithm:** `eciesEncryptionCofactorVariableIVX963SHA256AESGCM`  
**Key storage:** Login keychain, identified by application tag  
**File format:** Raw binary (files), Base64 (stdin/stdout)

## Options reference

```
secure-vault keygen  --tag <tag>     (default: io.securevault.default)
                     --label <label>

secure-vault encrypt --tag <tag>
                     --input <file>   (stdin if omitted)
                     --output <file>  (base64 stdout if omitted)

secure-vault decrypt --tag <tag>
                     --input <file>   (base64 stdin if omitted)
                     --output <file>  (stdout if omitted)
                     --reason <text>  (shown in auth prompt)

secure-vault list

secure-vault delete  --tag <tag>     (required)
                     --force         (skip confirmation)
```

## Project structure

```
secure-vault/
├── Package.swift
├── Makefile
└── Sources/secure-vault/
    ├── SecureVault.swift               @main entry point, root command
    ├── SecureEnclaveManager.swift      all crypto and keychain logic
    ├── Utilities.swift                 shared helpers
    └── Commands/
        ├── KeygenCommand.swift
        ├── EncryptCommand.swift
        ├── DecryptCommand.swift
        ├── ListCommand.swift
        └── DeleteCommand.swift
```

## Troubleshooting

**Binary is killed immediately (exit 137 / SIGKILL)**  
The `keychain-access-groups` entitlement requires a provisioning profile. Use `make sign` (which calls `xcodebuild` with automatic signing) rather than `codesign` directly — Xcode creates and embeds the profile in `SecureVault.app` for you.

**"No valid identities found" when signing**  
Open Xcode → Settings → Accounts, add your Apple ID, and download your development certificate.

**"Secure Enclave is not available"**  
Your Mac must have Apple Silicon or a T2 chip. Older Intel Macs without T2 do not have a Secure Enclave.

**Decryption fails immediately without prompting**  
The binary is likely unsigned or the signing identity doesn't match the one that generated the key. Re-sign with the correct identity or regenerate the key after signing.

**Touch ID prompt doesn't appear in some terminals**  
Some terminal emulators (e.g. certain SSH sessions) can't present the system auth dialog. Run from a local Terminal or iTerm2 session.
