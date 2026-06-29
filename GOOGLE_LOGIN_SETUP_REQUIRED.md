# Google Login setup required

If Google Login shows this error:

```text
PlatformException(sign_in_failed, com.google.android.gms.common.api.ApiException: 10: , null, null)
```

The app code is okay, but Firebase is missing the Android SHA certificate fingerprint.

## Fix on Windows

Open Terminal in the project root:

```powershell
cd android
.\gradlew signingReport
```

Copy the `SHA1` and `SHA-256` values from the `debug` variant.

Then go to Firebase Console:

```text
Project settings → General → Your apps → Android app com.sen.kasiai → Add fingerprint
```

Paste SHA-1 and SHA-256, save, then download a new:

```text
google-services.json
```

Put it here:

```text
android/app/google-services.json
```

Then run:

```powershell
flutter clean
flutter pub get
flutter build apk --release
```

## Release APK note

For release builds, you also need to add the release SHA-1/SHA-256 if you sign the APK with a release key.

## iOS note

For iOS Google Sign-In, make sure Firebase iOS app uses the same bundle ID:

```text
com.sen.kasiai
```

and `GoogleService-Info.plist` is in:

```text
ios/Runner/GoogleService-Info.plist
```
