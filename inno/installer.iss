; --- CIG Combinador PDF - OCR · PDF/A (Instalador Inno Setup) ---
; Instalación per-user (sen UAC), x64, inclúe OCRmyPDFPortable autocontido

[Setup]
AppId={{3E6F5B8A-2A19-4D7A-8E3B-7A6D5B2B1F3C}
AppName=CIG Combinador PDF - OCR · PDF/A
AppVersion={#AppVersionName}             ; versión que ve o usuario (en add/remove/...)
VersionInfoVersion={#AppVersionName}     ; versión embebida no instalador
AppPublisher=CIG
AppPublisherURL=https://cig.gal
DefaultDirName={localappdata}\CIG\CombinadorPDF
DefaultGroupName=CIG
DisableDirPage=no
DisableProgramGroupPage=no
OutputDir=dist
OutputBaseFilename=CIG-CombinadorPDF-Setup
SetupIconFile=windows\runner\resources\app_icon.ico
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
DisableReadyMemo=no
UninstallDisplayIcon={app}\pdf_merger_ocr_pdfa.exe
WizardStyle=modern

[Languages]
Name: "galego"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Crear icona no Escritorio"; GroupDescription: "Atallos:"; Flags: unchecked

[Files]
; 1) App Flutter (carpeta Release completa para non esquecer DLLs)
;    Se prefires ser estrito, cambia pola lista de DLLs necesarias + o .exe
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

; 2) OCRmyPDFPortable autocontido (debe vivir xunto ao .exe)
Source: "windows\OCRmyPDFPortable\*"; DestDir: "{app}\OCRmyPDFPortable"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\CIG Combinador PDF"; Filename: "{app}\pdf_merger_ocr_pdfa.exe"; IconFilename: "{app}\pdf_merger_ocr_pdfa.exe"
Name: "{userdesktop}\CIG Combinador PDF"; Filename: "{app}\pdf_merger_ocr_pdfa.exe"; Tasks: desktopicon

[Run]
; Lanzar a app ao rematar a instalación (opcional, sen elevar)
Filename: "{app}\pdf_merger_ocr_pdfa.exe"; Description: "Executar agora"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Por se o usuario deixa ficheiros extra no cartafol portable
Type: filesandordirs; Name: "{app}\OCRmyPDFPortable"
