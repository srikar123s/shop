@echo off
setlocal
rem Ensure Flutter SDK is on PATH if not already present
where flutter >nul 2>&1
if errorlevel 1 (
    if exist "C:\Users\srikar\Downloads\flutter\bin" (
        set "PATH=C:\Users\srikar\Downloads\flutter\bin;%PATH%"
    )
)
echo ================================================================
echo   Building Both APKs: Shop Wholesale (Cloud) and Shop Retail (Local)
echo ================================================================

if not exist "android\key.properties" (
    echo.
    echo [ERROR] Missing android\key.properties for signing release APKs.
    echo Even for personal use on your shop phones, using one consistent personal
    echo keystore lets you install future updates without wiping local SQLite data.
    echo.
    echo Setup once:
    echo   1. Generate keystore:
    echo      keytool -genkey -v -keystore android\keystore\upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
    echo   2. Copy android\key.properties.example to android\key.properties and fill in passwords/path.
    echo   3. Or for quick local USB testing, run: flutter build apk --debug --flavor wholesale
    exit /b 1
)

rem Release any lingering file locks from background daemons
echo Stopping lingering daemons to prevent Windows file locking...
pushd android
call gradlew.bat --stop >nul 2>&1
popd
if exist "build\app\intermediates\merged_java_res" rd /s /q "build\app\intermediates\merged_java_res" >nul 2>&1

echo.
echo [1/2] Building App 1: Shop Wholesale (Cloud Sync)...
call flutter build apk --release --flavor wholesale
if errorlevel 1 (
    echo [ERROR] Failed to build Shop Wholesale APK.
    exit /b %errorlevel%
)
move /Y "build\app\outputs\flutter-apk\app-wholesale-release.apk" "build\app\outputs\flutter-apk\app-wholesale-cloud-release.apk" >nul
if exist "build\app\outputs\flutter-apk\app-wholesale-release.apk.sha1" del /f /q "build\app\outputs\flutter-apk\app-wholesale-release.apk.sha1" >nul 2>&1
echo [SUCCESS] Saved app-wholesale-cloud-release.apk (Shop Wholesale)

echo.
echo [2/2] Building App 2: Shop Retail (Pure Local Offline)...
call flutter build apk --release --flavor retail --dart-define=STANDALONE_LOCAL=true
if errorlevel 1 (
    echo [ERROR] Failed to build Shop Retail APK.
    exit /b %errorlevel%
)
move /Y "build\app\outputs\flutter-apk\app-retail-release.apk" "build\app\outputs\flutter-apk\app-retail-local-release.apk" >nul
if exist "build\app\outputs\flutter-apk\app-retail-release.apk.sha1" del /f /q "build\app\outputs\flutter-apk\app-retail-release.apk.sha1" >nul 2>&1
echo [SUCCESS] Saved app-retail-local-release.apk (Shop Retail)

rem Clean up any legacy or duplicate APK copies if present
if exist "build\app\outputs\flutter-apk\app-cloud-sync-release.apk" del /f /q "build\app\outputs\flutter-apk\app-cloud-sync-release.apk" >nul 2>&1
if exist "build\app\outputs\flutter-apk\app-local-offline-release.apk" del /f /q "build\app\outputs\flutter-apk\app-local-offline-release.apk" >nul 2>&1
if exist "build\app\outputs\flutter-apk\app-release.apk" del /f /q "build\app\outputs\flutter-apk\app-release.apk" >nul 2>&1
if exist "build\app\outputs\flutter-apk\*.sha1" del /f /q "build\app\outputs\flutter-apk\*.sha1" >nul 2>&1

echo.
echo ================================================================
echo   Both APKs Built Successfully!
echo   1. app-wholesale-cloud-release.apk (Shop Wholesale - Cloud Sync)
echo   2. app-retail-local-release.apk    (Shop Retail - Fast Offline)
echo ================================================================
