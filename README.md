# ssh-access

Personal SSH `authorized_keys` bootstrap.

The script installs one selected public SSH key and removes the other known personal public keys from selected users' `authorized_keys` files.

It does **not** remove unknown keys.

## Key modes

1. `id_ed25519` - simplified file key.
2. `id_ed25519_sk_main` - hardware key with touch.

`id_ed25519_sk_fast` is intentionally not used.

## What the script removes

Before adding the selected key, the script removes these known personal keys from selected `authorized_keys` files:

- `id_ed25519`
- `id_ed25519_sk`
- `id_ed25519_sk_main`

Then it appends the selected key.

## Target user selection

The script can install the key for:

- the current effective user;
- one or several detected users from `/etc/passwd`;
- all listed users;
- manually entered usernames.

To modify users other than the current one, run the script with `sudo`.

## Run from GitHub

Replace `AryaPaw/ssh-access` if the repository is named differently.

```bash
curl -fsSLO 'https://raw.githubusercontent.com/AryaPaw/ssh-access/main/install.sh' && bash install.sh
```

For installing to `root` or other users:

```bash
curl -fsSLO 'https://raw.githubusercontent.com/AryaPaw/ssh-access/main/install.sh' && sudo bash install.sh
```

The downloaded `install.sh` removes itself on exit when run outside a Git checkout. To keep the file, set `SSH_ACCESS_KEEP=1`.

## Run without saving the launcher command to Bash history

```bash
export HISTFILE=/dev/null; set +o history; trap '' DEBUG; curl -fsSLO 'https://raw.githubusercontent.com/AryaPaw/ssh-access/main/install.sh' && sudo bash install.sh; HN="$(history 1 2>/dev/null | awk '{print $1}')"; [ -n "$HN" ] && history -d "$HN" 2>/dev/null || true
```

This only affects ordinary shell history. It does not hide commands from audit logs, terminal scrollback, session recording, or provider consoles.

## Safer manual review flow

```bash
curl -fsSLO 'https://raw.githubusercontent.com/AryaPaw/ssh-access/main/install.sh' && less install.sh && sudo bash install.sh
```

## Suggested repository names

Recommended: `ssh-access`.

Other options:

- `ssh-keyring`
- `authorized-keys`
- `ssh-bootstrap`
- `server-access`
