plugins {
    kotlin("multiplatform") version "2.0.21"
    kotlin("plugin.serialization") version "2.0.21"
}

group = "com.voice"
version = "1.0-SNAPSHOT"

repositories {
    mavenCentral()
}

kotlin {
    // macOS ARM64 target (M1/M2/M3/M4)
    macosArm64("macos") {
        binaries {
            executable {
                entryPoint = "com.voice.cli.main"
            }
        }

        compilations["main"].cinterops {
            create("KissFFT") {
                defFile = file("src/nativeInterop/cinterop/KissFFT.def")
            }
            create("OnnxRuntime") {
                defFile = file("src/nativeInterop/cinterop/OnnxRuntime.def")
            }
            create("Accelerate") {
                defFile = file("src/nativeInterop/cinterop/Accelerate.def")
            }
            create("CopyHelper") {
                defFile = file("src/nativeInterop/cinterop/CopyHelper.def")
            }
        }
    }

    sourceSets {
        val commonMain by getting {
            dependencies {
                implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.6.3")
            }
        }
        val macosMain by getting {
            dependencies {
                implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.1")
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
