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

  def test_ordered_list
    adf = {
      'type' => 'doc',
      'content' => [
        {
          'type' => 'orderedList',
          'content' => [
            { 'type' => 'listItem', 'content' => [ { 'type' => 'paragraph', 'content' => [ { 'type' => 'text', 'text' => 'First' } ] } ] },
            { 'type' => 'listItem', 'content' => [ { 'type' => 'paragraph', 'content' => [ { 'type' => 'text', 'text' => 'Second' } ] } ] }
          ]
        }
      ]
    }
    expected = "\n. First\n. Second\n"
    assert_equal expected, @converter.convert(adf)
  end

  def test_nested_bullet_list
    adf = {
      'type' => 'doc',
      'content' => [
        {
          'type' => 'bulletList',
          'content' => [
            {
              'type' => 'listItem',
              'content' => [
                { 'type' => 'paragraph', 'content' => [ { 'type' => 'text', 'text' => 'Parent 1' } ] },
                {
                  'type' => 'bulletList',
                  'content' => [
                    { 'type' => 'listItem', 'content' => [ { 'type' => 'paragraph', 'content' => [ { 'type' => 'text', 'text' => 'Child 1' } ] } ] }
                  ]
                }
              ]
            },
            {
              'type' => 'listItem',
              'content' => [ { 'type' => 'paragraph', 'content' => [ { 'type' => 'text', 'text' => 'Parent 2' } ] } ]
            }
          ]
        }
      ]
    }
    expected = "\n* Parent 1\n** Child 1\n* Parent 2\n"
    assert_equal expected, @converter.convert(adf)
  end

  def test_code_block
    adf = {
      'type' => 'doc',
      'content' => [
        {
          'type' => 'codeBlock',
          'attrs' => { 'language' => 'ruby' },
          'content' => [ { 'type' => 'text', 'text' => "puts 'hi'" } ]
        }
      ]
    }
    expected = "\n[source,ruby]\n----\nputs 'hi'\n----\n"
    assert_equal expected, @converter.convert(adf)
  end

  def test_hard_break_in_paragraph
    adf = {
      'type' => 'doc',
      'content' => [
        {
          'type' => 'paragraph',
          'content' => [
            { 'type' => 'text', 'text' => 'Line1' },
            { 'type' => 'hardBreak' },
            { 'type' => 'text', 'text' => 'Line2' }
          ]
        }
      ]
    }
    expected = "\nLine1\nLine2\n"
    assert_equal expected, @converter.convert(adf)
  end

  def test_rule_between_paragraphs
    adf = {
      'type' => 'doc',
      'content' => [
        { 'type' => 'paragraph', 'content' => [ { 'type' => 'text', 'text' => 'Above' } ] },
        { 'type' => 'rule' },
        { 'type' => 'paragraph', 'content' => [ { 'type' => 'text', 'text' => 'Below' } ] }
      ]
    }
    expected = "\nAbove\n\n'''\n\nBelow\n"
    assert_equal expected, @converter.convert(adf)
  end

  def test_panel_mappings
    panel_types = %w[info success warning error custom]
    adf = {
      'type' => 'doc',
      'content' => panel_types.map do |p|
        {
          'type' => 'panel',
          'attrs' => { 'panelType' => p },
          'content' => [
            { 'type' => 'paragraph', 'content' => [ { 'type' => 'text', 'text' => "#{p} text" } ] }
          ]
        }
      end
    }
    out = @converter.convert(adf)
    assert_includes out, "[NOTE]\n====\ninfo text\n===="       # info -> NOTE
    assert_includes out, "[TIP]\n====\nsuccess text\n===="       # success -> TIP
    assert_includes out, "[WARNING]\n====\nwarning text\n===="   # warning -> WARNING
    assert_includes out, "[CAUTION]\n====\nerror text\n===="     # error -> CAUTION
    assert_includes out, "[NOTE]\n====\ncustom text\n===="       # fallback -> NOTE
  end

  def test_additional_heading_level
    adf = {
      'type' => 'doc',
      'content' => [
        { 'type' => 'heading', 'attrs' => { 'level' => 4 }, 'content' => [ { 'type' => 'text', 'text' => 'Deep Heading' } ] }
      ]
    }
    expected = "\n==== Deep Heading\n"
    assert_equal expected, @converter.convert(adf)
  end

  def test_text_strike_and_code_marks
    adf = {
      'type' => 'doc',
      'content' => [
        { 'type' => 'paragraph', 'content' => [
          { 'type' => 'text', 'text' => 'Struck', 'marks' => [ { 'type' => 'strike' } ] },
          { 'type' => 'text', 'text' => ' and ' },
          { 'type' => 'text', 'text' => 'code', 'marks' => [ { 'type' => 'code' } ] }
        ] }
      ]
    }
    expected = "\n[line-through]#_Struck_# and `code`\n"
    assert_equal expected, @converter.convert(adf)
  end
end
