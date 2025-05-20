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
uv run upload_to_confluence.py --base-url https://your-domain.atlassian.net --asciidoc path/to/main.adoc --adf path/to/adf.json --space-id 123456 --title "Page Title" --username "user@example.com" --api-token "your-api-token"
```

**Example: Update an existing page**
```
uv run upload_to_confluence.py --base-url https://your-domain.atlassian.net --asciidoc path/to/main.adoc --adf path/to/adf.json --space-id 123456 --title "Page Title" --username "user@example.com" --api-token "your-api-token" --page-id 987654
```

When updating, the script will:
- Upload any new or changed images (using checksums to avoid unnecessary uploads)
- Remove old attachments if they are replaced
- Patch the ADF file with the correct attachment IDs
- Update the page content in Confluence, incrementing the version as required

## Running Tests

To run the tests (from within the `helper_scripts` directory):

```
uv pip install pytest
uv run -m pytest
```
