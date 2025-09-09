require 'minitest/autorun'
require_relative '../src/adf_to_asciidoc'

class AdfToAsciidocConverterTest < Minitest::Test
  def setup
    @converter = AdfToAsciidocConverter.new
  end

  def test_convert_heading
    adf = {
      "type" => "doc",
      "content" => [
        {
          "type" => "heading",
          "attrs" => { "level" => 2 },
          "content" => [
            { "type" => "text", "text" => "My Heading" }
          ]
        }
      ]
    }
    expected_asciidoc = "\n== My Heading\n"
    assert_equal expected_asciidoc, @converter.convert(adf)
  end

  def test_convert_bullet_list
    adf = {
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
                    { "type" => "text", "text" => "Item 1" }
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
                    { "type" => "text", "text" => "Item 2" }
                  ]
                }
              ]
            }
          ]
        }
      ]
    }
    expected_asciidoc = "\n* Item 1\n* Item 2\n"
    assert_equal expected_asciidoc, @converter.convert(adf)
  end

  def test_text_formatting
    adf = {
      "type" => "doc",
      "content" => [
        {
          "type" => "paragraph",
          "content" => [
            { "type" => "text", "text" => "This is " },
            { "type" => "text", "text" => "bold", "marks" => [{ "type" => "strong" }] },
            { "type" => "text", "text" => ", " },
            { "type" => "text", "text" => "italic", "marks" => [{ "type" => "em" }] },
            { "type" => "text", "text" => ", and a " },
            { "type" => "text", "text" => "link", "marks" => [{ "type" => "link", "attrs" => { "href" => "http://example.com" } }] },
            { "type" => "text", "text" => "." }
          ]
        }
      ]
    }
    expected_asciidoc = "\nThis is *bold*, _italic_, and a link:http://example.com[link].\n"
    assert_equal expected_asciidoc, @converter.convert(adf)
  end

  def test_convert_simple_paragraph
    adf = {
      "version" => 1,

      "type" => "doc",
      "content" => [
        {
          "type" => "paragraph",
          "content" => [
            {
              "type" => "text",
              "text" => "Hello, world!"
            }
          ]
        }
      ]
    }
    expected_asciidoc = "\nHello, world!\n"
    assert_equal expected_asciidoc, @converter.convert(adf)
  end
end
