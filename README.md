# Asciidoctor Confluence ADF Converter

## Overview

This converter transforms AsciiDoc documents into Atlassian Document Format (ADF), enabling seamless integration with Atlassian tools like Confluence.

## Features

- Converts AsciiDoc elements (e.g., paragraphs, lists, tables) into ADF-compliant JSON.
- Supports Confluence-specific macros (e.g., anchors, TOC).
- Includes a Jira inline macro for convenient issue linking.
- Includes an Atlassian mention macro for user mentions, with Confluence Cloud user lookup.
- Supports Confluence Table of Contents (TOC) macro via `:toc:`.
- Automatically handles inline formatting (e.g., bold, italic, links).
- Generates structured JSON for use in Confluence or other Atlassian tools.

> **Note:**  
> This project has been created with the support of large language models (LLMs).  
> As a result, some code may reflect an iterative or "vibe coding" style.  
> The codebase will be gradually cleaned up and refactored for clarity and maintainability.

## Installation

To install the necessary dependencies, run the following command:

```bash
bundle install
```

## Usage

### Using in a Ruby Application

To use the Asciidoctor ADF converter, include it in your Ruby application and specify the `adf` backend. Here’s a basic example:

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

By default, the `adf_extensions.rb` file loads **both** the ADF converter and the Jira/Atlassian mention macros, so you can use them together with a single `-r` option:

```bash
asciidoctor -r ./src/adf_extensions.rb -b adf yourfile.adoc
```

If you only want to use the Jira and Atlassian mention macros (for example, with the standard HTML backend), you can load just the macro:

```bash
asciidoctor -r ./src/jira_macro.rb yourfile.adoc
```

> **Note:**  
> `adf_extensions.rb` registers both the ADF converter and the macros for convenience.  
> If you only need the macros, require `jira_macro.rb` directly.

---

## Jira Inline Macro

This project includes a **Jira inline macro** for easily linking to Jira issues from your AsciiDoc content.

### Usage

In your AsciiDoc file, use the macro as follows:

```adoc
jira:ISSUE-123[]
jira:ISSUE-456[Custom link text]
```

- The macro will render as a link to the specified Jira issue.
- You can optionally provide custom link text in the brackets.

### Setting the Jira Base URL

The macro uses the `JIRA_BASE_URL` environment variable to construct the link.  
Set it when running Asciidoctor, for example:

```bash
JIRA_BASE_URL="https://your-company.atlassian.net" asciidoctor -r ./src/jira_macro.rb -b adf yourfile.adoc
```

If `JIRA_BASE_URL` is not set, the macro will output the original macro text as plain text and print a warning.

---

## Atlassian Mention Inline Macro

This project also includes an **Atlassian mention macro** for user mentions, which can resolve user IDs from Confluence Cloud.

### Usage

In your AsciiDoc file, use the macro as follows (note the use of underscores for spaces):

```adoc
atlasMention:Adrian_Partl[]
```

- The macro will look up the user "Adrian Partl" in Confluence Cloud and insert an ADF mention node (when using the `adf` backend).
- For non-ADF backends (e.g., HTML), it will render as plain text `@Adrian Partl`.

### Setting Confluence API Credentials

The macro uses the following environment variables to connect to Confluence Cloud:

- `CONFLUENCE_BASE_URL` (e.g., `https://your-company.atlassian.net`)
- `CONFLUENCE_API_TOKEN`
- `CONFLUENCE_USER_EMAIL`

Set them when running Asciidoctor, for example:

```bash
CONFLUENCE_BASE_URL="https://your-company.atlassian.net" \
CONFLUENCE_API_TOKEN="your-api-token" \
CONFLUENCE_USER_EMAIL="your-email@example.com" \
asciidoctor -r ./src/adf_extensions.rb -b adf yourfile.adoc
```

If credentials are missing or the user is not found, the macro will output `@Adrian Partl` as plain text.

---

## Confluence Table of Contents (TOC) Macro

You can insert a Confluence-style Table of Contents macro into your document using:

```adoc
:toc:
```

This will be converted to a Confluence TOC macro in the ADF output.

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

## Python Helper Scripts for Confluence Upload

This repository also includes a set of Python helper scripts for uploading ADF JSON and images as attachments to Confluence Cloud.  
You can find them in the [`helper_scripts/`](./helper_scripts/) directory.

**Features:**
- Uploads images and ADF JSON to Confluence Cloud using the REST API.
- Handles image extraction from AsciiDoc sources (including includes and imagesdir).
- Automatically patches ADF media nodes with Confluence file IDs.

**Quickstart:**

See [`helper_scripts/README.md`](./helper_scripts/README.md) for full documentation and advanced usage.

## Contributing

Contributions are welcome! Please follow these steps to contribute:

1. Fork the repository.
2. Create a new branch for your feature or bug fix.
3. Make your changes and commit them.
4. Push your branch to your forked repository.
5. Create a pull request.

## License

This project is licensed under the MIT License. See the LICENSE file for more details.