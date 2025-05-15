import copy

from typing import Any, Dict


def update_adf_media_ids(adf_json: Any, filename_to_fileid: Dict[str, str]) -> Any:
    """Recursively update all media nodes in the ADF JSON with the attachment fileIds."""

    def recurse_update(node: Any) -> Any:
        if isinstance(node, dict):
            if node.get("type") in ["media", "mediaInline"] and "attrs" in node:
                attrs = node["attrs"]
                file_name = attrs.get("id")
                if file_name and file_name in filename_to_fileid:
                    attrs["id"] = filename_to_fileid[file_name]
            for key, value in node.items():
                node[key] = recurse_update(value)
        elif isinstance(node, list):
            node = [recurse_update(item) for item in node]
        return node

    return recurse_update(copy.deepcopy(adf_json))
