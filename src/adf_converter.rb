require 'asciidoctor'
require 'json'
require 'securerandom'
require 'cgi'

class AdfConverter < Asciidoctor::Converter::Base
  register_for 'adf'

  DEFAULT_MARK_BACKGROUND_COLOR = '#FFFF00' # yellow

  ADMONITION_TYPE_MAPPING = {
    "note" => "info",
    "tip" => "info",
    "warning" => "warning",
    "important" => "error",
    "caution" => "error"
  }.freeze

  attr_accessor :node_list

  def initialize(backend, opts = {})
    super
    @node_list = []
    outfilesuffix '.adf'
  end

  def convert(node, transform = node.node_name, opts = nil)
    case transform
    when 'document' then convert_document(node)
    when 'paragraph' then convert_paragraph(node)
    when 'section' then convert_section(node)
    when 'ulist' then convert_ulist(node)
    when 'olist' then convert_olist(node)
    when 'table' then convert_table(node)
    when 'quote' then convert_quote(node)
    when 'image' then convert_image(node)
    when 'admonition' then convert_admonition(node)
    when 'preamble' then convert_preamble(node)
    when 'page_break' then convert_page_break(node)
    when 'inline_anchor' then convert_inline_anchor(node)
    when 'inline_quoted' then convert_inline_quoted(node)
    when 'inline_image' then convert_inline_image(node)
    when 'listing' then convert_listing(node)
    when 'embedded' then convert_embedded(node)
    else
      super
    end
  end

  def convert_document(node)
    a = node.content

    {
      "version" => 1,
      "type" => "doc",
      "content" => self.node_list.compact.empty? ? a : self.node_list.compact
    }.to_json
  end

  def convert_paragraph(node)
    self.node_list << create_paragraph_node(parse_or_escape(node.content))
  end

  def convert_section(node)
    anchor = if node.attr('id') then
      convert_anchor(node)
    end

    # Create the heading for the section
    self.node_list << {
      "type" => "heading",
      "attrs" => { "level" => node.level + 1 },
      "content" => [
        create_text_node(node.title),
        anchor
      ].compact
    }

    node.blocks.map { |block| convert(block) }
  end

  def convert_ulist(node)
    self.node_list << {
      "type" => "bulletList",
      "content" => node.items.map do |item|
        {
          "type" => "listItem",
          "content" => [
            create_paragraph_node(parse_or_escape(item.text))
          ]
        }
      end
    }
  end

  def convert_olist(node)
    self.node_list << {
      "type" => "orderedList",
      "content" => node.items.map do |item|
        {
          "type" => "listItem",
          "content" => [
            create_paragraph_node(parse_or_escape(item.text))
          ]
        }
      end
    }
  end

  def convert_table(node)
    self.node_list << {
      "type" => "table",
      "content" => node.rows[:body].map do |row|
        {
          "type" => "tableRow",
          "content" => row.map do |cell|
            cell_attrs = {}
            if cell.colspan
              cell_attrs["colspan"] = cell.colspan
            else
              cell_attrs["colspan"] = 1
            end
            if cell.rowspan
              cell_attrs["rowspan"] = cell.rowspan
            else
              cell_attrs["rowspan"] = 1
            end
            
            case cell.style
            when :asciidoc
              cell_content = cell.content
            when :literal
              cell_content = cell.text
            else
              cell_content = (cell_content = cell.content).empty? ? '' : cell_content.join("\n")
            end
            
            {
              "type" => "tableCell",
              "attrs" => cell_attrs.empty? ? nil : cell_attrs,
              "content" => [
                create_paragraph_node(parse_or_escape(cell_content))
              ]
            }.compact
          end
        }
      end
    }
  end

  def convert_quote(node)
    self.node_list << {
      "type" => "blockquote",
      "content" => [
        create_paragraph_node(parse_or_escape(node.content))
      ]
    }
  end

  def convert_image(node)
    self.node_list << {
      "type" => "mediaSingle",
      "attrs" => { "layout" => "center" },
      "content" => [
        {
          "type" => "media",
          "attrs" => {
            "type" => "file",
            "id" => node.attr('target'),
            "collection" => "attachments"
          }
        }
      ]
    }
  end

  def convert_inline_image(node)
    {
      "type" => "mediaInline",
      "attrs" => {
        "type" => "file",
        "id" => node.attr('target') || "unknown-id",
        "collection" => "attachments",
        "alt" => node.attr('alt') || "",
        "occurrenceKey" => node.attr('occurrenceKey') || SecureRandom.uuid,
        "width" => node.attr('width')&.to_i,
        "height" => node.attr('height')&.to_i,
        "data" => node.attr('data') || {}
      }.compact
    }.to_json
  end

  def convert_admonition(node)
    panel_type = ADMONITION_TYPE_MAPPING[node.attr('name')] || "info" # Default to "info" if type is unknown

    self.node_list << {
      "type" => "panel",
      "attrs" => { "panelType" => panel_type },
      "content" => [
        create_paragraph_node(parse_or_escape(node.content))
      ]
    }
  end

  def convert_preamble(node)
  end

  def convert_page_break(node)
    self.node_list << {
      "type" => "rule"
    }
  end

  def convert_embedded(node)
    ""
  end

  def convert_anchor(node)
    return unless node.id

    @anchors ||= {}
    @anchors[node.id] = node

    # Generate the Confluence inline extension macro for the anchor
    {
      "type" => "inlineExtension",
      "attrs" => {
        "extensionType" => "com.atlassian.confluence.macro.core",
        "extensionKey" => "anchor",
        "parameters" => {
          "macroParams" => {
            "" => { "value" => node.id },
            "legacyAnchorId" => { "value" => "LEGACY-#{node.id}" },
            "_parentId" => { "value" => SecureRandom.uuid }
          },
          "macroMetadata" => {
            "macroId" => { "value" => SecureRandom.uuid },
            "schemaVersion" => { "value" => "1" },
            "title" => "Anchor"
          }
        },
        "localId" => SecureRandom.uuid
      }
    }
  end

  def get_root_document node
    while (node = node.document).nested?
      node = node.parent_document
    end
    node
  end

  def root_document(node)
    while (node = node.document).nested?
      node = node.parent_document
    end
    node
  end

  def convert_inline_anchor(node)
    link_text = case node.type
    when :xref
      unless (text = node.text)
        if Asciidoctor::AbstractNode === (ref = (@refs ||= node.document.catalog[:refs])[refid = node.attributes['refid']] || (refid.nil_or_empty? ? (top = get_root_document node) : nil))
          text = top ? nil : %([#{refid}])
        else
          text = %([#{refid}])
        end
      end
      text
    else
      node.text || node.reftext || node.target
    end
    
    href = case node.type
    when :xref
      @anchors && @anchors[refid] ? "##{refid}" : "##{refid}"
    else
      node.target
    end

    marks = [
      {
        "type" => "link",
        "attrs" => { "href" => href }
      }
    ]

    create_text_node(link_text, marks).to_json
  end

  def convert_inline_quoted(node)
    mark_type = case node.type
                when :strong then "strong"
                when :emphasis then "em"
                when :monospaced then "code"
                when :superscript then "sup"
                when :subscript then "sub"
                when :underline then "underline"
                when :strikethrough then "strike"
                when :mark then "backgroundColor"
                else nil
                end

    mark_attrs = node.type == :mark ? { "color" => DEFAULT_MARK_BACKGROUND_COLOR } : nil
    marks = [{ "type" => mark_type, "attrs" => mark_attrs }.compact]

    create_text_node(node.text, marks).to_json
  end

  def convert_listing(node)
    self.node_list << {
      "type" => "codeBlock",
      "attrs" => { "language" => node.attr('language') || "plaintext" },
      "content" => [
        create_text_node(node.content) # Escape newlines and quotes
      ]
    }
  end

  def parse_or_escape(text)
    content_array = []
    buffer = ""
    json_buffer = ""
    inside_json = false
    json_depth = 0

    text = CGI.unescapeHTML(text)

    text.each_char do |char|
      if inside_json
        json_buffer << char
        if char == '{' || char == '['
          json_depth += 1
        elsif char == '}' || char == ']'
          json_depth -= 1
          if json_depth.zero?
            parse_json_buffer(json_buffer, buffer, content_array)
            json_buffer.clear
            inside_json = false
          end
        end
      else
        if char == '{' || char == '['
          inside_json = true
          json_depth += 1
          json_buffer << char
        else
          buffer << char
        end
      end
    end

    content_array << create_text_node(buffer) unless buffer.empty?
    content_array
  end

  private

  def parse_json_buffer(json_buffer, buffer, content_array)
    begin
      parsed_json = JSON.parse(json_buffer)
      content_array << create_text_node(buffer) unless buffer.empty?
      content_array << parsed_json unless parsed_json.empty?
      buffer.clear
    rescue JSON::ParserError
      buffer << json_buffer
    end
  end

  def create_text_node(text, marks = nil)
    raise ArgumentError, "Text cannot be nil or empty" if text.nil? || text.empty?
    raise ArgumentError, "Text must be a String" unless text.is_a?(String)

    node = { "text" => CGI.unescapeHTML(text), "type" => "text" }
    node["marks"] = marks if marks && !marks.empty?
    node.compact
  end

  def create_paragraph_node(content)
    { "type" => "paragraph", "content" => content }
  end
end