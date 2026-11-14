#!/bin/bash
ccgo_download_install() (
  set -euo pipefail
  set +x
  umask 077
  completed=''
  work=''
  releases=''
  password=''
  die() { printf 'ccgo | %s\n' "$*" >&2; exit 1; }
  # Remove private download files on every exit. A run that stops before its
  # last statement (including a bash 3.2 unbound-variable error) exits non-zero.
  finish() {
    local status=$?
    password=''
    if [[ -n "$work" && -n "$releases" && "$work" == "$releases/.download-"* ]]; then
      rm -rf -- "$work" 2>/dev/null || true
    fi
    if [[ "$completed" != 1 ]]; then
      [[ $status -ne 0 ]] || status=1
      exit "$status"
    fi
  }
  trap finish EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  [[ $# -eq 0 ]] || die 'This installer takes no arguments.'
  [[ $EUID -ne 0 ]] || die 'Run this installer as your normal user, without sudo.'
  [[ "$(uname -s)" == Darwin ]] || die 'ccgo requires macOS 15 or later.'
  os_version="$(sw_vers -productVersion)"
  os_major="${os_version%%.*}"
  [[ "$os_major" =~ ^[0-9]+$ ]] && [[ "$os_major" -ge 15 ]] || die 'ccgo requires macOS 15 or later.'
  # This reports the hardware, including in a Rosetta terminal.
  [[ "$(PATH="$PATH:/usr/sbin" sysctl -n hw.optional.arm64 2>/dev/null || true)" == 1 ]] || die 'ccgo needs a Mac with Apple silicon.'
  # scripts/release.py rewrites these values together. Published assets are immutable.
  version=0.3.0
  architecture=arm64
  expected=b24586b6b9e0f19f76da0b672ae13a246592cbf1a052c40d128009a670a2058a
  encrypted_expected=e840211c1dcd5331e9f7df3b7e997a6266785616bc552b29d9762348e972943c
  endpoint="https://github.com/kemarachanger/ccgo-downloads/releases/download/v$version/ccgo-$version-darwin-$architecture.tar.gz.enc"
  # Decrypted files stay inside ccgo's private releases folder, which Claude
  # sessions cannot read, rather than in a shared temporary folder.
  base="$HOME/.local/share/ccgo"
  releases="$base/releases"
  [[ ! -L "$base" && ! -L "$releases" ]] || die 'Installation directory must not be a symbolic link.'
  mkdir -p "$releases" 2>/dev/null || die 'Cannot create ~/.local/share/ccgo (disk full or no permission). No changes were made.'
  [[ ! -L "$base" && ! -L "$releases" && -d "$releases" ]] || die 'Installation directory must not be a symbolic link.'
  chmod 700 "$base" "$releases" 2>/dev/null || die 'Cannot protect ~/.local/share/ccgo (no permission). No changes were made.'
  # Remove folders left by an interrupted installer.
  find "$releases" -mindepth 1 -maxdepth 1 -type d \( -name '.download-*' -o -name '.install-*' \) -mmin +60 -exec rm -rf -- {} + 2>/dev/null || true
  # stdin contains this script when launched with curl | bash. Read the password
  # from the controlling terminal, without echoing or putting it in history.
  { exec 3<>/dev/tty; } 2>/dev/null || die 'Run this command in an interactive Mac terminal.'
  printf 'ccgo | Download password: ' >&3
  IFS= read -r -s password <&3 || die 'No password was entered.'
  printf '\n' >&3
  exec 3>&-
  [[ "$password" =~ ^[[:print:]]{6,128}$ ]] || die 'Enter a password of 6–128 printable characters.'
  work="$(mktemp -d "$releases/.download-XXXXXXXX" 2>/dev/null)" || die 'Not enough disk space or permission to install. No changes were made.'
  archive="$work/ccgo.tar.gz"
  encrypted="$work/ccgo.tar.gz.enc"
  printf 'ccgo | Downloading %s\n' "$version"
  # Only encrypted bytes are public. The password never leaves this Mac.
  if ! curl -q --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 20 --speed-limit 1024 --speed-time 60 --max-time 7200 --retry 2 --retry-delay 1 --output "$encrypted" "$endpoint"; then
    die 'Download interrupted. Run the command again to retry.'
  fi
  actual="$(shasum -a 256 "$encrypted")"
  [[ "${actual%% *}" == "$encrypted_expected" ]] || die 'Encrypted package checksum mismatch. Installation stopped.'
  # stdin is a pipe here, so the password is absent from argv and environment.
  if ! printf '%s\n' "$password" | /usr/bin/openssl enc -d -aes-256-cbc -pbkdf2 -iter 1000000 -md sha256 -pass stdin -in "$encrypted" -out "$archive" 2>/dev/null; then
    die 'Incorrect download password. Installation stopped.'
  fi
  password=''
  actual="$(shasum -a 256 "$archive")"
  [[ "${actual%% *}" == "$expected" ]] || die 'Incorrect password or package checksum mismatch. Installation stopped.'
  printf 'ccgo | Package verified; installing\n'
  tar -xzf "$archive" -C "$work" 2>/dev/null || die 'Not enough disk space or permission to install. No changes were made.'
  rm -f -- "$archive" "$encrypted"
  bundle="$work/ccgo-$version-darwin-$architecture"
  [[ -f "$bundle/install.sh" && ! -L "$bundle/install.sh" ]] || die 'Package installer is missing.'
  [[ "$(cat "$bundle/VERSION" 2>/dev/null)" == "$version" && "$(cat "$bundle/ARCH" 2>/dev/null)" == "$architecture" ]] || die 'Package version or architecture does not match.'
  /bin/bash "$bundle/install.sh"
  completed=1
)

ccgo_download_install "$@"
