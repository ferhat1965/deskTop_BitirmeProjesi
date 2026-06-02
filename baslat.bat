@echo off
cd /d "%~dp0"

echo [1/2] Arka plan (Backend) sunucusu baslatiliyor...
cd backend
if exist ".venv\Scripts\activate.bat" (
    start cmd /k "title RoadGuard Backend && .venv\Scripts\activate.bat && python app.py"
) else (
    start cmd /k "title RoadGuard Backend && python app.py"
)
cd ..

echo.
echo [2/2] Masaustu (Frontend) uygulamasi baslatiliyor...
start cmd /k "title YolGüven Frontend && flutter run -d windows"
