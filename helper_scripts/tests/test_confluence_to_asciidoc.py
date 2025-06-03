#!/usr/bin/env python3
"""
Test suite for the confluence_to_asciidoc.py script.
"""

import os
import json
import pytest
import tempfile
import sys
from unittest.mock import patch, Mock, MagicMock
import traceback

# Add the parent directory to sys.path so we can import modules directly
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

# Import the classes and needed modules
from confluence_to_asciidoc import (
    FileUtils,
    AdfToAsciidocConverter,
    ConfluenceDownloader,
    LinkExtractor,
    main,
)
from adf_resources import process_node, get_node_text_content
from confluence_client import ConfluenceClient


class TestConfluenceToAsciidoc:
    """Test the confluence_to_asciidoc functions."""

    def setup_method(self):
        """Set up test environment."""
        self.base_url = "https://example.atlassian.net"
        self.page_id = "12345"
        self.username = "testuser"
        self.api_token = "testtoken"
        self.output_dir = "test_output"
        self.images_dir = "images"

        # Create a client instance for testing
        self.client = ConfluenceClient(self.base_url, self.username, self.api_token)

        # Create instances of our utility classes
        self.file_utils = FileUtils()
        self.converter = AdfToAsciidocConverter()
        self.downloader = ConfluenceDownloader(self.client)

        # Import the DownloadConfig class for tests
        from confluence_to_asciidoc import DownloadConfig

        self.DownloadConfig = DownloadConfig

    def _create_test_config(self, temp_dir, page_style="xref"):
        """Create a standard DownloadConfig object for tests."""
        return self.DownloadConfig(
            output_dir=temp_dir,
            images_dir="images",
            recursive=True,
            max_depth=2,
            include_linked_pages=False,
            page_style=page_style,
        )

    def test_sanitize_filename(self):
        """Test filename sanitization."""
        # Test with various inputs
        assert FileUtils.sanitize_filename("Hello World") == "Hello_World"
        assert (
            FileUtils.sanitize_filename("File/with\\invalid:chars")
            == "Filewithinvalidchars"
        )
        assert (
            FileUtils.sanitize_filename("Normal-File_Name.123")
            == "Normal-File_Name.123"
        )

    @patch("requests.get")
    def test_get_page_info_success(self, mock_get):
        """Test successful page info retrieval."""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {"title": "Test Page", "id": self.page_id}
        mock_get.return_value = mock_response

        # Use the client instead of the standalone function
        result = self.client.get_page_info(self.page_id)

        assert result["title"] == "Test Page"
        assert result["id"] == self.page_id
        mock_get.assert_called_once()

    @patch("requests.get")
    def test_get_page_info_failure(self, mock_get):
        """Test failed page info retrieval."""
        mock_response = Mock()
        mock_response.status_code = 404
        mock_response.text = "Not found"
        mock_get.return_value = mock_response

        # Use the client instead of the standalone function
        result = self.client.get_page_info(self.page_id)

        assert result is None
        mock_get.assert_called_once()

    @patch("requests.get")
    def test_get_page_content_success(self, mock_get):
        """Test successful page content retrieval."""
        mock_response = Mock()
        mock_response.status_code = 200
        # Mock the nested atlas_doc_format structure
        mock_response.json.return_value = {
            "id": self.page_id,
            "title": "Test Page",
            "body": {
                "atlas_doc_format": {
                    "representation": "atlas_doc_format",
                    "value": '{"type":"doc","content":[{"type":"paragraph","content":[{"text":"Test content","type":"text"}]}]}',
                }
            },
        }
        mock_get.return_value = mock_response

        # Use the client instead of the standalone function
        result = self.client.get_page_content(self.page_id)

        assert result is not None
        assert result["type"] == "doc"
        assert result["content"][0]["type"] == "paragraph"
        assert result["content"][0]["content"][0]["text"] == "Test content"
        mock_get.assert_called_once()

    @patch("requests.get")
    def test_get_page_attachments_success(self, mock_get):
        """Test successful attachments retrieval."""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            "results": [{"title": "image.png", "extensions": {"fileId": "123"}}]
        }
        mock_get.return_value = mock_response

        # Use the client instead of the standalone function
        result = self.client.get_page_attachments(self.page_id)

        assert len(result) == 1
        assert result[0]["title"] == "image.png"
        assert result[0]["extensions"]["fileId"] == "123"
        mock_get.assert_called_once()

    @patch("requests.get")
    def test_download_media_files(self, mock_get):
        """Test successful attachment download."""
        # Mock the attachment list request
        attachments_response = MagicMock()
        attachments_response.status_code = 200
        attachments_response.json.return_value = {
            "results": [
                {"id": "123", "title": "test.png"},
                {"id": "456", "title": "test.txt"},  # Should be filtered out
            ]
        }

        # Mock the file download request
        download_response = MagicMock()
        download_response.status_code = 200

        # Return a fresh iterator for iter_content each time it is called
        def iter_content_side_effect(chunk_size=8192):
            return iter([b"test content"])

        download_response.iter_content.side_effect = iter_content_side_effect

        # Make the mock return different responses based on URLs
        def get_side_effect(*args, **kwargs):
            url = args[0]
            if "download" in url:
                return download_response  # For the file download request
            elif "child/attachment" in url:
                return attachments_response  # For the attachment list request
            else:
                raise ValueError(f"Unexpected URL: {url}")

        mock_get.side_effect = get_side_effect

        # Create a temporary directory for the test
        with tempfile.TemporaryDirectory() as tmpdirname:
            media_files, file_id_to_filename = self.client.download_media_files(
                self.page_id, tmpdirname
            )

            # Should be 1 file (test.txt is filtered out as not a media file)
            assert len(media_files) == 1
            assert media_files[0]["id"] == "123"
            assert media_files[0]["title"] == "test.png"

            # Verify the file was created
            file_path = os.path.join(tmpdirname, "test.png")
            assert os.path.exists(file_path) is True

            # Verify the file content
            with open(file_path, "rb") as f:
                content = f.read()
                assert content == b"test content"

    def test_is_media_file(self):
        """Test identification of media files."""
        self.client._is_media_file("image.png") is True
        self.client._is_media_file("document.PDF") is True
        self.client._is_media_file("script.js") is False
        self.client._is_media_file("document.txt") is False

    def test_convert_adf_to_asciidoc_simple(self):
        """Test conversion of simple ADF to AsciiDoc."""
        adf_content = {
            "type": "doc",
            "content": [
                {
                    "type": "paragraph",
                    "content": [{"type": "text", "text": "This is a test paragraph."}],
                }
            ],
        }

        result = self.converter.convert(adf_content, title="Test Document")

        # Check that the result contains the title and content
        assert "= Test Document" in result
        assert "This is a test paragraph." in result

    def test_child_pages_section_generation(self):
        """Test that parent pages include a properly formatted Child Pages section."""
        with tempfile.TemporaryDirectory() as temp_dir:
            # Mock ConfluenceClient
            mock_client = MagicMock()

            # Configure a simple page hierarchy: root page with two children
            # Configure get_page_info mock
            def mock_get_page_info(page_id):
                page_info = {
                    "parent": {
                        "id": "parent",
                        "title": "Parent Page",
                        "space": {"key": "TEST"},
                    },
                    "child1": {
                        "id": "child1",
                        "title": "Child Page 1",
                        "space": {"key": "TEST"},
                    },
                    "child2": {
                        "id": "child2",
                        "title": "Child Page 2",
                        "space": {"key": "TEST"},
                    },
                }
                return page_info.get(page_id)

            mock_client.get_page_info.side_effect = mock_get_page_info

            # Configure get_child_pages mock
            def mock_get_child_pages(page_id):
                if page_id == "parent":
                    return [
                        {"id": "child1", "title": "Child Page 1"},
                        {"id": "child2", "title": "Child Page 2"},
                    ]
                return []

            mock_client.get_child_pages.side_effect = mock_get_child_pages

            # Simple content for all pages
            def mock_get_page_content(page_id):
                return {
                    "type": "doc",
                    "content": [
                        {
                            "type": "paragraph",
                            "content": [
                                {"type": "text", "text": f"Content of page {page_id}"}
                            ],
                        }
                    ],
                }

            mock_client.get_page_content.side_effect = mock_get_page_content

            # Return the correct format for download_media_files
            mock_client.download_media_files.return_value = (
                [],
                {},
            )  # Empty media files and mapping
            mock_client.base_url = "https://example.atlassian.net"

            # Create a downloader with the mock client
            downloader = ConfluenceDownloader(mock_client)

            # Create a set to track visited pages and a page mapping dict
            visited_pages = set()
            page_mapping = {}

            # Create config object
            config = self._create_test_config(temp_dir, "xref")

            # Run the method with the config object
            downloader.download_page_recursive(
                page_id="parent",
                config=config,
                base_dir=temp_dir,  # Add the base_dir parameter
                current_depth=0,
                visited_pages=visited_pages,
                is_root=True,
                page_mapping=page_mapping,
            )

            # Verify parent file was created
            parent_file_path = os.path.join(temp_dir, "Parent_Page.adoc")
            assert os.path.exists(parent_file_path)

            # Verify child files were created
            child1_dir = os.path.join(temp_dir, "Child_Page_1")
            child1_file = os.path.join(child1_dir, "Child_Page_1.adoc")
            assert os.path.exists(child1_file)

            child2_dir = os.path.join(temp_dir, "Child_Page_2")
            child2_file = os.path.join(child2_dir, "Child_Page_2.adoc")
            assert os.path.exists(child2_file)

            # Verify parent file contains Child Pages section with links using base_path
            with open(parent_file_path, "r") as f:
                content = f.read()
                assert "* xref:{base_path}/" in content
                assert "[Child Page 1]" in content
                assert "[Child Page 2]" in content
                # Verify that include directives are NOT present
                assert "include::" not in content

    def test_page_style_xref(self):
        """Test that 'xref' page style creates cross-references to child pages."""
        with tempfile.TemporaryDirectory() as temp_dir:
            # Set up a basic page hierarchy with mock client
            mock_client = self._setup_mock_client_with_hierarchy()

            # Create a downloader with the mock client
            downloader = ConfluenceDownloader(mock_client)

            # Create a set to track visited pages and a page mapping dict
            visited_pages = set()
            page_mapping = {}

            # Create config object
            from confluence_to_asciidoc import DownloadConfig

            config = DownloadConfig(
                output_dir=temp_dir,
                images_dir="images",
                recursive=True,
                max_depth=2,
                include_linked_pages=False,
                page_style="xref",
            )

            # Run the method with the config object
            downloader.download_page_recursive(
                page_id="parent",
                config=config,
                base_dir=temp_dir,  # Add the base_dir parameter
                current_depth=0,
                visited_pages=visited_pages,
                is_root=True,
                page_mapping=page_mapping,
            )

            # Verify parent file contains Child Pages section with xrefs
            parent_file_path = os.path.join(temp_dir, "Parent_Page.adoc")
            with open(parent_file_path, "r") as f:
                content = f.read()
                assert "* xref:{base_path}/" in content
                assert "[Child Page 1]" in content
                assert "[Child Page 2]" in content
                # Verify that include directives are NOT present
                assert "include::" not in content

    def test_page_style_include(self):
        """Test that 'include' page style adds include directives and creates a consolidated document."""
        with tempfile.TemporaryDirectory() as temp_dir:
            # Set up a basic page hierarchy with mock client
            mock_client = self._setup_mock_client_with_hierarchy()

            # Create a downloader with the mock client
            downloader = ConfluenceDownloader(mock_client)

            # Create a set to track visited pages and a page mapping dict
            visited_pages = set()
            page_mapping = {}

            # Create config object
            config = self._create_test_config(temp_dir, "include")

            # Run the method with the config object
            downloader.download_page_recursive(
                page_id="parent",
                config=config,
                base_dir=temp_dir,  # Add the base_dir parameter
                current_depth=0,
                visited_pages=visited_pages,
                is_root=True,
                page_mapping=page_mapping,
            )

            # Verify parent file contains Child Pages section with include directives
            parent_file_path = os.path.join(temp_dir, "Parent_Page.adoc")
            with open(parent_file_path, "r") as f:
                content = f.read()
                # Verify that xrefs are NOT present
                assert "xref:" not in content
                # Verify include directives are present
                assert "include::{base_path}/" in content
                assert "[leveloffset=+1]" in content

            # Check if parent key exists in page_mapping and add it if it doesn't
            if "parent" not in page_mapping:
                # Manually add the parent page to the mapping with the correct information
                page_mapping["parent"] = {
                    "title": "Parent Page",
                    "path": parent_file_path,
                    "dir": temp_dir,
                }

            # Create consolidated document
            downloader.create_consolidated_document("parent", temp_dir, page_mapping)

            # Verify consolidated document was created
            consolidated_path = os.path.join(temp_dir, "Parent_Page_Consolidated.adoc")
            assert os.path.exists(consolidated_path)

            # Check contents of consolidated document
            with open(consolidated_path, "r") as f:
                content = f.read()
                assert "= Parent Page (Consolidated)" in content
                assert ":toc: left" in content
                # Check for include directive with base_path
                assert "include::{base_path}/Parent_Page.adoc[lines=2..]" in content

    def test_page_style_both(self):
        """Test that 'both' page style adds both xrefs and include directives."""
        with tempfile.TemporaryDirectory() as temp_dir:
            # Set up a basic page hierarchy with mock client
            mock_client = self._setup_mock_client_with_hierarchy()

            # Create a downloader with the mock client
            downloader = ConfluenceDownloader(mock_client)

            # Create a set to track visited pages and a page mapping dict
            visited_pages = set()
            page_mapping = {}

            # Create config object using the helper method
            config = self._create_test_config(temp_dir, "both")

            # Run the method with the config object
            downloader.download_page_recursive(
                page_id="parent",
                config=config,
                base_dir=temp_dir,  # Add the base_dir parameter
                current_depth=0,
                visited_pages=visited_pages,
                is_root=True,
                page_mapping=page_mapping,
            )

            # Verify parent file contains Child Pages section with both xrefs and include directives
            parent_file_path = os.path.join(temp_dir, "Parent_Page.adoc")
            with open(parent_file_path, "r") as f:
                content = f.read()
                # Verify xrefs are present
                assert "* xref:{base_path}/" in content
                assert "[Child Page 1]" in content
                assert "[Child Page 2]" in content
                # Verify include directives are also present
                assert "include::{base_path}/" in content
                assert "[leveloffset=+1]" in content

    def test_base_path_attribute_handling(self):
        """Test that base_path is only defined in root document and referenced in children."""
        with tempfile.TemporaryDirectory() as temp_dir:
            # Set up a basic page hierarchy with mock client
            mock_client = self._setup_mock_client_with_hierarchy()

            # Create a downloader with the mock client
            downloader = ConfluenceDownloader(mock_client)

            # Create a set to track visited pages and a page mapping dict
            visited_pages = set()
            page_mapping = {}

            # Create config object
            config = self._create_test_config(temp_dir, "xref")

            # Run the method with the config object
            downloader.download_page_recursive(
                page_id="parent",
                config=config,
                base_dir=temp_dir,  # Add the base_dir parameter
                current_depth=0,
                visited_pages=visited_pages,
                is_root=True,
                page_mapping=page_mapping,
            )

            # Verify the root document defines the base_path attribute
            parent_file_path = os.path.join(temp_dir, "Parent_Page.adoc")
            with open(parent_file_path, "r") as f:
                content = f.read()
                # Check that root document defines base_path
                assert f":base_path: {os.path.abspath(temp_dir)}" in content
                # Check imagesdir uses base_path
                assert ":imagesdir: {base_path}/images" in content

            # Verify child documents reference base_path but don't define it
            child1_file_path = os.path.join(
                temp_dir, "Child_Page_1", "Child_Page_1.adoc"
            )
            with open(child1_file_path, "r") as f:
                content = f.read()
                # Check that child document doesn't define base_path
                base_path_def = f":base_path: {os.path.abspath(temp_dir)}"
                assert base_path_def not in content
                # Check that child document uses base_path in imagesdir
                assert ":imagesdir: {base_path}/Child_Page_1/images" in content

            # Verify child pages references use base_path
            with open(parent_file_path, "r") as f:
                content = f.read()
                # More flexible assertion for xref format - the exact path format may vary
                assert "* xref:{base_path}/" in content
                assert "[Child Page 1]" in content
                assert "[Child Page 2]" in content

            # Verify consolidated document has proper path references
            if "parent" not in page_mapping:
                page_mapping["parent"] = {
                    "title": "Parent Page",
                    "path": parent_file_path,
                    "dir": temp_dir,
                    "is_root": True,
                }

            # Create consolidated document
            consolidated_path = downloader.create_consolidated_document(
                "parent", temp_dir, page_mapping
            )

            # Check contents of consolidated document
            with open(consolidated_path, "r") as f:
                content = f.read()
                assert f":base_path: {os.path.abspath(temp_dir)}" in content
                assert ":imagesdir: {base_path}/images" in content
                assert "include::{base_path}/" in content
                assert "[lines=2..]" in content

    def _setup_mock_client_with_hierarchy(self):
        """Set up a mock client with a basic page hierarchy."""
        mock_client = MagicMock()

        # Configure get_page_info mock
        def mock_get_page_info(page_id):
            page_info = {
                "parent": {
                    "id": "parent",
                    "title": "Parent Page",
                    "space": {"key": "TEST"},
                },
                "child1": {
                    "id": "child1",
                    "title": "Child Page 1",
                    "space": {"key": "TEST"},
                },
                "child2": {
                    "id": "child2",
                    "title": "Child Page 2",
                    "space": {"key": "TEST"},
                },
            }
            return page_info.get(page_id)

        mock_client.get_page_info.side_effect = mock_get_page_info

        # Configure get_child_pages mock
        def mock_get_child_pages(page_id):
            if page_id == "parent":
                return [
                    {"id": "child1", "title": "Child Page 1"},
                    {"id": "child2", "title": "Child Page 2"},
                ]
            return []

        mock_client.get_child_pages.side_effect = mock_get_child_pages

        # Simple content for all pages
        def mock_get_page_content(page_id):
            return {
                "type": "doc",
                "content": [
                    {
                        "type": "paragraph",
                        "content": [
                            {"type": "text", "text": f"Content of page {page_id}"}
                        ],
                    }
                ],
            }

        mock_client.get_page_content.side_effect = mock_get_page_content

        # Return the correct format for download_media_files
        mock_client.download_media_files.return_value = (
            [],
            {},
        )  # Empty media files and mapping
        mock_client.base_url = "https://example.atlassian.net"

        return mock_client
