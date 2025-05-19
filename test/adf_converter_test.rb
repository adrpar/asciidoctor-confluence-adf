require 'minitest/autorun'
require_relative '../src/adf_converter'
require 'asciidoctor'

class AdfConverterTest < Minitest::Test
  def test_convert_document
    adoc = "= Title\n\nThis is a paragraph."
    doc = Asciidoctor.load(adoc, backend: 'adf', safe: :safe, header_footer: false)
    assert_kind_of AdfConverter, doc.converter
    result = doc.converter.convert(doc, 'document')

    expected = {
      "version" => 1,
      "type" => "doc",
      "content" => [
        {
          "type" => "paragraph",
          "content" => [
            {
              "text" => "This is a paragraph.",
              "type" => "text"
            }
          ]
        }
      ]
    }.to_json
    assert_equal expected, result
  end

  def test_convert_paragraph
    adoc = "This is a paragraph."
    doc = Asciidoctor.load(adoc, backend: 'adf', safe: :safe, header_footer: false)

    assert_kind_of AdfConverter, doc.converter
    result = doc.converter.convert(doc, 'document')

    expected = {
      "version" => 1,
      "type" => "doc",
      "content" => [
        {
          "type" => "paragraph",
          "content" => [
            {
              "text" => "This is a paragraph.",
              "type" => "text"
            }
          ]
        }
      ]
    }.to_json
    assert_equal expected, result
  end

  def test_convert_section
    adoc = "= Title\n\n== Section Title\n\nThis is a section."
    doc = Asciidoctor.load(adoc, backend: 'adf', safe: :safe, header_footer: false)

    assert_kind_of AdfConverter, doc.converter
    result = JSON.parse(doc.converter.convert(doc, 'document'))

    expected = {
      "version" => 1,
      "type" => "doc",
      "content" => [
        {
          "type" => "heading",
          "attrs" => { "level" => 2 },
          "content" => [
            {
              "text" => "Section Title",
              "type" => "text"
            },
            {
              "type" => "inlineExtension",
              "attrs" => {
                "extensionType" => "com.atlassian.confluence.macro.core",
                "extensionKey" => "anchor",
                "parameters" => {
                  "macroParams" => {
                    "" => { "value" => "_section_title" },
                    "legacyAnchorId" => { "value" => "LEGACY-_section_title" },
                  },
                  "macroMetadata" => {
                    "schemaVersion" => { "value" => "1" },
                    "title" => "Anchor"
                  }
                }
              }
            }
          ]
        },
        {
          "type" => "paragraph",
          "content" => [
            {
              "text" => "This is a section.",
              "type" => "text"
            }
          ]
        }
      ]
    }

    assert_equal expected, result
  end

  def test_convert_ulist
    adoc = <<~ADOC
      * Item 1
      * Item 2
    ADOC
    doc = Asciidoctor.load(adoc, backend: 'adf', safe: :safe, header_footer: false)

    assert_kind_of AdfConverter, doc.converter
    result = doc.converter.convert(doc, 'document')

    expected = {
      "version" => 1,
      "type" => "doc",
      "content" => [
        {
          "type" => "bulletList",
          "content" => [
            {
              "type" => "listItem",
              "content" => [
                {
                  "type" => "paragraph",
                  "content" => [
                    {
                      "text" => "Item 1",
                      "type" => "text"
                    }
                  ]
                }
              ]
            },
            {
              "type" => "listItem",
              "content" => [
                {
                  "type" => "paragraph",
                  "content" => [
                    {
                      "text" => "Item 2",
                      "type" => "text"
                    }
                  ]
                }
              ]
            }
          ]
        }
      ]
    }.to_json
    assert_equal expected, result
  end

  def test_convert_olist
    adoc = <<~ADOC
      . Step 1
      . Step 2
    ADOC
    doc = Asciidoctor.load(adoc, backend: 'adf', safe: :safe, header_footer: false)

    assert_kind_of AdfConverter, doc.converter
    result = doc.converter.convert(doc, 'document')

    expected = {
      "version" => 1,
      "type" => "doc",
      "content" => [
        {
          "type" => "orderedList",
          "content" => [
            {
              "type" => "listItem",
              "content" => [
                {
                  "type" => "paragraph",
                  "content" => [
                    {
                      "text" => "Step 1",
                      "type" => "text"
                    }
                  ]
                }
              ]
            },
            {
              "type" => "listItem",
              "content" => [
                {
                  "type" => "paragraph",
                  "content" => [
                    {
                      "text" => "Step 2",
                      "type" => "text"
                    }
                  ]
                }
              ]
            }
          ]
        }
      ]
    }.to_json
    assert_equal expected, result
  end

  def test_convert_inline_anchor
    adoc = "See <<TEST-123>> for details."
    doc = Asciidoctor.load(adoc, backend: 'adf', safe: :safe, header_footer: false)

    assert_kind_of AdfConverter, doc.converter
    result = doc.converter.convert(doc, 'document')

    expected = {
      "version" => 1,
      "type" => "doc",
      "content" => [
        {
          "type" => "paragraph",
          "content" => [
            {
              "text" => "See ",
              "type" => "text"
            },
            {
              "text" => "[TEST-123]",
              "type" => "text",
              "marks" => [
                {
                  "type" => "link",
                  "attrs" => { "href" => "#TEST-123" }
                }
              ]
            },
            {
              "text" => " for details.",
              "type" => "text"
            }
          ]
        }
      ]
    }.to_json
    assert_equal expected, result
  end

  def test_section_anchor_and_reference
    adoc = <<~ADOC
      [[section-anchor]]
      == Section with Anchor

      See <<section-anchor>> for more details.
    ADOC

    doc = Asciidoctor.load(adoc, backend: 'adf', safe: :safe, header_footer: false)

    assert_kind_of AdfConverter, doc.converter
    result = JSON.parse(doc.converter.convert(doc, 'document'))

    expected = {
      "version" => 1,
      "type" => "doc",
      "content" => [
        {
          "type" => "heading",
          "attrs" => { "level" => 2 },
          "content" => [
            {
              "text" => "Section with Anchor",
              "type" => "text"
            },
            {
              "type" => "inlineExtension",
              "attrs" => {
                "extensionType" => "com.atlassian.confluence.macro.core",
                "extensionKey" => "anchor",
                "parameters" => {
                  "macroParams" => {
                    "" => { "value" => "section-anchor" },
                    "legacyAnchorId" => { "value" => "LEGACY-section-anchor" },
                  },
                  "macroMetadata" => {
                    "schemaVersion" => { "value" => "1" },
                    "title" => "Anchor"
                  }
                }
              }
            }
          ]
        },
        {
          "type" => "paragraph",
          "content" => [
            {
              "text" => "See ",
              "type" => "text"
            },
            {
              "text" => "Section with Anchor",
              "type" => "text",
              "marks" => [
                {
                  "type" => "link",
                  "attrs" => { "href" => "#section-anchor" }
                }
              ]
            },
            {
              "text" => " for more details.",
              "type" => "text"
            }
          ]
        }
      ]
    }

    assert_equal expected, result
  end

  def test_convert_toc_macro
    adoc = <<~ADOC
     = Title
     :toc: 

     == Section 1
     == Section 2
     ADOC

    doc = Asciidoctor.load(adoc, backend: 'adf', safe: :safe, header_footer: false)
    assert_kind_of AdfConverter, doc.converter
    result = JSON.parse(doc.converter.convert(doc, 'document'))

    expected = {
      "version" => 1,
      "type" => "doc",
      "content" => [
        {
          "type" => "inlineExtension",
          "attrs" => {
            "extensionType" => "com.atlassian.confluence.macro.core",
            "extensionKey" => "toc",
            "parameters" => {
              "macroParams" => {},
              "macroMetadata" => {
                "schemaVersion" => { "value" => "1" },
                "title" => "Table of Contents"
              }
            }
          }
        },
        {
          "type" => "heading",
          "attrs" => { "level" => 2 },
          "content" => [
            { "text" => "Section 1", "type" => "text" },
            {
              "type" => "inlineExtension",
              "attrs" => {
                "extensionType" => "com.atlassian.confluence.macro.core",
                "extensionKey" => "anchor",
                "parameters" => {
                  "macroParams" => {
                    "" => { "value" => "_section_1" },
                    "legacyAnchorId" => { "value" => "LEGACY-_section_1" },
                  },
                  "macroMetadata" => {
                    "schemaVersion" => { "value" => "1" },
                    "title" => "Anchor"
                  }
                }
              }
            }
          ]
        },
        {
          "type" => "heading",
          "attrs" => { "level" => 2 },
          "content" => [
            { "text" => "Section 2", "type" => "text" },
            {
              "type" => "inlineExtension",
              "attrs" => {
                "extensionType" => "com.atlassian.confluence.macro.core",
                "extensionKey" => "anchor",
                "parameters" => {
                  "macroParams" => {
                    "" => { "value" => "_section_2" },
                    "legacyAnchorId" => { "value" => "LEGACY-_section_2" },
                  },
                  "macroMetadata" => {
                    "schemaVersion" => { "value" => "1" },
                    "title" => "Anchor"
                  }
                }
              }
            }
          ]
        }
      ]
    }

    assert_equal expected, result
  end

  def test_convert_literal_blocks_with_languages
    adoc = <<~ADOC
      [source,ruby]
      ----
      puts 'Hello, world!'
      ----

      [source,python]
      ----
      print("Hello, world!")
      ----

      ----
      Plain text code block
      ----
    ADOC

    doc = Asciidoctor.load(adoc, backend: 'adf', safe: :safe, header_footer: false)
    assert_kind_of AdfConverter, doc.converter
    result = JSON.parse(doc.converter.convert(doc, 'document'))

    expected = {
      "version" => 1,
      "type" => "doc",
      "content" => [
        {
          "type" => "codeBlock",
          "attrs" => { "language" => "ruby" },
          "content" => [
            { "type" => "text", "text" => "puts 'Hello, world!'" }
          ]
        },
        {
          "type" => "codeBlock",
          "attrs" => { "language" => "python" },
          "content" => [
            { "type" => "text", "text" => 'print("Hello, world!")' }
          ]
        },
        {
          "type" => "codeBlock",
          "attrs" => { "language" => "plaintext" },
          "content" => [
            { "type" => "text", "text" => "Plain text code block" }
          ]
        }
      ]
    }

    assert_equal expected, result
  end

  def test_convert_image_block
    adoc = <<~ADOC
      image::example.png[Alt text, width=300, height=200]
    ADOC

    doc = Asciidoctor.load(adoc, backend: 'adf', safe: :safe, header_footer: false)
    assert_kind_of AdfConverter, doc.converter
    result = JSON.parse(doc.converter.convert(doc, 'document'))

    expected = {
      "version" => 1,
      "type" => "doc",
      "content" => [
        {
          "type" => "mediaSingle",
          "attrs" => {"layout" => "center"},
          "content" => [
            {
              "type" => "media",
              "attrs" => {
                "type" => "file",
                "id" => "example.png",
                "collection" => "attachments",
                "alt" => "Alt text",
                "occurrenceKey" => "normalized-uuid",
                "width" => 300,
                "height" => 200
              }
            }
          ]
        }
      ]
    }

    # Normalize UUIDs in the result
    result_json = normalize_uuids(result)
    expected_json = normalize_uuids(expected)
    assert_equal expected_json, result_json
  end

  def test_convert_inline_image
    adoc = <<~ADOC
      This is an inline image image:example.png[Alt text, width=100, height=50] in a sentence.
    ADOC

    doc = Asciidoctor.load(adoc, backend: 'adf', safe: :safe, header_footer: false)
    assert_kind_of AdfConverter, doc.converter
    result = JSON.parse(doc.converter.convert(doc, 'document'))

    # Find the paragraph node
    para = result["content"].find { |n| n["type"] == "paragraph" }
    assert para, "Paragraph node should exist"

    # Find the inline image node
    inline_image = para["content"].find { |n| n["type"] == "mediaInline" }
    assert inline_image, "Inline image node should exist"

    # Check attributes
    attrs = inline_image["attrs"]
    assert_equal "file", attrs["type"]
    assert_equal "example.png", attrs["id"]
    assert_equal "attachments", attrs["collection"]
    assert_equal "Alt text", attrs["alt"]
    assert_equal 100, attrs["width"]
    assert_equal 50, attrs["height"]
  end

  private

  def normalize_uuids(json)
    case json
    when Hash
      json.each do |key, value|
        json[key] = normalize_uuids(value)
      end
    when Array
      json.map! { |item| normalize_uuids(item) }
    when String
      json.match?(/\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/) ? 'normalized-uuid' : json
    else
      json
    end
  end
end