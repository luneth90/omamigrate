# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |

## Security Considerations

OmaMigrate is designed to handle sensitive user data, including:
- Private SSH keys (`~/.ssh`)
- GPG encryption keys (`~/.gnupg`)
- Unix password stores (`~/.password-store`)
- AI CLI sessions and OAuth tokens

### Best Practices for Users
1. **Never upload the generated `omarchy-migration.tar.gz` archive to public repositories or public cloud storage.**
2. Use **LocalSend** or encrypted point-to-point transfers (`scp`, local physical USB drive) for transferring migration bundles across machines.
3. Delete temporary restoration staging directories (`~/omarchy-restore` or `/tmp/omamigrate-*`) once migration is complete.

## Reporting a Vulnerability

If you discover a security vulnerability within OmaMigrate, please open a private security advisory on GitHub or contact the maintainers directly. Do not report security vulnerabilities via public GitHub issues.
