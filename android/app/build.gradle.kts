import java.util.Properties

plugins {
    id("com.android.application")
}

val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localPropertiesFile.inputStream().use { localProperties.load(it) }
}

val blenderNativeOut = localProperties.getProperty(
    "blender.native.outdir",
    "../build_android/bin",
)

android {
    namespace = "org.blender.experimental"
    compileSdk = 35

    defaultConfig {
        applicationId = "org.blender.experimental"
        minSdk = 29
        targetSdk = 35
        versionCode = 50200
        versionName = "5.2.0-android-experimental"

        ndk {
            /* All modern phones (Pixel, Samsung, etc.) — 64-bit ARM only. */
            abiFilters += "arm64-v8a"
        }

        externalNativeBuild {
            cmake {
                arguments += listOf(
                    "-DANDROID_STL=c++_shared",
                    "-DANDROID_PLATFORM=android-29",
                    "-DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON",
                )
            }
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
            keepDebugSymbols += "**/*.so"
        }
        resources {
            excludes += listOf("META-INF/DEPENDENCIES", "META-INF/LICENSE*", "META-INF/NOTICE*")
        }
    }

    buildTypes {
        debug {
            isDebuggable = true
            isMinifyEnabled = false
        }
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            jniLibs.srcDirs("src/main/jniLibs")
            assets.srcDirs("src/main/assets")
        }
    }

    androidResources {
        noCompress += listOf("blend", "py", "pyc", "whl")
    }

    lint {
        abortOnError = false
    }
}

dependencies {
    implementation("androidx.annotation:annotation:1.9.1")
    implementation("androidx.core:core:1.15.0")
}

// Native Blender is built by android/build_apk.ps1 (NDK CMake) and copied into jniLibs.
// This module only packages the already-built shared libraries and runtime assets.
