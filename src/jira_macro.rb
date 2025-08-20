require 'asciidoctor'
require 'asciidoctor/extensions'
require 'net/http'
require 'json'

require_relative 'confluence_client'

class JiraInlineMacro < Asciidoctor::Extensions::InlineMacroProcessor
  use_dsl

  named :jira
  name_positional_attributes 'text'

  def process parent, target, attrs
    base_url = ENV['JIRA_BASE_URL']
    if base_url.nil? || base_url.empty?
      warn ">>> WARN: No Jira base URL found, the Jira extension may not work as expected."
      if attrs['text']
        return %(jira:#{target}[#{attrs['text']}])
      else
        return %(jira:#{target}[])
      end
    else
      url = "#{base_url}/browse/#{target}"
      text = attrs['text'] || target
      create_anchor parent, text, type: :link, target: url
    end
  end
end

class AtlasMentionInlineMacro < Asciidoctor::Extensions::InlineMacroProcessor
  use_dsl

  named :atlasMention
  name_positional_attributes 'text'

  def process parent, target, attrs
    name = target.tr('_', ' ')
    if parent.document.converter && parent.document.converter.backend == 'adf'
      confluence_base_url = ENV['CONFLUENCE_BASE_URL']
      jira_base_url = ENV['JIRA_BASE_URL'] || confluence_base_url
      api_token = ENV['CONFLUENCE_API_TOKEN']
      user_email = ENV['CONFLUENCE_USER_EMAIL']

      if confluence_base_url.nil? || api_token.nil? || user_email.nil?
        warn ">>> WARN: Missing Confluence API credentials for atlasMention macro."
        return { "type" => "text", "text" => "@#{name}" }.to_json
      end

      client = ConfluenceJiraClient.new(
        base_url: confluence_base_url,
        jira_base_url: jira_base_url,
        api_token: api_token,
        user_email: user_email
      )
      user = client.find_user_by_fullname(name)

      if user
        {
          "type" => "mention",
          "attrs" => {
            "id" => user["id"],
            "text" => "@#{user["displayName"]}"
          }
        }.to_json
      else
        "@#{name}"
      end
    else
      "@#{name}"
    end
  end
end

class JiraIssuesTableBlockMacro < Asciidoctor::Extensions::BlockMacroProcessor
  use_dsl

  named :jiraIssuesTable
  name_positional_attributes 'jql'

  def process(parent, target, attrs)
    return handle_invalid_attributes(parent, target, attrs) unless valid_attributes?(attrs)
    
    credentials = get_credentials
    return handle_missing_credentials(parent, target, attrs) unless credentials_valid?(credentials)
    
    fields = parse_fields(attrs)
    jql = parse_jql(target, attrs)
    return handle_missing_jql(parent, target, attrs) if jql.nil? || jql.empty?

    client = create_jira_client(credentials)
    
    result = client.query_jira_issues(
      jql: jql,
      fields: fields
    )
    
    field_result = client.get_jira_fields
    
    if api_query_successful?(result)
      table_content = build_table(result[:data]['issues'], fields, field_result, credentials[:base_url])
      
      # Add bold title if specified
      if attrs['title']
        title_content = "**#{attrs['title']}**\n\n"
        table_content = title_content + table_content
      end

      parse_content parent, table_content, {}
    else
      handle_failed_api_query(parent, target, attrs, result)
    end
  end

  def format_status_field(status_field)
    if status_field.is_a?(Hash)
      if status_field['statusCategory'] && status_field['statusCategory']['name']
        "#{status_field['name']} (#{status_field['statusCategory']['name']})"
      else
        status_field['name'] || status_field.to_s
      end
    else
      status_field.to_s
    end
  end

  def format_custom_field(field_value)
    case field_value
    when Array
      format_array_field(field_value)
    when Hash
      format_hash_field(field_value)
    when String
      format_string_field(field_value)
    when nil
      ""
    else
      field_value.to_s
    end
  end

  # Handle array values in custom fields
  def format_array_field(array_value)
    if array_value.empty?
      ""
    elsif array_value.first.is_a?(Hash)
      if array_value.first.key?("value")
        array_value.map { |item| item["value"] }.join(", ")
      elsif array_value.first.key?("name")
        array_value.map { |item| item["name"] }.join(", ")
      elsif array_value.first.key?("displayName")
        array_value.map { |item| item["displayName"] }.join(", ")
      else
        array_value.map(&:to_s).join(", ")
      end
    else
      array_value.join(", ")
    end
  end

  # Handle hash values in custom fields
  def format_hash_field(hash_value)
    if hash_value.key?("value")
      hash_value["value"].to_s
    elsif hash_value.key?("name")
      hash_value["name"].to_s
    elsif hash_value.key?("displayName")
      hash_value["displayName"].to_s
    else
      hash_value.to_s
    end
  end

  private

  def valid_attributes?(attrs)
    valid_attrs = ['jql', 'fields', 'title', '1']
    unknown_attrs = attrs.keys.reject { |k| valid_attrs.include?(k.to_s()) || k.to_s().start_with?('_') }
    
    if unknown_attrs.empty?
      true
    else
      warn ">>> WARN: Unknown attributes for jiraIssuesTable macro: #{unknown_attrs.join(', ')}"
      false
    end
  end

  def credentials_valid?(credentials)
    !credentials[:base_url].nil? && !credentials[:api_token].nil? && !credentials[:user_email].nil?
  end

  def handle_invalid_attributes(parent, target, attrs)
    create_paragraph(parent, "jiraIssuesTable::#{target}[INVALID ATTRIBUTES]", {})
  end

  def handle_missing_credentials(parent, target, attrs)
    warn ">>> WARN: Missing Jira API credentials for jiraIssuesTable macro."
    create_paragraph(parent, "jiraIssuesTable::#{target}[fields=\"#{attrs['fields']}\"]", {})
  end

  def handle_missing_jql(parent, target, attrs)
    warn ">>> WARN: Missing JQL query for jiraIssuesTable macro."
    create_paragraph(parent, "jiraIssuesTable::#{target}[fields=\"#{attrs['fields']}\"]", {})
  end

  def handle_failed_api_query(parent, target, attrs, result)
    warn ">>> WARN: Jira API query failed or returned no issues: #{result[:message] || 'Unknown error'}"
    create_paragraph(parent, "jiraIssuesTable::#{target}[fields=\"#{attrs['fields']}\"]", {})
  end

  def get_credentials
    {
      base_url: ENV['JIRA_BASE_URL'],
      confluence_base_url: ENV['CONFLUENCE_BASE_URL'] || ENV['JIRA_BASE_URL'],
      api_token: ENV['CONFLUENCE_API_TOKEN'],
      user_email: ENV['CONFLUENCE_USER_EMAIL']
    }
  end

  def parse_fields(attrs)
    fields_param = attrs['fields'] 
    fields = fields_param ? fields_param.split(',').map(&:strip) : nil
    fields || ['key', 'summary', 'status']
  end

  def parse_jql(target, attrs)
    target.to_s.empty? ? attrs['jql'] : target
  end

  def create_jira_client(credentials)
    ConfluenceJiraClient.new(
      base_url: credentials[:confluence_base_url],
      jira_base_url: credentials[:base_url],
      api_token: credentials[:api_token],
      user_email: credentials[:user_email]
    )
  end

  def api_query_successful?(result)
    result[:success] && result[:data] && result[:data]['issues']
  end

  def build_table(issues, fields, field_result, base_url)
    field_names = build_field_names_mapping(field_result)
    print_field_information_for_debugging(issues, field_result)

    # Build the table structure
    col_defs = define_column_widths(fields)
    table = initialize_table(col_defs)
    
    # Add header row
    header_row = build_header_row(fields, field_names)
    table << "| " + header_row.join(" | ") + "\n"
    
    # Add data rows
    issues.each do |issue|
      table << build_table_row(issue, fields, base_url) + "\n"
    end
    
    table << "|===\n"
    table
  end

  def build_field_names_mapping(field_result)
    field_names = {}
    
    if field_result && field_result[:success] && field_result[:fields]
      field_result[:fields].each do |field|
        field_names[field['id']] = field['name']
      end
    end
    
    field_names
  end

  def define_column_widths(fields)
    fields.map do |field_id|
      case field_id
      when 'key' then '1'
      when 'summary' then '2'
      when 'description' then '3'
      else '1'
      end
    end
  end

  def initialize_table(col_defs)
    table = "[cols=\"#{col_defs.join(',')}\", options=\"header,autowidth\"]\n"
    table << "|===\n"
    table
  end

  def build_header_row(fields, field_names)
    fields.map do |field_id|
      if field_id.start_with?('customfield_')
        field_names[field_id] || field_id.capitalize
      else
        field_id.capitalize
      end
    end
  end

  def build_table_row(issue, fields, base_url)
    row_values = []
    
    fields.each do |field|
      if field == 'key'
        row_values << format_key_field(issue['key'], base_url)
      elsif field == 'status' && issue['fields'] && issue['fields'][field]
        row_values << format_status_field(issue['fields'][field])
      else
        field_value = issue['fields'] ? issue['fields'][field] : nil
        formatted = format_custom_field(field_value)
        
        if formatted.include?("\n") && formatted.include?("- ")
          # Use AsciiDoc cell specifier for rich content
          row_values << "a|\n#{formatted}"
        else
          row_values << formatted
        end
      end
    end
    
    # Build the row with proper cell handling
    row_values.each_with_index.map do |value, idx|
      if value.start_with?("a|")
        # For AsciiDoc cells, don't add the pipe prefix
        if idx == 0
          value  # First cell already has the prefix
        else
          "\n#{value}"  # Add a newline before other cells with AsciiDoc content
        end
      else
        if idx == 0
          "| #{value}"
        else
          " | #{value}"
        end
      end
    end.join("")
  end

  def format_key_field(key, base_url)
    url = "#{base_url}/browse/#{key}"
    "link:#{url}[#{key}]"
  end

  def format_string_field(content)
    content = process_wiki_links(content)
    
    # Check if content contains bullet points or multiple paragraphs
    has_complex_content = content.match?(/^[ \t]*[*\-][ \t]+/m) || content.match?(/\n\s*\n/)
    
    if has_complex_content
      format_complex_content(content)
    else
      format_simple_content(content)
    end
  end

  def process_wiki_links(content)
    # Convert Jira/Confluence wiki link markup to AsciiDoc links
    content = content.gsub(/\[(https?:\/\/[^\]]+?)\|([^\]|]+?)(?:\|[^\]]+?)?\]/) do |match|
      parts = match[1..-2].split('|')  # Remove brackets and split by pipe
      
      if parts.length >= 2
        url = parts[0]
        text = parts[1]
        "link:#{url}[#{text}]"
      else
        # If for some reason we can't parse it properly, leave it as is
        match
      end
    end

    # Also handle the case where a URL is in square brackets without a pipe
    content.gsub(/\[(https?:\/\/[^\]\|]+)\]/) do |match|
      url = $1
      "link:#{url}[#{url}]"
    end
  end

  def format_complex_content(content)
    lines = content.split(/[\r\n]+/)
    
    # Process each line
    processed_lines = []
    last_line_was_bold_title = false
    
    lines.each do |line|
      line = line.rstrip
      
      is_bold_title = line.match?(/^\s*\*[^*]+:\*\s*$/)
      
      # Add empty line before new bold section titles (except the first one)
      if is_bold_title && !processed_lines.empty? && !last_line_was_bold_title
        processed_lines << ""
      end
      
      # Process the line based on its type
      if line.strip.start_with?('*') && line.strip.match?(/^\*\s+/)
        process_bullet_point(line, processed_lines)
      else
        processed_lines << process_regular_line(line)
      end
      
      last_line_was_bold_title = is_bold_title
    end
    
    content = processed_lines.join("\n")
    
    # Escape pipes to avoid breaking table
    content.gsub(/\|/, '\\|')
  end

  def process_bullet_point(line, processed_lines)
    # Add empty line before bullet points for proper list formatting
    if !processed_lines.empty? && !processed_lines.last.strip.empty? && 
       !processed_lines.last.strip.start_with?('-')
      processed_lines << ""
    end
    
    # Convert Jira bullet (* item) to AsciiDoc bullet (- item)
    indentation = line[/^\s*/]
    bullet_content = line.sub(/^\s*\*\s+/, '')
    
    # Process bold and italic in the bullet content
    bullet_content = bullet_content
      .gsub(/\*([^*\r\n]+)\*/, '*\1*')  # Bold
      .gsub(/_([^_\n]+)_/, '_\1_')      # Italic
    
    processed_lines << "#{indentation}- #{bullet_content}"
  end

  def process_regular_line(line)
    # Process bold text
    line = line.gsub(/\*([^*\r\n]+)\*/, '*\1*')
    
    # Convert italic syntax
    line.gsub(/_([^_\n]+)_/, '_\1_')
  end

  def format_simple_content(content)
    # For normal content without bullets, replace newlines with spaces
    content = content.gsub(/[\r\n]+/, " ")
    
    # Handle Jira markup for bold and italic
    content = content
      .gsub(/\*([^*\n]+)\*/, '*\1*')
      .gsub(/_([^_\n]+)_/, '_\1_')
    
    # Escape pipe characters
    content.gsub(/\|/, "\\|")
  end

  def print_field_information_for_debugging(issues, field_result)
    # Use class variable instead of instance variable
    @@field_info_printed ||= false
    return if @@field_info_printed
    
    if !field_result[:success]
      warn ">>> WARN: Unable to fetch field metadata: #{field_result[:error]}"
      return
    end
    
    # Create a mapping of field ID to field name
    field_map = {}
    field_result[:fields].each do |field|
      field_map[field['id']] = {
        name: field['name'],
        type: field['schema'] ? field['schema']['type'] : 'unknown',
        custom: field['custom'],
        description: field['description']
      }
    end
    
    # Collect fields that appear in the sample data
    used_fields = {}
    if !issues.empty?
      sample_issue = issues.first
      sample_issue['fields'].each_key do |field_id|
        used_fields[field_id] = true
      end
    end
    
    puts ">>> JIRA FIELD REFERENCE:"
    puts ">>> ====================="
    puts ">>> Custom Fields:"
    puts ">>> -------------"
    
    field_map.each do |field_id, info|
      next unless info[:custom]
      used = used_fields[field_id] ? " (PRESENT IN RESULTS)" : ""
      puts sprintf(">>> %-25s = %-30s [%s]%s", field_id, "\"#{info[:name]}\"", info[:type], used)
      puts sprintf(">>>    Description: %s", info[:description]) if info[:description]
    end
    
    puts ">>> "
    puts ">>> Standard Fields:"
    puts ">>> ---------------"
    field_map.each do |field_id, info|
      next if info[:custom]
      used = used_fields[field_id] ? " (PRESENT IN RESULTS)" : ""
      puts sprintf(">>> %-25s = %-30s [%s]%s", field_id, "\"#{info[:name]}\"", info[:type], used)
    end
    
    puts ">>> "
    puts ">>> USAGE EXAMPLE: jiraIssuesTable:[project = DEMO,fields=key,summary,status,customfield_10984]"
    puts ">>> =============="
    
    @@field_info_printed = true
  end
end

Asciidoctor::Extensions.register do
  inline_macro JiraInlineMacro
  inline_macro AtlasMentionInlineMacro
  block_macro JiraIssuesTableBlockMacro
end