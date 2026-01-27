module JustYAML
  class Lexer
    @reader : Char::Reader
    @line : Int32 = 1
    @column : Int32 = 1
    @started : Bool = false
    @finished : Bool = false

    def initialize(input : String)
      @reader = Char::Reader.new(input)
    end

    def next_token : Token
      unless @started
        @started = true
        return Token.new(TokenType::StreamStart, "", current_location)
      end

      skip_whitespace

      if at_end?
        return stream_end_token
      end

      case current_char
      when '\n'
        scan_newline
      when ':'
        scan_value_indicator
      else
        scan_scalar
      end
    end

    private def current_char : Char
      @reader.current_char
    end

    private def peek_char : Char
      @reader.peek_next_char
    end

    private def at_end? : Bool
      !@reader.has_next? && current_char == '\0'
    end

    private def advance : Char
      char = current_char
      @reader.next_char
      if char == '\n'
        @line += 1
        @column = 1
      else
        @column += 1
      end
      char
    end

    private def current_location : Location
      Location.new(@line, @column)
    end

    private def skip_whitespace : Nil
      while current_char == ' ' || current_char == '\t'
        advance
      end
    end

    private def stream_end_token : Token
      if @finished
        raise LexerError.new("Unexpected read past end of stream", current_location)
      end
      @finished = true
      Token.new(TokenType::StreamEnd, "", current_location)
    end

    private def scan_newline : Token
      loc = current_location
      advance
      skip_whitespace
      Token.new(TokenType::Newline, "", loc)
    end

    private def scan_value_indicator : Token
      loc = current_location
      advance
      Token.new(TokenType::ValueIndicator, ":", loc)
    end

    private def scan_scalar : Token
      loc = current_location
      value = String.build do |str|
        while !at_end? && !scalar_terminator?(current_char)
          str << advance
        end
      end
      Token.new(TokenType::Scalar, value.strip, loc)
    end

    private def scalar_terminator?(char : Char) : Bool
      char == '\n' || char == ':'
    end
  end
end
