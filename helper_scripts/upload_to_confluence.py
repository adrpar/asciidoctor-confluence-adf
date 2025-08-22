import json
import click
from asciidoc_resources import extract_images_and_includes
from confluence_client import ConfluenceClient
from adf_resources import update_adf_media_ids, update_adf_image_dimensions


@click.command()
@click.option(
    "--base-url",
    required=True,
    help="Base URL of your Confluence instance (e.g. https://your-domain.atlassian.net)",
)
@click.option("--asciidoc", required=True, help="Path to the main Asciidoctor file.")
@click.option("--adf", required=True, help="Path to the converted ADF JSON file.")
@click.option("--space-id", required=True, type=int, help="Confluence space ID.")
@click.option("--title", required=True, help="Title of the Confluence page.")
@click.option("--username", required=True, help="Confluence username (email).")
@click.option("--api-token", required=True, help="Confluence API token.")
@click.option(
    "--page-id",
    required=False,
    type=str,
    help="ID of the existing Confluence page to update. If not provided, a new page will be created.",
)
@click.option(
    "--max-image-width",
    required=False,
    type=int,
    help="Maximum width for images (pixels). If set, images wider than this will be resized and height adjusted to keep aspect ratio.",
)
def main(base_url, asciidoc, adf, space_id, title, username, api_token, page_id, max_image_width):
    # Initialize client
    client = ConfluenceClient(base_url, username, api_token)

    images = []
    extract_images_and_includes(asciidoc, images)

    # If page_id is not provided, create a new page
    if not page_id:
        page_id = client.create_empty_page(space_id, title)
        print("Created empty page with ID:", page_id)
    else:
        print("Updating existing page with ID:", page_id)

    if not page_id:
        print("Failed to create or find page. Exiting.")
        return

    # Get current attachments for the page
    current_attachments = client.get_page_attachments(page_id)
    current_files = {
        att["title"]: att["extensions"]["fileId"] for att in current_attachments
    }

    # Upload new/changed images
    print("Uploading images to Confluence...")
    filename_to_fileid = client.upload_images_to_confluence(
        images, page_id, current_files
    )

    with open(adf, "r") as f:
        adf_json = json.load(f)

    patched_adf = update_adf_media_ids(adf_json, filename_to_fileid)
    # If max_image_width is set, update image dimensions
    if max_image_width:
        patched_adf = update_adf_image_dimensions(patched_adf, max_image_width)
    temp_adf_path = adf + ".patched"
    with open(temp_adf_path, "w") as f:
        json.dump(patched_adf, f)
    print("Patched ADF path:", temp_adf_path)

    print("Updating page content...")
    client.update_page_content(page_id, patched_adf)

    print("Upload completed successfully.")


if __name__ == "__main__":
    main()
