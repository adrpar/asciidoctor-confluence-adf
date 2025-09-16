# Asciidoctor Confluence ADF Converter

## Overview

This converter transforms AsciiDoc documents into Atlassian Document Format (ADF), enabling seamless integration with Atlassian tools like Confluence.

> ⚠️ **CRITICAL WARNING** ⚠️
> 
> Asciidoctor document headers **MUST NOT** contain blank lines between attribute declarations. 
> This is especially important for included files that set attributes such as `:imagesdir:`.
>
> If blank lines are present, attribute processing may fail silently, causing features like image resolution to break.
>
> **Example of correct header format:**
> ```asciidoc
> = Document Title
> :toc-title: Table of Contents
> :imagesdir: images
> :icons: font
> // No blank lines between attributes!
> ```

## Features

- Converts AsciiDoc elements (e.g., paragraphs, lists, tables) into ADF-compliant JSON.
- Supports Confluence-specific macros (e.g., anchors, TOC).
- Includes a Jira inline macro for convenient issue linking.
- Includes a Jira issues table macro to embed issue query results.
- Includes an Atlassian mention macro for user mentions, with Confluence Cloud user lookup.
- Supports Appfox Workflows for Confluence macros for metadata, approvers, and change tables.
- Supports Confluence Table of Contents (TOC) macro via `:toc:`.
- Automatically handles inline formatting (e.g., bold, italic, links).
- Generates structured JSON for use in Confluence or other Atlassian tools.
- Provides bidirectional conversion between AsciiDoc and Confluence content.

### Logging & Build Failure Behavior

All extension and converter diagnostics now route through the Asciidoctor logging framework (Asciidoctor::LoggerManager). This means the Asciidoctor CLI option `--failure-level` (or `-a failure-level=` attribute) will correctly cause the process to exit with a non‑zero status when messages at or above the configured severity are emitted.

Examples:

```bash
# Fail the build on any warning or error produced by the extensions
asciidoctor --failure-level=WARN -r ./src/adf_extensions.rb -b adf yourfile.adoc

# Fail only on errors (default behavior if not specified)
asciidoctor --failure-level=ERROR -r ./src/adf_extensions.rb -b adf yourfile.adoc
```

Internally, helpers in `adf_logger.rb` map to the Asciidoctor logger (`fatal`, `error`, `warn`, `info`, `debug`). If Asciidoctor isn’t loaded (e.g., during isolated script execution), they fallback to simple STDERR/STDOUT output so local scripts still show diagnostics.

If you previously saw that warnings never caused a non‑zero exit code, make sure you’re using the updated extensions (require `adf_extensions.rb` or the specific macro file) and pass `--failure-level=warn` (case-insensitive) to enforce stricter CI behavior.

> **Note:**  
> This project has been created with the support of large language models (LLMs).  
> As a result, some code may reflect an iterative or "vibe coding" style.  
> The codebase will be gradually cleaned up and refactored for clarity and maintainability.

## Configuration

This project uses document attributes for configuration. Document attributes can be set:
- In your AsciiDoc file header
- Via command line with `-a attribute=value`

See [document-attributes.md](./doc/document-attributes.md) for detailed documentation.

> **Warning:**  
> Be careful about blank lines in your AsciiDoc document header. Any blank line signals the end of the header, which means document attributes defined after that blank line will not be processed correctly.

---

## Macro Support

This converter provides native support for several Confluence and Appfox macros, allowing you to author and maintain workflow-driven documentation in AsciiDoc and publish it to Confluence with all workflow metadata and tables intact.

### Jira Inline Macro

This project includes a **Jira inline macro** for easily linking to Jira issues from your AsciiDoc content.

**Usage:**
```adoc
jira:ISSUE-123[]
jira:ISSUE-456[Custom link text]
```
- The macro will render as a link to the specified Jira issue.
- You can optionally provide custom link text in the brackets.

Set the `jira-base-url` document attribute to control the link target:

```adoc
= Document Title
:jira-base-url: https://jira.example.com

See jira:PROJECT-123[] for details.
```

You can also set it via command line:
```bash
asciidoctor -a jira-base-url=https://jira.example.com -r ./src/jira_macro.rb yourfile.adoc
```

---

### Jira Issues Table Macro

The **Jira issues table macro** allows you to embed query results from Jira directly into your document as a table.

**Usage:**
```adoc
jiraIssuesTable::['project = "DEMO"', fields='key,summary,description,status']
```

**Parameters:**
- The macro target (between :: and [) is the JQL query to execute
- The `fields` attribute specifies which Jira fields to include in the table

**Example with more options:**
```adoc
jiraIssuesTable::['project = "PRQ" AND status = Review', fields='key,summary,description,customfield_10984,status']
```

The macro will:
1. Query Jira using the provided JQL
2. Format the results in a table with the specified fields as columns
3. Automatically format rich content in fields like description (including bullet lists, bold text, etc.)
4. Create links to the Jira issues

#### Field Selection & Resolution (New Behavior)

You can specify Jira fields using either:
- The canonical Jira field ID (e.g. `summary`, `description`, `status`, `customfield_12345`)
- The human-readable Jira field display name exactly as shown in Jira (case-insensitive; trailing whitespace ignored)

The macro now fetches field metadata first and resolves display names to field IDs automatically. This removes the need to “hunt” for `customfield_XXXXX` identifiers when composing documents.

If you specify a field that does not exist:
- An error is logged
- A reference list of available fields (ID → Name) is printed once to help you pick the correct names
- A placeholder paragraph is rendered instead of the table so the build fails visibly but gracefully

#### Quoting Field Names Containing Commas

Some field display names may contain commas. You can include these by quoting the field name:

```adoc
jiraIssuesTable::['project = "DEMO"', fields='key,Summary,"Complex, Field Name","Another \'Quoted\' Field"']
```

Rules:
- Use either single `'` or double `"` quotes around a field containing commas
- Inside a single-quoted token, escape a literal single quote by doubling it (`''`)
- Inside a double-quoted token, escape a literal double quote using standard CSV doubling (`""`), though this is rarely needed
- Whitespace around tokens is trimmed

#### Custom Fields
You can always bypass name resolution by specifying the raw Jira custom field ID directly:
```adoc
jiraIssuesTable::['project = "DEMO"', fields='key,summary,customfield_12345,status']
```

If the display name for a custom field is successfully resolved, its human-readable name is used in the table header; otherwise the raw ID is shown.

#### Error Example (Unknown Field)

```adoc
jiraIssuesTable::['project = "DEMO"', fields='key,summary,NotARealField,status']
```
Will log:
```
ERROR: Unknown Jira field name(s): "NotARealField". Use an exact field name as shown above or the custom field id (e.g. customfield_12345).
```
and emit a placeholder paragraph.

**Document Attributes:**
- `jira-base-url`: Base URL of your Jira instance
- `confluence-api-token`: API token for Jira authentication
- `confluence-user-email`: Email for Jira authentication

Set these document attributes either in your AsciiDoc file header or via command line:

```bash
asciidoctor -a jira-base-url=https://jira.example.com \
            -a confluence-api-token=your-token \
            -a confluence-user-email=your.email@example.com \
            -r ./src/jira_macro.rb yourfile.adoc
```

**Note:** The converter handles complex formatting in Jira fields differently based on the backend:
- With HTML backend: Renders description fields with AsciiDoc formatting preserved
- With ADF backend: Converts description formatting to proper ADF nodes (bullet lists, bold text, etc.)

---

### Atlassian Mention Inline Macro

This project also includes an **Atlassian mention macro** for user mentions, which can resolve user IDs from Confluence Cloud.

**Usage:**
```adoc
atlasMention:Adrian_Partl[]
```
- The macro will look up the user "Adrian Partl" in Confluence Cloud and insert an ADF mention node (when using the `adf` backend).
- For non-ADF backends (e.g., HTML), it will render as plain text `@Adrian Partl`.

Set the following document attributes for user lookup:
- `confluence-base-url`
- `confluence-api-token`
- `confluence-user-email`

```bash
asciidoctor -a confluence-base-url=https://yourcompany.atlassian.net \
            -a confluence-api-token=your-api-token \
            -a confluence-user-email=your.email@example.com \
            -r ./src/jira_macro.rb yourfile.adoc
```

---

### Appfox Workflows for Confluence Macros

[Appfox Workflows for Confluence](https://www.appfox.io/products/workflows-confluence/) is a popular Confluence Cloud app that enables teams to add document workflows, approvals, and metadata to Confluence pages.

This converter provides native support for Appfox Workflows macros:

#### Metadata Macro

Use `appfoxWorkflowMetadata:KEYWORD[]` to insert workflow metadata fields such as status, approvers, expiry date, etc.

**Example:**
```adoc
appfoxWorkflowMetadata:status[]
appfoxWorkflowMetadata:approvers[]
```

#### Approvers Table Macro

Use `workflowApproval:all[]` for all approvers, or `workflowApproval:latest[]` for latest approvals.

**Example:**
```adoc
workflowApproval:all[]
workflowApproval:latest[]
```

#### Change Table Macro

Use `workflowChangeTable:all[]` to insert the document control/change table (old `workflowChangeTable:[]` still works but defaults to `all`).

**Example:**
```adoc
workflowChangeTable:all[]
```

These macros are automatically converted to the correct ADF JSON for Appfox Workflows macros when using the `adf` backend.  
If you use a non-ADF backend (e.g., HTML), the macro will render as plain text for easy editing.

---

### Table of Contents (TOC) Macro

You can insert a Confluence-style Table of Contents macro into your document using:

```adoc
:toc:
```

This will be converted to a Confluence TOC macro in the ADF output.

---

## Installation

To install the necessary dependencies, run the following command:

```bash
bundle install
```

## Usage

### Using in a Ruby Application

To use the Asciidoctor ADF converter, include it in your Ruby application and specify the `adf` backend. Here's a basic example:

```ruby
require 'asciidoctor'
require_relative 'src/adf_converter'

# Convert an AsciiDoc document to ADF JSON
adoc = <<~ADOC
= Document Title

:toc:

This is a paragraph.

== Section Title

* Item 1
* Item 2

|===
|Cell 1 |Cell 2
|Cell 3 |Cell 4
|===

atlasMention:Adrian_Partl[]
jira:ISSUE-123[]
appfoxWorkflowMetadata:status[]
workflowApproval:all[]
workflowChangeTable:all[]

jiraIssuesTable::['project = "DEMO"', fields='key,summary,status']
ADOC

output = Asciidoctor.convert(adoc, backend: 'adf', safe: :safe, header_footer: false)
puts output
```

### Running Directly with Asciidoctor

You can also run the converter directly from the command line using the `asciidoctor` command:

```bash
asciidoctor --trace -r ./src/adf_converter.rb -b adf ./docs/asciidoc/arc42.adoc
```

This command:
- Loads the `AdfConverter` from the `src/adf_converter.rb` file.
- Specifies the `adf` backend with `-b adf`.
- Converts the input AsciiDoc file (`./docs/asciidoc/arc42.adoc`) into ADF JSON.

---

## Extension Loading

By default, the `adf_extensions.rb` file loads **both** the ADF converter and all macros, including Jira, Atlassian mention, and Appfox Workflows macros, so you can use them together with a single `-r` option:

```bash
asciidoctor -r ./src/adf_extensions.rb -b adf yourfile.adoc
```

If you only want to use the macros (for example, with the standard HTML backend), you can load just the macro file(s):

```bash
asciidoctor -r ./src/jira_macro.rb -a jira-base-url=https://jira.example.com yourfile.adoc
asciidoctor -r ./src/appfox_workflows_macro.rb yourfile.adoc

# For documentation on setting document attributes, see doc/document-attributes.md
```

> **Note:**  
> `adf_extensions.rb` registers both the ADF converter and all macros for convenience.  
> If you only need the macros, require the relevant macro file(s) directly.

---

## Supported Elements

### Paragraphs
AsciiDoc:
```adoc
This is a paragraph.
```

ADF Output:
```json
{
  "type": "paragraph",
  "content": [
    {
      "type": "text",
      "text": "This is a paragraph."
    }
  ]
}
```

### Sections
AsciiDoc:
```adoc
== Section Title
This is a section.
```

ADF Output:
```json
{
  "type": "heading",
  "attrs": { "level": 2 },
  "content": [
    {
      "type": "text",
      "text": "Section Title"
    },
    {
      "type": "inlineExtension",
      "attrs": {
        "extensionType": "com.atlassian.confluence.macro.core",
        "extensionKey": "anchor",
        "parameters": {
          "macroParams": {
            "": { "value": "_section_title" },
            "legacyAnchorId": { "value": "LEGACY-_section_title" },
            "_parentId": { "value": "normalized-uuid" }
          },
          "macroMetadata": {
            "macroId": { "value": "normalized-uuid" },
            "schemaVersion": { "value": "1" },
            "title": "Anchor"
          }
        },
        "localId": "normalized-uuid"
      }
    }
  ]
},
{
  "type": "paragraph",
  "content": [
    {
      "type": "text",
      "text": "This is a section."
    }
  ]
}
```

### Lists

#### Unordered List
AsciiDoc:
```adoc
* Item 1
* Item 2
```

ADF Output:
```json
{
  "type": "bulletList",
  "content": [
    {
      "type": "listItem",
      "content": [
        {
          "type": "paragraph",
          "content": [
            {
              "type": "text",
              "text": "Item 1"
            }
          ]
        }
      ]
    },
    {
      "type": "listItem",
      "content": [
        {
          "type": "paragraph",
          "content": [
            {
              "type": "text",
              "text": "Item 2"
            }
          ]
        }
      ]
    }
  ]
}
```

#### Ordered List
AsciiDoc:
```adoc
. Step 1
. Step 2
```

ADF Output:
```json
{
  "type": "orderedList",
  "content": [
    {
      "type": "listItem",
      "content": [
        {
          "type": "paragraph",
          "content": [
            {
              "type": "text",
              "text": "Step 1"
            }
          ]
        }
      ]
    },
    {
      "type": "listItem",
      "content": [
        {
          "type": "paragraph",
          "content": [
            {
              "type": "text",
              "text": "Step 2"
            }
          ]
        }
      ]
    }
  ]
}
```

### Tables
AsciiDoc:
```adoc
|===
|Cell 1 |Cell 2
|Cell 3 |Cell 4
|===
```

ADF Output:
```json
{
  "type": "table",
  "content": [
    {
      "type": "tableRow",
      "content": [
        {
          "type": "tableCell",
          "attrs": { "colspan": 1, "rowspan": 1 },
          "content": [
            {
              "type": "paragraph",
              "content": [
                {
                  "type": "text",
                  "text": "Cell 1"
                }
              ]
            }
          ]
        },
        {
          "type": "tableCell",
          "attrs": { "colspan": 1, "rowspan": 1 },
          "content": [
            {
              "type": "paragraph",
              "content": [
                {
                  "type": "text",
                  "text": "Cell 2"
                }
              ]
            }
          ]
        }
      ]
    },
    {
      "type": "tableRow",
      "content": [
        {
          "type": "tableCell",
          "attrs": { "colspan": 1, "rowspan": 1 },
          "content": [
            {
              "type": "paragraph",
              "content": [
                {
                  "type": "text",
                  "text": "Cell 3"
                }
              ]
            }
          ]
        },
        {
          "type": "tableCell",
          "attrs": { "colspan": 1, "rowspan": 1 },
          "content": [
            {
              "type": "paragraph",
              "content": [
                {
                  "type": "text",
                  "text": "Cell 4"
                }
              ]
            }
          ]
        }
      ]
    }
  ]
}
```

### Jira Issues Table Macro
AsciiDoc:
```adoc
jiraIssuesTable::['project = "DEMO"', fields='key,summary,description,status']
```

ADF Output:
```json
{
  "type": "table",
  "attrs": {
    "isNumberColumnEnabled": false,
    "layout": "default"
  },
  "content": [
    {
      "type": "tableRow",
      "content": [
        {
          "type": "tableHeader",
          "attrs": { "colspan": 1, "rowspan": 1 },
          "content": [{ "type": "paragraph", "content": [{ "text": "Key", "type": "text" }] }]
        },
        {
          "type": "tableHeader",
          "attrs": { "colspan": 1, "rowspan": 1 },
          "content": [{ "type": "paragraph", "content": [{ "text": "Summary", "type": "text" }] }]
        },
        {
          "type": "tableHeader",
          "attrs": { "colspan": 1, "rowspan": 1 },
          "content": [{ "type": "paragraph", "content": [{ "text": "Description", "type": "text" }] }]
        },
        {
          "type": "tableHeader",
          "attrs": { "colspan": 1, "rowspan": 1 },
          "content": [{ "type": "paragraph", "content": [{ "text": "Status", "type": "text" }] }]
        }
      ]
    },
    {
      "type": "tableRow",
      "content": [
        {
          "type": "tableCell",
          "attrs": { "colspan": 1, "rowspan": 1 },
          "content": [{
            "type": "paragraph",
            "content": [{
              "text": "DEMO-1",
              "type": "text",
              "marks": [{ "type": "link", "attrs": { "href": "https://jira.example.com/browse/DEMO-1" } }]
            }]
          }]
        },
        {
          "type": "tableCell",
          "attrs": { "colspan": 1, "rowspan": 1 },
          "content": [{ "type": "paragraph", "content": [{ "text": "Issue summary", "type": "text" }] }]
        },
        {
          "type": "tableCell",
          "attrs": { "colspan": 1, "rowspan": 1 },
          "content": [
            {
              "type": "paragraph",
              "content": [{ "text": "Overview:", "type": "text", "marks": [{ "type": "strong" }] }]
            },
            {
              "type": "paragraph",
              "content": [{ "text": "This is the issue description.", "type": "text" }]
            },
            {
              "type": "bulletList",
              "content": [
                {
                  "type": "listItem",
                  "content": [{ 
                    "type": "paragraph", 
                    "content": [{ "text": "Bullet point 1", "type": "text" }]
                  }]
                },
                {
                  "type": "listItem",
                  "content": [{ 
                    "type": "paragraph", 
                    "content": [{ "text": "Bullet point 2", "type": "text" }]
                  }]
                }
              ]
            }
          ]
        },
        {
          "type": "tableCell",
          "attrs": { "colspan": 1, "rowspan": 1 },
          "content": [{ "type": "paragraph", "content": [{ "text": "In Progress", "type": "text" }] }]
        }
      ]
    }
  ]
}
```

### Inline Anchors
AsciiDoc:
```adoc
See <<TEST-123>> for details.
```

ADF Output:
```json
{
  "type": "paragraph",
  "content": [
    {
      "type": "text",
      "text": "See "
    },
    {
      "type": "text",
      "text": "TEST-123",
      "marks": [
        {
          "type": "link",
          "attrs": { "href": "#TEST-123" }
        }
      ]
    },
    {
      "type": "text",
      "text": " for details."
    }
  ]
}
```

### Table of Contents (TOC) Macro
AsciiDoc:
```adoc
:toc:
```

ADF Output:
```json
{
  "type": "inlineExtension",
  "attrs": {
    "extensionType": "com.atlassian.confluence.macro.core",
    "extensionKey": "toc",
    "parameters": {
      "macroParams": {},
      "macroMetadata": {
        "macroId": { "value": "normalized-uuid" },
        "schemaVersion": { "value": "1" },
        "title": "Table of Contents"
      }
    },
    "localId": "normalized-uuid"
  }
}
```

### Atlassian Mention Macro
AsciiDoc:
```adoc
atlasMention:Adrian_Partl[]
```

ADF Output (if user found):
```json
{
  "type": "mention",
  "attrs": {
    "id": "5e73358b2354a30c3ba2f02b",
    "text": "@Adrian Partl"
  }
}
```
If the user is not found or credentials are missing, the macro outputs plain text:
```json
{
  "type": "text",
  "text": "@Adrian Partl"
}
```

### Image Handling

The converter includes smart image handling that detects image dimensions automatically and properly converts them to ADF format.

#### Image Dimensions

When including images in your AsciiDoc content, you can:

1. **Specify dimensions explicitly** using width and height attributes:
   ```adoc
   image::diagram.png[Diagram,width=400,height=300]
   ```

2. **Let the converter detect dimensions automatically** from the image file:
   ```adoc
   image::diagram.png[Diagram]
   ```

3. **Specify only one dimension** and the converter will calculate the other to maintain the aspect ratio:
   ```adoc
   image::diagram.png[Diagram,width=400]
   ```

The converter supports:
- Local image files (with automatic path resolution using `imagesdir` attribute)
- Remote images (via HTTP/HTTPS URLs)
- Both block images and inline images

#### ADF Output

Images are converted to ADF `mediaSingle` or `mediaInline` nodes with proper dimensions:

```json
{
  "type": "mediaSingle",
  "attrs": { "layout": "wide" },
  "content": [
    {
      "type": "media",
      "attrs": {
        "type": "file",
        "id": "diagram.png",
        "collection": "attachments",
        "alt": "Diagram",
        "occurrenceKey": "uuid",
        "width": 400,
        "height": 300
      }
    }
  ]
}
```

#### Path Resolution

The converter follows Asciidoctor's fundamental principles for image resolution:

1. The raw path as specified in the document (in case it's already absolute)
2. Relative to the document's base directory (where Asciidoctor was invoked)
3. Relative to the "images" directory under the base directory (following the common AsciiDoc convention)

This aligns with Asciidoctor's core principle: **image paths inside an included file are resolved relative to the base document that initiated the render process, not relative to the included file itself**.

> ⚠️ **IMPORTANT NOTE ABOUT IMAGE RESOLUTION** ⚠️
> 
> If you're defining `:imagesdir:` in an included file (like a config.adoc), make sure there are **NO BLANK LINES** in the header section of your document. 
> Asciidoctor's attribute processing is sensitive to document structure, and blank lines can cause attributes like `:imagesdir:` to be silently ignored.
>
> The converter automatically checks for images in an "images" directory under the base directory as a fallback, but proper attribute handling is preferred.
>
> **Example for config.adoc:**
> ```asciidoc
> // asciidoc settings
> :toc-title: Table of Contents
> :toc:
> :imagesdir: images
> // NO BLANK LINES between attributes!
> ```

As the official Asciidoctor documentation explains:
> "By default, the imagesdir value is empty. That means the images are resolved relative to the document."
> "If the include directive is used in the primary (top-level) document, relative paths are resolved relative to the base directory."

This ensures images are properly referenced regardless of:
- Where the document is located in the directory structure
- Whether the document includes other files
- How deeply nested your document structure is

The image handler provides useful diagnostics in the console output:
- Shows key document attributes like `base_dir` and `imagesdir`
- Lists exactly which paths were searched for each image
- Indicates when and where an image is successfully found
- Provides clear error messages when images cannot be located

### Literal/Source Code Blocks

You can include code blocks with or without a specified language. These are converted to ADF `codeBlock` nodes with the appropriate language attribute.

AsciiDoc:
```adoc
[source,ruby]
----
puts 'Hello, world!'
----

[source,python]
----
print("Hello, world!")
----

----
Plain text code block
----
```

ADF Output:
```json
{
  "type": "codeBlock",
  "attrs": { "language": "ruby" },
  "content": [
    { "type": "text", "text": "puts 'Hello, world!'" }
  ]
},
{
  "type": "codeBlock",
  "attrs": { "language": "python" },
  "content": [
    { "type": "text", "text": "print(\"Hello, world!\")" }
  ]
},
{
  "type": "codeBlock",
  "attrs": { "language": "plaintext" },
  "content": [
    { "type": "text", "text": "Plain text code block" }
  ]
}
```

## Python Helper Scripts

This repository includes Python helper scripts for bidirectional conversion between AsciiDoc and Confluence:

1. **Upload to Confluence**: Convert and upload AsciiDoc content to Confluence with proper image handling
2. **Download from Confluence**: Download Confluence content as AsciiDoc with support for recursive page hierarchies

These scripts are located in the [`helper_scripts/`](./helper_scripts/) directory and provide a complete workflow for maintaining documentation in both AsciiDoc and Confluence formats.

See [`helper_scripts/README.md`](./helper_scripts/README.md) for detailed documentation and usage examples.

## Contributing

Contributions are welcome! Please follow these steps to contribute:

1. Fork the repository.
2. Create a new branch for your feature or bug fix.
3. Make your changes and commit them.
4. Push your branch to your forked repository.
5. Create a pull request.

## License

This project is licensed under the MIT License. See the LICENSE file for more details.

## Documentation

- [Document Attributes](./doc/document-attributes.md): Detailed documentation on configuring document attributes
- [Gradle Integration Guide](./doc/gradle-integration.md): How to run the converter in a Gradle build
