require 'asciidoctor'
require 'json'
require 'securerandom'
require 'cgi'
require_relative 'image_handler'
require_relative 'adf_builder'
require_relative 'inline_anchor_helper'
require_relative 'asciidoc_table_cell_parser'
require_relative 'text_or_json_parser'

class AdfConverter < Asciidoctor::Converter::Base
  include ImageHandler
  include InlineAnchorHelper
  register_for 'adf'

  DEFAULT_MARK_BACKGROUND_COLOR = '#FFFF00'

  MARK_TYPE_MAP = {
    strong: 'strong',
    emphasis: 'em',
    monospaced: 'code',
    superscript: 'sup',
    subscript: 'sub',
    underline: 'underline',
    strikethrough: 'strike',
    mark: 'backgroundColor'
  }.freeze

  ADMONITION_TYPE_MAPPING = {
    'note' => 'info',
    'tip' => 'info',
    'warning' => 'warning',
    'important' => 'error',
    'caution' => 'error'
  }.freeze

  attr_accessor :node_list

  def initialize(backend, opts = {})
    super
    @node_list = []
    @text_or_json_parser = TextOrJsonParser.new { |txt| create_text_node(txt) }
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
    when 'sidebar' then convert_sidebar(node)
    when 'floating_title' then convert_floating_title(node)
    when 'thematic_break' then convert_thematic_break(node)
    else
      super
    end
  end

  def convert_document(node)
    sectioned = node.sections
    if sectioned && (node.attr? 'toc') && (node.attr? 'toc-placement', 'auto')
      convert_toc(node)
    end
    node.blocks.each { |block| convert(block) }
    AdfBuilder.serialize_document(self.node_list.compact).to_json
  end

  def convert_paragraph(node)
    self.node_list << AdfBuilder.paragraph_node(parse_or_escape(node.content))
  end

  def convert_section(node)
    anchor = node.id ? convert_anchor(node) : nil
    self.node_list << AdfBuilder.heading_node(node.level + 1, [create_text_node(node.title), anchor].compact)
    node.blocks.each { |block| convert(block) }
  end

  def convert_ulist(node)
    self.node_list << AdfBuilder.bullet_list(
      node.items.map { |item| AdfBuilder.list_item(parse_or_escape(item.text)) }
    )
  end

  def convert_olist(node)
    self.node_list << AdfBuilder.ordered_list(
      node.items.map { |item| AdfBuilder.list_item(parse_or_escape(item.text)) }
    )
  end

  def convert_table(node)
    # Ensure downstream parsing (e.g., AsciiDoc cells) has access to the current document context
    previous_document = @current_document
    @current_document = node.document
    table_content = convert_table_rows(node.rows)
    self.node_list << { 'type' => 'table', 'content' => table_content }
  ensure
    # Restore previous document context
    @current_document = previous_document
  end

  def convert_table_rows(rows_hash)
    return [] unless rows_hash
    out = []
    parser = AsciidocTableCellParser.new(converter: self, current_document: @current_document)

    %i[head body].each do |section|
      rows = rows_hash[section]
      next unless rows && !rows.empty?
      rows.each do |row|
        force_header = (section == :head)
        out << AdfBuilder.table_row(row.map { |cell| build_table_cell(cell, parser, force_header: force_header) })
      end
    end
    out
  end

  def build_table_cell(cell, parser, force_header: false)
    type = force_header ? 'tableHeader' : cell_type(cell)
    colspan, rowspan = table_cell_spans(cell)
    content_nodes =
      if cell.style == :asciidoc
        parser.parse(cell)
      else
        [AdfBuilder.paragraph_node(parse_or_escape(cell.text))]
      end
    AdfBuilder.table_cell(type, colspan, rowspan, content_nodes)
  end

  def cell_type(cell)
    return 'tableHeader' if cell.style == :header
    cell.style == :asciidoc && cell.role == 'header' ? 'tableHeader' : 'tableCell'
  end

  def convert_quote(node)
    self.node_list << { "type" => "blockquote", "content" => [ AdfBuilder.paragraph_node(parse_or_escape(node.content)) ] }
  end

  # Image handling methods are now included from the ImageHandler module

  # Image conversion methods are now included from the ImageHandler module

  def convert_admonition(node)
    panel_type = ADMONITION_TYPE_MAPPING[node.attr('name')] || "info" # Default to "info" if type is unknown

    self.node_list << AdfBuilder.panel_node(panel_type, parse_or_escape(node.content))
  end

  def convert_preamble(node)
    node.blocks.each do |block|
      convert(block, block.context.to_s)
    end
  end

  def convert_page_break(node)
    self.node_list << { "type" => "rule" }
  end

  def convert_embedded(node)
    ""
  end

  # Sidebar blocks are currently ignored (no-op)
  def convert_sidebar(node)
    # intentionally left blank
    nil
  end

  # Floating titles are currently ignored (no-op)
  def convert_floating_title(node)
    # intentionally left blank
    nil
  end

  # Thematic breaks are currently ignored (no-op)
  def convert_thematic_break(node)
    # intentionally left blank
    nil
  end

  def convert_toc(node)
    self.node_list << AdfBuilder.inline_extension(
      extension_type: 'com.atlassian.confluence.macro.core',
      extension_key: 'toc',
      parameters: {
        'macroParams' => {},
        'macroMetadata' => {
          'schemaVersion' => { 'value' => '1' },
          'title' => 'Table of Contents'
        }
      }
    )
  end

  def convert_anchor(node)
    return unless node.id

    @anchors ||= {}
    @anchors[node.id] = node

    # Generate the Confluence inline extension macro for the anchor
    AdfBuilder.inline_extension(
      extension_type: 'com.atlassian.confluence.macro.core',
      extension_key: 'anchor',
      parameters: {
        'macroParams' => {
          '' => { 'value' => node.id },
          'legacyAnchorId' => { 'value' => "LEGACY-#{node.id}" }
        },
        'macroMetadata' => {
          'schemaVersion' => { 'value' => '1' },
          'title' => 'Anchor'
        }
      }
    )
  end

  def get_root_document node
    while (node = node.document).nested?
      node = node.parent_document
    end
    node
  end

  def convert_inline_anchor(node)
    build_link_from_inline_anchor(node)
  end

  def convert_inline_quoted(node)
    mark_type = MARK_TYPE_MAP[node.type]
    marks = []
    if mark_type
      mark_attrs = (mark_type == 'backgroundColor') ? { 'color' => DEFAULT_MARK_BACKGROUND_COLOR } : nil
      marks << { 'type' => mark_type, 'attrs' => mark_attrs }.compact
    end
    create_text_node(node.text, marks).to_json
  end

  def convert_listing(node)
    append_code_block(node)
  end

  def convert_literal(node)
    append_code_block(node)
  end

  def convert_pass(node)
    if node.content_model == :raw
      node.content
    else
      convert_content(node)
    end
  end

  def parse_or_escape(text)
    @text_or_json_parser.parse(text)
  end

  private


  def create_text_node(text, marks = nil)
    raise ArgumentError, "Text cannot be nil or empty" if text.nil? || text.empty?
    raise ArgumentError, "Text must be a String" unless text.is_a?(String)

    node = { "text" => CGI.unescapeHTML(text), "type" => "text" }
    node["marks"] = marks if marks && !marks.empty?
    node.compact
  end

  def create_paragraph_node(content)
    AdfBuilder.paragraph_node(content)
  end

  # Unified code/literal handling
  def append_code_block(node)
    self.node_list << AdfBuilder.code_block_node(resolve_code_language(node), node.content)
  end

  def resolve_code_language(node)
    lang = node.attr('language')
    lang = nil if lang.is_a?(String) && lang.strip.empty?
    lang || 'plaintext'
  end

  def table_cell_spans(cell)
    [cell.colspan || 1, cell.rowspan || 1]
  end
end
