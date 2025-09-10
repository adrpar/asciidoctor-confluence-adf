require 'asciidoctor'
require 'asciidoctor/extensions'
require 'net/http'
require 'json'
require 'csv'

require_relative 'confluence_client'
require_relative 'adf_to_asciidoc'
require_relative 'adf_logger'
require_relative 'jira_support'

class JiraInlineMacro < Asciidoctor::Extensions::InlineMacroProcessor
  use_dsl

  named :jira
  name_positional_attributes 'text'

  def process parent, target, attrs
    base_url = parent.document.attr('jira-base-url') || ENV['JIRA_BASE_URL']
    if base_url.nil? || base_url.empty?
      AdfLogger.warn "No Jira base URL found, the Jira extension may not work as expected."
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
      confluence_base_url = parent.document.attr('confluence-base-url') || ENV['CONFLUENCE_BASE_URL']
      jira_base_url = parent.document.attr('jira-base-url') || confluence_base_url || ENV['JIRA_BASE_URL']
      api_token = parent.document.attr('confluence-api-token') || ENV['CONFLUENCE_API_TOKEN']
      user_email = parent.document.attr('confluence-user-email') || ENV['CONFLUENCE_USER_EMAIL']


      if confluence_base_url.nil? || api_token.nil? || user_email.nil?
        AdfLogger.warn "Missing Confluence API credentials for atlasMention macro."
        return { "type" => "text", "text" => "@#{name}" }.to_json
      end

      client = ConfluenceJiraClient.new(
        base_url: confluence_base_url,
        jira_base_url: jira_base_url,
        api_token: api_token,
        user_email: user_email
      )
      user = client.find_user_by_fullname(name)

      return user ? { "type" => "mention", "attrs" => { "id" => user["id"], "text" => "@#{user["displayName"]}" } }.to_json : "@#{name}"
    else
      "@#{name}"
    end
  end
end

class JiraIssuesTableBlockMacro < Asciidoctor::Extensions::BlockMacroProcessor
  use_dsl

  named :jiraIssuesTable
  name_positional_attributes 'jql'

  def initialize(*args)
    super
    @adf_converter = AdfToAsciidocConverter.new
  end

  def process(parent, target, attrs)
    return handle_invalid_attributes(parent, target, attrs) unless valid_attributes?(attrs)

    credentials = JiraCredentials.from_document(parent.document)
    return handle_missing_credentials(parent, target, attrs) unless credentials.valid?

    user_fields = parse_fields(attrs)
    jql = parse_jql(target, attrs)
    return handle_missing_jql(parent, target, attrs) if jql.nil? || jql.empty?

    client = create_jira_client(credentials.to_h)

    # Fetch field metadata before resolving user supplied field names
    field_result = client.get_jira_fields

    resolution = JiraFieldResolver.new(field_result).resolve(user_fields)
    resolved_fields = resolution.resolved
    unknown_fields = resolution.unknown
    if !unknown_fields.empty?
      print_field_information_for_debugging([], field_result)
      AdfLogger.error "Unknown Jira field name(s): #{unknown_fields.map { |f| '"' + f + '"' }.join(', ')}. Use an exact field name as shown above or the custom field id (e.g. customfield_12345)."
      return create_paragraph(parent, "jiraIssuesTable::['#{jql}', fields='#{attrs['fields']}']", {})
    end

    result = client.query_jira_issues(
      jql: jql,
      fields: resolved_fields
    )

    if api_query_successful?(result)
      table_content = build_table(result[:data]['issues'], resolved_fields, field_result, credentials.base_url)

      # Add bold title if specified
      if attrs['title']
        title_content = "**#{attrs['title']}**\n\n"
        table_content = title_content + table_content
      end

      parse_content parent, table_content, {}
    else
      handle_failed_api_query(parent, jql, attrs, result)
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
      if field_value.key?('type') && field_value['type'] == 'doc'
        converted = @adf_converter.convert(field_value).to_s
        # Strip leading/trailing blank lines to avoid empty first paragraph inside cell
        converted = converted.gsub(/^\n+/, '').gsub(/\n+\z/, '')
        converted = ensure_blank_line_before_lists(converted)
        "a|\n#{converted}"
      else
        format_hash_field(field_value)
      end
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
    valid_attrs = ['jql', 'fields', 'title']
    unknown_attrs = attrs.keys.reject { |k| valid_attrs.include?(k.to_s) || k.to_s.start_with?('_') || k.to_s.match?(/^\d+$/) }
    
    if unknown_attrs.empty?
      true
    else
      AdfLogger.warn "Unknown attributes for jiraIssuesTable macro: #{unknown_attrs.join(', ')}"
      false
    end
  end


  def handle_invalid_attributes(parent, target, attrs)
    # Attempt to recover JQL from positional attribute if provided
    jql = target.to_s.empty? ? (attrs['jql'] || attrs['1']) : target
    create_paragraph(parent, "jiraIssuesTable::['#{jql}', fields='INVALID ATTRIBUTES']", {})
  end

  def handle_missing_credentials(parent, target, attrs)
    AdfLogger.warn "Missing Jira API credentials for jiraIssuesTable macro."
    jql = target.to_s.empty? ? (attrs['jql'] || attrs['1']) : target
    create_paragraph(parent, "jiraIssuesTable::['#{jql}', fields='#{attrs['fields']}']", {})
  end

  def handle_missing_jql(parent, target, attrs)
    AdfLogger.warn "Missing JQL query for jiraIssuesTable macro."
    create_paragraph(parent, "jiraIssuesTable::['', fields='#{attrs['fields']}']", {})
  end

  def handle_failed_api_query(parent, target, attrs, result)
    AdfLogger.warn "Jira API query failed or returned no issues: #{result[:error] || 'Unknown error'}"
    create_paragraph(parent, "jiraIssuesTable::['#{target}', fields='#{attrs['fields']}']", {})
  end


  def parse_fields(attrs)
    raw = attrs['fields']
    return ['key', 'summary', 'status'] if raw.nil? || raw.strip.empty?

    # Allow single-quoted field tokens (including commas) by converting ONLY whole single-quoted tokens
    # bounded by start/end or commas, not isolated single-quoted words inside a double-quoted token.
    # Example (should NOT change inner quotes):
    #   key,Summary,"Complex, Field Name","Another 'Quoted' Field"  => unchanged
    # Example (should convert):
    #   key,Summary,'Complex, Field Name','Another ''Quoted'' Field'
    # We match (^|,) optional leading comma boundary, then the single-quoted token, ensuring next char is comma or end.
    normalized = raw.gsub(/(^|,)\s*'([^']*(?:''[^']*)*)'\s*(?=,|$)/) do
      prefix = Regexp.last_match(1)
      inner  = Regexp.last_match(2).gsub(/''/, "'") # unescape doubled single quotes
      # Re-wrap in double quotes, escaping embedded double quotes per CSV rules.
      %(#{prefix}"#{inner.gsub('"', '""')}")
    end

    fields = CSV.parse_line(normalized, col_sep: ',', quote_char: '"', skip_blanks: true) || []
    fields = fields.map { |field| field.is_a?(String) ? field.strip : field.to_s }.reject(&:empty?)
  end

  def parse_jql(target, attrs)
    return target if !target.to_s.empty?
    attrs['jql'] || attrs['1']
  end

  def create_jira_client(credentials_hash)
    ConfluenceJiraClient.new(
      base_url: credentials_hash[:confluence_base_url],
      jira_base_url: credentials_hash[:base_url],
      api_token: credentials_hash[:api_token],
      user_email: credentials_hash[:user_email]
    )
  end

  def api_query_successful?(result)
    result[:success] && result[:data] && result[:data]['issues']
  end

  def build_table(issues, fields, field_result, base_url)
    field_names = build_field_names_mapping(field_result)

    # Build the table structure
    col_defs = define_column_widths(fields)
    table = initialize_table(col_defs)
    
    # Add header row
    header_row = build_header_row(fields, field_names)
    table << "| " + header_row.join(" | ") + "\n"
    
    # Add data rows
    issues.each do |issue|
      table << build_table_row(issue, fields, base_url)
    end
    
    table << "|===\n"
    table
  end

  def build_field_names_mapping(field_result)
    field_names = {}
    
    if field_result && field_result[:success] && field_result[:fields]
      field_result[:fields].each do |field|
      # Trim trailing whitespace for stable display while keeping original ID association
      display_name = field['name']&.rstrip
      field_names[field['id']] = display_name
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
    # Collect cell renderings respecting block (a|) cells which must start at beginning of line
    rendered_cells = []
    fields.each do |field_id|
      field_value = issue.dig('fields', field_id)
      value = case field_id
              when 'key'
                format_key_field(issue['key'], base_url)
              when 'status'
                format_status_field(field_value)
              else
                format_custom_field(field_value)
              end

      if value.to_s.start_with?("a|\n")
        # Block cell: already includes a| and newline
        rendered_cells << value
      elsif value.to_s.start_with?("a|")
        # Edge case: a| with no immediate newline content; ensure newline
        rendered_cells << (value.end_with?("\n") ? value : value + "\n")
      else
        # Simple inline cell
        rendered_cells << "| #{value.to_s.gsub(/\|/, '\\|')}"
      end
    end

    # Join cells with newlines. Each cell already starts with its delimiter.
    rendered_cells.map { |c| c.end_with?("\n") ? c : c + "\n" }.join
  end

  def format_key_field(key, base_url)
    url = "#{base_url}/browse/#{key}"
    "link:#{url}[#{key}]"
  end

  def format_string_field(content)
    return "" if content.nil? || content.empty?
    
    content = process_wiki_links(content)
    
    # Use 'a|' for any multi-line content or content with list-like structures
    if content.include?("\n") || content.match?(/^[ \t]*[*\-][ \t]+/)
      "a|\n#{format_complex_content(content)}"
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
    lines = content.split(/\r?\n/)
    processed = []
    lines.each_with_index do |line, idx|
      if line.match?(/^[ \t]*\*[ \t]+/)
        # If previous non-empty line isn't blank and not a bullet, insert blank line for list start
        prev_non_blank = processed.reverse.find { |l| !l.strip.empty? }
        if prev_non_blank && !prev_non_blank.start_with?('* ')
          processed << ''
        end
        processed << line.sub(/^[ \t]*\*/, '*').sub(/\*[ ]+/, '* ')
      else
        processed << process_regular_line(line)
      end
    end
    ensure_blank_line_before_lists(processed.join("\n"))
  end

  def ensure_blank_line_before_lists(text)
    out_lines = []
    previous_non_blank = nil
    text.split(/\n/).each do |l|
      if l.start_with?('* ')
        if previous_non_blank && !previous_non_blank.start_with?('* ') && !out_lines.last.to_s.empty?
          out_lines << ''
        end
      end
      out_lines << l
      previous_non_blank = l unless l.strip.empty?
    end
    out_lines.join("\n")
  end

  def process_bullet_point(line, processed_lines)
    # Add empty line before bullet points for proper list formatting
    if !processed_lines.empty? && !processed_lines.last.empty? && 
       !processed_lines.last.match?(/^[ \t]*\*[ \t]/)
      processed_lines << ""
    end
    
    # Convert Jira bullet (* item) to AsciiDoc bullet
    indentation = line[/^\s*/]
    bullet_content = line.sub(/^[ \t]*\*[ \t]+/, '')
    
    # Process bold and italic in the bullet content
    bullet_content = process_regular_line(bullet_content)
    
    processed_lines << "#{indentation}* #{bullet_content}"
  end

  def process_regular_line(line)
    # Process bold text
    line = line.gsub(/\*([^\*\s][^\*]*[^\*\s]|[^\*])\*/, '*\1*')
    
    # Convert italic syntax
    line.gsub(/_([^\s_][^_]*[^\s_]|[^\s_])_/, '_\1_')
  end

  def format_simple_content(content)
    # For normal content without bullets, replace newlines with spaces
    content = content.gsub(/[\r\n]+/, " ")
    
    # Handle Jira markup for bold and italic
    content = process_regular_line(content)
    
    # Escape pipe characters
    content.gsub(/\|/, "\\|")
  end

  def print_field_information_for_debugging(issues, field_result)
    # Use class variable instead of instance variable
    @@field_info_printed ||= false
    return if @@field_info_printed
    
    if !field_result[:success]
      AdfLogger.warn "Unable to fetch field metadata: #{field_result[:error]}"
      return
    end
    
    # Create a mapping of field ID to field name
    field_map = {}
    field_result[:fields].each do |field|
      trimmed_name = field['name']&.rstrip
      field_map[field['id']] = {
        name: trimmed_name,
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
    
    AdfLogger.info "JIRA FIELD REFERENCE:"
    AdfLogger.info "====================="
    AdfLogger.info "Custom Fields:"
    AdfLogger.info "-------------"
    
    field_map.each do |field_id, info|
      next unless info[:custom]
      used = used_fields[field_id] ? " (PRESENT IN RESULTS)" : ""
      AdfLogger.info sprintf("%-25s = %-30s [%s]%s", field_id, "\"#{info[:name]}\"", info[:type], used)
      AdfLogger.info sprintf("   Description: %s", info[:description]) if info[:description]
    end
    
    AdfLogger.info ""
    AdfLogger.info "Standard Fields:"
    AdfLogger.info "---------------"
    field_map.each do |field_id, info|
      next if info[:custom]
      used = used_fields[field_id] ? " (PRESENT IN RESULTS)" : ""
      AdfLogger.info sprintf("%-25s = %-30s [%s]%s", field_id, "\"#{info[:name]}\"", info[:type], used)
    end
    
    AdfLogger.info ""
    AdfLogger.info "USAGE EXAMPLE: jiraIssuesTable::['project = DEMO', fields='key,summary,status,customfield_10984']"
    AdfLogger.info "============="
    
    @@field_info_printed = true
  end

  # field resolution moved to JiraFieldResolver

end

Asciidoctor::Extensions.register do
  inline_macro JiraInlineMacro
  inline_macro AtlasMentionInlineMacro
  block_macro JiraIssuesTableBlockMacro
end