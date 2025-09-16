# Integrating Asciidoctor Confluence ADF Converter with Gradle

This guide explains how to run the Asciidoctor Confluence ADF converter using a Gradle build file. It covers the necessary plugins, dependencies, and configuration steps, with placeholders for project-specific values.

## Prerequisites
- Java (JDK 8+)
- Gradle (6.0+ recommended)

## Example Gradle Build File

Below is a template for integrating the converter. Replace all placeholder values (e.g., `<YOUR_ADOC_FILE>`, `<YOUR_ADF_CONVERTER_PATH>`, `<YOUR_CONFLUENCE_BASE_URL>`, etc.) with your actual project settings.

```groovy
plugins {
    id 'org.asciidoctor.jvm.convert' version '4.0.4'
    id 'org.asciidoctor.jvm.gems' version '4.0.4'
}

repositories {
    mavenCentral() // For Java libraries
    ruby.gems()    // For Ruby gems
}

asciidoctor {
    sourceDir = file('.')
    sources {
        include '<YOUR_ADOC_FILE>.adoc'
    }
    outputDir = file('build/')
}

dependencies {
    asciidoctorGems 'rubygems:fastimage:2.4.0'
}

import org.asciidoctor.gradle.jvm.AsciidoctorTask

tasks.withType(AsciidoctorTask).configureEach {
    dependsOn tasks.named('asciidoctorGemsPrepare')
    withGemPath(
        layout.buildDirectory.dir('.asciidoctorGems').map { it.asFile },
        'asciidoctorGemsPrepare'
    )
}

tasks.register('asciidoctorAdf', org.asciidoctor.gradle.jvm.AsciidoctorTask) {
    sourceDir = file('.')
    sources {
        include '<YOUR_ADOC_FILE>.adoc'
    }
    outputDir = file('build/')

    outputOptions {
        backends = ['adf'] // Use the ADF backend
    }

    asciidoctorj {
        requires 'fastimage'
        requires(new File('<YOUR_ADF_CONVERTER_PATH>/src/adf_extensions.rb').absolutePath)
    }

    attributes(
        // Preferred unified base URL (works for Jira links & Confluence API)
        'atlassian-base-url': System.getenv('ATLASSIAN_BASE_URL') ?: System.getenv('CONFLUENCE_BASE_URL') ?: '<YOUR_ATLASSIAN_SITE_BASE_URL>',
        'confluence-api-token': System.getenv('CONFLUENCE_API_TOKEN') ?: '<YOUR_CONFLUENCE_API_TOKEN>',
        'confluence-user-email': System.getenv('CONFLUENCE_USER_EMAIL') ?: '<YOUR_CONFLUENCE_USER_EMAIL>'
        // Deprecated (still accepted until removal): 'jira-base-url', 'confluence-base-url'
    )
}
```

## Key Points
- **Plugins**: Use both `org.asciidoctor.jvm.convert` and `org.asciidoctor.jvm.gems`.
- **Dependencies**: Add the `fastimage` gem for image dimension detection.
- **Backend**: Set `backends = ['adf']` to use the ADF converter.
- **Attributes**: Pass Confluence credentials as document attributes, preferably via environment variables for security.
- **Extension Loading**: Use the `requires` directive to load the ADF converter and macros.

## Security Note
Do **not** hardcode sensitive credentials in your build file. Use environment variables and Gradle's attribute passing to keep secrets out of source control.

## Further Reading
- [Asciidoctor Gradle Plugin Documentation](https://asciidoctor.github.io/asciidoctor-gradle-plugin/)
- [Document Attributes](./document-attributes.md)

---

For more details on document attributes and configuration, see [document-attributes.md](./document-attributes.md).
