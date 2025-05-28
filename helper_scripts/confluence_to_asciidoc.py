"""
Download Confluence page content as ADF and convert to AsciiDoc.

This script retrieves a Confluence page, extracts its ADF content, and converts it to AsciiDoc.
It also downloads all media attachments referenced in the page and can recursively download 
child pages to create a complete documentation tree.
"""

import os
import click
import re
import json
from confluence_client import ConfluenceClient
from adf_resources import process_node, get_node_text_content, update_adf_media_ids


@click.command()
@click.option(
    "--base-url",
    required=True,
    help="Base URL of your Confluence instance (e.g. https://your-domain.atlassian.net)",
)
@click.option(
    "--page-id", required=True, type=str, help="ID of the Confluence page to download."
)
@click.option(
    "--output-dir",
    required=True,
    help="Directory where the AsciiDoc file and images should be saved.",
)
@click.option("--username", required=True, help="Confluence username (email).")
@click.option("--api-token", required=True, help="Confluence API token.")
@click.option(
    "--jira-base-url",
    required=False,
    help="Base URL of your Jira instance for issue links. Defaults to base-url.",
)
@click.option(
    "--images-dir",
    default="images",
    help="Subdirectory name for downloaded images. Default: 'images'",
)
@click.option("--recursive", is_flag=True, help="Recursively download child pages.")
@click.option(
    "--max-depth",
    default=5,
    type=int,
    help="Maximum recursion depth when downloading pages. Default: 5",
)
@click.option(
    "--include-linked-pages",
    is_flag=True,
    help="Also download pages linked from the content, not just child pages.",
)
@click.option(
    "--page-style",
    type=click.Choice(["xref", "include", "both"]),
    default="xref",
    help="How to handle child pages: 'xref' (separate linked pages), 'include' (consolidated), or 'both'",
)
def main(
    base_url,
    page_id,
    output_dir,
    username,
    api_token,
    jira_base_url,
    images_dir,
    recursive,
    max_depth,
    include_linked_pages,
    page_style,
):
    """Download a Confluence page and convert it to AsciiDoc."""
    # Initialize client
    client = ConfluenceClient(base_url, username, api_token, jira_base_url)

    # Ensure output directory exists
    os.makedirs(output_dir, exist_ok=True)

    # Download the page and its children recursively
    visited_pages = set()
    page_mapping = {}

    download_page_recursive(
        client=client,
        page_id=page_id,
        output_dir=output_dir,
        images_dir=images_dir,
        recursive=recursive,
        current_depth=0,
        max_depth=max_depth,
        include_linked_pages=include_linked_pages,
        visited_pages=visited_pages,
        is_root=True,
        page_mapping=page_mapping,
        page_style=page_style,
    )

    # Create consolidated document if requested
    if page_style in ["include", "both"]:
        create_consolidated_document(page_id, output_dir, page_mapping)

    print(f"Downloaded {len(visited_pages)} pages in total")
    return True


def sanitize_filename(filename):
    """Convert a string to a valid filename."""
    # Remove invalid characters and replace spaces with underscores
    valid_chars = "-_.() abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    return "".join(c for c in filename if c in valid_chars).replace(" ", "_")


def extract_page_id_from_url(url, base_url):
    """Extract a Confluence page ID from a URL if it's a Confluence page link."""
    if not url or not base_url:
        return None

    # Check if the URL is from the same Confluence instance
    if base_url not in url:
        return None

    # Common patterns for Confluence page URLs
    patterns = [r"/pages/(\d+)", r"/spaces/[^/]+/pages/(\d+)", r"pageId=(\d+)"]

    for pattern in patterns:
        match = re.search(pattern, url)
        if match:
            return match.group(1)

    return None


def extract_linked_page_ids(adf_content, base_url):
    """Extract Confluence page IDs from links in the content."""
    page_ids = set()

    def process_node_for_links(node):
        if not isinstance(node, dict):
            return

        # Check for link marks in text nodes
        if node.get("type") == "text" and node.get("marks"):
            for mark in node.get("marks", []):
                if mark.get("type") == "link":
                    href = mark.get("attrs", {}).get("href", "")
                    # Extract page ID from Confluence URL
                    page_id = extract_page_id_from_url(href, base_url)
                    if page_id:
                        page_ids.add(page_id)

        # Check for inlineCard nodes (which are also links)
        if node.get("type") == "inlineCard":
            url = node.get("attrs", {}).get("url", "")
            page_id = extract_page_id_from_url(url, base_url)
            if page_id:
                page_ids.add(page_id)

        # Recursively process child nodes
        for key, value in node.items():
            if key == "content" and isinstance(value, list):
                for child in value:
                    process_node_for_links(child)

    # Start processing from the root
    for node in adf_content.get("content", []):
        process_node_for_links(node)

    return page_ids


def convert_adf_to_asciidoc(
    content,
    title=None,
    media_files=None,
    page_id=None,
    images_dir=None,
    file_id_to_filename=None,
    page_mapping=None,
    current_file_path=None,
    base_url=None,
):
    """Convert ADF content to AsciiDoc."""
    if content is None:
        return ""

    # Create context for processing
    context = {
        "list_depth": 0,
        "media_files": media_files or [],
        "file_id_to_filename": file_id_to_filename or {},
        "page_mapping": page_mapping or {},
        "current_file_path": current_file_path,
        "base_url": base_url,
        "images_dir": images_dir or "images",  # Default to "images" if not provided
    }

    result = []

    # Add the title as level 1 heading
    if title:
        result.append(f"= {title}\n")

    # Use the ABSOLUTE path for imagesdir
    if current_file_path:
        # Get the directory containing the current file
        file_dir = os.path.dirname(os.path.abspath(current_file_path))

        # Calculate absolute path to images directory
        if not os.path.isabs(images_dir):
            # If images_dir is relative, make it absolute
            absolute_images_path = os.path.abspath(os.path.join(file_dir, images_dir))
        else:
            # If images_dir is already absolute, use it directly
            absolute_images_path = images_dir

        # Add the imagesdir attribute with the true absolute path
        result.append(f":imagesdir: {absolute_images_path}\n\n")
    else:
        # Fallback - should not happen if current_file_path is always provided
        result.append(f":imagesdir: {images_dir}\n\n")

    # Process the content
    for node in content.get("content", []):
        result.extend(process_node(node, context))

    # Join all parts
    return "".join(result)


def download_page_recursive(
    client,
    page_id,
    output_dir,
    images_dir,
    recursive,
    current_depth,
    max_depth,
    include_linked_pages,
    visited_pages,
    is_root=False,
    parent_dir=None,
    page_mapping=None,
    page_style="xref",
):
    """Recursively download a page and its children."""
    # Initialize page mapping if not provided
    if page_mapping is None:
        page_mapping = {}

    # Skip if we've already visited this page
    if page_id in visited_pages or current_depth > max_depth:
        return

    visited_pages.add(page_id)
    print(f"Processing page {page_id} at depth {current_depth}...")

    # Get page information
    page_info = client.get_page_info(page_id)
    if not page_info:
        print(f"Failed to retrieve information for page {page_id}")
        return

    page_title = page_info.get("title", f"Confluence Page {page_id}")

    # Create directory for this page if not root
    if is_root:
        page_dir = output_dir
    else:
        # Create a subdirectory for this page
        sanitized_title = sanitize_filename(page_title)
        page_dir = os.path.join(parent_dir or output_dir, sanitized_title)

    os.makedirs(page_dir, exist_ok=True)

    # Create images directory if it doesn't exist
    image_output_dir = os.path.join(page_dir, images_dir)
    os.makedirs(image_output_dir, exist_ok=True)

    # Get ADF content
    adf_content = client.get_page_content(page_id)
    if not adf_content:
        print(f"Failed to retrieve content for page {page_id}")
        return

    # Download media files
    print(f"Downloading media files for page {page_id}...")
    media_files, file_id_to_filename = client.download_media_files(
        page_id, image_output_dir
    )
    print(f"Downloaded {len(media_files)} media files to {image_output_dir}")

    # Convert ADF to AsciiDoc
    output_filename = sanitize_filename(page_title)
    output_path = os.path.join(page_dir, f"{output_filename}.adoc")

    print(media_files)

    asciidoc_content = convert_adf_to_asciidoc(
        adf_content,
        title=page_title,
        media_files=media_files,
        page_id=page_id,
        images_dir=images_dir,  # Just pass the relative path
        file_id_to_filename=file_id_to_filename,  # Pass the mapping
        page_mapping=page_mapping,
        current_file_path=output_path,
        base_url=client.base_url,
    )

    # Save AsciiDoc file
    with open(output_path, "w") as f:
        f.write(asciidoc_content)

    # Add page to mapping
    page_mapping[page_id] = {"title": page_title, "path": output_path, "dir": page_dir}

    print(f"AsciiDoc content saved to {output_path}")

    # Save the original ADF content as JSON for reference
    adf_output_path = os.path.join(
        page_dir, f"{sanitize_filename(page_title)}.adf.json"
    )
    with open(adf_output_path, "w") as f:
        json.dump(adf_content, f, indent=2)

    # Get child pages
    child_pages = []
    if recursive and current_depth < max_depth:
        child_pages = client.get_child_pages(page_id)

        # Process child pages recursively BEFORE adding links to them
        for child_page in child_pages:
            child_id = child_page.get("id")
            if child_id:
                # Add parent-child relationship to the mapping
                if page_mapping.get(child_id) is None:
                    page_mapping[child_id] = {"parent_id": page_id}
                else:
                    page_mapping[child_id]["parent_id"] = page_id

                download_page_recursive(
                    client=client,
                    page_id=child_id,
                    output_dir=output_dir,
                    images_dir=images_dir,
                    recursive=recursive,
                    current_depth=current_depth + 1,
                    max_depth=max_depth,
                    include_linked_pages=include_linked_pages,
                    visited_pages=visited_pages,
                    parent_dir=page_dir,
                    page_mapping=page_mapping,
                    page_style=page_style,
                )

        # Process linked pages if requested
        if include_linked_pages:
            linked_page_ids = extract_linked_page_ids(adf_content, client.base_url)
            for linked_id in linked_page_ids:
                if linked_id not in visited_pages:  # Skip if already visited
                    download_page_recursive(
                        client=client,
                        page_id=linked_id,
                        output_dir=output_dir,
                        images_dir=images_dir,
                        recursive=recursive,
                        current_depth=current_depth + 1,
                        max_depth=max_depth,
                        include_linked_pages=False,  # Don't recursively follow links from linked pages
                        visited_pages=visited_pages,
                        parent_dir=page_dir,
                        page_mapping=page_mapping,
                        page_style=page_style,
                    )

        # NOW add child pages list after all children have been processed
        if child_pages:
            with open(output_path, "a") as f:
                for child_page in child_pages:
                    child_id = child_page.get("id")
                    child_title = child_page.get("title")
                    if child_id in page_mapping:
                        child_path = page_mapping[child_id]["path"]
                        rel_path = os.path.relpath(
                            child_path, os.path.dirname(output_path)
                        )

                        if page_style == "xref" or page_style == "both":
                            # Add cross-reference link
                            f.write(f"* xref:{rel_path}[{child_title}]\n")

                        if page_style == "include" or page_style == "both":
                            # Add include directive comment (for information)
                            f.write(f"include::{rel_path}[leveloffset=+1]\n")


def create_consolidated_document(root_page_id, output_dir, page_mapping):
    """Create a consolidated document that includes all pages."""
    if not root_page_id or root_page_id not in page_mapping:
        print("Error: Cannot create consolidated document, root page not found")
        return

    root_info = page_mapping[root_page_id]
    root_title = root_info["title"]

    consolidated_path = os.path.join(
        output_dir, f"{sanitize_filename(root_title)}_Consolidated.adoc"
    )

    with open(consolidated_path, "w") as f:
        f.write(f"= {root_title} (Consolidated)\n\n")
        f.write(":toc: left\n")
        f.write(":toclevels: 4\n\n")

        # Add global imagesdir setting to use absolute paths
        f.write(":imagesdir: images\n")
        f.write(":attribute-missing: warn\n\n")

        # Add include for the root page content (skipping its title)
        root_rel_path = os.path.relpath(root_info["path"], output_dir)
        f.write(f"include::{root_rel_path}[lines=2..]\n\n")

        # Create a function to recursively add includes for child pages
        def add_child_includes(parent_id, level):
            # Get child pages for this parent
            children = [
                pid
                for pid, info in page_mapping.items()
                if "parent_id" in info and info["parent_id"] == parent_id
            ]

            for child_id in children:
                child_info = page_mapping[child_id]
                child_path = child_info["path"]
                child_dir = child_info["dir"]
                rel_path = os.path.relpath(child_path, output_dir)

                # Get the relative path to the child's images directory
                images_rel_path = os.path.join(os.path.dirname(rel_path), "images")

                # Add custom imagesdir setting for this include
                f.write(f":imagesdir: {images_rel_path}\n")

                # Add include with appropriate level offset
                f.write(f"include::{rel_path}[leveloffset=+{level}]\n\n")

                # Recursively process this child's children
                add_child_includes(child_id, level + 1)

        # Start including children from the root
        add_child_includes(root_page_id, 1)

    print(f"Consolidated document created: {consolidated_path}")


def get_child_pages(self, page_id):
    """Get direct child pages of a Confluence page."""
    # Try both possible API endpoints
    url = f"{self.base_url}/wiki/rest/api/content/{page_id}/child/page"
    print(f"Attempting to fetch child pages from: {url}")

    response = requests.get(url, headers=self._auth_headers())

    if response.status_code == 200:
        data = response.json()
        children = data.get("results", [])
        print(f"Found {len(children)} child pages")
        return children
    else:
        # Try alternate URL format
        alt_url = f"{self.base_url}/rest/api/content/{page_id}/child/page"
        print(f"First attempt failed ({response.status_code}), trying: {alt_url}")
        alt_response = requests.get(alt_url, headers=self._auth_headers())

        if alt_response.status_code == 200:
            data = alt_response.json()
            children = data.get("results", [])
            print(f"Found {len(children)} child pages using alternate URL")
            return children
        else:
            print(
                f"Failed to fetch child pages: {response.status_code} / {alt_response.status_code}"
            )
            print(f"Response: {response.text[:200]}...")
            return []


if __name__ == "__main__":
    main()
