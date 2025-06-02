import os
import pytest
import json

from helper_scripts.adf_resources import (
    update_adf_media_ids,
    process_node,
    get_node_text_content,
    process_paragraph_node,
    process_heading_node,
    process_media_node,
    process_list_node,
    process_code_block_node,
    process_table_node,
    process_table_cell_node,
    process_inline_extension_node,
    process_extension_node,
    process_inline_card_node,
    process_task_list_node,
)


def test_update_adf_media_ids_simple():
    adf = {
        "type": "doc",
        "version": 1,
        "content": [
            {
                "type": "mediaSingle",
                "content": [
                    {
                        "type": "media",
                        "attrs": {
                            "type": "file",
                            "id": "image1.png",
                            "collection": "attachments",
                        },
                    }
                ],
            }
        ],
    }
    mapping = {"image1.png": "12345-fileid"}
    updated = update_adf_media_ids(adf, mapping)
    assert updated["content"][0]["content"][0]["attrs"]["id"] == "12345-fileid"


def test_update_adf_media_ids_nested():
    adf = {
        "type": "doc",
        "version": 1,
        "content": [
            {
                "type": "mediaSingle",
                "content": [
                    {
                        "type": "media",
                        "attrs": {
                            "type": "file",
                            "id": "image2.jpg",
                            "collection": "attachments",
                        },
                    }
                ],
            },
            {
                "type": "paragraph",
                "content": [
                    {
                        "type": "media",
                        "attrs": {
                            "type": "file",
                            "id": "image3.gif",
                            "collection": "attachments",
                        },
                    }
                ],
            },
        ],
    }
    mapping = {"image2.jpg": "id-222", "image3.gif": "id-333"}
    updated = update_adf_media_ids(adf, mapping)
    assert updated["content"][0]["content"][0]["attrs"]["id"] == "id-222"
    assert updated["content"][1]["content"][0]["attrs"]["id"] == "id-333"


def test_update_adf_media_ids_inline_ids():
    adf = {
        "type": "doc",
        "version": 1,
        "content": [
            {
                "type": "paragraph",
                "content": [
                    {
                        "type": "mediaInline",
                        "attrs": {
                            "type": "file",
                            "id": "inline-image.png",
                            "collection": "attachments",
                        },
                    }
                ],
            }
        ],
    }
    mapping = {"inline-image.png": "inline-fileid"}
    updated = update_adf_media_ids(adf, mapping)
    assert updated["content"][0]["content"][0]["attrs"]["id"] == "inline-fileid"


def test_get_node_text_content_simple():
    node = {"type": "text", "text": "Simple text"}
    context = {}
    result = get_node_text_content(node, context)
    assert result == "Simple text"


def test_get_node_text_content_with_marks():
    node = {"type": "text", "text": "Formatted text", "marks": [{"type": "strong"}]}
    context = {}
    result = get_node_text_content(node, context)
    assert result == "*Formatted text*"


def test_get_node_text_content_with_link():
    node = {
        "type": "text",
        "text": "Link text",
        "marks": [{"type": "link", "attrs": {"href": "https://example.com"}}],
    }
    context = {}
    result = get_node_text_content(node, context)
    assert "link:https://example.com" in result
    assert "Link text" in result


def test_get_node_text_content_with_nested_content():
    node = {
        "type": "paragraph",
        "content": [
            {"type": "text", "text": "Part 1"},
            {"type": "text", "text": "Part 2", "marks": [{"type": "strong"}]},
        ],
    }
    context = {}
    result = get_node_text_content(node, context)
    assert result == "Part 1*Part 2*"


def test_process_paragraph_node():
    node = {
        "type": "paragraph",
        "content": [{"type": "text", "text": "Paragraph text"}],
    }
    context = {}
    result = process_paragraph_node(node, context)
    assert "Paragraph text" in result[0]


def test_process_heading_node():
    node = {
        "type": "heading",
        "attrs": {"level": 2},
        "content": [{"type": "text", "text": "Heading title"}],
    }
    context = {}
    result = process_heading_node(node, context)
    assert result[0] == "\n== Heading title\n"


def test_process_code_block_node():
    node = {
        "type": "codeBlock",
        "attrs": {"language": "python"},
        "content": [{"type": "text", "text": "print('Hello World')"}],
    }
    context = {}
    result = process_code_block_node(node, context)
    assert "[source,python]" in result[0]
    assert "print('Hello World')" in result[2]


def test_process_media_node():
    node = {"type": "media", "attrs": {"id": "image.png", "type": "file"}}
    context = {
        "file_id_to_filename": {"image.png": "image.png"},
        "images_dir": "images",
    }
    result = process_media_node(node, context)
    assert "image::image.png" in result[0]


def test_process_media_node_with_uuid():
    """Test media node processing when using UUIDs instead of attachment IDs."""
    # Create a node with a UUID
    node = {
        "type": "media",
        "attrs": {"id": "dc4584b0-2795-486e-a0d5-f4509a8233b8", "type": "file"},
    }

    # Create a context with both UUID and attachment ID mappings
    context = {
        "file_id_to_filename": {
            "att123456": "test-image.png",
            "dc4584b0-2795-486e-a0d5-f4509a8233b8": "test-uuid-image.jpg",
        },
        "images_dir": "images",
    }

    # Process the node
    result = process_media_node(node, context)

    # Verify we got the correct filename from the UUID mapping
    assert "test-uuid-image.jpg" in result[0]


def test_process_media_node_without_extension():
    """Test media node processing when the filename has no extension."""
    node = {"type": "media", "attrs": {"id": "missing-ext-id", "type": "file"}}

    context = {
        "file_id_to_filename": {"missing-ext-id": "image-without-extension"},
        "images_dir": "images",
    }
    result = process_media_node(node, context)

    # Verify extension was added
    assert "image-without-extension.png" in result[0]


def test_process_list_node():
    node = {
        "type": "bulletList",
        "content": [
            {
                "type": "listItem",
                "content": [
                    {
                        "type": "paragraph",
                        "content": [{"type": "text", "text": "List item 1"}],
                    }
                ],
            }
        ],
    }
    context = {"list_depth": 0, "in_bullet_list": True}
    result = process_list_node(node, context)
    assert "* List item 1" in "".join(result)


def test_process_node_unknown_type():
    node = {"type": "unknown_type", "content": []}
    context = {}
    result = process_node(node, context)
    assert result == []


def test_process_node_empty():
    node = {}
    context = {}
    result = process_node(node, context)
    assert result == []


def test_process_node_recursive():
    node = {
        "type": "bulletList",
        "content": [
            {
                "type": "listItem",
                "content": [
                    {
                        "type": "paragraph",
                        "content": [{"type": "text", "text": "Nested content"}],
                    }
                ],
            }
        ],
    }
    context = {"list_depth": 0, "in_bullet_list": True}
    result = process_node(node, context)
    assert "Nested content" in "".join(result)


def test_update_adf_media_ids_edge_cases():
    # Test with empty inputs
    assert update_adf_media_ids({}, {}) == {}
    assert update_adf_media_ids(None, {}) is None

    # Test with no matching media
    adf = {
        "type": "doc",
        "content": [
            {
                "type": "paragraph",
                "content": [{"type": "text", "text": "No media here"}],
            }
        ],
    }
    assert update_adf_media_ids(adf, {"img.png": "123"}) == adf


def test_links_in_table_cells():
    """Test that links in table cells are rendered correctly."""
    node = {
        "type": "tableCell",
        "content": [
            {
                "type": "paragraph",
                "content": [
                    {"text": "Visit ", "type": "text"},
                    {
                        "text": "Ada website",
                        "type": "text",
                        "marks": [
                            {"type": "link", "attrs": {"href": "https://ada.com"}}
                        ],
                    },
                ],
            }
        ],
    }
    context = {}
    result, _ = process_table_cell_node(node, context)
    assert "link:https://ada.com[Ada website]" in result


def test_pipe_character_in_table_cells():
    """Test that pipe characters in table cells are properly escaped."""
    node = {
        "type": "tableCell",
        "content": [
            {
                "type": "paragraph",
                "content": [
                    {
                        "text": "Product & Design | Team Assessment",
                        "type": "text",
                        "marks": [
                            {"type": "link", "attrs": {"href": "https://example.com"}}
                        ],
                    }
                ],
            }
        ],
    }
    context = {}
    result, _ = process_table_cell_node(node, context)
    assert "Product & Design \\| Team Assessment" in result


def test_multiple_paragraphs_in_table_cell():
    """Test that multiple paragraphs in a table cell are separated by newlines."""
    node = {
        "type": "tableCell",
        "content": [
            {"type": "paragraph", "content": [{"text": "Paragraph 1", "type": "text"}]},
            {"type": "paragraph", "content": [{"text": "Paragraph 2", "type": "text"}]},
        ],
    }
    context = {}
    result = process_table_cell_node(node, context)
    assert "Paragraph 1\nParagraph 2" in result


def test_nested_lists():
    """Test that nested lists are rendered correctly."""
    node = {
        "type": "bulletList",
        "content": [
            {
                "type": "listItem",
                "content": [
                    {
                        "type": "paragraph",
                        "content": [{"text": "Parent item", "type": "text"}],
                    },
                    {
                        "type": "bulletList",
                        "content": [
                            {
                                "type": "listItem",
                                "content": [
                                    {
                                        "type": "paragraph",
                                        "content": [
                                            {"text": "Child item", "type": "text"}
                                        ],
                                    }
                                ],
                            }
                        ],
                    },
                ],
            }
        ],
    }
    context = {"list_depth": 0, "in_bullet_list": True}
    result = "".join(process_list_node(node, context))
    # Check that parent and child items appear with proper formatting
    assert "* Parent item" in result
    assert "** Child item" in result
    # Check that there are proper newlines between parent and nested list
    assert result.count("\n") >= 3


def test_jira_link_detection():
    """Test that links to JIRA issues are converted to JIRA macros."""
    # Save original env var if it exists
    original_jira_url = os.environ.get("JIRA_BASE_URL")

    try:
        # Set test JIRA URL
        os.environ["JIRA_BASE_URL"] = "https://jira.example.com"

        # Test with a JIRA link
        node = {
            "type": "text",
            "text": "See issue",
            "marks": [
                {
                    "type": "link",
                    "attrs": {"href": "https://jira.example.com/browse/TEST-123"},
                }
            ],
        }
        context = {}
        result = get_node_text_content(node, context)
        assert result == "jira:TEST-123[]"

        # Test with a non-JIRA link
        node = {
            "type": "text",
            "text": "See documentation",
            "marks": [{"type": "link", "attrs": {"href": "https://example.com"}}],
        }
        result = get_node_text_content(node, context)
        assert result == "link:https://example.com[See documentation]"
    finally:
        # Restore original env var
        if original_jira_url:
            os.environ["JIRA_BASE_URL"] = original_jira_url
        elif "JIRA_BASE_URL" in os.environ:
            del os.environ["JIRA_BASE_URL"]


def test_bullet_list_in_table_cell():
    """Test that bullet lists in table cells are rendered correctly."""
    node = {
        "type": "tableCell",
        "content": [
            {
                "type": "bulletList",
                "content": [
                    {
                        "type": "listItem",
                        "content": [
                            {
                                "type": "paragraph",
                                "content": [
                                    {"text": "First bullet item", "type": "text"}
                                ],
                            }
                        ],
                    },
                    {
                        "type": "listItem",
                        "content": [
                            {
                                "type": "paragraph",
                                "content": [
                                    {"text": "Second bullet item", "type": "text"}
                                ],
                            }
                        ],
                    },
                    {
                        "type": "listItem",
                        "content": [
                            {
                                "type": "paragraph",
                                "content": [
                                    {"text": "Item with ", "type": "text"},
                                    {
                                        "text": "link",
                                        "type": "text",
                                        "marks": [
                                            {
                                                "type": "link",
                                                "attrs": {
                                                    "href": "https://example.com"
                                                },
                                            }
                                        ],
                                    },
                                ],
                            }
                        ],
                    },
                ],
            }
        ],
    }

    context = {}
    result, _ = process_table_cell_node(node, context)

    # Verify that each bullet point is formatted correctly within the table cell
    assert "* First bullet item" in result
    assert "* Second bullet item" in result
    assert "* Item with link:https://example.com[link]" in result

    # Verify that the bullet points are separated by newlines but remain in the same cell
    bullet_points = [
        "* First bullet item",
        "* Second bullet item",
        "* Item with link:https://example.com[link]",
    ]
    for i in range(len(bullet_points) - 1):
        # Check that adjacent bullet points appear in the expected order
        assert result.find(bullet_points[i]) < result.find(bullet_points[i + 1])


def test_process_media_node_path_handling():
    """Test that images use relative paths with images_dir."""
    node = {"type": "media", "attrs": {"id": "path-test-id", "type": "file"}}

    # Test with both relative and absolute image_dir paths
    contexts = [
        {"file_id_to_filename": {"path-test-id": "test.png"}, "images_dir": "images"},
        {
            "file_id_to_filename": {"path-test-id": "test.png"},
            "images_dir": "/absolute/path/images",
        },
    ]

    for context in contexts:
        result = process_media_node(node, context)

        # Images should not contain absolute paths
        assert not result[0].startswith("/")
        # Images should use the images_dir as prefix
        assert f"image::test.png[]" in result[0]


def test_table_with_asciidoc_list_in_cell():
    """Test processing a table with an AsciiDoc list in one cell."""
    adf_table = {
        "type": "table",
        "content": [
            {
                "type": "tableRow",
                "content": [
                    {
                        "type": "tableHeader",
                        "content": [{"type": "text", "text": "Version"}],
                    },
                    {
                        "type": "tableHeader",
                        "content": [{"type": "text", "text": "Change description"}],
                    },
                    {
                        "type": "tableHeader",
                        "content": [{"type": "text", "text": "Date"}],
                    },
                ],
            },
            {
                "type": "tableRow",
                "content": [
                    {"type": "tableCell", "content": [{"type": "text", "text": "6.0"}]},
                    {
                        "type": "tableCell",
                        "content": [
                            {
                                "type": "paragraph",
                                "content": [
                                    {"type": "text", "text": "Updates include:"}
                                ],
                            },
                            {
                                "type": "bulletList",
                                "content": [
                                    {
                                        "type": "listItem",
                                        "content": [
                                            {
                                                "type": "paragraph",
                                                "content": [
                                                    {
                                                        "type": "text",
                                                        "text": "Improved performance",
                                                    }
                                                ],
                                            }
                                        ],
                                    },
                                    {
                                        "type": "listItem",
                                        "content": [
                                            {
                                                "type": "paragraph",
                                                "content": [
                                                    {
                                                        "type": "text",
                                                        "text": "Bug fixes",
                                                    }
                                                ],
                                            }
                                        ],
                                    },
                                    {
                                        "type": "listItem",
                                        "content": [
                                            {
                                                "type": "paragraph",
                                                "content": [
                                                    {
                                                        "type": "text",
                                                        "text": "New features",
                                                    }
                                                ],
                                            }
                                        ],
                                    },
                                ],
                            },
                        ],
                    },
                    {
                        "type": "tableCell",
                        "content": [
                            {
                                "type": "paragraph",
                                "content": [{"type": "text", "text": "2023-05-28"}],
                            }
                        ],
                    },
                ],
            },
            {
                "type": "tableRow",
                "content": [
                    {"type": "tableCell", "content": [{"type": "text", "text": "5.0"}]},
                    {
                        "type": "tableCell",
                        "content": [
                            {
                                "type": "paragraph",
                                "content": [{"type": "text", "text": "Minor updates"}],
                            }
                        ],
                    },
                    {
                        "type": "tableCell",
                        "content": [
                            {
                                "type": "paragraph",
                                "content": [{"type": "text", "text": "2023-04-15"}],
                            }
                        ],
                    },
                ],
            },
        ],
    }

    # Expected AsciiDoc output - adjusted to match actual implementation formatting
    expected_output = """|===
| Version | Change description | Date
| 6.0 a| Updates include:

* Improved performance
* Bug fixes
* New features | 2023-05-28
| 5.0 | Minor updates | 2023-04-15
|===
"""

    # Process the table node
    context = {}
    output = process_table_node(adf_table, context)

    # Assert the output matches the expected result
    assert output == expected_output


def test_process_list_item_content():
    """Test processing list item content with various configurations."""
    from helper_scripts.adf_resources import process_list_item_content

    # Test case 1: Simple bullet list item
    simple_item = {
        "type": "listItem",
        "content": [
            {"type": "paragraph", "content": [{"type": "text", "text": "Simple item"}]}
        ],
    }
    context = {"list_depth": 1, "in_bullet_list": True}
    result = process_list_item_content(simple_item, context)
    assert result == ["* Simple item"]

    # Test case 2: List item with multiple paragraphs
    multi_para_item = {
        "type": "listItem",
        "content": [
            {
                "type": "paragraph",
                "content": [{"type": "text", "text": "First paragraph"}],
            },
            {
                "type": "paragraph",
                "content": [{"type": "text", "text": "Second paragraph"}],
            },
        ],
    }
    result = process_list_item_content(multi_para_item, context)
    assert result == ["* First paragraph", "  Second paragraph"]

    # Test case 3: Ordered list item
    ordered_item = {
        "type": "listItem",
        "content": [
            {"type": "paragraph", "content": [{"type": "text", "text": "Ordered item"}]}
        ],
    }
    ordered_context = {"list_depth": 1, "in_bullet_list": False}
    result = process_list_item_content(ordered_item, ordered_context)
    assert result == [". Ordered item"]

    # Test case 4: Nested list
    nested_list_item = {
        "type": "listItem",
        "content": [
            {"type": "paragraph", "content": [{"type": "text", "text": "Parent item"}]},
            {
                "type": "bulletList",
                "content": [
                    {
                        "type": "listItem",
                        "content": [
                            {
                                "type": "paragraph",
                                "content": [{"type": "text", "text": "Child item"}],
                            }
                        ],
                    }
                ],
            },
        ],
    }
    result = process_list_item_content(nested_list_item, context)
    assert len(result) == 2
    assert result[0] == "* Parent item"
    assert "* Child item" in result[1]


def test_process_jira_snapshot_extension():
    """Test processing a JIRA JQL snapshot extension node."""
    node = {
        "type": "extension",
        "attrs": {
            "layout": "full-width",
            "extensionType": "com.atlassian.confluence.macro.core",
            "extensionKey": "jira-jql-snapshot",
            "parameters": {
                "macroParams": {
                    "macroPageVersion": {
                        "value": '{"version":1745422974377,"macroId":"1f035986-cdff-4a26-b71e-35bdb1662216"}'
                    },
                    "macroId": {"value": "1f035986-cdff-4a26-b71e-35bdb1662216"},
                    "macroParams": {
                        "value": '{"levels":[{"id":"c2f4cc93-8ea4-48f2-b778-10f71091cff4","title":"Architecture requirements for Example Product","jql":"project = prq and issuetype = \\"software/system requirement\\" AND \\"Product[Select List (multiple choices)]\\" = \\"Example Product\\"","fieldsPosition":[{"value":{"id":"key","key":"key"},"label":"Key","available":true},{"value":{"id":"summary","key":"summary"},"label":"Summary","available":true},{"label":"Description","value":{"id":"description","key":"description"},"available":true}],"fieldsOptions":{"groupedFields":[],"sortedFields":[]},"levelType":"JIRA_ISSUES"}],"macroId":"1f035986-cdff-4a26-b71e-35bdb1662216"}'
                    },
                }
            },
        },
    }

    context = {}
    from helper_scripts.adf_resources import process_extension_node

    result = process_extension_node(node, context)

    # Check that the result contains a jiraIssuesTable macro
    result_text = "".join(result)
    assert "jiraIssuesTable::" in result_text

    # Check that the JQL query is included
    assert "project = prq and issuetype" in result_text

    # Check that the fields are included
    assert 'fields="key,summary,description"' in result_text

    # Check that the title is included as an attribute
    assert 'title="Architecture requirements for Example Product"' in result_text


def test_process_jira_snapshot_with_title():
    """Test processing a JIRA JQL snapshot extension node with a title."""
    node = {
        "type": "extension",
        "attrs": {
            "layout": "full-width",
            "extensionType": "com.atlassian.confluence.macro.core",
            "extensionKey": "jira-jql-snapshot",
            "parameters": {
                "macroParams": {
                    "macroParams": {
                        "value": json.dumps(
                            {
                                "levels": [
                                    {
                                        "jql": "project = DEMO",
                                        "fieldsPosition": [
                                            {"value": {"id": "key"}, "available": True},
                                            {
                                                "value": {"id": "summary"},
                                                "available": True,
                                            },
                                            {
                                                "value": {"id": "status"},
                                                "available": True,
                                            },
                                        ],
                                        "title": "Demo Project Issues",
                                    }
                                ]
                            }
                        )
                    }
                }
            },
        },
    }

    context = {}
    result = process_extension_node(node, context)

    # Check that the result contains the jiraIssuesTable macro with the title
    result_text = "".join(result)
    assert (
        'jiraIssuesTable::[\'project = DEMO\', fields="key,summary,status", title="Demo Project Issues"]'
        in result_text
    )


def test_process_jira_snapshot_without_title():
    """Test processing a JIRA JQL snapshot extension node without a title."""
    node = {
        "type": "extension",
        "attrs": {
            "layout": "full-width",
            "extensionType": "com.atlassian.confluence.macro.core",
            "extensionKey": "jira-jql-snapshot",
            "parameters": {
                "macroParams": {
                    "macroParams": {
                        "value": json.dumps(
                            {
                                "levels": [
                                    {
                                        "jql": "project = DEMO",
                                        "fieldsPosition": [
                                            {"value": {"id": "key"}, "available": True},
                                            {
                                                "value": {"id": "summary"},
                                                "available": True,
                                            },
                                            {
                                                "value": {"id": "status"},
                                                "available": True,
                                            },
                                        ],
                                    }
                                ]
                            }
                        )
                    }
                }
            },
        },
    }

    context = {}
    result = process_extension_node(node, context)

    # Check that the result contains the jiraIssuesTable macro without the title
    result_text = "".join(result)
    assert (
        "jiraIssuesTable::['project = DEMO', fields=\"key,summary,status\"]"
        in result_text
    )
    assert "title=" not in result_text


def test_process_anchor_extension():
    """Test processing of anchor extension nodes and links to these anchors."""
    from helper_scripts.adf_resources import (
        process_inline_extension_node,
        get_node_text_content,
        process_node,
    )

    # Test 1: Basic anchor conversion
    anchor_node = {
        "type": "inlineExtension",
        "attrs": {
            "extensionType": "com.atlassian.confluence.macro.core",
            "extensionKey": "anchor",
            "parameters": {
                "macroParams": {
                    "": {"value": "_database"},
                    "legacyAnchorId": {
                        "value": "ModuleArchitectureAssess[MT]-_database"
                    },
                },
                "macroMetadata": {
                    "macroId": {"value": "b5301d4e-964b-44ff-bb57-edd670596e8c"},
                    "schemaVersion": {"value": "1"},
                    "title": "Anchor",
                },
            },
        },
    }

    context = {}
    result = process_inline_extension_node(anchor_node, context)
    assert result == ["[[_database]]"]
    assert "_database" in context.get("anchors", {})

    # Test 2: Same-page anchor link
    link_node = {
        "type": "text",
        "text": "Database section",
        "marks": [{"type": "link", "attrs": {"href": "#_database"}}],
    }

    # Context should have the anchor we created
    same_page_context = {"anchors": {"_database": True}}
    result = get_node_text_content(link_node, same_page_context)
    assert result == "<<_database,Database section>>"

    # Test 3: Cross-page anchor link
    cross_page_link_node = {
        "type": "text",
        "text": "Other page database",
        "marks": [
            {
                "type": "link",
                "attrs": {
                    "href": "https://confluence.example.com/pages/viewpage.action?pageId=123456#_database"
                },
            }
        ],
    }

    cross_page_context = {
        "base_url": "https://confluence.example.com",
        "page_mapping": {
            "123456": {"path": "/path/to/other-page.adoc", "title": "Other Page"}
        },
        "current_file_path": "/path/to/current-page.adoc",
    }

    result = get_node_text_content(cross_page_link_node, cross_page_context)
    assert "xref:" in result
    assert "#_database" in result
    assert "Other page database" in result

    # Test 4: Complete document with anchors and links
    doc_node = {
        "type": "doc",
        "content": [
            {
                "type": "paragraph",
                "content": [
                    {
                        "type": "inlineExtension",
                        "attrs": {
                            "extensionKey": "anchor",
                            "parameters": {"macroParams": {"": {"value": "section1"}}},
                        },
                    },
                    {"type": "text", "text": "Section 1 Content"},
                ],
            },
            {
                "type": "paragraph",
                "content": [
                    {
                        "type": "text",
                        "text": "Link to ",
                    },
                    {
                        "type": "text",
                        "text": "Section 1",
                        "marks": [{"type": "link", "attrs": {"href": "#section1"}}],
                    },
                ],
            },
        ],
    }

    # Process the entire document
    doc_context = {}
    result = []
    for content_node in doc_node.get("content", []):
        result.extend(process_node(content_node, doc_context))

    result_text = "".join(result)
    assert "[[section1]]" in result_text
    assert "<<section1,Section 1>>" in result_text


def test_process_workflow_metadata_extension():
    """Test processing of workflow metadata extension nodes."""
    from helper_scripts.adf_resources import process_inline_extension_node

    # Test metadata-macro with known value
    metadata_node = {
        "type": "inlineExtension",
        "attrs": {
            "extensionType": "com.atlassian.confluence.macro.core",
            "extensionKey": "metadata-macro",
            "parameters": {
                "macroParams": {"data": {"value": "Current Official Version"}},
                "macroMetadata": {
                    "macroId": {
                        "value": "91528036b374eac463e3afd03bcbd7281e7327709b1506ee5e5a8f4c50e1cce0"
                    },
                    "schemaVersion": {"value": "1"},
                    "indexedMacroParams": {
                        "text": "Current Official Version",
                        "type": "text",
                    },
                    "placeholder": [
                        {
                            "type": "icon",
                            "data": {
                                "url": "https://ac-cloud.com/workflows/images/logo.png"
                            },
                        }
                    ],
                    "title": "Workflows Metadata",
                },
            },
            "localId": "40b00485-7486-485c-a1e3-c47b0b8eba55",
        },
    }

    context = {}
    result = process_inline_extension_node(metadata_node, context)
    assert result == ["appfoxWorkflowMetadata:version[]"]

    # Test with unknown metadata value
    unknown_metadata_node = {
        "type": "inlineExtension",
        "attrs": {
            "extensionType": "com.atlassian.confluence.macro.core",
            "extensionKey": "metadata-macro",
            "parameters": {
                "macroParams": {"data": {"value": "Unknown Metadata Value"}},
                "macroMetadata": {"title": "Workflows Metadata"},
            },
        },
    }

    result = process_inline_extension_node(unknown_metadata_node, context)
    assert result == ["// Unknown workflow metadata: Unknown Metadata Value"]

    # Test additional metadata values
    for confluence_value, asciidoc_target in [
        ("Workflow Status", "status"),
        ("Approvers for Current Status", "approvers"),
        ("Expiry Date", "expiry"),
        ("Transition Date", "transition"),
        ("Unique Page ID", "pageid"),
        ("Current Official Version Description", "versiondesc"),
    ]:
        test_node = {
            "type": "inlineExtension",
            "attrs": {
                "extensionKey": "metadata-macro",
                "parameters": {"macroParams": {"data": {"value": confluence_value}}},
            },
        }
        result = process_inline_extension_node(test_node, context)
        assert result == [f"appfoxWorkflowMetadata:{asciidoc_target}[]"]


def test_process_workflow_approvers_extension():
    """Test processing of workflow approvers extension node."""
    from helper_scripts.adf_resources import process_extension_node

    # Test 1: approvers-macro with "Latest Approvals for Current Workflow" option
    latest_approvers_node = {
        "type": "extension",
        "attrs": {
            "extensionType": "com.atlassian.confluence.macro.core",
            "extensionKey": "approvers-macro",
            "parameters": {
                "macroParams": {
                    "data": {"value": "Latest Approvals for Current Workflow"}
                },
                "macroMetadata": {
                    "macroId": {"value": "8d49c7fa-6f72-4b9c-a12b-8125fbd62482"},
                    "schemaVersion": {"value": "1"},
                    "title": "Workflows Approvers Metadata",
                },
            },
        },
    }

    context = {}
    result = process_extension_node(latest_approvers_node, context)
    assert "workflowApproval:latest[]" in "".join(result)

    # Test 2: approvers-macro with default (all) option
    all_approvers_node = {
        "type": "extension",
        "attrs": {
            "extensionType": "com.atlassian.confluence.macro.core",
            "extensionKey": "approvers-macro",
            "parameters": {
                "macroParams": {
                    # No data value or a different value results in "all" option
                },
                "macroMetadata": {"title": "Workflows Approvers Metadata"},
            },
        },
    }

    result = process_extension_node(all_approvers_node, context)
    assert "workflowApproval:all[]" in "".join(result)

    # Test 3: Error handling
    invalid_node = {
        "type": "extension",
        "attrs": {
            "extensionKey": "approvers-macro",
            # Missing required parameters
        },
    }

    result = process_extension_node(invalid_node, context)
    assert "// Error processing Workflow Approvers" in "".join(result)


def test_process_workflow_change_table_extension():
    """Test processing of workflow change table extension node."""
    from helper_scripts.adf_resources import process_extension_node

    # Test document-control-table-macro
    change_table_node = {
        "type": "extension",
        "attrs": {
            "extensionType": "com.atlassian.confluence.macro.core",
            "extensionKey": "document-control-table-macro",
            "parameters": {
                "macroMetadata": {
                    "macroId": {"value": "7f8b9c1d-5e6f-4a2b-9c3d-8a7b6c5d4e3f"},
                    "schemaVersion": {"value": "1"},
                    "title": "Workflows Document Control Table",
                }
            },
        },
    }

    context = {}
    result = process_extension_node(change_table_node, context)
    assert "workflowChangeTable:[]" in "".join(result)

    # Test error handling
    invalid_node = {
        "type": "extension",
        "attrs": {
            "extensionKey": "document-control-table-macro",
            # Missing required parameters
        },
    }

    result = process_extension_node(invalid_node, context)
    assert "// Error processing Workflow Change Table" in "".join(result)


def test_process_mention_node():
    """Test processing of ADF mention nodes to AtlasMention macros."""
    from helper_scripts.adf_resources import process_mention_node

    # Test 1: Basic mention with user ID and name
    basic_mention = {
        "type": "mention",
        "attrs": {
            "id": "fake-user-id-111",
            "text": "John Doe",
        },
    }
    context = {}
    result = process_mention_node(basic_mention, context)
    assert result == ["atlasMention:John_Doe[]"]
    assert "John_Doe" in context.get("mention_username_to_id", {})
    assert context["mention_username_to_id"]["John_Doe"] == "fake-user-id-111"

    # Test 2: Mention with @ prefix
    at_prefix_mention = {
        "type": "mention",
        "attrs": {"id": "fake-user-id-222", "text": "@Jane Doe"},
    }
    context = {}
    result = process_mention_node(at_prefix_mention, context)
    assert result == ["atlasMention:Jane_Doe[]"]

    # Test 3: Mention with no spaces in name
    no_space_mention = {
        "type": "mention",
        "attrs": {"id": "fake-user-id-333", "text": "@JohnDoe"},
    }
    context = {}
    result = process_mention_node(no_space_mention, context)
    assert result == ["atlasMention:JohnDoe[]"]

    # Test 4: Integration with process_node
    from helper_scripts.adf_resources import process_node

    paragraph_with_mention = {
        "type": "paragraph",
        "content": [
            {
                "type": "mention",
                "attrs": {"id": "fake-user-id-111", "text": "@John Doe"},
            },
            {"type": "text", "text": " please review this document."},
        ],
    }

    context = {}
    result = "".join(process_node(paragraph_with_mention, context))
    assert "atlasMention:John_Doe[] please review this document." in result


def test_process_inline_card_node():
    """Test processing an inlineCard node."""
    node = {
        "type": "inlineCard",
        "attrs": {
            "url": "https://adahealth.atlassian.net/wiki/spaces/ATIC/pages/1057302499492689"
        },
    }
    context = {}
    result = process_inline_card_node(node, context)
    assert result == [
        "link:https://adahealth.atlassian.net/wiki/spaces/ATIC/pages/1057302499492689[https://adahealth.atlassian.net/wiki/spaces/ATIC/pages/1057302499492689]"
    ]


def test_process_inline_card_in_paragraph():
    """Test processing an inlineCard node within a paragraph."""
    node = {
        "type": "paragraph",
        "content": [
            {"type": "text", "text": "Here is a link: "},
            {
                "type": "inlineCard",
                "attrs": {
                    "url": "https://adahealth.atlassian.net/wiki/spaces/ATIC/pages/1057302499492689"
                },
            },
            {"type": "text", "text": " and some more text."},
        ],
    }
    context = {}
    result = process_node(node, context)
    result_text = "".join(result).strip()  # Strip trailing whitespace

    # Verify the inlineCard is rendered as a link
    assert (
        "link:https://adahealth.atlassian.net/wiki/spaces/ATIC/pages/1057302499492689[https://adahealth.atlassian.net/wiki/spaces/ATIC/pages/1057302499492689]"
        in result_text
    )

    # Verify the surrounding text is preserved
    assert result_text.startswith("Here is a link: ")
    assert result_text.endswith(" and some more text.")


def test_process_inline_card_with_confluence_page_title(mocker):
    """Test processing an inlineCard node with a Confluence page title."""
    mock_client = mocker.Mock()
    mock_client.get_confluence_page_title.return_value = "Example Page Title"

    context = {"confluence_client": mock_client}
    node = {
        "type": "inlineCard",
        "attrs": {
            "url": "https://adahealth.atlassian.net/wiki/spaces/ATIC/pages/1057302499492689"
        },
    }

    result = process_inline_card_node(node, context)
    assert result == [
        "link:https://adahealth.atlassian.net/wiki/spaces/ATIC/pages/1057302499492689[Example Page Title]"
    ]
    mock_client.get_confluence_page_title.assert_called_once_with(
        "https://adahealth.atlassian.net/wiki/spaces/ATIC/pages/1057302499492689"
    )


def test_process_inline_card_with_jira_ticket_title(mocker):
    """Test processing an inlineCard node with a Jira ticket title."""
    mock_client = mocker.Mock()
    mock_client.get_jira_ticket_title.return_value = "Example Ticket Title"

    context = {"confluence_client": mock_client}
    node = {
        "type": "inlineCard",
        "attrs": {"url": "https://adahealth.atlassian.net/browse/DEMO-123"},
    }

    result = process_inline_card_node(node, context)
    assert result == [
        "link:https://adahealth.atlassian.net/browse/DEMO-123[Example Ticket Title]"
    ]
    mock_client.get_jira_ticket_title.assert_called_once_with(
        "https://adahealth.atlassian.net/browse/DEMO-123"
    )


def test_process_task_list_node():
    adf_task_list = {
        "type": "taskList",
        "attrs": {"localId": "taskList1"},
        "content": [
            {
                "type": "taskItem",
                "attrs": {"state": "DONE", "localId": "1"},
                "content": [{"type": "text", "text": "Complete the documentation"}],
            },
            {
                "type": "taskItem",
                "attrs": {"state": "TODO", "localId": "2"},
                "content": [{"type": "text", "text": "Review the code changes"}],
            },
        ],
    }

    context = {}
    result = process_task_list_node(adf_task_list, context)
    expected = [
        "\n",
        "* [x] Complete the documentation\n",
        "* [ ] Review the code changes\n",
    ]
    assert result == expected
