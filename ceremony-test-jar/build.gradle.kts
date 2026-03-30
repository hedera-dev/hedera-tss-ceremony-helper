plugins {
    java
    application
}

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(21)
    }
}

repositories {
    mavenCentral()
}

dependencies {
    implementation(platform("software.amazon.awssdk:bom:2.31.46"))
    implementation("software.amazon.awssdk:s3")
    implementation("org.slf4j:slf4j-nop:2.0.16")
}

application {
    mainClass = "com.hedera.ceremony.test.S3PermissionTest"
}

tasks.jar {
    archiveBaseName = "ceremony-s3-permission-test"
    archiveVersion = ""
    archiveClassifier = ""

    manifest {
        attributes("Main-Class" to "com.hedera.ceremony.test.S3PermissionTest")
    }

    // Build a fat jar by including all runtime dependencies.
    from(configurations.runtimeClasspath.get().map { if (it.isDirectory) it else zipTree(it) })
    duplicatesStrategy = DuplicatesStrategy.EXCLUDE
}
