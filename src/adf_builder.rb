# Small helper module to build ADF node structures in a consistent way
# Keeps key insertion order stable (tests compare JSON in places)
module AdfBuilder
  module_function

  # Text node (order: text, type, marks)
  def text_node(text, marks = nil)
    raise ArgumentError, 'Text cannot be nil or empty' if text.nil? || text.empty?
    raise ArgumentError, 'Text must be a String' unless text.is_a?(String)
    node = { 'text' => text, 'type' => 'text' }
    node['marks'] = marks if marks && !marks.empty?
    node
  end

  # Paragraph node (order: type, content)
  def paragraph_node(content)
    { 'type' => 'paragraph', 'content' => content }
  end

  # Heading node with optional anchor extension already constructed
  def heading_node(level, inline_content)
    { 'type' => 'heading', 'attrs' => { 'level' => level }, 'content' => inline_content }
  end

  def link_mark(href)
    { 'type' => 'link', 'attrs' => { 'href' => href } }
  end

  def code_block_node(language, text)
    { 'type' => 'codeBlock', 'attrs' => { 'language' => language }, 'content' => [ text_node(text) ] }
  end

  def panel_node(panel_type, paragraph_content)
    { 'type' => 'panel', 'attrs' => { 'panelType' => panel_type }, 'content' => [ paragraph_node(paragraph_content) ] }
  end

  def bullet_list(items)
    { 'type' => 'bulletList', 'content' => items }
  end

  def ordered_list(items)
    { 'type' => 'orderedList', 'content' => items }
  end

  def list_item(paragraph_content)
    { 'type' => 'listItem', 'content' => [ paragraph_node(paragraph_content) ] }
  end

  def table_node(rows)
    { 'type' => 'table', 'content' => rows }
  end

  def table_row(cells)
    { 'type' => 'tableRow', 'content' => cells }
  end

  def table_cell(type_name, colspan, rowspan, content)
    { 'type' => type_name, 'attrs' => { 'colspan' => colspan, 'rowspan' => rowspan }, 'content' => content }
  end

  # Media / extensions -------------------------------------------------

  def media_single(layout:, width:, width_type: 'pixel', media_node:)
    {
      'type' => 'mediaSingle',
      'attrs' => { 'layout' => layout, 'width' => width, 'widthType' => width_type },
      'content' => [ media_node ]
    }
  end

  def media(attrs)
    { 'type' => 'media', 'attrs' => attrs }
  end

  def media_inline(attrs)
    { 'type' => 'mediaInline', 'attrs' => attrs }
  end

  def inline_extension(extension_type:, extension_key:, parameters:)
    {
      'type' => 'inlineExtension',
      'attrs' => {
        'extensionType' => extension_type,
        'extensionKey' => extension_key,
        'parameters' => parameters
      }
    }
  end

  def extension(extension_type:, extension_key:, attributes: {})
    {
      'type' => 'extension',
      'attrs' => attributes.merge('extensionType' => extension_type, 'extensionKey' => extension_key)
    }
  end

  def mention(id:, text:)
    { 'type' => 'mention', 'attrs' => { 'id' => id, 'text' => text } }
  end

  # Serializer ----------------------------------------------------------

  def serialize_document(content_nodes)
    {
      'version' => 1,
      'type' => 'doc',
      'content' => content_nodes.compact
    }
  end
end
