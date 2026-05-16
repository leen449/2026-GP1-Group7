# CrashLens  
### AI-Powered Vehicle Accident Damage Assessment System

---

<img src='https://img.freepik.com/premium-photo/car-crash-accident-road_293060-1.jpg' alt='car crashed' width='1000/'>

<br>
<h2> Project Overview</h2>

CrashLens is a mobile-based intelligent accident assessment system that uses
Artificial Intelligence and Computer Vision to analyze vehicle damage caused by
accidents.

The system aims to support drivers and insurance companies by providing faster,
more consistent, and automated damage severity classification and repair cost
estimation.

CrashLens contributes to improving accident response efficiency and aligns with
Saudi Vision 2030 goals for smart digital transformation.

---

## Project Goals

CrashLens is designed to:

- Classify vehicle damage severity (Minor, Moderate, Severe)
- Provide an approximate repair cost estimation
- Generate structured accident assessment reports
- Support administrators in reviewing accident cases and resolving disputes
- Reduce subjectivity and delays in traditional manual inspection processes

---

## Technologies Used

The project will be developed using the following technologies:

- **Flutter** – Mobile application development  
- **Firebase** – Authentication and cloud storage  
- **Python** – Backend and machine learning development  
- **CNN Models** – Vehicle damage severity prediction
- **YOLOv8** – Damage detection model 
- **FastAPI** – AI inference service integration
- **EasyOCR** – Data extraction and deep-learning-based optical character recognition
- **Google Colab** – Model training and experimentation  

---

## Repository Structure

This repository is organized as follows:

```text
2026-GP1-Group7/
├── docs/                   # All reports & documentation
│   ├── proposal/
│   ├── sprint0/
│   └── sprint2/
├── mobile_app/             # Flutter frontend
│   ├── lib/                # Flutter source code (screens, widgets, etc.)
│   └── assets/             # App assets used by Flutter (icons, images)
├── backend_api/            # Backend services (FastAPI / Flask)
│   ├── routes/
│   ├── models/
│   └── services/
├── ml_model/
│   ├── training/           # Notebooks & training scripts
│   └── weights/            # Saved models 
├── AUTHORS.md
└── README.md
```
---

## Launch Instructions
### 📱 Mobile Application (Flutter)

cd mobile_app
flutter pub get
flutter run

> Ensure a physical device or emulator is connected.



### 🔧 Backend API (FastAPI)

cd backend_api  
pip install -r requirements.txt  
uvicorn main:app --reload  

> The backend currently runs on a local IP address.  
> Make sure the mobile app is configured to use the correct IP.


### ☁️ Firebase Configuration

- Firebase is fully integrated for authentication, Firestore, and storage.
- The Firebase configuration file (google-services.json) is stored locally and excluded from the repository via `.gitignore`.



### 🤖 Machine Learning Model

- The damage detection model was trained using YOLOv8.
- Model training and experimentation were conducted using Google Colab.
- The trained weights are stored under the ml_model/weights/ directory.
- The model is integrated with the backend inference service.
- The backend receives vehicle damage images and returns damage detection results to the mobile application.



## Sprint Information

- **Sprint 0:**
  - Project setup and planning
  - System architecture and requirements
  - Initial repository structure

- **Sprint 1:**
  - Mobile application core implementation
  - Firebase integration (Authentication, Firestore, Storage)
  - User account management
  - Vehicle management (manual entry + OCR-based extraction)
  - Accident case submission workflow
  - Najm report upload and OCR-based verification

- **Sprint 2:**
  - Guided image capture for vehicle damage documentation
  - Damage image upload
  - Damage detection model development
  - Integration of the damage detection model with the FastAPI backend
  - Integration between the mobile application and backend inference service
  - Display of damage detection results in the mobile application
  - UI/UX improvements and system stability enhancements

- **Upcoming:**
  -Damage severity classification
  - Repair cost estimation
  - Full report generation
  - QR-based report verification
  - Admin dashboard completion
  - Case history implementation
  - Objection submission and tracking
---











