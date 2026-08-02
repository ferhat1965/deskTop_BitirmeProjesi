import base64
import binascii
import io
import json
import logging
import os
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, List, Optional

import cv2
import numpy as np
from dotenv import load_dotenv
from fastapi import FastAPI, File, HTTPException, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from pydantic import BaseModel
from PIL import Image, ImageOps
from sqlmodel import Field, Session, SQLModel, col, create_engine, select

# TensorFlow Lite için
tflite = None
try:
    import tflite_runtime.interpreter as tflite  # pyright: ignore[reportMissingImports]
    TFLITE_AVAILABLE = True
except ImportError:
    TFLITE_AVAILABLE = False

# Ultralytics YOLOv8 için
YOLO = None
try:
    from ultralytics import YOLO
    YOLO_AVAILABLE = True
except ImportError:
    YOLO_AVAILABLE = False

BASE_DIR = Path(__file__).resolve().parent
RESOURCE_DIR = Path(getattr(sys, '_MEIPASS', BASE_DIR))
RUNTIME_DIR = Path(sys.executable).resolve().parent if getattr(sys, 'frozen', False) else BASE_DIR
load_dotenv(RUNTIME_DIR / '.env')

logging.basicConfig(level=os.getenv('LOG_LEVEL', 'INFO'))
logger = logging.getLogger('roadguard')


def resolve_local_path(value: str) -> Path:
    path = Path(value).expanduser()
    return path if path.is_absolute() else RUNTIME_DIR / path


model_override = os.getenv('MODEL_PATH')
MODEL_PATH = (
    resolve_local_path(model_override)
    if model_override
    else RESOURCE_DIR / 'models' / 'best.pt'
)
STORAGE_DIR = resolve_local_path(os.getenv('STORAGE_DIR', 'storage'))
database_value = os.getenv('DATABASE_URL', 'sqlite:///records.db')
if database_value.startswith('sqlite:///'):
    sqlite_path = Path(database_value.removeprefix('sqlite:///'))
    if not sqlite_path.is_absolute():
        sqlite_path = RUNTIME_DIR / sqlite_path
    DATABASE_URL = f"sqlite:///{sqlite_path.resolve().as_posix()}"
else:
    DATABASE_URL = database_value

MAX_IMAGE_BYTES = int(os.getenv('MAX_IMAGE_BYTES', str(15 * 1024 * 1024)))
MAX_VIDEO_BYTES = int(os.getenv('MAX_VIDEO_BYTES', str(250 * 1024 * 1024)))
MAX_IMAGE_PIXELS = int(os.getenv('MAX_IMAGE_PIXELS', '25000000'))
MAX_RAW_DIMENSION = int(os.getenv('MAX_RAW_DIMENSION', '8192'))
STORAGE_DIR.mkdir(parents=True, exist_ok=True)

# Model yükleme
model: Any = None
model_type = None

try:
    if MODEL_PATH.suffix == '.tflite' and TFLITE_AVAILABLE and tflite is not None and MODEL_PATH.is_file():
        model = tflite.Interpreter(model_path=str(MODEL_PATH))
        model.allocate_tensors()
        model_type = 'tflite'
        logger.info("TensorFlow Lite model yüklendi: %s", MODEL_PATH)
    elif MODEL_PATH.suffix == '.pt' and YOLO_AVAILABLE and YOLO is not None and MODEL_PATH.is_file():
        model = YOLO(str(MODEL_PATH))
        model_type = 'yolo'
        logger.info("YOLOv8 model yüklendi: %s", MODEL_PATH)
    else:
        logger.error("Model dosyası bulunamadı veya çalışma zamanı desteklenmiyor: %s", MODEL_PATH)
except Exception:
    logger.exception("Model yüklenirken hata oluştu: %s", MODEL_PATH)


def ensure_model_ready() -> None:
    if model is None or model_type is None:
        raise HTTPException(status_code=503, detail='Tespit modeli hazır değil')


async def read_upload_limited(upload: UploadFile, max_bytes: int) -> bytes:
    chunks = []
    total = 0
    try:
        while chunk := await upload.read(1024 * 1024):
            total += len(chunk)
            if total > max_bytes:
                raise HTTPException(status_code=413, detail='Yüklenen dosya izin verilen boyutu aşıyor')
            chunks.append(chunk)
    finally:
        await upload.close()
    return b''.join(chunks)


def open_validated_image(data: bytes) -> Image.Image:
    try:
        image = Image.open(io.BytesIO(data))
        image = ImageOps.exif_transpose(image).convert('RGB')
        if image.width <= 0 or image.height <= 0 or image.width * image.height > MAX_IMAGE_PIXELS:
            raise HTTPException(status_code=413, detail='Resim boyutları izin verilen sınırı aşıyor')
        return image
    except HTTPException:
        raise
    except Exception as exc:
        logger.warning("Geçersiz resim reddedildi: %s", exc)
        raise HTTPException(status_code=400, detail='Resim açılamadı veya geçersiz') from exc

def detect_with_tflite(image: Image.Image):
    """TensorFlow Lite ile tespit"""
    # Input tensor bilgilerini al
    input_details = model.get_input_details()
    output_details = model.get_output_details()

    # Görüntüyü hazırla
    img = image.resize((320, 320))  # YOLOv8 Tiny için tipik boyut
    img_array = np.array(img, dtype=np.uint8)
    img_array = np.expand_dims(img_array, axis=0)

    # Tensörü ayarla ve çıkarım yap
    model.set_tensor(input_details[0]['index'], img_array)
    model.invoke()

    # Sonuçları al
    boxes = model.get_tensor(output_details[0]['index'])
    classes = model.get_tensor(output_details[1]['index'])
    scores = model.get_tensor(output_details[2]['index'])

    detections = []
    for i in range(len(scores[0])):
        if scores[0][i] > 0.25:  # confidence threshold
            ymin, xmin, ymax, xmax = boxes[0][i]
            class_id = int(classes[0][i])

            # Normalize coordinates
            nx1 = max(0.0, min(1.0, xmin))
            ny1 = max(0.0, min(1.0, ymin))
            nx2 = max(0.0, min(1.0, xmax))
            ny2 = max(0.0, min(1.0, ymax))

            detections.append({
                'bbox': [nx1, ny1, nx2, ny2],
                'confidence': float(scores[0][i]),
                'class': 'pothole',  # TFLite modelinde class name olmayabilir
            })

    return detections

def detect_with_yolo(image: Image.Image):
    """YOLOv8 ile tespit"""
    results = model(image, imgsz=640, conf=0.25, iou=0.45)
    detections = []

    for r in results:
        if r.boxes is None:
            continue
        for box in r.boxes.data.tolist():
            x1, y1, x2, y2, conf, cls = box
            class_name = model.names[int(cls)] if model.names and int(cls) in model.names else str(int(cls))

            width, height = image.size
            # normalize coords
            nx1 = max(0.0, min(1.0, x1 / width))
            ny1 = max(0.0, min(1.0, y1 / height))
            nx2 = max(0.0, min(1.0, x2 / width))
            ny2 = max(0.0, min(1.0, y2 / height))

            detections.append({
                'bbox': [nx1, ny1, nx2, ny2],
                'confidence': float(conf),
                'class': class_name,
            })

    return detections

engine = create_engine(DATABASE_URL, echo=False)

class PotholeRecord(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    detected_at: datetime
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    confidence: float
    class_name: str
    image_path: str
    bbox: str  # JSON string olarak depolayacağız

class PredictionResponse(BaseModel):
    image_id: str
    detections: List[dict]
    media_width: Optional[int] = None
    media_height: Optional[int] = None

class DeleteRecordsRequest(BaseModel):
    record_ids: List[int]

class RecordResponse(BaseModel):
    id: int
    detected_at: datetime
    latitude: Optional[float]
    longitude: Optional[float]
    confidence: float
    class_name: str
    image_url: str
    bbox: List[float]

app = FastAPI(title='RoadGuard Backend', version='1.0')

cors_origins = [
    origin.strip()
    for origin in os.getenv('CORS_ORIGINS', 'http://127.0.0.1,http://localhost').split(',')
    if origin.strip()
]
app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins,
    allow_credentials=False,
    allow_methods=['GET', 'POST', 'DELETE'],
    allow_headers=['Content-Type', 'X-Image-Width', 'X-Image-Height', 'X-Save-Record'],
)

@app.on_event('startup')
def on_startup():
    SQLModel.metadata.create_all(engine)

@app.get('/')
def root():
    return {
        'status': 'ok',
        'message': 'RoadGuard Backend is running',
        'model_ready': model is not None,
    }

@app.get('/health')
def health():
    return {
        'status': 'ok' if model is not None else 'degraded',
        'model': str(MODEL_PATH),
        'model_ready': model is not None,
    }

@app.post('/predict', response_model=PredictionResponse)
async def predict(file: UploadFile = File(...), latitude: Optional[float] = None, longitude: Optional[float] = None, save_record: bool = True):
    ensure_model_ready()
    filename = (file.filename or '').lower()
    if not filename.endswith(('.jpg', '.jpeg', '.png', '.bmp', '.webp')):
        raise HTTPException(status_code=400, detail='Geçersiz dosya türü. Resim yükleyin.')

    contents = await read_upload_limited(file, MAX_IMAGE_BYTES)
    image = open_validated_image(contents)

    unique_id = str(uuid.uuid4())

    # Model türüne göre tespit yap
    if model_type == 'tflite':
        detections = detect_with_tflite(image)
    elif model_type == 'yolo':
        detections = detect_with_yolo(image)
    else:
        raise HTTPException(status_code=500, detail="Model yüklenemedi")

    # Yalnızca gerçek bir kayıt oluşturulacaksa resmi diske yaz.
    if save_record and detections:
        output_name = STORAGE_DIR / f'{unique_id}.jpg'
        image.save(output_name, format='JPEG', quality=90)
        with Session(engine) as session:
            for det in detections:
                rec = PotholeRecord(
                    detected_at=datetime.now(timezone.utc),
                    latitude=latitude,
                    longitude=longitude,
                    confidence=det['confidence'],
                    class_name=det['class'],
                    image_path=str(output_name),
                    bbox=json.dumps(det['bbox']),
                )
                session.add(rec)
            session.commit()

    return PredictionResponse(
        image_id=unique_id, 
        detections=detections, 
        media_width=image.width, 
        media_height=image.height
    )

class Base64PredictionRequest(BaseModel):
    image: str

@app.post('/predict_base64', response_model=PredictionResponse)
async def predict_base64(req: Base64PredictionRequest, latitude: Optional[float] = None, longitude: Optional[float] = None, save_record: bool = True):
    ensure_model_ready()
    try:
        base64_data = req.image
        if "," in base64_data:
            prefix, base64_data = base64_data.split(",", 1)
            if not prefix.lower().startswith('data:image/') or ';base64' not in prefix.lower():
                raise ValueError('Geçersiz data URI')
        if len(base64_data) > ((MAX_IMAGE_BYTES * 4) // 3) + 8:
            raise HTTPException(status_code=413, detail='Yüklenen resim izin verilen boyutu aşıyor')
        image_data = base64.b64decode(base64_data, validate=True)
    except HTTPException:
        raise
    except (ValueError, binascii.Error) as exc:
        raise HTTPException(status_code=400, detail='Geçersiz Base64 resim verisi') from exc

    if len(image_data) > MAX_IMAGE_BYTES:
        raise HTTPException(status_code=413, detail='Yüklenen resim izin verilen boyutu aşıyor')
    image = open_validated_image(image_data)

    unique_id = str(uuid.uuid4())
    # Model türüne göre tespit yap
    if model_type == 'tflite':
        detections = detect_with_tflite(image)
    elif model_type == 'yolo':
        detections = detect_with_yolo(image)
    else:
        raise HTTPException(status_code=500, detail="Model yüklenemedi")

    # Veritabanına kaydet
    if save_record and detections:
        output_name = STORAGE_DIR / f'{unique_id}.jpg'
        image.save(output_name, format='JPEG', quality=90)
        with Session(engine) as session:
            for det in detections:
                rec = PotholeRecord(
                    detected_at=datetime.now(timezone.utc),
                    latitude=latitude,
                    longitude=longitude,
                    confidence=det['confidence'],
                    class_name=det['class'],
                    image_path=str(output_name),
                    bbox=json.dumps(det['bbox']),
                )
                session.add(rec)
            session.commit()

    return PredictionResponse(
        image_id=unique_id, 
        detections=detections, 
        media_width=image.width, 
        media_height=image.height
    )

@app.post('/predict_raw', response_model=PredictionResponse)
async def predict_raw(request: Request):
    ensure_model_ready()
    # Bu endpoint saniyede onlarca kez çağrılabilir. 
    # Kayıt tutulmaz, sadece anlık bbox döndürür.
    width_str = request.headers.get('X-Image-Width')
    height_str = request.headers.get('X-Image-Height')
    
    if not width_str or not height_str:
        raise HTTPException(status_code=400, detail="Eksik boyut bilgisi")
        
    try:
        width = int(width_str)
        height = int(height_str)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail='Geçersiz boyut bilgisi') from exc

    if not (1 <= width <= MAX_RAW_DIMENSION and 1 <= height <= MAX_RAW_DIMENSION):
        raise HTTPException(status_code=413, detail='Görüntü boyutları izin verilen sınırı aşıyor')
    
    raw_bytes = await request.body()
    expected_size = width * height * 4
    if expected_size > MAX_IMAGE_BYTES or len(raw_bytes) != expected_size:
        raise HTTPException(status_code=400, detail='Ham görüntü boyutu başlıklarla eşleşmiyor')
    
    # BGRA to RGB (Windows Flutter CameraImage format is BGRA8888)
    img_array = np.frombuffer(raw_bytes, dtype=np.uint8).reshape((height, width, 4))
    img_rgb = cv2.cvtColor(img_array, cv2.COLOR_BGRA2RGB)
    image = Image.fromarray(img_rgb)
    
    if model_type == 'tflite':
        detections = detect_with_tflite(image)
    elif model_type == 'yolo':
        detections = detect_with_yolo(image)
    else:
        raise HTTPException(status_code=500, detail="Model yüklü değil")
        
    save_record = request.headers.get('X-Save-Record') == 'true'
    
    if save_record and detections:
        unique_id = str(uuid.uuid4())
        output_name = STORAGE_DIR / f'{unique_id}.jpg'
        image.save(output_name, format='JPEG', quality=90)

        with Session(engine) as session:
            for det in detections:
                rec = PotholeRecord(
                    detected_at=datetime.now(timezone.utc),
                    confidence=det['confidence'],
                    class_name=det['class'],
                    image_path=str(output_name),
                    bbox=json.dumps(det['bbox']),
                )
                session.add(rec)
            session.commit()
        
    return PredictionResponse(
        image_id="stream",
        detections=detections,
        media_width=width,
        media_height=height
    )

@app.post('/predict_video', response_model=PredictionResponse)
async def predict_video(file: UploadFile = File(...), latitude: Optional[float] = None, longitude: Optional[float] = None):
    ensure_model_ready()
    filename = (file.filename or '').lower()
    if not filename.endswith(('.mp4', '.avi', '.mov', '.mkv')):
        raise HTTPException(status_code=400, detail='Geçersiz dosya türü. Video yükleyin.')

    contents = await read_upload_limited(file, MAX_VIDEO_BYTES)
    unique_id = str(uuid.uuid4())
    video_path = STORAGE_DIR / f'{unique_id}.mp4'
    with open(video_path, 'wb') as f:
        f.write(contents)

    cap = cv2.VideoCapture(str(video_path))
    try:
        if not cap.isOpened():
            raise HTTPException(status_code=400, detail='Video açılamadı')

        detections = []
        frame_count = 0
        video_width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        video_height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))

        if video_width <= 0 or video_height <= 0 or video_width * video_height > MAX_IMAGE_PIXELS:
            raise HTTPException(status_code=413, detail='Video boyutları izin verilen sınırı aşıyor')

        while True:
            ret, frame = cap.read()
            if not ret:
                break

            frame_count += 1
            if frame_count % 30 != 0:
                continue

            frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            image = Image.fromarray(frame_rgb)
            frame_detections = (
                detect_with_tflite(image)
                if model_type == 'tflite'
                else detect_with_yolo(image)
            )
            for detection in frame_detections:
                detection['frame'] = frame_count
                detections.append(detection)
    finally:
        cap.release()
        video_path.unlink(missing_ok=True)

    # En güvenilir detection'ları kaydet (confidence > 0.5)
    high_conf_detections = [d for d in detections if d['confidence'] > 0.5]

    # Video araması veritabanına kaydedilmeyecektir (sadece anlık UI kullanımı için).
    # high_conf_detections listesi direkt Flutter'a dönülür.

    return PredictionResponse(
        image_id=unique_id, 
        detections=high_conf_detections,
        media_width=video_width,
        media_height=video_height
    )

@app.get('/records', response_model=List[RecordResponse])
def get_records():
    with Session(engine) as session:
        rows = session.exec(
            select(PotholeRecord).order_by(col(PotholeRecord.detected_at).desc())
        ).all()
    return [RecordResponse(
        id=r.id,
        detected_at=r.detected_at,
        latitude=r.latitude,
        longitude=r.longitude,
        confidence=r.confidence,
        class_name=r.class_name,
        image_url=f'/storage/{Path(r.image_path).name}',
        bbox=json.loads(r.bbox),
    ) for r in rows if r.id is not None]

@app.delete('/records/{record_id}')
def delete_record(record_id: int):
    image_path = None
    with Session(engine) as session:
        record = session.get(PotholeRecord, record_id)
        if not record:
            raise HTTPException(status_code=404, detail="Kayıt bulunamadı")
        image_path = record.image_path
        session.delete(record)
        session.commit()
        remaining = session.exec(
            select(PotholeRecord).where(PotholeRecord.image_path == image_path)
        ).first()
    if remaining is None:
        remove_stored_image(image_path)
    return {"message": "Kayıt başarıyla silindi"}

@app.delete('/records/bulk/delete')
def delete_records_bulk(req: DeleteRecordsRequest):
    if not req.record_ids:
        return {"message": "0 kayıt silindi"}
    with Session(engine) as session:
        records = session.exec(
            select(PotholeRecord).where(col(PotholeRecord.id).in_(set(req.record_ids)))
        ).all()
        image_paths = {record.image_path for record in records}
        for record in records:
            session.delete(record)
        session.commit()
        remaining_paths = {
            row for row in session.exec(
                select(PotholeRecord.image_path).where(col(PotholeRecord.image_path).in_(image_paths))
            ).all()
        }
    for image_path in image_paths - remaining_paths:
        remove_stored_image(image_path)
    return {"message": f"{len(records)} kayıt silindi"}


def remove_stored_image(image_path: str) -> None:
    try:
        candidate = Path(image_path).resolve()
        if candidate.is_relative_to(STORAGE_DIR.resolve()) and candidate.is_file():
            candidate.unlink()
    except OSError:
        logger.exception("Kayıt resmi silinemedi: %s", image_path)

@app.get('/storage/{filename}')
def view_image(filename: str):
    if not filename or Path(filename).name != filename:
        raise HTTPException(status_code=400, detail='Geçersiz dosya adı')
    path = (STORAGE_DIR / filename).resolve()
    if path.parent != STORAGE_DIR.resolve() or not path.is_file():
        raise HTTPException(status_code=404, detail='Dosya bulunamadı')
    return FileResponse(str(path), media_type='image/jpeg')

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        app,
        host=os.getenv('HOST', '127.0.0.1'),
        port=int(os.getenv('PORT', '8000')),
    )
