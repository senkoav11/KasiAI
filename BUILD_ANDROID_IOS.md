# KasiAI — Build Android and iOS

This project is prepared for both Android and iOS.

## Android APK

Run on Windows or Mac:

```bash
flutter clean
flutter pub get
flutter build apk --release
```

APK output:

```text
build/app/outputs/flutter-apk/app-release.apk
```

## iOS on real iPhone

Run on MacBook only. Install Xcode first, then connect iPhone by USB and Trust This Computer.

```bash
flutter clean
flutter pub get
cd ios
pod install
cd ..
flutter devices
flutter run
```

If signing fails:

```bash
open ios/Runner.xcworkspace
```

Then in Xcode:

```text
Runner > Signing & Capabilities
Automatically manage signing: ON
Team: choose your Apple ID
Bundle Identifier: com.sen.kasiai
```

## iOS IPA

```bash
flutter build ipa
```

IPA output:

```text
build/ios/ipa/*.ipa
```
