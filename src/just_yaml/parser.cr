module JustYAML
  class Parser
    @lexer : Lexer
    @current_token : Token
    @anchors : Hash(String, AST::Node) = {} of String => AST::Node

    def initialize(input : String)
      @lexer = Lexer.new(input)
      @current_token = @lexer.next_token
    end

    def parse : AST::StreamNode
      stream = AST::StreamNode.new
      stream.start_location = @current_token.location

      expect(TokenType::StreamStart)

      first_document = true
      after_document_end = true # First document acts as if after "end"
      while !check(TokenType::StreamEnd)
        skip_comments_and_newlines
        break if check(TokenType::StreamEnd)

        doc = parse_document(first_document || after_document_end)
        # Only add documents that have content or explicit markers
        # Skip empty documents that only have document-end markers
        if doc.root || doc.explicit_start
          stream.documents << doc
        end
        first_document = false
        after_document_end = doc.explicit_end
      end

      stream.end_location = @current_token.location
      stream
    end

    private def parse_document(after_document_end : Bool = false) : AST::DocumentNode
      doc = AST::DocumentNode.new
      doc.start_location = @current_token.location

      # Check for directives before document
      had_directives = skip_directives_with_validation(after_document_end)

      # Check for explicit document start
      if check(TokenType::DocumentStart)
        doc.explicit_start = true
        advance
        skip_comments_and_newlines
      end

      # If we had directives but no document marker follows, it's an error
      # An empty document (--- ... ---) after a directive is valid
      if had_directives && !doc.explicit_start
        if check(TokenType::StreamEnd) || check(TokenType::DocumentEnd)
          raise ParseError.new("Directive(s) without following document", doc.start_location)
        end
      end

      # Parse document content (if any)
      unless check(TokenType::StreamEnd) || check(TokenType::DocumentStart) || check(TokenType::DocumentEnd)
        doc.root = parse_node(0)
      end

      skip_comments_and_newlines

      # Check for explicit document end
      if check(TokenType::DocumentEnd)
        doc.explicit_end = true
        doc_end_line = @current_token.location.line
        advance

        # Skip comments on the same line
        if check(TokenType::Comment)
          advance
        end

        # After document end, we must have newline, EOF, or new document marker
        # Content on the same line is invalid
        if !check(TokenType::StreamEnd) && !check(TokenType::Newline) &&
           !check(TokenType::DocumentStart) && !check(TokenType::DocumentEnd)
          if @current_token.location.line == doc_end_line
            raise ParseError.new(
              "Unexpected content after document end marker",
              @current_token.location
            )
          end
        end

        skip_comments_and_newlines
      end

      doc.end_location = @current_token.location
      doc
    end

    private def parse_node(min_indent : Int32) : AST::Node
      skip_comments_and_newlines

      # Track where node properties start (for mapping indent detection)
      entry_start_col = @current_token.location.column

      # Parse anchor, tag, or alias that precedes the actual node
      anchor, tag, alias_node = parse_node_properties

      return alias_node if alias_node

      # Skip newlines after anchor/tag (content may be on next line)
      skip_comments_and_newlines

      # Pass anchor/tag info so mapping can apply it to the key if appropriate
      node = parse_node_content_with_properties(min_indent, entry_start_col, anchor, tag)

      node
    end

    private def parse_node_properties : {String?, String?, AST::Node?}
      anchor : String? = nil
      tag : String? = nil

      # Handle anchor and tag in any order
      loop do
        if check(TokenType::Anchor) && anchor.nil?
          anchor = @current_token.value
          advance
          skip_whitespace_tokens
        elsif check(TokenType::Tag) && tag.nil?
          tag = @current_token.value
          advance
          skip_whitespace_tokens
        else
          break
        end
      end

      # Handle alias reference
      if check(TokenType::Alias)
        alias_name = @current_token.value
        loc = @current_token.location
        advance

        resolved = @anchors[alias_name]?
        unless resolved
          raise ParseError.new("Unknown alias '#{alias_name}'", loc)
        end

        return {nil, nil, resolved}
      end

      {anchor, tag, nil}
    end

    private def parse_node_content(min_indent : Int32) : AST::Node
      parse_node_content_with_properties(min_indent, @current_token.location.column, nil, nil)
    end

    private def parse_node_content_with_entry_start(min_indent : Int32, entry_start_col : Int32) : AST::Node
      parse_node_content_with_properties(min_indent, entry_start_col, nil, nil)
    end

    private def parse_node_content_with_properties(min_indent : Int32, entry_start_col : Int32, anchor : String?, tag : String?) : AST::Node
      case @current_token.type
      when TokenType::SequenceEntry
        node = parse_block_sequence(min_indent)
        apply_node_properties(node, anchor, tag)
      when TokenType::Scalar
        parse_mapping_or_scalar_with_properties(min_indent, entry_start_col, anchor, tag)
      when TokenType::SequenceStart
        node = parse_flow_sequence
        apply_node_properties(node, anchor, tag)
      when TokenType::MappingStart
        node = parse_flow_mapping
        apply_node_properties(node, anchor, tag)
      when TokenType::BlockScalarHeader
        node = parse_block_scalar(min_indent)
        apply_node_properties(node, anchor, tag)
      when TokenType::ValueIndicator
        # Implicit null key mapping (e.g., ": value")
        node = parse_block_mapping_with_null_key(min_indent)
        apply_node_properties(node, anchor, tag)
      when TokenType::KeyIndicator
        # Explicit key mapping (e.g., "? key\n: value")
        node = parse_block_mapping_with_explicit_key(min_indent)
        apply_node_properties(node, anchor, tag)
      when TokenType::Anchor, TokenType::Tag
        # Nested anchor/tag (e.g., "&outer\n&inner value")
        # The outer anchor applies to the whole structure
        inner_anchor, inner_tag, alias_node = parse_node_properties
        if alias_node
          # Apply outer properties and return alias
          apply_node_properties(alias_node, anchor, tag)
        else
          skip_comments_and_newlines
          # Parse the inner node
          inner_node = parse_inner_node_with_properties(min_indent, entry_start_col, inner_anchor, inner_tag)
          skip_whitespace_tokens

          # Check if this is a mapping key
          if check(TokenType::ValueIndicator)
            # The inner node is a mapping key - create a mapping
            key = inner_node
            mapping = parse_block_mapping_with_complex_key(key, entry_start_col)
            apply_node_properties(mapping, anchor, tag)
          else
            apply_node_properties(inner_node, anchor, tag)
          end
        end
      else
        raise ParseError.new(
          "Unexpected token #{@current_token.type}",
          @current_token.location
        )
      end
    end

    private def apply_node_properties(node : AST::Node, anchor : String?, tag : String?) : AST::Node
      if anchor
        node.anchor = anchor
        @anchors[anchor] = node
      end
      node.tag = tag if tag
      node
    end

    # Parse inner node with properties (doesn't check for mapping key afterward)
    private def parse_inner_node_with_properties(min_indent : Int32, entry_start_col : Int32, anchor : String?, tag : String?) : AST::Node
      case @current_token.type
      when TokenType::Scalar
        scalar = parse_scalar
        apply_node_properties(scalar, anchor, tag)
      when TokenType::SequenceStart
        node = parse_flow_sequence
        apply_node_properties(node, anchor, tag)
      when TokenType::MappingStart
        node = parse_flow_mapping
        apply_node_properties(node, anchor, tag)
      when TokenType::SequenceEntry
        node = parse_block_sequence(min_indent)
        apply_node_properties(node, anchor, tag)
      when TokenType::BlockScalarHeader
        node = parse_block_scalar(min_indent)
        apply_node_properties(node, anchor, tag)
      when TokenType::Anchor, TokenType::Tag
        # Another level of nesting
        inner_anchor, inner_tag, alias_node = parse_node_properties
        if alias_node
          apply_node_properties(alias_node, anchor, tag)
        else
          skip_comments_and_newlines
          node = parse_inner_node_with_properties(min_indent, entry_start_col, inner_anchor, inner_tag)
          apply_node_properties(node, anchor, tag)
        end
      else
        raise ParseError.new(
          "Unexpected token #{@current_token.type}",
          @current_token.location
        )
      end
    end

    # Parse a block mapping where the first key is already parsed as a complex node
    private def parse_block_mapping_with_complex_key(first_key : AST::Node, key_indent : Int32) : AST::MappingNode
      mapping = AST::MappingNode.new
      mapping.start_location = first_key.start_location || @current_token.location
      mapping.style = AST::CollectionStyle::Block

      key = first_key

      loop do
        expect(TokenType::ValueIndicator)
        skip_whitespace_tokens

        value = parse_mapping_value(key_indent)
        mapping.entries << AST::MappingEntry.new(key: key, value: value)

        skip_comments_and_newlines

        break if check(TokenType::StreamEnd) ||
                 check(TokenType::DocumentStart) ||
                 check(TokenType::DocumentEnd)

        next_col = @current_token.location.column
        break if next_col < key_indent

        # For subsequent keys, use standard parsing
        case @current_token.type
        when TokenType::Scalar, TokenType::Anchor, TokenType::Tag
          entry_start = @current_token.location.column
          break if entry_start != key_indent

          # Parse key with potential anchor/tag
          next_key_anchor : String? = nil
          next_key_tag : String? = nil

          if check(TokenType::Anchor)
            next_key_anchor = @current_token.value
            advance
            skip_whitespace_tokens
          end

          if check(TokenType::Tag)
            next_key_tag = @current_token.value
            advance
            skip_whitespace_tokens
          end

          if check(TokenType::Scalar)
            key = parse_scalar
            skip_whitespace_tokens
            unless check(TokenType::ValueIndicator)
              raise ParseError.new("Expected ':' after mapping key", @current_token.location)
            end
            if next_key_anchor
              key.anchor = next_key_anchor
              @anchors[next_key_anchor] = key
            end
            key.tag = next_key_tag if next_key_tag
          elsif check(TokenType::SequenceStart) || check(TokenType::MappingStart)
            key = if check(TokenType::SequenceStart)
                    parse_flow_sequence
                  else
                    parse_flow_mapping
                  end
            skip_whitespace_tokens
            unless check(TokenType::ValueIndicator)
              raise ParseError.new("Expected ':' after mapping key", @current_token.location)
            end
            if next_key_anchor
              key.anchor = next_key_anchor
              @anchors[next_key_anchor] = key
            end
            key.tag = next_key_tag if next_key_tag
          else
            break
          end
        when TokenType::KeyIndicator
          # Explicit key
          advance
          skip_whitespace_tokens
          if check(TokenType::Newline) || check(TokenType::ValueIndicator)
            key = AST::ScalarNode.new("")
            key.start_location = @current_token.location
            key.end_location = @current_token.location
          else
            key = parse_node(key_indent)
          end
          skip_comments_and_newlines
          unless check(TokenType::ValueIndicator)
            raise ParseError.new("Expected ':' after explicit key", @current_token.location)
          end
        else
          break
        end
      end

      mapping.end_location = @current_token.location
      mapping
    end

    private def parse_mapping_or_scalar(min_indent : Int32) : AST::Node
      parse_mapping_or_scalar_with_properties(min_indent, @current_token.location.column, nil, nil)
    end

    private def parse_mapping_or_scalar_with_entry_start(min_indent : Int32, entry_start_col : Int32) : AST::Node
      parse_mapping_or_scalar_with_properties(min_indent, entry_start_col, nil, nil)
    end

    private def parse_mapping_or_scalar_with_properties(min_indent : Int32, entry_start_col : Int32, anchor : String?, tag : String?) : AST::Node
      first_scalar = parse_scalar
      skip_whitespace_tokens

      if check(TokenType::ValueIndicator)
        # This is a mapping - apply anchor/tag to the KEY, not the mapping
        if anchor
          first_scalar.anchor = anchor
          @anchors[anchor] = first_scalar
        end
        first_scalar.tag = tag if tag
        parse_block_mapping_with_entry_start(first_scalar, min_indent, entry_start_col)
      else
        # Just a scalar - apply anchor/tag to it
        node = parse_multiline_plain_scalar(first_scalar)
        apply_node_properties(node, anchor, tag)
      end
    end

    # Parse multiline plain scalar by checking for continuation lines
    private def parse_multiline_plain_scalar(first_scalar : AST::ScalarNode) : AST::Node
      fold_multiline_plain_scalar(first_scalar)
    end

    # Mode for multiline plain scalar parsing context
    private enum MultilineScalarMode
      Root     # Top-level or general block context
      Sequence # Inside a block sequence item
      Mapping  # Inside a block mapping value
    end

    # Build the final multiline plain scalar node from collected lines
    private def build_multiline_plain_scalar(
      lines : Array(String),
      first_scalar : AST::ScalarNode,
      end_location : Location,
    ) : AST::ScalarNode
      # Join with spaces, but preserve newlines from empty lines
      result = String.build do |str|
        lines.each_with_index do |line, idx|
          if idx > 0 && !lines[idx - 1].ends_with?("\n") && !line.starts_with?("\n")
            str << " "
          end
          str << line.gsub(/^\n+/) { |m| m } # Preserve leading newlines
        end
      end

      scalar = AST::ScalarNode.new(result, AST::ScalarStyle::Plain)
      scalar.start_location = first_scalar.start_location
      scalar.end_location = end_location
      scalar
    end

    # Append a continuation line to the lines array, handling empty line counts
    private def append_continuation_line(
      lines : Array(String),
      line_content : String,
      empty_line_count : Int32,
    ) : Int32
      if empty_line_count > 0
        lines << "\n" * empty_line_count
      end
      lines << line_content
      0 # Reset empty line count
    end

    # Shared helper for parsing multiline plain scalars across all contexts
    # Returns the folded scalar node or the original if no continuation found
    #
    # Parameters:
    # - mode: parsing context (Root uses scalar column, Sequence/Mapping use indent params)
    # - entry_indent: for Sequence mode, the column of the sequence entry indicator
    # - key_indent: for Mapping mode, the column of the mapping key
    private def fold_multiline_plain_scalar(
      first_scalar : AST::ScalarNode,
      *,
      mode : MultilineScalarMode = MultilineScalarMode::Root,
      entry_indent : Int32 = -1,
      key_indent : Int32 = -1,
    ) : AST::Node
      # Only plain scalars can span multiple lines
      return first_scalar unless first_scalar.style == AST::ScalarStyle::Plain

      scalar_indent = first_scalar.start_location.column
      lines = [first_scalar.value]
      empty_line_count = 0

      loop do
        # Check for newline followed by potential continuation
        break unless check(TokenType::Newline) || check(TokenType::Comment)

        # Track empty lines (they become newlines in folded text)
        while check(TokenType::Newline)
          advance
          if check(TokenType::Newline) || check(TokenType::StreamEnd)
            empty_line_count += 1
          end
        end

        # Skip comments (they don't count as content)
        if check(TokenType::Comment)
          advance
          next
        end

        # Check if we should stop
        break if check(TokenType::StreamEnd) ||
                 check(TokenType::DocumentStart) ||
                 check(TokenType::DocumentEnd)

        # Check indentation of next content
        next_col = @current_token.location.column

        # Mode-specific indentation break conditions
        case mode
        when MultilineScalarMode::Root
          break if next_col < scalar_indent
        when MultilineScalarMode::Sequence
          break if next_col <= entry_indent
        when MultilineScalarMode::Mapping
          break if next_col <= key_indent
        end

        # Sequence mode: check for continuation that looks like sequence entry
        if mode == MultilineScalarMode::Sequence && check(TokenType::SequenceEntry)
          # Could be nested sequence entry OR literal text
          # If between entry_indent and scalar_indent, it's literal text
          if next_col > entry_indent && next_col < scalar_indent
            line_content = consume_sequence_like_continuation
            if line_content
              empty_line_count = append_continuation_line(lines, line_content, empty_line_count)
              next
            end
          end
          # Otherwise it's a real sequence entry, stop multiline
          break
        end

        # For continuation lines that are MORE indented, consume all tokens
        # as literal text (indicators become literal chars in this context)
        if next_col > scalar_indent
          line_content = consume_plain_scalar_continuation_line
          if line_content
            empty_line_count = append_continuation_line(lines, line_content, empty_line_count)
            next
          else
            break
          end
        end

        # At same indentation, continue if it's a plain scalar or directive-like content
        if check(TokenType::Directive)
          # Directive at same indentation is continuation content
          # (it's only a real directive if at start of stream or after document end)
          empty_line_count = append_continuation_line(lines, @current_token.value, empty_line_count)
          advance
          # Skip the newline after the directive
          advance if check(TokenType::Newline)
          next
        end

        break unless check(TokenType::Scalar)

        # Look ahead to see if this scalar is a mapping key
        saved_token = @current_token
        next_scalar = parse_scalar
        skip_whitespace_tokens

        if check(TokenType::ValueIndicator)
          # This scalar is a mapping key, not a continuation
          raise ParseError.new(
            "Cannot have mapping key after multiline scalar at same indentation",
            saved_token.location
          )
        end

        # Add this line as continuation
        empty_line_count = append_continuation_line(lines, next_scalar.value, empty_line_count)
      end

      # If no continuation, just return original scalar
      return first_scalar if lines.size == 1

      build_multiline_plain_scalar(lines, first_scalar, @current_token.location)
    end

    # Consume tokens on a continuation line and return as literal text
    # In multiline plain scalar context, indicators become literal characters
    private def consume_plain_scalar_continuation_line : String?
      parts = [] of String
      start_line = @current_token.location.line

      while @current_token.location.line == start_line
        case @current_token.type
        when TokenType::Scalar
          parts << @current_token.value
          advance
        when TokenType::Anchor
          parts << "&#{@current_token.value}"
          advance
        when TokenType::Alias
          parts << "*#{@current_token.value}"
          advance
        when TokenType::Tag
          parts << @current_token.value
          advance
        when TokenType::ValueIndicator
          parts << ":"
          advance
        when TokenType::KeyIndicator
          parts << "?"
          advance
        when TokenType::Newline, TokenType::Comment, TokenType::StreamEnd,
             TokenType::DocumentStart, TokenType::DocumentEnd
          break
        else
          break
        end
      end

      return nil if parts.empty?
      parts.join(" ")
    end

    # Parse multiline plain scalar in sequence item context
    # Handles cases where continuation looks like a sequence entry
    private def parse_multiline_plain_scalar_in_sequence(first_scalar : AST::ScalarNode, entry_indent : Int32) : AST::Node
      fold_multiline_plain_scalar(first_scalar, mode: MultilineScalarMode::Sequence, entry_indent: entry_indent)
    end

    # Consume a continuation line that starts with what looks like sequence entry
    private def consume_sequence_like_continuation : String?
      parts = [] of String
      start_line = @current_token.location.line

      while @current_token.location.line == start_line
        case @current_token.type
        when TokenType::SequenceEntry
          parts << "-"
          advance
        when TokenType::Scalar
          parts << @current_token.value
          advance
        when TokenType::Anchor
          parts << "&#{@current_token.value}"
          advance
        when TokenType::Alias
          parts << "*#{@current_token.value}"
          advance
        when TokenType::Tag
          parts << @current_token.value
          advance
        when TokenType::ValueIndicator
          parts << ":"
          advance
        when TokenType::KeyIndicator
          parts << "?"
          advance
        when TokenType::Newline, TokenType::Comment, TokenType::StreamEnd,
             TokenType::DocumentStart, TokenType::DocumentEnd
          break
        else
          break
        end
      end

      return nil if parts.empty?
      parts.join(" ")
    end

    # Parse multiline plain scalar in mapping value context
    private def parse_multiline_plain_scalar_in_mapping(first_scalar : AST::ScalarNode, key_indent : Int32) : AST::Node
      fold_multiline_plain_scalar(first_scalar, mode: MultilineScalarMode::Mapping, key_indent: key_indent)
    end

    private def parse_block_mapping(first_key : AST::ScalarNode, min_indent : Int32) : AST::MappingNode
      parse_block_mapping_with_entry_start(first_key, min_indent, first_key.start_location.column)
    end

    private def parse_block_mapping_with_entry_start(first_key : AST::ScalarNode, min_indent : Int32, entry_start_col : Int32) : AST::MappingNode
      mapping = AST::MappingNode.new
      mapping.start_location = first_key.start_location
      mapping.style = AST::CollectionStyle::Block

      # Use entry_start_col for mapping indent (handles anchors/tags before key)
      key_indent = entry_start_col
      key : AST::Node = first_key

      loop do
        expect(TokenType::ValueIndicator)
        skip_whitespace_tokens

        value = parse_mapping_value(key_indent)
        mapping.entries << AST::MappingEntry.new(key: key, value: value)

        skip_comments_and_newlines

        # Check if we're done with this mapping
        break if check(TokenType::StreamEnd) ||
                 check(TokenType::DocumentStart) ||
                 check(TokenType::DocumentEnd)

        # Check indentation for next potential entry
        next_col = @current_token.location.column
        break if next_col < key_indent

        # Parse next key (may have anchor/tag prefix)
        entry_start = @current_token.location.column
        next_key_anchor : String? = nil
        next_key_tag : String? = nil

        # Handle anchor/tag on key
        if check(TokenType::Anchor)
          next_key_anchor = @current_token.value
          advance
          skip_whitespace_tokens
        end

        if check(TokenType::Tag)
          next_key_tag = @current_token.value
          advance
          skip_whitespace_tokens
        end

        case @current_token.type
        when TokenType::Scalar
          # Check if entry is at the correct indentation
          break if entry_start != key_indent

          # Look ahead to verify this is a mapping entry (has ValueIndicator)
          saved_token = @current_token
          key = parse_scalar
          skip_whitespace_tokens

          unless check(TokenType::ValueIndicator)
            # Not a mapping entry - this scalar is something else (error)
            raise ParseError.new(
              "Unexpected scalar '#{saved_token.value}' without mapping value",
              saved_token.location
            )
          end

          # Apply anchor/tag to the key
          if next_key_anchor
            key.anchor = next_key_anchor
            @anchors[next_key_anchor] = key
          end
          key.tag = next_key_tag if next_key_tag
        when TokenType::SequenceEntry
          # Block sequence at same level - not part of this mapping
          break
        else
          break
        end
      end

      mapping.end_location = @current_token.location
      mapping
    end

    private def parse_block_mapping_with_null_key(min_indent : Int32) : AST::MappingNode
      mapping = AST::MappingNode.new
      mapping.start_location = @current_token.location
      mapping.style = AST::CollectionStyle::Block

      key_indent = @current_token.location.column

      loop do
        # Create null key
        key = AST::ScalarNode.new("")
        key.start_location = @current_token.location
        key.end_location = @current_token.location

        expect(TokenType::ValueIndicator)
        skip_whitespace_tokens

        value = parse_mapping_value(key_indent)
        mapping.entries << AST::MappingEntry.new(key: key, value: value)

        skip_comments_and_newlines

        # Check if we're done with this mapping
        break if check(TokenType::StreamEnd) ||
                 check(TokenType::DocumentStart) ||
                 check(TokenType::DocumentEnd)

        # Check indentation for next potential entry
        next_col = @current_token.location.column
        break if next_col < key_indent

        # Check for another null key entry
        unless check(TokenType::ValueIndicator)
          break
        end
      end

      mapping.end_location = @current_token.location
      mapping
    end

    private def parse_block_mapping_with_explicit_key(min_indent : Int32) : AST::MappingNode
      mapping = AST::MappingNode.new
      mapping.start_location = @current_token.location
      mapping.style = AST::CollectionStyle::Block

      key_indent = @current_token.location.column

      loop do
        expect(TokenType::KeyIndicator)
        skip_whitespace_tokens

        # Parse the key (can be any node, or implicit null)
        key : AST::Node = if check(TokenType::Newline) || check(TokenType::ValueIndicator)
          # Null key
          null_key = AST::ScalarNode.new("")
          null_key.start_location = @current_token.location
          null_key.end_location = @current_token.location
          null_key
        else
          parse_explicit_key_value(key_indent)
        end

        skip_comments_and_newlines

        # Parse value (optional - may have : or be implicit null)
        value : AST::Node? = nil
        if check(TokenType::ValueIndicator)
          advance
          skip_whitespace_tokens

          unless check(TokenType::Newline) || check(TokenType::KeyIndicator) ||
                 check(TokenType::StreamEnd) || check(TokenType::DocumentStart) ||
                 check(TokenType::DocumentEnd)
            value = parse_mapping_value(key_indent)
          end
        end

        mapping.entries << AST::MappingEntry.new(key: key, value: value)

        skip_comments_and_newlines

        # Check if we're done
        break if check(TokenType::StreamEnd) ||
                 check(TokenType::DocumentStart) ||
                 check(TokenType::DocumentEnd)

        # Check indentation
        next_col = @current_token.location.column
        break if next_col < key_indent

        # Continue if another key follows (explicit or implicit)
        if check(TokenType::KeyIndicator)
          # Another explicit key - continue looping
          next
        elsif check(TokenType::Scalar) && next_col == key_indent
          # Implicit key at same indentation - check if followed by :
          saved_token = @current_token
          implicit_key = parse_scalar
          skip_whitespace_tokens

          if check(TokenType::ValueIndicator)
            advance
            skip_whitespace_tokens

            implicit_value : AST::Node? = nil
            unless check(TokenType::Newline) || check(TokenType::KeyIndicator) ||
                   check(TokenType::StreamEnd) || check(TokenType::DocumentStart) ||
                   check(TokenType::DocumentEnd)
              implicit_value = parse_mapping_value(key_indent)
            end

            mapping.entries << AST::MappingEntry.new(key: implicit_key, value: implicit_value)
            skip_comments_and_newlines

            # Check if we should continue after implicit entry
            break if check(TokenType::StreamEnd) ||
                     check(TokenType::DocumentStart) ||
                     check(TokenType::DocumentEnd)
            # Continue to check for more entries
            next
          else
            # Not a mapping entry, stop
            break
          end
        else
          break
        end
      end

      mapping.end_location = @current_token.location
      mapping
    end

    private def parse_explicit_key_value(key_indent : Int32) : AST::Node
      case @current_token.type
      when TokenType::Scalar
        parse_scalar
      when TokenType::SequenceStart
        parse_flow_sequence
      when TokenType::MappingStart
        parse_flow_mapping
      else
        # Default to empty scalar
        null_key = AST::ScalarNode.new("")
        null_key.start_location = @current_token.location
        null_key.end_location = @current_token.location
        null_key
      end
    end

    # Parse a mapping where the first key is an already-resolved alias
    private def parse_block_mapping_with_alias_key(first_key : AST::Node, key_indent : Int32) : AST::MappingNode
      mapping = AST::MappingNode.new
      mapping.start_location = first_key.start_location
      mapping.style = AST::CollectionStyle::Block

      key = first_key

      loop do
        expect(TokenType::ValueIndicator)
        skip_whitespace_tokens

        value = parse_mapping_value(key_indent)
        mapping.entries << AST::MappingEntry.new(key: key, value: value)

        skip_comments_and_newlines

        # Check if we're done with this mapping
        break if check(TokenType::StreamEnd) ||
                 check(TokenType::DocumentStart) ||
                 check(TokenType::DocumentEnd)

        # Check indentation for next potential entry
        next_col = @current_token.location.column
        break if next_col < key_indent

        # Parse next key - could be scalar or alias
        case @current_token.type
        when TokenType::Scalar
          next_key_col = @current_token.location.column
          break if next_key_col != key_indent

          key = parse_scalar
          skip_whitespace_tokens

          unless check(TokenType::ValueIndicator)
            break
          end
        when TokenType::Alias
          next_key_col = @current_token.location.column
          break if next_key_col != key_indent

          alias_name = @current_token.value
          alias_loc = @current_token.location
          advance
          skip_whitespace_tokens

          resolved = @anchors[alias_name]?
          unless resolved
            raise ParseError.new("Unknown alias '#{alias_name}'", alias_loc)
          end

          key = resolved

          unless check(TokenType::ValueIndicator)
            break
          end
        else
          break
        end
      end

      mapping.end_location = @current_token.location
      mapping
    end

    private def parse_mapping_value(key_indent : Int32) : AST::Node?
      # Check for anchor/tag/alias on value
      anchor, tag, alias_node = parse_value_properties
      return alias_node if alias_node

      node = parse_mapping_value_content(key_indent, anchor, tag)

      # If node is nil but we have an anchor or tag, create an empty scalar
      # This handles cases like "a: &anchor" where the value is null
      if node.nil? && (anchor || tag)
        node = AST::ScalarNode.new("", AST::ScalarStyle::Plain)
        node.start_location = @current_token.location
        node.end_location = @current_token.location
      end

      if node && anchor
        node.anchor = anchor
        @anchors[anchor] = node
      end
      if node && tag
        node.tag = tag
      end

      node
    end

    private def parse_value_properties : {String?, String?, AST::Node?}
      anchor : String? = nil
      tag : String? = nil

      # Handle anchor and tag in any order
      loop do
        if check(TokenType::Anchor) && anchor.nil?
          anchor = @current_token.value
          advance
          skip_whitespace_tokens
        elsif check(TokenType::Tag) && tag.nil?
          tag = @current_token.value
          advance
          skip_whitespace_tokens
        else
          break
        end
      end

      # Handle alias reference
      if check(TokenType::Alias)
        alias_name = @current_token.value
        loc = @current_token.location
        advance

        resolved = @anchors[alias_name]?
        unless resolved
          raise ParseError.new("Unknown alias '#{alias_name}'", loc)
        end

        return {nil, nil, resolved}
      end

      {anchor, tag, nil}
    end

    private def parse_mapping_value_content(key_indent : Int32, anchor : String?, tag : String?) : AST::Node?
      case @current_token.type
      when TokenType::Scalar
        scalar = parse_scalar
        skip_whitespace_tokens

        if check(TokenType::ValueIndicator)
          # Nested mapping inline
          parse_block_mapping(scalar, key_indent)
        else
          # Check for multiline plain scalar
          parse_multiline_plain_scalar_in_mapping(scalar, key_indent)
        end
      when TokenType::SequenceStart
        parse_flow_sequence
      when TokenType::MappingStart
        parse_flow_mapping
      when TokenType::BlockScalarHeader
        parse_block_scalar(key_indent)
      when TokenType::SequenceEntry
        # Inline sequence entry (rare but valid)
        parse_block_sequence(key_indent)
      when TokenType::Newline, TokenType::Comment
        # Value on next line (block collection)
        skip_comments_and_newlines

        return nil if check(TokenType::StreamEnd) ||
                      check(TokenType::DocumentStart) ||
                      check(TokenType::DocumentEnd)

        next_col = @current_token.location.column

        # Block sequences/mappings as values can be at same level as key
        # But scalars must be more indented
        if next_col < key_indent
          # Dedented - not a nested value
          return nil
        end

        if next_col == key_indent
          # Same level - only valid for sequences/mappings, not scalars
          unless check(TokenType::SequenceEntry) || check(TokenType::KeyIndicator)
            return nil
          end
        end

        # Nested block content
        parse_nested_value(next_col, key_indent, anchor, tag)
      when TokenType::StreamEnd
        nil
      else
        nil
      end
    end

    private def parse_nested_value(next_col : Int32, key_indent : Int32, anchor : String?, tag : String?) : AST::Node?
      case @current_token.type
      when TokenType::SequenceEntry
        parse_block_sequence(next_col)
      when TokenType::KeyIndicator
        # Explicit key mapping as nested value
        parse_block_mapping_with_explicit_key(next_col)
      when TokenType::Scalar
        # Check if this is a nested mapping
        scalar = parse_scalar
        skip_whitespace_tokens

        if check(TokenType::ValueIndicator)
          parse_block_mapping(scalar, next_col)
        else
          # Check for multiline plain scalar continuation
          fold_multiline_plain_scalar(scalar, mode: MultilineScalarMode::Mapping, key_indent: key_indent)
        end
      when TokenType::SequenceStart
        parse_flow_sequence
      when TokenType::MappingStart
        parse_flow_mapping
      when TokenType::Alias
        # Alias can be a mapping key: *alias : value
        alias_name = @current_token.value
        alias_loc = @current_token.location
        advance
        skip_whitespace_tokens

        resolved = @anchors[alias_name]?
        unless resolved
          raise ParseError.new("Unknown alias '#{alias_name}'", alias_loc)
        end

        if check(TokenType::ValueIndicator)
          # Alias is a mapping key - create a mapping with it
          parse_block_mapping_with_alias_key(resolved, next_col)
        else
          # Just an alias value
          resolved
        end
      when TokenType::Anchor
        # Anchor on nested content
        nested_anchor = @current_token.value
        nested_anchor_loc = @current_token.location
        advance
        skip_whitespace_tokens

        # Now check what follows the anchor
        # If it's a scalar followed by :, this is a mapping (anchor is on the key)
        # If it's just a scalar, the anchor is on the value (check for duplicates)
        if check(TokenType::Scalar)
          # Peek ahead: parse the scalar and check for ValueIndicator
          scalar = parse_scalar
          skip_whitespace_tokens

          if check(TokenType::ValueIndicator)
            # This is a mapping entry with anchored key
            # The outer anchor (if any) is on the mapping, inner anchor is on key
            mapping = parse_block_mapping(scalar, next_col)
            scalar.anchor = nested_anchor
            @anchors[nested_anchor] = scalar

            # Apply outer anchor to the mapping
            if anchor
              mapping.anchor = anchor
              @anchors[anchor] = mapping
            end
            return mapping
          else
            # Just a scalar - check for duplicate anchor
            if anchor
              raise ParseError.new(
                "Node cannot have multiple anchors (both '#{anchor}' and '#{nested_anchor}')",
                nested_anchor_loc
              )
            end
            scalar.anchor = nested_anchor
            @anchors[nested_anchor] = scalar
            return scalar
          end
        else
          # Not a scalar - recursively parse
          node = parse_nested_value(next_col, key_indent, nested_anchor, nil)
          if node && nested_anchor
            node.anchor = nested_anchor
            @anchors[nested_anchor] = node
          end
          node
        end
      else
        nil
      end
    end

    private def parse_block_sequence(min_indent : Int32) : AST::SequenceNode
      sequence = AST::SequenceNode.new
      sequence.start_location = @current_token.location
      sequence.style = AST::CollectionStyle::Block

      entry_indent = @current_token.location.column

      while check(TokenType::SequenceEntry)
        # Verify indentation
        current_indent = @current_token.location.column
        break if current_indent < entry_indent

        expect(TokenType::SequenceEntry)
        skip_whitespace_tokens

        # Parse item value
        item = parse_sequence_item(entry_indent)
        sequence.items << item

        skip_comments_and_newlines

        # Check if we should continue
        break if check(TokenType::StreamEnd) ||
                 check(TokenType::DocumentStart) ||
                 check(TokenType::DocumentEnd)
      end

      sequence.end_location = @current_token.location
      sequence
    end

    private def parse_sequence_item(entry_indent : Int32) : AST::Node
      # Check for anchor/tag on item
      anchor, tag, alias_node = parse_value_properties
      return alias_node if alias_node

      node = parse_sequence_item_content(entry_indent)

      if anchor
        node.anchor = anchor
        @anchors[anchor] = node
      end
      if tag
        node.tag = tag
      end

      node
    end

    private def parse_sequence_item_content(entry_indent : Int32) : AST::Node
      case @current_token.type
      when TokenType::Scalar
        scalar = parse_scalar
        skip_whitespace_tokens

        if check(TokenType::ValueIndicator)
          # This is actually a mapping
          parse_block_mapping(scalar, entry_indent)
        else
          # Check for multiline plain scalar continuation
          parse_multiline_plain_scalar_in_sequence(scalar, entry_indent)
        end
      when TokenType::SequenceStart
        parse_flow_sequence
      when TokenType::MappingStart
        parse_flow_mapping
      when TokenType::SequenceEntry
        # Nested sequence
        parse_block_sequence(entry_indent)
      when TokenType::BlockScalarHeader
        parse_block_scalar(entry_indent)
      when TokenType::Newline, TokenType::Comment
        # Check for block content on next line
        skip_comments_and_newlines

        if check(TokenType::StreamEnd) ||
           check(TokenType::DocumentStart) ||
           check(TokenType::DocumentEnd)
          return AST::ScalarNode.new("")
        end

        next_col = @current_token.location.column

        if next_col > entry_indent
          # Nested content
          case @current_token.type
          when TokenType::SequenceEntry
            parse_block_sequence(next_col)
          when TokenType::Scalar
            scalar = parse_scalar
            skip_whitespace_tokens
            if check(TokenType::ValueIndicator)
              parse_block_mapping(scalar, next_col)
            else
              scalar
            end
          else
            AST::ScalarNode.new("")
          end
        else
          AST::ScalarNode.new("")
        end
      else
        AST::ScalarNode.new("")
      end
    end

    private def parse_flow_sequence : AST::SequenceNode
      sequence = AST::SequenceNode.new
      sequence.start_location = @current_token.location
      sequence.style = AST::CollectionStyle::Flow

      expect(TokenType::SequenceStart)
      skip_flow_whitespace

      unless check(TokenType::SequenceEnd)
        loop do
          item = parse_flow_sequence_item
          sequence.items << item

          skip_flow_whitespace

          if check(TokenType::FlowSeparator)
            advance
            skip_flow_whitespace
            # Allow trailing comma
            break if check(TokenType::SequenceEnd)
          else
            break
          end
        end
      end

      expect(TokenType::SequenceEnd)
      sequence.end_location = @current_token.location
      sequence
    end

    # Parse a flow sequence item, which might be an implicit or explicit mapping entry
    private def parse_flow_sequence_item : AST::Node
      skip_flow_whitespace
      start_loc = @current_token.location

      # Check for explicit key indicator (? key : value)
      if check(TokenType::KeyIndicator)
        advance
        skip_flow_whitespace

        # Parse key (or empty key)
        key : AST::Node
        if check(TokenType::ValueIndicator) || check(TokenType::FlowSeparator) || check(TokenType::SequenceEnd)
          key = AST::ScalarNode.new("")
          key.start_location = @current_token.location
          key.end_location = @current_token.location
        else
          key = parse_flow_node
        end

        skip_flow_whitespace

        # Parse value if there's a colon
        value : AST::Node? = nil
        if check(TokenType::ValueIndicator)
          advance
          skip_flow_whitespace

          unless check(TokenType::FlowSeparator) || check(TokenType::SequenceEnd)
            value = parse_flow_node
          end
        end

        # Create a mapping with single entry
        mapping = AST::MappingNode.new
        mapping.start_location = start_loc
        mapping.end_location = @current_token.location
        mapping.style = AST::CollectionStyle::Flow
        mapping.entries << AST::MappingEntry.new(key: key, value: value)
        return mapping
      end

      # Check for empty key (: value)
      if check(TokenType::ValueIndicator)
        empty_key = AST::ScalarNode.new("")
        empty_key.start_location = @current_token.location
        empty_key.end_location = @current_token.location

        advance
        skip_flow_whitespace

        empty_key_value : AST::Node? = nil
        unless check(TokenType::FlowSeparator) || check(TokenType::SequenceEnd)
          empty_key_value = parse_flow_node
        end

        mapping = AST::MappingNode.new
        mapping.start_location = start_loc
        mapping.end_location = @current_token.location
        mapping.style = AST::CollectionStyle::Flow
        mapping.entries << AST::MappingEntry.new(key: empty_key, value: empty_key_value)
        return mapping
      end

      # Parse the first node
      first_node = parse_flow_node
      skip_flow_whitespace

      # Check if this is an implicit mapping (key: value)
      if check(TokenType::ValueIndicator)
        advance
        skip_flow_whitespace

        # Parse value
        implicit_value : AST::Node? = nil
        unless check(TokenType::FlowSeparator) || check(TokenType::SequenceEnd)
          implicit_value = parse_flow_node
        end

        # Create a mapping with single entry
        mapping = AST::MappingNode.new
        mapping.start_location = start_loc
        mapping.end_location = @current_token.location
        mapping.style = AST::CollectionStyle::Flow
        mapping.entries << AST::MappingEntry.new(key: first_node, value: implicit_value)
        return mapping
      end

      # Also handle case where lexer combined :value into a scalar
      if check(TokenType::Scalar) && @current_token.value.starts_with?(":")
        scalar_value = @current_token.value[1..]
        advance

        colon_value : AST::Node? = nil
        if !scalar_value.empty?
          colon_value = AST::ScalarNode.new(scalar_value, AST::ScalarStyle::Plain)
          colon_value.start_location = @current_token.location
          colon_value.end_location = @current_token.location
        end

        mapping = AST::MappingNode.new
        mapping.start_location = start_loc
        mapping.end_location = @current_token.location
        mapping.style = AST::CollectionStyle::Flow
        mapping.entries << AST::MappingEntry.new(key: first_node, value: colon_value)
        return mapping
      end

      first_node
    end

    private def parse_flow_mapping : AST::MappingNode
      mapping = AST::MappingNode.new
      mapping.start_location = @current_token.location
      mapping.style = AST::CollectionStyle::Flow

      expect(TokenType::MappingStart)
      skip_flow_whitespace

      unless check(TokenType::MappingEnd)
        loop do
          key : AST::Node
          value : AST::Node? = nil

          if check(TokenType::KeyIndicator)
            # Explicit key: ? key : value
            advance
            skip_flow_whitespace

            # Parse key (or empty key)
            if check(TokenType::ValueIndicator) || check(TokenType::FlowSeparator) || check(TokenType::MappingEnd)
              key = AST::ScalarNode.new("")
              key.start_location = @current_token.location
              key.end_location = @current_token.location
            else
              key = parse_flow_node
            end

            skip_flow_whitespace

            # Parse value if there's a colon
            if check(TokenType::ValueIndicator)
              advance
              skip_flow_whitespace

              unless check(TokenType::FlowSeparator) || check(TokenType::MappingEnd)
                value = parse_flow_node
              end
            end
          elsif check(TokenType::ValueIndicator)
            # Empty key: : value
            key = AST::ScalarNode.new("")
            key.start_location = @current_token.location
            key.end_location = @current_token.location

            advance
            skip_flow_whitespace

            unless check(TokenType::FlowSeparator) || check(TokenType::MappingEnd)
              value = parse_flow_node
            end
          else
            # Regular key: value
            key = parse_flow_node
            skip_flow_whitespace

            # Expect colon (or handle :value case where : is adjacent to value)
            if check(TokenType::ValueIndicator)
              advance
              skip_flow_whitespace

              unless check(TokenType::FlowSeparator) || check(TokenType::MappingEnd)
                value = parse_flow_node
              end
            elsif check(TokenType::Scalar) && @current_token.value.starts_with?(":")
              # Handle case like { "key":value } where :value was lexed as a scalar
              # Split it into value indicator + value
              scalar_value = @current_token.value[1..]
              advance

              if !scalar_value.empty?
                node = AST::ScalarNode.new(scalar_value, AST::ScalarStyle::Plain)
                node.start_location = @current_token.location
                node.end_location = @current_token.location
                value = node
              end
            end
          end

          mapping.entries << AST::MappingEntry.new(key: key, value: value)

          skip_flow_whitespace

          if check(TokenType::FlowSeparator)
            advance
            skip_flow_whitespace
            # Allow trailing comma
            break if check(TokenType::MappingEnd)
          else
            break
          end
        end
      end

      expect(TokenType::MappingEnd)
      mapping.end_location = @current_token.location
      mapping
    end

    private def parse_flow_node : AST::Node
      skip_flow_whitespace

      # Check for anchor/tag/alias
      anchor, tag, alias_node = parse_value_properties
      return alias_node if alias_node

      # Skip whitespace after properties (tag/anchor may be on different line than value)
      skip_flow_whitespace

      node = case @current_token.type
             when TokenType::Scalar
               parse_scalar
             when TokenType::SequenceStart
               parse_flow_sequence
             when TokenType::MappingStart
               parse_flow_mapping
             else
               # Empty value
               AST::ScalarNode.new("")
             end

      if anchor
        node.anchor = anchor
        @anchors[anchor] = node
      end
      if tag
        node.tag = tag
      end

      node
    end

    private def parse_block_scalar(parent_indent : Int32 = 0) : AST::ScalarNode
      header = @current_token
      loc = header.location
      advance

      # Parse header to determine style and modifiers
      header_value = header.value
      style = if header_value.starts_with?("|")
                AST::ScalarStyle::Literal
              else
                AST::ScalarStyle::Folded
              end

      # Parse chomping indicator and explicit indentation
      chomping = :clip # default
      explicit_indent = 0

      header_value[1..].each_char do |c|
        case c
        when '-'
          chomping = :strip
        when '+'
          chomping = :keep
        when '1'..'9'
          explicit_indent = c.to_i
        end
      end

      # Skip comment on header line (but not the newline yet)
      if check(TokenType::Comment)
        advance
      end

      # Must have a newline after header
      unless check(TokenType::Newline) || check(TokenType::StreamEnd)
        raise ParseError.new("Expected newline after block scalar header", @current_token.location)
      end

      # Skip the newline to get to content
      advance if check(TokenType::Newline)

      # Collect lines with their raw content (preserving indentation info)
      lines = [] of {content: String, indent: Int32, is_empty: Bool}
      # Explicit indent specifies the additional indentation relative to parent context
      # Content indent is calculated as parent_indent + explicit_indent (in column terms)
      # If no explicit indent, auto-detect from first content line
      if explicit_indent > 0
        # explicit_indent is relative to parent; parent_indent is already 1-indexed column
        content_indent = parent_indent + explicit_indent
        min_content_indent = content_indent
      else
        content_indent = -1                    # Will be auto-detected from first content line
        min_content_indent = parent_indent + 1 # At minimum, more indented than parent
      end

      while !check(TokenType::StreamEnd) && !check(TokenType::DocumentStart) && !check(TokenType::DocumentEnd)
        if check(TokenType::Newline)
          # Empty/whitespace-only line
          # The column tells us how much whitespace was on the line
          ws_col = @current_token.location.column
          if content_indent > 0 && ws_col > content_indent
            # Line has extra whitespace beyond content indent - preserve it
            extra_ws = " " * (ws_col - content_indent)
            lines << {content: extra_ws, indent: ws_col, is_empty: false}
          else
            lines << {content: "", indent: 0, is_empty: true}
          end
          advance
        elsif check(TokenType::Scalar) || check(TokenType::Comment) ||
              check(TokenType::Anchor) || check(TokenType::Alias) ||
              check(TokenType::Tag) || check(TokenType::SequenceEntry) ||
              check(TokenType::KeyIndicator) || check(TokenType::ValueIndicator) ||
              check(TokenType::Directive)
          # In block scalars, all indicators are literal content
          line_col = @current_token.location.column
          line_value = case @current_token.type
                       when TokenType::Comment
                         "#" + @current_token.value
                       when TokenType::Anchor
                         "&" + @current_token.value
                       when TokenType::Alias
                         "*" + @current_token.value
                       when TokenType::Tag
                         @current_token.value
                       when TokenType::SequenceEntry
                         "-"
                       when TokenType::KeyIndicator
                         "?"
                       when TokenType::ValueIndicator
                         ":"
                       when TokenType::Directive
                         @current_token.value # Already includes %
                       else
                         @current_token.value
                       end

          # Line must be at or above minimum content indent
          if line_col < min_content_indent
            break
          end

          # Auto-detect content indentation from first content line
          if content_indent < 0
            content_indent = line_col
          end

          # Check if we've dedented below auto-detected content level
          if line_col < content_indent
            break
          end

          # Calculate extra indentation (for more-indented lines)
          extra_indent = line_col > content_indent ? line_col - content_indent : 0

          line_content = " " * extra_indent + line_value
          lines << {content: line_content, indent: line_col, is_empty: false}
          advance

          # Consume the newline after this line
          if check(TokenType::Newline)
            advance
          else
            break
          end
        else
          break
        end
      end

      # If no content at all, return empty scalar with appropriate trailing
      if lines.empty? || lines.all?(&.[:is_empty])
        result = chomping == :keep ? "\n" * lines.size : ""
        node = AST::ScalarNode.new(result, style)
        node.start_location = loc
        node.end_location = @current_token.location
        return node
      end

      # Build result based on style
      result = if style == AST::ScalarStyle::Literal
                 # Literal: preserve all newlines between content lines
                 build_literal_scalar(lines, chomping)
               else
                 # Folded: fold single newlines to spaces, preserve multiple
                 build_folded_scalar(lines, chomping)
               end

      node = AST::ScalarNode.new(result, style)
      node.start_location = loc
      node.end_location = @current_token.location
      node
    end

    private def build_literal_scalar(lines : Array({content: String, indent: Int32, is_empty: Bool}), chomping : Symbol) : String
      # Find last non-empty line for chomping
      last_content_idx = lines.rindex { |l| !l[:is_empty] } || -1

      result = String.build do |str|
        lines.each_with_index do |line, idx|
          # Skip trailing empty lines unless keeping
          next if idx > last_content_idx && chomping != :keep

          if line[:is_empty]
            str << "\n"
          else
            str << line[:content]
            # Add newline after content lines (except the last one for strip mode)
            if idx < last_content_idx || chomping != :strip
              str << "\n"
            end
          end
        end

        # For strip mode, we don't add trailing newline (handled above)
        # For clip mode, we added exactly one newline after last content
        # For keep mode, we added all trailing empty lines plus newline after last content
      end

      result
    end

    private def build_folded_scalar(lines : Array({content: String, indent: Int32, is_empty: Bool}), chomping : Symbol) : String
      # Find last non-empty line for chomping
      last_content_idx = lines.rindex { |l| !l[:is_empty] } || -1

      result = String.build do |str|
        prev_empty = false
        prev_more_indented = false
        had_content = false
        had_regular_content = false # Track if we had non-more-indented content

        lines.each_with_index do |line, idx|
          # Skip trailing empty lines unless keeping
          next if idx > last_content_idx && chomping != :keep

          if line[:is_empty]
            # Empty lines in folded scalars:
            # - Preserve as newlines
            str << "\n"
            prev_empty = true
          else
            is_more_indented = line[:content].starts_with?(" ")

            # Add separator between content lines
            if had_content && !prev_empty
              if prev_more_indented || is_more_indented
                str << "\n"
              else
                str << " "
              end
            elsif prev_empty && had_content
              # After empty line, add extra newline when:
              # - Transitioning to more-indented from regular content
              # - Transitioning from more-indented to regular content
              if (had_regular_content && is_more_indented) || (prev_more_indented && !is_more_indented)
                str << "\n"
              end
            end

            str << line[:content]
            prev_empty = false
            prev_more_indented = is_more_indented
            had_content = true
            if !is_more_indented
              had_regular_content = true
            end
          end
        end

        # Apply chomping for final newline
        case chomping
        when :clip, :keep
          str << "\n"
        when :strip
          # No trailing newline
        end
      end

      result
    end

    private def parse_scalar : AST::ScalarNode
      token = @current_token
      advance

      style = case token.scalar_style
              when ScalarTokenStyle::SingleQuoted
                AST::ScalarStyle::SingleQuoted
              when ScalarTokenStyle::DoubleQuoted
                AST::ScalarStyle::DoubleQuoted
              else
                AST::ScalarStyle::Plain
              end

      node = AST::ScalarNode.new(token.value, style)
      node.start_location = token.location
      node.end_location = token.location
      node
    end

    private def advance : Token
      previous = @current_token
      @current_token = @lexer.next_token
      previous
    end

    private def check(type : TokenType) : Bool
      @current_token.type == type
    end

    private def expect(type : TokenType) : Token
      if check(type)
        advance
      else
        raise ParseError.new(
          "Expected #{type}, got #{@current_token.type}",
          @current_token.location
        )
      end
    end

    private def skip_directives : Nil
      while check(TokenType::Directive) || check(TokenType::Newline) || check(TokenType::Comment)
        advance
      end
    end

    private def skip_directives_with_validation(after_document_end_or_first : Bool) : Bool
      had_directives = false

      while check(TokenType::Directive) || check(TokenType::Newline) || check(TokenType::Comment)
        if check(TokenType::Directive)
          had_directives = true
        end
        advance
      end

      had_directives
    end

    private def skip_comments_and_newlines : Nil
      while check(TokenType::Newline) || check(TokenType::Comment)
        advance
      end
    end

    private def skip_whitespace_tokens : Nil
      # Currently no whitespace tokens - handled by lexer
    end

    private def skip_flow_whitespace : Nil
      while check(TokenType::Newline) || check(TokenType::Comment)
        advance
      end
    end
  end
end
