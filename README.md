# ccgo downloads

Install on macOS 15 or later:

~~~sh
curl -fsSL https://gist.github.com/raw/db9c6d19cec0d03803a7c0ebff589a13 | bash
~~~

Enter the password supplied by the owner. Open a new terminal, run ccgo config, sign in with ccgo -- auth login, then run ccgo. Re-run the same installer to update; existing configuration is preserved.

This repository contains only the public bootstrap and password-encrypted release assets. Application source stays private. Plaintext node files and passwords are never published here.

The installer uses GitHub downloads and macOS built-in tools. It verifies ciphertext and plaintext checksums. No VPS, GitHub login, or Homebrew is required. An installed Claude Code CLI is required.

Encryption cannot stop offline password guessing. A six-digit password provides limited protection; anyone with the password can install and share the package.