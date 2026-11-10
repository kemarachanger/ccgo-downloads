# ccgo downloads

Install on macOS 15 or later:

~~~sh
curl -fsSL https://gist.github.com/raw/db9c6d19cec0d03803a7c0ebff589a13 | bash
~~~

Enter the password supplied by the owner. Open a new terminal, run ccgo config, sign in with ccgo -- auth login, then run ccgo. Re-run the same installer to update; existing configuration is preserved.

This repository contains only the public bootstrap and password-encrypted release assets. Application source stays private. Plaintext node files and passwords are never published here.

The installer uses GitHub downloads and macOS built-in tools. It verifies ciphertext and plaintext checksums. No VPS, GitHub login, or Homebrew is required. An installed Claude Code CLI is required.

Encryption cannot stop offline password guessing. A six-digit password provides limited protection; anyone with the password can install and share the package.

## Windows 11 preview

Windows 11 x64 with native Claude Code and Git for Windows:

```powershell
irm https://raw.githubusercontent.com/kemarachanger/ccgo-downloads/main/windows/install.ps1 | iex
```

Enter the download password, approve the initial protection setup, then run `ccgo config`, `ccgo -- auth login`, and `ccgo`. The package includes nodes 99 and 172. Windows uses native PowerShell; Git Bash, Windows Server, Windows 10 and ARM64 are outside this preview.

Use `ccgo self-update --check` to check for updates and `ccgo self-update` to upgrade ccgo. The installer saves the download credential with the current user's Windows DPAPI. This command does not update Claude Code. Source and plaintext node credentials remain private.
