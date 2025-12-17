# Firebase Deployment Guide for DreamWeaver

This document explains the Firebase configuration files and how to deploy them.

## 📋 Configuration Files Generated

### 1. `firestore.indexes.json`
Defines composite indexes required for complex Firestore queries:

- **dreams collection:**
  - `ownerId` + `dreamDate` (desc) - For user's dream timeline
  - `ownerId` + `tags` (array-contains) + `dreamDate` (desc) - For tag-based search
  - `ownerId` + `metadata.source` + `dreamDate` (desc) - For prompt-based streak calculation

- **prompts collection:**
  - `date` (desc) + `createdAt` (desc) - For latest prompt retrieval

- **dream_analyses collection:**
  - `ownerId` + `createdAt` (desc) - For analysis history

### 2. `firestore.rules`
Security rules protecting your Firestore data:

- **users collection:** Private - users can only read/write their own profile
- **users/{uid}/analytics:** Private - users can only access their own analytics events
- **dreams collection:** Private - users can only read/write their own dreams
- **dream_analyses collection:** Private - users can only access their own analyses
- **prompts collection:** Public read, admin write (Cloud Functions use admin SDK)

### 3. `storage.rules`
Security rules for Firebase Storage:

- **users/{userId}/profile/*:** User profile images
- **dreams/{userId}/{dreamId}/*:** Dream-related media files
- **generated/{userId}/videos/*:** Generated video files
- **generated/{userId}/images/*:** Generated image files
- **audio/{userId}/*:** Audio recordings

All storage paths are private to the owner (authenticated users only).

### 4. `firebase.json`
Main Firebase configuration file linking all components:
- Firestore rules and indexes
- Cloud Functions configuration
- Storage rules

## 🚀 Deployment Steps

### Deploy via Firebase Panel (Recommended)

1. **Open the Firebase Panel** in Dreamflow (left sidebar)
2. **Ensure you're connected** to your Firebase project
3. **Click "Deploy"** - This will deploy:
   - Firestore security rules
   - Firestore indexes
   - Storage security rules
   - Cloud Functions (if any changes)

### Monitor Deployment Status

After deployment:
1. **Check deployment status** in the Firebase panel
2. **Wait for indexes to build** - This can take a few minutes
3. **Verify in Firebase Console:**
   - Rules: https://console.firebase.google.com/project/getd88s74dzbyvweuc5nio1u3fyjuc/firestore/rules
   - Indexes: https://console.firebase.google.com/project/getd88s74dzbyvweuc5nio1u3fyjuc/firestore/indexes
   - Storage: https://console.firebase.google.com/project/getd88s74dzbyvweuc5nio1u3fyjuc/storage/rules

## 🔐 Authentication Setup

**IMPORTANT:** Enable authentication providers in Firebase Console:

1. Visit: https://console.firebase.google.com/u/0/project/getd88s74dzbyvweuc5nio1u3fyjuc/authentication/providers
2. Enable the following providers:
   - ✅ Email/Password
   - ✅ Google (for Google Sign-In)
   - ✅ Anonymous (optional, for guest access)

## 📊 Collections Structure

Your app uses the following Firestore collections:

### `/users/{userId}`
User profiles with subscription status, preferences, and usage tracking.

### `/users/{userId}/analytics/{eventId}`
User-specific analytics events (dream_logged, video_generated, etc.)

### `/dreams/{dreamId}`
Dream entries with metadata, analysis, and visual generation status.

### `/prompts/{promptId}`
Daily prompts (managed by Cloud Functions).

### `/dream_analyses/{analysisId}` (if used)
Detailed dream analysis records.

## 🔍 Troubleshooting

### Index Errors
If you see "The query requires an index" errors:
1. Check the error message for the missing index link
2. Click the link to create the index in Firebase Console
3. Wait for the index to build (usually 2-5 minutes)
4. Retry the operation

### Permission Denied Errors
If you see "Missing or insufficient permissions" errors:
1. Verify rules are deployed via Firebase panel
2. Check user is authenticated (signed in)
3. Verify the query matches security rule conditions (e.g., filtering by ownerId)

### Storage Upload Failures
If file uploads fail:
1. Check storage rules are deployed
2. Verify user is authenticated
3. Ensure file path matches the pattern in storage.rules

## 📝 Notes

- Cloud Functions use the Firebase Admin SDK, which bypasses security rules
- All queries in the codebase are designed to match the security rules
- Indexes are optimized for the specific queries used in the app
- Storage paths follow a user-centric structure for privacy and organization

## 🎯 Next Steps

After deployment:
1. ✅ Test authentication flows (email, Google, anonymous)
2. ✅ Create a test dream entry
3. ✅ Verify analytics events are logged
4. ✅ Test daily prompt generation
5. ✅ Upload test media files to Storage
6. ✅ Monitor Firebase Console for any errors
