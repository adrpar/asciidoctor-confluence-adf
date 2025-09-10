require 'minitest/autorun'
require 'asciidoctor'
require_relative '../src/jira_support'

class JiraSupportTest < Minitest::Test
  def setup
    @original_env = {
      'JIRA_BASE_URL' => ENV['JIRA_BASE_URL'],
      'CONFLUENCE_BASE_URL' => ENV['CONFLUENCE_BASE_URL'],
      'CONFLUENCE_API_TOKEN' => ENV['CONFLUENCE_API_TOKEN'],
      'CONFLUENCE_USER_EMAIL' => ENV['CONFLUENCE_USER_EMAIL']
    }
  end

  def teardown
    @original_env.each { |k,v| ENV[k] = v }
  end

  # JiraCredentials tests --------------------------------------------------
  def test_credentials_from_document_attributes_take_precedence
    ENV['JIRA_BASE_URL'] = 'https://env-jira.example'
    ENV['CONFLUENCE_API_TOKEN'] = 'env-token'
    ENV['CONFLUENCE_USER_EMAIL'] = 'env@example.com'
    doc = Asciidoctor.load '', attributes: {
      'jira-base-url' => 'https://attr-jira.example',
      'confluence-api-token' => 'attr-token',
      'confluence-user-email' => 'attr@example.com'
    }
    creds = JiraCredentials.from_document(doc)
    assert_equal 'https://attr-jira.example', creds.base_url
    assert_equal 'attr-token', creds.api_token
    assert_equal 'attr@example.com', creds.user_email
  end

  def test_credentials_fallback_chain_for_confluence_base_url
    # Case 1: explicit confluence-base-url attribute
    doc1 = Asciidoctor.load '', attributes: {
      'jira-base-url' => 'https://jira.example',
      'confluence-base-url' => 'https://confluence.example',
      'confluence-api-token' => 't',
      'confluence-user-email' => 'u@example.com'
    }
    creds1 = JiraCredentials.from_document(doc1)
    assert_equal 'https://confluence.example', creds1.confluence_base_url

    # Case 2: no confluence-base-url attribute, falls back to jira-base-url attribute
    doc2 = Asciidoctor.load '', attributes: {
      'jira-base-url' => 'https://jira-only.example',
      'confluence-api-token' => 't',
      'confluence-user-email' => 'u@example.com'
    }
    creds2 = JiraCredentials.from_document(doc2)
    assert_equal 'https://jira-only.example', creds2.confluence_base_url

    # Case 3: none in attributes, use ENV CONFLUENCE_BASE_URL then JIRA_BASE_URL
    ENV['CONFLUENCE_BASE_URL'] = 'https://env-confluence.example'
    ENV['JIRA_BASE_URL'] = 'https://env-jira.example'
    ENV['CONFLUENCE_API_TOKEN'] = 't'
    ENV['CONFLUENCE_USER_EMAIL'] = 'u@example.com'
    doc3 = Asciidoctor.load ''
    creds3 = JiraCredentials.from_document(doc3)
    assert_equal 'https://env-confluence.example', creds3.confluence_base_url

    # Case 4: no CONFLUENCE_BASE_URL, falls back to ENV JIRA_BASE_URL
    ENV.delete('CONFLUENCE_BASE_URL')
    creds4 = JiraCredentials.from_document(doc3)
    assert_equal 'https://env-jira.example', creds4.confluence_base_url
  end

  def test_credentials_validity
    doc = Asciidoctor.load '', attributes: {
      'jira-base-url' => 'https://jira.example',
      'confluence-api-token' => 'token',
      'confluence-user-email' => 'user@example.com'
    }
    creds = JiraCredentials.from_document(doc)
    assert creds.valid?, 'Expected credentials to be valid'

    # Missing user email
    doc2 = Asciidoctor.load '', attributes: {
      'jira-base-url' => 'https://jira.example',
      'confluence-api-token' => 'token'
    }
    creds2 = JiraCredentials.from_document(doc2)
    refute creds2.valid?, 'Expected credentials to be invalid when user email missing'
  end

  # JiraFieldResolver tests ------------------------------------------------
  def sample_field_result
    {
      success: true,
      fields: [
        { 'id' => 'summary', 'name' => 'Summary' },
        { 'id' => 'status', 'name' => 'Status' },
        { 'id' => 'customfield_12345', 'name' => 'My Custom Field  ' }, # note trailing spaces
        { 'id' => 'description', 'name' => 'Description' }
      ]
    }
  end

  def test_field_resolver_resolves_known_tokens
    resolver = JiraFieldResolver.new(sample_field_result)
  # Pass display name with spaces as a single token (wrapped how user would specify normally)
  resolved, unknown = resolver.resolve(['key', 'summary', 'My Custom Field', 'status', 'customfield_12345'])
  assert_empty unknown, "Expected no unknown fields, got #{unknown.inspect}"
    # Expect summary, status, custom field id, key, customfield_12345 preserved
    assert_includes resolved, 'summary'
    assert_includes resolved, 'status'
    assert_includes resolved, 'customfield_12345'
    assert_includes resolved, 'key'
  end

  def test_field_resolver_identifies_unknown_fields
    resolver = JiraFieldResolver.new(sample_field_result)
    resolved, unknown = resolver.resolve(%w[summary NotAField])
    assert_includes resolved, 'summary'
    assert_equal ['NotAField'], unknown
  end

  def test_field_resolver_case_and_space_insensitive
    resolver = JiraFieldResolver.new(sample_field_result)
    resolved, unknown = resolver.resolve(['my   custom   field'])
    assert_includes resolved, 'customfield_12345'
    assert_empty unknown
  end

  def test_field_resolver_passthrough_when_metadata_missing
    resolver = JiraFieldResolver.new({ success: false })
    user = %w[key summary customfield_99999]
    resolved, unknown = resolver.resolve(user)
    assert_equal user, resolved
    assert_empty unknown
  end
end
