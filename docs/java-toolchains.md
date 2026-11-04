# Java toolchains and the Foojay plugin

[中文](zh-CN/java-toolchains.md) | [English](java-toolchains.md)

A Gradle build can name the JDK it needs, with `java.toolchain`. Gradle then compiles
and tests with a JDK of that version, whichever JDK it runs on itself, and when it
finds none it downloads one, if a settings plugin tells it where from. The usual
plugin is [Foojay Toolchains](https://github.com/gradle/foojay-toolchains),
`org.gradle.toolchains.foojay-resolver-convention`. Gradle describes the feature in
[Toolchains for JVM projects](https://docs.gradle.org/current/userguide/toolchains.html).

The vfox plugin takes no part in it. It sets `GRADLE_HOME` and `PATH`, and a JDK that
Gradle downloads goes to `jdks` in the Gradle user home, `~/.gradle/jdks`, where vfox
does not look. A build with the Foojay plugin therefore needs nothing from the plugin
to work with a Gradle that vfox installed. This page is about what is easy to get
wrong when vfox installs the JDKs as well.

Everything on it ran on Linux (amd64), in a home directory of its own, with vfox
1.0.13, Gradle 9.8.2 and [vfox-java](https://github.com/version-fox/vfox-java) 0.6.5
(Temurin 17.0.21 and 21.0.13). The outputs are the ones the commands printed on
2026-11-04, with `~` for that home directory. What was not run is at the end.

## Recommended setup

- **Let the build be self-contained.** Name the JDK with `java.toolchain`, add the
  Foojay plugin (1.0.0 or later for Gradle 9) to `settings.gradle.kts`, and pin Gradle
  with the wrapper. A build should pass on a machine without vfox, so it should not
  depend on what vfox installed. Gradle's own advice is the same: use toolchains, and
  `JAVA_HOME` only for a default JDK of the machine (the documentation of Gradle 9.8.2,
  2026-11-04).
- **Use vfox for the JDK Gradle runs on,** one recent LTS that your Gradle releases and
  the Foojay plugin accept (Java 17 or later for plugin 1.0.0), and for Gradle itself
  where a project has no wrapper. Do not switch `JAVA_HOME` to match a toolchain.
- **Let Gradle download what it needs.** A JDK is downloaded once and shared by all
  projects, about 500 MB on disk for Temurin 17.0.21.
- **Only when that costs too much** (a slow or blocked network, little disk), let
  Gradle use the JDKs vfox installed: `org.gradle.java.installations.paths`, which
  Gradle documents, or links in `~/.jdks`, see
  [below](#letting-gradle-use-the-jdks-vfox-installed).

## Two JDKs

A Gradle build has two JDKs, and `vfox use java@…` chooses only the first:

- The one **Gradle runs on**. The build scripts and the plugins run on it, the Foojay
  plugin among them. It is `JAVA_HOME`, or the `java` on the `PATH`, see
  [Java](../README.md#java) in the README. (A build can also give the daemon a JDK of
  its own with Daemon JVM criteria, `gradle/gradle-daemon-jvm.properties`, which take
  precedence over `JAVA_HOME`, see Gradle's
  [daemon](https://docs.gradle.org/current/userguide/gradle_daemon.html). This page
  leaves them out.)
- The one **the build uses**, the toolchain. It compiles and tests the project. The
  build names the version, and Gradle finds a matching JDK or downloads one.

A build that wants Java 17, with the Foojay plugin, and a task that prints both:

```kotlin
// settings.gradle.kts
plugins {
    id("org.gradle.toolchains.foojay-resolver-convention") version "1.0.0"
}

rootProject.name = "demo"
```

```kotlin
// build.gradle.kts
plugins {
    java
}

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(17)
    }
}

tasks.register("jvms") {
    val compiler = javaToolchains.compilerFor(java.toolchain)
    doLast {
        println("Gradle runs on:   " + System.getProperty("java.home"))
        println("javac comes from: " + compiler.get().metadata.installationPath)
    }
}
```

With `gradle@9.8.2` and `java@21-tem` selected (`vfox use --global`), and `java@17-tem`
installed too:

```bash
gradle --version
gradle jvms
```

```text
Gradle 9.8.2
Launcher JVM:  21.0.13 (Eclipse Adoptium 21.0.13+9-LTS)
Daemon JVM:    ~/.vfox/cache/java/v-21.0.13+9-tem/java-21.0.13+9-tem (no Daemon JVM specified, using current Java home)
...
Gradle runs on:   ~/.vfox/cache/java/v-21.0.13+9-tem/java-21.0.13+9-tem
javac comes from: ~/.gradle/jdks/eclipse_adoptium-17-amd64-linux.2
```

The first command's output is shortened to the lines that matter. Gradle runs on 21,
and it compiled with a 17 that it downloaded to `~/.gradle/jdks`, although `java@17-tem`
was installed. A download is 185 MB, and Gradle keeps the archive next to the 319 MB
it unpacks to (Temurin 17.0.21). A later build finds the unpacked JDK and does not
download it again. Deleting `~/.gradle/jdks` removes them, and the next build that needs
one downloads it again.

### The Foojay plugin and the Gradle that vfox selects

The Foojay plugin runs inside the Gradle that vfox selected, on the JDK it runs on, so
both choices limit which version of the plugin works. Its
[README](https://github.com/gradle/foojay-toolchains) says that 1.0.0 and later need
Java 17 or later and Gradle 7.6 or later, and that earlier versions need Gradle 7.6
to 8.14.x (2026-11-04). With Gradle 9.8.2 selected, a build that pins 0.10.0 fails as
soon as it asks for a JDK that is not installed:

```text
> Class org.gradle.jvm.toolchain.JvmVendorSpec does not have member field 'org.gradle.jvm.toolchain.JvmVendorSpec IBM_SEMERU'
```

Move the build to 1.0.0, the newest version on 2026-11-04. Of these requirements only
that failure was run, not the Java 17 of 1.0.0.

## Gradle does not look in vfox's directories

Before it downloads anything, Gradle looks for an installed JDK that matches, in a fixed
set of places. Its documentation lists them (2026-11-04): the usual directories of Linux,
macOS and Windows, `JAVA_HOME`, the package managers Asdf-vm, Jabba and SDKMAN!, Maven
toolchain specifications, and IntelliJ IDEA installations, see
[auto-detection](https://docs.gradle.org/current/userguide/toolchains.html#sec:auto_detection).
vfox is not among them, and Gradle will not add it: a request for vfox
([gradle/gradle#29195](https://github.com/gradle/gradle/issues/29195)) was closed as
not planned in 2024-06, with the answer that Gradle does not want more built-in sources
and wants a mechanism for third parties instead
([gradle/gradle#29508](https://github.com/gradle/gradle/issues/29508), still open on
2026-11-04). Of the JDKs vfox installed, Gradle finds only the one it runs on, which is
the one in use. With 21 in use and 17 installed, the `javaToolchains` task
lists only 21:

```bash
gradle -q javaToolchains
```

```text
 + Options
     | Auto-detection:     Enabled
     | Auto-download:      Enabled

 + Eclipse Temurin JDK 21 (21.0.13+9-LTS)
     | Location:           ~/.vfox/cache/java/v-21.0.13+9-tem/java-21.0.13+9-tem
     | Language Version:   21
     | Vendor:             Eclipse Temurin
     | Architecture:       amd64
     | Is JDK:             true
     | Detected by:        Current JVM
```

After `vfox use --global java@17-tem` it lists only 17. That is why the build above
downloaded a 17 of its own. Without the Foojay plugin in `settings.gradle.kts`, the same
build fails instead:

```text
> Cannot find a Java installation on your machine (...) matching: {languageVersion=17, vendor=any vendor, implementation=vendor-specific, nativeImageCapable=false}. Toolchain download repositories have not been configured.
```

`(...)` stands for the operating system and the CPU. The JDK is installed, and Gradle
does not know where.

## Letting Gradle use the JDKs vfox installed

Without this the build still works, with one download for each version that is not the
one in use. To reuse what vfox installed, tell Gradle where it is, in one of two ways.
Both need doing again after you install or uninstall a JDK.

### `org.gradle.java.installations.paths`

This Gradle property is a comma-separated list of JDK directories, the interface Gradle
documents for JDKs it does not detect
([Custom toolchain locations](https://docs.gradle.org/current/userguide/toolchains.html#sec:custom_loc)).
Put it in the
`gradle.properties` of the Gradle user home, `~/.gradle/gradle.properties` (in
`$GRADLE_USER_HOME` when that is set), so that it applies to every build and no
repository carries it. The directories are `~/.vfox/cache/java/v-<version>/java-<version>`,
see [Where the JDK is](https://github.com/version-fox/vfox-java/blob/main/docs/troubleshooting.md#where-the-jdk-is)
in vfox-java's documentation. This prints the line for all the JDKs vfox installed:

```bash
echo "org.gradle.java.installations.paths=$(ls -d ~/.vfox/cache/java/v-*/java-* | paste -sd, -)"
```

```text
org.gradle.java.installations.paths=/home/me/.vfox/cache/java/v-17.0.21+9-tem/java-17.0.21+9-tem,/home/me/.vfox/cache/java/v-21.0.13+9-tem/java-21.0.13+9-tem
```

(`/home/me` stands for your home directory.) With that line in the file and
`~/.gradle/jdks` deleted, `gradle -q javaToolchains` lists the 17 too, as
`Detected by: Gradle property 'org.gradle.java.installations.paths'`, and
`gradle jvms` prints:

```text
Gradle runs on:   ~/.vfox/cache/java/v-21.0.13+9-tem/java-21.0.13+9-tem
javac comes from: ~/.vfox/cache/java/v-17.0.21+9-tem/java-17.0.21+9-tem
```

Nothing is downloaded, and `~/.gradle/jdks` is not created. The paths have to be
absolute: with `~` in the property the 17 was not found, and the build downloaded
another one.

### Links in `~/.jdks`

Gradle also takes the JDKs in `~/.jdks`, IntelliJ IDEA's download folder. The links that
[vfox-java's documentation](https://github.com/version-fox/vfox-java/blob/main/docs/troubleshooting.md#where-the-jdk-is)
makes for IDEA therefore work for Gradle, and need nothing more:

```bash
mkdir -p ~/.jdks
for d in ~/.vfox/cache/java/v-*/java-*; do ln -sfn "$d" ~/.jdks/"$(basename "$d")"; done
```

With them, `gradle -q javaToolchains` lists the 17 as `Detected by: IntelliJ`, and
`gradle jvms` prints the same two lines as above: it compiles with the 17 of vfox, and
nothing is downloaded. Delete the links of the JDKs you uninstall.

## What was not run

Windows and macOS. A Gradle other than 9.8.2. JDKs other than Temurin. Daemon JVM
criteria. The Java 17 that the Foojay plugin 1.0.0 needs, which is its README's word.
