# GSheet Sync

A minimalist macOS menu bar app that syncs Google Sheets to local Excel files.

## Features

- **Menu Bar Only** - Lives in your menu bar, no dock icon clutter
- **Bidirectional Sync** - Changes flow both ways between Google Sheets and local files
- **Cell-by-Cell Updates** - Only changed cells are updated, not full sheet rewrites
- **Automatic Backups** - Configurable backups every 5 hours (or custom interval)
- **Conflict Resolution** - Conflicts are appended, never overwritten
- **Launch at Login** - Optional auto-start when you log in
- **Multiple Formats** - Supports XLSX (Excel), CSV, and JSON

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15+ (for building)
- Google account

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/yourusername/gsheet-sync.git
cd gsheet-sync
```

### 2. Create Google OAuth Credentials

See [docs/GOOGLE_SETUP.md](docs/GOOGLE_SETUP.md) for detailed instructions with screenshots.

**Quick version:**
1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project
3. Enable Google Sheets API and Google Drive API
4. Create OAuth 2.0 Desktop credentials
5. Copy the Client ID

### 3. Configure Secrets

```bash
cp GSheetSync/Config/Secrets.example.txt GSheetSync/Config/Secrets.swift
```

Edit `GSheetSync/Config/Secrets.swift` and replace `YOUR_CLIENT_ID` with your actual Client ID:

```swift
enum Secrets {
    static let googleClientId = "123456789-xxxx.apps.googleusercontent.com"
    static let googleRedirectScheme = "com.gsheetsync.app"
}
```

### 4. Build and Run

**Using Xcode:**
```bash
open Package.swift
# Or: xed .
```
Then press Cmd+R to build and run.

**Using Command Line:**
```bash
./build.sh
open build/GSheetSync.app
```

This creates a proper macOS app bundle in `build/GSheetSync.app`.

## Usage

1. **Click the menu bar icon** (sync arrows)
2. **Sign in with Google** when prompted
3. **Click "+"** to add a new sync
4. **Select a Google Sheet** from your Drive
5. **Choose sheet tabs** to sync (or leave empty for all)
6. **Pick a local folder** to save the file
7. **Done!** Syncs automatically every 30 seconds (configurable)

## How It Works

### Sync Process

1. **Fetch** - Downloads current state from Google Sheets
2. **Compare** - Detects changes using SHA256 hashes of each cell
3. **Merge** - Combines local and remote changes
4. **Resolve** - Handles conflicts (append strategy)
5. **Update** - Pushes changes to both local file and Google Sheets

### Conflict Resolution

When the same cell is modified both locally and in Google Sheets:
- Your local change is kept in place
- The Google Sheets version is appended as a new row with a conflict marker
- Format: `[CONFLICT - Google - timestamp] | values...`

You manually review and resolve conflicts by editing the file.

### Backup System

- **Location:** `~/Library/Application Support/GSheetSync/backups/`
- **Frequency:** Every 5 hours (configurable), only if changes detected
- **Format:** Same as your sync file (XLSX/CSV/JSON)
- **Cache Limit:** 10GB default, configurable

## Configuration

### Sync Settings (per sheet)
- Sync frequency: 10s to 1 hour
- File format: XLSX, CSV, or JSON
- Specific tabs or all tabs
- Custom file name
- Backup settings

### Global Settings
- Launch at login
- Show notifications
- Default sync frequency
- Default file format
- Backup cache limit

## File Formats

| Format | Pros | Cons |
|--------|------|------|
| **XLSX** (default) | Preserves formatting, multiple tabs | Larger file size |
| **CSV** | Universal, small size | Single tab only, no formatting |
| **JSON** | Multiple tabs, programmable | Not spreadsheet-native |

## Rate Limiting

The app respects Google's API quotas:
- **Reads:** Max 250/minute (conservative: 50 used)
- **Writes:** Max 50/minute (conservative: 25 used)
- **Backoff:** Exponential (1s → 2s → 4s → max 64s)

If rate limited, the app waits automatically and retries.

## Troubleshooting

### "Not signed in" error
- Sign out and sign in again
- Check if your Google OAuth credentials are valid
- Verify the app is authorized in your Google account settings

### Sync not working
- Check your internet connection
- Verify the Google Sheet still exists and you have access
- Check the local file path is writable

### "Permission denied" error
- Re-authorize the app in Google account settings
- Ensure you've added your email as a test user (if app is in testing mode)

### Build errors
- Ensure Xcode 15+ is installed
- Run `swift package resolve` to fetch dependencies
- Check that `Secrets.swift` exists (not `Secrets.example.swift`)

## Development

### Project Structure

```
GSheetSync/
├── App/                    # App entry point, AppDelegate
├── Core/
│   ├── Models/            # Data models
│   ├── Services/
│   │   ├── Auth/          # Google OAuth
│   │   ├── GoogleSheets/  # API client
│   │   ├── Sync/          # Sync engine
│   │   ├── FileSystem/    # Local file handling
│   │   └── Backup/        # Backup management
│   └── Utilities/         # Logger, notifications
├── UI/
│   ├── MenuBar/           # Menu bar icon
│   ├── Views/             # SwiftUI views
│   └── Components/        # Reusable components
├── Config/                # Secrets (gitignored)
└── Resources/             # Assets
```

### Key Files

- `GSheetSyncApp.swift` - App entry point
- `SyncEngine.swift` - Main sync orchestrator
- `GoogleAuthService.swift` - OAuth handling
- `GoogleSheetsAPIClient.swift` - API wrapper
- `MainPopoverView.swift` - Primary UI

### Dependencies

- **CoreXLSX** - Reading/writing Excel files
- Native frameworks: SwiftUI, AppKit, AuthenticationServices, CryptoKit

## License

MIT License - see [LICENSE](LICENSE)

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## Acknowledgments

- [CoreXLSX](https://github.com/CoreOffice/CoreXLSX) for Excel file support
- Google Sheets API documentation
