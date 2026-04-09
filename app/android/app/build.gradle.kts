import java.util.Locale

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val apkBaseName = "Codex Remote"

android {
    namespace = "com.example.mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
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

@Suppress("DEPRECATION")
android.applicationVariants.all {
    val flavorSuffix =
        if (flavorName.isNullOrBlank()) {
            ""
        } else {
            "-${flavorName.lowercase(Locale.ROOT)}"
        }
    val variantSuffix = "$flavorSuffix-${buildType.name}"
    val customApkName = "$apkBaseName$variantSuffix.apk"
    val flutterApkName = "app$variantSuffix.apk"
    val apkOutputSubdirectory =
        if (flavorName.isNullOrBlank()) {
            buildType.name
        } else {
            "${flavorName}/${buildType.name}"
        }
    val assembleTaskName = "assemble${name.replaceFirstChar { it.titlecase(Locale.ROOT) }}"
    val copyTaskName = "copy${name.replaceFirstChar { it.titlecase(Locale.ROOT) }}ApkWithProductName"

    val copyNamedApkTask =
        tasks.register(copyTaskName) {
            doLast {
                copy {
                    from(layout.buildDirectory.file("outputs/flutter-apk/$flutterApkName"))
                    into(layout.buildDirectory.dir("outputs/flutter-apk"))
                    rename { customApkName }
                }
                copy {
                    from(layout.buildDirectory.file("outputs/apk/$apkOutputSubdirectory/$flutterApkName"))
                    into(layout.buildDirectory.dir("outputs/apk/$apkOutputSubdirectory"))
                    rename { customApkName }
                }
            }
        }

    tasks.named(assembleTaskName) {
        finalizedBy(copyNamedApkTask)
    }
}

flutter {
    source = "../.."
}
