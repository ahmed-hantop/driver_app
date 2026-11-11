import org.gradle.api.tasks.compile.JavaCompile

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}
subprojects {
    configurations.all {
        resolutionStrategy {
            force("androidx.appcompat:appcompat:1.7.0")
        }
    }
}

subprojects {
    tasks.withType<JavaCompile>().configureEach {
        sourceCompatibility = JavaVersion.VERSION_17.toString()
        targetCompatibility = JavaVersion.VERSION_17.toString()
        options.compilerArgs.addAll(listOf("-Xlint:-options", "-Xlint:-deprecation")) // hide obsolete/deprecation warnings
    }
}

// Patch AGP 8.x namespace requirement for older plugins that omit it
gradle.afterProject {
    extensions.findByType<com.android.build.gradle.LibraryExtension>()?.let { lib ->
        if (lib.namespace == null) {
            lib.namespace = group.toString()
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
