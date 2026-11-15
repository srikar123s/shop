@echo off
echo ===================================================
echo   Building Both APKs: Cloud Sync and Local Offline
echo ===================================================

echo.
echo [1/2] Building Cloud Sync APK...
call flutter build apk --release
if errorlevel 1 (
    echo [ERROR] Failed to build Cloud Sync APK.
    exit /b %errorlevel%
)
copy /Y "build\app\outputs\flutter-apk\app-release.apk" "build\app\outputs\flutter-apk\app-cloud-sync-release.apk" >nul
echo [SUCCESS] Saved build\app\outputs\flutter-apk\app-cloud-sync-release.apk

echo.
echo [2/2] Building Pure Local Offline APK...
call flutter build apk --release -Pstandalone=true --dart-define=STANDALONE_LOCAL=true
if errorlevel 1 (
    echo [ERROR] Failed to build Local Offline APK.
    exit /b %errorlevel%
)
copy /Y "build\app\outputs\flutter-apk\app-release.apk" "build\app\outputs\flutter-apk\app-local-offline-release.apk" >nul
echo [SUCCESS] Saved build\app\outputs\flutter-apk\app-local-offline-release.apk

echo.
echo ===================================================
echo   Both APKs Built Successfully!
echo   1. app-cloud-sync-release.apk (Shop Cloud)
echo   2. app-local-offline-release.apk (Shop Local)
echo ===================================================
