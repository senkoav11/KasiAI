# KasiAI Firebase Cloud Function public invoker fix

This version adds `invoker: "public"` to the Gen 2 callable Cloud Function `analyzeCropImage`, so mobile apps can call the function while the Gemini API key remains protected in Firebase Secret Manager.

Deploy again after extracting:

```cmd
cd functions
npm install
cd ..
firebase deploy --only functions
```
