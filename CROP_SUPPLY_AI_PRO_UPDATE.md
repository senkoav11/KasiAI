# KasiAI Crop Supply Predictor Pro Update

This version upgrades Crop Supply Predictor from simple Firestore aggregation to Cloud AI-assisted prediction.

## What changed

- Added Firebase Cloud Function: `predictSupplyHttp`
- Flutter app calls the Cloud Function from Crop Supply Predictor
- Gemini API key remains in Firebase Secret Manager only
- AI prediction uses collected Firestore data:
  - `planting_records`
  - `product_listings`
  - `buying_demands`
  - `deals`
- Prediction result is saved to `supply_predictions`
- UI shows AI Supply Intelligence card with:
  - predicted supply
  - listed supply
  - buyer demand
  - deal quantity
  - net balance
  - risk level
  - confidence
  - market signal
  - recommendation
  - action plan
  - price strategy
  - data quality note

## Deploy Cloud Function

```cmd
cd functions
npm install
cd ..
firebase deploy --only functions
```

## Run app

```cmd
flutter clean
flutter pub get
flutter run
```

## GitHub/Codemagic

This version can be pushed to GitHub because no Gemini API key is inside Flutter source code.
