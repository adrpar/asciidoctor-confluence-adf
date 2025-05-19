require 'minitest/autorun'
require_relative '../src/adf_converter'
require 'asciidoctor'

class AdfConverterTableTest < Minitest::Test
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
                  "attrs" => { "colspan" => 1, "rowspan" => 1 },
                  "content" => [
                    {
                      "type" => "paragraph",
                      "content" => [
                        { "text" => "Cell 1", "type" => "text" }
                      ]
                    }
                  ]
                },
                {
                  "type" => "tableCell",
                  "attrs" => { "colspan" => 1, "rowspan" => 1 },
                  "content" => [
                    {
                      "type" => "paragraph",
                      "content" => [
                        { "text" => "Cell 2", "type" => "text" }
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
                  "attrs" => { "colspan" => 1, "rowspan" => 1 },
                  "content" => [
                    {
                      "type" => "paragraph",
                      "content" => [
                        { "text" => "Cell 3", "type" => "text" }
                      ]
                    }
                  ]
                },
                {
                  "type" => "tableCell",
                  "attrs" => { "colspan" => 1, "rowspan" => 1 },
                  "content" => [
                    {
                      "type" => "paragraph",
                      "content" => [
                        { "text" => "Cell 4", "type" => "text" }
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

  def test_convert_table_with_headers
    adoc = <<~ADOC
      [options="header",cols="1,1"]
      |===
      |Header 1 |Header 2
      |Cell 1   |Cell 2
      |Cell 3   |Cell 4
      |===
    ADOC

    doc = Asciidoctor.load(adoc, backend: 'adf', safe: :safe, header_footer: false)
    assert_kind_of AdfConverter, doc.converter
    result = JSON.parse(doc.converter.convert(doc, 'document'))

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
                  "type" => "tableHeader",
                  "attrs" => { "colspan" => 1, "rowspan" => 1 },
                  "content" => [
                    {
                      "type" => "paragraph",
                      "content" => [
                        { "type" => "text", "text" => "Header 1" }
                      ]
                    }
                  ]
                },
                {
                  "type" => "tableHeader",
                  "attrs" => { "colspan" => 1, "rowspan" => 1 },
                  "content" => [
                    {
                      "type" => "paragraph",
                      "content" => [
                        { "type" => "text", "text" => "Header 2" }
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
                  "attrs" => { "colspan" => 1, "rowspan" => 1 },
                  "content" => [
                    {
                      "type" => "paragraph",
                      "content" => [
                        { "type" => "text", "text" => "Cell 1" }
                      ]
                    }
                  ]
                },
                {
                  "type" => "tableCell",
                  "attrs" => { "colspan" => 1, "rowspan" => 1 },
                  "content" => [
                    {
                      "type" => "paragraph",
                      "content" => [
                        { "type" => "text", "text" => "Cell 2" }
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
                  "attrs" => { "colspan" => 1, "rowspan" => 1 },
                  "content" => [
                    {
                      "type" => "paragraph",
                      "content" => [
                        { "type" => "text", "text" => "Cell 3" }
                      ]
                    }
                  ]
                },
                {
                  "type" => "tableCell",
                  "attrs" => { "colspan" => 1, "rowspan" => 1 },
                  "content" => [
                    {
                      "type" => "paragraph",
                      "content" => [
                        { "type" => "text", "text" => "Cell 4" }
                      ]
                    }
                  ]
                }
              ]
            }
          ]
        }
      ]
    }

    assert_equal expected, result
  end

  def test_convert_table_with_header_and_left_header_column
    adoc = <<~ADOC
      [options="header", cols="1h,1,1"]
      |===
      |       |Header 1 |Header 2
      |Row 1  |Cell 1   |Cell 2
      |Row 2  |Cell 3   |Cell 4
      |===
    ADOC

    doc = Asciidoctor.load(adoc, backend: 'adf', safe: :safe, header_footer: false)
    assert_kind_of AdfConverter, doc.converter
    result = JSON.parse(doc.converter.convert(doc, 'document'))

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
                  "type" => "tableHeader",
                  "attrs" => { "colspan" => 1, "rowspan" => 1 },
                  "content" => [
                    { "type" => "paragraph", "content" => [ ] }
                  ]
                },
                {
                  "type" => "tableHeader",
                  "attrs" => { "colspan" => 1, "rowspan" => 1 },
                  "content" => [
                    { "type" => "paragraph", "content" => [ { "text" => "Header 1", "type" => "text" } ] }
                  ]
                },
                {
                  "type" => "tableHeader",
                  "attrs" => { "colspan" => 1, "rowspan" => 1 },
                  "content" => [
                    { "type" => "paragraph", "content" => [ { "text" => "Header 2", "type" => "text" } ] }
                  ]
                }
              ]
            },
            {
              "type" => "tableRow",
              "content" => [
                {
                  "type" => "tableHeader",
                  "attrs" => { "colspan" => 1, "rowspan" => 1 },
                  "content" => [
                    { "type" => "paragraph", "content" => [ { "text" => "Row 1", "type" => "text" } ] }
                  ]
                },
                {
                  "type" => "tableCell",
                  "attrs" => { "colspan" => 1, "rowspan" => 1 },
                  "content" => [
                    { "type" => "paragraph", "content" => [ { "text" => "Cell 1", "type" => "text" } ] }
                  ]
                },
                {
                  "type" => "tableCell",
                  "attrs" => { "colspan" => 1, "rowspan" => 1 },
                  "content" => [
                    { "type" => "paragraph", "content" => [ { "text" => "Cell 2", "type" => "text" } ] }
                  ]
                }
              ]
            },
            {
              "type" => "tableRow",
              "content" => [
                {
                  "type" => "tableHeader",
                  "attrs" => { "colspan" => 1, "rowspan" => 1 },
                  "content" => [
                    { "type" => "paragraph", "content" => [ { "text" => "Row 2", "type" => "text" } ] }
                  ]
                },
                {
                  "type" => "tableCell",
                  "attrs" => { "colspan" => 1, "rowspan" => 1 },
                  "content" => [
                    { "type" => "paragraph", "content" => [ { "text" => "Cell 3", "type" => "text" } ] }
                  ]
                },
                {
                  "type" => "tableCell",
                  "attrs" => { "colspan" => 1, "rowspan" => 1 },
                  "content" => [
                    { "type" => "paragraph", "content" => [ { "text" => "Cell 4", "type" => "text" } ] }
                  ]
                }
              ]
            }
          ]
        }
      ]
    }

    assert_equal expected, result
  end

  def test_convert_table_with_links
    adoc = <<~ADOC
      |===
      |Cell 1 |http://example.com[Cell 2]
      |Cell 3 |Cell 4
      |===
    ADOC
    doc = Asciidoctor.load(adoc, backend: 'adf', safe: :safe, header_footer: false)

    assert_kind_of AdfConverter, doc.converter
    result = JSON.parse(doc.converter.convert(doc, 'document'))

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
                  "attrs" => { "colspan" => 1, "rowspan" => 1 },
                  "content" => [
                    {
                      "type" => "paragraph",
                      "content" => [
                        { "text" => "Cell 1", "type" => "text" }
                      ]
                    }
                  ]
                },
                {
                  "type" => "tableCell",
                  "attrs" => { "colspan" => 1, "rowspan" => 1 },
                  "content" => [
                    {
                      "type" => "paragraph",
                      "content" => [
                        {
                          "text" => "Cell 2",
                          "type" => "text",
                          "marks" => [
                            { "type" => "link", "attrs" => { "href" => "http://example.com" } }
                          ]
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
                  "attrs" => { "colspan" => 1, "rowspan" => 1 },
                  "content" => [
                    {
                      "type" => "paragraph",
                      "content" => [
                        { "text" => "Cell 3", "type" => "text" }
                      ]
                    }
                  ]
                },
                {
                  "type" => "tableCell",
                  "attrs" => { "colspan" => 1, "rowspan" => 1 },
                  "content" => [
                    {
                      "type" => "paragraph",
                      "content" => [
                        { "text" => "Cell 4", "type" => "text" }
                      ]
                    }
                  ]
                }
              ]
            }
          ]
        }
      ]
    }
    assert_equal expected, result
  end

  def test_convert_table_in_root_section
    adoc = <<~ADOC
      = Title

      |===
      |Cell 1 |Cell 2
      |Cell 3 |Cell 4
      |===

      == Another Section Title
    ADOC
    doc = Asciidoctor.load(adoc, backend: 'adf', safe: :safe, header_footer: false)

    assert_kind_of AdfConverter, doc.converter
    result = JSON.parse(doc.converter.convert(doc, 'document'))

    result_json = result
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
                  "attrs" => { "colspan" => 1, "rowspan" => 1 },
                  "content" => [
                    {
                      "type" => "paragraph",
                      "content" => [
                        { "text" => "Cell 1", "type" => "text" }
                      ]
                    }
                  ]
                },
                {
                  "type" => "tableCell",
                  "attrs" => { "colspan" => 1, "rowspan" => 1 },
                  "content" => [
                    {
                      "type" => "paragraph",
                      "content" => [
                        { "text" => "Cell 2", "type" => "text" }
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
                  "attrs" => { "colspan" => 1, "rowspan" => 1 },
                  "content" => [
                    {
                      "type" => "paragraph",
                      "content" => [
                        { "text" => "Cell 3", "type" => "text" }
                      ]
                    }
                  ]
                },
                {
                  "type" => "tableCell",
                  "attrs" => { "colspan" => 1, "rowspan" => 1 },
                  "content" => [
                    {
                      "type" => "paragraph",
                      "content" => [
                        { "text" => "Cell 4", "type" => "text" }
                      ]
                    }
                  ]
                }
              ]
            }
          ]
        },
        {
          "type" => "heading",
          "attrs" => { "level" => 2 },
          "content" => [
            { "text" => "Another Section Title", "type" => "text" },
            {
              "type" => "inlineExtension",
              "attrs" => {
                "extensionType" => "com.atlassian.confluence.macro.core",
                "extensionKey" => "anchor",
                "parameters" => {
                  "macroParams" => {
                    "" => { "value" => "_another_section_title" },
                    "legacyAnchorId" => { "value" => "LEGACY-_another_section_title" },
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
end