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
