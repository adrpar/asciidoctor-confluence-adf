require 'json'
require 'cgi'

# Parses mixed plain text containing embedded JSON array/object fragments.
# Returns an array of ADF inline nodes: existing parsed JSON nodes are inserted
# verbatim, while plain text is wrapped in a provided text node factory.
class TextOrJsonParser
  def initialize(&text_node_factory)
    @text_node_factory = text_node_factory || proc { |txt| { 'type' => 'text', 'text' => txt } }
  end

  # Public API: parse a string and return array of nodes.
  def parse(text)
    return [] if text.nil? || text.empty?
    @content_array = []
    @buffer = ''
    @json_buffer = ''
    inside_json = false
    json_depth = 0
    text = CGI.unescapeHTML(text)
    text.each_char do |char|
      if inside_json
        @json_buffer << char
        if char == '{' || char == '['
          json_depth += 1
        elsif char == '}' || char == ']'
          json_depth -= 1
          if json_depth.zero?
            flush_json_buffer
            inside_json = false
          end
        end
      else
        if char == '{' || char == '['
          inside_json = true
          json_depth += 1
          @json_buffer << char
        else
          @buffer << char
        end
      end
    end
    # If we ended while still inside_json we treat the accumulated json_buffer as text
    if inside_json && !@json_buffer.empty?
      @buffer << @json_buffer
      @json_buffer.clear
    end
    @content_array << build_text_node(@buffer) unless @buffer.empty?
    @content_array
  end

  private

  def flush_json_buffer
    begin
      parsed_json = JSON.parse(@json_buffer)
      if parsed_json.empty?
        # treat as plain text if empty structure
        @buffer << @json_buffer
      else
        unless @buffer.empty?
          @content_array << build_text_node(@buffer)
          @buffer = ''
        end
        @content_array << parsed_json
      end
    rescue JSON::ParserError
      @buffer << @json_buffer
    ensure
      @json_buffer.clear
    end
  end

  def build_text_node(text)
    @text_node_factory.call(text)
  end
end
