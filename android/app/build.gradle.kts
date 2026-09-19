import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

val requiredSigningKeys = listOf("keyAlias", "keyPassword", "storeFile", "storePassword")
val missingSigningKeys = requiredSigningKeys.filter {
    (keystoreProperties[it] as String?)?.isBlank() != false
}
val hasReleaseSigning = keystorePropertiesFile.exists() && missingSigningKeys.isEmpty()
val allowUnsignedRelease = providers.gradleProperty("allowUnsignedRelease")
    .map { it.toBoolean() }
    .getOrElse(false)

android {
    namespace = "com.nalori.reader"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.nalori.reader"
        minSdk = flutter.minSdkVersion
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasReleaseSigning) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
        }

        release {
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
            isMinifyEnabled = true
            isShrinkResources = true
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

gradle.taskGraph.whenReady {
    val hasReleaseTask = allTasks.any { it.name.contains("Release") }
    if (hasReleaseTask && !hasReleaseSigning && !allowUnsignedRelease) {
        val detail = if (!keystorePropertiesFile.exists()) {
            "android/key.properties is missing"
        } else {
            "android/key.properties is missing: ${missingSigningKeys.joinToString()}"
        }
        throw GradleException(
            "Release signing requires a complete android/key.properties file ($detail). " +
                "Use -PallowUnsignedRelease=true only for CI validation builds."
        )
    }
}

flutter {
    source = "../.."
}
