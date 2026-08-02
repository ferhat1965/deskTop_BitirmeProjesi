@echo off
cd /d "%~dp0"

echo [1/2] Arka plan (Backend) sunucusu baslatiliyor...
cd backend
".venv\Scripts\python.exe" --version >nul 2>&1
if not errorlevel 1 (
    start "RoadGuard Backend" ".venv\Scripts\python.exe" app.py
) else (
    where python >nul 2>&1
    if errorlevel 1 (
        echo HATA: Python bulunamadi. README icindeki backend kurulumunu uygulayin.
        pause
        exit /b 1
    )
    start "RoadGuard Backend" python app.py
)
cd ..

echo.
echo [2/2] Masaustu (Frontend) uygulamasi baslatiliyor...
where flutter >nul 2>&1
if errorlevel 1 (
    echo HATA: Flutter SDK PATH icinde bulunamadi.
    pause
    exit /b 1
)
start cmd /k "title YolGüven Frontend && flutter run -d windows"
