import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Local credentials are ignored; CI can supply all four values through secrets.
val releaseKeys = Properties().apply {
    val localKeys = rootProject.file("key.properties")
    if (localKeys.isFile) localKeys.reader(Charsets.UTF_8).use { load(it) }
}
val releaseEnvironment = mapOf(
    "storeFile" to "RECEIPT_READER_STORE_FILE",
    "storePassword" to "RECEIPT_READER_STORE_PASSWORD",
    "keyAlias" to "RECEIPT_READER_KEY_ALIAS",
    "keyPassword" to "RECEIPT_READER_KEY_PASSWORD",
)
// Never combine partial CI credentials with an unrelated local signing identity.
if (releaseEnvironment.values.any { System.getenv(it) != null }) {
    releaseKeys.clear()
    releaseEnvironment.forEach { (property, variable) ->
        System.getenv(variable)?.let { releaseKeys.setProperty(property, it) }
    }
}
val releaseSigningReady = releaseEnvironment.keys.all {
    !releaseKeys.getProperty(it).isNullOrBlank()
}

android {
    namespace = "fi.juhonis.receipt_reader"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Stable identity for retained phone installations and signed updates.
        applicationId = "fi.juhonis.receipt_reader"
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
        create("receiptRelease") {
            if (releaseSigningReady) {
                storeFile = rootProject.file(releaseKeys.getProperty("storeFile"))
                storePassword = releaseKeys.getProperty("storePassword")
                keyAlias = releaseKeys.getProperty("keyAlias")
                keyPassword = releaseKeys.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("receiptRelease")
            proguardFiles("proguard-rules.pro")
        }
    }
}

tasks.matching { it.name == "preReleaseBuild" }.configureEach {
    doFirst {
        check(releaseSigningReady) {
            "Release signing is required. Configure android/key.properties or all " +
                "RECEIPT_READER signing environment variables; see docs/releases.md."
        }
        check(rootProject.file(releaseKeys.getProperty("storeFile")).isFile) {
            "Release keystore is missing. Restore the permanent key; do not generate a replacement."
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

dependencies {
    // Approved Android engine; bundle the Latin model for first-run offline use.
    implementation("com.google.mlkit:text-recognition:16.0.1")
}
