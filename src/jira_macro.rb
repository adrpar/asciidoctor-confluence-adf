require 'asciidoctor'
require 'asciidoctor/extensions'

require_relative 'confluence_client'

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

# Atlassian Mention Inline Macro
class AtlasMentionInlineMacro < Asciidoctor::Extensions::InlineMacroProcessor
  use_dsl

  named :atlasMention
  name_positional_attributes 'text'

  def process parent, target, attrs
    name = target.tr('_', ' ')
    if parent.document.converter && parent.document.converter.backend == 'adf'
      confluence_base_url = ENV['CONFLUENCE_BASE_URL']
      api_token = ENV['CONFLUENCE_API_TOKEN']
      user_email = ENV['CONFLUENCE_USER_EMAIL']

      if confluence_base_url.nil? || api_token.nil? || user_email.nil?
        warn ">>> WARN: Missing Confluence API credentials for atlasMention macro."
        return { "type" => "text", "text" => "@#{name}" }
      end

      client = ConfluenceClient.new(
        base_url: confluence_base_url,
        api_token: api_token,
        user_email: user_email
      )
      user = client.find_user_by_fullname(name)

      if user
        {
          "type" => "mention",
          "attrs" => {
            "id" => user["id"],
            "text" => "@#{user["displayName"]}"
          }
        }.to_json
      else
        "@#{name}"
      end
    else
      "@#{name}"
    end
  end
end

Asciidoctor::Extensions.register do
  inline_macro JiraInlineMacro
  inline_macro AtlasMentionInlineMacro
end