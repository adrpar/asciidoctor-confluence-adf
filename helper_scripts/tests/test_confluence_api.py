import pytest
import tempfile
import os
import json
from unittest.mock import patch, MagicMock
from helper_scripts import confluence_api


def test_create_empty_page_success():
    with patch("requests.post") as mock_post:
        mock_response = MagicMock()
        mock_response.status_code = 201
        mock_response.json.return_value = {"id": "12345"}
        mock_post.return_value = mock_response

        page_id = confluence_api.create_empty_page(
            "https://example.atlassian.net", 123, "Test Title", "user", "token"
        )
        assert page_id == "12345"


def test_create_empty_page_failure():
    with patch("requests.post") as mock_post:
        mock_response = MagicMock()
        mock_response.status_code = 400
        mock_response.text = "Bad Request"
        mock_post.return_value = mock_response

        page_id = confluence_api.create_empty_page(
            "https://example.atlassian.net", 123, "Test Title", "user", "token"
        )
        assert page_id is None


def test_get_page_info_success():
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

        info = confluence_api.get_page_info(
            "https://example.atlassian.net", "12345", "user", "token"
        )
        assert info["id"] == "12345"
        assert info["title"] == "Test"


def test_get_page_info_failure():
    with patch("requests.get") as mock_get:
        mock_response = MagicMock()
        mock_response.status_code = 404
        mock_response.text = "Not Found"
        mock_get.return_value = mock_response

        info = confluence_api.get_page_info(
            "https://example.atlassian.net", "12345", "user", "token"
        )
        assert info is None


def test_update_page_content_success():
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
        confluence_api.update_page_content(
            "https://example.atlassian.net", "12345", {"foo": "bar"}, "user", "token"
        )


def test_update_page_content_failure():
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
        confluence_api.update_page_content(
            "https://example.atlassian.net", "12345", {"foo": "bar"}, "user", "token"
        )


def test_upload_images_to_confluence_success(tmp_path):
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

        result = confluence_api.upload_images_to_confluence(
            "https://example.atlassian.net", images, "12345", "user", "token"
        )
        assert result["test.png"] == "fileid-123"


def test_upload_images_to_confluence_missing_file(tmp_path):
    images = [str(tmp_path / "notfound.png")]
    with pytest.raises(FileNotFoundError):
        confluence_api.upload_images_to_confluence(
            "https://example.atlassian.net", images, "12345", "user", "token"
        )


def test_upload_images_to_confluence_skips_unchanged(tmp_path):
    # Create a fake image file
    img = tmp_path / "test.png"
    img.write_bytes(b"fakeimg")
    images = [str(img)]

    # Patch checksum to match
    with patch("requests.get") as mock_get, \
         patch("requests.post") as mock_post, \
         patch("helper_scripts.confluence_api._calculate_file_sha256", return_value="abc"), \
         patch("helper_scripts.confluence_api._calculate_remote_sha256", return_value="abc"), \
         patch("helper_scripts.confluence_api.get_page_attachments") as mock_get_attachments:

        # Simulate existing attachment
        mock_get_attachments.return_value = [{
            "title": "test.png",
            "extensions": {"fileId": "fileid-123"},
            "id": "attid-1",
            "_links": {"download": "/download/test.png"}
        }]
        current_files = {"test.png": "fileid-123"}

        result = confluence_api.upload_images_to_confluence(
            "https://example.atlassian.net", images, "12345", "user", "token", current_files
        )
        assert result["test.png"] == "fileid-123"
        assert mock_post.call_count == 0  # No upload


def test_upload_images_to_confluence_replaces_and_deletes(tmp_path):
    # Create a fake image file
    img = tmp_path / "test.png"
    img.write_bytes(b"fakeimg")
    images = [str(img)]

    with patch("requests.get") as mock_get, \
         patch("requests.post") as mock_post, \
         patch("helper_scripts.confluence_api._calculate_file_sha256", return_value="abc"), \
         patch("helper_scripts.confluence_api._calculate_remote_sha256", return_value="def"), \
         patch("helper_scripts.confluence_api.get_page_attachments") as mock_get_attachments, \
         patch("helper_scripts.confluence_api.delete_attachment") as mock_delete:

        # Simulate existing attachment with different checksum
        mock_get_attachments.return_value = [{
            "title": "test.png",
            "extensions": {"fileId": "fileid-123"},
            "id": "attid-1",
            "_links": {"download": "/download/test.png"}
        }]
        mock_response = MagicMock()
        mock_response.status_code = 201
        mock_response.json.return_value = {
            "results": [{"extensions": {"fileId": "fileid-456"}}]
        }
        mock_post.return_value = mock_response
        current_files = {"test.png": "fileid-123"}

        result = confluence_api.upload_images_to_confluence(
            "https://example.atlassian.net", images, "12345", "user", "token", current_files
        )
        assert result["test.png"] == "fileid-456"
        assert mock_post.call_count == 1  # Upload happened
        mock_delete.assert_called_once_with(
            "https://example.atlassian.net", "attid-1", "user", "token"
        )


def test_delete_attachment_success():
    with patch("requests.delete") as mock_delete:
        mock_response = MagicMock()
        mock_response.status_code = 204
        mock_delete.return_value = mock_response
        assert confluence_api.delete_attachment("https://example.atlassian.net", "attid-1", "user", "token")


def test_delete_attachment_failure():
    with patch("requests.delete") as mock_delete:
        mock_response = MagicMock()
        mock_response.status_code = 400
        mock_response.text = "Bad Request"
        mock_delete.return_value = mock_response
        assert not confluence_api.delete_attachment("https://example.atlassian.net", "attid-1", "user", "token")
