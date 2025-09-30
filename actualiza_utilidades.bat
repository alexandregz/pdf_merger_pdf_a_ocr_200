REM Script para actualizar as utilidades do entorno ocr-env (micromamba)
REM by chatgpt, non probado aínda

REM 1) Ir ao cartafol onde está micromamba
cd "%LOCALAPPDATA%\CIG\tools\mm"

REM 2) Actualizar TODOS os paquetes do entorno 'ocr-env'
micromamba.exe update -y -r "%LOCALAPPDATA%\CIG\tools\mm" -n ocr-env --all -c conda-forge

REM (opcional) ver lista de paquetes e versións
micromamba.exe list -r "%LOCALAPPDATA%\CIG\tools\mm" -n ocr-env

REM (opcional) instalar unha versión concreta dun paquete
micromamba.exe install -y -r "%LOCALAPPDATA%\CIG\tools\mm" -n ocr-env -c conda-forge ocrmypdf=16.*

REM (opcional) limpeza de cachés
micromamba.exe clean -a -y
