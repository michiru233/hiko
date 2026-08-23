import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// local.properties（不进 git）：sdk.dir / flutter.sdk / hiko 发布签名信息
val keystoreProps = Properties().apply {
    val f = rootProject.file("local.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

android {
    namespace = "top.voicehub.hiko"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "top.voicehub.hiko"
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
            val ksPath = keystoreProps.getProperty("hiko.keystore.path")
            if (ksPath != null) {
                storeFile = file(ksPath)
                storePassword = keystoreProps.getProperty("hiko.keystore.password")
                keyAlias = keystoreProps.getProperty("hiko.key.alias")
                keyPassword = keystoreProps.getProperty("hiko.key.password")
            }
        }
    }

    buildTypes {
        release {
            // 发布签名：keystore 在 ~/.hiko/hiko-release.jks，凭据存 local.properties（git 忽略）。
            // 未配置时回退 debug 签名（仅本地开发兜底，Release 发版必须有正式签名）。
            signingConfig = if (keystoreProps.getProperty("hiko.keystore.path") != null) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // SAF 目录/文件操作（HikoPlugin）
    implementation("androidx.documentfile:documentfile:1.0.1")
    // FileProvider（导出分享 library.json）
    implementation("androidx.core:core-ktx:1.13.1")
    testImplementation("junit:junit:4.13.2")
}

flutter {
    source = "../.."
}
