@echo off
setlocal enabledelayedexpansion

REM Usage: batch_process_images.bat input_folder output_folder

if "%~2"=="" (
    echo Usage: %~nx0 input_folder output_folder
    exit /b 1
)

set "INPUT_DIR=%~1"
set "OUTPUT_DIR=%~2"
set "HASH_LOG=hashlog.txt"

if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"
if not exist "%HASH_LOG%" type nul > "%HASH_LOG%"

REM Process each supported file type separately
for %%F in ("%INPUT_DIR%\*.jpg") do call :processFile "%%~F"
for %%F in ("%INPUT_DIR%\*.jpeg") do call :processFile "%%~F"
for %%F in ("%INPUT_DIR%\*.png") do call :processFile "%%~F"

goto :eof

:processFile
set "INPUT_FILE=%~1"
if not exist "%INPUT_FILE%" exit /b

set "FILENAME=%~nx1"
set "BASENAME=%~n1"
set "OUTFILE=%OUTPUT_DIR%\%FILENAME%"

REM Compute hash of input file
set "FILEHASH="
for /f "tokens=* delims=" %%H in ('certutil -hashfile "%INPUT_FILE%" MD5 ^| find /i /v "MD5" ^| find /i /v "certutil"') do (
    set "FILEHASH=%%H"
)

REM Check if this hash exists in hashlog
for /f "tokens=1,2 delims=," %%A in (%HASH_LOG%) do (
    if "!FILEHASH!"=="%%A" (
        if exist "%%B" (
            echo Duplicate found: %FILENAME% matches previous input. Copying existing output.
            copy /Y "%%B" "%OUTFILE%" >NUL
            echo Skipped: %FILENAME%
            exit /b
        )
    )
)

if exist "%OUTFILE%" (
    echo Skipping already processed: %FILENAME%
    exit /b
)

REM Temp files
set "TMP1=%TEMP%\%BASENAME%_1.png"
set "TMP2=%TEMP%\%BASENAME%_2.png"
set "TMP3=%TEMP%\%BASENAME%_3.png"
set "TMP4=%TEMP%\%BASENAME%_4.png"
set "TMP5=%TEMP%\%BASENAME%_5.png"
set "TMP6=%TEMP%\%BASENAME%_6.png"
set "TMP7=%TEMP%\%BASENAME%_7.png"
set "EDGE=%TEMP%\%BASENAME%_edge.png"

REM --- STEP 1: Generate thin, aliased Sobel edge mask at 70% opacity ---
magick "%INPUT_FILE%" -colorspace Gray ^
    -morphology Convolve Sobel ^
    -negate -threshold 25%% ^
    -alpha set -channel A -evaluate multiply 0.5 +channel ^
    "%EDGE%"

REM --- STEP 2: Apply main image filters (without edge) ---
magick "%INPUT_FILE%" -level 20x80%% "%TMP1%"
magick "%TMP1%" -unsharp 0x1 "%TMP2%"
copy /Y "%TMP2%" "%TMP3%" >NUL
magick "%TMP3%" -motion-blur 0x10-25 "%TMP4%"
magick "%TMP4%" -alpha set -channel A -evaluate set 70%% +channel "%TMP5%"
magick "%TMP2%" "%TMP5%" -compose over -composite "%TMP6%"

REM --- STEP 3: Posterize at the very end ---
magick "%TMP6%" -posterize 9 "%TMP7%"

REM --- STEP 4: Final composite with edge overlay ---
magick "%TMP7%" "%EDGE%" -compose Multiply -composite "%OUTFILE%"

if exist "%OUTFILE%" (
    echo %FILEHASH%,%OUTFILE%>> "%HASH_LOG%"
    echo Processed: %FILENAME%
) else (
    echo FAILED: %FILENAME%
)

REM Clean up temp files
del /q "%TMP1%" "%TMP2%" "%TMP3%" "%TMP4%" "%TMP5%" "%TMP6%" "%TMP7%" "%EDGE%"

exit /b
