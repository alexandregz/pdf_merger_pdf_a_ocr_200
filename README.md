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

> **Dependencias externas (gratuítas):** `qpdf`, `ocrmypdf`, `tesseract`, `ghostscript` deben estar instalados e no PATH. En macOS pódese vía Homebrew: `brew install qpdf ocrmypdf tesseract ghostscript`. A 2025-09-28 os paths están hardcodeados para desenvolvemento en macos, ver `const candidates` en _which()


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


## Personalizacións

- **Tipo de PDF/A**: `ocrmypdf` xera PDF/A-2b por defecto. Podes engadir flags adicionais (ex.: `--pdfa-1`, `--pdfa-3`) se a túa versión os soporta, modificando `_ocrPdfA`.
- **Idiomas OCR**: cambia `_settings.ocrLanguages` (ex.: `glg+spa+por+eng`). Debes ter os datos de idioma instalados en Tesseract.
- **Optimización de tamaño**: axusta `_settings.optimizeLevel` (0–3). 3 é máis agresivo.



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


## Utilidades

- Validador PDF/A online: https://www.pdf2go.com/validate-pdfa
- Validador PDF/A online: https://www.pdfforge.org/online/en/validate-pdfa



## ToDo

- **Windows**: control de todas as dependencias, o usuario non debe ter que instalar nada.
- Opción de empregar `--redo-ocr` en `ocrmypdf` como parámetro en lugar de `--skip-text`. Agora mesmo empregando `--skip-text`, un PDF de 33M e 170 pax mergeado con outro de 3M e 374 pax. de texto e outro de 300K en lugar de empregar 15 minutos tarda 45 segundos e segue a devolver un PDF/A OCR. Pola contra con `--redo-ocr` convirte en lexible todas as páxinas ainda sen o ser no orixinal.

Cos mesmos ficheiros:
- `--skip-text` ==  `Feito en 0:00:45.114569` (45 seg.)
- `--redo-ocr` == `Feito en 0:16:50.251696` (16 min.)



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