#!/usr/bin/env bash
set -euo pipefail

COMMENT='me@aryapaw.dev'

KEY_FILE='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPmBdRFELuAxun1fX7nOpRLcpj98PXd5E95XUVmGx3K0'
KEY_GENERAL='sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIIAMGvI9FY+SNLIG/AKcPG0EuWTGHKhPTvE/gskThvdGAAAAC3NzaDpHZW5lcmFs'
KEY_MAIN='sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIDmbvz9IBFg4kXkI/t6GjWWkAGZ9nlj2fUwXfpZ5HgtKAAAACHNzaDpNYWlu'

is_root() {
  [ "$(id -u)" -eq 0 ]
}

print_header() {
  echo
  echo 'ssh-access'
  echo '----------'
}

normalize_list() {
  tr ',;' '  ' | xargs -n1 2>/dev/null || true
}

detect_users() {
  awk -F: '
    ($1 == "root") { print $1; next }
    ($3 >= 1000 && $6 != "" && $6 != "/" && $7 !~ /(nologin|false)$/) { print $1 }
  ' /etc/passwd | awk '!seen[$0]++'
}

user_home() {
  getent passwd "$1" | cut -d: -f6
}

apply_key() {
  local user="$1"
  local key="$2"
  local home file tmp group

  if ! id "$user" >/dev/null 2>&1; then
    echo "SKIP: user '$user' does not exist"
    return 0
  fi

  if ! is_root && [ "$user" != "$(id -un)" ]; then
    echo "ERROR: cannot modify user '$user' without root. Run with sudo."
    return 1
  fi

  home="$(user_home "$user")"

  if [ -z "$home" ] || [ "$home" = "/" ]; then
    echo "SKIP: invalid home for user '$user'"
    return 0
  fi

  file="$home/.ssh/authorized_keys"

  mkdir -p "$home/.ssh"
  touch "$file"

  tmp="$(mktemp)"
  awk \
    -v k1="$KEY_FILE" \
    -v k2="$KEY_GENERAL" \
    -v k3="$KEY_MAIN" \
    'index($0,k1)==0 && index($0,k2)==0 && index($0,k3)==0' \
    "$file" > "$tmp"

  cat "$tmp" > "$file"
  rm -f "$tmp"

  printf '%s %s\n' "$key" "$COMMENT" >> "$file"

  chmod 700 "$home/.ssh"
  chmod 600 "$file"

  if is_root; then
    group="$(id -gn "$user")"
    chown -R "$user:$group" "$home/.ssh"
  fi

  echo "OK: installed key for '$user' -> $file"
}

choose_key() {
  echo 'Choose SSH key mode:'
  echo '1) Simplified: id_ed25519'
  echo '2) Hardware touch: id_ed25519_sk_main'
  echo 'q) Quit'
  printf '> '

  local choice
  read -r choice

  case "$choice" in
    1) SELECTED_KEY="$KEY_FILE"; SELECTED_MODE='id_ed25519' ;;
    2) SELECTED_KEY="$KEY_MAIN"; SELECTED_MODE='id_ed25519_sk_main' ;;
    q|Q) exit 0 ;;
    *) echo 'ERROR: invalid key mode'; exit 1 ;;
  esac
}

choose_targets() {
  local users=()
  local input
  local selected=()
  local idx token manual

  mapfile -t users < <(detect_users)

  echo
  echo 'Choose target users:'
  echo '0) Current effective user only'

  idx=1
  for user in "${users[@]}"; do
    echo "$idx) $user"
    idx=$((idx + 1))
  done

  echo 'a) All listed users'
  echo 'm) Manual username input'
  echo 'q) Quit'
  echo
  echo 'You can enter several numbers, for example: 1,3 or 1 3'
  printf '> '
  read -r input

  case "$input" in
    q|Q)
      exit 0
      ;;
    0)
      TARGET_USERS=("$(id -un)")
      return 0
      ;;
    a|A)
      TARGET_USERS=("${users[@]}")
      return 0
      ;;
    m|M)
      echo
      echo 'Enter one or several existing usernames, separated by spaces or commas:'
      printf '> '
      read -r manual
      while IFS= read -r token; do
        [ -n "$token" ] && selected+=("$token")
      done < <(printf '%s\n' "$manual" | normalize_list)
      TARGET_USERS=("${selected[@]}")
      return 0
      ;;
  esac

  while IFS= read -r token; do
    [ -n "$token" ] || continue
    if ! [[ "$token" =~ ^[0-9]+$ ]]; then
      echo "ERROR: invalid selection '$token'"
      exit 1
    fi

    if [ "$token" -lt 1 ] || [ "$token" -gt "${#users[@]}" ]; then
      echo "ERROR: selection '$token' is out of range"
      exit 1
    fi

    selected+=("${users[$((token - 1))]}")
  done < <(printf '%s\n' "$input" | normalize_list)

  if [ "${#selected[@]}" -eq 0 ]; then
    echo 'ERROR: no users selected'
    exit 1
  fi

  TARGET_USERS=("${selected[@]}")
}

confirm() {
  echo
  echo "Selected key: $SELECTED_MODE"
  echo 'Selected users:'
  printf ' - %s\n' "${TARGET_USERS[@]}"
  echo
  echo 'Known personal keys will be removed from selected authorized_keys files before adding the selected key.'
  echo 'Unknown keys will not be removed.'
  printf 'Continue? [y/N] '

  local answer
  read -r answer

  case "$answer" in
    y|Y|yes|YES) return 0 ;;
    *) echo 'Cancelled'; exit 0 ;;
  esac
}

main() {
  print_header
  choose_key
  choose_targets
  confirm

  echo
  for user in "${TARGET_USERS[@]}"; do
    apply_key "$user" "$SELECTED_KEY"
  done
}

main "$@"
