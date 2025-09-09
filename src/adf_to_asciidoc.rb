require 'json'

class AdfToAsciidocConverter
  def convert(adf)
    # ADF can be a string or a hash
    adf = JSON.parse(adf) if adf.is_a?(String)
    process_node(adf)
  end

  private

  def process_node(node, context = { list_depth: 0 })
    return '' unless node.is_a?(Hash)

    node_type = node['type']
    content = node['content']

    case node_type
    when 'doc'
      process_content_list(content, context).join
    when 'paragraph'
      process_paragraph(node, context)
    when 'text'
      process_text(node)
    when 'hardBreak'
      "\n"
    when 'heading'
      process_heading(node, context)
    when 'bulletList', 'orderedList'
      process_list(node, context)
    when 'listItem'
      process_list_item(node, context)
    when 'codeBlock'
      process_code_block(node)
    when 'rule'
      "\n'''\n"
    when 'panel'
      process_panel(node, context)
    else
      # For unknown nodes, process their content if they have any
      if content.is_a?(Array)
        process_content_list(content, context).join
      else
        ''
      end
    end
  end

  def process_content_list(content, context)
    return [] unless content.is_a?(Array)
    content.map { |child_node| process_node(child_node, context) }
  end

  def get_text_from_content(content, context)
    process_content_list(content, context).join
  end

  def process_paragraph(node, context)
    text = get_text_from_content(node['content'], context)
    return '' if text.empty?

    # If inside a list, don't add extra newlines around paragraphs
    if context[:list_depth] > 0
      text
    else
      "\n#{text}\n"
    end
  end

  def process_text(node)
    text = node['text']
    (node['marks'] || []).each do |mark|
      case mark['type']
      when 'strong'
        text = "*#{text}*"
      when 'em'
        text = "_#{text}_"
      when 'strike'
        text = "[line-through]#_#{text}_#"
      when 'code'
        text = "`#{text}`"
      when 'link'
        href = mark.dig('attrs', 'href')
        text = "link:#{href}[#{text}]"
      end
    end
    text
  end

  def process_heading(node, context)
    level = node.dig('attrs', 'level') || 1
    text = get_text_from_content(node['content'], context)
    "\n#{'=' * level} #{text}\n"
  end

  def process_list(node, context)
    marker = node['type'] == 'bulletList' ? '*' : '.'
    context[:list_depth] += 1
    
    items = (node['content'] || []).map do |item|
      context_for_item = context.merge(list_marker: marker)
      process_node(item, context_for_item)
    end.join

    context[:list_depth] -= 1
    
    if context[:list_depth] == 0
      "\n#{items.strip}\n"
    else
      items
    end
  end

  def process_list_item(node, context)
    marker = context[:list_marker] || '*'
    indent = marker * context[:list_depth]
    
    parts = []
    (node['content'] || []).each_with_index do |content_node, idx|
      rendered = process_node(content_node, context)
      # If this content node is a nested list and previous part doesn't end with a newline, insert one
      if idx > 0 && content_node.is_a?(Hash) && content_node['type']&.end_with?('List') && !(parts.last&.end_with?("\n"))
        parts << "\n" + rendered
      else
        parts << rendered
      end
    end
    content_text = parts.join.strip

    "#{indent} #{content_text}\n"
  end

  def process_code_block(node)
    language = node.dig('attrs', 'language') || ''
    code = (node['content'] || []).map { |text_node| text_node['text'] }.join("\n")
    "\n[source,#{language}]\n----\n#{code}\n----\n"
  end

  def process_panel(node, context)
    panel_type = node.dig('attrs', 'panelType')
    title = panel_type.capitalize
    
    # Mapping panel types to admonition types
    admonition_map = {
      'info' => 'NOTE',
      'note' => 'NOTE',
      'success' => 'TIP',
      'warning' => 'WARNING',
      'error' => 'CAUTION'
    }
    admonition_type = admonition_map[panel_type] || 'NOTE'
    
    content = process_content_list(node['content'], context).join.strip
    
    "\n[#{admonition_type}]\n====\n#{content}\n====\n"
  end
end
