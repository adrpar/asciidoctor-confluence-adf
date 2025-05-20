require 'minitest/autorun'
require 'asciidoctor'
require_relative '../src/appfox_workflows_macro'
require_relative '../src/adf_converter'

class AppfoxWorkflowMetadataInlineMacroTest < Minitest::Test
  def adoc_with_macros
    <<~ADOC
      appfoxWorkflowMetadata:approvers[]
      appfoxWorkflowMetadata:versiondesc[]
      appfoxWorkflowMetadata:version[]
      appfoxWorkflowMetadata:expiry[]
      appfoxWorkflowMetadata:transition[]
      appfoxWorkflowMetadata:pageid[]
      appfoxWorkflowMetadata:status[]
    ADOC
  end

  def test_macro_with_adf_backend
    doc = Asciidoctor.load(adoc_with_macros, safe: :safe, backend: 'adf', extensions: proc { inline_macro AppfoxWorkflowMetadataInlineMacro })
    result = doc.converter.convert(doc, 'document')

    assert_includes result, '"type":"inlineExtension"'
    assert_includes result, '"extensionKey":"metadata-macro"'
    assert_includes result, 'Approvers for Current Status'
    assert_includes result, 'Current Official Version Description'
    assert_includes result, 'Current Official Version'
    assert_includes result, 'Expiry Date'
    assert_includes result, 'Transition Date'
    assert_includes result, 'Unique Page ID'
    assert_includes result, 'Workflow Status'
  end

  def test_macro_with_html_backend
    doc = Asciidoctor.load('appfoxWorkflowMetadata:approvers[]', safe: :safe, backend: 'html5', extensions: proc { inline_macro AppfoxWorkflowMetadataInlineMacro })
    result = doc.convert
    assert_includes result, 'appfoxWorkflowMetadata:approvers[]'
  end

  def test_warn_and_fallback_on_unknown_keyword
    out, err = capture_io do
      doc = Asciidoctor.load('appfoxWorkflowMetadata:unknownkey[]', safe: :safe, backend: 'adf', extensions: proc { inline_macro AppfoxWorkflowMetadataInlineMacro })
      result = doc.converter.convert(doc, 'document')
      assert_includes result, 'appfoxWorkflowMetadata:unknownkey[]'
    end

    assert_includes err, 'WARN: Unknown appfoxWorkflowMetadata keyword'
  end

  def test_macro_params_and_indexed_macro_params
    doc = Asciidoctor.load('appfoxWorkflowMetadata:status[]', safe: :safe, backend: 'adf', extensions: proc { inline_macro AppfoxWorkflowMetadataInlineMacro })
    result = doc.converter.convert(doc, 'document')

    assert_includes result, '"text":"Workflow Status"'
    assert_includes result, '"type":"text"'
    assert_includes result, '"title":"Workflows Metadata"'
    assert_includes result, '"url":"https://ac-cloud.com/workflows/images/logo.png"'
  end
end

class AppfoxWorkflowApproversTableInlineMacroTest < Minitest::Test
  def test_workflow_approval_all_adf
    doc = Asciidoctor.load('workflowApproval:all[]', safe: :safe, backend: 'adf', extensions: proc { inline_macro AppfoxWorkflowApproversTableInlineMacro })
    result = doc.converter.convert(doc, 'document')
    assert_includes result, '"type":"extension"'
    assert_includes result, '"extensionKey":"approvers-macro"'
    assert_includes result, '"title":"Workflows Approvers Metadata"'
    refute_includes result, 'Latest Approvals for Current Workflow'
    # Should not have indexedMacroParams for "all"
    refute_includes result, '"indexedMacroParams"'
  end

  def test_workflow_approval_latest_adf
    doc = Asciidoctor.load('workflowApproval:latest[]', safe: :safe, backend: 'adf', extensions: proc { inline_macro AppfoxWorkflowApproversTableInlineMacro })
    result = doc.converter.convert(doc, 'document')
    assert_includes result, '"type":"extension"'
    assert_includes result, '"extensionKey":"approvers-macro"'
    assert_includes result, '"title":"Workflows Approvers Metadata"'
    assert_includes result, 'Latest Approvals for Current Workflow'
    assert_includes result, '"indexedMacroParams"'
    assert_includes result, '"text":"Latest Approvals for Current Workflow"'
  end

  def test_workflow_approval_html_backend
    doc = Asciidoctor.load('workflowApproval:all[]', safe: :safe, backend: 'html5', extensions: proc { inline_macro AppfoxWorkflowApproversTableInlineMacro })
    result = doc.convert
    assert_includes result, 'workflowApproval:all[]'
  end

  def test_workflow_approval_warn_and_fallback_on_unknown_option
    out, err = capture_io do
      doc = Asciidoctor.load('workflowApproval:unknown[]', safe: :safe, backend: 'adf', extensions: proc { inline_macro AppfoxWorkflowApproversTableInlineMacro })
      result = doc.converter.convert(doc, 'document')
      assert_includes result, 'workflowApproval:unknown[]'
    end
    assert_includes err, 'WARN: Unknown workflowApproval option'
  end
end

class AppfoxWorkflowChangeTableInlineMacroTest < Minitest::Test
  def test_workflow_change_table_adf
    doc = Asciidoctor.load('workflowChangeTable:all[]', safe: :safe, backend: 'adf', extensions: proc { inline_macro AppfoxWorkflowChangeTableInlineMacro })
    result = doc.converter.convert(doc, 'document')

    assert_includes result, '"type":"extension"'
    assert_includes result, '"extensionKey":"document-control-table-macro"'
    assert_includes result, '"title":"Workflows Document Control Table"'
    assert_includes result, '"layout":"default"'
    assert_includes result, '"schemaVersion":{"value":"1"}'
    assert_includes result, '"url":"https://ac-cloud.com/workflows/images/logo.png"'
  end

  def test_workflow_change_table_html_backend
    doc = Asciidoctor.load('workflowChangeTable:all[]', safe: :safe, backend: 'html5', extensions: proc { inline_macro AppfoxWorkflowChangeTableInlineMacro })
    result = doc.convert
    assert_includes result, 'workflowChangeTable:all[]'
  end
end