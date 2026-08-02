; ==========================================
;   YolGüven Profesyonel Setup Hazırlama Betiği
; ==========================================

[Setup]
AppName=YolGüven
AppVersion=1.0.0
AppPublisher=YolGüven AI
DefaultDirName={localappdata}\Programs\YolGuven
DefaultGroupName=YolGüven
PrivilegesRequired=lowest
OutputDir=installer_output
OutputBaseFilename=YolGuven_Setup
; Uygulamanın kurulum sihirbazındaki ikonunu belirler
SetupIconFile=windows\runner\resources\app_icon.ico
Compression=lzma
SolidCompression=yes
DisableProgramGroupPage=yes

[Languages]
Name: "turkish"; MessagesFile: "compiler:Languages\Turkish.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; 1. Flutter Arayüz Dosyalarını Kopyala
Source: "build\windows\x64\runner\Release\yolguven.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

; 2. Derlenmiş Python Backend Dosyalarını Kopyala
Source: "backend\dist\RoadGuardBackend\*"; DestDir: "{app}\RoadGuardBackend"; Flags: ignoreversion recursesubdirs createallsubdirs

[Dirs]
; Resimlerin kaydedilmesi için boş storage klasörünü oluştur
Name: "{app}\RoadGuardBackend\storage"

[Icons]
; Başlat menüsü kısayolu
Name: "{group}\YolGüven"; Filename: "{app}\yolguven.exe"
; Masaüstü kısayolu (Tam istediğiniz gibi ikonlu!)
Name: "{autodesktop}\YolGüven"; Filename: "{app}\yolguven.exe"; Tasks: desktopicon

[Run]
; Kurulum bittiğinde uygulamayı çalıştırma seçeneği
Filename: "{app}\yolguven.exe"; Description: "{cm:LaunchProgram,YolGüven}"; Flags: nowait postinstall skipifsilent
