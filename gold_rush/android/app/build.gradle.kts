import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releasePropertiesFile = rootProject.file("key.properties")
val releaseProperties = Properties().apply {
    if (releasePropertiesFile.isFile) {
        releasePropertiesFile.reader(Charsets.UTF_8).use { load(it) }
    }
}

val releaseEnvironment = mapOf(
    "storeFile" to providers.environmentVariable("GOLD_RUSH_RELEASE_STORE_FILE").orNull,
    "storePassword" to providers.environmentVariable("GOLD_RUSH_RELEASE_STORE_PASSWORD").orNull,
    "keyAlias" to providers.environmentVariable("GOLD_RUSH_RELEASE_KEY_ALIAS").orNull,
    "keyPassword" to providers.environmentVariable("GOLD_RUSH_RELEASE_KEY_PASSWORD").orNull,
)
val useReleaseEnvironment = releaseEnvironment.values.any { !it.isNullOrEmpty() }
val releaseSigning = releaseEnvironment.mapValues { (property, value) ->
    if (useReleaseEnvironment) value else releaseProperties.getProperty(property)
}
val missingReleaseProperties = releaseSigning.filterValues { it.isNullOrEmpty() }.keys
val releaseStoreFile = releaseSigning["storeFile"]?.takeIf { it.isNotEmpty() }
    ?.let { rootProject.file(it) }
val useDebugSigning = !useReleaseEnvironment && !releasePropertiesFile.isFile &&
    providers.environmentVariable("GOLD_RUSH_ALLOW_DEBUG_SIGNING").orNull == "true"

if (!useDebugSigning) {
    val checkReleaseSigning = tasks.register("checkReleaseSigning") {
        doLast {
            check(missingReleaseProperties.isEmpty()) {
                "Release signing requires android/key.properties or the GOLD_RUSH_RELEASE_* " +
                    "environment variables. Missing: ${missingReleaseProperties.joinToString()}"
            }
            check(releaseStoreFile?.isFile == true) {
                "Release signing keystore was not found. Check the configured storeFile."
            }
        }
    }
    tasks.matching { it.name == "preReleaseBuild" }.configureEach {
        dependsOn(checkReleaseSigning)
    }
}

android {
    namespace = "com.goldrush.gold_rush"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.goldrush.gold_rush"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            storeFile = releaseStoreFile
            storePassword = releaseSigning["storePassword"]
            keyAlias = releaseSigning["keyAlias"]
            keyPassword = releaseSigning["keyPassword"]
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (useDebugSigning) "debug" else "release")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
