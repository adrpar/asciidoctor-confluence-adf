require 'minitest/autorun'
require 'asciidoctor'
require 'json'
require_relative '../src/jira_macro'
require_relative '../src/adf_converter'

class AtlasMentionTableTest < Minitest::Test
  def setup
    # Ensure required env for client construction (values won't be used due to stub)
    ENV['CONFLUENCE_BASE_URL'] = 'https://example.atlassian.net'
    ENV['CONFLUENCE_API_TOKEN'] = 'token'
    ENV['CONFLUENCE_USER_EMAIL'] = 'user@example.com'
  end

  def test_atlas_mention_in_table_cell_renders_mention_node
    # Stub the ConfluenceJiraClient to return a user for atlasMention macro
    fake_client = Object.new
    def fake_client.find_user_by_fullname(name)
      { 'id' => 'user-123', 'displayName' => 'Alex Example' }
    end

    ConfluenceJiraClient.stub :new, fake_client do
      adoc_content = <<~ADOC
        |===
        | Label | Value
        
        | *Author* | atlasMention:Alex_Example[]
        |===
      ADOC

      # Convert with ADF backend and atlasMention macro registered
      doc = Asciidoctor.load(
        adoc_content,
        safe: :safe,
        backend: 'adf',
        extensions: proc { inline_macro AtlasMentionInlineMacro }
      )
      adf_json = doc.converter.convert(doc, 'document')
      adf_data = JSON.parse(adf_json)

      # Locate the table and the Author row's value cell
      table = adf_data['content'].find { |n| n['type'] == 'table' }
      refute_nil table, 'ADF should contain a table node'
      rows = table['content']
      # Expect header row + author row at least
      assert rows.size >= 2, 'Table should have at least 2 rows'
      author_row = rows[1]
      assert_equal 'tableRow', author_row['type']
      cells = author_row['content']
      assert_equal 2, cells.size

      # The value cell should contain a paragraph with a mention node, not a text node with JSON
      value_cell = cells[1]
      paras = value_cell['content']
      refute_nil paras
      para = paras.find { |c| c['type'] == 'paragraph' }
      refute_nil para, 'Value cell should contain a paragraph'
      inline = para['content']
      refute_nil inline

      # Assert we have a mention node
      assert inline.any? { |n| n['type'] == 'mention' }, 'Inline content should contain a mention node'
      refute inline.any? { |n| n['type'] == 'text' && n['text'].include?('"type":"mention"') }, 'Should not contain escaped mention JSON text'
      mention = inline.find { |n| n['type'] == 'mention' }
      assert_equal 'user-123', mention['attrs']['id']
      assert_equal '@Alex Example', mention['attrs']['text']
    end
  end
end
