require 'minitest/autorun'
require_relative '../src/text_or_json_parser'

class TextOrJsonParserTest < Minitest::Test
  def parser
    TextOrJsonParser.new { |txt| { 'type' => 'text', 'text' => txt } }
  end

  def test_empty_input_returns_empty_array
    assert_equal [], parser.parse('')
    assert_equal [], parser.parse(nil)
  end

  def test_plain_text_returns_single_text_node
    result = parser.parse('Hello World')
    assert_equal 1, result.size
    assert_equal({'type' => 'text', 'text' => 'Hello World'}, result.first)
  end

  def test_embedded_simple_json_object
    result = parser.parse('Prefix {"type":"emoji"} Suffix')
    # Expected: text node for 'Prefix ', parsed JSON hash, text node for ' Suffix'
    assert_equal 3, result.size
    assert_equal 'Prefix ', result[0]['text']
    assert_equal 'emoji', result[1]['type']
    assert_equal ' Suffix', result[2]['text']
  end

  def test_embedded_json_array
    result = parser.parse('Start [{"type":"text","text":"Inner"}] End')
    assert_equal 3, result.size
    assert_equal 'Start ', result[0]['text']
    assert_kind_of Array, result[1]
    assert_equal 'text', result[1][0]['type']
    assert_equal 'Inner', result[1][0]['text']
    assert_equal ' End', result[2]['text']
  end

  def test_multiple_json_segments
    str = 'X {"type":"emoji","name":"smile"} Y [{"type":"text","text":"Z"}]'
    result = parser.parse(str)
  # Parser collapses trailing nothing into absence of final empty text node => 4 nodes
  assert_equal 4, result.size
  assert_equal 'X ', result[0]['text']
  assert_equal 'emoji', result[1]['type']
  assert_equal ' Y ', result[2]['text']
  assert_equal 'text', result[3][0]['type']
  assert_equal 'Z', result[3][0]['text']
  end

  def test_unbalanced_braces_treated_as_text
    str = 'Hello {"type":"text"' # missing closing brace
    result = parser.parse(str)
    assert_equal 1, result.size
    assert_equal str, result[0]['text']
  end

  def test_empty_json_object_treated_as_literal
    str = 'Hi {} there'
    result = parser.parse(str)
    # Empty object should be left inside surrounding text (no JSON node)
    assert_equal 1, result.size
    assert_equal 'Hi {} there', result[0]['text']
  end

  def test_empty_json_array_treated_as_literal
    str = 'Hi [] there'
    result = parser.parse(str)
    assert_equal 1, result.size
    assert_equal 'Hi [] there', result[0]['text']
  end
end
