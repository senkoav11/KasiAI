# KasiAI Firebase Login + Firestore Supply Predictor

This version adds Firebase Authentication and Firestore for real Crop Supply Predictor data.

## Run

```bash
flutter clean
flutter pub get
flutter run
```

## Included Firebase files

- android/app/google-services.json
- ios/Runner/GoogleService-Info.plist

## Firebase collections

- users
- planting_records

## Test flow

1. Open app
2. Register account with email/password
3. Go to Crop Supply Predictor
4. Add planting record
5. Check Firestore Console > planting_records
6. Log in with another account to test user separation

## Notes

Firestore is currently in test mode. Change rules before production.
