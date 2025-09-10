require_relative 'adf_logger'

# Encapsulates acquisition and validation of JIRA / Confluence credentials.
class JiraCredentials
  attr_reader :base_url, :confluence_base_url, :api_token, :user_email

  def self.from_document(doc)
    new(
      base_url: doc.attr('jira-base-url') || ENV['JIRA_BASE_URL'],
      confluence_base_url: doc.attr('confluence-base-url') || doc.attr('jira-base-url') || ENV['CONFLUENCE_BASE_URL'] || ENV['JIRA_BASE_URL'],
      api_token: doc.attr('confluence-api-token') || ENV['CONFLUENCE_API_TOKEN'],
      user_email: doc.attr('confluence-user-email') || ENV['CONFLUENCE_USER_EMAIL']
    )
  end

  def initialize(base_url:, confluence_base_url:, api_token:, user_email:)
    @base_url = base_url
    @confluence_base_url = confluence_base_url
    @api_token = api_token
    @user_email = user_email
  end

  def valid?
    !@base_url.nil? && !@api_token.nil? && !@user_email.nil?
  end

  def to_h
    { base_url: @base_url, confluence_base_url: @confluence_base_url, api_token: @api_token, user_email: @user_email }
  end
end

# Resolves user supplied field tokens to Jira field ids using metadata.
class JiraFieldResolver
  # field_result: structure with :success, :fields (array of Jira field hashes)
  def initialize(field_result)
    @field_result = field_result
    @name_lookup = nil
  end

  # Returns [resolved_fields_array, unknown_fields_array]
  def resolve(user_fields)
    return [user_fields, []] unless success?

    build_lookup_if_needed
    resolved = []
    unknown  = []
    user_fields.each do |token|
      if token =~ /^customfield_\d+$/
        resolved << token
      elsif %w[key summary status description].include?(token)
        resolved << token
      else
        normalized_token = normalize_field_name(token)
        if @name_lookup.key?(normalized_token)
          resolved << @name_lookup[normalized_token]
        else
          unknown << token
        end
      end
    end
    [resolved, unknown]
  end

  private

  def success?
    @field_result && @field_result[:success] && @field_result[:fields]
  end

  def build_lookup_if_needed
    return if @name_lookup
    @name_lookup = {}
    @field_result[:fields].each do |field|
      next unless field['name'] && field['id']
      normalized = normalize_field_name(field['name'].rstrip)
      @name_lookup[normalized] = field['id']
    end
  end

  def normalize_field_name(name)
    name.strip.downcase.gsub(/\s+/, ' ')
  end
end
