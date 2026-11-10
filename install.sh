#!/bin/bash
ccgo_download_install() (
  set -euo pipefail
  set +x
  umask 077
  die() { printf 'ccgo | %s\n' "$*" >&2; exit 1; }
  [[ $# -eq 0 ]] || die 'This installer takes no arguments.'
  [[ "$(uname -s)" == Darwin ]] || die 'ccgo requires macOS 15 or later.'
  os_version="$(sw_vers -productVersion)"
  os_major="${os_version%%.*}"
  [[ "$os_major" =~ ^[0-9]+$ ]] && [[ "$os_major" -ge 15 ]] || die 'ccgo requires macOS 15 or later.'
  version=0.1.2
  case "$(uname -m)" in
    arm64)
      architecture=arm64
      expected=4778eed157efcc6845a92399222028ec78fa3461b6de9a0a212d844efed3a516
      encrypted_expected=dbed026612364591a98ba6ec3394c2cd93cec2ca0308e8feddfabac7a24c40a7
      ;;
    x86_64)
      architecture=amd64
      expected=d002a228e008da96b7a7e94cd7bb94a64964a91df80709d48c2eb3077926c81c
      encrypted_expected=957e2ed724b6e27f8e014cb87c1cafc021ccaab6ff63b8cadfdbb34c5127591b
      ;;
    *) die 'Unsupported Mac architecture.' ;;
  esac
  endpoint="https://github.com/kemarachanger/ccgo-downloads/releases/download/v$version/ccgo-$version-darwin-$architecture.tar.gz.enc"
  # stdin contains this script when launched with curl | bash. Read the password
  # from the controlling terminal, without echoing or putting it in history.
  exec 3<>/dev/tty || die 'Run this command in an interactive Mac terminal.'
  printf 'ccgo | Download password: ' >&3
  IFS= read -r -s password <&3 || die 'No password was entered.'
  printf '\n' >&3
  exec 3>&-
  [[ "$password" =~ ^[[:print:]]{6,128}$ ]] || die 'Enter a password of 6–128 printable characters.'
  work="$(mktemp -d "${TMPDIR:-/tmp}/ccgo-download.XXXXXXXX")"
  trap 'unset password; rm -rf -- "$work"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  archive="$work/ccgo.tar.gz"
  encrypted="$work/ccgo.tar.gz.enc"
  printf 'ccgo | Downloading %s for %s\n' "$version" "$architecture"
  # Only encrypted bytes are public. The password never leaves this Mac.
  if ! curl -q --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 20 --max-time 600 --retry 2 --retry-delay 1 --output "$encrypted" "$endpoint"; then
    die 'Download interrupted. Run the command again to retry.'
  fi
  actual="$(shasum -a 256 "$encrypted")"
  [[ "${actual%% *}" == "$encrypted_expected" ]] || die 'Encrypted package checksum mismatch. Installation stopped.'
  # stdin is a pipe here, so the password is absent from argv and environment.
  if ! printf '%s\n' "$password" | /usr/bin/openssl enc -d -aes-256-cbc -pbkdf2 -iter 1000000 -md sha256 -pass stdin -in "$encrypted" -out "$archive" 2>/dev/null; then
    die 'Incorrect download password. Installation stopped.'
  fi
  unset password
  actual="$(shasum -a 256 "$archive")"
  [[ "${actual%% *}" == "$expected" ]] || die 'Incorrect password or package checksum mismatch. Installation stopped.'
  printf 'ccgo | Package verified; installing\n'
  tar -xzf "$archive" -C "$work"
  bundle="$work/ccgo-$version-darwin-$architecture"
  [[ -f "$bundle/install.sh" && ! -L "$bundle/install.sh" ]] || die 'Package installer is missing.'
  [[ "$(cat "$bundle/VERSION")" == "$version" && "$(cat "$bundle/ARCH")" == "$architecture" ]] || die 'Package version or architecture does not match.'
  /bin/bash "$bundle/install.sh"
)

ccgo_download_install "$@"
