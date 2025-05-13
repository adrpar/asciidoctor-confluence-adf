import os
import json
import requests
import mimetypes
from urllib.parse import urljoin


def create_empty_page(base_url, space_id, title, username, api_token):
    """Create an empty draft page and return its ID."""
    url = urljoin(base_url, "/wiki/api/v2/pages")
    data = {
        "title": title,
        "status": "draft",
        "spaceId": space_id,
        "body": {
            "value": json.dumps(
                {
                    "version": 1,
                    "type": "doc",
                    "content": [{"type": "paragraph", "content": []}],
                }
            ),
            "representation": "atlas_doc_format",
        },
    }
    headers = {
        "Content-Type": "application/json",
        "Authorization": requests.auth._basic_auth_str(username, api_token),
    }
    response = requests.post(url, headers=headers, data=json.dumps(data))
    if response.status_code in (200, 201):
        print("Empty page created.")
        return response.json()["id"]
    else:
        print(f"Failed to create empty page: {response.status_code} - {response.text}")
        return None


def get_page_info(base_url, page_id, username, api_token):
    """Fetch current page information."""
    url = urljoin(base_url, f"/wiki/api/v2/pages/{page_id}")
    headers = {"Authorization": requests.auth._basic_auth_str(username, api_token)}
    response = requests.get(url, headers=headers)
    if response.status_code == 200:
        return response.json()
    else:
        print(f"Failed to fetch page info: {response.status_code} - {response.text}")
        return None


def update_page_content(base_url, page_id, adf_json, username, api_token):
    """Update the page with the actual ADF content."""
    page_info = get_page_info(base_url, page_id, username, api_token)
    current_version = page_info["version"]["number"]
    title = page_info["title"]
    status = page_info["status"]

    inner_json_str = json.dumps(adf_json)
    data = {
        "id": page_id,
        "status": status,
        "title": title,
        "version": {"number": current_version},
        "body": {"value": inner_json_str, "representation": "atlas_doc_format"},
    }
    url = urljoin(base_url, f"/wiki/api/v2/pages/{page_id}")
    headers = {
        "Content-Type": "application/json",
        "Authorization": requests.auth._basic_auth_str(username, api_token),
    }
    response = requests.put(url, headers=headers, data=json.dumps(data))
    if response.status_code in (200, 201):
        print("Page content updated.")
    else:
        print(
            f"Failed to update page content: {response.status_code} - {response.text}"
        )


def upload_images_to_confluence(base_url, images, page_id, username, api_token):
    """Upload images to Confluence."""
    filename_to_fileid = {}
    for image in images:
        if not os.path.exists(image):
            raise FileNotFoundError(f"Image not found: {image}")

        with open(image, "rb") as img_file:
            img_data = img_file.read()

        filename = os.path.basename(image)
        url = urljoin(
            base_url, f"/wiki/rest/api/content/{page_id}/child/attachment?status=draft"
        )

        mime_type, _ = mimetypes.guess_type(filename)
        if not mime_type:
            mime_type = "application/octet-stream"

        files = {"file": (filename, img_data, mime_type)}

        headers = {
            "Authorization": requests.auth._basic_auth_str(username, api_token),
            "X-Atlassian-Token": "no-check",
        }

        response = requests.post(url, headers=headers, files=files)

        if response.status_code in (200, 201):
            file_id = response.json()["results"][0]["extensions"]["fileId"]
            print(f"Uploaded image: {filename} with ID: {file_id}")
            filename_to_fileid[filename] = file_id
        else:
            print(
                f"Failed to upload image {filename}: {response.status_code} - {response.text}"
            )
    return filename_to_fileid
