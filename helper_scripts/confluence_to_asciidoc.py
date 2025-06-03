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
import logging
from confluence_client import ConfluenceClient
from adf_resources import process_node, get_node_text_content, update_adf_media_ids

# Set up logging
logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)


class FileUtils:
    """Utility methods for file operations."""

    @staticmethod
    def sanitize_filename(filename):
        """Convert a string to a valid filename. Removes invalid characters and replace spaces with underscores."""
        valid_chars = (
            "-_.() abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        )
        return "".join(c for c in filename if c in valid_chars).replace(" ", "_")

    @staticmethod
    def ensure_dir_exists(directory):
        """Ensure a directory exists, creating it if necessary."""
        os.makedirs(directory, exist_ok=True)

    @staticmethod
    def save_text_file(path, content):
        """Save text content to a file."""
        try:
            with open(path, "w") as f:
                f.write(content)
            return True
        except Exception as e:
            logger.error(f"Error writing to file {path}: {str(e)}")
            return False

    @staticmethod
    def save_json_file(path, content):
        """Save JSON content to a file."""
        try:
            with open(path, "w") as f:
                json.dump(content, f, indent=2)
            return True
        except Exception as e:
            logger.error(f"Error writing JSON to file {path}: {str(e)}")
            return False


class LinkExtractor:
    """Extract links and page IDs from Confluence content."""

    @staticmethod
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

    @staticmethod
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
                        page_id = LinkExtractor.extract_page_id_from_url(href, base_url)
                        if page_id:
                            page_ids.add(page_id)

            # Check for inlineCard nodes (which are also links)
            if node.get("type") == "inlineCard":
                url = node.get("attrs", {}).get("url", "")
                page_id = LinkExtractor.extract_page_id_from_url(url, base_url)
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


class AdfToAsciidocConverter:
    """Convert ADF content to AsciiDoc format."""

    def convert(
        self,
        content,
        title=None,
        media_files=None,
        page_id=None,
        images_dir=None,
        file_id_to_filename=None,
        page_mapping=None,
        current_file_path=None,
        base_url=None,
        client=None,
        is_root=False,
        root_dir=None,
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
            "images_dir": images_dir or "images",
            "confluence_client": client,
        }

        result = []

        # Add the title as level 1 heading
        if title:
            result.append(f"= {title}\n")

        if current_file_path and root_dir:
            # For all documents, reference the base_path attribute
            if is_root:
                # For the root document, define the base_path attribute as an absolute path
                absolute_base_path = os.path.abspath(root_dir)
                result.append(f":base_path: {absolute_base_path}\n")

            # Get the path relative to the root for the current file's images
            rel_path = os.path.relpath(os.path.dirname(current_file_path), root_dir)

            # Use the base_path for imagesdir, adjusted for this page's location
            if rel_path == ".":
                # Root document
                result.append(f":imagesdir: {{base_path}}/{images_dir}\n\n")
            else:
                # Child document
                result.append(f":imagesdir: {{base_path}}/{rel_path}/{images_dir}\n\n")
        else:
            # Fallback - should not happen if current_file_path is always provided
            result.append(f":imagesdir: {images_dir}\n\n")

        for node in content.get("content", []):
            result.extend(process_node(node, context))

        return "".join(result)


class DownloadConfig:
    """Configuration settings for page download operations."""

    def __init__(
        self,
        output_dir,
        images_dir="images",
        recursive=False,
        max_depth=5,
        include_linked_pages=False,
        page_style="xref",
    ):
        self.output_dir = output_dir
        self.images_dir = images_dir
        self.recursive = recursive
        self.max_depth = max_depth
        self.include_linked_pages = include_linked_pages
        self.page_style = page_style


class ConfluenceDownloader:
    """Handles downloading and processing Confluence content."""

    def __init__(self, client):
        self.client = client
        self.file_utils = FileUtils()
        self.converter = AdfToAsciidocConverter()

    def download_page_recursive(
        self,
        page_id,
        config,
        base_dir,
        current_depth=0,
        visited_pages=None,
        is_root=False,
        parent_dir=None,
        page_mapping=None,
    ):
        """Recursively download a page and its children.

        Args:
            page_id: ID of the page to download
            config: DownloadConfig object with settings
            base_dir: The root directory for all output paths
            current_depth: Current recursion depth
            visited_pages: Set of already visited pages
            is_root: Whether this is the root page being downloaded
            parent_dir: Parent directory for this page
            page_mapping: Dictionary mapping page ID to information
        """
        # Initialize tracking collections if not provided
        visited_pages = visited_pages or set()
        page_mapping = page_mapping or {}

        # Skip if we've already visited this page or exceeded max depth
        if page_id in visited_pages or current_depth > config.max_depth:
            return page_mapping  # Make sure to return the mapping

        visited_pages.add(page_id)
        logger.info(f"Processing page {page_id} at depth {current_depth}...")

        # Get page information
        page_info = self.client.get_page_info(page_id)
        if not page_info:
            logger.error(f"Failed to retrieve information for page {page_id}")
            return page_mapping  # Return the mapping even on error

        page_title = page_info.get("title", f"Confluence Page {page_id}")
        parent_id = (
            page_info.get("ancestors", [{}])[-1].get("id")
            if page_info.get("ancestors")
            else None
        )

        # Create directory for this page
        if is_root:
            page_dir = base_dir
        else:
            # Create a subdirectory for this page
            sanitized_title = self.file_utils.sanitize_filename(page_title)
            page_dir = os.path.join(parent_dir or base_dir, sanitized_title)

        self.file_utils.ensure_dir_exists(page_dir)

        # Create images directory if it doesn't exist
        image_output_dir = os.path.join(page_dir, config.images_dir)
        self.file_utils.ensure_dir_exists(image_output_dir)

        # Get ADF content
        adf_content = self.client.get_page_content(page_id)
        if not adf_content:
            logger.error(f"Failed to retrieve content for page {page_id}")
            return page_mapping

        # Download media files
        logger.info(f"Downloading media files for page {page_id}...")
        media_files, file_id_to_filename = self.client.download_media_files(
            page_id, image_output_dir
        )
        logger.info(f"Downloaded {len(media_files)} media files to {image_output_dir}")

        # Convert ADF to AsciiDoc
        output_filename = self.file_utils.sanitize_filename(page_title)
        output_path = os.path.join(page_dir, f"{output_filename}.adoc")

        asciidoc_content = self.converter.convert(
            adf_content,
            title=page_title,
            media_files=media_files,
            page_id=page_id,
            images_dir=config.images_dir,
            file_id_to_filename=file_id_to_filename,
            page_mapping=page_mapping,
            current_file_path=output_path,
            base_url=self.client.base_url,
            client=self.client,
            is_root=is_root,
            root_dir=base_dir,
        )

        # Save AsciiDoc file
        self.file_utils.save_text_file(output_path, asciidoc_content)

        # Add page to mapping
        page_mapping[page_id] = {
            "title": page_title,
            "path": output_path,
            "dir": page_dir,
            "parent_id": parent_id,
            "is_root": is_root,
        }

        logger.info(f"AsciiDoc content saved to {output_path}")

        # Process child pages recursively
        self._process_child_pages(
            page_id,
            page_info,
            adf_content,
            output_path,
            page_dir,
            base_dir,
            current_depth,
            visited_pages,
            page_mapping,
            config,
        )

        return page_mapping

    def _process_child_pages(
        self,
        page_id,
        page_info,
        adf_content,
        output_path,
        page_dir,
        base_dir,
        current_depth,
        visited_pages,
        page_mapping,
        config,
    ):
        """Process child pages and linked pages."""
        child_pages = self.client.get_child_pages(page_id)

        # Process child pages recursively BEFORE adding links to them
        for child_page in child_pages:
            child_id = child_page.get("id")
            if child_id:
                # Add parent-child relationship to the mapping
                if page_mapping.get(child_id) is None:
                    page_mapping[child_id] = {"parent_id": page_id}
                else:
                    page_mapping[child_id]["parent_id"] = page_id

                self.download_page_recursive(
                    page_id=child_id,
                    config=config,
                    base_dir=base_dir,
                    current_depth=current_depth + 1,
                    visited_pages=visited_pages,
                    parent_dir=page_dir,
                    page_mapping=page_mapping,
                )

        # Add child pages list after all children have been processed
        if child_pages:
            self._add_child_page_references(
                output_path, child_pages, page_mapping, config.page_style, base_dir
            )

    def _add_child_page_references(
        self, output_path, child_pages, page_mapping, page_style, base_dir
    ):
        """Add child page references (xref or include) to the parent page."""
        with open(output_path, "a") as f:
            for child_page in child_pages:
                child_id = child_page.get("id")
                child_title = child_page.get("title")
                if child_id in page_mapping:
                    child_path = page_mapping[child_id]["path"]

                    # Calculate path relative to the base directory
                    rel_path = os.path.relpath(child_path, base_dir)

                    if page_style == "xref" or page_style == "both":
                        # Add cross-reference link using base_path attribute
                        f.write(f"* xref:{{base_path}}/{rel_path}[{child_title}]\n")

                    if page_style == "include" or page_style == "both":
                        # Add include directive using base_path attribute
                        f.write(f"include::{{base_path}}/{rel_path}[leveloffset=+1]\n")

    def create_consolidated_document(self, root_page_id, output_dir, page_mapping):
        """Create a consolidated document that includes all pages."""
        # Debug information
        logger.debug(f"Creating consolidated document with root ID: {root_page_id}")
        logger.debug(f"Available page IDs: {list(page_mapping.keys())}")

        # First try to find the page with the exact ID
        if root_page_id in page_mapping:
            root_info = page_mapping[root_page_id]
        else:
            # If not found, try to find a page marked as is_root=True
            root_pages = [
                pid for pid, info in page_mapping.items() if info.get("is_root")
            ]
            if root_pages:
                root_page_id = root_pages[0]
                root_info = page_mapping[root_page_id]
                logger.info(f"Using page {root_page_id} as root page (marked as root)")
            else:
                # Last resort: try to find a page without a parent
                for pid, info in page_mapping.items():
                    if "parent_id" not in info or info["parent_id"] is None:
                        root_page_id = pid
                        root_info = info
                        logger.info(f"Using page {pid} as root page (no parent)")
                        break
                else:
                    # If we still haven't found a root page, just use the first one
                    if page_mapping:
                        root_page_id = next(iter(page_mapping))
                        root_info = page_mapping[root_page_id]
                        logger.info(
                            f"Using page {root_page_id} as root page (first in mapping)"
                        )
                    else:
                        logger.error(
                            "Cannot create consolidated document, no pages in mapping"
                        )
                        return None

        root_title = root_info["title"]

        consolidated_path = os.path.join(
            output_dir,
            f"{self.file_utils.sanitize_filename(root_title)}_Consolidated.adoc",
        )

        content = []
        # Document title
        content.append(f"= {root_title} (Consolidated)\n\n")
        # Document attributes
        content.append(":toc: left\n")
        content.append(":toclevels: 4\n\n")
        # Add base_path attribute as an absolute path
        absolute_base_path = os.path.abspath(output_dir)
        content.append(f":base_path: {absolute_base_path}\n")
        content.append(f":imagesdir: {{base_path}}/images\n")
        content.append(":attribute-missing: warn\n\n")

        # Add include for the root page content (skipping its title)
        root_rel_path = os.path.relpath(root_info["path"], output_dir)
        content.append(f"include::{{base_path}}/{root_rel_path}[lines=2..]\n\n")

        # Generate includes for all child pages
        content.extend(
            self._generate_child_includes(root_page_id, output_dir, page_mapping, 1)
        )

        # Save the consolidated document
        self.file_utils.save_text_file(consolidated_path, "".join(content))
        logger.info(f"Consolidated document created: {consolidated_path}")
        return consolidated_path  # Return the path for testing convenience

    def _generate_child_includes(self, parent_id, base_dir, page_mapping, level):
        """Recursively generate include directives for child pages."""
        content = []

        # Get child pages for this parent
        children = [
            pid
            for pid, info in page_mapping.items()
            if "parent_id" in info and info["parent_id"] == parent_id
        ]

        for child_id in children:
            child_info = page_mapping[child_id]
            child_path = child_info["path"]

            # Calculate path relative to the base directory
            rel_path = os.path.relpath(child_path, base_dir)

            # Add include with appropriate level offset using base_path attribute
            content.append(
                f"include::{{base_path}}/{rel_path}[leveloffset=+{level}]\n\n"
            )

            # Recursively process this child's children
            content.extend(
                self._generate_child_includes(
                    child_id, base_dir, page_mapping, level + 1
                )
            )

        return content


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
    try:
        # Initialize client
        client = ConfluenceClient(base_url, username, api_token, jira_base_url)
        downloader = ConfluenceDownloader(client)

        # Ensure output directory exists
        FileUtils.ensure_dir_exists(output_dir)

        # Create download configuration
        config = DownloadConfig(
            output_dir=output_dir,
            images_dir=images_dir,
            recursive=recursive,
            max_depth=max_depth,
            include_linked_pages=include_linked_pages,
            page_style=page_style,
        )

        # Download the page and its children recursively
        visited_pages = set()
        page_mapping = {}

        logger.info(f"Starting download of page {page_id} and its children...")

        page_mapping = downloader.download_page_recursive(
            page_id=page_id,
            config=config,
            base_dir=output_dir,
            visited_pages=visited_pages,
            is_root=True,
            page_mapping=page_mapping,
        )

        # Create consolidated document if requested
        if page_style in ["include", "both"]:
            logger.info(f"Creating consolidated document...")
            consolidated_path = downloader.create_consolidated_document(
                page_id, output_dir, page_mapping
            )
            if consolidated_path:
                logger.info(f"Consolidated document created at: {consolidated_path}")

        logger.info(f"Downloaded {len(visited_pages)} pages in total")
        return True

    except Exception as e:
        logger.error(f"Error during conversion: {str(e)}", exc_info=True)
        return False


if __name__ == "__main__":
    main()
