require 'minitest/autorun'
require 'asciidoctor'
require 'net/http'
require_relative '../src/jira_macro'
require_relative '../src/adf_converter'

class JiraMacroTest < Minitest::Test
  def asciidoc_with_macros
    <<~ADOC
      jira:ISSUE-123[]
      jira:ISSUE-456[Custom link text]
    ADOC
  end

  def test_jira_macro_with_base_url
    ENV['JIRA_BASE_URL'] = 'https://jira.example.com'
    doc = Asciidoctor.load(asciidoc_with_macros, safe: :safe, extensions: proc { inline_macro JiraInlineMacro })
    html = doc.convert

    assert_includes html, '<a href="https://jira.example.com/browse/ISSUE-123">ISSUE-123</a>'
    assert_includes html, '<a href="https://jira.example.com/browse/ISSUE-456">Custom link text</a>'
  ensure
    ENV.delete('JIRA_BASE_URL')
  end

  def test_jira_macro_without_base_url
    ENV.delete('JIRA_BASE_URL')
    doc = Asciidoctor.load(asciidoc_with_macros, safe: :safe, extensions: proc { inline_macro JiraInlineMacro })
    html = doc.convert

    assert_includes html, 'jira:ISSUE-123[]'
    assert_includes html, 'jira:ISSUE-456[Custom link text]'
  end

  def test_atlas_mention_macro_adf_backend
    adoc = 'atlasMention:Adrian_Partl[]'
    fake_user_id = '1234-5678'
    fake_user_name = 'Adrian Partl'

    # Stub Net::HTTP to avoid real HTTP requests
    Net::HTTP.stub :start, ->(*args) {
      response = Struct.new(:body, :code) do
        def is_a?(klass)
          klass == Net::HTTPSuccess
        end
      end
      response.new(
        {
          "results" => [
            {
              "user" => {
                "accountId" => fake_user_id,
                "displayName" => fake_user_name
              }
            }
          ]
        }.to_json,
        '200'
      )
    } do
      ENV['CONFLUENCE_BASE_URL'] = 'https://example.atlassian.net'
      ENV['CONFLUENCE_API_TOKEN'] = 'fake-token'
      ENV['CONFLUENCE_USER_EMAIL'] = 'fake@example.com'

      doc = Asciidoctor.load(
        adoc,
        backend: 'adf',
        safe: :safe,
        header_footer: false,
        extensions: proc { inline_macro AtlasMentionInlineMacro }
      )
      result = doc.converter.convert(doc, 'document')
      result_json = JSON.parse(result)

      mention = result_json["content"][0]["content"].find {|n| n["type"] == "mention"}
      refute_nil mention, "Mention node should be present"

      assert_equal fake_user_id, mention["attrs"]["id"]
      assert_equal "@#{fake_user_name}", mention["attrs"]["text"]
    end
  end

  def test_atlas_mention_macro_non_adf_backend
    adoc = 'atlasMention:Adrian_Partl[]'
    doc = Asciidoctor.load(
      adoc,
      backend: 'html5',
      safe: :safe,
      header_footer: false,
      extensions: proc { inline_macro AtlasMentionInlineMacro }
    )
    result = doc.convert
    assert_includes result, '@Adrian Partl'
  end
end