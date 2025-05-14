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

    result_json = normalize_uuids(result)

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
                    "_parentId" => { "value" => "normalized-uuid" }
                  },
                  "macroMetadata" => {
                    "macroId" => { "value" => "normalized-uuid" },
                    "schemaVersion" => { "value" => "1" },
                    "title" => "Anchor"
                  }
                },
                "localId" => "normalized-uuid"
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

    assert_equal expected, result_json
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

  def test_convert_table
    adoc = <<~ADOC
      |===
      |Cell 1 |Cell 2
      |Cell 3 |Cell 4
      |===
    ADOC
    doc = Asciidoctor.load(adoc, backend: 'adf', safe: :safe, header_footer: false)

    assert_kind_of AdfConverter, doc.converter
    result = doc.converter.convert(doc, 'document')

    expected = {
      "version" => 1,
      "type" => "doc",
      "content" => [
        {
          "type" => "table",
          "content" => [
            {
              "type" => "tableRow",
              "content" => [
                {
                  "type" => "tableCell",
                  "attrs" =>
                  {
                    "colspan" => 1,
                    "rowspan" => 1
                  },
                  "content" => [
                    {
                      "type" => "paragraph",
                      "content" => [
                        {
                          "text" => "Cell 1",
                          "type" => "text"
                        }
                      ]
                    }
                  ]
                },
                {
                  "type" => "tableCell",
                  "attrs" =>
                  {
                    "colspan" => 1,
                    "rowspan" => 1
                  },
                  "content" => [
                    {
                      "type" => "paragraph",
                      "content" => [
                        {
                          "text" => "Cell 2",
                          "type" => "text"
                        }
                      ]
                    }
                  ]
                }
              ]
            },
            {
              "type" => "tableRow",
              "content" => [
                {
                  "type" => "tableCell",
                  "attrs" =>
                  {
                    "colspan" => 1,
                    "rowspan" => 1
                  },
                  "content" => [
                    {
                      "type" => "paragraph",
                      "content" => [
                        {
                          "text" => "Cell 3",
                          "type" => "text"
                        }
                      ]
                    }
                  ]
                },
                {
                  "type" => "tableCell",
                  "attrs" =>
                  {
                    "colspan" => 1,
                    "rowspan" => 1
                  },
                  "content" => [
                    {
                      "type" => "paragraph",
                      "content" => [
                        {
                          "text" => "Cell 4",
                          "type" => "text"
                        }
                      ]
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

    # Normalize UUIDs in the result
    result_json = normalize_uuids(result)

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
                    "_parentId" => { "value" => "normalized-uuid" }
                  },
                  "macroMetadata" => {
                    "macroId" => { "value" => "normalized-uuid" },
                    "schemaVersion" => { "value" => "1" },
                    "title" => "Anchor"
                  }
                },
                "localId" => "normalized-uuid"
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

    expected_json = normalize_uuids(expected)

    assert_equal expected_json, result_json
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