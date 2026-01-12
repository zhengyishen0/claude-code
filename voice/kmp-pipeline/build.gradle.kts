plugins {
    kotlin("multiplatform") version "2.0.21"
    kotlin("plugin.serialization") version "2.0.21"
}

group = "com.voice.pipeline"
version = "1.0-SNAPSHOT"

repositories {
    mavenCentral()
}

kotlin {
    // macOS ARM64 target (M1/M2/M3/M4)
    macosArm64("macos") {
        binaries {
            executable {
                entryPoint = "com.voice.pipeline.main"
            }
        }

        // Using platform.CoreML, platform.AVFoundation, platform.Accelerate
        // which are built-in to Kotlin/Native for macOS
    }

    sourceSets {
        val macosMain by getting {
            dependencies {
                implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.1")
                implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.6.3")
            }
        }
    }
}

// Allow deprecation warnings for Kotlin/Native (needed for MLMultiArray.initWithShape)
tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinNativeCompile>().configureEach {
    compilerOptions {
        allWarningsAsErrors.set(false)
        freeCompilerArgs.addAll("-Xsuppress-deprecated-jvm-target-warning")
    }
}
