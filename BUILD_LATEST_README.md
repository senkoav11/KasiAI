# KasiAI Latest Clean Build

This project is prepared for GitHub + Codemagic and Firebase Cloud Functions.

Important:
- No `.git` history
- No `build/`
- No `.dart_tool/`
- Gemini key is not stored in Flutter source code
- Gemini key is stored in Firebase Secret Manager and used by Cloud Functions
- App version is `1.0.8+9`

## Push to GitHub

```cmd
git init
git branch -M main
git remote add origin https://github.com/senkoav11/KasiAI.git
git add .
git commit -m "upload KasiAI with Firebase Cloud Gemini"
git push -u origin main --force
```

## Deploy Cloud Functions first

```cmd
npm install -g firebase-tools
firebase login
cd functions
npm install
cd ..
firebase functions:secrets:set GEMINI_API_KEY
firebase deploy --only functions
```

## Codemagic

Start a new build and choose:

- `iOS Unsigned Build (free route)` for IPA
- `Android APK Build` for APK

No Codemagic Gemini secret or `--dart-define` is required now because the app calls Firebase Cloud Functions.
