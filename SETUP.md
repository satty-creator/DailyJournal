# Quick Setup Guide

## Step-by-Step Instructions

### 1. Create Xcode Project

Since this is a Swift source code structure, you need to create the Xcode project:

1. Open Xcode
2. File → New → Project
3. Choose "iOS" → "App"
4. Fill in:
   - Product Name: `DailyJournal`
   - Team: Your team
   - Organization Identifier: `com.yourcompany`
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Storage: None
   - Minimum Deployments: **iOS 17.0**

5. Save to: `/Users/satty/workspace/journal/DailyJournal/`

### 2. Replace Default Files

Delete the default files Xcode created and copy the structure from this repo:
- Delete default `ContentView.swift`
- Delete default `DailyJournalApp.swift`
- Copy all files from this structure

### 3. Add Firebase Dependencies

1. In Xcode: File → Add Package Dependencies
2. Add these packages:

```
Firebase iOS SDK
https://github.com/firebase/firebase-ios-sdk.git
Version: 10.20.0 or newer
Select:
- FirebaseAuth
- FirebaseFirestore

GoogleSignIn iOS
https://github.com/google/GoogleSignIn-iOS.git
Version: 7.0.0 or newer
```

### 4. Firebase Console Setup

1. Go to https://console.firebase.google.com/
2. Create new project: "DailyJournal"
3. Add iOS app:
   - Bundle ID: `com.yourcompany.DailyJournal` (match your Xcode project)
   - Download `GoogleService-Info.plist`
   - Drag into Xcode project root (next to DailyJournalApp.swift)
   - Make sure "Copy items if needed" is checked

4. Enable Authentication:
   - Firebase Console → Build → Authentication → Get started
   - Enable "Email/Password"
   - Enable "Google"

5. Create Firestore Database:
   - Firebase Console → Build → Firestore Database → Create database
   - Start in **production mode**
   - Choose location (e.g., us-central)
   - Go to Rules tab
   - Copy contents from `firestore.rules` file
   - Publish

### 5. Configure Info.plist

Add URL scheme for Google Sign-In:

1. In Xcode, open `Info.plist`
2. Add new entry:
   - Key: `URL types` (array)
   - Item 0 (dictionary):
     - Key: `URL Schemes` (array)
       - Item 0 (string): Copy `REVERSED_CLIENT_ID` from `GoogleService-Info.plist`
       - (Looks like: `com.googleusercontent.apps.123456789`)

Or in XML:
```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>YOUR_REVERSED_CLIENT_ID_HERE</string>
        </array>
    </dict>
</array>
```

### 6. Build and Test

1. Select iPhone simulator (iOS 17+)
2. Press `Cmd + R`
3. App should compile and launch

### 7. Test Authentication

**Test Signup:**
1. Enter email and password
2. Tap "Create Account"
3. Should navigate to empty journal screen

**Test Google Sign-In:**
1. Tap "Continue with Google"
2. Select Google account
3. Grant permissions
4. Should navigate to journal screen

**Test Journaling:**
1. Tap + button
2. Enter content
3. Select mood
4. Add tags
5. Tap Save
6. Should see entry in list

### 8. Test Offline Mode

1. Write an entry
2. Enable Airplane Mode on simulator (or disconnect network)
3. Write another entry
4. Disable Airplane Mode
5. Entries should sync automatically

## Troubleshooting

### "FirebaseApp.configure() not found"
- Make sure Firebase package is added via SPM
- Clean build folder: `Cmd + Shift + K`

### "GoogleService-Info.plist not found"
- Download from Firebase Console
- Drag into Xcode (copy files)
- Verify it's in Build Phases → Copy Bundle Resources

### Google Sign-In fails
- Check URL scheme in Info.plist matches REVERSED_CLIENT_ID
- Verify Google provider is enabled in Firebase Console
- Check Firebase project is correctly configured

### Firestore permission denied
- Verify rules in Firestore Console
- Make sure user is authenticated
- Check userId matches in security rules

### Build errors
- Update to Xcode 15+
- Set deployment target to iOS 17+
- Clean derived data: `Cmd + Shift + Option + K`

## Next Steps

Once the app is working:

1. **Customize branding**
   - Change app icon
   - Update accent color in Assets
   - Modify theme in `AppTheme.swift`

2. **Test on device**
   - Connect iPhone
   - Set team in Signing & Capabilities
   - Build to device

3. **Deploy to TestFlight**
   - Archive the app
   - Upload to App Store Connect
   - Configure TestFlight testing

4. **Add features**
   - See roadmap in README.md
   - Start with Phase 2 features

Good luck building! 🚀