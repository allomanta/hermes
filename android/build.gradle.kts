import com.android.build.api.dsl.ApplicationExtension
import com.android.build.api.variant.LibraryAndroidComponentsExtension

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

project(":fcm_shared_isolate") {
    plugins.withId("com.android.library") {
        extensions.configure<LibraryAndroidComponentsExtension> {
            finalizeDsl {
                // fcm_shared_isolate 0.2.0 hardcodes API 33, below its AndroidX requirements.
                it.compileSdk = project(":app").extensions.getByType<ApplicationExtension>().compileSdk
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
