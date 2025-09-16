import os
import json
import requests
import mimetypes
import hashlib
from urllib.parse import urljoin, urlparse, parse_qs
import re


class ConfluenceClient:
    """Client for interacting with Confluence API."""

    def __init__(
        self,
        base_url=os.environ.get("CONFLUENCE_BASE_URL"),
        username=os.environ.get("CONFLUENCE_USER_EMAIL"),
        api_token=os.environ.get("CONFLUENCE_API_TOKEN"),
        jira_base_url=None,
    ):
        """Initialize the Confluence client.

        Args:
            base_url (str): Base URL of your Confluence instance (e.g. https://your-domain.atlassian.net)
            username (str): Confluence username (email)
            api_token (str): Confluence API token
            jira_base_url (str, optional): Base URL of your Jira instance. Defaults to base_url.
        """
        self.base_url = base_url
        self.username = username
        self.api_token = api_token
        self.jira_base_url = jira_base_url or base_url

    def _auth_headers(self, content_type=None, atlassian_token=None):
        """Create authentication headers for API requests."""
        headers = {
            "Authorization": requests.auth._basic_auth_str(
                self.username, self.api_token
            )
        }
        if content_type:
            headers["Content-Type"] = content_type
        if atlassian_token:
            headers["X-Atlassian-Token"] = atlassian_token
        return headers

    def create_empty_page(self, space_id, title):
        """Create an empty draft page and return its ID."""
        url = urljoin(self.base_url, "/wiki/api/v2/pages")
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

        response = self._make_request(
            url, method="POST", data=json.dumps(data), content_type="application/json"
        )

        if response:
            print("Empty page created.")
            return response["id"]
        else:
            print("Failed to create empty page")
            return None

    def get_page_info(self, page_id):
        """Fetch current page information."""
        url = urljoin(self.base_url, f"/wiki/api/v2/pages/{page_id}")
        response = self._make_request(url)

        if response:
            return response
        else:
            print(f"Failed to fetch page info for page ID: {page_id}")
            return None

    def get_page_content(self, page_id):
        """Get the ADF content of a Confluence page."""
        url = urljoin(self.base_url, f"/wiki/api/v2/pages/{page_id}")
        params = {"body-format": "atlas_doc_format"}

        response = self._make_request(url, params=params)

        if response:
            data = response
            body_content = data.get("body", {})

            # Check if the content is nested in atlas_doc_format
            if "atlas_doc_format" in body_content:
                # The value is a JSON string that needs to be parsed
                adf_json_str = body_content["atlas_doc_format"]["value"]
                return json.loads(adf_json_str)

            return body_content
        else:
            print(f"Error retrieving page content for page ID: {page_id}")
            return None

    def update_page_content(self, page_id, adf_json):
        """Update the page with the actual ADF content."""
        page_info = self.get_page_info(page_id)
        if not page_info:
            return False
        
        new_version = page_info["version"]["number"] + 1 if page_info["status"] != "draft" else page_info["version"]["number"]
        title = page_info["title"]
        status = page_info["status"]

        inner_json_str = json.dumps(adf_json)
        data = {
            "id": page_id,
            "status": status,
            "title": title,
            "version": {"number": new_version},
            "body": {"value": inner_json_str, "representation": "atlas_doc_format"},
        }

        url = urljoin(self.base_url, f"/wiki/api/v2/pages/{page_id}")
        response = self._make_request(
            url, method="PUT", data=json.dumps(data), content_type="application/json"
        )

        if response:
            print("Page content updated.")
            return True
        else:
            print("Failed to update page content")
            return False

    def get_page_attachments(self, page_id):
        """Get all attachments for a page with pagination support."""
        url_template = "/wiki/rest/api/content/{page_id}/child/attachment"
        path_params = {"page_id": page_id}
        query_params = {"expand": "extensions"}

        return self._paginate(
            url_template=url_template,
            path_params=path_params,
            query_params=query_params,
            limit=50,
        )

    def delete_attachment(self, attachment_id):
        """Delete an attachment by its ID."""
        delete_url = urljoin(self.base_url, f"/wiki/rest/api/content/{attachment_id}")
        response = self._make_request(delete_url, method="DELETE")

        if response:
            print(f"Deleted attachment (id: {attachment_id})")
            return True
        else:
            print(f"Failed to delete attachment (id: {attachment_id})")
            return False

    def _get_attachment_download_url(self, attachment):
        """Get the download URL for an attachment."""
        download_path = attachment.get("_links", {}).get("download")
        if not download_path:
            return None

        if not download_path.startswith("/wiki"):
            download_path = (
                "/wiki" + download_path
                if not download_path.startswith("/")
                else "/wiki" + download_path
            )
        return urljoin(self.base_url, download_path)

    def _calculate_file_sha256(self, filepath):
        """Calculate SHA256 checksum of a local file."""
        sha256 = hashlib.sha256()
        with open(filepath, "rb") as f:
            for chunk in iter(lambda: f.read(8192), b""):
                sha256.update(chunk)
        return sha256.hexdigest()

    def _calculate_remote_sha256(self, url):
        """Calculate SHA256 checksum of a remote file."""
        sha256 = hashlib.sha256()
        response = self._make_request(url, stream=True)

        if response:
            for chunk in response.iter_content(8192):
                sha256.update(chunk)
            return sha256.hexdigest()
        else:
            print(f"Failed to download attachment for checksum from URL: {url}")
            return None

    def upload_images_to_confluence(self, images, page_id, current_files=None):
        """Upload images to Confluence, skipping unchanged files (by checksum).
        If an attachment is updated, remove the old one after successful upload.

        Args:
            images (list): List of image file paths to upload
            page_id (str): ID of the Confluence page
            current_files (dict, optional): Map of existing file names to file IDs

        Returns:
            dict: Mapping from filenames to file IDs in Confluence
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

        # Determine page status to decide correct attachment endpoint (draft vs current)
        page_status = "current"
        page_info = self.get_page_info(page_id)
        if page_info:
            page_status = page_info.get("status", "current")
        else:
            page_status = "current"

        attachment_endpoint = f"/wiki/rest/api/content/{page_id}/child/attachment"
        if page_status == "draft":
            attachment_endpoint += "?status=draft"

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
                    attachments = self.get_page_attachments(page_id)
                    attachments_by_name = {att["title"]: att for att in attachments}
                attachment = attachments_by_name.get(filename)
                if attachment:
                    remote_url = self._get_attachment_download_url(attachment)
                    if remote_url:
                        local_sha = self._calculate_file_sha256(image)
                        remote_sha = self._calculate_remote_sha256(remote_url)
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

                url = urljoin(self.base_url, attachment_endpoint)

                mime_type, _ = mimetypes.guess_type(filename)
                if not mime_type:
                    mime_type = "application/octet-stream"

                files = {"file": (filename, img_data, mime_type)}

                response = requests.post(
                    url,
                    headers=self._auth_headers(atlassian_token="no-check"),
                    files=files,
                )

                if response.status_code in (200, 201):
                    file_id = response.json()["results"][0]["extensions"]["fileId"]
                    print(f"Uploaded image: {filename} with ID: {file_id}")
                    filename_to_fileid[filename] = file_id

                    # Remove old attachment if it existed and was replaced
                    if old_attachment_id:
                        self.delete_attachment(old_attachment_id)
                else:
                    print(
                        f"Failed to upload image {filename}: {response.status_code} - {response.text}"
                    )
        return filename_to_fileid

    def download_media_files(self, page_id, output_dir):
        """Download all media files attached to a Confluence page."""
        media_files = []
        file_id_to_filename = {}  # Create mapping of ID to filename

        # Get all attachments with pagination
        url_template = "/wiki/rest/api/content/{page_id}/child/attachment"
        path_params = {"page_id": page_id}
        
        # Use the _paginate method to get all attachments
        attachments = self._paginate(
            url_template=url_template,
            path_params=path_params,
            limit=50
        )
        
        # If no attachments found with the first URL format, try alternative format
        if not attachments:
            url_template = "/rest/api/content/{page_id}/child/attachment"
            attachments = self._paginate(
                url_template=url_template,
                path_params=path_params,
                limit=50
            )

        if not attachments:
            print(f"No attachments found for page {page_id}")
            return [], {}  # Return empty lists for both values

        # Download each attachment that is a media file
        for attachment in attachments:
            attachment_id = attachment.get("id")
            attachment_title = attachment.get("title", "")

            # Skip non-media files
            if not self._is_media_file(attachment_title):
                print(f"Skipping non-media file: {attachment_title}")
                continue

            # Get UUID from the attachment metadata
            attachment_uuid = None
            if "extensions" in attachment:
                attachment_uuid = attachment.get("extensions", {}).get("fileId")
            elif "metadata" in attachment:
                attachment_uuid = attachment.get("metadata", {}).get(
                    "mediaId"
                ) or attachment.get("metadata", {}).get("fileId")

            # Sanitize filename
            safe_filename = sanitize_filename(attachment_title)

            # Check if file already exists
            output_path = os.path.join(output_dir, safe_filename)
            if os.path.exists(output_path):
                print(f"File already exists, skipping download: {safe_filename}")

                # Still add to media_files list and mapping
                media_files.append(
                    {
                        "id": attachment_id,
                        "uuid": attachment_uuid,
                        "title": safe_filename,
                        "path": output_path,
                    }
                )

                # Add to mapping
                file_id_to_filename[attachment_id] = safe_filename

                # If we have a UUID, also map it to the filename
                if attachment_uuid:
                    file_id_to_filename[attachment_uuid] = safe_filename

                continue

            # File doesn't exist, download it
            download_url = f"{self.base_url}/wiki/rest/api/content/{page_id}/child/attachment/{attachment_id}/download"

            try:
                # Make download request
                response = requests.get(
                    download_url, headers=self._auth_headers(), stream=True
                )

                if response.status_code == 200:
                    # Save file
                    with open(output_path, "wb") as f:
                        for chunk in response.iter_content(chunk_size=8192):
                            if chunk:  # Filter out keep-alive empty chunks
                                f.write(chunk)

                    print(f"Downloaded {safe_filename}")

                    # Add to media_files list
                    media_files.append(
                        {
                            "id": attachment_id,
                            "uuid": attachment_uuid,
                            "title": safe_filename,
                            "path": output_path,
                        }
                    )

                    # Add to mapping
                    file_id_to_filename[attachment_id] = safe_filename

                    # If we have a UUID, also map it to the filename
                    if attachment_uuid:
                        file_id_to_filename[attachment_uuid] = safe_filename
                else:
                    print(
                        f"Failed to download attachment {attachment_id}: {response.status_code}"
                    )

            except Exception as e:
                print(f"Error downloading attachment {attachment_id}: {str(e)}")

        return media_files, file_id_to_filename  # Always return both values

    def get_child_pages(self, page_id):
        """Get all direct child pages of a Confluence page with pagination support."""
        url_template = "/wiki/rest/api/content/{page_id}/child/page"
        path_params = {"page_id": page_id}

        return self._paginate(
            url_template=url_template, path_params=path_params, limit=50
        )

    def _make_request(
        self,
        url,
        method="GET",
        data=None,
        params=None,
        files=None,
        content_type=None,
        stream=False,
        atlassian_token=None,
    ):
        """Make a request to the Confluence API with authentication.

        Args:
            url (str): The URL to make the request to
            method (str): HTTP method (GET, POST, PUT, DELETE)
            data (dict/str): JSON data or string data for the request body
            params (dict): Query parameters
            files (dict): Files to upload
            content_type (str): Content type header
            stream (bool): Whether to stream the response
            atlassian_token (str): Value for X-Atlassian-Token header

        Returns:
            dict/bytes/None: Response data or None if request failed
        """
        headers = self._auth_headers(
            content_type=content_type, atlassian_token=atlassian_token
        )

        try:
            if method == "GET":
                response = requests.get(
                    url, headers=headers, params=params, stream=stream
                )
            elif method == "POST":
                if files:
                    response = requests.post(
                        url, headers=headers, params=params, files=files
                    )
                else:
                    response = requests.post(
                        url, headers=headers, params=params, data=data
                    )
            elif method == "PUT":
                response = requests.put(url, headers=headers, params=params, data=data)
            elif method == "DELETE":
                response = requests.delete(url, headers=headers, params=params)
            else:
                print(f"Unsupported method: {method}")
                return None

            if response.status_code in (200, 201, 204):
                if stream:
                    return response
                elif response.content:
                    try:
                        return response.json()
                    except ValueError:
                        return response.content
                else:
                    return True
            else:
                print(f"Request failed: {url} ({response.status_code})")
                print(f"Response: {response.text[:200]}...")
                return None
        except Exception as e:
            print(f"Error making request to {url}: {str(e)}")
            return None

    def _is_media_file(self, filename):
        """Check if the file is an image or other media type we want to download."""
        media_extensions = [
            ".png",
            ".jpg",
            ".jpeg",
            ".gif",
            ".svg",
            ".mp4",
            ".webp",
            ".pdf",
            ".bmp",
            ".tiff",
        ]
        return any(filename.lower().endswith(ext) for ext in media_extensions)

    def get_confluence_page_title(self, url):
        """Fetch the title of a Confluence page using its URL."""
        page_id = self._extract_page_id_from_url(url)
        if not page_id:
            return None

        api_url = f"{self.base_url}/wiki/rest/api/content/{page_id}?expand=title"
        headers = self._auth_headers(content_type="application/json")

        try:
            response = requests.get(api_url, headers=headers)
            if response.status_code == 200:
                data = response.json()
                return data.get("title")
        except Exception as e:
            print(f"Failed to fetch Confluence page title: {e}")
        return None

    def get_jira_ticket_title(self, url):
        """Fetch the title of a Jira ticket using its URL."""
        issue_key = self._extract_jira_issue_key_from_url(url)
        if not issue_key:
            return None

        api_url = f"{self.jira_base_url}/rest/api/2/issue/{issue_key}"
        headers = self._auth_headers(content_type="application/json")

        try:
            response = requests.get(api_url, headers=headers)
            if response.status_code == 200:
                data = response.json()
                return data.get("fields", {}).get("summary")
        except Exception as e:
            print(f"Failed to fetch Jira ticket title: {e}")
        return None

    def _extract_page_id_from_url(self, url):
        """Extract the page ID from a Confluence URL."""
        parsed_url = urlparse(url)
        query_params = parse_qs(parsed_url.query)

        # Check for pageId in query parameters
        if "pageId" in query_params:
            return query_params["pageId"][0]

        # Check for page ID in the path
        match = re.search(r"/pages/(\d+)", parsed_url.path)
        if match:
            return match.group(1)
        return None

    def _extract_jira_issue_key_from_url(self, url):
        """Extract the issue key from a Jira URL."""
        match = re.search(r"/browse/([A-Z]+-\d+)", url)
        if match:
            return match.group(1)
        return None

    def _paginate(self, url_template, path_params=None, query_params=None, limit=50):
        """Generic pagination method for Confluence API endpoints.

        Args:
            url_template (str): URL template with {path_param} placeholders
            path_params (dict): Parameters to substitute in the URL path
            query_params (dict): Additional query parameters
            limit (int): Number of items per page

        Returns:
            list: Combined results from all pages
        """
        all_results = []
        start = 0
        path_params = path_params or {}
        query_params = query_params or {}

        while True:
            # Build URL with path parameters
            url_path = url_template.format(**path_params)

            # Make sure we have a complete URL by joining it with base_url
            # urljoin will handle making sure we don't have double slashes
            full_url = urljoin(self.base_url, url_path)

            # Add pagination and other query parameters
            current_params = {"start": start, "limit": limit, **query_params}

            response = self._make_request(full_url, params=current_params)

            if not response:
                break

            results = response.get("results", [])
            all_results.extend(results)

            # Check if there are more pages based on _links.next
            if "next" not in response.get("_links", {}):
                break

            start += limit

        return all_results


def sanitize_filename(filename):
    """Convert a string to a valid filename."""
    # Remove invalid characters and replace spaces with underscores
    valid_chars = "-_.() abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    return "".join(c for c in filename if c in valid_chars).replace(" ", "_")
