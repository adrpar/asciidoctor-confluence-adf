require 'net/http'
require 'json'

# Simple Confluence API client for user lookup
class ConfluenceClient
  def initialize(base_url:, api_token:, user_email:)
    @base_url = base_url
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
        warn ">>> WARN: Failed to query Confluence user: #{res.code} #{res.message}"
        nil
      end
    rescue => e
      warn ">>> WARN: Failed to query Confluence user: #{e}"
      nil
    end
  end
end