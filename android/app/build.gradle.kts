plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

// BEacon's 5x1 restyle and state bridge are shared with the iPhone app: copy them out of
// BEep/BEacon.swift at build time so both apps always look and behave the same.
val webScripts = layout.buildDirectory.dir("generated/webScripts")
val extractWebScripts by tasks.registering {
    val swift = rootProject.file("../BEep/BEacon.swift")
    inputs.file(swift); outputs.dir(webScripts)
    doLast {
        val source = swift.readText()
        val dir = webScripts.get().asFile.resolve("web").apply { mkdirs() }
        for (name in listOf("theme", "bridge")) {
            val start = source.indexOf("private static let $name = \"\"\"")
            check(start >= 0) { "BEacon.swift has no $name script" }
            val body = source.substring(source.indexOf('\n', start) + 1, source.indexOf("\"\"\"", source.indexOf('\n', start)))
            dir.resolve("$name.js").writeText(body.trimIndent().replace("\\\"", "\"").replace("\\\\", "\\"))
        }
    }
}

android {
    namespace = "com.jiborevival.beep"
    compileSdk = 35
    defaultConfig {
        applicationId = "com.jiborevival.beep"
        minSdk = 26
        targetSdk = 35
        versionCode = 10
        versionName = "1.7"
    }
    flavorDimensions += "channel"
    productFlavors {
        create("stable") { dimension = "channel"; resValue("string", "app_name", "BEep") }
        create("beta") {
            dimension = "channel"
            applicationIdSuffix = ".beta"
            resValue("string", "app_name", "BEep BETA")
            // Every CI run is a new beta build.
            versionCode = (System.getenv("GITHUB_RUN_NUMBER") ?: "1").toInt()
        }
    }
    signingConfigs {
        create("release") {
            // CI writes the keystore from repository secrets; local builds fall back to debug signing.
            val store = System.getenv("BEEP_KEYSTORE")
            if (store != null) {
                storeFile = file(store)
                storePassword = System.getenv("BEEP_KEYSTORE_PASSWORD")
                keyAlias = "beep"
                keyPassword = System.getenv("BEEP_KEYSTORE_PASSWORD")
            }
        }
    }
    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = if (System.getenv("BEEP_KEYSTORE") != null) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
        }
    }
    sourceSets["main"].assets.srcDir(webScripts)
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = "17" }
    packaging { resources.excludes += setOf("META-INF/versions/9/OSGI-INF/MANIFEST.MF") }
}
tasks.named("preBuild") { dependsOn(extractWebScripts) }

dependencies {
    implementation("androidx.webkit:webkit:1.12.1")
    implementation("com.github.mwiede:jsch:0.2.21")
    testImplementation("junit:junit:4.13.2")
}
