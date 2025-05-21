require 'minitest/autorun'
require 'asciidoctor'
require 'net/http'
require_relative '../src/jira_macro'
require_relative '../src/adf_converter'

class JiraMacroTest < Minitest::Test
  # Setup and teardown for environment variables
  def setup
    @original_env = {
      'JIRA_BASE_URL' => ENV['JIRA_BASE_URL'],
      'CONFLUENCE_BASE_URL' => ENV['CONFLUENCE_BASE_URL'],
      'CONFLUENCE_API_TOKEN' => ENV['CONFLUENCE_API_TOKEN'],
      'CONFLUENCE_USER_EMAIL' => ENV['CONFLUENCE_USER_EMAIL']
    }
  end
  
  def teardown
    @original_env.each { |key, value| ENV[key] = value }
  end
  
  # Test fixtures 
  def setup_jira_env
    ENV['JIRA_BASE_URL'] = 'https://jira.example.com'
    ENV['CONFLUENCE_BASE_URL'] = 'https://confluence.example.com' 
    ENV['CONFLUENCE_API_TOKEN'] = 'fake-token'
    ENV['CONFLUENCE_USER_EMAIL'] = 'fake@example.com'
  end
  
  # Test data - extracted to reusable methods
  def basic_jira_issues
    {
      "issues" => [
        {
          "key" => "DEMO-1",
          "fields" => {
            "summary" => "First issue",
            "status" => { "name" => "To Do", "statusCategory" => { "name" => "To Do" } }
          }
        },
        {
          "key" => "DEMO-2",
          "fields" => {
            "summary" => "Second issue", 
            "status" => { "name" => "In Progress", "statusCategory" => { "name" => "In Progress" } }
          }
        }
      ]
    }
  end
  
  def standard_fields
    [
      { "id" => "summary", "name" => "Summary", "schema" => { "type" => "string" } },
      { "id" => "description", "name" => "Description", "schema" => { "type" => "string" } },
      { "id" => "status", "name" => "Status", "schema" => { "type" => "status" } }
    ]
  end
  
  # Improved and reusable API mocking
  def mock_api_responses(issues_data, fields_data = nil)
    fields_data ||= standard_fields
    
    # Create a mock response object that behaves like Net::HTTPResponse
    mock_response = Struct.new(:code, :body) do
      def is_a?(klass)
        klass == Net::HTTPSuccess
      end
    end

    # Mock the Net::HTTP.start method directly
    http_mock = Minitest::Mock.new
    
    # Mock the request/response for issues search
    http_mock.expect(:request, mock_response.new('200', issues_data.to_json)) do |req|
      req.path.include?('/search')
    end
    
    # Mock the request/response for fields API
    http_mock.expect(:request, mock_response.new('200', fields_data.to_json)) do |req|
      req.path.include?('/field')
    end
    
    # Return a Proc that can be used with stub
    ->(host, port, options = {}, &block) { block.call(http_mock) }
  end
  
  # Helper for loading and converting documents with the JiraIssuesTableBlockMacro
  def load_and_convert_jira_table(adoc_content, backend = 'html5')
    doc = Asciidoctor.load(
      adoc_content, 
      safe: :safe, 
      backend: backend,
      extensions: proc { block_macro JiraIssuesTableBlockMacro }
    )
    doc.convert
  end
  
  # Helper for loading and converting documents with the JiraInlineMacro
  def load_and_convert_jira_links(adoc_content, backend = 'html5')
    doc = Asciidoctor.load(
      adoc_content, 
      safe: :safe, 
      backend: backend,
      extensions: proc { inline_macro JiraInlineMacro }
    )
    doc.convert
  end

  # Original test methods, now using the helpers
  def asciidoc_with_macros
    <<~ADOC
      jira:ISSUE-123[]
      jira:ISSUE-456[Custom link text]
    ADOC
  end

  def test_jira_macro_with_base_url
    ENV['JIRA_BASE_URL'] = 'https://jira.example.com'
    html = load_and_convert_jira_links(asciidoc_with_macros)

    assert_includes html, '<a href="https://jira.example.com/browse/ISSUE-123">ISSUE-123</a>'
    assert_includes html, '<a href="https://jira.example.com/browse/ISSUE-456">Custom link text</a>'
  end

  def test_jira_macro_without_base_url
    ENV.delete('JIRA_BASE_URL')
    html = load_and_convert_jira_links(asciidoc_with_macros)

    assert_includes html, 'jira:ISSUE-123[]'
    assert_includes html, 'jira:ISSUE-456[Custom link text]'
  end

  def test_jira_issues_table_macro_success
    setup_jira_env
    
    Net::HTTP.stub :start, mock_api_responses(basic_jira_issues) do
      html = load_and_convert_jira_table('jiraIssuesTable::"project = DEMO ORDER BY created DESC"[fields="key,summary,status"]')
      
      assert_includes html, 'DEMO-1'
      assert_includes html, 'First issue'
      assert_includes html, 'To Do'
      assert_includes html, 'DEMO-2'
      assert_includes html, 'Second issue'
      assert_includes html, 'In Progress'
    end
  end

  def test_jira_issues_table_macro_missing_credentials
    ENV.delete('JIRA_BASE_URL')
    ENV.delete('CONFLUENCE_API_TOKEN')
    ENV.delete('CONFLUENCE_USER_EMAIL')

    html = load_and_convert_jira_table('jiraIssuesTable::"project = DEMO ORDER BY created DESC"[fields="key,summary,status"]')
    assert_includes html, 'jiraIssuesTable::"project = DEMO ORDER BY created DESC"[fields="key,summary,status"]'
  end

  def test_jira_issues_table_macro_with_complex_formatting
    setup_jira_env
    
    # Mock response with complex formatting in description field
    complex_issues = {
      "issues" => [
        {
          "key" => "DEMO-1",
          "fields" => {
            "summary" => "Issue with complex formatting",
            "status" => { "name" => "In Progress", "statusCategory" => { "name" => "In Progress" } },
            "description" => "*Overview:*\nThis is a complex issue with formatted content.\n\n*Key Points:*\n\n* First bullet point\n* Second bullet point\n* Third bullet point with *bold* text\n\n*Objectives:*\n\n* Primary goal\n* Secondary goal"
          }
        }
      ]
    }
    
    fields = standard_fields.dup
    fields << { "id" => "customfield_10001", "name" => "Epic Link", "custom" => true, "schema" => { "type" => "string" } }

    # Stub Net::HTTP.start to return our mock
    Net::HTTP.stub :start, mock_api_responses(complex_issues, fields) do
      html = load_and_convert_jira_table('jiraIssuesTable::"project = DEMO"[fields="key,summary,description,status"]')

      # Test various elements
      assert_formatting_elements(html)
    end
  end
  
  # Helper for complex formatting assertions
  def assert_formatting_elements(html)
    # Test proper formatting of various elements
    assert_includes html, 'DEMO-1'
    assert_includes html, 'Issue with complex formatting'
    assert_includes html, 'In Progress (In Progress)'  # Status with category

    # Test for proper bold heading formatting
    assert_includes html, '<strong>Overview:</strong>'
    assert_includes html, '<strong>Key Points:</strong>'
    assert_includes html, '<strong>Objectives:</strong>'

    # Test for bullet point conversion
    assert_includes html, '<div class="ulist">'
    assert_includes html, '<ul>'
    assert_includes html, '<li>'
    assert_includes html, 'First bullet point'
  end

  def test_jira_issues_table_macro_with_links
    setup_jira_env

    # Mock response with links in description field
    link_issues = {
      "issues" => [
        {
          "key" => "DEMO-1",
          "fields" => {
            "summary" => "Issue with links",
            "status" => { "name" => "Open" },
            "description" => "This issue has [https://example.com|an external link] and [https://jira.example.com/browse/RELATED-123|a JIRA issue link|smart-link]."
          }
        }
      ]
    }

    Net::HTTP.stub :start, mock_api_responses(link_issues) do
      html = load_and_convert_jira_table('jiraIssuesTable::"project = DEMO"[fields="key,summary,description"]')

      # Test links are properly converted
      assert_link_formatting(html)
    end
  end
  
  # Helper for link formatting assertions
  def assert_link_formatting(html)
    # Test proper conversion of wiki links to HTML links
    assert_includes html, '<a href="https://example.com">an external link</a>'
    assert_includes html, '<a href="https://jira.example.com/browse/RELATED-123"'
    assert_includes html, '>a JIRA issue link</a>'

    # Make sure smart-link suffix is removed
    refute_includes html, 'smart-link'

    # Test that pipe characters aren't visible in output
    refute_includes html, '|an external link'
  end

  def test_jira_issues_table_custom_field_array_formatting
    setup_jira_env
    
    # Mock response with complex custom fields
    custom_field_issues = {
      "issues" => [
        {
          "key" => "DEMO-1",
          "fields" => {
            "summary" => "Issue with custom fields",
            "customfield_10001" => [
              {"self" => "https://example.com/1", "value" => "Option 1", "id" => "1001"},
              {"self" => "https://example.com/2", "value" => "Option 2", "id" => "1002"}
            ],
            "customfield_10002" => [
              {"self" => "https://example.com/3", "name" => "Name 1", "id" => "1003"},
              {"self" => "https://example.com/4", "name" => "Name 2", "id" => "1004"}
            ],
            "customfield_10003" => [
              {"self" => "https://example.com/5", "displayName" => "Display 1", "id" => "1005"},
              {"self" => "https://example.com/6", "displayName" => "Display 2", "id" => "1006"}
            ],
            "customfield_10004" => ["Simple", "Array", "Values"]
          }
        }
      ]
    }

    # Custom fields metadata
    custom_fields = [
      { "id" => "summary", "name" => "Summary" },
      { "id" => "customfield_10001", "name" => "Custom Field Values", "custom" => true },
      { "id" => "customfield_10002", "name" => "Custom Field Names", "custom" => true },
      { "id" => "customfield_10003", "name" => "Custom Field Display", "custom" => true },
      { "id" => "customfield_10004", "name" => "Custom Field Array", "custom" => true }
    ]

    Net::HTTP.stub :start, mock_api_responses(custom_field_issues, custom_fields) do
      html = load_and_convert_jira_table(
        'jiraIssuesTable::"project = DEMO"[fields="key,customfield_10001,customfield_10002,customfield_10003,customfield_10004"]'
      )

      # Test custom field formatting
      assert_custom_field_formatting(html)
    end
  end
  
  # Helper for custom field formatting assertions
  def assert_custom_field_formatting(html)
    # Test proper conversion of different custom field types
    assert_includes html, 'Option 1, Option 2'
    assert_includes html, 'Name 1, Name 2'
    assert_includes html, 'Display 1, Display 2'
    assert_includes html, 'Simple, Array, Values'
    
    # Test proper field name resolution
    assert_includes html, 'Custom Field Values'
    assert_includes html, 'Custom Field Names' 
    assert_includes html, 'Custom Field Display'
    assert_includes html, 'Custom Field Array'
  end
  
  # Unit tests for helper methods
  def test_format_status_with_category
    macro = JiraIssuesTableBlockMacro.new
    
    # Test with status category
    status_with_category = {
      "name" => "Review",
      "statusCategory" => {
        "name" => "In Progress"
      }
    }
    
    formatted = macro.format_status(status_with_category)
    assert_equal "Review (In Progress)", formatted
    
    # Test with just status name
    status_with_name = {
      "name" => "Done"
    }
    
    formatted = macro.format_status(status_with_name)
    assert_equal "Done", formatted
    
    # Test with string input
    formatted = macro.format_status("Simple String")
    assert_equal "Simple String", formatted
  end

  def test_format_custom_field_handles_nil_values
    macro = JiraIssuesTableBlockMacro.new
    
    # Test that nil values are handled gracefully
    formatted = macro.format_custom_field(nil)
    assert_equal "", formatted
    
    # Test empty arrays
    formatted = macro.format_custom_field([])
    assert_equal "", formatted
    
    # Test empty hash
    formatted = macro.format_custom_field({})
    assert_equal "{}", formatted
  end
end

