# Unified logging helper for consistent output across environments
# Uses Asciidoctor logger when available; falls back to simple STDERR/STDOUT output.
module AdfLogger
  module_function

  # Map all logging through Asciidoctor::LoggerManager when available so that
  # the --failure-level CLI option is honored. Any use of Kernel.warn / puts
  # would bypass the Asciidoctor logger and therefore never trigger a non-zero
  # exit status. Extensions should only call these helpers.

  def error(message)
    if defined?(Asciidoctor::LoggerManager)
      Asciidoctor::LoggerManager.logger.error message
    else
      Kernel.warn ">>> ERROR: #{message}"
    end
  end

  def fatal(message)
    if defined?(Asciidoctor::LoggerManager)
      Asciidoctor::LoggerManager.logger.fatal message
    else
      Kernel.warn ">>> FATAL: #{message}"
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
