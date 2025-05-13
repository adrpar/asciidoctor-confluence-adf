import os
import re


def extract_images_and_includes(
    asciidoc_file_path, images, base_dir=None, processed_files=None, imagesdir=None
):
    """Recursively extract image paths and resolve includes from an Asciidoctor source file."""
    if processed_files is None:
        processed_files = set()
    if base_dir is None:
        base_dir = os.path.dirname(asciidoc_file_path)
    if imagesdir is None:
        imagesdir = base_dir

    includes = []

    if asciidoc_file_path in processed_files:
        return images, imagesdir

    processed_files.add(asciidoc_file_path)

    imagesdir = extract_images_and_includes_from_file(
        asciidoc_file_path, base_dir, images, includes, imagesdir
    )

    for include in includes:
        imagesdir = extract_images_and_includes(
            include, images, base_dir, processed_files, imagesdir
        )

    return imagesdir


def extract_images_and_includes_from_file(
    asciidoc_file_path, base_dir, images, includes, imagesdir
):
    with open(asciidoc_file_path, "r") as file:
        for line in file:
            imagesdir = extract_image_and_include_paths_from_line(
                line, imagesdir, base_dir, asciidoc_file_path, images, includes
            )
    return imagesdir


def extract_image_and_include_paths_from_line(
    line, imagesdir, base_dir, asciidoc_file_path, images, includes
):
    """Extract image and include paths from a single Asciidoc line."""
    # Match :imagesdir: directive
    imagesdir_match = re.match(r":imagesdir:\s*(.+)", line)
    if imagesdir_match:
        imagesdir = os.path.normpath(
            os.path.join(base_dir, imagesdir_match.group(1).strip())
        )

    # Match (inline) image: or (block) image:: directives
    image_match = re.search(r"image:{1,2}([^\[]+)", line)
    if image_match:
        image_path = os.path.normpath(
            os.path.join(imagesdir, image_match.group(1).strip())
        )
        if not os.path.isfile(image_path):
            raise FileNotFoundError(f"Image not found: {image_path}")
        images.append(image_path)

    # Match include:: directives
    include_match = re.search(r"include::([^\[]+)", line)
    if include_match:
        include_path = os.path.normpath(
            os.path.join(
                os.path.dirname(asciidoc_file_path), include_match.group(1).strip()
            )
        )
        includes.append(include_path)

    return imagesdir
