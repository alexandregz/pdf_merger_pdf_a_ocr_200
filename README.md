# Combinador de PDFs

Xunta PDFs nun só según os requerimentos dos xulgados

## Requerimentos legais previos

- Característica de OCR
- Formato PDF/A
- Resolución: 200 PPI
- O documento non pode pesar mais de 4 gigas


## Características

- Acepta **drag & drop** de PDFs
- Lista e permite **reordenar** os ficheiros
- **Une** os PDFs (qpdf)
- Aplica **OCR + PDF/A** e forza **200 dpi** (ocrmypdf/Tesseract/Ghostscript)
- **Controla o límite de 4 GB** con estimación previa e comprobacións reais
- UI simple con progreso e opcións básicas

> **Dependencias externas (gratuítas):** `qpdf`, `ocrmypdf`, `tesseract`, `ghostscript` deben estar instalados e no PATH. En macOS pódese vía Homebrew: `brew install qpdf ocrmypdf tesseract ghostscript`. A 2025-09-28 os paths están hardcodeados para desenvolvemento en macos, ver `const candidates` en _which()


## Dependencias

- [qpdf](https://github.com/qpdf/qpdf)
- [ocrmypdf](https://github.com/ocrmypdf/OCRmyPDF)
- [tesseract](https://github.com/tesseract-ocr/tesseract)
- [gs](https://ghostscript.com/)


## Notas de uso

1. **Instalar dependencias externas** no sistema (PATH):
   - `qpdf`, `ocrmypdf`, `tesseract`, `gs` (ghostscript)
2. Arrastra PDFs á caixa ou emprega o botón **"Engadir"**, reordénaos se precisas.
3. Preme **“Xerar PDF”**, escolle o nome do ficheiro final.
4. A app:
   - Valida dependencias
   - **Une** con `qpdf` → comproba tamaño
   - **OCR + PDF/A + 200 dpi** con `ocrmypdf` → comproba tamaño
   - Garda o resultado


## Personalizacións

- **Tipo de PDF/A**: `ocrmypdf` xera PDF/A-2b por defecto. Podes engadir flags adicionais (ex.: `--pdfa-1`, `--pdfa-3`) se a túa versión os soporta, modificando `_ocrPdfA`.
- **Idiomas OCR**: cambia `_settings.ocrLanguages` (ex.: `glg+spa+por+eng`). Debes ter os datos de idioma instalados en Tesseract.
- **Optimización de tamaño**: axusta `_settings.optimizeLevel` (0–3). 3 é máis agresivo.



## Notas desenvolvemento

- en `macos` hai que saltarse o `sandbox` dos binarios, ou ben eliminando nos `.entitlements` os `com.apple.security.app-sandbox` ou empregando `xattr` directamente contra os binarios empregados
- **OCR**: os argumentos actuais están en `ocrArgs`, por se cómpre revisalos
- **Tipo de PDF/A**: `ocrmypdf` xera PDF/A-2b por defecto. Poderíanse engadir flags adicionais (ex.: `--pdfa-1`, `--pdfa-3`) se a versión os soporta.



## Utilidades

- Validador PDF/A online: https://www.pdf2go.com/validate-pdfa
- Validador PDF/A online: https://www.pdfforge.org/online/en/validate-pdfa



## ToDo

- **Windows**: control de todas as dependencias, o usuario non debe ter que instalar nada.
- Engadir identidade corporativa (Iconos e demais identidade da CIG)