# Google Cloud Console Setup Guide

This guide walks you through creating OAuth credentials for sheetsync.

## Prerequisites

- A Google account
- Access to [Google Cloud Console](https://console.cloud.google.com/)

## Step 1: Create a Google Cloud Project

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Click the project dropdown at the top of the page
3. Click **"New Project"**
4. Enter project details:
   - **Project name:** `sheetsync` (or any name you prefer)
   - **Organization:** Leave as default
5. Click **"Create"**
6. Wait for the project to be created, then select it from the dropdown

## Step 2: Enable Required APIs

1. Go to **"APIs & Services"** → **"Library"** (in the left sidebar)
2. Search for and enable each of these APIs:

### Google Sheets API
1. Search for "Google Sheets API"
2. Click on it
3. Click **"Enable"**

### Google Drive API
1. Search for "Google Drive API"
2. Click on it
3. Click **"Enable"**

## Step 3: Configure OAuth Consent Screen

1. Go to **"APIs & Services"** → **"OAuth consent screen"**
2. Select **"External"** (unless you have a Google Workspace organization)
3. Click **"Create"**
4. Fill in the required fields:

### App Information
- **App name:** `sheetsync`
- **User support email:** Your email address
- **App logo:** (Optional)

### App Domain
- Leave these fields empty for personal use

### Developer Contact Information
- **Email addresses:** Your email address

5. Click **"Save and Continue"**

### Scopes
1. Click **"Add or Remove Scopes"**
2. Add these scopes:
   - `https://www.googleapis.com/auth/spreadsheets` - See, edit, create, and delete all your Google Sheets spreadsheets
   - `https://www.googleapis.com/auth/drive.readonly` - See and download all your Google Drive files
   - `https://www.googleapis.com/auth/userinfo.email` - See your primary Google Account email address
3. Click **"Update"**
4. Click **"Save and Continue"**

### Test Users
1. Click **"Add Users"**
2. Enter your Google account email address
3. Click **"Add"**
4. Click **"Save and Continue"**

### Summary
1. Review your settings
2. Click **"Back to Dashboard"**

> **Note:** Your app will be in "Testing" mode, which is fine for personal use. Only the email addresses you added as test users will be able to authenticate.

## Step 4: Create OAuth Credentials

1. Go to **"APIs & Services"** → **"Credentials"**
2. Click **"Create Credentials"** → **"OAuth client ID"**
3. Configure the OAuth client:
   - **Application type:** `Desktop app`
   - **Name:** `sheetsync macOS`
4. Click **"Create"**
5. A dialog will show your credentials:
   - **Client ID:** Copy this (looks like: `123456789-xxxx.apps.googleusercontent.com`)
   - **Client Secret:** Not needed for this app (PKCE flow)
6. Click **"OK"**

## Step 5: Configure the App

1. Copy the example secrets file:
   ```bash
   cp SheetSync/Config/Secrets.example.txt SheetSync/Config/Secrets.swift
   ```

2. Edit `SheetSync/Config/Secrets.swift`:
   ```swift
   enum Secrets {
       static let googleClientId = "YOUR_CLIENT_ID_HERE.apps.googleusercontent.com"
       static let googleRedirectScheme = "com.sheetsync.app"
   }
   ```

3. Replace `YOUR_CLIENT_ID_HERE` with your actual Client ID

## Verification

After setup, you should be able to:
1. Build and run the app
2. Click "Sign in with Google"
3. Complete the OAuth flow in your browser
4. See your email in the app's menu

## Troubleshooting

### "Access blocked" error
- Make sure you added your email as a test user
- Wait a few minutes after adding test users

### "Invalid client" error
- Verify the Client ID is correct in `Secrets.swift`
- Make sure you're using a Desktop app credential, not Web or iOS

### "Scope not authorized" error
- Go back to OAuth consent screen
- Add the missing scopes
- Re-authenticate in the app

### "API not enabled" error
- Go to APIs & Services → Library
- Verify both Google Sheets API and Google Drive API are enabled

## For Public Distribution

If you want to distribute this app publicly:

1. Go to **"OAuth consent screen"**
2. Click **"Publish App"**
3. Complete Google's verification process (requires privacy policy, etc.)

For personal use, keeping the app in "Testing" mode is sufficient.

## Security Notes

- Never commit `Secrets.swift` to version control
- The `.gitignore` file is configured to exclude it
- Each user should create their own Google Cloud project and credentials
- The app uses PKCE flow, so no client secret is needed or stored
