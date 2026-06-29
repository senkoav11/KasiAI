# KasiAI Firebase Advanced Version

This version adds:

- Email/Password login
- Google Sign-In button
- User Profile page with photo, phone, province and role
- Full Cambodia provinces list
- Extended common Cambodia crop list
- Firestore Crop Supply Predictor
- Firestore Smart Marketplace:
  - `product_listings`
  - `buying_demands`
  - `deals`

## Important Firebase setup

In Firebase Console enable:

1. Authentication → Sign-in method → Email/Password
2. Authentication → Sign-in method → Google
3. Cloud Firestore Database

## Android Google Sign-In

If Google login gives an error such as `ApiException: 10`, add your app SHA-1/SHA-256 in Firebase:

Project settings → Your Android app → SHA certificate fingerprints

Then download a new `google-services.json` and put it here:

`android/app/google-services.json`

## iOS Google Sign-In

Add your iOS app in Firebase and download:

`GoogleService-Info.plist`

Put it here:

`ios/Runner/GoogleService-Info.plist`

Then run on Mac:

```bash
flutter clean
flutter pub get
cd ios
pod install
cd ..
flutter run
```

## Firestore collections used

- `users`
- `planting_records`
- `product_listings`
- `buying_demands`
- `deals`

