"""
ADF Node Processing Utilities

This module contains functions for processing ADF (Atlassian Document Format) nodes
and converting them to AsciiDoc.
"""

import copy
import os
import re
import html
from urllib.parse import urlparse, parse_qs
import json
import base64
import requests

from typing import Any, Dict
from confluence_client import ConfluenceClient


def process_media_node(node, context):
    """Process a media node and convert to AsciiDoc image."""
    media_id = node.get("attrs", {}).get("id", "")
    alt_text = node.get("attrs", {}).get("alt", "")

    # Look up the file name using the file_id_to_filename mapping
    file_id_to_filename = context.get("file_id_to_filename", {})

    image_filename = file_id_to_filename.get(media_id, "")  # Try to get from mapping

    # If not found in mapping, try media_files as fallback
    if not image_filename and context.get("media_files"):
        for media_file in context.get("media_files", []):
            if media_file.get("id") == media_id:
                image_filename = media_file.get("title", "")
                break

    # If still not found, use the ID but ensure it has a file extension
    if not image_filename:
        image_filename = f"{media_id}.png"
    elif "." not in image_filename:
        image_filename = f"{image_filename}.png"

    # Format as a single string to match test expectations
    if alt_text:
        return [f".{alt_text}\nimage::{image_filename}[]\n"]
    else:
        return [f"image::{image_filename}[]\n"]


def process_media_single_node(node, context):
    """Process a mediaSingle node and convert to AsciiDoc image."""
    # Get the media node
    media_nodes = [
        child for child in node.get("content", []) if child.get("type") == "media"
    ]
    if not media_nodes:
        return []

    media_node = media_nodes[0]
    return_text = process_media_node(media_node, context)

    return [f"\n{return_text[0]}"]


def process_heading_node(node, context):
    """Process a heading node and convert to AsciiDoc heading."""
    level = node.get("attrs", {}).get("level", 1)
    heading_text = get_node_text_content(node, context)
    heading_marker = "=" * level
    return [f"\n{heading_marker} {heading_text}\n"]


def process_paragraph_node(node, context, indent=""):
    """Process a paragraph node and convert to AsciiDoc paragraph."""
    # Special handling for paragraphs with mixed content (text and inline extensions)
    if node.get("content"):
        additional_processing_needs = ["inlineExtension", "mention", "inlineCard"]
        has_additional_processing_need = any(
            child.get("type") in additional_processing_needs
            for child in node.get("content", [])
        )

        if has_additional_processing_need:
            # Process each child node individually and combine
            parts = []
            for child in node.get("content", []):
                if child.get("type") in additional_processing_needs:
                    # Process inline extension nodes directly
                    extension_result = process_node(child, context)
                    parts.extend(extension_result)
                else:
                    # Process other nodes normally
                    parts.append(get_node_text_content(child, context))

            return [f"{indent}{''.join(parts)}\n"]

    # Standard handling for simple paragraphs
    paragraph_text = get_node_text_content(node, context)
    if paragraph_text.strip():
        return [f"{indent}{paragraph_text}\n"]
    return [""]


def process_table_node(node, context):
    """Process a table node and convert it to AsciiDoc."""
    # TODO: Add support for table options like width, alignments, etc.
    result = ["|===\n"]

    for row_node in node.get("content", []):
        if row_node.get("type") == "tableRow":
            row_result = process_table_row_node(row_node, context)
            result.append(row_result)

    result.append("|===\n")
    return "".join(result)


def process_table_row_node(node, context):
    """Process a table row node."""
    cells = []
    for cell_node in node.get("content", []):
        cell_text, is_complex = process_table_cell_node(cell_node, context)

        # Always include a pipe for consistency
        if is_complex:
            cells.append(f"a| {cell_text}")
        else:
            cells.append(f"| {cell_text}")

    return " ".join(cells) + "\n"


def process_table_cell_node(node, context):
    """Process a table cell node and convert it to AsciiDoc."""
    cell_context = context.copy()
    cell_context["in_table_cell"] = True

    # Process cell content
    cell_lines = []
    has_complex_content = False

    # Track if we've seen a paragraph to add an extra newline before lists
    had_paragraph = False

    for content_node in node.get("content", []):
        # Check for content types that should trigger a|
        if content_node.get("type") in [
            "bulletList",
            "orderedList",
            "codeBlock",
            "panel",
        ]:
            has_complex_content = True
            # Add an extra newline if we just processed a paragraph
            if had_paragraph and cell_lines:
                cell_lines.append("")  # Empty string will create a newline when joined

        content_result = "".join(process_node(content_node, cell_context)).strip()
        if content_result:
            cell_lines.append(content_result)

        # Track if this was a paragraph for next node
        had_paragraph = content_node.get("type") == "paragraph"

    # Join all lines in the cell
    cell_text = "\n".join(cell_lines)

    # For non-complex cells, escape pipe characters
    if not has_complex_content:
        cell_text = cell_text.replace("|", "\\|")
        # Remove the double escaping that might happen with links
        cell_text = cell_text.replace("\\\\|", "\\|")

    return cell_text, has_complex_content or "\n" in cell_text


def process_list_node(node, context, indent=""):
    """Process a list node (bulletList or orderedList) and convert to AsciiDoc list."""
    result = []

    # Determine list type and marker
    is_bullet = node.get("type") == "bulletList"
    marker = "*" if is_bullet else "."

    # Track list depth
    context["list_depth"] = context.get("list_depth", 0) + 1
    context["in_bullet_list"] = is_bullet

    # Process each list item
    for item_node in node.get("content", []):
        if item_node.get("type") == "listItem":
            # Process the list item content using the extracted method
            item_lines = process_list_item_content(item_node, context, indent)

            # Add the list item to the result
            result.append("\n".join(item_lines))

    # Reset list depth
    context["list_depth"] -= 1
    if context["list_depth"] == 0:
        context.pop("in_bullet_list", None)

    # Join list items with newlines
    joined_result = "\n".join(result)

    # In table cells, we don't add extra newlines to preserve table formatting
    if not context.get("in_table_cell") and joined_result:
        return [f"\n{joined_result}\n\n"]
    else:
        return [f"\n{joined_result}"]


def process_code_block_node(node, context):
    """Process a code block node and convert to AsciiDoc code block."""
    result = []
    language = node.get("attrs", {}).get("language", "")
    result.append(f"\n[source,{language}]")
    result.append("\n----")

    # Extract code content
    code_content = ""
    for content_node in node.get("content", []):
        if content_node.get("type") == "text":
            code_content += content_node.get("text", "")

    result.append(f"\n{code_content}")
    result.append("\n----\n")

    return result


def process_extension_node(node, context):
    """Process an extension node and convert to appropriate AsciiDoc format."""
    result = []
    ext_key = node.get("attrs", {}).get("extensionKey", "")

    # Handle TOC macro
    if ext_key == "toc":
        result.append("\n:toc:\n")

    # Handle JIRA JQL Snapshot macro
    elif ext_key == "jira-jql-snapshot":
        try:
            # Extract the macro parameters JSON string and parse it
            macro_params_str = (
                node.get("attrs", {})
                .get("parameters", {})
                .get("macroParams", {})
                .get("macroParams", {})
                .get("value", "{}")
            )

            macro_params = json.loads(macro_params_str)

            # Extract JQL and fields from the first level
            if macro_params.get("levels") and len(macro_params["levels"]) > 0:
                level = macro_params["levels"][0]
                jql = level.get("jql", "")

                # Extract field names from fieldsPosition
                fields = []
                for field_obj in level.get("fieldsPosition", []):
                    if field_obj.get("available", False) and field_obj.get(
                        "value", {}
                    ).get("id"):
                        fields.append(field_obj["value"]["id"])

                fields_str = ",".join(fields)

                # Extract the title if present
                title = level.get("title", "")

                # Create the jiraIssuesTable macro with the title as an attribute
                if title:
                    result.append(
                        f'\njiraIssuesTable::[\'{jql}\', fields="{fields_str}", title="{title}"]\n'
                    )
                else:
                    result.append(
                        f"\njiraIssuesTable::['{jql}', fields=\"{fields_str}\"]\n"
                    )
        except Exception as e:
            # Log the error but continue processing
            import logging

            logging.warning(f"Error processing jira-jql-snapshot: {str(e)}")
            result.append(f"\n// Error processing JIRA snapshot: {str(e)}\n")

    # Handle Workflow Approvers macro
    elif ext_key == "approvers-macro":
        try:
            # Verify required structure exists
            if "parameters" not in node.get("attrs", {}):
                raise ValueError("Missing required parameters structure")

            # Extract the data value parameter to determine the option
            data_value = (
                node.get("attrs", {})
                .get("parameters", {})
                .get("macroParams", {})
                .get("data", {})
                .get("value", "")
            )

            # Map the data value to the AsciiDoc option
            option = (
                "latest"
                if data_value == "Latest Approvals for Current Workflow"
                else "all"
            )

            # Create the workflowApproval macro
            result.append(f"\nworkflowApproval:{option}[]\n")
        except Exception as e:
            import logging

            logging.warning(f"Error processing approvers-macro: {str(e)}")
            result.append(f"\n// Error processing Workflow Approvers: {str(e)}\n")

    # Handle Workflow Change Table macro
    elif ext_key == "document-control-table-macro":
        try:
            # Verify required structure exists
            if "parameters" not in node.get("attrs", {}):
                raise ValueError("Missing required parameters structure")

            # The document-control-table-macro doesn't have options in the Ruby extension
            result.append("\nworkflowChangeTable:[]\n")
        except Exception as e:
            import logging

            logging.warning(f"Error processing document-control-table-macro: {str(e)}")
            result.append(f"\n// Error processing Workflow Change Table: {str(e)}\n")

    return result


def process_inline_extension_node(node, context):
    """Process an inline extension node and convert to appropriate AsciiDoc format."""
    result = []
    ext_key = node.get("attrs", {}).get("extensionKey", "")

    if ext_key == "anchor":
        # Extract anchor ID from parameters
        macro_params = (
            node.get("attrs", {}).get("parameters", {}).get("macroParams", {})
        )
        # The anchor ID is in the unnamed parameter (empty string key)
        anchor_id = macro_params.get("", {}).get("value", "")
        if anchor_id:
            # Add the anchor ID to the context for potential later reference
            context.setdefault("anchors", {})[anchor_id] = True
            # Format as AsciiDoc anchor
            result.append(f"[[{anchor_id}]]")
    elif ext_key == "metadata-macro":
        # Extract data value from macro parameters
        macro_params = (
            node.get("attrs", {}).get("parameters", {}).get("macroParams", {})
        )
        data_value = macro_params.get("data", {}).get("value", "")

        # Mapping of Confluence metadata values to appfoxWorkflowMetadata targets
        # This must match the KEYWORDS mapping in the Ruby extension
        WORKFLOW_METADATA_KEYWORDS_REVERSE = {
            "Approvers for Current Status": "approvers",
            "Current Official Version Description": "versiondesc",
            "Current Official Version": "version",
            "Expiry Date": "expiry",
            "Transition Date": "transition",
            "Unique Page ID": "pageid",
            "Workflow Status": "status",
        }

        # Lookup the target keyword for the data value
        target = WORKFLOW_METADATA_KEYWORDS_REVERSE.get(data_value)
        if target:
            result.append(f"appfoxWorkflowMetadata:{target}[]")
        else:
            # If we don't recognize the data value, just use it as-is
            result.append(f"// Unknown workflow metadata: {data_value}")

    return result


def get_node_text_content(node, context):
    """Extract text content from a node, including formatting."""
    if not node:
        return ""
    if node.get("type") == "text":
        text = node.get("text", "")
        marks = node.get("marks", [])
        link_href = None

        for mark in marks:
            mark_type = mark.get("type")
            if mark_type == "link":
                href = mark.get("attrs", {}).get("href", "")

                # Check if this is an anchor link within the same page
                if href.startswith("#"):
                    anchor_id = href[1:]  # Remove the '#' prefix
                    if context.get("anchors", {}).get(anchor_id):
                        text = f"<<{anchor_id},{text}>>"
                        continue
                # Check if this is a link to an anchor on another page
                elif "#" in href and context.get("base_url") in href:
                    parts = href.split("#")
                    page_url = parts[0]
                    anchor_id = parts[1]
                    page_id = extract_page_id_from_url(
                        page_url, context.get("base_url")
                    )

                    # Only process if we have a valid page_id and it exists in the mapping with the required structure
                    if (
                        page_id
                        and page_id in context.get("page_mapping", {})
                        and "path" in context.get("page_mapping", {}).get(page_id, {})
                    ):
                        current_dir = os.path.dirname(
                            context.get("current_file_path", "")
                        )
                        target_path = context.get("page_mapping")[page_id]["path"]
                        rel_path = os.path.relpath(target_path, current_dir)
                        text = f"xref:{rel_path}#{anchor_id}[{text}]"
                        continue
                    else:
                        # Fall back to a regular link if the page mapping doesn't have the expected structure
                        link_href = href

                # Check if this is a JIRA link
                jira_base_url = os.environ.get(
                    "JIRA_BASE_URL", "https://jira.example.com"
                )
                if href and jira_base_url in href:
                    # Extract the issue key from URL
                    match = re.search(r"/browse/([A-Z]+-\d+)", href)
                    if match:
                        issue_key = match.group(1)
                        text = f"jira:{issue_key}[]"
                        continue

                link_href = href
            elif mark_type == "strong":
                text = f"*{text}*"
            elif mark_type == "em":
                text = f"_{text}_"
            elif mark_type == "code":
                text = f"`{text}`"
            elif mark_type == "strike":
                text = f"[.line-through]#{text}#"
            elif mark_type == "subsup" and mark.get("attrs", {}).get("type") == "sub":
                text = f"~{text}~"
            elif mark_type == "subsup" and mark.get("attrs", {}).get("type") == "sup":
                text = f"^{text}^"

        # Apply link formatting after other formatting (if not already handled)
        if link_href:
            if text.startswith("*") and text.endswith("*"):
                text = text.strip("*")
                text = f"*link:{link_href}[{text}]*"
            elif text.startswith("_") and text.endswith("_"):
                text = text.strip("_")
                text = f"_link:{link_href}[{text}]_"
            else:
                text = f"link:{link_href}[{text}]"

        # Escape pipe characters in table cells
        if context.get("in_table_cell"):
            text = text.replace("|", "\\|")

        return text
    elif node.get("content") and isinstance(node.get("content"), list):
        return "".join(
            get_node_text_content(child, context) for child in node.get("content")
        )
    return ""


def process_text_node(node, context):
    """Process a text node and apply any marks."""
    text = node.get("text", "")
    marks = node.get("marks", [])

    # Apply marks to text
    for mark in marks:
        mark_type = mark.get("type", "")

        if mark_type == "strong":
            text = f"*{text}*"
        elif mark_type == "em":
            text = f"_{text}_"
        elif mark_type == "code":
            text = f"`{text}`"
        elif mark_type == "strike":
            text = f"[.line-through]#{text}#"
        elif mark_type == "underline":
            text = f"[.underline]#{text}#"
        elif mark_type == "link":
            url = mark.get("attrs", {}).get("href", "")

            # Check if this is an internal Confluence page link
            if context.get("page_mapping") and context.get("base_url") in url:
                page_id = extract_page_id_from_url(url, context.get("base_url"))
                if page_id and page_id in context.get("page_mapping"):
                    # Get the relative path from current page to target page
                    current_dir = os.path.dirname(context.get("current_file_path", ""))
                    target_path = context.get("page_mapping")[page_id]["path"]
                    rel_path = os.path.relpath(target_path, current_dir)

                    # Create AsciiDoc xref
                    text = f"xref:{rel_path}[{text}]"
                    continue

            # Regular external link
            text = f"link:{url}[{text}]"

    return text


def process_node(node, context, indent=""):
    """Process a single ADF node and convert it to AsciiDoc."""
    # Skip node if it's marked to be skipped
    if context.get("next_node_to_skip") == node:
        context.pop("next_node_to_skip")
        return []

    # Store document content for lookups when processing a doc node
    if node.get("type") == "doc":
        context["doc_content"] = node.get("content", [])

    node_type = node.get("type")

    # Delegate to specific node type processing functions
    if node_type == "mediaSingle":
        return process_media_single_node(node, context)
    elif node_type == "heading":
        return process_heading_node(node, context)
    elif node_type == "paragraph":
        return process_paragraph_node(node, context, indent)
    elif node_type == "table":
        return process_table_node(node, context)
    elif node_type == "tableRow":
        return process_table_row_node(node, context)
    elif node_type in ["tableCell", "tableHeader"]:
        cell_text, _ = process_table_cell_node(node, context, False)
        return [cell_text]
    elif node_type == "media":
        return process_media_node(node, context)
    elif node_type in ["bulletList", "orderedList"]:
        return process_list_node(node, context, indent)
    elif node_type == "listItem":
        item_lines = process_list_item_content(node, context, indent)
        return ["\n".join(item_lines)]
    elif node_type == "codeBlock":
        return process_code_block_node(node, context)
    elif node_type == "extension":
        return process_extension_node(node, context)
    elif node_type == "inlineExtension":
        return process_inline_extension_node(node, context)
    elif node_type == "mention":
        return process_mention_node(node, context)
    elif node_type == "inlineCard":
        return process_inline_card_node(node, context)  # Handle inlineCard nodes
    elif node_type == "text":
        # Handle direct text nodes
        return [process_text_node(node, context)]
    # Process any other content
    elif node.get("content") and isinstance(node.get("content"), list):
        result = []
        for content_node in node.get("content"):
            result.extend(process_node(content_node, context, indent))
        return result

    # Default case: return empty list for unhandled node types
    return []


def update_adf_media_ids(adf_json, filename_to_fileid):
    """
    Update media IDs in ADF content with file IDs from Confluence.

    Args:
        adf_json (dict): The ADF JSON structure
        filename_to_fileid (dict): Mapping of filename to Confluence file ID

    Returns:
        dict: Updated ADF JSON with replaced file IDs
    """
    if not adf_json or not filename_to_fileid:
        return adf_json

    def process_node_recursively(node):
        if not isinstance(node, dict):
            return

        # Check for media nodes
        if (
            node.get("type") in ["media", "mediaInline"]
            and node.get("attrs", {}).get("collection") == "attachments"
        ):
            current_id = node.get("attrs", {}).get("id")
            if current_id in filename_to_fileid:
                node["attrs"]["id"] = filename_to_fileid[current_id]

        # Process all child nodes recursively
        for key, value in node.items():
            if isinstance(value, dict):
                process_node_recursively(value)
            elif isinstance(value, list):
                for item in value:
                    if isinstance(item, dict):
                        process_node_recursively(item)

    # Create a copy to avoid modifying the original
    updated_adf = adf_json.copy()
    process_node_recursively(updated_adf)

    return updated_adf


def process_list_item_content(item_node, context, indent=""):
    """
    Process the content of a list item and format it for AsciiDoc.

    Args:
        item_node: The list item node to process
        context: The current processing context
        indent: The current indentation level

    Returns:
        list: Formatted list item content lines
    """
    item_marker = (
        "*" * context.get("list_depth", 1)
        if context.get("in_bullet_list", True)
        else "." * context.get("list_depth", 1)
    )

    item_lines = []
    item_context = context.copy()
    item_context["list_item_indent"] = f"{item_marker} "

    for content_node in item_node.get("content", []):
        # Add the list marker to the first paragraph
        para_indent = "" if context.get("in_table_cell") else indent

        if content_node.get("type") == "paragraph" and not item_lines:
            item_text = "".join(process_node(content_node, item_context)).rstrip()
            item_lines.append(f"{para_indent}{item_marker} {item_text}")
        elif content_node.get("type") in ["bulletList", "orderedList"]:
            # Handle nested lists - finish current item first
            if item_lines:
                # We've already started this item, so add a line break
                nested_result = "".join(
                    process_node(content_node, item_context, indent + "  ")
                )
                item_lines.append(f"\n{nested_result}")
            else:
                # This is a nested list at the start of an item
                nested_result = "".join(
                    process_node(content_node, item_context, indent)
                )
                item_lines.append(f"{para_indent}{item_marker}\n{nested_result}")
        else:
            # For subsequent paragraphs or other node types
            item_content = "".join(process_node(content_node, item_context)).rstrip()
            if item_content:
                item_lines.append(f"{indent}  {item_content}")

    return item_lines


def extract_page_id_from_url(url, base_url=None):
    """
    Extract the page ID from a Confluence URL.

    Args:
        url (str): The Confluence URL
        base_url (str, optional): The base URL of the Confluence instance

    Returns:
        str: The page ID or None if not found
    """
    if not url:
        return None

    # Parse the URL to get query parameters
    parsed_url = urlparse(url)
    query_params = parse_qs(parsed_url.query)

    # Check for pageId in query parameters
    if "pageId" in query_params:
        return query_params["pageId"][0]

    # Check for page ID in the path (some Confluence URLs use this format)
    # Example: /pages/viewpage.action/123456 or /wiki/spaces/TEST/pages/123456
    match = re.search(r"/pages/(\d+)/?", parsed_url.path)
    if match:
        return match.group(1)

    # Also check alternative formats
    match = re.search(r"/pages/viewpage.action/(\d+)/?", parsed_url.path)
    if match:
        return match.group(1)

    return None


def process_mention_node(node, context):
    """Process an ADF mention node and convert to AsciiDoc AtlasMention macro."""
    print("Processing mention node:", node)
    mention_attrs = node.get("attrs", {})
    user_id = mention_attrs.get("id", "")
    mention_text = mention_attrs.get("text", "")

    # Extract the username from the mention text (remove @ prefix)
    if mention_text.startswith("@"):
        username = mention_text[1:]
    else:
        username = mention_text

    # Convert spaces to underscores for the macro format
    macro_username = username.replace(" ", "_")

    # Store mapping of usernames to IDs in context for potential reverse conversion
    context.setdefault("mention_username_to_id", {})[macro_username] = user_id

    return [f"atlasMention:{macro_username}[]"]


def process_inline_card_node(node, context):
    """Process an inlineCard node and convert it to an AsciiDoc link with the title."""
    url = node.get("attrs", {}).get("url", "")
    if not url:
        return []

    # Use the ConfluenceClient to fetch the title
    client = context.get("confluence_client")

    if not client:
        return [f"link:{url}[{url}]"]

    title = None
    if "atlassian.net/wiki" in url:
        # Fetch Confluence page title
        title = client.get_confluence_page_title(url)
    elif "atlassian.net/browse" in url:
        # Fetch Jira ticket title
        title = client.get_jira_ticket_title(url)

    # Use the title as the link text if available, otherwise use the URL
    link_text = title if title else url
    return [f"link:{url}[{link_text}]"]


def extract_title_from_url(url, context):
    """Extract the title of the referring Confluence page or Jira ticket."""
    if "atlassian.net/wiki" in url:
        # Handle Confluence page
        return fetch_confluence_page_title(url, context)
    elif "atlassian.net/browse" in url:
        # Handle Jira ticket
        return fetch_jira_ticket_title(url, context)
    return None


def fetch_confluence_page_title(url, context):
    """Fetch the title of a Confluence page using its URL."""
    base_url = context.get("confluence_base_url", os.environ.get("CONFLUENCE_BASE_URL"))
    api_token = os.environ.get("CONFLUENCE_API_TOKEN")
    user_email = os.environ.get("CONFLUENCE_USER_EMAIL")

    if not base_url or not api_token or not user_email:
        return None

    # Extract the page ID from the URL
    page_id = extract_page_id_from_url(url, base_url)
    if not page_id:
        return None

    # Query the Confluence API for the page title
    api_url = f"{base_url}/rest/api/content/{page_id}?expand=title"
    headers = {
        "Authorization": f"Basic {base64.b64encode(f'{user_email}:{api_token}'.encode()).decode()}",
        "Content-Type": "application/json",
    }

    try:
        response = requests.get(api_url, headers=headers)
        if response.status_code == 200:
            data = response.json()
            return data.get("title")
    except Exception as e:
        import logging

        logging.warning(f"Failed to fetch Confluence page title: {e}")

    return None


def fetch_jira_ticket_title(url, context):
    """Fetch the title of a Jira ticket using its URL."""
    base_url = context.get("jira_base_url", os.environ.get("JIRA_BASE_URL"))
    api_token = os.environ.get("JIRA_API_TOKEN")
    user_email = os.environ.get("JIRA_USER_EMAIL")

    if not base_url or not api_token or not user_email:
        return None

    # Extract the issue key from the URL
    match = re.search(r"/browse/([A-Z]+-\d+)", url)
    if not match:
        return None
    issue_key = match.group(1)

    # Query the Jira API for the issue title
    api_url = f"{base_url}/rest/api/2/issue/{issue_key}"
    headers = {
        "Authorization": f"Basic {base64.b64encode(f'{user_email}:{api_token}'.encode()).decode()}",
        "Content-Type": "application/json",
    }

    try:
        response = requests.get(api_url, headers=headers)
        if response.status_code == 200:
            data = response.json()
            return data.get("fields", {}).get("summary")
    except Exception as e:
        import logging

        logging.warning(f"Failed to fetch Jira ticket title: {e}")

    return None
