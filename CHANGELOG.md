# Changelog

All notable changes to SheetSync will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-01-31

### Added
- Initial release of SheetSync
- Menu bar app for syncing Google Sheets to local files
- Bidirectional sync between Google Sheets and local Excel/CSV/JSON files
- Cell-by-cell change detection using SHA256 hashing
- Automatic conflict resolution (remote wins, local backed up)
- Configurable sync intervals (10s to 1 hour)
- Automatic backups every 5 hours (configurable)
- Multiple file format support (XLSX, CSV, JSON)
- Launch at login option
- Rate limiting and exponential backoff for Google API
- Backup browser with restore and export capabilities
- OAuth 2.0 authentication with Google

### Fixed
- Build compatibility with macOS 14 (Sonoma)
- Replaced future macOS 26 APIs with macOS 14 compatible alternatives

## [Unreleased]

### Planned
- App signing and notarization
- Automatic updates via Sparkle framework
- Multiple Google account support
- Custom sync rules and filters
- Notification preferences per sync

[1.0.0]: https://github.com/yourusername/sheetsync/releases/tag/v1.0.0
