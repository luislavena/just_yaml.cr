module JustYAML
  class Lexer
    @reader : Char::Reader
    @line : Int32 = 1
    @column : Int32 = 1
    @started : Bool = false
    @finished : Bool = false
    @flow_level : Int32 = 0                   # Track nesting level of flow collections
    @whitespace_before_current : Bool = false # Track if current position was preceded by whitespace

    def initialize(input : String)
      @reader = Char::Reader.new(input)
    end

    def next_token : Token
      unless @started
        @started = true
        return Token.new(TokenType::StreamStart, "", current_location)
      end

      # Track if whitespace was skipped (needed for comment detection)
      # Also track if we started at column 1 (beginning of line)
      at_line_start = @column == 1
      whitespace_skipped = skip_whitespace
      # If we skipped whitespace here, reset the flag (it will be set again if needed)
      if whitespace_skipped
        @whitespace_before_current = false
      end

      if at_end?
        return stream_end_token
      end

      # Tab at start of indentation (column 1) is invalid for block indicators
      # But tabs before flow indicators ({, [) or plain scalar content are allowed
      if @column == 1 && current_char == '\t' && @flow_level == 0
        # Skip the tab(s) and check what follows
        tab_loc = current_location
        while current_char == '\t'
          advance
        end
        # Tab is invalid if followed by block indicators (-, ?, :)
        # Tab is valid if followed by: flow indicators, newline, EOF, or scalar content
        if current_char == '-' || current_char == '?' || current_char == ':'
          raise LexerError.new("Tab character cannot be used for indentation", tab_loc)
        end
        # Check if this looks like a mapping key (identifier followed by :)
        # That would mean tabs are being used for indentation in a mapping
        if !at_end? && current_char != '\n' && current_char != '[' && current_char != '{'
          # Look ahead to see if this is a mapping key
          saved_pos = @reader.pos
          saved_line = @line
          saved_col = @column
          # Skip to potential colon
          while !at_end? && current_char != '\n' && current_char != ':'
            advance
          end
          is_mapping_key = !at_end? && current_char == ':'
          # Restore position
          @reader.pos = saved_pos
          @line = saved_line
          @column = saved_col
          if is_mapping_key
            raise LexerError.new("Tab character cannot be used for indentation", tab_loc)
          end
        end
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
        # Comment only if at start of line or preceded by whitespace
        if at_line_start || whitespace_skipped || @whitespace_before_current
          @whitespace_before_current = false
          scan_comment
        else
          # # without preceding whitespace is part of plain scalar or error
          raise LexerError.new("Comment must be preceded by whitespace", current_location)
        end
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
      when '['
        scan_sequence_start
      when ']'
        # Only treat ] as SequenceEnd when inside a flow context
        if @flow_level > 0
          scan_sequence_end
        else
          scan_scalar
        end
      when '{'
        scan_mapping_start
      when '}'
        # Only treat } as MappingEnd when inside a flow context
        if @flow_level > 0
          scan_mapping_end
        else
          scan_scalar
        end
      when ','
        # Only treat , as FlowSeparator when inside a flow context
        if @flow_level > 0
          scan_flow_separator
        else
          scan_scalar
        end
      when '|', '>'
        scan_block_scalar_indicator
      when '?'
        scan_key_indicator_or_scalar
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

    # Returns true if any whitespace was skipped, false otherwise
    private def skip_whitespace : Bool
      # In flow context, tabs are allowed as whitespace
      # In block context, only spaces are valid indentation
      # Track start column to handle mid-line whitespace vs indentation
      start_col = @column
      skipped = false
      if @flow_level > 0 || start_col > 1
        # Flow context or mid-line: skip both spaces and tabs together
        while current_char == ' ' || current_char == '\t'
          advance
          skipped = true
        end
      else
        # Block context at start of line: only skip spaces for indentation
        while current_char == ' '
          advance
          skipped = true
        end
      end
      skipped
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
      # Don't skip whitespace here - let the next next_token call handle it
      # This preserves the column position for proper tab handling
      Token.new(TokenType::Newline, "", loc)
    end

    private def scan_value_indicator : Token
      loc = current_location
      advance

      # : followed by non-indicator characters is a plain scalar (e.g., ":foo")
      # : followed by whitespace, newline, or EOF is a value indicator
      # : followed by flow indicators (,]}) is a value indicator only in flow context
      is_value_indicator = at_end? || current_char == ' ' || current_char == '\t' || current_char == '\n'
      if !is_value_indicator && @flow_level > 0
        is_value_indicator = current_char == ',' || current_char == ']' || current_char == '}'
      end

      if is_value_indicator
        Token.new(TokenType::ValueIndicator, ":", loc)
      else
        # Scan as scalar (e.g., ":foo" or ":," becomes scalar value)
        value = String.build do |str|
          str << ':'
          while !at_end? && !scalar_terminator_with_colon_check?(current_char)
            str << advance
          end
        end
        # Strip trailing whitespace (not leading - preserve leading content like tabs)
        Token.new(TokenType::Scalar, value.rstrip, loc)
      end
    end

    private def scan_key_indicator_or_scalar : Token
      loc = current_location
      advance # consume ?

      # ? followed by whitespace, newline, or EOF is a key indicator
      if at_end? || current_char == ' ' || current_char == '\t' || current_char == '\n'
        Token.new(TokenType::KeyIndicator, "?", loc)
      else
        # Otherwise it's part of a scalar (e.g., "?foo")
        value = String.build do |str|
          str << '?'
          while !at_end? && !scalar_terminator?(current_char)
            str << advance
          end
        end
        Token.new(TokenType::Scalar, value.strip, loc)
      end
    end

    private def scan_scalar : Token
      loc = current_location
      value = String.build do |str|
        trailing_ws = String::Builder.new
        stopped_for_comment = false

        while !at_end? && !scalar_terminator_with_colon_check?(current_char)
          char = current_char
          if char == ' ' || char == '\t'
            # Track trailing whitespace
            trailing_ws << advance
          elsif char == '#'
            # # after whitespace is a comment - stop scanning
            if trailing_ws.empty?
              # # at start or after non-whitespace is part of scalar
              str << trailing_ws.to_s
              trailing_ws = String::Builder.new
              str << advance
            else
              # Comment starts here - don't include trailing whitespace
              # Mark that the # was preceded by whitespace for the next token call
              @whitespace_before_current = true
              stopped_for_comment = true
              break
            end
          elsif char == '\n' && @flow_level > 0
            # In flow context, check for multiline plain scalar continuation
            advance # consume newline
            @line += 1
            @column = 1
            trailing_ws = String::Builder.new

            # Skip whitespace at start of new line
            while !at_end? && (current_char == ' ' || current_char == '\t')
              advance
            end

            # Check if we should continue or stop
            # Comments and flow indicators terminate the scalar
            if at_end? || flow_scalar_terminator?(current_char) || current_char == '#'
              break
            end

            # Fold the newline into a space and continue
            str << ' '
          else
            # Regular character - flush trailing whitespace and add char
            str << trailing_ws.to_s
            trailing_ws = String::Builder.new
            str << advance
          end
        end
        # Include trailing whitespace (before newline terminator)
        # unless we stopped because of a comment
        unless stopped_for_comment
          str << trailing_ws.to_s
        end
      end
      Token.new(TokenType::Scalar, value, loc)
    end

    # Check if character terminates a scalar in flow context
    private def flow_scalar_terminator?(char : Char) : Bool
      char == ',' || char == '[' || char == ']' || char == '{' || char == '}' || char == ':'
    end

    # Check if character terminates a scalar, with special colon handling
    # Colon terminates when followed by whitespace, newline, or EOF
    # In flow context, colon also terminates when followed by flow indicators
    private def scalar_terminator_with_colon_check?(char : Char) : Bool
      if char == ':'
        # Colon at end of input is a value indicator
        return true unless @reader.has_next?
        # Peek at next char to see if it's whitespace or EOF
        saved_pos = @reader.pos
        @reader.next_char
        next_char = @reader.current_char
        @reader.pos = saved_pos
        is_terminator = next_char == ' ' || next_char == '\t' || next_char == '\n' || next_char == '\0'
        # In flow context, colon followed by flow indicators is also a value indicator
        if !is_terminator && @flow_level > 0
          is_terminator = next_char == ',' || next_char == ']' || next_char == '}'
        end
        is_terminator
      else
        scalar_terminator?(char)
      end
    end

    private def scan_single_quoted_scalar : Token
      loc = current_location
      advance # consume opening '

      value = String.build do |str|
        trailing_ws = String::Builder.new

        loop do
          if at_end?
            raise LexerError.new("Unterminated single-quoted string", loc)
          end

          char = current_char
          if char == '\''
            advance # consume the quote
            if current_char == '\''
              # Escaped single quote ('') becomes literal '
              str << trailing_ws.to_s
              trailing_ws = String::Builder.new
              str << advance
            else
              # End of string - keep trailing whitespace before closing quote
              str << trailing_ws.to_s
              break
            end
          elsif char == '\n'
            # Strip trailing whitespace before line break
            trailing_ws = String::Builder.new
            advance # consume newline

            # Check for document markers at start of line (forbidden in strings)
            if @column == 1 && check_document_marker?
              raise LexerError.new("Unterminated single-quoted string (document marker encountered)", loc)
            end

            # Handle line folding
            str << fold_single_quoted_line
          elsif char == ' ' || char == '\t'
            # Track trailing whitespace
            trailing_ws << advance
          else
            # Regular character - flush trailing whitespace
            str << trailing_ws.to_s
            trailing_ws = String::Builder.new
            str << advance
          end
        end
      end

      # Comment without preceding whitespace after quoted scalar is an error
      if !at_end? && current_char == '#'
        raise LexerError.new("Comment must be preceded by whitespace after quoted scalar", loc)
      end

      Token.new(TokenType::Scalar, value, loc, ScalarTokenStyle::SingleQuoted)
    end

    private def scan_double_quoted_scalar : Token
      loc = current_location
      advance # consume opening "

      value = String.build do |str|
        trailing_ws = String::Builder.new

        loop do
          if at_end?
            raise LexerError.new("Unterminated double-quoted string", loc)
          end

          char = current_char
          if char == '"'
            # Keep trailing whitespace before closing quote
            str << trailing_ws.to_s
            advance # consume closing "
            break
          elsif char == '\\'
            str << trailing_ws.to_s
            trailing_ws = String::Builder.new
            result = scan_escape_sequence(loc)
            # scan_escape_sequence returns empty string for escaped newline
            str << result unless result.is_a?(String) && result.empty?
          elsif char == '\n'
            # Strip trailing whitespace before line break
            trailing_ws = String::Builder.new
            advance # consume newline

            # Check for document markers at start of line (forbidden in strings)
            if @column == 1 && check_document_marker?
              raise LexerError.new("Unterminated double-quoted string (document marker encountered)", loc)
            end

            str << fold_double_quoted_line
          elsif char == ' ' || char == '\t'
            # Track trailing whitespace
            trailing_ws << advance
          else
            # Regular character - flush trailing whitespace
            str << trailing_ws.to_s
            trailing_ws = String::Builder.new
            str << advance
          end
        end
      end

      # Comment without preceding whitespace after quoted scalar is an error
      if !at_end? && current_char == '#'
        raise LexerError.new("Comment must be preceded by whitespace after quoted scalar", loc)
      end

      Token.new(TokenType::Scalar, value, loc, ScalarTokenStyle::DoubleQuoted)
    end

    # Handle line folding in quoted strings (single or double quoted)
    # - Skip leading whitespace on continuation line
    # - Return space for normal fold, newline for empty line
    private def fold_quoted_line : String
      # Check if this line is empty (only whitespace before newline)
      result = String.build do |str|
        # Count consecutive empty lines (newlines followed by whitespace only)
        empty_lines = 0

        loop do
          # Skip leading whitespace
          while current_char == ' ' || current_char == '\t'
            advance
          end

          if current_char == '\n'
            # Empty line - counts as a literal newline
            empty_lines += 1
            advance
          else
            break
          end
        end

        if empty_lines > 0
          # Empty lines become newlines
          str << "\n" * empty_lines
        else
          # Normal line break becomes a space
          str << " "
        end
      end
      result
    end

    # Aliases for clarity
    private def fold_single_quoted_line : String
      fold_quoted_line
    end

    private def fold_double_quoted_line : String
      fold_quoted_line
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
      when '\n'
        # Escaped newline - skip the newline and any leading whitespace on next line
        while current_char == ' ' || current_char == '\t'
          advance
        end
        "" # Return empty string (newline is escaped away)
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
        # Consume the three dashes
        advance # first -
        advance # second -
        advance # third -

        # --- is only a document marker if followed by whitespace, newline, or EOF
        if at_end? || current_char == ' ' || current_char == '\t' || current_char == '\n'
          Token.new(TokenType::DocumentStart, "---", loc)
        else
          # Not a document start - it's a scalar starting with ---
          value = String.build do |str|
            str << "---"
            while !at_end? && !scalar_terminator?(current_char)
              str << advance
            end
          end
          Token.new(TokenType::Scalar, value.strip, loc)
        end
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

    # Check if current position has a document marker (--- or ...)
    private def check_document_marker? : Bool
      return false unless current_char == '-' || current_char == '.'
      return false unless @reader.has_next?

      # Save position
      saved_pos = @reader.pos
      first_char = current_char

      @reader.next_char
      return false.tap { @reader.pos = saved_pos } unless @reader.current_char == first_char
      return false.tap { @reader.pos = saved_pos } unless @reader.has_next?

      @reader.next_char
      result = @reader.current_char == first_char

      @reader.pos = saved_pos
      result
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
      # In flow context, comma and brackets terminate scalars
      # Newlines in flow context are handled specially (folded into spaces)
      # In block context, only newline and colon terminate (brackets are valid in plain scalars)
      if @flow_level > 0
        char == ':' || char == ',' ||
          char == '[' || char == ']' || char == '{' || char == '}'
      else
        char == '\n' || char == ':'
      end
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

      # & must be followed by valid anchor name characters
      if at_end? || !valid_anchor_alias_char?(current_char)
        raise LexerError.new("Invalid anchor name: must contain valid characters", loc)
      end

      name = scan_anchor_alias_name(loc, "anchor")
      Token.new(TokenType::Anchor, name, loc)
    end

    private def scan_alias : Token
      loc = current_location
      advance # consume *

      # * followed by whitespace or flow indicator is not an alias - it's a literal * in content
      # Only * followed by valid anchor/alias name characters is an alias
      if at_end? || !valid_anchor_alias_char?(current_char)
        # Not an alias - return * as a scalar
        # Continue scanning the rest as a plain scalar
        value = String.build do |str|
          str << '*'
          while !at_end? && !scalar_terminator_with_colon_check?(current_char)
            str << advance
          end
        end
        return Token.new(TokenType::Scalar, value.strip, loc)
      end

      name = scan_anchor_alias_name(loc, "alias")
      Token.new(TokenType::Alias, name, loc)
    end

    private def scan_anchor_alias_name(loc : Location, kind : String) : String
      if at_end? || !valid_anchor_alias_char?(current_char)
        raise LexerError.new("Invalid #{kind} name: must contain valid characters", loc)
      end

      String.build do |str|
        while !at_end? && valid_anchor_alias_char?(current_char)
          str << advance
        end
      end
    end

    private def valid_anchor_alias_char?(char : Char) : Bool
      # YAML spec: ns-anchor-char excludes flow indicators, whitespace, and certain chars
      # We use a blocklist approach for better compatibility
      !anchor_alias_terminator?(char)
    end

    private def anchor_alias_terminator?(char : Char) : Bool
      char == ' ' || char == '\t' || char == '\n' || char == '\r' ||
        char == '[' || char == ']' || char == '{' || char == '}' || char == ','
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
          # Comma immediately after tag is invalid in block context (no whitespace between)
          # In flow context, comma is a valid separator after tag
          if !at_end? && current_char == ',' && @flow_level == 0
            raise LexerError.new("Invalid comma in tag - tags must be followed by whitespace", loc)
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
        elsif valid_tag_start_char?(current_char)
          # Local tag (!type) or named tag handle (!prefix!suffix)
          # Tag name must start with valid word char (alphanumeric or -)
          while !at_end? && !tag_terminator?(current_char)
            str << advance
          end
          # Comma immediately after tag is invalid in block context (no whitespace between)
          # In flow context, comma is a valid separator after tag
          if !at_end? && current_char == ',' && @flow_level == 0
            raise LexerError.new("Invalid comma in tag - tags must be followed by whitespace", loc)
          end
        else
          # Invalid tag start character (like !" or !#) - treat as scalar
          while !at_end? && !scalar_terminator_with_colon_check?(current_char)
            str << advance
          end
          return Token.new(TokenType::Scalar, str.to_s.strip, loc)
        end
      end

      Token.new(TokenType::Tag, value, loc)
    end

    # Check if character is valid for starting a tag name (after !)
    private def valid_tag_start_char?(char : Char) : Bool
      char.alphanumeric? || char == '-' || char == '_'
    end

    private def tag_terminator?(char : Char) : Bool
      char == ' ' || char == '\t' || char == '\n' || char == ':' ||
        char == ',' || char == '[' || char == ']' || char == '{' || char == '}'
    end

    private def scan_sequence_start : Token
      loc = current_location
      advance
      @flow_level += 1
      Token.new(TokenType::SequenceStart, "[", loc)
    end

    private def scan_sequence_end : Token
      loc = current_location
      advance
      @flow_level -= 1 if @flow_level > 0
      Token.new(TokenType::SequenceEnd, "]", loc)
    end

    private def scan_mapping_start : Token
      loc = current_location
      advance
      @flow_level += 1
      Token.new(TokenType::MappingStart, "{", loc)
    end

    private def scan_mapping_end : Token
      loc = current_location
      advance
      @flow_level -= 1 if @flow_level > 0
      Token.new(TokenType::MappingEnd, "}", loc)
    end

    private def scan_flow_separator : Token
      loc = current_location
      advance
      Token.new(TokenType::FlowSeparator, ",", loc)
    end

    private def scan_block_scalar_indicator : Token
      loc = current_location

      value = String.build do |str|
        # Read the indicator (| or >)
        str << advance

        # Read optional chomping indicator (+ or -) and/or indentation indicator (1-9)
        # They can appear in either order: |+ |2 |+2 |2+
        chomping_read = false
        indent_read = false

        2.times do
          break if at_end?

          case current_char
          when '+', '-'
            break if chomping_read
            str << advance
            chomping_read = true
          when '1', '2', '3', '4', '5', '6', '7', '8', '9'
            break if indent_read
            str << advance
            indent_read = true
          else
            break
          end
        end
      end

      # After block scalar header, only whitespace, comment (with preceding space), or newline allowed
      # A # directly after the header without whitespace is an error
      if !at_end? && current_char == '#'
        raise LexerError.new("Comment must be preceded by whitespace after block scalar indicator", loc)
      end

      Token.new(TokenType::BlockScalarHeader, value, loc)
    end
  end
end
