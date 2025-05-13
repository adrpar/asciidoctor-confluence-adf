import os
import tempfile
import pytest
from helper_scripts.asciidoc_resources import extract_images_and_includes


def write_file(path, content):
    with open(path, "w") as f:
        f.write(content)


def test_extract_images_and_includes_basic(tmp_path):
    # Setup test files
    img1 = tmp_path / "img1.png"
    img1.write_bytes(b"fakeimg")
    adoc = tmp_path / "doc.adoc"
    adoc.write_text(f"image::{img1.name}[]\n")

    images = []
    extract_images_and_includes(str(adoc), images)
    assert str(img1) in images


def test_extract_images_and_includes_with_imagesdir(tmp_path):
    images_dir = tmp_path / "images"
    images_dir.mkdir()
    img2 = images_dir / "img2.jpg"
    img2.write_bytes(b"fakeimg2")
    adoc = tmp_path / "doc2.adoc"
    adoc.write_text(f":imagesdir: images\nimage::img2.jpg[]\n")

    images = []
    extract_images_and_includes(str(adoc), images)
    assert str(img2) in images


def test_extract_images_and_includes_with_include(tmp_path):
    img3 = tmp_path / "img3.gif"
    img3.write_bytes(b"fakeimg3")
    included = tmp_path / "included.adoc"
    included.write_text(f"image::{img3.name}[]\n")
    adoc = tmp_path / "main.adoc"
    adoc.write_text(f"include::{included.name}[]\n")

    images = []
    extract_images_and_includes(str(adoc), images)
    assert str(img3) in images


def test_extract_images_and_includes_missing_image(tmp_path):
    adoc = tmp_path / "doc.adoc"
    adoc.write_text("image::notfound.png[]\n")
    images = []
    with pytest.raises(FileNotFoundError):
        extract_images_and_includes(str(adoc), images)
