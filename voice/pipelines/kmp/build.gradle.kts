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
    macosArm64("macosArm64") {
        binaries {
            executable {
                entryPoint = "com.voice.cli.main"
            }
            // Framework for Swift consumption
            framework {
                baseName = "VoicePipeline"
                isStatic = false
            }
        }

        compilations["main"].cinterops {
            create("KissFFT") {
                defFile = file("src/nativeInterop/cinterop/KissFFT_arm64.def")
            }
            create("OnnxRuntime") {
                defFile = file("src/nativeInterop/cinterop/OnnxRuntime_arm64.def")
            }
            create("Accelerate") {
                defFile = file("src/nativeInterop/cinterop/Accelerate.def")
            }
            create("CopyHelper") {
                defFile = file("src/nativeInterop/cinterop/CopyHelper_arm64.def")
            }
        }
    }

    // macOS x86_64 target (Intel)
    macosX64("macosX64") {
        binaries {
            executable {
                entryPoint = "com.voice.cli.main"
            }
            // Framework for Swift consumption
            framework {
                baseName = "VoicePipeline"
                isStatic = false
            }
        }

        compilations["main"].cinterops {
            create("KissFFT") {
                defFile = file("src/nativeInterop/cinterop/KissFFT_x86_64.def")
            }
            create("OnnxRuntime") {
                defFile = file("src/nativeInterop/cinterop/OnnxRuntime_x86_64.def")
            }
            create("Accelerate") {
                defFile = file("src/nativeInterop/cinterop/Accelerate.def")
            }
            create("CopyHelper") {
                defFile = file("src/nativeInterop/cinterop/CopyHelper_x86_64.def")
            }
        }
    }

    // Configure source sets with hierarchy
    sourceSets {
        val commonMain by getting {
            dependencies {
                implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.6.3")
            }
        }

        // Shared native source set for all macOS targets
        val nativeMacosMain by creating {
            dependsOn(commonMain)
            dependencies {
                implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.1")
            }
        }

        val macosArm64Main by getting {
            dependsOn(nativeMacosMain)
        }

        val macosX64Main by getting {
            dependsOn(nativeMacosMain)
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

// Task to create universal XCFramework
tasks.register("createUniversalXCFramework") {
    dependsOn("macosArm64Binaries", "macosX64Binaries")

    doLast {
        val buildDir = layout.buildDirectory.get().asFile
        val arm64Framework = file("$buildDir/bin/macosArm64/releaseFramework/VoicePipeline.framework")
        val x86_64Framework = file("$buildDir/bin/macosX64/releaseFramework/VoicePipeline.framework")
        val outputDir = file("$buildDir/xcframework")
        val xcframework = file("$outputDir/VoicePipeline.xcframework")

        // Clean previous output
        delete(xcframework)
        outputDir.mkdirs()

        // Create XCFramework using xcodebuild
        exec {
            commandLine(
                "xcodebuild", "-create-xcframework",
                "-framework", arm64Framework.absolutePath,
                "-framework", x86_64Framework.absolutePath,
                "-output", xcframework.absolutePath
            )
        }

        println("Created universal XCFramework at: ${xcframework.absolutePath}")
    }
}
