require 'asciidoctor'
require 'json'
require 'securerandom'
require 'cgi'
require_relative 'image_handler'

class AdfConverter < Asciidoctor::Converter::Base
  include ImageHandler
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
    when 'toc' then convert_toc(node)
    when 'literal' then convert_literal(node)
    when 'pass' then convert_pass(node)
    else
      super
    end
  end

  def convert_document(node)
    # Process sections if present
    sectioned = node.sections
    if sectioned && (node.attr? 'toc') && (node.attr? 'toc-placement', 'auto')
      convert_toc(node)
    end
    
    # Process all blocks in the document
    node.blocks.each do |block|
      convert(block)
    end

    # Return the document with the collected nodes
    {
      "version" => 1,
      "type" => "doc",
      "content" => self.node_list.compact.empty? ? [] : self.node_list.compact
    }.to_json
  end

  def convert_paragraph(node)
    self.node_list << create_paragraph_node(parse_or_escape(node.content))
  end

  def convert_section(node)
    anchor = node.id ? convert_anchor(node) : nil

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
    table_content = [
      *convert_table_head_rows(node.rows[:head]),
      *convert_table_body_rows(node.rows[:body])
    ]
    
    table_node = {
      "type" => "table",
      "content" => table_content
    }
    
    self.node_list << table_node
  end

  def convert_table_head_rows(head_rows)
    return [] unless head_rows && !head_rows.empty?
    head_rows.map do |row|
      {
        "type" => "tableRow",
        "content" => row.map { |cell| convert_table_header_cell(cell) }
      }
    end
  end

  def convert_table_body_rows(body_rows)
    return [] unless body_rows && !body_rows.empty?
    body_rows.map do |row|
      {
        "type" => "tableRow",
        "content" => row.map { |cell| convert_table_body_cell(cell) }
      }
    end
  end

  def convert_table_header_cell(cell)
    cell_attrs = {
      "colspan" => cell.colspan || 1,
      "rowspan" => cell.rowspan || 1
    }
    {
      "type" => "tableHeader",
      "attrs" => cell_attrs,
      "content" => [
        create_paragraph_node(parse_or_escape(cell.text))
      ]
    }
  end

  def convert_table_body_cell(cell)
    cell_type = (cell.style == :header) ? "tableHeader" : "tableCell"
    
    if cell.style == :asciidoc
      original_node_list = self.node_list.dup
      self.node_list = []
      
      # Check if blocks are empty but text is present - common case with a| cells
      if (cell.blocks.empty? || cell.blocks.nil?) && !cell.text.empty?
        # Parse the text content into blocks
        # We'll use a temporary document to parse the AsciiDoc content
        cell_doc = Asciidoctor.load(cell.text, safe: :safe, backend: 'adf')
        
        cell_doc.blocks.each do |block|
          convert(block)
        end
      else
        cell.blocks.each do |block|
          convert(block)
        end
      end
      
      cell_content_nodes = self.node_list
      
      self.node_list = original_node_list
      
      if cell_content_nodes.empty? && !cell.text.empty?
        cell_content_nodes = [create_paragraph_node(parse_or_escape(cell.text))]
      end
      
      return {
        "type" => cell_type,
        "attrs" => {
          "colspan" => cell.colspan || 1,
          "rowspan" => cell.rowspan || 1
        },
        "content" => cell_content_nodes
      }
    end
    
    {
      "type" => cell_type,
      "attrs" => {
        "colspan" => cell.colspan || 1,
        "rowspan" => cell.rowspan || 1
      },
      "content" => [
        create_paragraph_node(parse_or_escape(cell.text))
      ]
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

  # Image handling methods are now included from the ImageHandler module

  # Image conversion methods are now included from the ImageHandler module

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
    node.blocks.each do |block|
      convert(block, block.context.to_s)
    end
  end

  def convert_page_break(node)
    self.node_list << {
      "type" => "rule"
    }
  end

  def convert_embedded(node)
    ""
  end

  def convert_toc(node)
    # Add a Confluence TOC macro as an inlineExtension node
    self.node_list << {
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
    }
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
            "legacyAnchorId" => { "value" => "LEGACY-#{node.id}" }
          },
          "macroMetadata" => {
            "schemaVersion" => { "value" => "1" },
            "title" => "Anchor"
          }
        }
      }
    }
  end

  def get_root_document node
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
          text = top ? nil : (ref && ref.title ? ref.title : %([#{refid}]))
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

  def convert_literal(node)
    self.node_list << {
      "type" => "codeBlock",
      "attrs" => { "language" => node.attr('language') || "plaintext" },
      "content" => [
        create_text_node(node.content)
      ]
    }
  end

  def convert_pass(node)
    if node.content_model == :raw
      node.content
    else
      convert_content(node)
    end
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
      if parsed_json.empty?
        buffer << json_buffer
      else
        content_array << create_text_node(buffer) unless buffer.empty?
        content_array << parsed_json unless parsed_json.empty?
        buffer.clear
      end
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
