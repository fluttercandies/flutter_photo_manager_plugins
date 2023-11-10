---
title: "Configuring Java Version in photo_manager"
weight: 1
---

To ensure compatibility with older versions of AGP/flutter SDK, `photo_manager` supports configuring the project's Java version through configuration files, environment variables, and other methods.

It looks for the Java version in the following order:

1. Configuration in `gradle.properties` using the `java.version` property.
   The value should be in the format of a Java version number, such as `1.8`, `11`, `17`, `21`, etc.
2. Using the `JAVA_HOME` environment variable, which should point to the installation path of the JDK.
   Typically, the Java executable is located at `$JAVA_HOME/bin/java`.
3. Configuration in `gradle.properties` using the `java.home` property.
4. Reading the runtime property `java.home` of the JDK.
5. If none of the above is found, it defaults to using `JavaVersion.current()`.

Steps 4 and 5 should use the JDK configured in the Gradle settings, which is usually the same.

For example, if you configure `java.version` in `gradle.properties` as `17`,
it is equivalent to modifying the following properties in the `build.gradle` of `photo_manager`:

```groovy
android {
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }
}
