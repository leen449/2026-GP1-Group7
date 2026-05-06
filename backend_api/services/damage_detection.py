import os
import cv2
import tempfile
import requests
import uuid
from ultralytics import YOLO
import firebase_admin
from firebase_admin import firestore, credentials, storage
import urllib.parse

# [1] Load model ONCE 
model = YOLO("../ml_model/weight/best.pt")

def _ensure_firebase_initialized():
    # [2] Reusing the exact same initialization logic 
    if not firebase_admin._apps:
        try:
            cred = credentials.Certificate("serviceAccountKey.json")
            firebase_admin.initialize_app(cred, {
                'storageBucket': 'crashlens-233bf.firebasestorage.app'
            })
            print("✅ Firebase Admin initialized in damage_services")
        except Exception as e:
            print(f"❌ Firebase Admin initialization failed: {e}")
            raise

async def process_damage_detection(case_id: str) -> dict:
    try:
        print(f"--- DAMAGE DETECTION REQUEST: {case_id} ---")
        _ensure_firebase_initialized()
        db = firestore.client()
        
        # [3] Connect to the case in Firestore
        case_ref = db.collection("accidentCase").document(case_id)
        case_doc = case_ref.get()
        
        if not case_doc.exists:
            return {"status": "error", "message": f"Case {case_id} not found"}

        # [4] Get the images subcollection
        images_ref = case_ref.collection("images").stream()
        results = []
        bucket = storage.bucket('crashlens-233bf.firebasestorage.app')

        # [5] Process EACH image
        for img_doc in images_ref:
            img_data = img_doc.to_dict()
            image_url = img_data.get("downloadUrl")
            
            # [6] If there's no URL, skip this image
            if not image_url:
                continue

            temp_path = None
            annotated_img_path = None
            
            try:
                # [7] Create temp file and download image 
                with tempfile.NamedTemporaryFile(delete=False, suffix=".jpg") as tmp:
                    temp_path = tmp.name
                
                path_part = image_url.split('/o/')[1].split('?')[0]
                storage_path = urllib.parse.unquote(path_part)
                image_blob = bucket.blob(storage_path)
                image_blob.download_to_filename(temp_path)

                # [8] Run YOLO
                yolo_results = model(temp_path)
                
                for r in yolo_results:
                    
                    # [9] Evaluate if there is any damage using our new flag
                    has_damage = len(r.boxes) > 0
                    
                    # [10] The "No Damage" Path
                    if not has_damage:
                        img_doc.reference.update({
                            "annotatedImage": None,
                            "hasDamage": False,
                        })
                        results.append({
                            "originalImage": image_url,
                            "hasDamage": False,
                            "detections": []
                        })
                        continue

                    # [11] The "Damage Detected" Path
                    detections = []
                    for box in r.boxes:
                        cls_id = int(box.cls[0])
                        confidence = float(box.conf[0])
                        x1, y1, x2, y2 = box.xyxy[0].tolist()

                        detections.append({
                            "label": model.names[cls_id],
                            "confidence": round(confidence, 2),
                            "x1": round(x1, 2), "y1": round(y1, 2),
                            "x2": round(x2, 2), "y2": round(y2, 2)
                        })

                    # [12] Generate and upload annotated image
                    annotated_frame = r.plot()
                    annotated_img_path = os.path.join(tempfile.gettempdir(), f"annotated_{uuid.uuid4()}.jpg")
                    cv2.imwrite(annotated_img_path, annotated_frame)

                    blob = bucket.blob(f"accidentCases/{case_id}/annotated_{uuid.uuid4()}.jpg")
                    blob.upload_from_filename(annotated_img_path)
                    blob.make_public()
                    annotated_url = blob.public_url

                    # [13] Update the image document with the annotated image URL
                    img_doc.reference.update({
                        "annotatedImage": annotated_url,
                        "hasDamage": True,
                    })

                    # [14] Save each detection as a separate document in the detections subcollection
                    
                    for detection in detections:
                        img_doc.reference.collection("detections").add({
                            "label": detection["label"],
                            "confidence": detection["confidence"],
                            "x1": detection["x1"],
                            "y1": detection["y1"],
                            "x2": detection["x2"],
                            "y2": detection["y2"],
                            
                        })

                    results.append({
                        "originalImage": image_url,
                        "annotatedImage": annotated_url,
                        "hasDamage": True,
                        "detections": detections
                    })

            finally:
                # [15] Cleanup temp files
                if temp_path and os.path.exists(temp_path):
                    os.remove(temp_path)
                if annotated_img_path and os.path.exists(annotated_img_path):
                    os.remove(annotated_img_path)

        # [16] Update case status after ALL images have been processed
        case_ref.update({"status": "تم الفحص"})

        return {"status": "success", "data": results}

    except Exception as e:
        error_message = f"Damage Detection Error: {str(e)}"
        print(f"!!! {error_message}")
        
        # [17] Update case to reflect the error
        try:
            _ensure_firebase_initialized()
            db = firestore.client()
            db.collection("accidentCase").document(case_id).update({
                "status": "فشل الفحص",
                "detectionError": error_message
            })
        except Exception as update_error:
            print(f"❌ Failed to update case status after Detection exception: {update_error}")

        return {"status": "error", "message": error_message}