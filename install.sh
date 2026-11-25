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
  # scripts/release.py rewrites these values together: the Apple silicon
  # package's pins, then each Linux processor's. Published assets are immutable.
  version=0.6.0
  expected=c82a3cf0c15ba579a743fa5df7a27c2258608332cb8ee066247aa8fc675f0e0c
  encrypted_expected=890e319cdf3893c676e36f144afc263f1b7c87b85f4f80e6cb6e4f9da8d45edd
  linux_amd64_expected=1c6e77acec8d0d5e198afc1cd568fa482e238df198da4211396314feff7c90a8
  linux_amd64_encrypted_expected=178912308b56ecca32335e2d094301fdadac346899c463fce3ba22ffd247f2dd
  linux_arm64_expected=e547e5ec97219f880f2de051460735fd48ed009327b65e96093555d82ea18c37
  linux_arm64_encrypted_expected=fb6d0cc39e8c321c95eea7f636863c5523d9567a726ff3da2793567050dbe307
  case "$(uname -s)" in
    Darwin)
      os_version="$(sw_vers -productVersion)"
      os_major="${os_version%%.*}"
      [[ "$os_major" =~ ^[0-9]+$ ]] && [[ "$os_major" -ge 15 ]] || die 'ccgo requires macOS 15 or later.'
      # This reports the hardware, including in a Rosetta terminal.
      [[ "$(PATH="$PATH:/usr/sbin" sysctl -n hw.optional.arm64 2>/dev/null || true)" == 1 ]] || die 'ccgo needs a Mac with Apple silicon.'
      system=darwin architecture=arm64
      ;;
    Linux)
      # WSL runs Windows' programs too, and Claude there also reads Windows'
      # settings, which ccgo does not check.
      case "$(uname -r)" in *[Mm]icrosoft*) die 'ccgo does not run in WSL.' ;; esac
      for interop in /proc/sys/fs/binfmt_misc/WSLInterop*; do
        [[ ! -e "$interop" ]] || die 'ccgo does not run in WSL.'
      done
      # This processor's pins take the Apple silicon ones' place.
      case "$(uname -m)" in
        x86_64) system=linux architecture=amd64 expected="$linux_amd64_expected" encrypted_expected="$linux_amd64_encrypted_expected" ;;
        aarch64 | arm64) system=linux architecture=arm64 expected="$linux_arm64_expected" encrypted_expected="$linux_arm64_encrypted_expected" ;;
        *) die 'ccgo needs an x86-64 or arm64 computer.' ;;
      esac
      # Empty until the first release with Linux packages.
      [[ -n "$expected" && -n "$encrypted_expected" ]] || die 'This release has no Linux package.'
      ;;
    *) die 'ccgo requires macOS 15 or later, or Linux.' ;;
  esac
  # Checked before the password is asked for. A snap's curl cannot write
  # into hidden folders such as ~/.local. The password goes only to the
  # system's own decryptor and the installed ccgo, never to a program found
  # through PATH.
  case "$(command -v curl || true)" in
    '' | /snap/*) die "Install curl from your system's packages, not as a snap, then run the command again." ;;
  esac
  [[ -x /usr/bin/openssl ]] || die 'Install OpenSSL (the openssl package), then run the command again.'
  # Linux has coreutils' sha256sum, macOS Perl's shasum.
  sha256() { if [[ "$system" == linux ]]; then sha256sum "$1"; else shasum -a 256 "$1"; fi; }
  endpoint="https://github.com/kemarachanger/ccgo-downloads/releases/download/v$version/ccgo-$version-$system-$architecture.tar.gz.enc"
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
  { exec 3<>/dev/tty; } 2>/dev/null || die 'Run this command in an interactive terminal.'
  printf 'ccgo | Download password: ' >&3
  IFS= read -r -s password <&3 || die 'No password was entered.'
  printf '\n' >&3
  exec 3>&-
  [[ "$password" =~ ^[[:print:]]{6,128}$ ]] || die 'Enter a password of 6–128 printable characters.'
  work="$(mktemp -d "$releases/.download-XXXXXXXX" 2>/dev/null)" || die 'Not enough disk space or permission to install. No changes were made.'
  archive="$work/ccgo.tar.gz"
  encrypted="$work/ccgo.tar.gz.enc"
  printf 'ccgo | Downloading %s\n' "$version"
  # Only encrypted bytes are public. The password never leaves this computer.
  if ! curl -q --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 20 --speed-limit 1024 --speed-time 60 --max-time 7200 --retry 2 --retry-delay 1 --output "$encrypted" "$endpoint"; then
    die 'Download interrupted. Run the command again to retry.'
  fi
  actual="$(sha256 "$encrypted")"
  [[ "${actual%% *}" == "$encrypted_expected" ]] || die 'Encrypted package checksum mismatch. Installation stopped.'
  # stdin is a pipe here, so the password is absent from argv and environment.
  if ! printf '%s\n' "$password" | /usr/bin/openssl enc -d -aes-256-cbc -pbkdf2 -iter 1000000 -md sha256 -pass stdin -in "$encrypted" -out "$archive" 2>/dev/null; then
    die 'Incorrect download password. Installation stopped.'
  fi
  actual="$(sha256 "$archive")"
  [[ "${actual%% *}" == "$expected" ]] || die 'Incorrect password or package checksum mismatch. Installation stopped.'
  printf 'ccgo | Package verified; installing\n'
  tar -xzf "$archive" -C "$work" 2>/dev/null || die 'Not enough disk space or permission to install. No changes were made.'
  rm -f -- "$archive" "$encrypted"
  bundle="$work/ccgo-$version-$system-$architecture"
  [[ -f "$bundle/install.sh" && ! -L "$bundle/install.sh" ]] || die 'Package installer is missing.'
  [[ "$(cat "$bundle/VERSION" 2>/dev/null)" == "$version" && "$(cat "$bundle/ARCH" 2>/dev/null)" == "$architecture" ]] || die 'Package version or architecture does not match.'
  # Its closing line, which names the next step, is shown last.
  closing="$(/bin/bash "$bundle/install.sh")"
  # The installed ccgo keeps the password for ccgo self-update, read from a
  # pipe as above. The installation stands without it; updates then ask.
  if ! printf '%s\n' "$password" | "$base/current/ccgo" __save-download-password >/dev/null 2>&1; then
    printf 'ccgo | The download password was not saved; ccgo self-update will ask for it.\n' >&2
  fi
  password=''
  printf '%s\n' "$closing"
  completed=1
)

ccgo_download_install "$@"
