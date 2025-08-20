"""
ADF Node Processing Utilities

This module contains functions for processing ADF (Atlassian Document Format) nodes
and converting them to AsciiDoc.
"""

import os
import re
from urllib.parse import urlparse, parse_qs
import json


def process_media_node(node, context):
    """Process a media node and convert to AsciiDoc image."""
    media_id = node.get("attrs", {}).get("id", "")
    alt_text = node.get("attrs", {}).get("alt", "")
    file_title = node.get("attrs", {}).get("title", "")

    file_id_to_filename = context.get("file_id_to_filename", {})

    # First try to get the filename from the mapping
    image_filename = file_id_to_filename.get(media_id, "")

    # If not found in mapping, try media_files as fallback
    if not image_filename and context.get("media_files"):
        for media_file in context.get("media_files", []):
            if media_file.get("id") == media_id:
                image_filename = media_file.get("title", "")
                break

    # If we have alt_text that looks like a filename (contains a file extension), use it
    if alt_text and "." in alt_text and not image_filename:
        image_filename = alt_text

    # If we have a title and it looks like a filename, use it
    if file_title and "." in file_title and not image_filename:
        image_filename = file_title

    # If still not found, use the ID but ensure it has a file extension
    if not image_filename:
        image_filename = f"{media_id}.png"
    elif "." not in image_filename:
        image_filename = f"{image_filename}.png"

    # If alt_text exists and it's different from the filename, use it as a caption
    if alt_text and alt_text != image_filename:
        return [f".{alt_text}\nimage::{image_filename}[]\n"]
    else:
        return [f"image::{image_filename}[]\n"]


def process_media_single_node(node, context):
    """Process a mediaSingle node and convert to AsciiDoc image."""
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
    if node.get("content"):
        additional_processing_needs = ["inlineExtension", "mention", "inlineCard"]
        has_additional_processing_need = any(
            child.get("type") in additional_processing_needs
            for child in node.get("content", [])
        )

        if has_additional_processing_need:
            parts = []
            for child in node.get("content", []):
                if child.get("type") in additional_processing_needs:
                    extension_result = process_node(child, context)
                    parts.extend(extension_result)
                else:
                    parts.append(get_node_text_content(child, context))

            return [f"{indent}{''.join(parts)}\n"]

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

        # Extract colspan and rowspan attributes
        colspan = cell_node.get("attrs", {}).get("colspan", 1)
        rowspan = cell_node.get("attrs", {}).get("rowspan", 1)

        # Create span markers for AsciiDoc
        span_marker = ""
        if colspan > 1:
            span_marker += f"{colspan}+"
        if rowspan > 1:
            span_marker += f".{rowspan}+"

        # Always include a pipe for consistency
        if is_complex:
            cells.append(f"{span_marker}a| {cell_text}")
        else:
            cells.append(f"{span_marker}| {cell_text}")

    return " ".join(cells) + "\n"


def process_table_cell_node(node, context):
    """Process a table cell node and convert it to AsciiDoc."""
    cell_context = context.copy()
    cell_context["in_table_cell"] = True

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
                cell_lines.append("")

        content_result = "".join(process_node(content_node, cell_context)).strip()
        if content_result:
            cell_lines.append(content_result)

        had_paragraph = content_node.get("type") == "paragraph"

    cell_text = "\n".join(cell_lines)

    if not has_complex_content:
        cell_text = cell_text.replace("|", "\\|")
        # Remove the double escaping that might happen with links
        cell_text = cell_text.replace("\\\\|", "\\|")

    return cell_text, has_complex_content or "\n" in cell_text


def process_list_node(node, context, indent=""):
    """Process a list node (bulletList or orderedList) and convert to AsciiDoc list."""
    result = []

    is_bullet = node.get("type") == "bulletList"
    marker = "*" if is_bullet else "."

    context["list_depth"] = context.get("list_depth", 0) + 1
    context["in_bullet_list"] = is_bullet

    for item_node in node.get("content", []):
        if item_node.get("type") == "listItem":
            item_lines = process_list_item_content(item_node, context, indent)

            result.append("\n".join(item_lines))

    context["list_depth"] -= 1
    if context["list_depth"] == 0:
        context.pop("in_bullet_list", None)

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

    if ext_key == "toc":
        result.append("\n:toc:\n")

    elif ext_key == "jira-jql-snapshot":
        try:
            macro_params_str = (
                node.get("attrs", {})
                .get("parameters", {})
                .get("macroParams", {})
                .get("macroParams", {})
                .get("value", "{}")
            )

            macro_params = json.loads(macro_params_str)

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

                title = level.get("title", "")

                if title:
                    result.append(
                        f'\njiraIssuesTable::[\'{jql}\', fields="{fields_str}", title="{title}"]\n'
                    )
                else:
                    result.append(
                        f"\njiraIssuesTable::['{jql}', fields=\"{fields_str}\"]\n"
                    )
        except Exception as e:
            import logging

            logging.warning(f"Error processing jira-jql-snapshot: {str(e)}")
            result.append(f"\n// Error processing JIRA snapshot: {str(e)}\n")

    elif ext_key == "approvers-macro":
        try:
            if "parameters" not in node.get("attrs", {}):
                raise ValueError("Missing required parameters structure")

            data_value = (
                node.get("attrs", {})
                .get("parameters", {})
                .get("macroParams", {})
                .get("data", {})
                .get("value", "")
            )

            option = (
                "latest"
                if data_value == "Latest Approvals for Current Workflow"
                else "all"
            )

            result.append(f"\nworkflowApproval:{option}[]\n")
        except Exception as e:
            import logging

            logging.warning(f"Error processing approvers-macro: {str(e)}")
            result.append(f"\n// Error processing Workflow Approvers: {str(e)}\n")

    elif ext_key == "document-control-table-macro":
        try:
            if "parameters" not in node.get("attrs", {}):
                raise ValueError("Missing required parameters structure")

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
        macro_params = (
            node.get("attrs", {}).get("parameters", {}).get("macroParams", {})
        )
        # The anchor ID is in the unnamed parameter (empty string key)
        anchor_id = macro_params.get("", {}).get("value", "")
        if anchor_id:
            context.setdefault("anchors", {})[anchor_id] = True
            result.append(f"[[{anchor_id}]]")
    elif ext_key == "metadata-macro":
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
            else:
                # Use the shared formatting function for all other mark types
                text = apply_text_formatting(text, mark_type, mark)

        # Apply link formatting after other formatting (if not already handled)
        if link_href:
            # For links with formatting, need to handle specially
            if text.startswith("*") and text.endswith("*") and not text.endswith("* "):
                # Extract the content without the markers
                inner_text = text[1:-1]
                text = f"*link:{link_href}[{inner_text}]*"
            elif (
                text.startswith("_") and text.endswith("_") and not text.endswith("_ ")
            ):
                inner_text = text[1:-1]
                text = f"_link:{link_href}[{inner_text}]_"
            else:
                # Standard link
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

    for mark in marks:
        mark_type = mark.get("type", "")

        if mark_type == "link":
            url = mark.get("attrs", {}).get("href", "")

            # Check if this is an internal Confluence page link
            if context.get("page_mapping") and context.get("base_url") in url:
                page_id = extract_page_id_from_url(url, context.get("base_url"))
                if page_id and page_id in context.get("page_mapping"):
                    # Get the relative path from current page to target page
                    current_dir = os.path.dirname(context.get("current_file_path", ""))
                    target_path = context.get("page_mapping")[page_id]["path"]
                    rel_path = os.path.relpath(target_path, current_dir)

                    text = f"xref:{rel_path}[{text}]"
                    continue

            text = f"link:{url}[{text}]"
        else:
            text = apply_text_formatting(text, mark_type, mark)

    return text


def process_node(node, context, indent=""):
    """Process a single ADF node and convert it to AsciiDoc."""
    if context.get("next_node_to_skip") == node:
        context.pop("next_node_to_skip")
        return []

    # Store document content for lookups when processing a doc node
    if node.get("type") == "doc":
        context["doc_content"] = node.get("content", [])

    node_type = node.get("type")

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
    elif node_type == "taskList":
        return process_task_list_node(node, context, indent)
    elif node_type == "taskItem":
        return process_task_item_node(node, context, indent)
    elif node_type == "codeBlock":
        return process_code_block_node(node, context)
    elif node_type == "extension":
        return process_extension_node(node, context)
    elif node_type == "inlineExtension":
        return process_inline_extension_node(node, context)
    elif node_type == "mention":
        return process_mention_node(node, context)
    elif node_type == "inlineCard":
        return process_inline_card_node(node, context)
    elif node_type == "text":
        return [process_text_node(node, context)]
    elif node.get("content") and isinstance(node.get("content"), list):
        result = []
        for content_node in node.get("content"):
            result.extend(process_node(content_node, context, indent))
        return result

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


def update_adf_image_dimensions(adf_json, max_width):
    """
    Update image/media node widths and heights in ADF JSON, clamping width and adjusting height to keep aspect ratio.

    Args:
        adf_json (dict): The ADF JSON structure
        max_width (int): Maximum allowed width for images (pixels)

    Returns:
        dict: Updated ADF JSON with clamped image dimensions
    """
    if not adf_json or not max_width:
        return adf_json

    def process_node_recursively(node):
        if not isinstance(node, dict):
            return

        # Check for media/mediaInline nodes with width/height
        if node.get("type") in ["media", "mediaInline", "mediaSingle"]:
            attrs = node.get("attrs", {})
            width = attrs.get("width")
            height = attrs.get("height")
            # Only clamp if width is set and greater than max_width
            if width and isinstance(width, (int, float)) and width > max_width:
                # If height is set, adjust to keep aspect ratio
                if height and isinstance(height, (int, float)) and width > 0:
                    aspect = height / width
                    attrs["width"] = max_width
                    attrs["height"] = int(round(max_width * aspect))
                else:
                    attrs["width"] = max_width
                node["attrs"] = attrs

        # Process all child nodes recursively
        for key, value in node.items():
            if isinstance(value, dict):
                process_node_recursively(value)
            elif isinstance(value, list):
                for item in value:
                    if isinstance(item, dict):
                        process_node_recursively(item)

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
    mention_attrs = node.get("attrs", {})
    user_id = mention_attrs.get("id", "")
    mention_text = mention_attrs.get("text", "")

    if mention_text.startswith("@"):
        username = mention_text[1:]
    else:
        username = mention_text

    macro_username = username.replace(" ", "_")

    context.setdefault("mention_username_to_id", {})[macro_username] = user_id

    return [f"atlasMention:{macro_username}[]"]


def extract_title_from_url(url, context):
    """Extract the title of the referring Confluence page or Jira ticket."""
    client = context.get("confluence_client")
    if not client:
        return None

    if "atlassian.net/wiki" in url:
        return client.get_confluence_page_title(url)
    elif "atlassian.net/browse" in url:
        return client.get_jira_ticket_title(url)
    return None


def process_inline_card_node(node, context):
    """Process an inlineCard node and convert it to an AsciiDoc link with the title."""
    url = node.get("attrs", {}).get("url", "")
    if not url:
        return []

    client = context.get("confluence_client")
    if not client:
        return [f"link:{url}[{url}]"]

    title = extract_title_from_url(url, context)
    link_text = title if title else url
    return [f"link:{url}[{link_text}]"]


def process_task_list_node(node, context, indent=""):
    """Process a taskList node and convert it to a bulleted AsciiDoc list."""
    result = ["\n"]

    for task_item in node.get("content", []):
        if task_item.get("type") == "taskItem":
            result.extend(process_task_item_node(task_item, context, indent))

    return result


def process_task_item_node(node, context, indent=""):
    """Process a taskItem node and convert it to a bulleted AsciiDoc list item."""
    state = node.get("attrs", {}).get("state", "TODO")
    checkbox = "[x]" if state == "DONE" else "[ ]"

    task_text = get_node_text_content(node, context)

    return [f"{indent}* {checkbox} {task_text}\n"]


def apply_text_formatting(text, mark_type, mark=None):
    """
    Apply AsciiDoc formatting to text based on mark type.

    Args:
        text (str): The text to format
        mark_type (str): The type of formatting to apply
        mark (dict, optional): The full mark object with additional attributes

    Returns:
        str: The formatted text with preserved trailing whitespace
    """
    # Get the content and trailing whitespace separately
    content = text.rstrip()
    trailing_space = text[len(content) :]

    # Apply formatting to the content only
    if mark_type == "strong":
        return f"*{content}*{trailing_space}"

    elif mark_type == "em":
        return f"_{content}_{trailing_space}"

    elif mark_type == "code":
        return f"`{content}`{trailing_space}"

    elif mark_type == "strike":
        return f"[.line-through]#{content}#{trailing_space}"

    elif mark_type == "underline":
        return f"[.underline]#{content}#{trailing_space}"

    elif mark_type == "subsup" and mark and mark.get("attrs", {}).get("type") == "sub":
        return f"~{content}~{trailing_space}"

    elif mark_type == "subsup" and mark and mark.get("attrs", {}).get("type") == "sup":
        return f"^{content}^{trailing_space}"

    # Return original text if no formatting applied
    return text
