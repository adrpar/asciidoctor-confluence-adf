require 'asciidoctor'
require 'asciidoctor/extensions'

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
      warn ">>> WARN: Unknown appfoxWorkflowMetadata keyword '#{target}'."
      text = nil
    end

    if parent.document.converter && parent.document.converter.backend == 'adf' && text
      macro_params = {
        "data" => { "value" => text }
      }

      indexed_macro_params = {
        "text" => text,
        "type" => 'text'
      }

      {
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
      }.to_json
    else
      "appfoxWorkflowMetadata:#{target}[]"
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
      warn ">>> WARN: Unknown workflowApproval option '#{target}'."
      return "workflowApproval:#{target}[]"
    end

    macro_params = { }
    indexed_macro_params = nil

    if OPTIONS[option]
      macro_params["data"] = { "value" => OPTIONS[option] }
      indexed_macro_params = {
        "text" => OPTIONS[option],
        "type" => "text"
      }
    end

    if parent.document.converter && parent.document.converter.backend == 'adf'
      extension_attrs = {
        "layout" => DEFAULT_LAYOUT,
        "extensionType" => "com.atlassian.confluence.macro.core",
        "extensionKey" => "approvers-macro",
        "parameters" => {
          "macroParams" => macro_params,
          "macroMetadata" => {
            "schemaVersion" => { "value" => DEFAULT_SCHEMA_VERSION },
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
      # Only add indexedMacroParams if present
      if indexed_macro_params
        extension_attrs["parameters"]["macroMetadata"]["indexedMacroParams"] = indexed_macro_params
      end

      {
        "type" => "extension",
        "attrs" => extension_attrs
      }.to_json
    else
      "workflowApproval:#{target}[]"
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
    if parent.document.converter && parent.document.converter.backend == 'adf'
      extension_attrs = {
        "layout" => DEFAULT_LAYOUT,
        "extensionType" => "com.atlassian.confluence.macro.core",
        "extensionKey" => "document-control-table-macro",
        "parameters" => {
          "macroParams" => { },
          "macroMetadata" => {
            "schemaVersion" => { "value" => DEFAULT_SCHEMA_VERSION },
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

      {
        "type" => "extension",
        "attrs" => extension_attrs
      }.to_json
    else
      "workflowChangeTable:#{target}[]"
    end
  end
end

Asciidoctor::Extensions.register do
  inline_macro AppfoxWorkflowMetadataInlineMacro
  inline_macro AppfoxWorkflowApproversTableInlineMacro
  inline_macro AppfoxWorkflowChangeTableInlineMacro
end