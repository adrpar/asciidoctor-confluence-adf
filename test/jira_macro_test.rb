require 'minitest/autorun'
require 'asciidoctor'
require_relative '../src/jira_macro'

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
end