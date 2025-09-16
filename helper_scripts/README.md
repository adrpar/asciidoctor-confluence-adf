# Confluence ADF Uploader Helper Scripts

This directory contains Python scripts and modules for uploading ADF content and images to Confluence Cloud.

## Usage

All the instructions here are relative to the `helper_scripts` directory, so first
```
cd helper_scripts
```

Install requirements (recommended: use [uv](https://github.com/astral-sh/uv)):
```
uv pip install -r requirements.txt
```

### Creating or Updating a Page

You can use the upload script to **create a new Confluence page** or **update an existing one**.  
If you provide the `--page-id` option, the script will update the specified page (including attachments and content).  
If you omit `--page-id`, a new page will be created.

**Example: Create a new page**
```
uv run upload_to_confluence.py --atlassian-base-url https://your-domain.atlassian.net --asciidoc path/to/main.adoc --adf path/to/adf.json --space-id 123456 --title "Page Title" --username "user@example.com" --api-token "your-api-token"
```

**Example: Update an existing page**
```
uv run upload_to_confluence.py --atlassian-base-url https://your-domain.atlassian.net --asciidoc path/to/main.adoc --adf path/to/adf.json --space-id 123456 --title "Page Title" --username "user@example.com" --api-token "your-api-token" --page-id 987654
```

**Example: Resize large images while uploading**
```
uv run upload_to_confluence.py --atlassian-base-url https://your-domain.atlassian.net --asciidoc path/to/main.adoc --adf path/to/adf.json --space-id 123456 --title "Page Title" --username "user@example.com" --api-token "your-api-token" --page-id 987654 --max-image-width 800
```

When updating, the script will:
- Upload any new or changed images (using checksums to avoid unnecessary uploads)
- Remove old attachments if they are replaced
- Patch the ADF file with the correct attachment IDs
- If `--max-image-width` is specified, resize any images that exceed this width (preserving aspect ratio)
- Update the page content in Confluence, incrementing the version as required

### Downloading from Confluence to AsciiDoc

You can use the `confluence_to_asciidoc.py` script to download content from Confluence and convert it to AsciiDoc format.

**Example: Download a single page**
```
uv run confluence_to_asciidoc.py --atlassian-base-url https://your-domain.atlassian.net --page-id 123456 --output-dir ./output --username "user@example.com" --api-token "your-api-token"
```

**Example: Download a page and all its children**
```
uv run confluence_to_asciidoc.py --atlassian-base-url https://your-domain.atlassian.net --page-id 123456 --output-dir ./output --username "user@example.com" --api-token "your-api-token" --recursive
```

**Upload script options:**
```
--atlassian-base-url TEXT  Unified Atlassian base URL (e.g. https://your-domain.atlassian.net) [required]
--base-url TEXT            (Deprecated) Legacy option retained for backward compatibility.
--asciidoc TEXT           Path to the main Asciidoctor file [required]
--adf TEXT                Path to the converted ADF JSON file [required]
--space-id INTEGER        Confluence space ID [required]
--title TEXT              Title of the Confluence page [required]
--username TEXT           Confluence username (email) [required]
--api-token TEXT          Confluence API token [required]
--page-id TEXT            ID of the existing Confluence page to update. If not provided, a new page will be created
--max-image-width INTEGER Maximum width for images (pixels). If set, images wider than this will be resized and height adjusted to keep aspect ratio
```

**Download script options:**
```
--images-dir TEXT           Subdirectory name for downloaded images. Default: 'images'
--recursive                 Recursively download child pages.
--max-depth INTEGER         Maximum recursion depth when downloading pages. Default: 5
--include-linked-pages      Also download pages linked from the content, not just child pages.
--page-style [xref|include|both]
                            How to handle child pages: 'xref' (separate linked pages), 'include' (consolidated), or 'both'
--jira-base-url TEXT        (Deprecated) Separate Jira base URL; prefer unified --atlassian-base-url.
```

Environment variable precedence (if CLI options omitted):
1. ATLASSIAN_BASE_URL (preferred)
2. CONFLUENCE_BASE_URL (legacy)
3. JIRA_BASE_URL (only for Jira ticket lookups if distinct)

Deprecated document attributes / env vars still recognized elsewhere in the toolchain (`jira-base-url`, `confluence-base-url`, `JIRA_BASE_URL`, `CONFLUENCE_BASE_URL`) will emit a warning and should be migrated to `atlassian-base-url` / `ATLASSIAN_BASE_URL`.

The script will:
- Download the specified page content as AsciiDoc
- Save the original ADF JSON content for reference
- Download and save all media attachments
- With `--recursive`, download all child pages maintaining the hierarchy
- With `--include-linked-pages`, also download pages linked from the content
- With `--page-style` set to "include" or "both", create a consolidated document that combines all pages

## Running Tests

To run the tests (from within the `helper_scripts` directory):

```
uv pip install pytest
uv run -m pytest
```
