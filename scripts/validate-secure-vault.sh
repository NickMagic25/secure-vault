#!/bin/sh
set -eu

vault_bin_input=${SECURE_VAULT_BIN:-secure-vault}
vault_bin=

log() {
    printf '\n==> %s\n' "$*"
}

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

assert_equal() {
    expected=$1
    actual=$2
    description=$3

    if [ "$actual" != "$expected" ]; then
        printf 'error: %s mismatch\n' "$description" >&2
        printf 'expected: %s\n' "$expected" >&2
        printf 'actual:   %s\n' "$actual" >&2
        exit 1
    fi
}

expect_failure() {
    description=$1
    shift

    if "$@" >"$tmp_root/expected-failure.out" 2>"$tmp_root/expected-failure.err"; then
        fail "$description unexpectedly succeeded"
    fi
}

if [ -x "$vault_bin_input" ]; then
    vault_bin=$vault_bin_input
else
    vault_bin=$(command -v "$vault_bin_input" 2>/dev/null || true)
fi

if [ -z "$vault_bin" ]; then
    fail "could not find secure-vault. Run make install, or set SECURE_VAULT_BIN=/path/to/secure-vault."
fi

tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/secure-vault-validation.XXXXXX") || fail "could not create temp directory"
cleanup() {
    rm -rf "$tmp_root"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

suffix="$(date +%Y%m%d%H%M%S)-$$"
tag="io.securevault.validation.$suffix"
app="secure-vault-validation-$suffix"
username="validation-user"
secret_name="validation-secret-$suffix"
password_initial="initial-password-$suffix"
password_updated="updated-password-$suffix"
secret_token_initial="initial-token-$suffix"
secret_token_updated="updated-token-$suffix"

export SECURE_VAULT_DB_PATH="$tmp_root/vault.sqlite"

printf 'Using secure-vault binary: %s\n' "$vault_bin"
printf 'Using isolated vault DB:    %s\n' "$SECURE_VAULT_DB_PATH"
printf 'Using validation key tag:   %s\n' "$tag"
printf '\nExpect Touch ID or Apple Watch prompts during this validation.\n'
printf 'If the script stops before key cleanup, remove the validation key with:\n'
printf '  %s delete --tag %s --force\n' "$vault_bin" "$tag"

log "Storing password"
printf '%s' "$password_initial" | "$vault_bin" encrypt-password \
    --app "$app" \
    --username "$username" \
    --password-stdin \
    --tag "$tag"

log "Reading password"
actual_password=$("$vault_bin" get-password --app "$app" --username "$username")
assert_equal "$password_initial" "$actual_password" "initial password read"

log "Updating password"
printf '%s' "$password_updated" | "$vault_bin" update-password \
    --app "$app" \
    --username "$username" \
    --password-stdin

log "Reading updated password"
actual_password=$("$vault_bin" get-password --app "$app" --username "$username")
assert_equal "$password_updated" "$actual_password" "updated password read"

log "Deleting password"
"$vault_bin" delete-password --app "$app" --username "$username" --force
expect_failure "deleted password lookup" "$vault_bin" get-password --app "$app" --username "$username"

log "Storing JSON secret"
"$vault_bin" make-secret \
    --name "$secret_name" \
    --json "{\"API_TOKEN\":\"$secret_token_initial\",\"RETRIES\":1,\"ENABLED\":true}" \
    --tag "$tag"

log "Reading JSON secret key"
actual_token=$("$vault_bin" get-secret --name "$secret_name" --key API_TOKEN)
assert_equal "$secret_token_initial" "$actual_token" "initial secret token read"

log "Updating JSON secret"
"$vault_bin" update-secret \
    --name "$secret_name" \
    --json "{\"API_TOKEN\":\"$secret_token_updated\",\"RETRIES\":2}"

log "Reading updated JSON secret keys"
actual_token=$("$vault_bin" get-secret --name "$secret_name" --key API_TOKEN)
assert_equal "$secret_token_updated" "$actual_token" "updated secret token read"
actual_retries=$("$vault_bin" get-secret --name "$secret_name" --key RETRIES)
assert_equal "2" "$actual_retries" "updated secret retry read"

log "Applying JSON secret"
exports=$("$vault_bin" apply-secret --name "$secret_name")
case "$exports" in
    *"export API_TOKEN='$secret_token_updated'"*) ;;
    *) fail "apply-secret output did not include updated API_TOKEN export" ;;
esac
case "$exports" in
    *"export RETRIES='2'"*) ;;
    *) fail "apply-secret output did not include updated RETRIES export" ;;
esac

log "Deleting JSON secret"
"$vault_bin" delete-secret --name "$secret_name" --force
expect_failure "deleted secret lookup" "$vault_bin" get-secret --name "$secret_name"

log "Deleting validation Secure Enclave key"
"$vault_bin" delete --tag "$tag" --force

log "Validation passed"
