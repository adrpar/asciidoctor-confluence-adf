import os
import json
import requests
import mimetypes
import hashlib
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
        "version": {"number": current_version + 1},  # increment version!
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


def get_page_attachments(base_url, page_id, username, api_token):
    """Get all attachments for a page."""
    url = urljoin(
        base_url, f"/wiki/rest/api/content/{page_id}/child/attachment?expand=extensions"
    )
    headers = {"Authorization": requests.auth._basic_auth_str(username, api_token)}
    response = requests.get(url, headers=headers)
    if response.status_code == 200:
        return response.json().get("results", [])
    else:
        print(f"Failed to fetch attachments: {response.status_code} - {response.text}")
        return []


def _get_attachment_download_url(base_url, attachment):
    download_path = attachment.get("_links", {}).get("download")
    if not download_path:
        return None

    if not download_path.startswith("/wiki"):
        download_path = "/wiki" + download_path if not download_path.startswith("/") else "/wiki" + download_path
    return urljoin(base_url, download_path)


def _calculate_file_sha256(filepath):
    sha256 = hashlib.sha256()
    with open(filepath, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            sha256.update(chunk)
    return sha256.hexdigest()


def _calculate_remote_sha256(url, username, api_token):
    sha256 = hashlib.sha256()
    headers = {"Authorization": requests.auth._basic_auth_str(username, api_token)}
    response = requests.get(url, headers=headers, stream=True)

    if response.status_code == 200:
        for chunk in response.iter_content(8192):
            sha256.update(chunk)
        return sha256.hexdigest()
    else:
        print(
            f"Failed to download attachment for checksum: {response.status_code} - {response.text}"
        )
        return None

def delete_attachment(base_url, attachment_id, username, api_token):
    """Delete an attachment by its ID."""
    delete_url = urljoin(base_url, f"/wiki/rest/api/content/{attachment_id}")
    del_headers = {
        "Authorization": requests.auth._basic_auth_str(username, api_token),
    }
    del_response = requests.delete(delete_url, headers=del_headers)
    if del_response.status_code in (200, 204):
        print(f"Deleted attachment (id: {attachment_id})")
        return True
    else:
        print(
            f"Failed to delete attachment (id: {attachment_id}): {del_response.status_code} - {del_response.text}"
        )
        return False


def upload_images_to_confluence(
    base_url, images, page_id, username, api_token, current_files=None
):
    """Upload images to Confluence, skipping unchanged files (by checksum).
    If an attachment is updated, remove the old one after successful upload.
    """
    filename_to_fileid = {}
    current_files = current_files or {}

    # Build a map: filename -> attachment object
    attachments_by_name = (
        {att["title"]: att for att in current_files.values()}
        if isinstance(current_files, dict)
        and any(isinstance(v, dict) for v in current_files.values())
        else {}
    )

    for image in images:
        if not os.path.exists(image):
            raise FileNotFoundError(f"Image not found: {image}")

        filename = os.path.basename(image)
        needs_upload = True
        old_attachment_id = None

        # If file exists, compare checksum
        if filename in current_files:
            # If current_files is a dict of {filename: fileId}, get attachment info from API
            if not attachments_by_name:
                attachments = get_page_attachments(
                    base_url, page_id, username, api_token
                )
                attachments_by_name = {att["title"]: att for att in attachments}
            attachment = attachments_by_name.get(filename)
            if attachment:
                remote_url = _get_attachment_download_url(base_url, attachment)
                if remote_url:
                    local_sha = _calculate_file_sha256(image)
                    remote_sha = _calculate_remote_sha256(
                        remote_url, username, api_token
                    )
                    if local_sha == remote_sha:
                        filename_to_fileid[filename] = attachment["extensions"][
                            "fileId"
                        ]
                        print(f"Skipping unchanged image: {filename}")
                        needs_upload = False
                    else:
                        old_attachment_id = attachment["id"]

        if needs_upload:
            with open(image, "rb") as img_file:
                img_data = img_file.read()

            url = urljoin(
                base_url,
                f"/wiki/rest/api/content/{page_id}/child/attachment?status=draft",
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

                # Remove old attachment if it existed and was replaced
                if old_attachment_id:
                    delete_attachment(base_url, old_attachment_id, username, api_token)
            else:
                print(
                    f"Failed to upload image {filename}: {response.status_code} - {response.text}"
                )
    return filename_to_fileid
