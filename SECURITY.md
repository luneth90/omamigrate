# Security Policy

## Supported Versions

The following table lists the release branches and versions that currently receive security updates:

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |
| < 1.0   | :x:                |

## Security Considerations

OmaMigrate is designed to handle sensitive user data, including:
- Private SSH keys (`~/.ssh`)
- GPG encryption keys (`~/.gnupg`)
- Unix password stores (`~/.password-store`)
- AI CLI sessions and OAuth tokens

### Best Practices for Users

1. **Never upload the generated `omamigrate-backup.tar.gz` archive to public repositories or public cloud storage.**
2. Use **LocalSend** or encrypted point-to-point transfers (`scp`, local physical USB drive) for transferring migration bundles across machines.
3. Delete temporary restoration staging directories (`~/omarchy-restore` or `/tmp/omamigrate-*`) once migration is complete.

## Reporting a Vulnerability

The OmaMigrate team takes security vulnerabilities seriously. We appreciate your efforts to responsibly disclose findings.

### Private Reporting Channels

Please do **not** report security vulnerabilities through public GitHub issues. Instead:

1. **GitHub Private Vulnerability Reporting**: Go to the [Security tab](https://github.com/luneth90/omamigrate/security/advisories/new) of this repository and click **"Report a vulnerability"**. This creates an encrypted private advisory draft visible only to project maintainers.
2. **Email Disclosure**: If private vulnerability reporting is unavailable, email security concerns directly to `luneth90@icloud.com` with the subject line `[SECURITY] OmaMigrate Vulnerability Report`.

### What to Include in a Report

To help us triage and verify the report efficiently, please include:
- A clear description of the vulnerability and its potential impact.
- Exact steps to reproduce, proof-of-concept scripts, or minimal test cases.
- Any affected components (e.g. `bin/omamigrate`, `lib/core.sh`, `lib/restore.sh`, `lib/export.sh`, `lib/scan-archives.sh`, or QML components).
- Proposed mitigations or fixes, if any.

### Response Timeline

- **Initial Acknowledgment**: Within 48 hours of receiving your disclosure.
- **Triage & Assessment**: Within 5 business days, confirming whether the report is reproducible and assessing severity.
- **Remediation & Patch**: A fix will be developed, reviewed, and tested against regression test suites.
- **Public Disclosure**: Coordinated advisory and release notes published once a patched version is available.
