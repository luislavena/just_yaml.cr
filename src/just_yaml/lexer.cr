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
      when '\''
        scan_single_quoted_scalar
      when '"'
        scan_double_quoted_scalar
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

    private def scan_single_quoted_scalar : Token
      loc = current_location
      advance # consume opening '

      value = String.build do |str|
        loop do
          if at_end?
            raise LexerError.new("Unterminated single-quoted string", loc)
          end

          char = current_char
          if char == '\''
            advance # consume the quote
            if current_char == '\''
              # Escaped single quote ('') becomes literal '
              str << advance
            else
              # End of string
              break
            end
          else
            str << advance
          end
        end
      end

      Token.new(TokenType::Scalar, value, loc)
    end

    private def scan_double_quoted_scalar : Token
      loc = current_location
      advance # consume opening "

      value = String.build do |str|
        loop do
          if at_end?
            raise LexerError.new("Unterminated double-quoted string", loc)
          end

          char = current_char
          if char == '"'
            advance # consume closing "
            break
          elsif char == '\\'
            str << scan_escape_sequence(loc)
          else
            str << advance
          end
        end
      end

      Token.new(TokenType::Scalar, value, loc)
    end

    private def scan_escape_sequence(string_start_loc : Location) : Char | String
      escape_loc = current_location
      advance # consume backslash

      if at_end?
        raise LexerError.new("Unterminated escape sequence", escape_loc)
      end

      char = advance
      case char
      when '0'  then '\0'
      when 'a'  then '\a'
      when 'b'  then '\b'
      when 't'  then '\t'
      when '\t' then '\t' # literal tab after backslash
      when 'n'  then '\n'
      when 'v'  then '\v'
      when 'f'  then '\f'
      when 'r'  then '\r'
      when 'e'  then '\e'
      when ' '  then ' '
      when '"'  then '"'
      when '/'  then '/'
      when '\\' then '\\'
      when 'N'  then '\u0085' # NEL (Next Line)
      when '_'  then '\u00A0' # NBSP (Non-Breaking Space)
      when 'L'  then '\u2028' # LS (Line Separator)
      when 'P'  then '\u2029' # PS (Paragraph Separator)
      when 'x'
        # \xNN - 2 hex digits
        scan_hex_escape(2, escape_loc)
      when 'u'
        # \uNNNN - 4 hex digits
        scan_hex_escape(4, escape_loc)
      when 'U'
        # \UNNNNNNNN - 8 hex digits
        scan_hex_escape(8, escape_loc)
      else
        raise LexerError.new("Invalid escape sequence '\\#{char}'", escape_loc)
      end
    end

    private def scan_hex_escape(num_digits : Int32, escape_loc : Location) : Char | String
      hex_str = String.build do |str|
        num_digits.times do
          if at_end?
            raise LexerError.new("Incomplete hex escape sequence, expected #{num_digits} hex digits", escape_loc)
          end
          char = current_char
          unless char.hex?
            raise LexerError.new("Invalid hex digit '#{char}' in escape sequence", escape_loc)
          end
          str << advance
        end
      end

      codepoint = hex_str.to_i(16)

      # Validate Unicode codepoint range
      if codepoint > 0x10FFFF
        raise LexerError.new("Unicode codepoint out of range: U+#{hex_str.upcase}", escape_loc)
      end

      # Handle surrogate pairs (invalid in UTF-8)
      if codepoint >= 0xD800 && codepoint <= 0xDFFF
        raise LexerError.new("Invalid Unicode surrogate codepoint: U+#{hex_str.upcase}", escape_loc)
      end

      codepoint.chr
    end

    private def scalar_terminator?(char : Char) : Bool
      char == '\n' || char == ':'
    end
  end
end
