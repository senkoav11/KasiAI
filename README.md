# KasiAI / កសិAI

Flutter MVP app for **KhmerFarm Link AI**.

## What is new in this version

This version connects the AI Crop Doctor screen to a real backend:

- Flutter image upload with `image_picker`
- HTTP multipart upload to FastAPI
- FastAPI `/predict` endpoint
- TensorFlow/Keras model loader
- MobileNetV2 training script
- Khmer disease recommendation mapping

## Run Flutter app

```bash
flutter clean
flutter pub get
flutter run
```

## Run AI service

Go to:

```text
ai_service/README_AI_SETUP.md
```

Default emulator predict URL inside the app:

```text
http://10.0.2.2:8000/predict
```

## Important

The app is AI-backend-ready. You need to train or add this model file before prediction works:

```text
ai_service/model/crop_disease_model.keras
```

Use the included `ai_service/train_model.py` to train a real TensorFlow model from your dataset.


## Roboflow AI Mode

This project is configured for Option 1: Flutter -> FastAPI proxy -> Roboflow Hosted AI API.

Setup:

```bash
cd ai_service
python -m venv .venv
.venv\Scriptsctivate
pip install -r requirements.txt
copy .env.example .env
# edit .env and add ROBOFLOW_API_URL + ROBOFLOW_API_KEY
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

Flutter emulator AI URL:

```text
http://10.0.2.2:8000/predict
```

## Smart Marketplace Pro update

This version adds real marketplace functions: owner CRUD, product photos, public profile view, likes, comments, notifications, deal chat, completed deal hiding, and pagination.
