import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val dartDefinesRaw = if (project.hasProperty("dart-defines")) {
    project.property("dart-defines") as String
} else {
    ""
}

var dartDefinesDecoded = ""
if (dartDefinesRaw.isNotEmpty()) {
    dartDefinesDecoded = try {
        dartDefinesRaw.split(",").joinToString(",") { chunk ->
            try {
                String(Base64.getDecoder().decode(chunk))
            } catch (e: Exception) {
                chunk
            }
        }
    } catch (e: Exception) {
        dartDefinesRaw
    }
}

val isLocalMode = (project.hasProperty("standalone") && project.property("standalone") == "true")
        || dartDefinesDecoded.contains("STANDALONE_LOCAL=true")
        || dartDefinesRaw.contains("STANDALONE_LOCAL")

val customAppId = if (project.hasProperty("appId")) {
    project.property("appId") as String
} else if (isLocalMode) {
    "com.example.shop.local"
} else {
    "com.example.shop"
}

val customAppName = if (project.hasProperty("appName")) {
    project.property("appName") as String
} else if (isLocalMode) {
    "Shop Retail"
} else {
    "Shop Wholesale"
}

if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

android {
    namespace = "com.example.shop"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = customAppId
        manifestPlaceholders["appName"] = customAppName
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
