# Firebase Cloud Gemini HTTP Function Fix

This version uses a normal HTTPS Cloud Function instead of Firebase Callable Function for AI Crop Doctor.

Why:
- The app showed `AI Cloud error unauthenticated: UNAUTHENTICATED` before the function body ran.
- This usually means the Cloud Run/Gen 2 callable endpoint is protected by the Invoker IAM check.
- The new Flutter client uses an HTTP endpoint:
  `https://asia-southeast1-kasiai-33c68.cloudfunctions.net/analyzeCropImageHttp`
- Gemini API key is still stored in Firebase Secret Manager only.

Deploy:

```cmd
cd functions
npm install
cd ..
firebase deploy --only functions
```

If it still returns 401/UNAUTHENTICATED, open Google Cloud Console > Cloud Run > analyzeCropImageHttp > Security and set Allow public access, or grant `allUsers` role `Cloud Run Invoker` on that service.
