#!/usr/bin/env python3
"""
Test suite for the upload_to_confluence.py script.
"""

import os
import json
import pytest
import tempfile
import sys
from unittest.mock import patch, Mock, MagicMock, call

# Add the parent directory to sys.path so we can import modules directly
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from upload_to_confluence import main
from confluence_client import ConfluenceClient
from asciidoc_resources import extract_images_and_includes
from adf_resources import update_adf_media_ids, update_adf_image_dimensions


class TestUploadToConfluence:
    """Test the upload_to_confluence functions."""

    def setup_method(self):
        """Set up test environment."""
        self.base_url = "https://example.atlassian.net"
        self.username = "testuser"
        self.api_token = "testtoken"
        self.space_id = 12345
        self.page_id = "67890"
        self.title = "Test Page Title"

        # Create temporary files for testing
        self._create_temp_files()

    def teardown_method(self):
        """Clean up temporary files."""
        # Remove any temporary files created during tests
        if hasattr(self, "temp_asciidoc") and os.path.exists(self.temp_asciidoc):
            os.unlink(self.temp_asciidoc)
        if hasattr(self, "temp_adf") and os.path.exists(self.temp_adf):
            os.unlink(self.temp_adf)
        if hasattr(self, "temp_patched_adf") and os.path.exists(self.temp_patched_adf):
            os.unlink(self.temp_patched_adf)

    def _create_temp_files(self):
        """Create temporary AsciiDoc and ADF files for testing."""
        # Create a temporary AsciiDoc file with image references
        fd, self.temp_asciidoc = tempfile.mkstemp(suffix=".adoc")
        os.close(fd)
        with open(self.temp_asciidoc, "w") as f:
            f.write(
                """= Test Document
            
This is a test document with an image:

image::test_image.png[Test Image]

And another image:

image::another_image.jpg[Another Image]
            """
            )

        # Create a temporary ADF file
        fd, self.temp_adf = tempfile.mkstemp(suffix=".json")
        os.close(fd)

        # Sample ADF content with media nodes
        adf_content = {
            "version": 1,
            "type": "doc",
            "content": [
                {
                    "type": "paragraph",
                    "content": [
                        {
                            "type": "text",
                            "text": "This is a test document with an image:",
                        }
                    ],
                },
                {
                    "type": "mediaSingle",
                    "attrs": {},
                    "content": [
                        {
                            "type": "media",
                            "attrs": {
                                "id": "temp_id_1",
                                "type": "file",
                                "collection": "contentId",
                                "width": 800,
                                "height": 600,
                                "alt": "Test Image",
                                "filename": "test_image.png",
                            },
                        }
                    ],
                },
                {
                    "type": "paragraph",
                    "content": [{"type": "text", "text": "And another image:"}],
                },
                {
                    "type": "mediaSingle",
                    "attrs": {},
                    "content": [
                        {
                            "type": "media",
                            "attrs": {
                                "id": "temp_id_2",
                                "type": "file",
                                "collection": "contentId",
                                "width": 400,
                                "height": 300,
                                "alt": "Another Image",
                                "filename": "another_image.jpg",
                            },
                        }
                    ],
                },
            ],
        }

        with open(self.temp_adf, "w") as f:
            json.dump(adf_content, f)

        # Expected path for patched ADF
        self.temp_patched_adf = self.temp_adf + ".patched"

    def _create_test_images(self):
        """Create test image files."""
        # Create a test directory with image files
        self.test_img_dir = tempfile.mkdtemp()

        # Create dummy image files
        with open(os.path.join(self.test_img_dir, "test_image.png"), "wb") as f:
            f.write(b"fake png content")

        with open(os.path.join(self.test_img_dir, "another_image.jpg"), "wb") as f:
            f.write(b"fake jpg content")

        return self.test_img_dir

    @patch("upload_to_confluence.ConfluenceClient")
    @patch("upload_to_confluence.extract_images_and_includes")
    def test_create_new_page(self, mock_extract, mock_client_class):
        """Test creating a new page when page_id is not provided."""
        # Setup mocks
        mock_client = mock_client_class.return_value
        mock_client.create_empty_page.return_value = self.page_id
        mock_client.get_page_attachments.return_value = []
        mock_client.upload_images_to_confluence.return_value = {
            "test_image.png": "new_file_id_1",
            "another_image.jpg": "new_file_id_2",
        }

        # Mock the extract_images_and_includes to populate the images list
        def side_effect(path, images):
            images.extend(["test_image.png", "another_image.jpg"])

        mock_extract.side_effect = side_effect

        # Call main with click context
        from click.testing import CliRunner

        runner = CliRunner()
        result = runner.invoke(
            main,
            [
                "--atlassian-base-url",
                self.base_url,
                "--asciidoc",
                self.temp_asciidoc,
                "--adf",
                self.temp_adf,
                "--space-id",
                str(self.space_id),
                "--title",
                self.title,
                "--username",
                self.username,
                "--api-token",
                self.api_token,
            ],
        )

        # Verify command ran successfully
        assert result.exit_code == 0

        # Verify client was initialized
        mock_client_class.assert_called_once_with(
            self.base_url, self.username, self.api_token
        )

        # Verify extract_images_and_includes was called with the correct path
        # We use assert_called_once() to verify it was called once, then check args separately
        mock_extract.assert_called_once()
        args, _ = mock_extract.call_args
        assert args[0] == self.temp_asciidoc  # Check only the path

        # Verify a new page was created
        mock_client.create_empty_page.assert_called_once_with(self.space_id, self.title)

        # Verify attachments were fetched
        mock_client.get_page_attachments.assert_called_once_with(self.page_id)

        # Verify images were uploaded
        mock_client.upload_images_to_confluence.assert_called_once_with(
            ["test_image.png", "another_image.jpg"], self.page_id, {}
        )

        # Verify page content was updated
        mock_client.update_page_content.assert_called_once()

        # Verify the patched ADF was created
        assert os.path.exists(self.temp_patched_adf)

    @patch("upload_to_confluence.ConfluenceClient")
    @patch("upload_to_confluence.extract_images_and_includes")
    def test_update_existing_page(self, mock_extract, mock_client_class):
        """Test updating an existing page when page_id is provided."""
        # Setup mocks
        mock_client = mock_client_class.return_value
        mock_client.get_page_attachments.return_value = [
            {"title": "test_image.png", "extensions": {"fileId": "existing_file_id_1"}}
        ]
        mock_client.upload_images_to_confluence.return_value = {
            "test_image.png": "existing_file_id_1",  # Existing file, ID unchanged
            "another_image.jpg": "new_file_id_2",  # New file, new ID
        }

        # Mock the extract_images_and_includes to populate the images list
        def side_effect(path, images):
            images.extend(["test_image.png", "another_image.jpg"])

        mock_extract.side_effect = side_effect

        # Call main with click context
        from click.testing import CliRunner

        runner = CliRunner()
        result = runner.invoke(
            main,
            [
                "--base-url",
                self.base_url,
                "--asciidoc",
                self.temp_asciidoc,
                "--adf",
                self.temp_adf,
                "--space-id",
                str(self.space_id),
                "--title",
                self.title,
                "--username",
                self.username,
                "--api-token",
                self.api_token,
                "--page-id",
                self.page_id,
            ],
        )

        # Verify command ran successfully
        assert result.exit_code == 0

        # Verify client was initialized
        mock_client_class.assert_called_once_with(
            self.base_url, self.username, self.api_token
        )

        # Verify create_empty_page was NOT called
        mock_client.create_empty_page.assert_not_called()

        # Verify attachments were fetched
        mock_client.get_page_attachments.assert_called_once_with(self.page_id)

        # Verify images were uploaded with the current files map
        mock_client.upload_images_to_confluence.assert_called_once_with(
            ["test_image.png", "another_image.jpg"],
            self.page_id,
            {"test_image.png": "existing_file_id_1"},
        )

        # Verify page content was updated
        mock_client.update_page_content.assert_called_once()

        # Verify the patched ADF was created
        assert os.path.exists(self.temp_patched_adf)

    @patch("upload_to_confluence.ConfluenceClient")
    @patch("upload_to_confluence.extract_images_and_includes")
    def test_create_page_failure(self, mock_extract, mock_client_class):
        """Test handling failure when creating a new page."""
        # Setup mocks
        mock_client = mock_client_class.return_value
        mock_client.create_empty_page.return_value = None  # Simulate failure

        # Call main with click context
        from click.testing import CliRunner

        runner = CliRunner()
        result = runner.invoke(
            main,
            [
                "--base-url",
                self.base_url,
                "--asciidoc",
                self.temp_asciidoc,
                "--adf",
                self.temp_adf,
                "--space-id",
                str(self.space_id),
                "--title",
                self.title,
                "--username",
                self.username,
                "--api-token",
                self.api_token,
            ],
        )

        # Verify command ran but failed to create a page
        assert result.exit_code == 0
        assert "Failed to create or find page" in result.output

        # Verify create_empty_page was called but not the other methods
        mock_client.create_empty_page.assert_called_once()
        mock_client.get_page_attachments.assert_not_called()
        mock_client.upload_images_to_confluence.assert_not_called()
        mock_client.update_page_content.assert_not_called()

    @patch("upload_to_confluence.update_adf_media_ids")
    @patch("upload_to_confluence.ConfluenceClient")
    @patch("upload_to_confluence.extract_images_and_includes")
    def test_adf_media_ids_patching(
        self, mock_extract, mock_client_class, mock_update_adf
    ):
        """Test that ADF media IDs are properly updated."""
        # Setup mocks
        mock_client = mock_client_class.return_value
        mock_client.create_empty_page.return_value = self.page_id
        mock_client.get_page_attachments.return_value = []
        file_id_mapping = {
            "test_image.png": "new_file_id_1",
            "another_image.jpg": "new_file_id_2",
        }
        mock_client.upload_images_to_confluence.return_value = file_id_mapping

        # Create a patched ADF result
        patched_adf = {"type": "doc", "content": ["patched content"]}
        mock_update_adf.return_value = patched_adf

        # Mock the extract_images_and_includes to populate the images list
        def side_effect(path, images):
            images.extend(["test_image.png", "another_image.jpg"])

        mock_extract.side_effect = side_effect

        # Call main with click context
        from click.testing import CliRunner

        runner = CliRunner()
        result = runner.invoke(
            main,
            [
                "--base-url",
                self.base_url,
                "--asciidoc",
                self.temp_asciidoc,
                "--adf",
                self.temp_adf,
                "--space-id",
                str(self.space_id),
                "--title",
                self.title,
                "--username",
                self.username,
                "--api-token",
                self.api_token,
                "--page-id",
                self.page_id,
            ],
        )

        # Verify extract_images_and_includes was called
        mock_extract.assert_called_once()
        args, _ = mock_extract.call_args
        assert args[0] == self.temp_asciidoc  # Check only the path

        # Verify update_adf_media_ids was called with correct parameters
        mock_update_adf.assert_called_once()
        args, _ = mock_update_adf.call_args
        assert args[1] == file_id_mapping  # Check the file ID mapping was passed

        # Read the patched ADF file
        with open(self.temp_patched_adf, "r") as f:
            saved_patched_adf = json.load(f)

        # Verify the patched ADF was saved correctly
        assert saved_patched_adf == patched_adf

        # Verify the patched ADF was used to update the page
        mock_client.update_page_content.assert_called_once_with(
            self.page_id, patched_adf
        )
        
    @patch("upload_to_confluence.update_adf_media_ids")
    @patch("upload_to_confluence.update_adf_image_dimensions")
    @patch("upload_to_confluence.ConfluenceClient")
    @patch("upload_to_confluence.extract_images_and_includes")
    def test_max_image_width_parameter(
        self, mock_extract, mock_client_class, mock_update_dimensions, mock_update_adf
    ):
        """Test that max_image_width parameter resizes images correctly."""
        # Setup mocks
        mock_client = mock_client_class.return_value
        mock_client.create_empty_page.return_value = self.page_id
        mock_client.get_page_attachments.return_value = []
        file_id_mapping = {
            "test_image.png": "new_file_id_1",
            "another_image.jpg": "new_file_id_2",
        }
        mock_client.upload_images_to_confluence.return_value = file_id_mapping

        # Create patched ADF results
        patched_adf = {"type": "doc", "content": ["patched content"]}
        resized_adf = {"type": "doc", "content": ["resized content"]}
        
        mock_update_adf.return_value = patched_adf
        mock_update_dimensions.return_value = resized_adf

        # Mock the extract_images_and_includes to populate the images list
        def side_effect(path, images):
            images.extend(["test_image.png", "another_image.jpg"])

        mock_extract.side_effect = side_effect

        # Call main with click context and max_image_width parameter
        from click.testing import CliRunner

        runner = CliRunner()
        result = runner.invoke(
            main,
            [
                "--base-url",
                self.base_url,
                "--asciidoc",
                self.temp_asciidoc,
                "--adf",
                self.temp_adf,
                "--space-id",
                str(self.space_id),
                "--title",
                self.title,
                "--username",
                self.username,
                "--api-token",
                self.api_token,
                "--page-id",
                self.page_id,
                "--max-image-width",
                "800",
            ],
        )

        # Verify extract_images_and_includes was called
        mock_extract.assert_called_once()

        # Verify update_adf_media_ids was called with correct parameters
        mock_update_adf.assert_called_once()
        
        # Verify update_adf_image_dimensions was called with correct parameters
        mock_update_dimensions.assert_called_once_with(patched_adf, 800)

        # Read the patched ADF file
        with open(self.temp_patched_adf, "r") as f:
            saved_patched_adf = json.load(f)

        # Verify the resized ADF was saved correctly
        assert saved_patched_adf == resized_adf

        # Verify the resized ADF was used to update the page
        mock_client.update_page_content.assert_called_once_with(
            self.page_id, resized_adf
        )
        
    @patch("upload_to_confluence.update_adf_media_ids")
    @patch("upload_to_confluence.update_adf_image_dimensions")
    @patch("upload_to_confluence.ConfluenceClient")
    @patch("upload_to_confluence.extract_images_and_includes")
    def test_without_max_image_width_parameter(
        self, mock_extract, mock_client_class, mock_update_dimensions, mock_update_adf
    ):
        """Test that without max_image_width, image dimensions are not modified."""
        # Setup mocks
        mock_client = mock_client_class.return_value
        mock_client.create_empty_page.return_value = self.page_id
        mock_client.get_page_attachments.return_value = []
        file_id_mapping = {
            "test_image.png": "new_file_id_1",
            "another_image.jpg": "new_file_id_2",
        }
        mock_client.upload_images_to_confluence.return_value = file_id_mapping

        # Create patched ADF result
        patched_adf = {"type": "doc", "content": ["patched content"]}
        mock_update_adf.return_value = patched_adf

        # Mock the extract_images_and_includes to populate the images list
        def side_effect(path, images):
            images.extend(["test_image.png", "another_image.jpg"])

        mock_extract.side_effect = side_effect

        # Call main with click context without max_image_width parameter
        from click.testing import CliRunner

        runner = CliRunner()
        result = runner.invoke(
            main,
            [
                "--base-url",
                self.base_url,
                "--asciidoc",
                self.temp_asciidoc,
                "--adf",
                self.temp_adf,
                "--space-id",
                str(self.space_id),
                "--title",
                self.title,
                "--username",
                self.username,
                "--api-token",
                self.api_token,
                "--page-id",
                self.page_id,
            ],
        )

        # Verify update_adf_media_ids was called
        mock_update_adf.assert_called_once()
        
        # Verify update_adf_image_dimensions was NOT called
        mock_update_dimensions.assert_not_called()

        # Verify the original patched ADF (without resizing) was used to update the page
        mock_client.update_page_content.assert_called_once_with(
            self.page_id, patched_adf
        )


if __name__ == "__main__":
    pytest.main(["-v", "test_upload_to_confluence.py"])
