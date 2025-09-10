require 'minitest/autorun'
require 'asciidoctor'
require 'json'
require_relative '../src/adf_converter'

# Integration-style tests that validate InlineAnchorHelper behavior
# by inspecting the final ADF JSON produced for whole documents.
class InlineAnchorHelperTest < Minitest::Test
  def setup
    @opts = { backend: 'adf', safe: :safe, header_footer: false }
  end

  def test_xref_with_custom_text
    adoc = <<~ADOC
      [[sec-id]]
      == Section Title

      See <<sec-id,Custom Text>> for details.
    ADOC
    result = convert_to_adf(adoc)
    para = find_first_paragraph(result)
    # Expect three text nodes: prefix, linked text, suffix
    linked = para['content'].find { |n| n['text'] == 'Custom Text' }
    refute_nil linked, 'Expected linked text node'
    mark = linked['marks'].find { |m| m['type'] == 'link' }
    assert_equal '#sec-id', mark.dig('attrs', 'href')
  end

  def test_xref_missing_anchor_fallback
    adoc = 'See <<no-such-anchor>>.'
    result = convert_to_adf(adoc)
    para = find_first_paragraph(result)
    linked = para['content'].find { |n| n['marks'] && n['marks'].any? { |m| m['type'] == 'link' } }
    refute_nil linked, 'Expected a link text node'
    assert_match(/\[no-such-anchor\]/, linked['text'])
    mark = linked['marks'].find { |m| m['type'] == 'link' }
    assert_equal '#no-such-anchor', mark.dig('attrs', 'href')
  end

  def test_external_link_inline_anchor
    adoc = 'Visit https://example.com[Example Site] now.'
    result = convert_to_adf(adoc)
    para = find_first_paragraph(result)
    linked = para['content'].find { |n| n['text'] == 'Example Site' }
    refute_nil linked, 'Expected external link text node'
    mark = linked['marks'].find { |m| m['type'] == 'link' }
    assert_equal 'https://example.com', mark.dig('attrs', 'href')
  end

  def test_nested_section_anchors_and_references
    adoc = <<~ADOC
      = Doc Title

      [[top-sec]]
      == Top Section

      [[sub-sec-a]]
      === Sub Section A

      Paragraph referencing <<top-sec>> and <<sub-sec-a>> inside nested context.

      [[sub-sub]]
      ==== Sub Sub

      Another paragraph referencing <<sub-sub>>.
    ADOC

    result = convert_to_adf(adoc)
    headings = result['content'].select { |n| n['type'] == 'heading' }

    # Collect anchor ids from inlineExtension anchor macros inside headings
    anchor_ids = headings.flat_map do |h|
      (h['content'] || []).select { |c| c['type'] == 'inlineExtension' && c.dig('attrs','extensionKey') == 'anchor' }
                           .map { |c| c.dig('attrs','parameters','macroParams','')['value'] }
    end.compact

    assert_includes anchor_ids, 'top-sec'
    assert_includes anchor_ids, 'sub-sec-a'
    assert_includes anchor_ids, 'sub-sub'

    # Find paragraphs and ensure links exist
    paragraphs = result['content'].select { |n| n['type'] == 'paragraph' }
    first_para = paragraphs.find { |p| p['content'].any? { |c| c['text']&.include?('Paragraph referencing') } } || flunk('First reference paragraph missing')
    second_para = paragraphs.find { |p| p['content'].any? { |c| c['text']&.include?('Another paragraph') } } || flunk('Second reference paragraph missing')

    top_link = first_para['content'].find { |n| n['marks']&.any? { |m| m['type'] == 'link' && m.dig('attrs','href') == '#top-sec' } }
    sub_link = first_para['content'].find { |n| n['marks']&.any? { |m| m['type'] == 'link' && m.dig('attrs','href') == '#sub-sec-a' } }
    sub_sub_link = second_para['content'].find { |n| n['marks']&.any? { |m| m['type'] == 'link' && m.dig('attrs','href') == '#sub-sub' } }

    refute_nil top_link, 'Expected link to #top-sec'
    refute_nil sub_link, 'Expected link to #sub-sec-a'
    refute_nil sub_sub_link, 'Expected link to #sub-sub'
  end

  def test_multiple_xrefs_in_single_paragraph
    adoc = <<~ADOC
      [[a-one]]
      == A One

      [[b-two]]
      == B Two

      See <<a-one>> then <<b-two>> and again <<a-one>> in one line.
    ADOC

    result = convert_to_adf(adoc)
    para = result['content'].find { |n| n['type'] == 'paragraph' && n['content'].any? { |c| c['text']&.include?('See ') } } || flunk('Reference paragraph not found')

    link_nodes = para['content'].select { |n| n['marks']&.any? { |m| m['type'] == 'link' } }
    # We expect three link nodes: A One, B Two, A One (again)
    assert_equal 3, link_nodes.size, 'Expected three link occurrences'

    hrefs = link_nodes.flat_map { |n| n['marks'].select { |m| m['type'] == 'link' }.map { |m| m.dig('attrs','href') } }
    assert_equal ['#a-one', '#b-two', '#a-one'], hrefs, 'Unexpected link href sequence'

    texts = link_nodes.map { |n| n['text'] }
    # Title capitalization should be preserved from headings
    assert_equal ['A One', 'B Two', 'A One'], texts
  end

  private

  def convert_to_adf(adoc)
    doc = Asciidoctor.load(adoc, **@opts)
    JSON.parse(doc.converter.convert(doc, 'document'))
  end

  def find_first_paragraph(result)
    result['content'].find { |n| n['type'] == 'paragraph' } || flunk('Paragraph node not found')
  end
end
