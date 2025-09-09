# Unified logging helper for consistent output across environments
# Uses Asciidoctor logger when available; falls back to simple STDERR/STDOUT output.
module AdfLogger
  module_function

  def error(message)
    if defined?(Asciidoctor::LoggerManager)
      Asciidoctor::LoggerManager.logger.error message
    else
      Kernel.warn ">>> ERROR: #{message}"
    end
  end

  def warn(message)
    if defined?(Asciidoctor::LoggerManager)
      Asciidoctor::LoggerManager.logger.warn message
    else
      Kernel.warn ">>> WARN: #{message}"
    end
  end

  def info(message)
    if defined?(Asciidoctor::LoggerManager)
      Asciidoctor::LoggerManager.logger.info message
    else
      puts ">>> INFO: #{message}"
    end
  end

  def debug(message)
    if defined?(Asciidoctor::LoggerManager)
      Asciidoctor::LoggerManager.logger.debug message
    else
      puts ">>> DEBUG: #{message}"
    end
  end
end
