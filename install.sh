#!/usr/bin/env bash
set -euo pipefail

COMMENT='me@aryapaw.dev'

KEY_FILE='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPmBdRFELuAxun1fX7nOpRLcpj98PXd5E95XUVmGx3K0'
KEY_GENERAL='sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIIAMGvI9FY+SNLIG/AKcPG0EuWTGHKhPTvE/gskThvdGAAAAC3NzaDpHZW5lcmFs'
KEY_MAIN='sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIDmbvz9IBFg4kXkI/t6GjWWkAGZ9nlj2fUwXfpZ5HgtKAAAACHNzaDpNYWlu'

SELECTED_KEY=''
SELECTED_KEY_NAME=''
SELECTED_KEY_LABEL=''
TARGET_USERS=()

self_script_path() {
  local path="$1"
  local dir

  while [ -L "$path" ]; do
    path="$(readlink "$path")"
  done

  dir="$(cd -P "$(dirname "$path")" && pwd)"
  printf '%s/%s\n' "$dir" "$(basename "$path")"
}

should_self_delete() {
  local dir

  if [ -n "${SSH_ACCESS_KEEP:-}" ]; then
    return 1
  fi

  dir="$(dirname "$SCRIPT_SELF")"

  if git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return 1
  fi

  return 0
}

remove_self() {
  should_self_delete || return 0
  [ -f "$SCRIPT_SELF" ] || return 0
  rm -f -- "$SCRIPT_SELF"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  SCRIPT_SELF="$(self_script_path "${BASH_SOURCE[0]}")"
  trap remove_self EXIT
fi

if [ -t 1 ] && [ "${NO_COLOR:-}" = "" ]; then
  RESET=$'\033[0m'
  BOLD=$'\033[1m'

  TEXT=$'\033[38;5;255m'      # white
  MUTED=$'\033[38;5;245m'     # grey
  DIM=$'\033[38;5;240m'       # dark grey
  ACCENT=$'\033[38;5;203m'    # soft red
  BRAND=$'\033[38;5;141m'     # purple

  HEAD="$TEXT"
  NUM="$ACCENT"

  SIMPLE=$'\033[38;5;117m'    # light blue
  HARDWARE="$ACCENT"

  OKC=$'\033[38;5;114m'       # soft green
  WARNC="$ACCENT"
  ERRC="$ACCENT"
else
  RESET=''
  BOLD=''
  TEXT=''
  MUTED=''
  DIM=''
  ACCENT=''
  BRAND=''
  HEAD=''
  NUM=''
  SIMPLE=''
  HARDWARE=''
  OKC=''
  WARNC=''
  ERRC=''
fi

title() {
  printf '\n%s%b%s\n' "$HEAD$BOLD" "$1" "$RESET"
}

option() {
  local key="$1"
  local label="$2"
  local note="${3:-}"

  printf '  %s%-2s%s %s' "$NUM" "$key" "$RESET" "$label"

  if [ -n "$note" ]; then
    printf ' %s(%s)%s' "$MUTED" "$note" "$RESET"
  fi

  printf '\n'
}

ok() {
  printf '%sOK%s    %s\n' "$OKC$BOLD" "$RESET" "$1"
}

warn() {
  printf '%sWARN%s  %s\n' "$WARNC$BOLD" "$RESET" "$1"
}

error() {
  printf '%sERROR%s %s\n' "$ERRC$BOLD" "$RESET" "$1" >&2
}

prompt() {
  printf '%s>%s ' "$NUM$BOLD" "$RESET"
}

key_name() {
  case "$1" in
    "$KEY_FILE") echo 'id_ed25519' ;;
    "$KEY_GENERAL") echo 'id_ed25519_sk' ;;
    "$KEY_MAIN") echo 'id_ed25519_sk_main' ;;
    *) echo 'unknown' ;;
  esac
}

key_label_by_name() {
  case "$1" in
    id_ed25519) printf '%s%s%s' "$SIMPLE" "$1" "$RESET" ;;
    id_ed25519_sk_main) printf '%s%s%s' "$HARDWARE" "$1" "$RESET" ;;
    id_ed25519_sk) printf '%s%s%s' "$MUTED" "$1" "$RESET" ;;
    *) printf '%s' "$1" ;;
  esac
}

user_home() {
  getent passwd "$1" | cut -d: -f6
}

known_key_present_in_file() {
  local file="$1"
  local key="$2"

  [ -f "$file" ] || return 1
  awk -v k="$key" 'index($0,k)==1 { found=1 } END { exit found ? 0 : 1 }' "$file"
}

require_root_for_targets() {
  local current_user
  local user

  current_user="$(id -un)"

  if [ "$(id -u)" -eq 0 ]; then
    return 0
  fi

  for user in "${TARGET_USERS[@]}"; do
    if [ "$user" != "$current_user" ]; then
      error "Installing keys for other users requires root. Run: sudo bash install.sh"
      exit 1
    fi
  done
}

apply_key() {
  local user="$1"
  local key="$2"
  local home
  local file
  local tmp
  local group

  if ! id "$user" >/dev/null 2>&1; then
    warn "User '$user' does not exist, skipped"
    return 0
  fi

  home="$(user_home "$user")"

  if [ -z "$home" ] || [ "$home" = "/" ]; then
    warn "Invalid home for user '$user', skipped"
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
    'index($0,k1)!=1 && index($0,k2)!=1 && index($0,k3)!=1' \
    "$file" > "$tmp"

  cat "$tmp" > "$file"
  rm -f "$tmp"

  printf '%s %s\n' "$key" "$COMMENT" >> "$file"

  chmod 700 "$home/.ssh"
  chmod 600 "$file"

  if [ "$(id -u)" -eq 0 ]; then
    group="$(id -gn "$user")"
    chown -R "$user:$group" "$home/.ssh"
  fi

  ok "$user -> $file"
}

list_target_users() {
  {
    getent passwd "$(id -un)" 2>/dev/null || true
    getent passwd root 2>/dev/null || true
    getent passwd | awk -F: '
      $3 >= 1000 &&
      $6 != "" &&
      $6 != "/" &&
      $7 !~ /(nologin|false)$/ {
        print
      }
    '
  } | awk -F: '!seen[$1]++ { print $1 ":" $3 ":" $6 ":" $7 }'
}

choose_key() {
  local key_choice

  title "SSH key mode"

  option "1" "${SIMPLE}${BOLD}Simplified${RESET}      ${MUTED}id_ed25519${RESET}"
  option "2" "${HARDWARE}${BOLD}Hardware touch${RESET}  ${MUTED}id_ed25519_sk_main${RESET}"
  option "q" "${TEXT}Quit${RESET}"

  printf '\n'
  prompt
  read -r key_choice

  case "$key_choice" in
    1)
      SELECTED_KEY="$KEY_FILE"
      SELECTED_KEY_NAME='id_ed25519'
      SELECTED_KEY_LABEL="${SIMPLE}${BOLD}Simplified${RESET}"
      ;;
    2)
      SELECTED_KEY="$KEY_MAIN"
      SELECTED_KEY_NAME='id_ed25519_sk_main'
      SELECTED_KEY_LABEL="${HARDWARE}${BOLD}Hardware touch${RESET}"
      ;;
    q|Q)
      exit 0
      ;;
    *)
      error "Invalid key mode"
      exit 1
      ;;
  esac
}

choose_users() {
  local current_user
  local sudo_user
  local users=()
  local selected=()
  local line
  local i
  local input
  local part
  local username
  local manual_users
  local note
  local -A seen=()

  current_user="$(id -un)"
  sudo_user="${SUDO_USER:-}"

  while IFS= read -r line; do
    users+=("$line")
  done < <(list_target_users)

  title "Target users"

  for i in "${!users[@]}"; do
    username="${users[$i]%%:*}"
    note=''

    if [ "$username" = "$current_user" ]; then
      note='current'
    elif [ -n "$sudo_user" ] && [ "$username" = "$sudo_user" ]; then
      note='sudo user'
    fi

    option "$((i + 1))" "${TEXT}${username}${RESET}" "$note"
  done

  printf '\n'
  option "a" "${TEXT}All listed users${RESET}"
  option "m" "${TEXT}Manual username input${RESET}"
  option "q" "${TEXT}Quit${RESET}"

  printf '\n%sSelect users:%s numbers separated by comma, for example %s1,3,m%s\n' "$MUTED" "$RESET" "$NUM" "$RESET"
  prompt
  read -r input

  input="${input// /}"

  if [ "$input" = "q" ] || [ "$input" = "Q" ]; then
    exit 0
  fi

  IFS=',' read -ra parts <<< "$input"

  for part in "${parts[@]}"; do
    case "$part" in
      a|A)
        for line in "${users[@]}"; do
          selected+=("${line%%:*}")
        done
        ;;
      m|M)
        printf '%sManual usernames, separated by spaces:%s ' "$MUTED" "$RESET"
        read -r manual_users

        for username in $manual_users; do
          selected+=("$username")
        done
        ;;
      ''|*[!0-9]*)
        error "Invalid selection: $part"
        exit 1
        ;;
      *)
        if [ "$part" -lt 1 ] || [ "$part" -gt "${#users[@]}" ]; then
          error "User number out of range: $part"
          exit 1
        fi

        selected+=("${users[$((part - 1))]%%:*}")
        ;;
    esac
  done

  TARGET_USERS=()

  for username in "${selected[@]}"; do
    if [ -z "${seen[$username]:-}" ]; then
      TARGET_USERS+=("$username")
      seen[$username]=1
    fi
  done

  if [ "${#TARGET_USERS[@]}" -eq 0 ]; then
    error "No users selected"
    exit 1
  fi
}

print_user_plan() {
  local user="$1"
  local home
  local file
  local found_any=0
  local remove_any=0
  local refresh=0
  local key
  local name

  if ! id "$user" >/dev/null 2>&1; then
    printf '  %s%s%s\n' "$ERRC$BOLD" "$user - user does not exist, will be skipped" "$RESET"
    return 0
  fi

  home="$(user_home "$user")"
  file="$home/.ssh/authorized_keys"

  printf '  %s%s%s\n' "$TEXT$BOLD" "$user" "$RESET"
  printf '    %sfile:%s    %s\n' "$MUTED" "$RESET" "$file"
  printf '    %sadd:%s     %b %s(%s)%s\n' "$MUTED" "$RESET" "$SELECTED_KEY_LABEL" "$MUTED" "$SELECTED_KEY_NAME" "$RESET"

  for key in "$KEY_FILE" "$KEY_GENERAL" "$KEY_MAIN"; do
    name="$(key_name "$key")"

    if known_key_present_in_file "$file" "$key"; then
      found_any=1

      if [ "$key" = "$SELECTED_KEY" ]; then
        refresh=1
      else
        if [ "$remove_any" -eq 0 ]; then
          printf '    %sremove:%s  ' "$MUTED" "$RESET"
          remove_any=1
        else
          printf ', '
        fi

        key_label_by_name "$name"
      fi
    fi
  done

  if [ "$remove_any" -eq 1 ]; then
    printf '\n'
  fi

  if [ "$refresh" -eq 1 ]; then
    printf '    %srefresh:%s %s%s%s already exists, will be rewritten\n' "$MUTED" "$RESET" "$TEXT" "$SELECTED_KEY_NAME" "$RESET"
  fi

  if [ "$found_any" -eq 0 ]; then
    printf '    %sremove:%s  none of known keys found\n' "$MUTED" "$RESET"
  elif [ "$remove_any" -eq 0 ]; then
    printf '    %sremove:%s  no other known keys\n' "$MUTED" "$RESET"
  fi
}

confirm_and_apply() {
  local user

  title "Summary"

  printf '  %sMode:%s %b %s(%s)%s\n' "$MUTED" "$RESET" "$SELECTED_KEY_LABEL" "$MUTED" "$SELECTED_KEY_NAME" "$RESET"

  printf '\n%s%s%s\n' "$TEXT$BOLD" "Planned changes" "$RESET"

  for user in "${TARGET_USERS[@]}"; do
    print_user_plan "$user"
  done

  printf '\n%sProceed?%s [y/N] ' "$ACCENT$BOLD" "$RESET"
  read -r confirm

  case "$confirm" in
    y|Y|yes|YES)
      ;;
    *)
      warn "Cancelled"
      exit 0
      ;;
  esac

  require_root_for_targets

  title "Installing"

  for user in "${TARGET_USERS[@]}"; do
    apply_key "$user" "$SELECTED_KEY"
  done
}

main() {
  title "${BRAND}${BOLD}AryaPaw${RESET}${TEXT}${BOLD} SSH access installer"

  choose_key
  choose_users
  confirm_and_apply
}

main "$@"