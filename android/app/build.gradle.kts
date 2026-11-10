import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing. key.properties and the keystore are gitignored: losing the
// keystore means never being able to update the app on Play again, so keep a
// backup somewhere other than this machine.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKey = keystorePropertiesFile.exists()
if (hasReleaseKey) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

android {
    namespace = "in.dharaneesh.who_pays"
    compileSdk = flutter.compileSdkVersion
    // Pinned rather than `flutter.ndkVersion` (28.2.x), because this is the
    // version AGP defaults to and the one installed here. No plugin compiles
    // native code; the NDK is needed only so release builds can strip debug
    // symbols from the prebuilt .so files with llvm-strip.
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications uses java.time, which needs desugaring
        // to run on the older Android versions this app supports.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "in.dharaneesh.who_pays"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // The AdMob app id has to live in the manifest, so a --dart-define
        // cannot reach it. Supplied here instead, so the real id is set in
        // one place at build time rather than edited into a tracked file and
        // accidentally committed — or, worse, accidentally not.
        //
        // Defaults to the REAL app id, matching AdsService, which uses the
        // real interstitial unit in release builds. The two must agree: a
        // real unit under a test app id does not serve, and the mismatch is
        // reported as a vague initialisation failure rather than anything
        // that names the cause. Override with:
        //   -PadmobAppId=ca-app-pub-XXXXXXXX~YYYYYYYY
        manifestPlaceholders["admobAppId"] =
            (project.findProperty("admobAppId") as String?)
                ?: "ca-app-pub-7599014130116297~3845208711"
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = keystoreProperties["storeFile"]?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Falls back to debug keys until key.properties exists, so a
            // release build is testable before the keystore is created. Play
            // will reject a debug-signed bundle, which is the intended nudge.
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
