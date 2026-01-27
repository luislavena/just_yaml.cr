module JustYAML
  class Error < Exception
    getter location : Location?

    def initialize(message : String, @location : Location? = nil)
      if @location
        super("#{message} at #{@location}")
      else
        super(message)
      end
    end
  end

  class LexerError < Error; end

  class ParseError < Error; end

  class ResolveError < Error; end
end
