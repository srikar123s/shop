import java.util.Base64
import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use {
        keystoreProperties.load(it)
    }
}

val releaseKeyAlias = (keystoreProperties["keyAlias"] as String?)?.trim()
val releaseKeyPassword = (keystoreProperties["keyPassword"] as String?)?.trim()
val releaseStoreFilePath = (keystoreProperties["storeFile"] as String?)?.trim()
val releaseStorePassword = (keystoreProperties["storePassword"] as String?)?.trim()
val releaseStoreFile = releaseStoreFilePath
    ?.takeIf { it.isNotEmpty() }
    ?.let { path ->
        val fromRoot = rootProject.file(path)
        if (fromRoot.exists()) fromRoot else project.file(path)
    }
val hasValidReleaseKeystore = keystorePropertiesFile.exists()
        && !releaseKeyAlias.isNullOrEmpty()
        && !releaseKeyPassword.isNullOrEmpty()
        && !releaseStorePassword.isNullOrEmpty()
        && releaseStoreFile != null
        && releaseStoreFile.exists()

gradle.taskGraph.whenReady {
    val runningReleaseTask = allTasks.any { task ->
        task.name.contains("Release", ignoreCase = true)
    }
    if (runningReleaseTask && !hasValidReleaseKeystore) {
        throw GradleException(
            "Release build blocked: missing or incomplete android/key.properties or keystore file " +
                "(required keys: storeFile, storePassword, keyAlias, keyPassword). " +
                "Refusing insecure debug-keystore fallback for release builds."
        )
    }
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
        || dartDefinesDecoded.split(",").contains("STANDALONE_LOCAL=true")

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
        isCoreLibraryDesugaringEnabled = true
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

    flavorDimensions += "edition"
    productFlavors {
        create("wholesale") {
            dimension = "edition"
            applicationId = if (project.hasProperty("appId")) {
                project.property("appId") as String
            } else {
                "com.example.shop"
            }
            manifestPlaceholders["appName"] = if (project.hasProperty("appName")) {
                project.property("appName") as String
            } else {
                "Shop Wholesale"
            }
        }
        create("retail") {
            dimension = "edition"
            applicationId = if (project.hasProperty("appId")) {
                project.property("appId") as String
            } else {
                "com.example.shop.local"
            }
            manifestPlaceholders["appName"] = if (project.hasProperty("appName")) {
                project.property("appName") as String
            } else {
                "Shop Retail"
            }
        }
    }

    signingConfigs {
        if (hasValidReleaseKeystore) {
            create("release") {
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
                storeFile = releaseStoreFile
                storePassword = releaseStorePassword
            }
        }
    }

    buildTypes {
        release {
            val requireProdId = (project.hasProperty("requireProductionAppId") &&
                project.property("requireProductionAppId") == "true")
            if (requireProdId && customAppId.startsWith("com.example.")) {
                throw GradleException(
                    "Production release blocked: replace default '$customAppId' with your reverse-domain Play Store applicationId via -PappId=com.yourcompany.shop and matching google-services.json."
                )
            }
            if (hasValidReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
