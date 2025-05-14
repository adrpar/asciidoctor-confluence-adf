require 'asciidoctor'
require 'asciidoctor/extensions'

# Usage in AsciiDoc: jira:ISSUE-123[]
# Requires JIRA_BASE_URL to be set as an environment variable.

class JiraInlineMacro < Asciidoctor::Extensions::InlineMacroProcessor
  use_dsl

  named :jira
  name_positional_attributes 'text'

  def process parent, target, attrs
    base_url = ENV['JIRA_BASE_URL']
    if base_url.nil? || base_url.empty?
      warn ">>> WARN: No Jira base URL found, the Jira extension may not work as expected."
      # Reconstruct the original macro text, including custom text if present
      if attrs['text']
        return %(jira:#{target}[#{attrs['text']}])
      else
        return %(jira:#{target}[])
      end
    else
      url = "#{base_url}/browse/#{target}"
      text = attrs['text'] || target
      create_anchor parent, text, type: :link, target: url
    end
  end
end

Asciidoctor::Extensions.register do
  inline_macro JiraInlineMacro
end