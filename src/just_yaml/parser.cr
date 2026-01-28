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

      while !check(TokenType::StreamEnd)
        skip_comments_and_newlines
        break if check(TokenType::StreamEnd)

        stream.documents << parse_document
      end

      stream.end_location = @current_token.location
      stream
    end

    private def parse_document : AST::DocumentNode
      doc = AST::DocumentNode.new
      doc.start_location = @current_token.location

      # Check for explicit document start
      if check(TokenType::DocumentStart)
        doc.explicit_start = true
        advance
        skip_comments_and_newlines
      end

      # Parse document content (if any)
      unless check(TokenType::StreamEnd) || check(TokenType::DocumentStart) || check(TokenType::DocumentEnd)
        doc.root = parse_node(0)
      end

      skip_comments_and_newlines

      # Check for explicit document end
      if check(TokenType::DocumentEnd)
        doc.explicit_end = true
        advance
        skip_comments_and_newlines
      end

      doc.end_location = @current_token.location
      doc
    end

    private def parse_node(min_indent : Int32) : AST::Node
      skip_comments_and_newlines

      # Handle anchor
      anchor : String? = nil
      if check(TokenType::Anchor)
        anchor = @current_token.value
        advance
        skip_whitespace_tokens
      end

      # Handle tag
      tag : String? = nil
      if check(TokenType::Tag)
        tag = @current_token.value
        advance
        skip_whitespace_tokens
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

        return resolved
      end

      node = case @current_token.type
             when TokenType::SequenceEntry
               parse_block_sequence(min_indent)
             when TokenType::Scalar
               parse_mapping_or_scalar(min_indent)
             when TokenType::SequenceStart
               parse_flow_sequence
             when TokenType::MappingStart
               parse_flow_mapping
             when TokenType::BlockScalarHeader
               parse_block_scalar
             else
               raise ParseError.new(
                 "Unexpected token #{@current_token.type}",
                 @current_token.location
               )
             end

      node.anchor = anchor
      node.tag = tag

      if anchor
        @anchors[anchor] = node
      end

      node
    end

    private def parse_mapping_or_scalar(min_indent : Int32) : AST::Node
      first_scalar = parse_scalar
      skip_whitespace_tokens

      if check(TokenType::ValueIndicator)
        parse_block_mapping(first_scalar, min_indent)
      else
        first_scalar
      end
    end

    private def parse_block_mapping(first_key : AST::ScalarNode, min_indent : Int32) : AST::MappingNode
      mapping = AST::MappingNode.new
      mapping.start_location = first_key.start_location
      mapping.style = AST::CollectionStyle::Block

      key_indent = first_key.start_location.column
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

        # Parse next key
        case @current_token.type
        when TokenType::Scalar
          next_key_col = @current_token.location.column
          break if next_key_col != key_indent

          key = parse_scalar
          skip_whitespace_tokens
          unless check(TokenType::ValueIndicator)
            break
          end
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

    private def parse_mapping_value(key_indent : Int32) : AST::Node?
      # Same line value
      case @current_token.type
      when TokenType::Scalar
        scalar = parse_scalar
        skip_whitespace_tokens

        if check(TokenType::ValueIndicator)
          # Nested mapping inline
          parse_block_mapping(scalar, key_indent)
        else
          scalar
        end
      when TokenType::SequenceStart
        parse_flow_sequence
      when TokenType::MappingStart
        parse_flow_mapping
      when TokenType::BlockScalarHeader
        parse_block_scalar
      when TokenType::Newline, TokenType::Comment
        # Value on next line (block collection)
        skip_comments_and_newlines

        return nil if check(TokenType::StreamEnd) ||
                      check(TokenType::DocumentStart) ||
                      check(TokenType::DocumentEnd)

        next_col = @current_token.location.column

        # Value must be more indented than key
        if next_col <= key_indent
          # Not a nested value, just null
          return nil
        end

        # Nested block content
        case @current_token.type
        when TokenType::SequenceEntry
          parse_block_sequence(next_col)
        when TokenType::Scalar
          # Check if this is a nested mapping
          scalar = parse_scalar
          skip_whitespace_tokens

          if check(TokenType::ValueIndicator)
            parse_block_mapping(scalar, next_col)
          else
            scalar
          end
        when TokenType::SequenceStart
          parse_flow_sequence
        when TokenType::MappingStart
          parse_flow_mapping
        else
          nil
        end
      when TokenType::StreamEnd
        nil
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
      case @current_token.type
      when TokenType::Scalar
        scalar = parse_scalar
        skip_whitespace_tokens

        if check(TokenType::ValueIndicator)
          # This is actually a mapping
          parse_block_mapping(scalar, entry_indent)
        else
          scalar
        end
      when TokenType::SequenceStart
        parse_flow_sequence
      when TokenType::MappingStart
        parse_flow_mapping
      when TokenType::SequenceEntry
        # Nested sequence
        parse_block_sequence(entry_indent)
      when TokenType::BlockScalarHeader
        parse_block_scalar
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
          item = parse_flow_node
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

    private def parse_flow_mapping : AST::MappingNode
      mapping = AST::MappingNode.new
      mapping.start_location = @current_token.location
      mapping.style = AST::CollectionStyle::Flow

      expect(TokenType::MappingStart)
      skip_flow_whitespace

      unless check(TokenType::MappingEnd)
        loop do
          # Parse key
          key = parse_flow_node
          skip_flow_whitespace

          # Expect colon
          value : AST::Node? = nil
          if check(TokenType::ValueIndicator)
            advance
            skip_flow_whitespace

            unless check(TokenType::FlowSeparator) || check(TokenType::MappingEnd)
              value = parse_flow_node
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

      case @current_token.type
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
    end

    private def parse_block_scalar : AST::ScalarNode
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

      # Skip to content
      skip_comments_and_newlines

      # Read block scalar content
      content = String.build do |str|
        # Determine content indentation from first non-empty line
        content_indent = @current_token.location.column

        while !check(TokenType::StreamEnd) && !check(TokenType::DocumentStart)
          line_col = @current_token.location.column
          break if line_col < content_indent && !check(TokenType::Newline)

          if check(TokenType::Scalar)
            str << @current_token.value
            advance
          elsif check(TokenType::Newline)
            str << "\n"
            advance
            skip_whitespace_tokens
          else
            break
          end
        end
      end

      # Process according to style
      processed = if style == AST::ScalarStyle::Folded
                    # Folded: replace single newlines with spaces
                    content.gsub(/(?<!\n)\n(?!\n)/, " ").strip
                  else
                    content.rstrip
                  end

      node = AST::ScalarNode.new(processed, style)
      node.start_location = loc
      node.end_location = @current_token.location
      node
    end

    private def parse_scalar : AST::ScalarNode
      token = @current_token
      advance

      style = AST::ScalarStyle::Plain

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
