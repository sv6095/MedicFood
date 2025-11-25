allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.set(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.set(newSubprojectBuildDir)
}

subprojects {
    afterEvaluate {
        if (plugins.hasPlugin("com.android.library") || plugins.hasPlugin("com.android.application")) {
            try {
                configure<com.android.build.gradle.BaseExtension> {
                    if (namespace.isNullOrEmpty()) {
                        namespace = project.group?.toString() 
                            ?: "com.example.${project.name.replace("-", "_")}"
                        println("Set namespace for ${project.name}: $namespace")
                    }
                }
            } catch (e: Exception) {
                println("Warning: Could not set namespace for ${project.name}: ${e.message}")
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
