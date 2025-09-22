require 'asciidoctor'
require_relative '../../src/adf_logger'

# Test extension emitting a log at a chosen level (default warn) using the
# unified AdfLogger so failure-level behavior matches production extensions.
# Levels supported: fatal, error, warn, info, debug.
Asciidoctor::Extensions.register do
  treeprocessor do
    process do |doc|
      level = (doc.attr 'log-test-level', 'warn').downcase
      message = "Intentional test #{level} (failure-level test)"
      case level
      when 'fatal'
        AdfLogger.fatal message
      when 'error'
        AdfLogger.error message
      when 'warn'
        AdfLogger.warn message
      when 'debug'
        AdfLogger.debug message
      else
        AdfLogger.info message
      end
      nil
    end
  end
end
