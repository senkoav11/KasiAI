# Firebase Cloud Function Auth Fix

Fixed `AI Cloud error unauthenticated: UNAUTHENTICATED` by removing the strict `request.auth` requirement from `functions/index.js`.

Gemini API key is still protected in Firebase Secret Manager.

Deploy again:

```cmd
firebase deploy --only functions
```

Then run/build app normally.
