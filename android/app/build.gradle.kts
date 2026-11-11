import java.util.Properties
import org.gradle.api.GradleException

val keystoreProperties = Properties()
val defaultWorkspaceKeystorePropertiesFile = rootDir
    .resolve("../../speedlogi-driver-release/key.properties")
    .canonicalFile
val keystorePropertiesPath = providers.environmentVariable("DRIVER_APP_KEY_PROPERTIES")
    .orElse(providers.gradleProperty("driverAppKeyProperties"))
    .orNull
val keystorePropertiesFile = keystorePropertiesPath?.let { file(it) }
    ?: defaultWorkspaceKeystorePropertiesFile.takeIf { it.exists() }
val hasReleaseKeystore = keystorePropertiesFile?.exists() == true

if (hasReleaseKeystore) {
    keystorePropertiesFile!!.inputStream().use { keystoreProperties.load(it) }
}

val releaseKeystoreError = "Missing release signing properties. Set DRIVER_APP_KEY_PROPERTIES or -PdriverAppKeyProperties, or restore ../../speedlogi-driver-release/key.properties."

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    namespace = "com.ilabinformationtechnology.driver"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.ilabinformationtechnology.driver"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                signingConfig = signingConfigs.getByName("debug")
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

// Flutter 3.44 generates the release AOT library under its intermediate
// directory. With this project's redirected build directory, AGP can omit that
// library while packaging the APK, producing a launch-time "VM snapshot
// invalid" crash. Stage it as an explicit release JNI source before packaging.
val stageReleaseFlutterJniLibs by tasks.registering(Copy::class) {
    dependsOn("copyJniLibsflutterBuildRelease")
    from(layout.buildDirectory.dir("intermediates/flutter/release/jniLibs"))
    include("**/libapp.so")
    into(layout.buildDirectory.dir("generated/release-jni-libs"))
}

android.sourceSets.getByName("release").jniLibs.srcDir(
    layout.buildDirectory.dir("generated/release-jni-libs")
)

afterEvaluate {
    tasks.matching { it.name == "mergeReleaseJniLibFolders" }.configureEach {
        dependsOn(stageReleaseFlutterJniLibs)
    }

    tasks.matching { it.name.startsWith("uploadCrashlyticsMappingFile") }.configureEach {
        enabled = false
    }
}

gradle.taskGraph.whenReady {
    val needsReleaseSigning = allTasks.any { task ->
        task.project == project && task.name.contains("Release", ignoreCase = true)
    }

    if (needsReleaseSigning && !hasReleaseKeystore) {
        throw GradleException(releaseKeystoreError)
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}

// Redirect build output to where Flutter expects it: driver_app/build/app/
layout.buildDirectory.set(rootProject.layout.projectDirectory.dir("../build/app"))
