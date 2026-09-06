# Contributing to OmaMigrate

We welcome contributions, bug reports, and feature suggestions from the Omarchy community!

## Development Guidelines

1. **Keep it Idempotent**: Any script or feature added to the restoration flow must be safe to run multiple times without corrupting state or failing on reruns.
2. **Respect Architecture Portability**: Never assume the target machine shares the exact same CPU architecture (e.g. migrating between an Apple Silicon Asahi Mac and an x86_64 ThinkPad). Always filter hardware-specific drivers.
3. **Security First**: Do not log secrets, API keys, or plaintext passwords. Ensure appropriate file permissions (`700` for `.ssh`/`.gnupg`/`.password-store`, `600` for private keys).
4. **Shell Script Quality**: Run `tests/test_syntax.sh` before committing to ensure `bash -n` validation and CLI tests pass.
5. **OpenSSF Supply Chain Security**: All GitHub Actions in `.github/workflows/` must be pinned to full 40-character commit SHAs with version comments.

## Running Tests Locally

Before submitting your pull request, verify that tests and lint checks pass:

```bash
# Run shell syntax and CLI validation
./tests/test_syntax.sh

# Lint QML components (requires Qt 6.8+)
qmllint OmaMigrate.qml
```

## Pull Request Process

1. Fork the repository and create your feature branch: `git checkout -b feat/my-enhancement`.
2. Ensure all local tests and syntax checks pass.
3. Commit your changes with clear, conventional commit messages.
4. Push to your fork and submit a Pull Request against `main`.
5. Ensure all CI checks (Manifest validation, shell tests, QML linting, CodeQL) pass.

## Release Process

OmaMigrate follows [Semantic Versioning](https://semver.org/) and documents changes according to [Keep a Changelog](https://keepachangelog.com/).

To publish a new release:

1. **Update Changelog**:
   Add a new section `## [X.Y.Z] - YYYY-MM-DD` in `CHANGELOG.md` detailing the changes (Added, Changed, Deprecated, Removed, Fixed, Security).
2. **Bump Manifest Version**:
   Update `"version": "X.Y.Z"` in `manifest.json`.
3. **Commit & Tag**:
   ```bash
   git commit -am "chore(release): bump version to X.Y.Z"
   git tag vX.Y.Z
   git push origin main
   git push origin vX.Y.Z
   ```
4. **Automated Release**:
   Pushing the `v*` tag triggers the [Release Workflow](.github/workflows/release.yml), which:
   - Verifies the tag format and ensures `manifest.json` version matches the tag.
   - Runs full test syntax validation and QML component linting in an Arch Linux container.
   - Extracts the corresponding section from `CHANGELOG.md`.
   - Packages the distribution archive (`omamigrate-vX.Y.Z.tar.gz`) along with its SHA256 checksum.
   - Publishes the GitHub Release automatically with notes and distribution artifacts.
