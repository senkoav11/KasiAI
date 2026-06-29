# KasiAI Firebase Cloud Gemini Setup

This version does not store the Gemini API key inside Flutter.

Flow:

```text
Flutter app -> Firebase Cloud Function -> Gemini API -> Cloud Function -> Flutter app
```

## 1. Install Firebase CLI

```cmd
npm install -g firebase-tools
firebase login
```

## 2. Install Cloud Functions dependencies

Run from project root:

```cmd
cd functions
npm install
cd ..
```

## 3. Save Gemini API key to Firebase Secret Manager

Run from project root:

```cmd
firebase functions:secrets:set GEMINI_API_KEY
```

Paste your real Gemini API key when it asks.

## 4. Deploy the Cloud Function

```cmd
firebase deploy --only functions
```

The function is deployed in this region:

```text
asia-southeast1
```

The Flutter app calls the same region automatically.

## 5. Run Flutter app

No `--dart-define` is needed anymore.

```cmd
flutter clean
flutter pub get
flutter run
```

For APK:

```cmd
flutter build apk --release
```

## Notes

- Users must be logged in before using AI Crop Doctor.
- Do not put the Gemini key inside Flutter source code.
- The Firebase project id in `.firebaserc` is `kasiai-33c68`.
- If you change Firebase project, update `.firebaserc` and rebuild app config files.
