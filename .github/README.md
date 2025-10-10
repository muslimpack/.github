# Flutter Release Workflow - User Guide

This guide explains how to set up and use the reusable Flutter release workflow for your projects.

## 📋 Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Initial Setup](#initial-setup)
- [Adding to a New Project](#adding-to-a-new-project)
- [Creating a Release](#creating-a-release)
- [Troubleshooting](#troubleshooting)

---

## Overview

This workflow automates the build and release process for Flutter applications:

- ✅ Builds Android APK and AAB (App Bundle)
- ✅ Builds Windows executable
- ✅ Uploads to Google Play Store (production track)
- ✅ Creates GitHub Release with all artifacts
- ✅ Handles debug symbols and ProGuard mapping files

## Prerequisites

Before setting up the workflow, you need:

1. **Flutter project** with the following structure:
   ```
   your-repo/
   ├── .github/
   │   └── workflows/
   │       └── release.yml
   ├── your-app-name/          # Flutter app directory
   │   ├── .fvmrc              # Flutter version config
   │   ├── pubspec.yaml
   │   └── android/
   ├── distribution/
   │   └── whatsnew/           # Google Play release notes
   └── CHANGELOG.md
   ```

2. **Android keystore** for signing releases
3. **Google Play Service Account** JSON for automated uploads
4. **GitHub repository secrets** (see setup below)

---

## Initial Setup

### Step 1: Prepare Your Secrets

You need to add the following secrets to your GitHub repository:

#### Go to: `Repository Settings` → `Secrets and variables` → `Actions` → `New repository secret`

#### 1. **KEY_PROPERTIES**
Create a secret with all your Android signing properties:

```properties
keyAlias=your_key_alias
keyPassword=your_key_password
storePassword=your_store_password
```

**How to get these values:**
- These come from your Android keystore file
- If you don't have one, generate it using Android Studio or `keytool`

#### 2. **KEYSTORE_BASE64**
Your Android keystore file encoded in Base64:

```bash
# On Linux/Mac:
base64 -i your-keystore.jks | tr -d '\n'

# On Windows (PowerShell):
[Convert]::ToBase64String([IO.File]::ReadAllBytes("your-keystore.jks"))
```

Copy the entire output and paste it as the secret value.

#### 3. **SERVICE_ACCOUNT_JSON**
Google Play Service Account JSON (for automated Play Store uploads):

1. Go to [Google Play Console](https://play.google.com/console)
2. Navigate to: `Setup` → `API access`
3. Create or use existing service account
4. Download the JSON key file
5. Copy the **entire contents** of the JSON file and paste as the secret value

---

### Step 2: Create Flutter Version Config

In your Flutter app directory, create `.fvmrc`:

```json
{
  "flutter": "3.24.0"
}
```

Replace `3.24.0` with your desired Flutter version.

---

### Step 3: Prepare Release Notes

Create the directory structure for Google Play release notes:

```
distribution/
└── whatsnew/
    ├── whatsnew-ar-EG     # Arabic release notes
    ├── whatsnew-en-US     # English release notes
    └── whatsnew-xx-XX     # Other languages
```

Each file should contain the release notes for that language (max 500 characters).

---

## Adding to a New Project

### Step 1: Create the Workflow File

In your project repository, create `.github/workflows/release.yml`:

```yaml
name: Build and Release [Your App Name]

on:
  push:
    tags:
      - 'v*.*.*'

jobs:
  release:
    uses: muslimpack/.github/workflows/flutter_release.yaml@main
    with:
      app_directory: your-app-name
      package_name: com.yourcompany.yourapp
      java_version: '18'
    secrets:
      KEY_PROPERTIES: ${{ secrets.KEY_PROPERTIES }}
      KEYSTORE_BASE64: ${{ secrets.KEYSTORE_BASE64 }}
      SERVICE_ACCOUNT_JSON: ${{ secrets.SERVICE_ACCOUNT_JSON }}
```

### Step 2: Customize the Configuration

Update these values:

- `app_directory`: Name of your Flutter app directory (e.g., `hisnelmoslem`, `alazkar`, `qadaa`)
- `package_name`: Your Android package name (e.g., `com.hassaneltantawy.hisnelmoslem`)
- `java_version`: Java version to use (default: `'18'`)

### Step 3: Configure Android Flavor

Your `android/app/build.gradle` should have a `prod` flavor:

```gradle
android {
    flavorDimensions "default"
    productFlavors {
        prod {
            dimension "default"
            applicationId "com.yourcompany.yourapp"
        }
    }
}
```

---

## Creating a Release

### Step 1: Update Version

Update your app version in `pubspec.yaml`:

```yaml
version: 3.0.0+30  # version_name+version_code
```

### Step 2: Update CHANGELOG.md

Add release notes to your `CHANGELOG.md`:

```markdown
## [3.0.0] - 2024-01-15

### Added
- New feature X
- New feature Y

### Fixed
- Bug fix A
- Bug fix B
```

### Step 3: Create and Push Tag

```bash
# Create a git tag
git tag v3.0.0

# Push the tag to GitHub
git push origin v3.0.0
```

### Step 4: Monitor the Workflow

1. Go to your repository on GitHub
2. Click on `Actions` tab
3. Watch the workflow run
4. The workflow will:
   - Build Android APK and AAB
   - Build Windows executable
   - Upload to Google Play Store
   - Create GitHub Release with all artifacts

### Step 5: Verify Release

After the workflow completes:

1. **GitHub Release**: Check `Releases` tab for the new release
2. **Google Play**: Check [Google Play Console](https://play.google.com/console) → Your App → Production track

---

## Workflow Outputs

The workflow produces the following artifacts:

### GitHub Release Files:
- `yourapp_3.0.0_android.apk` - Direct download APK
- `yourapp_3.0.0_android.aab` - App Bundle
- `yourapp_3.0.0_windows.zip` - Windows executable

### Google Play:
- App Bundle uploaded to Production track
- ProGuard mapping files for crash reports
- Debug symbols for native code

---

## Troubleshooting

### Common Issues

#### 1. "Artifact not found" Error

**Problem:** Workflow can't find uploaded artifacts.

**Solution:** Ensure artifact names match between upload and download steps.

#### 2. "Version code already exists" on Google Play

**Problem:** Trying to upload the same version twice.

**Solution:** 
- Increment version code in `pubspec.yaml`
- Create a new tag (e.g., `v3.0.1`)
- Or delete the existing tag and fix issues before re-releasing

#### 3. "KEY_PROPERTIES not found"

**Problem:** Secret not properly configured.

**Solution:**
- Go to repository Settings → Secrets
- Verify `KEY_PROPERTIES` exists and has correct format
- Ensure no extra spaces or newlines

#### 4. Flutter version mismatch

**Problem:** Workflow uses wrong Flutter version.

**Solution:**
- Check `.fvmrc` file in your app directory
- Ensure it has valid JSON format
- Verify Flutter version exists

#### 5. Google Play upload fails

**Problem:** Service account doesn't have permissions.

**Solution:**
- Go to Google Play Console → Setup → API access
- Ensure service account has "Release to production" permission
- Verify JSON key is not expired

---

## Advanced Configuration

### Disable Google Play Upload

If you want to skip Google Play upload (for testing):

Comment out the Google Play upload step in the reusable workflow, or create a custom workflow without that step.

### Change Release Track

To release to a different track (internal/alpha/beta):

In the reusable workflow, change:
```yaml
track: production
```
to:
```yaml
track: internal  # or alpha, beta
```

### Add More Platforms

To add iOS or other platforms, extend the reusable workflow with additional jobs.

---

## Example Projects

- **HisnElmoslem**: [muslimpack/HisnElmoslem_App](https://github.com/muslimpack/HisnElmoslem_App)
- **Alazkar**: Similar setup with `app_directory: alazkar`
- **Qadaa**: Similar setup with `app_directory: qadaa`

---

## Support

If you encounter issues:

1. Check the Actions log for detailed error messages
2. Verify all secrets are properly configured
3. Ensure your project structure matches the expected format
4. Review this guide for missed steps

---

## Changelog

### Version 1.0
- Initial release with Android and Windows support
- Google Play integration
- GitHub Release creation
- Debug symbols handling