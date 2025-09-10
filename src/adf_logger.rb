# Unified logging helper for consistent output across environments
# Uses Asciidoctor logger when available; falls back to simple STDERR/STDOUT output.
module AdfLogger
  @external_logger = nil

  class << self
    # Allow an external logger (e.g., Asciidoctor::LoggerManager.logger or any Logger-like object) to be injected.
    def use(logger)
      @external_logger = logger
    end

    # Return current effective logger (external or nil)
    def effective_logger
      return @external_logger if @external_logger
      if defined?(Asciidoctor::LoggerManager)
        Asciidoctor::LoggerManager.logger
      else
        nil
      end
    end

    def error(message)
      if (log = effective_logger)
        log.error message
      else
        Kernel.warn ">>> ERROR: #{message}"
      end
    end

    def warn(message)
      if (log = effective_logger)
        log.warn message
      else
        Kernel.warn ">>> WARN: #{message}"
      end
    end

    def info(message)
      if (log = effective_logger)
        log.info message
      else
        puts ">>> INFO: #{message}"
      end
    end

    def debug(message)
      if (log = effective_logger)
        log.debug message
      else
        puts ">>> DEBUG: #{message}"
      end
    end

    # Provide a lightweight adapter responding to :debug/:info/:warn used by existing modules
    def adapter
      @adapter ||= Module.new do
        extend self
        def debug(msg); AdfLogger.debug(msg); end
        def info(msg); AdfLogger.info(msg); end
        def warn(msg); AdfLogger.warn(msg); end
      end
    end
  end
end
