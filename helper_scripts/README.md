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

If you want to run from within the `helper_scripts` directory:
```
uv run upload_to_confluence.py --base-url https://your-domain.atlassian.net --asciidoc path/to/main.adoc --adf path/to/adf.json --space-id 123456 --title "Page Title" --username "user@example.com" --api-token "your-api-token"
```

## Running Tests

To run the tests (from within the `helper_scripts` directory):

```
uv pip install pytest
uv run -m pytest
```
