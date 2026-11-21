allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Hardened fixes for broken/outdated plugins from pub.dev.
// coinbase_wallet_sdk 1.0.10 ships without consumer-rules.pro and pins compileSdk 31
// (AAR metadata of its androidx deps requires >= 34). Re-apply on every configure so a
// fresh `flutter pub get` cannot reintroduce the failures.
subprojects {
    if (project.name == "coinbase_wallet_sdk") {
        val consumerRules = project.file("consumer-rules.pro")
        if (!consumerRules.exists()) {
            consumerRules.writeText(
                "# Consumer ProGuard rules for coinbase_wallet_sdk (auto-created).\n"
            )
        }
        val proguardRules = project.file("proguard-rules.pro")
        if (!proguardRules.exists()) {
            proguardRules.writeText("# ProGuard rules for coinbase_wallet_sdk (auto-created).\n")
        }

        // Strip imperative KGP apply so Flutter's Built-in Kotlin check stays quiet;
        // Flutter re-applies KGP at runtime when android.builtInKotlin=false.
        val buildGradle = project.file("build.gradle")
        if (buildGradle.exists()) {
            val original = buildGradle.readText()
            val patched = original
                .lineSequence()
                .filter { it.trim() != "apply plugin: 'kotlin-android'" }
                .joinToString("\n")
                .replace("compileSdkVersion 31", "compileSdk = 37")
            if (patched != original) {
                buildGradle.writeText(patched + if (original.endsWith("\n")) "\n" else "")
            }
        }

        afterEvaluate {
            val androidExt = extensions.findByName("android")
            if (androidExt != null) {
                try {
                    val compileSdkProp = androidExt.javaClass.methods
                        .firstOrNull { it.name == "setCompileSdk" && it.parameterCount == 1 }
                    // AGP Groovy DSL: compileSdk setter takes Integer/int
                    compileSdkProp?.invoke(androidExt, 37)
                } catch (_: Exception) {
                    // Best-effort; file-level compileSdk = 37 above is the primary fix.
                }
            }
        }
    }

    if (project.name == "package_info_plus") {
        val buildGradle = project.file("build.gradle")
        if (buildGradle.exists()) {
            val original = buildGradle.readText()
            val patched = original
                .lineSequence()
                .filter { it.trim() != "apply plugin: 'kotlin-android'" }
                .joinToString("\n")
            if (patched != original) {
                buildGradle.writeText(patched + if (original.endsWith("\n")) "\n" else "")
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
