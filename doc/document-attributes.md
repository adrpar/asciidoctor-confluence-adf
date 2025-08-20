# Setting Document Attributes

In this project, we use document attributes to configure various aspects of the conversion process and macros.

## Document Attributes vs. Environment Variables

Document attributes are the preferred way to configure the converter and macros, as they follow Asciidoctor's standard approach. However, for backward compatibility, environment variables are still supported as a fallback.

### Important Document Attributes

The following document attributes are supported:

- `jira-base-url`: The base URL of your Jira instance
- `confluence-base-url`: The base URL of your Confluence instance
- `confluence-api-token`: The API token for authentication
- `confluence-user-email`: The email for authentication

## Setting Document Attributes

### In AsciiDoc Files

You can set document attributes in your AsciiDoc file header:

```adoc
= Document Title
:jira-base-url: https://jira.example.com
:confluence-base-url: https://confluence.example.com
:confluence-api-token: your-api-token
:confluence-user-email: your.email@example.com

Your document content starts here...
```

> **Warning:**  
> Be careful about blank lines in your AsciiDoc document header. Any blank line signals the end of the header, which means document attributes defined after that blank line will not be processed correctly.

### Using Command Line

You can also set document attributes via the command line:

```bash
asciidoctor -a jira-base-url=https://jira.example.com \
            -a confluence-base-url=https://confluence.example.com \
            -a confluence-api-token=your-token \
            -a confluence-user-email=your.email@example.com \
            -r ./src/jira_macro.rb yourfile.adoc
```

This approach is particularly useful for setting sensitive information like API tokens that you don't want to commit to version control.
