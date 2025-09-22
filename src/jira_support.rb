require_relative 'adf_logger'

# Encapsulates acquisition and validation of JIRA / Confluence credentials.
class JiraCredentials
  attr_reader :base_url, :confluence_base_url, :api_token, :user_email

  # One‑time deprecation flags (class variables so they are shared)
  @@deprecated_jira_base_logged = false
  @@deprecated_confluence_base_logged = false

  def self.from_document(doc)
    unified = doc.attr('atlassian-base-url') || ENV['ATLASSIAN_BASE_URL']
    jira_attr = doc.attr('jira-base-url') || ENV['JIRA_BASE_URL']
    conf_attr = doc.attr('confluence-base-url') || ENV['CONFLUENCE_BASE_URL']

    # Determine effective base url precedence: unified > jira > confluence
    base = unified || jira_attr || conf_attr
    confluence_base = unified || conf_attr || jira_attr

    if unified.nil?
      if jira_attr && !@@deprecated_jira_base_logged
        AdfLogger.warn "'jira-base-url' / JIRA_BASE_URL is deprecated. Use 'atlassian-base-url' / ATLASSIAN_BASE_URL instead."
        @@deprecated_jira_base_logged = true
      end
      if conf_attr && !@@deprecated_confluence_base_logged
        AdfLogger.warn "'confluence-base-url' / CONFLUENCE_BASE_URL is deprecated. Use 'atlassian-base-url' / ATLASSIAN_BASE_URL instead."
        @@deprecated_confluence_base_logged = true
      end
    end

    new(
      base_url: base,
      confluence_base_url: confluence_base,
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

  JiraFieldResolutionResult = Struct.new(:resolved, :unknown, keyword_init: true) do
    # Preserve legacy multi-assignment compatibility: resolved, unknown = resolver.resolve(list)
    def to_ary; [resolved, unknown]; end
  end

  # Returns JiraFieldResolutionResult (supports array deconstruction)
  def resolve(user_fields)
    return JiraFieldResolutionResult.new(resolved: user_fields, unknown: []) unless success?

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
    JiraFieldResolutionResult.new(resolved: resolved, unknown: unknown)
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
