#!/usr/bin/env python3
"""
Test suite for the image dimension handling functionality in adf_resources.py
"""

import os
import sys
import pytest
from unittest.mock import patch, Mock, MagicMock

# Add the parent directory to sys.path so we can import modules directly
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from adf_resources import update_adf_image_dimensions


class TestImageDimensions:
    """Test the image dimension handling functionality."""

    def test_update_adf_image_dimensions_no_change_needed(self):
        """Test that images smaller than max width are not changed."""
        # Create a test ADF document with media nodes that have width < max_width
        adf = {
            "version": 1,
            "type": "doc",
            "content": [
                {
                    "type": "mediaSingle",
                    "content": [
                        {
                            "type": "media",
                            "attrs": {
                                "width": 400,
                                "height": 300,
                                "id": "test1.png",
                                "type": "file",
                                "collection": "attachments",
                            },
                        }
                    ],
                }
            ],
        }
        
        # Set max_width to 800 (larger than image width)
        max_width = 800
        
        # Process the ADF
        updated_adf = update_adf_image_dimensions(adf, max_width)
        
        # Verify the width remains unchanged
        assert updated_adf["content"][0]["content"][0]["attrs"]["width"] == 400
        assert updated_adf["content"][0]["content"][0]["attrs"]["height"] == 300

    def test_update_adf_image_dimensions_width_reduced(self):
        """Test that images larger than max width are resized with aspect ratio preserved."""
        # Create a test ADF document with media nodes that have width > max_width
        adf = {
            "version": 1,
            "type": "doc",
            "content": [
                {
                    "type": "mediaSingle",
                    "content": [
                        {
                            "type": "media",
                            "attrs": {
                                "width": 1200,
                                "height": 600,
                                "id": "test1.png",
                                "type": "file",
                                "collection": "attachments",
                            },
                        }
                    ],
                }
            ],
        }
        
        # Set max_width to 800 (smaller than image width)
        max_width = 800
        
        # Process the ADF
        updated_adf = update_adf_image_dimensions(adf, max_width)
        
        # Verify the width is reduced to max_width
        assert updated_adf["content"][0]["content"][0]["attrs"]["width"] == 800
        # Verify the height is scaled proportionally (1200:600 = 800:400)
        assert updated_adf["content"][0]["content"][0]["attrs"]["height"] == 400

    def test_update_adf_image_dimensions_multiple_images(self):
        """Test that multiple images in a document are properly processed."""
        # Create a test ADF document with multiple media nodes
        adf = {
            "version": 1,
            "type": "doc",
            "content": [
                {
                    "type": "mediaSingle",
                    "content": [
                        {
                            "type": "media",
                            "attrs": {
                                "width": 1200,
                                "height": 600,
                                "id": "large.png",
                                "type": "file",
                                "collection": "attachments",
                            },
                        }
                    ],
                },
                {
                    "type": "mediaSingle",
                    "content": [
                        {
                            "type": "media",
                            "attrs": {
                                "width": 400,
                                "height": 300,
                                "id": "small.png",
                                "type": "file",
                                "collection": "attachments",
                            },
                        }
                    ],
                }
            ],
        }
        
        # Set max_width to 800
        max_width = 800
        
        # Process the ADF
        updated_adf = update_adf_image_dimensions(adf, max_width)
        
        # Verify the large image is resized
        assert updated_adf["content"][0]["content"][0]["attrs"]["width"] == 800
        assert updated_adf["content"][0]["content"][0]["attrs"]["height"] == 400
        
        # Verify the small image remains unchanged
        assert updated_adf["content"][1]["content"][0]["attrs"]["width"] == 400
        assert updated_adf["content"][1]["content"][0]["attrs"]["height"] == 300

    def test_update_adf_image_dimensions_nested_nodes(self):
        """Test that images in deeply nested nodes are properly processed."""
        # Create a test ADF document with nested media nodes
        adf = {
            "version": 1,
            "type": "doc",
            "content": [
                {
                    "type": "paragraph",
                    "content": [
                        {
                            "type": "mediaInline",
                            "attrs": {
                                "width": 1200,
                                "height": 600,
                                "id": "inline.png",
                                "type": "file",
                                "collection": "attachments",
                            },
                        }
                    ],
                },
                {
                    "type": "table",
                    "content": [
                        {
                            "type": "tableRow",
                            "content": [
                                {
                                    "type": "tableCell",
                                    "content": [
                                        {
                                            "type": "mediaSingle",
                                            "content": [
                                                {
                                                    "type": "media",
                                                    "attrs": {
                                                        "width": 900,
                                                        "height": 450,
                                                        "id": "table-cell.png",
                                                        "type": "file",
                                                        "collection": "attachments",
                                                    },
                                                }
                                            ],
                                        }
                                    ],
                                }
                            ],
                        }
                    ],
                }
            ],
        }
        
        # Set max_width to 600
        max_width = 600
        
        # Process the ADF
        updated_adf = update_adf_image_dimensions(adf, max_width)
        
        # Verify the inline image is resized
        assert updated_adf["content"][0]["content"][0]["attrs"]["width"] == 600
        assert updated_adf["content"][0]["content"][0]["attrs"]["height"] == 300
        
        # Verify the nested table cell image is resized
        nested_media = updated_adf["content"][1]["content"][0]["content"][0]["content"][0]["content"][0]
        assert nested_media["attrs"]["width"] == 600
        assert nested_media["attrs"]["height"] == 300

    def test_update_adf_image_dimensions_mediasingle_attrs(self):
        """Test that the mediaSingle node attrs are also updated if they have width/height."""
        adf = {
            "version": 1,
            "type": "doc",
            "content": [
                {
                    "type": "mediaSingle",
                    "attrs": {
                        "width": 1200,
                        "layout": "center",
                    },
                    "content": [
                        {
                            "type": "media",
                            "attrs": {
                                "width": 1200,
                                "height": 600,
                                "id": "test1.png",
                                "type": "file",
                                "collection": "attachments",
                            },
                        }
                    ],
                }
            ],
        }
        
        # Set max_width to 800
        max_width = 800
        
        # Process the ADF
        updated_adf = update_adf_image_dimensions(adf, max_width)
        
        # Verify both the mediaSingle node and media node widths are updated
        assert updated_adf["content"][0]["attrs"]["width"] == 800
        assert updated_adf["content"][0]["content"][0]["attrs"]["width"] == 800
        assert updated_adf["content"][0]["content"][0]["attrs"]["height"] == 400

    def test_update_adf_image_dimensions_no_height(self):
        """Test handling of images with width but no height."""
        adf = {
            "version": 1,
            "type": "doc",
            "content": [
                {
                    "type": "mediaSingle",
                    "content": [
                        {
                            "type": "media",
                            "attrs": {
                                "width": 1200,
                                "id": "test1.png",
                                "type": "file",
                                "collection": "attachments",
                            },
                        }
                    ],
                }
            ],
        }
        
        # Set max_width to 800
        max_width = 800
        
        # Process the ADF
        updated_adf = update_adf_image_dimensions(adf, max_width)
        
        # Verify the width is updated but no height is added
        assert updated_adf["content"][0]["content"][0]["attrs"]["width"] == 800
        assert "height" not in updated_adf["content"][0]["content"][0]["attrs"]

    def test_update_adf_image_dimensions_edge_cases(self):
        """Test edge cases like empty inputs and non-image nodes."""
        # Test with empty ADF
        assert update_adf_image_dimensions({}, 800) == {}
        
        # Test with None ADF
        assert update_adf_image_dimensions(None, 800) is None
        
        # Test with zero max_width
        adf = {
            "version": 1,
            "type": "doc",
            "content": [
                {
                    "type": "mediaSingle",
                    "content": [
                        {
                            "type": "media",
                            "attrs": {
                                "width": 1200,
                                "height": 600,
                                "id": "test1.png",
                            },
                        }
                    ],
                }
            ],
        }
        
        # Should not modify the ADF if max_width is 0
        assert update_adf_image_dimensions(adf, 0) == adf
        
        # Test with None max_width
        assert update_adf_image_dimensions(adf, None) == adf

    def test_update_adf_image_dimensions_non_number_values(self):
        """Test handling of non-numeric width/height values."""
        adf = {
            "version": 1,
            "type": "doc",
            "content": [
                {
                    "type": "mediaSingle",
                    "content": [
                        {
                            "type": "media",
                            "attrs": {
                                "width": "auto",  # Non-numeric width
                                "height": 600,
                                "id": "test1.png",
                            },
                        }
                    ],
                }
            ],
        }
        
        # Process the ADF - should handle non-numeric width gracefully
        updated_adf = update_adf_image_dimensions(adf, 800)
        
        # Verify no changes were made to non-numeric values
        assert updated_adf["content"][0]["content"][0]["attrs"]["width"] == "auto"
