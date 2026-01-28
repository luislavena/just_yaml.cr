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

      # Skip any directives before document
      skip_directives

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

      # Parse anchor, tag, or alias that precedes the actual node
      anchor, tag, alias_node = parse_node_properties

      return alias_node if alias_node

      # Skip newlines after anchor/tag (content may be on next line)
      skip_comments_and_newlines

      node = parse_node_content(min_indent)

      node.anchor = anchor
      node.tag = tag

      if anchor
        @anchors[anchor] = node
      end

      node
    end

    private def parse_node_properties : {String?, String?, AST::Node?}
      anchor : String? = nil
      tag : String? = nil

      # Handle anchor
      if check(TokenType::Anchor)
        anchor = @current_token.value
        advance
        skip_whitespace_tokens
      end

      # Handle tag
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

        return {nil, nil, resolved}
      end

      {anchor, tag, nil}
    end

    private def parse_node_content(min_indent : Int32) : AST::Node
      case @current_token.type
      when TokenType::SequenceEntry
        parse_block_sequence(min_indent)
      when TokenType::Scalar
        parse_mapping_or_scalar(min_indent)
      when TokenType::SequenceStart
        parse_flow_sequence
      when TokenType::MappingStart
        parse_flow_mapping
      when TokenType::BlockScalarHeader
        parse_block_scalar(min_indent)
      when TokenType::ValueIndicator
        # Implicit null key mapping (e.g., ": value")
        parse_block_mapping_with_null_key(min_indent)
      when TokenType::KeyIndicator
        # Explicit key mapping (e.g., "? key\n: value")
        parse_block_mapping_with_explicit_key(min_indent)
      else
        raise ParseError.new(
          "Unexpected token #{@current_token.type}",
          @current_token.location
        )
      end
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

          # Look ahead to verify this is a mapping entry (has ValueIndicator)
          # We need to check if a colon follows this scalar
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

        # Continue if another explicit key follows
        unless check(TokenType::KeyIndicator)
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

      # Handle anchor
      if check(TokenType::Anchor)
        anchor = @current_token.value
        advance
        skip_whitespace_tokens
      end

      # Handle tag
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
          scalar
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

        # Value must be more indented than key
        if next_col <= key_indent
          # Not a nested value, just null
          return nil
        end

        # Nested block content
        parse_nested_value(next_col, anchor, tag)
      when TokenType::StreamEnd
        nil
      else
        nil
      end
    end

    private def parse_nested_value(next_col : Int32, anchor : String?, tag : String?) : AST::Node?
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
          node = parse_nested_value(next_col, nested_anchor, nil)
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

    # Parse a flow sequence item, which might be an implicit mapping entry
    private def parse_flow_sequence_item : AST::Node
      skip_flow_whitespace
      start_loc = @current_token.location

      # Parse the first node
      first_node = parse_flow_node
      skip_flow_whitespace

      # Check if this is an implicit mapping (key: value)
      if check(TokenType::ValueIndicator)
        advance
        skip_flow_whitespace

        # Parse value
        value : AST::Node? = nil
        unless check(TokenType::FlowSeparator) || check(TokenType::SequenceEnd)
          value = parse_flow_node
        end

        # Create a mapping with single entry
        mapping = AST::MappingNode.new
        mapping.start_location = start_loc
        mapping.end_location = @current_token.location
        mapping.style = AST::CollectionStyle::Flow
        mapping.entries << AST::MappingEntry.new(key: first_node, value: value)
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
          # Parse key
          key = parse_flow_node
          skip_flow_whitespace

          # Expect colon (or handle :value case where : is adjacent to value)
          value : AST::Node? = nil
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
        elsif check(TokenType::Scalar) || check(TokenType::Comment)
          # In block scalars, comments are literal content (# is not special)
          line_col = @current_token.location.column
          line_value = if check(TokenType::Comment)
                         "#" + @current_token.value
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

        lines.each_with_index do |line, idx|
          # Skip trailing empty lines unless keeping
          next if idx > last_content_idx && chomping != :keep

          if line[:is_empty]
            str << "\n"
            prev_empty = true
          else
            is_more_indented = line[:content].starts_with?(" ")

            # Add separator between content lines
            if idx > 0 && !prev_empty
              if prev_more_indented || is_more_indented
                str << "\n"
              else
                str << " "
              end
            end

            str << line[:content]
            prev_empty = false
            prev_more_indented = is_more_indented
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
