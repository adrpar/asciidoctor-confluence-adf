import pytest

from helper_scripts.adf_media import update_adf_media_ids


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
