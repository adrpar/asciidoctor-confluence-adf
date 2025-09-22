module AdfLogger
  @external_logger = nil

  class << self
    def use(logger)
      @external_logger = logger
    end

    def effective_logger
      return @external_logger if @external_logger
      if defined?(Asciidoctor::LoggerManager)
        Asciidoctor::LoggerManager.logger
      else
        nil
      end
    end

    def fatal(message)
      if (log = effective_logger)
        log.fatal message
      else
        Kernel.warn ">>> FATAL: #{message}"
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
