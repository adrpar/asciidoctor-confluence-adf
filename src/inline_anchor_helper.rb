# Helper module extracting inline anchor/link resolution logic
# Keeps AdfConverter smaller and focused on dispatch.
require_relative 'adf_builder'

module InlineAnchorHelper
  # Resolve link text and href for an inline anchor / xref node.
  # Returns a JSON string representing the text node with link mark (to keep existing tests passing).
  def build_link_from_inline_anchor(node)
    if node.type == :xref
      refid = node.attributes['refid']
      refs = (@refs ||= node.document.catalog[:refs])
      ref = refs[refid] if refs && refid
      # Derive text (prefer explicit node text; else referenced title; else bracketed id)
      text = node.text
      unless text
        if Asciidoctor::AbstractNode === ref
          text = ref && ref.title ? ref.title : %([#{refid}])
        else
          text = %([#{refid}])
        end
      end
      href = "##{refid}"
      create_text_node(text, [AdfBuilder.link_mark(href)]).to_json
    else
      text = node.text || node.reftext || node.target
      href = node.target
      create_text_node(text, [AdfBuilder.link_mark(href)]).to_json
    end
  end
end
