plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.voiceagent.voice_agent"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications needs java.time on minSdk 24.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.voiceagent.voice_agent"
        minSdk = 24
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    flavorDimensions += "environment"
    productFlavors {
        create("stable") {
            dimension = "environment"
            applicationId = "com.voiceagent.voice_agent"
            resValue("string", "app_name", "Voice Agent")
        }
        create("dev") {
            dimension = "environment"
            applicationId = "com.voiceagent.voice_agent.dev"
            resValue("string", "app_name", "Voice Agent DEV")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // Gson keep rules for flutter_local_notifications; see the file.
            proguardFiles("proguard-rules.pro")
        }
    }
}

dependencies {
    implementation("androidx.media:media:1.7.0")
    implementation("androidx.work:work-runtime:2.11.2")
    implementation("com.google.android.gms:play-services-location:21.3.0")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // The trigger parser is tested off the device (ADR-NET-007); android.jar's
    // org.json is a stub there, so the real one is put first.
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
}

flutter {
    source = "../.."
}
