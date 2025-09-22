require 'minitest/autorun'
require 'open3'

# Integration test verifying that Asciidoctor's --failure-level works with our extensions
class FailureLevelIntegrationTest < Minitest::Test
  ASCIIDOCTOR_CMD = ENV['ASCIIDOCTOR_CMD'] || 'asciidoctor'
  ROOT = File.expand_path('..', __dir__)
  EXT = File.join(ROOT, 'test', 'fixtures', 'logging_extension.rb')

  SIMPLE_DOC = File.join(ROOT, 'test', 'fixtures', 'simple_doc.adoc')

  def setup
    unless File.exist?(SIMPLE_DOC)
      File.write(SIMPLE_DOC, "= Test\n\nParagraph.")
    end
  end

  def run_asciidoctor(args)
    cmd = [ASCIIDOCTOR_CMD, '--trace', *args]
    stdout, stderr, status = Open3.capture3({ 'RUBYOPT' => nil }, *cmd)
    [stdout, stderr, status]
  end

  def test_failure_level_warn_trips_on_warn
    _o, err, status = run_asciidoctor(['--failure-level=WARN', '-r', EXT, '-a', 'log-test-level=warn', SIMPLE_DOC])
    assert_match(/Intentional test warn/, err)
    refute status.success?, 'Expected process to fail (non-zero exit) on WARN'
  end

  def test_failure_level_error_does_not_trip_on_warn
    _o, err, status = run_asciidoctor(['--failure-level=ERROR', '-r', EXT, '-a', 'log-test-level=warn', SIMPLE_DOC])
    assert_match(/Intentional test warn/, err)
    assert status.success?, 'Expected process to succeed when failure-level is ERROR but only WARN emitted'
  end

  def test_failure_level_error_trips_on_error
    _o, err, status = run_asciidoctor(['--failure-level=ERROR', '-r', EXT, '-a', 'log-test-level=error', SIMPLE_DOC])
    assert_match(/Intentional test error/, err)
    refute status.success?, 'Expected process to fail (non-zero exit) on ERROR'
  end
end
