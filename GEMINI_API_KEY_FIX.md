# Gemini API key location

Gemini API key is now stored in Firebase Secret Manager and used by Cloud Functions.
The Flutter app no longer contains the real key.

Use:

```cmd
firebase functions:secrets:set GEMINI_API_KEY
firebase deploy --only functions
```

Then build normally:

```cmd
flutter build apk --release
```
