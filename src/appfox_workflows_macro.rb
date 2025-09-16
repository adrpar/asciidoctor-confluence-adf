require 'asciidoctor'
require 'asciidoctor/extensions'

require_relative 'adf_logger'

class AppfoxWorkflowMetadataInlineMacro < Asciidoctor::Extensions::InlineMacroProcessor
  use_dsl

  named :appfoxWorkflowMetadata
  name_positional_attributes 'text'

  # Default values for macro parameters
  DEFAULT_TITLE = "Workflows Metadata"
  DEFAULT_ICON_URL = "https://ac-cloud.com/workflows/images/logo.png"
  DEFAULT_SCHEMA_VERSION = "1"

  # Supported keywords mapping
  KEYWORDS = {
    "approvers" => "Approvers for Current Status",
    "versiondesc" => "Current Official Version Description",
    "version" => "Current Official Version",
    "expiry" => "Expiry Date",
    "transition" => "Transition Date",
    "pageid" => "Unique Page ID",
    "status" => "Workflow Status"
  }

  def process parent, target, attrs
    raise ArgumentError, "Target cannot be nil" if target.nil?
    if KEYWORDS.key?(target.downcase)
      text = KEYWORDS[target.downcase]
    else
      AdfLogger.warn "Unknown appfoxWorkflowMetadata keyword '#{target}'."
      return create_inline parent, :quoted, "appfoxWorkflowMetadata:#{target}[]", type: :unquoted
    end

    # Use document backend (available during parse) instead of converter which may not be initialized yet
    if parent.document.backend == 'adf'
      macro_params = {
        "data" => { "value" => text }
      }

      indexed_macro_params = {
        "text" => text,
        "type" => 'text'
      }

      extension_hash = {
        "type" => "inlineExtension",
        "attrs" => {
          "extensionType" => "com.atlassian.confluence.macro.core",
          "extensionKey" => "metadata-macro",
          "parameters" => {
            "macroParams" => macro_params,
            "macroMetadata" => {
              "schemaVersion" => { "value" => DEFAULT_SCHEMA_VERSION },
              "indexedMacroParams" => indexed_macro_params,
              "placeholder" => [
                {
                  "type" => "icon",
                  "data" => { "url" => DEFAULT_ICON_URL }
                }
              ],
              "title" => DEFAULT_TITLE
            }
          }
        }
      }
      return create_inline parent, :quoted, extension_hash.to_json, type: :unquoted
    else
      return create_inline parent, :quoted, "appfoxWorkflowMetadata:#{target}[]", type: :unquoted
    end
  end
end

class AppfoxWorkflowApproversTableInlineMacro < Asciidoctor::Extensions::InlineMacroProcessor
  use_dsl

  named :workflowApproval
  name_positional_attributes 'text'

  DEFAULT_TITLE = "Workflows Approvers Metadata"
  DEFAULT_ICON_URL = "https://ac-cloud.com/workflows/images/logo.png"
  DEFAULT_SCHEMA_VERSION = "1"
  DEFAULT_LAYOUT = "default"

  # Supported options and their corresponding ADF values
  OPTIONS = {
    "all" => nil, # All approvers for current workflow (no data param)
    "latest" => "Latest Approvals for Current Workflow"
  }

  def process parent, target, attrs
    option = (target || '').downcase
    unless OPTIONS.key?(option)
      AdfLogger.warn "Unknown workflowApproval option '#{target}'."
      return create_inline parent, :quoted, "workflowApproval:#{target}[]", type: :unquoted
    end

    macro_params = {}
    indexed_macro_params = nil
    if OPTIONS[option]
      value = OPTIONS[option]
      macro_params['data'] = { 'value' => value } if value
      indexed_macro_params = { 'text' => value, 'type' => 'text' } if value
    end

    if parent.document.backend == 'adf'
      metadata = {
        'schemaVersion' => { 'value' => DEFAULT_SCHEMA_VERSION },
        'placeholder' => [ { 'type' => 'icon', 'data' => { 'url' => DEFAULT_ICON_URL } } ],
        'title' => DEFAULT_TITLE
      }
      metadata['indexedMacroParams'] = indexed_macro_params if indexed_macro_params
      extension_json = {
        'type' => 'extension',
        'attrs' => {
          'layout' => DEFAULT_LAYOUT,
          'extensionType' => 'com.atlassian.confluence.macro.core',
          'extensionKey' => 'approvers-macro',
          'parameters' => {
            'macroParams' => macro_params,
            'macroMetadata' => metadata
          }
        }
      }.to_json
      create_inline parent, :quoted, extension_json, type: :unquoted
    else
      create_inline parent, :quoted, "workflowApproval:#{target}[]", type: :unquoted
    end
  end
end

class AppfoxWorkflowChangeTableInlineMacro < Asciidoctor::Extensions::InlineMacroProcessor
  use_dsl

  named :workflowChangeTable
  name_positional_attributes 'text'

  DEFAULT_TITLE = "Workflows Document Control Table"
  DEFAULT_ICON_URL = "https://ac-cloud.com/workflows/images/logo.png"
  DEFAULT_SCHEMA_VERSION = "1"
  DEFAULT_LAYOUT = "default"

  def process parent, target, attrs
    if parent.document.backend == 'adf'
      extension_json = {
        'type' => 'extension',
        'attrs' => {
          'layout' => DEFAULT_LAYOUT,
          'extensionType' => 'com.atlassian.confluence.macro.core',
          'extensionKey' => 'document-control-table-macro',
          'parameters' => {
            'macroParams' => {},
            'macroMetadata' => {
              'schemaVersion' => { 'value' => DEFAULT_SCHEMA_VERSION },
              'placeholder' => [ { 'type' => 'icon', 'data' => { 'url' => DEFAULT_ICON_URL } } ],
              'title' => DEFAULT_TITLE
            }
          }
        }
      }.to_json
      create_inline parent, :quoted, extension_json, type: :unquoted
    else
      create_inline parent, :quoted, "workflowChangeTable:#{target}[]", type: :unquoted
    end
  end
end

Asciidoctor::Extensions.register do
  inline_macro AppfoxWorkflowMetadataInlineMacro
  inline_macro AppfoxWorkflowApproversTableInlineMacro
  inline_macro AppfoxWorkflowChangeTableInlineMacro
end