import json
import click
from asciidoc_resources import extract_images_and_includes
from confluence_api import (
    create_empty_page,
    upload_images_to_confluence,
    update_page_content
)
from adf_media import update_adf_media_ids

@click.command()
@click.option('--base-url', required=True, help="Base URL of your Confluence instance (e.g. https://your-domain.atlassian.net)")
@click.option('--asciidoc', required=True, help="Path to the main Asciidoctor file.")
@click.option('--adf', required=True, help="Path to the converted ADF JSON file.")
@click.option('--space-id', required=True, type=int, help="Confluence space ID.")
@click.option('--title', required=True, help="Title of the Confluence page.")
@click.option('--username', required=True, help="Confluence username (email).")
@click.option('--api-token', required=True, help="Confluence API token.")
def main(base_url, asciidoc, adf, space_id, title, username, api_token):
    images = []
    extract_images_and_includes(asciidoc, images)

    page_id = create_empty_page(base_url, space_id, title, username, api_token)
    print("Created empty page with ID:", page_id)
    
    if page_id:
        print("Uploading images to Confluence...")
        filename_to_fileid = upload_images_to_confluence(base_url, images, page_id, username, api_token)
        with open(adf, 'r') as f:
            adf_json = json.load(f)

        patched_adf = update_adf_media_ids(adf_json, filename_to_fileid)
        temp_adf_path = adf + ".patched"
        with open(temp_adf_path, 'w') as f:
            json.dump(patched_adf, f)
        print("Patched ADF path:", temp_adf_path)

        print("Updating page content...")
        update_page_content(base_url, page_id, patched_adf, username, api_token)
    else:
        print("Failed to create page. Exiting.")
        return
    
    print("Upload completed successfully.")

if __name__ == '__main__':
    main()