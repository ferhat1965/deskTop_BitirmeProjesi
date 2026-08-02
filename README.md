# YolGüven

YolGüven, Windows kamerasından alınan görüntülerde yol çukuru tespiti yapan bir
Flutter masaüstü uygulaması ve yerel FastAPI/YOLO backend'idir.

## Gereksinimler

- Flutter SDK (projenin `pubspec.yaml` dosyasındaki Dart sürümüyle uyumlu)
- Python 3.11–3.13 (backend ve PyInstaller paketleme için)
- Visual Studio Desktop development with C++ bileşenleri
- Inno Setup 6 (yalnızca Windows installer üretmek için)

## Backend kurulumu

```powershell
cd backend
py -3.13 -m venv .venv
.\.venv\Scripts\python.exe -m pip install --upgrade pip
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
Copy-Item .env.example .env
.\.venv\Scripts\python.exe app.py
```

Backend varsayılan olarak yalnızca `127.0.0.1:8000` adresini dinler. Model
dosyası `backend/models/best.pt` konumunda olmalıdır. `.env`, veritabanı ve
yüklenen görüntüler Git'e eklenmez.

## Flutter uygulaması

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

Uygulama açılırken backend kapalıysa geliştirme ortamındaki Python backend'ini,
kurulu sürümde ise `RoadGuardBackend/RoadGuardBackend.exe` dosyasını başlatmayı
dener.

## Windows paketleme

Önce backend'i ve Flutter uygulamasını yeniden derleyin:

```powershell
cd backend
.\.venv\Scripts\python.exe -m pip install pyinstaller
.\.venv\Scripts\pyinstaller.exe --clean RoadGuardBackend.spec
cd ..
flutter build windows --release
```

Son olarak `yolguven_setup.iss` dosyasını Inno Setup ile derleyin. Installer
çıktısı `installer_output` klasörüne yazılır.

## Güvenlik notları

- Backend'i internete açmayın; tasarım gereği yerel masaüstü uygulamasına hizmet eder.
- `.env`, `records.db`, `storage/`, `build/` ve `dist/` dosyalarını commit etmeyin.
- Dosya yükleme sınırları `.env` üzerinden düşürülebilir; üretimde yükseltmeden önce bellek kullanımını ölçün.
- Eski paketleri dağıtmadan önce backend ve Windows release klasörlerini temizleyip yeniden derleyin.
