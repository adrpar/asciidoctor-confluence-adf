import pytest
import tempfile
import os
import json
import sys
from unittest.mock import patch, MagicMock

# Add the parent directory to sys.path so we can import modules directly
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

# Direct import from the module
from confluence_client import ConfluenceClient


@pytest.fixture
def client():
    return ConfluenceClient("https://example.atlassian.net", "user", "token")


def test_create_empty_page_success(client):
    with patch("requests.post") as mock_post:
        mock_response = MagicMock()
        mock_response.status_code = 201
        mock_response.json.return_value = {"id": "12345"}
        mock_post.return_value = mock_response

        page_id = client.create_empty_page(123, "Test Title")
        assert page_id == "12345"


def test_create_empty_page_failure(client):
    with patch("requests.post") as mock_post:
        mock_response = MagicMock()
        mock_response.status_code = 400
        mock_response.text = "Bad Request"
        mock_post.return_value = mock_response

        page_id = client.create_empty_page(123, "Test Title")
        assert page_id is None


def test_get_page_info_success(client):
    with patch("requests.get") as mock_get:
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            "id": "12345",
            "title": "Test",
            "version": {"number": 1},
            "status": "draft",
        }
        mock_get.return_value = mock_response

        info = client.get_page_info("12345")
        assert info["id"] == "12345"
        assert info["title"] == "Test"


def test_get_page_info_failure(client):
    with patch("requests.get") as mock_get:
        mock_response = MagicMock()
        mock_response.status_code = 404
        mock_response.text = "Not Found"
        mock_get.return_value = mock_response

        info = client.get_page_info("12345")
        assert info is None


def test_update_page_content_success(client):
    with patch("requests.get") as mock_get, patch("requests.put") as mock_put:
        # Mock get_page_info
        mock_get_response = MagicMock()
        mock_get_response.status_code = 200
        mock_get_response.json.return_value = {
            "id": "12345",
            "title": "Test",
            "version": {"number": 1},
            "status": "draft",
        }
        mock_get.return_value = mock_get_response

        # Mock put
        mock_put_response = MagicMock()
        mock_put_response.status_code = 200
        mock_put.return_value = mock_put_response

        # Should not raise
        result = client.update_page_content("12345", {"foo": "bar"})
        assert result is True


def test_update_page_content_failure(client):
    with patch("requests.get") as mock_get, patch("requests.put") as mock_put:
        # Mock get_page_info
        mock_get_response = MagicMock()
        mock_get_response.status_code = 200
        mock_get_response.json.return_value = {
            "id": "12345",
            "title": "Test",
            "version": {"number": 1},
            "status": "draft",
        }
        mock_get.return_value = mock_get_response

        # Mock put
        mock_put_response = MagicMock()
        mock_put_response.status_code = 400
        mock_put_response.text = "Bad Request"
        mock_put.return_value = mock_put_response

        # Should not raise, just print error
        result = client.update_page_content("12345", {"foo": "bar"})
        assert result is False


def test_upload_images_to_confluence_success(client, tmp_path):
    # Create a fake image file
    img = tmp_path / "test.png"
    img.write_bytes(b"fakeimg")
    images = [str(img)]

    with patch("requests.post") as mock_post:
        mock_response = MagicMock()
        mock_response.status_code = 201
        mock_response.json.return_value = {
            "results": [{"extensions": {"fileId": "fileid-123"}}]
        }
        mock_post.return_value = mock_response

        result = client.upload_images_to_confluence(images, "12345")
        assert result["test.png"] == "fileid-123"


def test_upload_images_to_confluence_missing_file(client, tmp_path):
    images = [str(tmp_path / "notfound.png")]
    with pytest.raises(FileNotFoundError):
        client.upload_images_to_confluence(images, "12345")


def test_upload_images_to_confluence_skips_unchanged(client, tmp_path):
    # Create a fake image file
    img = tmp_path / "test.png"
    img.write_bytes(b"fakeimg")
    images = [str(img)]

    # Patch checksum to match
    with patch("requests.get") as mock_get, patch("requests.post") as mock_post, patch(
        "confluence_client.ConfluenceClient._calculate_file_sha256", return_value="abc"
    ), patch(
        "confluence_client.ConfluenceClient._calculate_remote_sha256",
        return_value="abc",
    ), patch(
        "confluence_client.ConfluenceClient.get_page_attachments"
    ) as mock_get_attachments:
        # Simulate existing attachment
        mock_get_attachments.return_value = [
            {
                "title": "test.png",
                "extensions": {"fileId": "fileid-123"},
                "id": "attid-1",
                "_links": {"download": "/download/test.png"},
            }
        ]
        current_files = {"test.png": "fileid-123"}

        result = client.upload_images_to_confluence(images, "12345", current_files)
        assert result["test.png"] == "fileid-123"
        assert mock_post.call_count == 0  # No upload


def test_upload_images_to_confluence_replaces_and_deletes(client, tmp_path):
    # Create a fake image file
    img = tmp_path / "test.png"
    img.write_bytes(b"fakeimg")
    images = [str(img)]

    with patch("requests.get") as mock_get, patch("requests.post") as mock_post, patch(
        "confluence_client.ConfluenceClient._calculate_file_sha256", return_value="abc"
    ), patch(
        "confluence_client.ConfluenceClient._calculate_remote_sha256",
        return_value="def",
    ), patch(
        "confluence_client.ConfluenceClient.get_page_attachments"
    ) as mock_get_attachments, patch(
        "confluence_client.ConfluenceClient.delete_attachment"
    ) as mock_delete:
        # Simulate existing attachment with different checksum
        mock_get_attachments.return_value = [
            {
                "title": "test.png",
                "extensions": {"fileId": "fileid-123"},
                "id": "attid-1",
                "_links": {"download": "/download/test.png"},
            }
        ]
        mock_response = MagicMock()
        mock_response.status_code = 201
        mock_response.json.return_value = {
            "results": [{"extensions": {"fileId": "fileid-456"}}]
        }
        mock_post.return_value = mock_response
        current_files = {"test.png": "fileid-123"}

        result = client.upload_images_to_confluence(images, "12345", current_files)
        assert result["test.png"] == "fileid-456"
        assert mock_post.call_count == 1  # Upload happened
        mock_delete.assert_called_once_with("attid-1")


def test_delete_attachment_success(client):
    with patch("requests.delete") as mock_delete:
        mock_response = MagicMock()
        mock_response.status_code = 204
        mock_delete.return_value = mock_response
        assert client.delete_attachment("attid-1")


def test_delete_attachment_failure(client):
    with patch("requests.delete") as mock_delete:
        mock_response = MagicMock()
        mock_response.status_code = 400
        mock_response.text = "Bad Request"
        mock_delete.return_value = mock_response
        assert not client.delete_attachment("attid-1")


def test_download_media_files(client):
    with patch("requests.get") as mock_get:
        # Mock the attachment list request
        attachments_response = MagicMock()
        attachments_response.status_code = 200
        attachments_response.json.return_value = {
            "results": [
                {"id": "att1", "title": "image.png"},
                {"id": "att2", "title": "document.pdf"},
                {"id": "att3", "title": "text.txt"},  # Should be filtered out
            ]
        }

        # Mock the file download request
        download_response = MagicMock()
        download_response.status_code = 200
        download_response.iter_content.return_value = [b"test content"]

        # Make the mock return different responses based on URLs
        def get_side_effect(*args, **kwargs):
            url = args[0]
            if "child/attachment" in url:
                return attachments_response
            else:
                return download_response

        mock_get.side_effect = get_side_effect

        # Create a temporary directory for the test
        with tempfile.TemporaryDirectory() as tmpdirname:
            media_files, file_id_to_filename = client.download_media_files(
                "12345", tmpdirname
            )
            # Should download 2 files (ignores text.txt)
            assert len(media_files) == 2
            assert media_files[0]["id"] == "att1"
            assert media_files[1]["id"] == "att2"


def test_is_media_file(client):
    # Test positive cases
    assert client._is_media_file("image.png") is True
    assert client._is_media_file("photo.jpg") is True
    assert client._is_media_file("document.PDF") is True

    # Test negative cases
    assert client._is_media_file("script.js") is False
    assert client._is_media_file("document.txt") is False


def test_get_child_pages_success(client):
    """Test successful retrieval of child pages."""
    with patch("requests.get") as mock_get:
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            "results": [
                {"id": "page1", "title": "Child Page 1"},
                {"id": "page2", "title": "Child Page 2"},
            ]
        }
        mock_get.return_value = mock_response

        child_pages = client.get_child_pages("12345")

        # Verify the API was called with the correct URL
        mock_get.assert_called_once()
        call_args = mock_get.call_args[0][0]
        assert "12345/child/page" in call_args

        # Verify results
        assert len(child_pages) == 2
        assert child_pages[0]["id"] == "page1"
        assert child_pages[1]["title"] == "Child Page 2"


def test_get_child_pages_failure(client):
    """Test handling of failed child pages retrieval."""
    with patch("requests.get") as mock_get:
        mock_response = MagicMock()
        mock_response.status_code = 404
        mock_response.text = "Not Found"
        mock_get.return_value = mock_response

        child_pages = client.get_child_pages("12345")

        # Verify empty list is returned on failure
        assert isinstance(child_pages, list)
        assert len(child_pages) == 0


def test_download_media_files_with_content():
    """Test that media files are downloaded with correct content."""
    client = ConfluenceClient("https://example.com", "user", "pass")

    with patch("requests.get") as mock_get:
        # Mock the attachment list request
        attachments_response = MagicMock()
        attachments_response.status_code = 200
        attachments_response.json.return_value = {
            "results": [
                {
                    "id": "att123",
                    "title": "test.png",
                    "metadata": {"mediaId": "uuid-123"},
                }
            ]
        }

        # Mock the file download request
        download_response = MagicMock()
        download_response.status_code = 200

        # Return a generator function for iter_content to avoid exhaustion
        def mock_iter_content(chunk_size=None):
            yield b"test image content"

        download_response.iter_content.side_effect = mock_iter_content

        # Set up the mock response based on URL
        def get_side_effect(*args, **kwargs):
            url = args[0]
            if "attachment" in url and not "download" in url:
                return attachments_response
            elif "download" in url:
                return download_response
            else:
                raise ValueError(f"Unexpected URL: {url}")

        mock_get.side_effect = get_side_effect

        # Create a temporary directory for the test
        with tempfile.TemporaryDirectory() as tmpdirname:
            media_files, file_id_to_filename = client.download_media_files(
                "12345", tmpdirname
            )

            # Check media_files has correct data
            assert len(media_files) == 1
            assert media_files[0]["id"] == "att123"
            assert media_files[0]["title"] == "test.png"

            # Check mapping includes both ID and UUID
            assert file_id_to_filename["att123"] == "test.png"
            assert file_id_to_filename["uuid-123"] == "test.png"

            # Verify the file exists and has correct content
            file_path = os.path.join(tmpdirname, "test.png")
            assert os.path.exists(file_path)

            with open(file_path, "rb") as f:
                content = f.read()
                assert content == b"test image content"


def test_file_id_to_filename_mapping():
    """Test that the file_id_to_filename mapping includes both UUID and attachment ID."""
    client = ConfluenceClient("https://example.com", "user", "pass")

    with patch("requests.get") as mock_get:
        # Mock the attachment list request with both UUIDs and attachment IDs
        attachments_response = MagicMock()
        attachments_response.status_code = 200
        attachments_response.json.return_value = {
            "results": [
                {
                    "id": "att123",
                    "title": "image1.png",
                    "metadata": {"mediaId": "uuid-123"},
                },
                {
                    "id": "att456",
                    "title": "image2.jpg",
                    "extensions": {"fileId": "uuid-456"},
                },
            ]
        }

        # Mock the download response
        download_response = MagicMock()
        download_response.status_code = 200
        download_response.iter_content.side_effect = lambda chunk_size: iter(
            [b"content"]
        )

        # Set up the mock response based on URL
        def get_side_effect(*args, **kwargs):
            def test_download_media_files_failed_attachment_list():
                """Test error handling when attachment list request fails."""
                client = ConfluenceClient("https://example.com", "user", "pass")

                with patch("requests.get") as mock_get:
                    # Mock failed attachment list request
                    failed_response = MagicMock()
                    failed_response.status_code = 404
                    mock_get.return_value = failed_response

                    with tempfile.TemporaryDirectory() as tmpdirname:
                        media_files, file_id_to_filename = client.download_media_files(
                            "12345", tmpdirname
                        )

                        # Should return empty results
                        assert len(media_files) == 0
                        assert len(file_id_to_filename) == 0

            def test_download_media_files_alternate_url():
                """Test fetching attachments using the alternate URL format."""
                client = ConfluenceClient("https://example.com", "user", "pass")

                with patch("requests.get") as mock_get:
                    # Mock responses for different URLs
                    primary_url_response = MagicMock()
                    primary_url_response.status_code = 404  # Primary URL fails

                    alternate_url_response = MagicMock()
                    alternate_url_response.status_code = 200
                    alternate_url_response.json.return_value = {
                        "results": [{"id": "att123", "title": "test.png"}]
                    }

                    download_response = MagicMock()
                    download_response.status_code = 200
                    download_response.iter_content.return_value = iter(
                        [b"test content"]
                    )

                    # Set up mock to return different responses based on URL
                    def get_side_effect(*args, **kwargs):
                        url = args[0]
                        if (
                            "/wiki/rest/api/content/" in url
                            and "child/attachment" in url
                            and not "download" in url
                        ):
                            return primary_url_response
                        elif (
                            "/rest/api/content/" in url
                            and "child/attachment" in url
                            and not "download" in url
                        ):
                            return alternate_url_response
                        else:
                            return download_response

                    mock_get.side_effect = get_side_effect

                    with tempfile.TemporaryDirectory() as tmpdirname:
                        media_files, file_id_to_filename = client.download_media_files(
                            "12345", tmpdirname
                        )

                        # Should download the file using alternate URL
                        assert len(media_files) == 1
                        assert media_files[0]["id"] == "att123"
                        assert file_id_to_filename["att123"] == "test.png"

            def test_download_media_files_no_media_found():
                """Test when no media files are found in attachments."""
                client = ConfluenceClient("https://example.com", "user", "pass")

                with patch("requests.get") as mock_get:
                    # Mock attachment list with only non-media files
                    attachments_response = MagicMock()
                    attachments_response.status_code = 200
                    attachments_response.json.return_value = {
                        "results": [
                            {"id": "att1", "title": "document.txt"},
                            {"id": "att2", "title": "script.js"},
                        ]
                    }

                    mock_get.return_value = attachments_response

                    with tempfile.TemporaryDirectory() as tmpdirname:
                        media_files, file_id_to_filename = client.download_media_files(
                            "12345", tmpdirname
                        )

                        # Should return empty results (no media files)
                        assert len(media_files) == 0
                        assert len(file_id_to_filename) == 0

            def test_download_media_files_download_failure():
                """Test handling of file download failures."""
                client = ConfluenceClient("https://example.com", "user", "pass")

                with patch("requests.get") as mock_get:
                    # Mock the attachment list request
                    attachments_response = MagicMock()
                    attachments_response.status_code = 200
                    attachments_response.json.return_value = {
                        "results": [
                            {"id": "att1", "title": "success.png"},
                            {"id": "att2", "title": "failure.jpg"},
                        ]
                    }

                    # Create responses with different status codes
                    def create_response(status_code, content=None):
                        response = MagicMock()
                        response.status_code = status_code
                        if content and status_code == 200:
                            response.iter_content.return_value = iter([content])
                        return response

                    # Set up mock to return different responses based on URL
                    def get_side_effect(*args, **kwargs):
                        url = args[0]
                        if "child/attachment" in url and not "download" in url:
                            return create_response(200)
                        elif "download" in url and "att1" in url:
                            return create_response(200, b"success content")
                        elif "download" in url and "att2" in url:
                            return create_response(404)
                        else:
                            return create_response(404)

                    # Configure the mock
                    mock_get.side_effect = get_side_effect
                    attachments_response.json.return_value = {
                        "results": [
                            {"id": "att1", "title": "success.png"},
                            {"id": "att2", "title": "failure.jpg"},
                        ]
                    }

                    with tempfile.TemporaryDirectory() as tmpdirname:
                        media_files, file_id_to_filename = client.download_media_files(
                            "12345", tmpdirname
                        )

                        # Should only include the successfully downloaded file
                        assert len(media_files) == 1
                        assert media_files[0]["id"] == "att1"
                        assert file_id_to_filename["att1"] == "success.png"
                        assert "att2" not in file_id_to_filename

            def test_download_media_files_exception_handling():
                """Test exception handling during file download."""
                client = ConfluenceClient("https://example.com", "user", "pass")

                with patch("requests.get") as mock_get:
                    # Mock the attachment list request
                    attachments_response = MagicMock()
                    attachments_response.status_code = 200
                    attachments_response.json.return_value = {
                        "results": [{"id": "att1", "title": "image.png"}]
                    }

                    # Mock a download that raises an exception
                    def side_effect(*args, **kwargs):
                        url = args[0]
                        if "child/attachment" in url and not "download" in url:
                            return attachments_response
                        else:
                            raise ConnectionError("Network error")

                    mock_get.side_effect = side_effect

                    with tempfile.TemporaryDirectory() as tmpdirname:
                        media_files, file_id_to_filename = client.download_media_files(
                            "12345", tmpdirname
                        )

                        # Should handle the exception and return empty mappings
                        assert len(media_files) == 0
                        assert len(file_id_to_filename) == 0
