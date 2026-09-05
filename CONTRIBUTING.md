# Contributing to OmaMigrate

We welcome contributions, bug reports, and feature suggestions from the Omarchy community!

## Development Guidelines

1. **Keep it Idempotent**: Any script or feature added to the restoration flow must be safe to run multiple times without corrupting state or failing on reruns.
2. **Respect Architecture Portability**: Never assume the target machine shares the exact same CPU architecture (e.g. migrating between an Apple Silicon Asahi Mac and an x86_64 ThinkPad). Always filter hardware-specific drivers.
3. **Security First**: Do not log secrets, API keys, or plaintext passwords. Ensure appropriate file permissions (`700` for `.ssh`/`.gnupg`/`.password-store`, `600` for private keys).
4. **Shell Script Quality**: Run `tests/test_syntax.sh` before committing to ensure `bash -n` validation passes.

## Pull Request Process

1. Fork the repository and create your feature branch: `git checkout -b feature/my-enhancement`.
2. Test on a clean environment or container.
3. Commit your changes with clear messages.
4. Push to your fork and submit a Pull Request.
