# Combinador de PDFs

Xunta PDFs nun só según os requerimentos dos xulgados

## Requerimentos legais previos

- Característica de OCR
- Formato PDF/A
- Resolución: 200 dpi
- O documento non pode pesar mais de 4 gigas


## Características

- Acepta **drag & drop** de PDFs
- Lista e permite **reordenar** os ficheiros
- **Une** os PDFs (qpdf)
- Aplica **OCR + PDF/A** e forza **200 dpi** (ocrmypdf/Tesseract/Ghostscript)
- **Controla o límite de 4 GB** con estimación previa e comprobacións reais
- UI simple con progreso e opcións básicas

> **Dependencias externas (gratuítas):** `qpdf`, `ocrmypdf`, `tesseract`, `ghostscript` deben estar instalados e no PATH. En macOS pódese vía Homebrew: `brew install qpdf ocrmypdf tesseract ghostscript`. En windows empréganse versión autocontidas (ver https://github.com/alexandregz/ocrmypdf_portable_windows)


## Dependencias

- [qpdf](https://github.com/qpdf/qpdf)
- [ocrmypdf](https://github.com/ocrmypdf/OCRmyPDF)
- [tesseract](https://github.com/tesseract-ocr/tesseract)
- [gs](https://ghostscript.com/)


## Notas de uso

1.(macos/*nix) **Instalar dependencias externas** no sistema (PATH):
   - `qpdf`, `ocrmypdf`, `tesseract`, `gs` (ghostscript)
2. Arrastra PDFs á caixa ou emprega o botón **"Engadir"**, reordénaos se precisas.
3. Preme **“Xerar PDF”**, escolle o nome do ficheiro final.
4. A app:
   - Valida dependencias
   - **Une** con `qpdf` → comproba tamaño
   - **OCR + PDF/A + 200 dpi** con `ocrmypdf` → comproba tamaño
   - Garda o resultado

Pódese desactivar o uso de `ocrmypdf` e simplemente unir PDFs con `qpdf`.

## Personalizacións

- **Tipo de PDF/A**: `ocrmypdf` xera PDF/A-2b por defecto. Podes engadir flags adicionais (ex.: `--pdfa-1`, `--pdfa-3`) se a túa versión os soporta, engadindo parámetros adicionas en `Axustes`.
- **Idiomas OCR**: cambia `_settings.ocrLanguages` (ex.: `glg+spa+por+eng`). Debes ter os datos de idioma instalados en Tesseract.
- **Optimización de tamaño**: axusta `_settings.optimizeLevel` (0–3). 3 é máis agresivo.

## Desactivado ocrmypdf

En `Axustes` pódese desactivar o uso de ocrmypdf, así como personalizar o uso con parámetros.

Como exemplo, combinando 3 PDFs pequenos:

- Sen ocrmypdf:
```
Feito en 0:00:00.086811. Gardado en: /Users/alex/Desktop/documento_final.pdf
```

- Con ocrmypdf:
```
ocrmypdf durou 0:00:10.411909
Tamaño final: 1.12 MB
Feito en 0:00:10.610828. Gardado en: /Users/alex/Desktop/documento_final.pdf
```


## Dependencias

- **qpdf**: para unir PDFs na orde indicada, crea un merged_raw.pdf a partir da lista
- **ocrmypdf**: orquestador do OCR e da conversión a PDF/A, chamando a `tesseract` e `gs`. Toma o merged_raw.pdf, fai OCR, mete capa de texto, converte a PDF/A e xera merged_final.pdf
- **tesseract**: motor do OCR, chamado internamente por `ocrmypdf`
- **gs**: empregado internamente por `ocrmypdf` para render/repasar e axudar coa conformidade PDF/A.


## Notas desenvolvemento

- en `macos` hai que saltarse o `sandbox` dos binarios, ou ben eliminando nos `.entitlements` os `com.apple.security.app-sandbox` ou empregando `xattr` directamente contra os binarios empregados
- **OCR**: os argumentos actuais están en `ocrArgs`, por se cómpre revisalos
- **Tipo de PDF/A**: `ocrmypdf` xera PDF/A-2b por defecto. Poderíanse engadir flags adicionais (ex.: `--pdfa-1`, `--pdfa-3`) se a versión os soporta.
- en `windows` emprega `ocrmypdf` autocontido en proxecto propio: https://github.com/alexandregz/ocrmypdf_portable_windows
- Pódese empregar `--redo-ocr` en `ocrmypdf` como parámetro en lugar de `--skip-text` (opción empregada por defecto). Empregando `--skip-text`, un PDF de 33M e 170 pax mergeado con outro de 3M e 374 pax. de texto e outro de 300K en lugar de empregar 15 minutos tarda 45 segundos e segue a devolver un PDF/A OCR. Pola contra con `--redo-ocr` convirte en lexible todas as páxinas ainda sen o ser no orixinal.

Cos mesmos ficheiros:
- `--skip-text` ==  `Feito en 0:00:45.114569` (45 seg.)
- `--redo-ocr` == `Feito en 0:16:50.251696` (16 min.)

## Construir versionado en windows

- versionar con `pubspec.yaml`
- `flutter clean` e `flutter build windows`
- empregar `inno/get_version.ps1` (dentro do directorio) para pasar version a `installer.iss`:
```powershell
PS C:\Users\aemen\develop\pdf_merger_pdf_a_ocr_200\inno> .\get_version.ps1
```
- a app queda en `inno/dist/`

## Construir versionado en macos

- versionar co `pubspec.yaml`
- executar `bash create_dmg/build_dmg.sh`

```bash
alex@vosjod:~/Development/flutter/pdf_merger_pdf_a_ocr_200 (main)$ bash create_dmg/build_dmg.sh
==> 0) Dependencias rápidas
==> 1) Forzar build universal (arm64 + x86_64) en Release sen abrir Xcode
==> 2) Build Release de macOS (Flutter)
Cleaning Xcode workspace...                                      2.689ms
Deleting build...                                                      ⣷
   266ms
Deleting .dart_tool...                                               3ms
Deleting ephemeral...                                                0ms
Deleting ephemeral...                                                0ms
Deleting .flutter-plugins-dependencies...                            0ms
Resolving dependencies...
Downloading packages...
  characters 1.4.0 (1.4.1 available)
  desktop_drop 0.6.1 (0.7.0 available)
  file_selector_android 0.5.1+16 (0.5.2+1 available)
  file_selector_ios 0.5.3+2 (0.5.3+3 available)
  file_selector_macos 0.9.4+4 (0.9.4+5 available)
  material_color_utilities 0.11.1 (0.13.0 available)
  meta 1.16.0 (1.17.0 available)
  package_info_plus 8.3.1 (9.0.0 available)
  shared_preferences_android 2.4.14 (2.4.15 available)
  shared_preferences_foundation 2.5.4 (2.5.5 available)
  url_launcher_android 6.3.23 (6.3.24 available)
  url_launcher_ios 6.3.4 (6.3.5 available)
  url_launcher_macos 3.2.3 (3.2.4 available)
Got dependencies!
13 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
Running pod install...                                             757ms
warning: Run script build phase 'Run Script' will be run during every build because it does not specify any outputs. To address this issue, either add output dependencies to the script phase, or configure it to run in every build by unchecking "Based on dependency analysis" in the script phase. (in target 'Flutter Assemble' from project 'Runner')
Building macOS application...
✓ Built build/macos/Build/Products/Release/CIG Combinador PDF.app (47.0MB)

==> 3) Verificar que o binario é universal
Arquitecturas atopadas: x86_64 arm64

==> 4) Asinar ad-hoc (sen hardened runtime)
build/macos/Build/Products/Release/CIG Combinador PDF.app: replacing existing signature
--prepared:/Users/alex/Development/flutter/pdf_merger_pdf_a_ocr_200/build/macos/Build/Products/Release/CIG Combinador PDF.app/Contents/Frameworks/shared_preferences_foundation.framework/Versions/Current/.
--prepared:/Users/alex/Development/flutter/pdf_merger_pdf_a_ocr_200/build/macos/Build/Products/Release/CIG Combinador PDF.app/Contents/Frameworks/desktop_drop.framework/Versions/Current/.
--prepared:/Users/alex/Development/flutter/pdf_merger_pdf_a_ocr_200/build/macos/Build/Products/Release/CIG Combinador PDF.app/Contents/Frameworks/package_info_plus.framework/Versions/Current/.
--validated:/Users/alex/Development/flutter/pdf_merger_pdf_a_ocr_200/build/macos/Build/Products/Release/CIG Combinador PDF.app/Contents/Frameworks/desktop_drop.framework/Versions/Current/.
--validated:/Users/alex/Development/flutter/pdf_merger_pdf_a_ocr_200/build/macos/Build/Products/Release/CIG Combinador PDF.app/Contents/Frameworks/shared_preferences_foundation.framework/Versions/Current/.
--validated:/Users/alex/Development/flutter/pdf_merger_pdf_a_ocr_200/build/macos/Build/Products/Release/CIG Combinador PDF.app/Contents/Frameworks/package_info_plus.framework/Versions/Current/.
--prepared:/Users/alex/Development/flutter/pdf_merger_pdf_a_ocr_200/build/macos/Build/Products/Release/CIG Combinador PDF.app/Contents/Frameworks/screen_retriever_macos.framework/Versions/Current/.
--prepared:/Users/alex/Development/flutter/pdf_merger_pdf_a_ocr_200/build/macos/Build/Products/Release/CIG Combinador PDF.app/Contents/Frameworks/window_manager.framework/Versions/Current/.
--validated:/Users/alex/Development/flutter/pdf_merger_pdf_a_ocr_200/build/macos/Build/Products/Release/CIG Combinador PDF.app/Contents/Frameworks/window_manager.framework/Versions/Current/.
--validated:/Users/alex/Development/flutter/pdf_merger_pdf_a_ocr_200/build/macos/Build/Products/Release/CIG Combinador PDF.app/Contents/Frameworks/screen_retriever_macos.framework/Versions/Current/.
--prepared:/Users/alex/Development/flutter/pdf_merger_pdf_a_ocr_200/build/macos/Build/Products/Release/CIG Combinador PDF.app/Contents/Frameworks/file_selector_macos.framework/Versions/Current/.
--validated:/Users/alex/Development/flutter/pdf_merger_pdf_a_ocr_200/build/macos/Build/Products/Release/CIG Combinador PDF.app/Contents/Frameworks/file_selector_macos.framework/Versions/Current/.
--prepared:/Users/alex/Development/flutter/pdf_merger_pdf_a_ocr_200/build/macos/Build/Products/Release/CIG Combinador PDF.app/Contents/Frameworks/url_launcher_macos.framework/Versions/Current/.
--validated:/Users/alex/Development/flutter/pdf_merger_pdf_a_ocr_200/build/macos/Build/Products/Release/CIG Combinador PDF.app/Contents/Frameworks/url_launcher_macos.framework/Versions/Current/.
--prepared:/Users/alex/Development/flutter/pdf_merger_pdf_a_ocr_200/build/macos/Build/Products/Release/CIG Combinador PDF.app/Contents/Frameworks/App.framework/Versions/Current/.
--validated:/Users/alex/Development/flutter/pdf_merger_pdf_a_ocr_200/build/macos/Build/Products/Release/CIG Combinador PDF.app/Contents/Frameworks/App.framework/Versions/Current/.
--prepared:/Users/alex/Development/flutter/pdf_merger_pdf_a_ocr_200/build/macos/Build/Products/Release/CIG Combinador PDF.app/Contents/Frameworks/FlutterMacOS.framework/Versions/Current/.
--validated:/Users/alex/Development/flutter/pdf_merger_pdf_a_ocr_200/build/macos/Build/Products/Release/CIG Combinador PDF.app/Contents/Frameworks/FlutterMacOS.framework/Versions/Current/.
build/macos/Build/Products/Release/CIG Combinador PDF.app: valid on disk
build/macos/Build/Products/Release/CIG Combinador PDF.app: satisfies its Designated Requirement
==> 5) Preparar unha copia co nome amigable para o DMG
==> 6) Crear DMG con create-dmg + ligazón a Applications
Creating disk image...
........................................................................................................................................
created: /Users/alex/Development/flutter/pdf_merger_pdf_a_ocr_200/rw.41935.CIG Combinador PDF.dmg
Mounting disk image...
Device name:     /dev/disk21
Searching for mounted interstitial disk image using /dev/disk21s...
Mount dir:       /Volumes/dmg.8K2DRx
Making link to Applications dir...
/Volumes/dmg.8K2DRx
Running AppleScript to make Finder stuff pretty: /usr/bin/osascript "/var/folders/mx/tgfkvtc57_qbzsv0hm_m33z80000gn/T/createdmg.tmp.XXXXXXXXXX.aTug6bxcGT" "dmg.8K2DRx"
waited 1 seconds for .DS_STORE to be created.
Done running the AppleScript...
Fixing permissions...
Done fixing permissions
Skipping blessing on sandbox
Deleting .fseventsd
Unmounting disk image...
"disk21" ejected.
Compressing disk image...
Preparando creación de imagen…
Leyendo Protective Master Boot Record (MBR: 0)…
   (CRC32 $61ED8E02: Protective Master Boot Record (MBR: 0))
Leyendo GPT Header (Primary GPT Header: 1)…
   (CRC32 $869CE0DF: GPT Header (Primary GPT Header: 1))
Leyendo GPT Partition Data (Primary GPT Table: 2)…
   (CRC32 $C428B80C: GPT Partition Data (Primary GPT Table: 2))
Leyendo  (Apple_Free: 3)…
   (CRC32 $00000000:  (Apple_Free: 3))
Leyendo disk image (Apple_HFS: 4)…
....................................................................................................................................................................................
   (CRC32 $9F09B37B: disk image (Apple_HFS: 4))
Leyendo  (Apple_Free: 5)…
....................................................................................................................................................................................
   (CRC32 $00000000:  (Apple_Free: 5))
Leyendo GPT Partition Data (Backup GPT Table: 6)…
....................................................................................................................................................................................
   (CRC32 $C428B80C: GPT Partition Data (Backup GPT Table: 6))
Leyendo GPT Header (Backup GPT Header: 7)…
....................................................................................................................................................................................
   (CRC32 $6DA3AA7E: GPT Header (Backup GPT Header: 7))
Añadiendo recursos…
....................................................................................................................................................................................
Tiempo transcurrido:  4.925s
Tamaño del archivo: 18858118 bytes, Suma: CRC32 $D7A75B8A
Sectores procesados: 147536, 94500 comprimido
Velocidad: 9.4M B/s
Ahorro: 75.0 %
created: /Users/alex/Development/flutter/pdf_merger_pdf_a_ocr_200/CIG Combinador PDF.dmg
hdiutil does not support internet-enable. Note it was removed in macOS 10.15.
Disk image done
==> 7) Comprobacións básicas
Calculando suma de Protective Master Boot Record (MBR: 0)…
Protective Master Boot Record (MBR: : verificado   CRC32 $61ED8E02
Calculando suma de GPT Header (Primary GPT Header: 1)…
  GPT Header (Primary GPT Header: 1): verificado   CRC32 $869CE0DF
Calculando suma de GPT Partition Data (Primary GPT Table: 2)…
GPT Partition Data (Primary GPT Tabl: verificado   CRC32 $C428B80C
Calculando suma de  (Apple_Free: 3)…
                     (Apple_Free: 3): verificado   CRC32 $00000000
Calculando suma de disk image (Apple_HFS: 4)…
....................................................................................................................................................................................
           disk image (Apple_HFS: 4): verificado   CRC32 $9F09B37B
Calculando suma de  (Apple_Free: 5)…
....................................................................................................................................................................................
                     (Apple_Free: 5): verificado   CRC32 $00000000
Calculando suma de GPT Partition Data (Backup GPT Table: 6)…
....................................................................................................................................................................................
GPT Partition Data (Backup GPT Table: verificado   CRC32 $C428B80C
Calculando suma de GPT Header (Backup GPT Header: 7)…
....................................................................................................................................................................................
   GPT Header (Backup GPT Header: 7): verificado   CRC32 $6DA3AA7E
....................................................................................................................................................................................
verificado   CRC32 $D7A75B8A
hdiutil: verify: checksum of "CIG Combinador PDF.dmg" is VALID
CIG Combinador PDF.dmg: rejected
source=Insufficient Context
Listo! DMG xerado: CIG Combinador PDF.dmg

NOTA IMPORTANTE:
- En *outros* Macs, ao non estar notarizado con Developer ID, Gatekeeper pode amosar aviso.
- Para probas no teu Mac: abre o DMG, arrastra a Applications e, se che avisa, click dereito > Open > Open.

Se máis adiante queres eliminar calquera aviso en Macs alleos, activa o bloque de notarización inferior.

==> [DEV ID] Crear de novo o DMG asinando a app oficial
Creating disk image...
........................................................................................................................................
created: /Users/alex/Development/flutter/pdf_merger_pdf_a_ocr_200/rw.42358.CIG Combinador PDF.dmg
Mounting disk image...
Device name:     /dev/disk21
Searching for mounted interstitial disk image using /dev/disk21s...
Mount dir:       /Volumes/dmg.p1btbX
Making link to Applications dir...
/Volumes/dmg.p1btbX
Running AppleScript to make Finder stuff pretty: /usr/bin/osascript "/var/folders/mx/tgfkvtc57_qbzsv0hm_m33z80000gn/T/createdmg.tmp.XXXXXXXXXX.GvAvsnmCst" "dmg.p1btbX"
waited 1 seconds for .DS_STORE to be created.
Done running the AppleScript...
Fixing permissions...
Done fixing permissions
Skipping blessing on sandbox
Deleting .fseventsd
Unmounting disk image...
"disk21" ejected.
Compressing disk image...
Preparando creación de imagen…
Leyendo Protective Master Boot Record (MBR: 0)…
   (CRC32 $61ED8E02: Protective Master Boot Record (MBR: 0))
Leyendo GPT Header (Primary GPT Header: 1)…
   (CRC32 $0EDE9616: GPT Header (Primary GPT Header: 1))
Leyendo GPT Partition Data (Primary GPT Table: 2)…
   (CRC32 $27BB0945: GPT Partition Data (Primary GPT Table: 2))
Leyendo  (Apple_Free: 3)…
   (CRC32 $00000000:  (Apple_Free: 3))
Leyendo disk image (Apple_HFS: 4)…
....................................................................................................................................................................................
   (CRC32 $9D5E75A2: disk image (Apple_HFS: 4))
Leyendo  (Apple_Free: 5)…
....................................................................................................................................................................................
   (CRC32 $00000000:  (Apple_Free: 5))
Leyendo GPT Partition Data (Backup GPT Table: 6)…
....................................................................................................................................................................................
   (CRC32 $27BB0945: GPT Partition Data (Backup GPT Table: 6))
Leyendo GPT Header (Backup GPT Header: 7)…
....................................................................................................................................................................................
   (CRC32 $E5E1DCB7: GPT Header (Backup GPT Header: 7))
Añadiendo recursos…
....................................................................................................................................................................................
Tiempo transcurrido:  4.170s
Tamaño del archivo: 18858117 bytes, Suma: CRC32 $A9E2E560
Sectores procesados: 147536, 94500 comprimido
Velocidad: 11.1M B/s
Ahorro: 75.0 %
created: /Users/alex/Development/flutter/pdf_merger_pdf_a_ocr_200/CIG Combinador PDF.dmg
hdiutil does not support internet-enable. Note it was removed in macOS 10.15.
Disk image done
alex@vosjod:~/Development/flutter/pdf_merger_pdf_a_ocr_200 (main)$
```



## Utilidades

- Validador PDF/A online: https://www.pdf2go.com/validate-pdfa
- Validador PDF/A online: https://www.pdfforge.org/online/en/validate-pdfa



## Capturas de pantalla

![lanzar app](imaxes/001%20lanzar.png)

![drag&drop de ficheiros](imaxes/002%20draganddrop.png)

![xerar](imaxes/003%20xerar.png)

![documento de destino](imaxes/004%20destino.png)

![xerando](imaxes/005%20xerando.png)

![xerado documento final](imaxes/006%20xerado.png)

![comprobación de formato PDF-A](imaxes/007%20comprobacion.png)


#### Como reordenar

Pinchas nas dúas linhas e reordena o ficheiro:

![reordenar](imaxes/008%20reordenar.png)


#### Como eliminar

Para eliminar un ficheiro do documento final, simplemente pincha na cruz á dereito do mesmo ficheiro:

![eliminar](imaxes/009%20eliminar%20ficheiro.png)

![eliminado](imaxes/010%20eliminar%20ficheiro.png)


### Axustes

![botón Axustes](imaxes/011%20axustes.png)

![Axustes](imaxes/012%20axustes.png)

![Axustes abaixo](imaxes/013%20axustes.png)

macos:
![Acerca de](imaxes/014%20about.png)