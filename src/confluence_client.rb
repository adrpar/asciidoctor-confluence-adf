require 'net/http'
require 'json'
require_relative 'adf_logger'

# Simple Confluence and Jira API client
class ConfluenceJiraClient
  def initialize(base_url:, jira_base_url:, api_token:, user_email:)
    @base_url = base_url
    @jira_base_url = jira_base_url
    @api_token = api_token
    @user_email = user_email
  end

  def find_user_by_fullname(fullname)
    uri = URI("#{@base_url}/wiki/rest/api/search/user?cql=#{URI.encode_www_form_component("user.fullname~\"#{fullname}\"")}")
    req = Net::HTTP::Get.new(uri)
    req.basic_auth(@user_email, @api_token)
    req['Accept'] = 'application/json'

    begin
      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
        http.request(req)
      end
      if res.is_a?(Net::HTTPSuccess)
        data = JSON.parse(res.body)
        if data['results'].is_a?(Array) && !data['results'].empty?
          user = data['results'][0]['user']
          {
            "id" => user['accountId'],
            "displayName" => user['displayName']
          }
        else
          nil
        end
      else
        AdfLogger.warn "Failed to query Confluence user: #{uri} -> #{res.code} #{res.message}"
        nil
      end
    rescue => e
      AdfLogger.warn "Failed to query Confluence user: #{e}"
      nil
    end
  end

  # Query Jira issues using JQL - Updated to use v3 JQL endpoint
  def query_jira_issues(jql:, fields: nil)
    # Updated to new REST API v3 JQL search endpoint
    uri = URI("#{@jira_base_url}/rest/api/3/search/jql")
    params = { 'jql' => jql }
    params['fields'] = fields.join(',') if fields # Only add fields parameter if specified
    uri.query = URI.encode_www_form(params)
    
    req = Net::HTTP::Get.new(uri)
    req.basic_auth(@user_email, @api_token)
    req['Accept'] = 'application/json'

    begin
      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
        http.request(req)
      end
      
      if res.code.to_i == 200
        data = JSON.parse(res.body)
        { success: true, data: data }
      else
        { success: false, error: "Jira API query failed: #{uri.to_s} -> #{res.code} #{res.body}" }
      end
    rescue => e
      { success: false, error: "Failed to query Jira: #{e}" }
    end
  end

  # Get all available Jira fields metadata - Updated to use v3 API
  def get_jira_fields
    # Updated to REST API v3 field endpoint
    uri = URI("#{@jira_base_url}/rest/api/3/field")
    req = Net::HTTP::Get.new(uri)
    req.basic_auth(@user_email, @api_token)
    req['Accept'] = 'application/json'

    begin
      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
        http.request(req)
      end
      
      if res.code.to_i == 200
        fields = JSON.parse(res.body)
        { success: true, fields: fields }
      else
        { success: false, error: "Failed to get Jira fields: #{uri.to_s} -> #{res.code} #{res.body}" }
      end
    rescue => e
      { success: false, error: "Error fetching Jira fields: #{e}" }
    end
  end
end