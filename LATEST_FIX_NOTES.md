# KasiAI latest fix

Changes in this package:

- AI Crop Doctor now calls Firebase Cloud Functions instead of calling Gemini directly from Flutter.
- Gemini API key is stored in Firebase Secret Manager as `GEMINI_API_KEY`.
- Flutter source code does not contain the Gemini API key.
- Added `functions/` backend with `analyzeCropImage` callable function.
- Added `FIREBASE_CLOUD_GEMINI_SETUP.md` setup guide.
- Codemagic no longer needs `--dart-define=GEMINI_API_KEY`.
- Version updated to `1.0.8+9`.

Deploy functions first:

```cmd
firebase functions:secrets:set GEMINI_API_KEY
firebase deploy --only functions
```

Then build app normally.
