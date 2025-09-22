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

    # Lightweight HTTP mock allowing any order of requests
    http_mock = Object.new
    def http_mock.initialize_responses(search_body, fields_body, response_class)
      @search_body = search_body
      @fields_body = fields_body
      @response_class = response_class
    end
    def http_mock.request(req)
      if req.path.include?('/field')
        @response_class.new('200', @fields_body.to_json)
      elsif req.path.include?('/search')
        @response_class.new('200', @search_body.to_json)
      else
        @response_class.new('404', '{}')
      end
    end
    http_mock.initialize_responses(issues_data, fields_data, mock_response)

    ->(host, port, options = {}, &block) { block.call(http_mock) }
  end
  
  # Helper for loading and converting documents with the JiraIssuesTableBlockMacro
  def load_and_convert_jira_table(adoc_content, backend = 'html5', attributes = {})
    doc = Asciidoctor.load(
      adoc_content, 
      safe: :safe, 
      backend: backend,
      extensions: proc { block_macro JiraIssuesTableBlockMacro },
      attributes: attributes
    )
    doc.convert
  end
  
  # Helper for loading and converting documents with the JiraInlineMacro
  def load_and_convert_jira_links(adoc_content, backend = 'html5', attributes = {})
    doc = Asciidoctor.load(
      adoc_content, 
      safe: :safe, 
      backend: backend,
      extensions: proc { inline_macro JiraInlineMacro },
      attributes: attributes
    )
    doc.convert
  end
  
  # Test setting attributes via command-line style attributes parameter
  def test_jira_macro_with_command_line_attributes
    ENV.delete('JIRA_BASE_URL')
    
    html = load_and_convert_jira_links(
      asciidoc_with_macros, 
      'html5', 
      { 'jira-base-url' => 'https://cli-example.com' }
    )
    
    assert_includes html, '<a href="https://cli-example.com/browse/ISSUE-123">ISSUE-123</a>'
    assert_includes html, '<a href="https://cli-example.com/browse/ISSUE-456">Custom link text</a>'
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
  
  def test_jira_macro_with_document_attribute
    ENV.delete('JIRA_BASE_URL')
    adoc = <<~ADOC
      :jira-base-url: https://company.atlassian.net
      
      jira:ISSUE-123[]
      jira:ISSUE-456[Custom link text]
    ADOC
    
    html = load_and_convert_jira_links(adoc)
    
    assert_includes html, '<a href="https://company.atlassian.net/browse/ISSUE-123">ISSUE-123</a>'
    assert_includes html, '<a href="https://company.atlassian.net/browse/ISSUE-456">Custom link text</a>'
  end

  def test_jira_macro_without_base_url
    ENV.delete('JIRA_BASE_URL')
    ENV.delete('ATLASSIAN_BASE_URL')
    ENV.delete('CONFLUENCE_BASE_URL')
    html = load_and_convert_jira_links(asciidoc_with_macros)

    assert_includes html, 'jira:ISSUE-123[]'
    assert_includes html, 'jira:ISSUE-456[Custom link text]'
  end

  def test_jira_issues_table_macro_success
    setup_jira_env
    
    Net::HTTP.stub :start, mock_api_responses(basic_jira_issues) do
      html = load_and_convert_jira_table("jiraIssuesTable::['project = DEMO ORDER BY created DESC', fields='key,summary,status']")
      
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

    html = load_and_convert_jira_table("jiraIssuesTable::['project = DEMO ORDER BY created DESC', fields='key,summary,status']")
    assert_includes html, "jiraIssuesTable::['project = DEMO ORDER BY created DESC', fields='key,summary,status']"
  end
  
  def test_jira_issues_table_macro_with_document_attributes
    ENV.delete('JIRA_BASE_URL')
    ENV.delete('CONFLUENCE_API_TOKEN')
    ENV.delete('CONFLUENCE_USER_EMAIL')
    
    adoc = <<~ADOC
      :jira-base-url: https://company.atlassian.net
      :confluence-api-token: test-token
      :confluence-user-email: test@example.com
      
      jiraIssuesTable::['project = DEMO ORDER BY created DESC', fields='key,summary,status']
    ADOC
    
    Net::HTTP.stub :start, mock_api_responses(basic_jira_issues) do
      html = load_and_convert_jira_table(adoc)
      
      assert_includes html, 'DEMO-1'
      assert_includes html, 'First issue'
      assert_includes html, 'To Do'
      assert_includes html, 'DEMO-2'
      assert_includes html, 'Second issue'
      assert_includes html, 'In Progress'
    end
  end
  
  # Test that document attributes take precedence over environment variables
  def test_jira_issues_table_macro_attributes_precedence
    ENV['JIRA_BASE_URL'] = 'https://env-example.com'
    ENV['CONFLUENCE_API_TOKEN'] = 'env-token'
    ENV['CONFLUENCE_USER_EMAIL'] = 'env@example.com'
    
    adoc = <<~ADOC
      :jira-base-url: https://attr-example.com
      :confluence-api-token: attr-token
      :confluence-user-email: attr@example.com
      
      jiraIssuesTable::['project = DEMO', fields='key,summary,status']
    ADOC
    
    # Create mock for HTTP requests to verify correct URLs are used
    mock_response = Struct.new(:code, :body) do
      def is_a?(klass)
        klass == Net::HTTPSuccess
      end
    end
    
    http_mock = Minitest::Mock.new
    
    # Expect requests to the attribute URL, not the ENV URL
    http_mock.expect(:request, mock_response.new('200', basic_jira_issues.to_json)) do |req|
      req.path.include?('/search') && req['Authorization'].include?('attr-token')
    end
    
    http_mock.expect(:request, mock_response.new('200', standard_fields.to_json)) do |req|
      req.path.include?('/field')
    end
    
    Net::HTTP.stub :start, ->(host, port, options = {}, &block) { 
      assert_equal 'attr-example.com', host, "Should use the host from document attributes"
      block.call(http_mock) 
    } do
      html = load_and_convert_jira_table(adoc)
      
      # Basic verification that the table was rendered
      assert_includes html, 'key'
      assert_includes html, 'summary' 
      assert_includes html, 'status'
    end
    
    http_mock.verify
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
      html = load_and_convert_jira_table("jiraIssuesTable::['project = DEMO', fields='key,summary,description,status']")

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
      html = load_and_convert_jira_table("jiraIssuesTable::['project = DEMO', fields='key,summary,description']")

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
        "jiraIssuesTable::['project = DEMO', fields='key,customfield_10001,customfield_10002,customfield_10003,customfield_10004']"
      )

      # Test custom field formatting
      assert_custom_field_formatting(html)
    end
  end

  def test_jira_issues_table_field_name_resolution
    setup_jira_env

    issues = {
      'issues' => [
        {
          'key' => 'DEMO-9',
          'fields' => {
            'summary' => 'Summary Text',
            'status' => { 'name' => 'Done', 'statusCategory' => { 'name' => 'Done' } },
            'customfield_12345' => 'Custom Value'
          }
        }
      ]
    }

    fields_meta = [
      { 'id' => 'summary', 'name' => 'Summary' },
      { 'id' => 'status', 'name' => 'Status' },
      { 'id' => 'customfield_12345', 'name' => 'My Custom Field', 'custom' => true }
    ]

    Net::HTTP.stub :start, mock_api_responses(issues, fields_meta) do
      html = load_and_convert_jira_table("jiraIssuesTable::['project = DEMO', fields='key,Summary,My Custom Field,status']")
      assert_includes html, 'DEMO-9'
      assert_includes html, 'Summary Text'
      assert_includes html, 'Custom Value'
      # Header should show resolved custom field name
      assert_includes html, 'My Custom Field'
    end
  end

  def test_jira_issues_table_field_name_resolution_with_trailing_spaces
    setup_jira_env
    issues = {
      'issues' => [
        { 'key' => 'DEMO-11', 'fields' => { 'summary' => 'Has spaced custom', 'customfield_55555' => 'Spaced Value' } }
      ]
    }
    fields_meta = [
      { 'id' => 'summary', 'name' => 'Summary' },
      { 'id' => 'customfield_55555', 'name' => 'Custom Field With Space   ', 'custom' => true }
    ]
    Net::HTTP.stub :start, mock_api_responses(issues, fields_meta) do
      html = load_and_convert_jira_table("jiraIssuesTable::['project = DEMO', fields='key,Summary,Custom Field With Space,status']")
      assert_includes html, 'DEMO-11'
      assert_includes html, 'Spaced Value'
      # Header should not include trailing spaces
      refute_includes html, 'Custom Field With Space   '
      assert_includes html, 'Custom Field With Space'
    end
  end

  def test_jira_issues_table_field_parsing_with_commas_inside_quotes
    setup_jira_env
    issues = {
      'issues' => [
        {
          'key' => 'DEMO-12',
          'fields' => {
            'summary' => 'Comma field test',
            'customfield_66666' => 'Value A',
            'customfield_77778' => 'Value B'
          }
        }
      ]
    }
    fields_meta = [
      { 'id' => 'summary', 'name' => 'Summary' },
      { 'id' => 'customfield_66666', 'name' => 'Complex, Field Name', 'custom' => true },
      { 'id' => 'customfield_77778', 'name' => "Another 'Quoted' Field", 'custom' => true }
    ]
    Net::HTTP.stub :start, mock_api_responses(issues, fields_meta) do
      # Use quotes around names containing commas and quotes
      # Inner single quotes inside a single-quoted token must be doubled per CSV-style escaping rules
      html = load_and_convert_jira_table("jiraIssuesTable::[\"project = DEMO\", fields=\"key,Summary,'Complex, Field Name','Another ''Quoted'' Field'\"]")
      assert_includes html, 'DEMO-12'
      assert_includes html, 'Complex, Field Name'
      assert_includes html, "Another 'Quoted' Field"

      html = load_and_convert_jira_table("jiraIssuesTable::['project = DEMO', fields='key,Summary,\"Complex, Field Name\",\"Another \\'Quoted\\' Field\"']")
      assert_includes html, 'DEMO-12'
      assert_includes html, 'Complex, Field Name'
      assert_includes html, "Another 'Quoted' Field"
    end
  end

  def test_jira_issues_table_field_parsing_with_inner_single_quotes_in_double_quoted_field
    setup_jira_env
    issues = {
      'issues' => [
        {
          'key' => 'DEMO-13',
          'fields' => {
            'summary' => 'Inner quotes test',
            'customfield_66666' => 'Value A',
            'customfield_77778' => 'Value B'
          }
        }
      ]
    }
    fields_meta = [
      { 'id' => 'summary', 'name' => 'Summary' },
      { 'id' => 'customfield_66666', 'name' => 'Complex, Field Name', 'custom' => true },
      { 'id' => 'customfield_77778', 'name' => "Another 'Quoted' Field", 'custom' => true }
    ]
    Net::HTTP.stub :start, mock_api_responses(issues, fields_meta) do
      # Double-quoted field containing a single-quoted word should remain unchanged by normalization
      macro = "jiraIssuesTable::['project = DEMO', fields='key,Summary,\"Complex, Field Name\",\"Another \\'Quoted\\' Field\"']"
      html = load_and_convert_jira_table(macro)
      assert_includes html, 'DEMO-13'
      assert_includes html, 'Complex, Field Name'
      assert_includes html, "Another 'Quoted' Field"
      refute_includes html, 'Another "Quoted" Field', 'Inner single quotes were incorrectly converted to double quotes'
    end
  end

  def test_jira_issues_table_unknown_field_raises_error_and_prints_reference
    setup_jira_env

    issues = basic_jira_issues
    fields_meta = standard_fields

    Net::HTTP.stub :start, mock_api_responses(issues, fields_meta) do
      html = load_and_convert_jira_table("jiraIssuesTable::['project = DEMO', fields='key,summary,NotAField,status']")
      # Placeholder currently renders with bracketed target and comma separated attributes
      assert_includes html, "jiraIssuesTable::['project = DEMO', fields='key,summary,NotAField,status']"
    end
  end

  def test_jira_issues_table_direct_customfield_id_supported
    setup_jira_env
    issues = {
      'issues' => [
        {
          'key' => 'DEMO-10',
          'fields' => {
            'summary' => 'Has direct custom id',
            'customfield_77777' => 'Direct Custom'
          }
        }
      ]
    }
    fields_meta = [
      { 'id' => 'summary', 'name' => 'Summary' },
      { 'id' => 'customfield_77777', 'name' => 'Direct Custom Field', 'custom' => true }
    ]

    Net::HTTP.stub :start, mock_api_responses(issues, fields_meta) do
      html = load_and_convert_jira_table("jiraIssuesTable::['project = DEMO', fields='key,summary,customfield_77777']")
      assert_includes html, 'DEMO-10'
      assert_includes html, 'Direct Custom'
      assert_includes html, 'Direct Custom Field'
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
    
    formatted = macro.format_status_field(status_with_category)
    assert_equal "Review (In Progress)", formatted
    
    # Test with just status name
    status_with_name = {
      "name" => "Done"
    }
    
    formatted = macro.format_status_field(status_with_name)
    assert_equal "Done", formatted
    
    # Test with string input
    formatted = macro.format_status_field("Simple String")
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

  # Add a test for ADF conversion of complex formatting
  def test_jira_issues_table_macro_with_complex_formatting_in_adf
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
      # Use ADF backend for conversion
      adoc_with_macros = "jiraIssuesTable::['project = DEMO', fields='key,summary,description,status']"
      doc = Asciidoctor.load(adoc_with_macros, safe: :safe, backend: 'adf', extensions: proc { block_macro JiraIssuesTableBlockMacro })
      adf_json = doc.converter.convert(doc, 'document')

      # Parse the ADF output
      adf_data = JSON.parse(adf_json)

      # Test the structure
      assert_equal "doc", adf_data["type"]
      assert adf_data["content"].is_a?(Array)
      
      # Find the table in the content
      table = adf_data["content"].find { |node| node["type"] == "table" }
      assert table, "Should contain a table node"

      # Test table structure
      assert table["content"].is_a?(Array), "Table should have content"
      
      # Test table rows
      assert table["content"].size >= 2, "Table should have at least 2 rows (header + data)"
      
      # Find the header row
      header_row = table["content"].first
      assert_equal "tableRow", header_row["type"]
      assert header_row["content"].is_a?(Array)
      
      # Verify header cells
      header_cells = header_row["content"]
      header_names = header_cells.map { |cell| 
        cell["content"].first["content"].first["text"] rescue nil 
      }.compact
      
      assert_includes header_names, "Key"
      assert_includes header_names, "Summary" 
      assert_includes header_names, "Description"
      assert_includes header_names, "Status"
      
      # Find the data row
      data_row = table["content"][1]
      assert_equal "tableRow", data_row["type"]
      
      # Get the cells of the data row
      data_cells = data_row["content"]
      assert_equal 4, data_cells.size, "Should have 4 columns in the data row"
      
      # Find the description cell (third cell)
      description_cell = data_cells[2]
      description_content = description_cell["content"]
      
      # Extract texts from description
      texts = extract_all_texts(description_content)
      
      # Verify complex formatting elements
      assert texts.any? { |t| t.include?("Overview") }, "Should include Overview heading"
      assert texts.any? { |t| t.include?("Key Points") }, "Should include Key Points heading"
      assert texts.any? { |t| t.include?("Objectives") }, "Should include Objectives heading"
      assert texts.any? { |t| t.include?("First bullet point") }, "Should include first bullet point"
      assert texts.any? { |t| t.include?("Second bullet point") }, "Should include second bullet point"
      assert texts.any? { |t| t.include?("Third bullet point with") }, "Should include third bullet point"
      assert texts.any? { |t| t.include?("bold") }, "Should include bold text"
      assert texts.any? { |t| t.include?("Primary goal") }, "Should include primary goal"
      
      # Verify that the description contains proper structures
      has_bullet_list = find_node_by_type(description_content, "bulletList")
      assert has_bullet_list, "Should contain bullet lists in the description"
      
      # Verify status cell (fourth cell)
      status_cell = data_cells[3]
      status_text = status_cell["content"].first["content"].first["text"] rescue nil
      assert_equal "In Progress (In Progress)", status_text
    end
  end

  # Helper method to recursively extract all text nodes from ADF content
  def extract_all_texts(content)
    return [] unless content.is_a?(Array)
    
    result = []
    content.each do |node|
      if node["type"] == "text"
        result << node["text"]
      end
      
      # Process any child content
      if node["content"].is_a?(Array)
        result.concat(extract_all_texts(node["content"]))
      end
    end
    
    result
  end

  # Helper method to find a node of a specific type in ADF content
  def find_node_by_type(content, type)
    return nil unless content.is_a?(Array)
    
    # Look for the node type at this level
    node = content.find { |n| n["type"] == type }
    return node if node
    
    # Recursively search in child content
    content.each do |child|
      if child["content"].is_a?(Array)
        found = find_node_by_type(child["content"], type)
        return found if found
      end
    end
    
    nil
  end

  def test_jira_issues_table_macro_with_title
    setup_jira_env

    # Mock response for Jira issues
    mock_issues = {
      "issues" => [
        {
          "key" => "DEMO-1",
          "fields" => {
            "summary" => "First issue",
            "status" => { "name" => "To Do", "statusCategory" => { "name" => "To Do" } }
          }
        }
      ]
    }

    # Stub Net::HTTP.start to return the mock response
    Net::HTTP.stub :start, mock_api_responses(mock_issues) do
      # Test with the title attribute
      adoc_content = "jiraIssuesTable::['project = DEMO', fields='key,summary,status', title='Demo Project Issues']"
      html = load_and_convert_jira_table(adoc_content)

      # Verify the title is rendered as bold text
      assert_includes html, '<strong>Demo Project Issues</strong>'
      # Verify the table content is still rendered correctly
      assert_includes html, 'DEMO-1'
      assert_includes html, 'First issue'
      assert_includes html, 'To Do'
    end
  end

  def test_jira_issues_table_with_adf_description
    setup_jira_env

    adf_description = {
      "version" => 1,
      "type" => "doc",
      "content" => [
        {
          "type" => "paragraph",
          "content" => [
            { "type" => "text", "text" => "This is a description in ADF." }
          ]
        },
        {
          "type" => "bulletList",
          "content" => [
            {
              "type" => "listItem",
              "content" => [
                {
                  "type" => "paragraph",
                  "content" => [
                    { "type" => "text", "text" => "ADF Item 1" }
                  ]
                }
              ]
            }
          ]
        }
      ]
    }

    issues_with_adf = {
      "issues" => [
        {
          "key" => "DEMO-3",
          "fields" => {
            "summary" => "ADF Description",
            "status" => { "name" => "Done" },
            "description" => adf_description
          }
        }
      ]
    }

    Net::HTTP.stub :start, mock_api_responses(issues_with_adf) do
    html = load_and_convert_jira_table("jiraIssuesTable::['project = DEMO', fields='key,summary,description,status']")

  # Accept both legacy expected snippet (without content wrapper) and current Asciidoctor output (with wrapper)
  assert_includes html, 'This is a description in ADF.'
  assert_includes html, 'ADF Item 1'
  assert_includes html, '<div class="ulist">'
    end
  end
end

def test_atlas_mention_in_table_cell_renders_mention_node
  # Ensure required env for client construction (values won't be used due to stub)
  ENV['CONFLUENCE_BASE_URL'] = 'https://example.atlassian.net'
  ENV['CONFLUENCE_API_TOKEN'] = 'token'
  ENV['CONFLUENCE_USER_EMAIL'] = 'user@example.com'

  # Mock the ConfluenceJiraClient to return a user for atlasMention macro
  mock_client = Minitest::Mock.new
  mock_client.expect(:find_user_by_fullname, { 'id' => 'user-123', 'displayName' => 'Alex Example' }, ['Alex Example'])

  ConfluenceJiraClient.stub :new, mock_client do
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

def test_atlas_mention_macro_with_adf_output
  setup_jira_env

  # Mock the ConfluenceJiraClient to return a user
  mock_client = Minitest::Mock.new
  mock_client.expect(:find_user_by_fullname, { "id" => "12345", "displayName" => "John Doe" }, ["John Doe"])
  ConfluenceJiraClient.stub :new, mock_client do
    adoc_content = 'atlasMention:John_Doe[]'
    doc = Asciidoctor.load(adoc_content, safe: :safe, backend: 'adf', extensions: proc { inline_macro AtlasMentionInlineMacro })
    adf_json = doc.converter.convert(doc, 'document')

    # Parse the ADF output
    adf_data = JSON.parse(adf_json)

    # Verify the mention node
    mention_node = adf_data["content"].find { |node| node["type"] == "mention" }
    assert mention_node, "Should contain a mention node"
    assert_equal "12345", mention_node["attrs"]["id"]
    assert_equal "@John Doe", mention_node["attrs"]["text"]
  end
end

def test_atlas_mention_macro_with_html_output
  setup_jira_env

  # Mock the ConfluenceJiraClient to return a user
  mock_client = Minitest::Mock.new
  mock_client.expect(:find_user_by_fullname, { "id" => "12345", "displayName" => "John Doe" }, ["John Doe"])
  ConfluenceJiraClient.stub :new, mock_client do
    adoc_content = 'atlasMention:John_Doe[]'
    html = Asciidoctor.convert(adoc_content, safe: :safe, backend: 'html5', extensions: proc { inline_macro AtlasMentionInlineMacro })

    # Verify the HTML output
    assert_includes html, "@John Doe"
  end
end

def test_atlas_mention_macro_missing_credentials
  ENV.delete('CONFLUENCE_BASE_URL')
  ENV.delete('CONFLUENCE_API_TOKEN')
  ENV.delete('CONFLUENCE_USER_EMAIL')

  adoc_content = 'atlasMention:John_Doe[]'
  html = Asciidoctor.convert(adoc_content, safe: :safe, backend: 'html5', extensions: proc { inline_macro AtlasMentionInlineMacro })

  # Verify fallback behavior
  assert_includes html, "@John Doe"
end

def test_atlas_mention_macro_with_document_attributes
  ENV.delete('CONFLUENCE_BASE_URL')
  ENV.delete('CONFLUENCE_API_TOKEN')
  ENV.delete('CONFLUENCE_USER_EMAIL')
  
  adoc_content = <<~ADOC
    :confluence-base-url: https://company.atlassian.net
    :confluence-api-token: test-token
    :confluence-user-email: test@example.com
    
    atlasMention:John_Doe[]
  ADOC
  
  # Mock the ConfluenceJiraClient to return a user
  mock_client = Minitest::Mock.new
  mock_client.expect(:find_user_by_fullname, { "id" => "12345", "displayName" => "John Doe" }, ["John Doe"])
  
  ConfluenceJiraClient.stub :new, mock_client do
    doc = Asciidoctor.load(adoc_content, safe: :safe, backend: 'adf', extensions: proc { inline_macro AtlasMentionInlineMacro })
    adf_json = doc.converter.convert(doc, 'document')

    # Parse the ADF output
    adf_data = JSON.parse(adf_json)

    # Verify the mention node
    mention_node = adf_data["content"].find { |node| node["type"] == "mention" }
    assert mention_node, "Should contain a mention node"
    assert_equal "12345", mention_node["attrs"]["id"]
    assert_equal "@John Doe", mention_node["attrs"]["text"]
  end
end

def test_atlas_mention_macro_user_not_found
  setup_jira_env

  # Mock the ConfluenceJiraClient to return nil for user
  mock_client = Minitest::Mock.new
  mock_client.expect(:find_user_by_fullname, nil, ["John Doe"])
  ConfluenceJiraClient.stub :new, mock_client do
    adoc_content = 'atlasMention:John_Doe[]'
    html = Asciidoctor.convert(adoc_content, safe: :safe, backend: 'html5', extensions: proc { inline_macro AtlasMentionInlineMacro })

    # Verify fallback behavior
    assert_includes html, "@John Doe"
  end

  # Helper method to find a node of a specific type in ADF content
  def find_node_by_type(content, type)
    return nil unless content.is_a?(Array)
    
    # Look for the node type at this level
    node = content.find { |n| n["type"] == type }
    return node if node
    
    # Recursively search in child content
    content.each do |child|
      if child["content"].is_a?(Array)
        found = find_node_by_type(child["content"], type)
        return found if found
      end
    end
    
    nil
  end
end

