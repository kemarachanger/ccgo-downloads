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
  version=0.1.0
  case "$(uname -m)" in
    arm64)
      architecture=arm64
      expected=3f581df0c3c984e81da767d1828542d68cdb4212fe56268dcd01a6ebd88d8dd2
      encrypted_expected=8166e255c931a89a0f99cae238afaf3497dd66017cdc01a075a565d4065b614f
      ;;
    x86_64)
      architecture=amd64
      expected=e232cda5203dc411d59d997a4549e5fdfc478e404e79d21a377527b64e285642
      encrypted_expected=3d72d0467a41cd67b0d5151974f0d49f09de325533bca6a9d3bacd3bd43ecfdd
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
