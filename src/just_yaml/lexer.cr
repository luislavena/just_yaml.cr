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
      when '#'
        scan_comment
      when '&'
        scan_anchor
      when '*'
        scan_alias
      when '!'
        scan_tag
      when '-'
        scan_document_start_or_sequence_entry
      when '.'
        scan_document_end_or_scalar
      when '%'
        scan_directive
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

    private def scan_document_start_or_sequence_entry : Token
      loc = current_location

      # Check if we're at column 1 (start of line) and might be ---
      if @column == 1 && peek_next_chars_are?('-', '-')
        # This is ---
        advance # first -
        advance # second -
        advance # third -
        Token.new(TokenType::DocumentStart, "---", loc)
      else
        # Single dash - could be sequence entry or part of a scalar
        advance # consume the first -

        if at_end? || current_char == ' ' || current_char == '\n' || current_char == '\t'
          Token.new(TokenType::SequenceEntry, "-", loc)
        else
          # It's part of a scalar (e.g., "-123" or "-word")
          # Continue reading the rest of the scalar
          value = String.build do |str|
            str << '-'
            while !at_end? && !scalar_terminator?(current_char)
              str << advance
            end
          end
          Token.new(TokenType::Scalar, value.strip, loc)
        end
      end
    end

    private def scan_document_end_or_scalar : Token
      loc = current_location

      # Check if we're at column 1 (start of line) and have ...
      if @column == 1 && peek_next_chars_are?('.', '.')
        # Read all three dots
        advance # first .
        advance # second .
        advance # third .

        # Document end must be followed by whitespace, newline, or EOF
        if at_end? || current_char == ' ' || current_char == '\t' || current_char == '\n'
          Token.new(TokenType::DocumentEnd, "...", loc)
        else
          # Not a valid document end, treat as scalar
          value = String.build do |str|
            str << "..."
            while !at_end? && !scalar_terminator?(current_char)
              str << advance
            end
          end
          Token.new(TokenType::Scalar, value.strip, loc)
        end
      else
        # Just a regular scalar starting with .
        scan_scalar
      end
    end

    private def scan_directive : Token
      loc = current_location

      # Directives must be at the start of a line
      if @column != 1
        return scan_scalar
      end

      advance # consume %

      value = String.build do |str|
        str << '%'
        while !at_end? && current_char != '\n'
          str << advance
        end
      end

      Token.new(TokenType::Directive, value.strip, loc)
    end

    # Check if next two characters (after current) match c1 and c2
    private def peek_next_chars_are?(c1 : Char, c2 : Char) : Bool
      return false unless @reader.has_next?

      # Save current position
      saved_pos = @reader.pos

      # Move to next char and check if it matches c1
      @reader.next_char
      unless @reader.current_char == c1
        @reader.pos = saved_pos
        return false
      end

      # Check if there's another char and if it matches c2
      unless @reader.has_next?
        @reader.pos = saved_pos
        return false
      end

      @reader.next_char
      result = @reader.current_char == c2

      # Restore position
      @reader.pos = saved_pos

      result
    end

    private def scalar_terminator?(char : Char) : Bool
      char == '\n' || char == ':'
    end

    private def scan_comment : Token
      loc = current_location
      advance # consume #

      value = String.build do |str|
        while !at_end? && current_char != '\n'
          str << advance
        end
      end

      Token.new(TokenType::Comment, value, loc)
    end

    private def scan_anchor : Token
      loc = current_location
      advance # consume &

      name = scan_anchor_alias_name(loc, "anchor")

      Token.new(TokenType::Anchor, name, loc)
    end

    private def scan_alias : Token
      loc = current_location
      advance # consume *

      name = scan_anchor_alias_name(loc, "alias")

      Token.new(TokenType::Alias, name, loc)
    end

    private def scan_anchor_alias_name(loc : Location, kind : String) : String
      if at_end? || !valid_anchor_alias_start?(current_char)
        raise LexerError.new("Invalid #{kind} name: must start with a letter or underscore", loc)
      end

      String.build do |str|
        while !at_end? && valid_anchor_alias_char?(current_char)
          str << advance
        end
      end
    end

    private def valid_anchor_alias_start?(char : Char) : Bool
      char.ascii_letter? || char == '_'
    end

    private def valid_anchor_alias_char?(char : Char) : Bool
      char.ascii_alphanumeric? || char == '-' || char == '_'
    end

    private def scan_tag : Token
      loc = current_location
      advance # consume first !

      value = String.build do |str|
        str << '!'

        if at_end? || tag_terminator?(current_char)
          # Just "!" - non-specific tag
        elsif current_char == '!'
          # Secondary tag handle: !!type
          str << advance
          while !at_end? && !tag_terminator?(current_char)
            str << advance
          end
        elsif current_char == '<'
          # Verbatim tag: !<uri>
          str << advance
          while !at_end? && current_char != '>'
            if current_char == '\n'
              raise LexerError.new("Unterminated verbatim tag", loc)
            end
            str << advance
          end
          if at_end?
            raise LexerError.new("Unterminated verbatim tag", loc)
          end
          str << advance # consume >
        else
          # Local tag (!type) or named tag handle (!prefix!suffix)
          while !at_end? && !tag_terminator?(current_char)
            str << advance
          end
        end
      end

      Token.new(TokenType::Tag, value, loc)
    end

    private def tag_terminator?(char : Char) : Bool
      char == ' ' || char == '\t' || char == '\n' || char == ':'
    end
  end
end
