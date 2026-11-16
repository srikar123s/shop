@echo off
echo ================================================================
echo   Building Both APKs: Shop Wholesale (Cloud) and Shop Retail (Local)
echo ================================================================

rem Release any lingering file locks from background daemons
echo Stopping lingering daemons to prevent Windows file locking...
pushd android
call gradlew.bat --stop >nul 2>&1
popd
if exist "build\app\intermediates\merged_java_res" rd /s /q "build\app\intermediates\merged_java_res" >nul 2>&1

echo.
echo [1/2] Building App 1: Shop Wholesale (Cloud Sync)...
call flutter build apk --release -PappName="Shop Wholesale"
if errorlevel 1 (
    echo [ERROR] Failed to build Shop Wholesale APK.
    exit /b %errorlevel%
)
copy /Y "build\app\outputs\flutter-apk\app-release.apk" "build\app\outputs\flutter-apk\app-wholesale-cloud-release.apk" >nul
copy /Y "build\app\outputs\flutter-apk\app-release.apk" "build\app\outputs\flutter-apk\app-cloud-sync-release.apk" >nul
echo [SUCCESS] Saved app-wholesale-cloud-release.apk (Shop Wholesale)

rem Clean intermediate jar before second build to avoid cross-flavor R8 lock
if exist "build\app\intermediates\merged_java_res" rd /s /q "build\app\intermediates\merged_java_res" >nul 2>&1

echo.
echo [2/2] Building App 2: Shop Retail (Pure Local Offline)...
call flutter build apk --release -Pstandalone=true -PappName="Shop Retail" -PappId="com.example.shop.local" --dart-define=STANDALONE_LOCAL=true
if errorlevel 1 (
    echo [ERROR] Failed to build Shop Retail APK.
    exit /b %errorlevel%
)
copy /Y "build\app\outputs\flutter-apk\app-release.apk" "build\app\outputs\flutter-apk\app-retail-local-release.apk" >nul
copy /Y "build\app\outputs\flutter-apk\app-release.apk" "build\app\outputs\flutter-apk\app-local-offline-release.apk" >nul
echo [SUCCESS] Saved app-retail-local-release.apk (Shop Retail)

echo.
echo ================================================================
echo   Both APKs Built Successfully!
echo   1. app-wholesale-cloud-release.apk (Shop Wholesale - Cloud Sync)
echo   2. app-retail-local-release.apk    (Shop Retail - Fast Offline)
echo ================================================================
