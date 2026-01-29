module JustYAML
  class Serializer
    property indent_size : Int32 = 2

    def serialize(node : AST::StreamNode) : String
      String.build do |io|
        node.documents.each_with_index do |doc, index|
          serialize_document(doc, io, index > 0)
        end
      end
    end

    private def serialize_document(node : AST::DocumentNode, io : IO, needs_separator : Bool) : Nil
      # Output document start marker if explicit or needed for separation
      if node.explicit_start || needs_separator
        io << "---"
        io << "\n" if node.root
      end

      # Serialize leading comments
      serialize_comments(node.leading_comments, io, 0)

      # Serialize document content
      if root = node.root
        serialize_node(root, io, 0, context: :block)
        io << "\n"
      end

      # Output document end marker if explicit
      if node.explicit_end
        io << "...\n"
      end
    end

    private def serialize_node(node : AST::Node, io : IO, indent : Int32, context : Symbol) : Nil
      # Serialize anchor if present
      if anchor = node.anchor
        io << "&" << anchor << " "
      end

      # Serialize tag if present
      if tag = node.tag
        io << tag << " "
      end

      case node
      when AST::ScalarNode
        serialize_scalar(node, io, indent, context)
      when AST::SequenceNode
        serialize_sequence(node, io, indent, context)
      when AST::MappingNode
        serialize_mapping(node, io, indent, context)
      end

      # Serialize trailing comment
      if comment = node.trailing_comment
        io << " #" << comment.text
      end
    end

    private def serialize_scalar(node : AST::ScalarNode, io : IO, indent : Int32, context : Symbol) : Nil
      value = node.value

      case node.style
      when AST::ScalarStyle::SingleQuoted
        io << "'" << value.gsub("'", "''") << "'"
      when AST::ScalarStyle::DoubleQuoted
        io << "\"" << escape_double_quoted(value) << "\""
      when AST::ScalarStyle::Literal
        serialize_literal_scalar(value, io, indent)
      when AST::ScalarStyle::Folded
        serialize_folded_scalar(value, io, indent)
      else # Plain
        if needs_quoting?(value)
          io << "\"" << escape_double_quoted(value) << "\""
        else
          io << value
        end
      end
    end

    private def escape_double_quoted(value : String) : String
      value
        .gsub("\\", "\\\\")
        .gsub("\"", "\\\"")
        .gsub("\n", "\\n")
        .gsub("\r", "\\r")
        .gsub("\t", "\\t")
    end

    private def needs_quoting?(value : String) : Bool
      return true if value.empty?

      # Check for special values that need quoting
      special_values = ["null", "Null", "NULL", "~",
                        "true", "True", "TRUE",
                        "false", "False", "FALSE",
                        ".inf", "-.inf", "+.inf",
                        ".nan", ".NaN", ".NAN"]

      return true if special_values.includes?(value)

      # Check for indicators at start
      first_char = value[0]?
      return true if first_char.in?('&', '*', '!', '|', '>', '\'', '"', '%', '@', '`', '#', ',', '[', ']', '{', '}', '?', '-', ':')

      # Check for special characters that require quoting
      value.each_char do |char|
        return true if char == ':' || char == '#' || char == '\n'
      end

      false
    end

    private def serialize_literal_scalar(value : String, io : IO, indent : Int32) : Nil
      io << "|"
      io << "\n"

      value.each_line(chomp: false) do |line|
        io << " " * (indent + @indent_size)
        io << line.chomp
        io << "\n"
      end
    end

    private def serialize_folded_scalar(value : String, io : IO, indent : Int32) : Nil
      io << ">"
      io << "\n"

      value.each_line(chomp: false) do |line|
        io << " " * (indent + @indent_size)
        io << line.chomp
        io << "\n"
      end
    end

    private def serialize_sequence(node : AST::SequenceNode, io : IO, indent : Int32, context : Symbol) : Nil
      if node.style == AST::CollectionStyle::Flow || node.items.empty?
        serialize_flow_sequence(node, io)
      else
        serialize_block_sequence(node, io, indent, context)
      end
    end

    private def serialize_flow_sequence(node : AST::SequenceNode, io : IO) : Nil
      io << "["
      node.items.each_with_index do |item, index|
        io << ", " if index > 0
        serialize_node(item, io, 0, context: :flow)
      end
      io << "]"
    end

    private def serialize_block_sequence(node : AST::SequenceNode, io : IO, indent : Int32, context : Symbol) : Nil
      # If this is a value in a mapping, we need a newline before the first item
      if context == :mapping_value
        io << "\n"
      end

      node.items.each_with_index do |item, index|
        # Serialize leading comments for item
        serialize_comments(item.leading_comments, io, indent)

        # Output the sequence entry
        io << " " * indent if indent > 0 || context == :mapping_value
        io << "- "

        case item
        when AST::MappingNode
          if item.style == AST::CollectionStyle::Block && !item.entries.empty?
            # Block mapping as sequence item - first entry on same line as dash
            first_entry = item.entries.first
            serialize_mapping_entry_inline(first_entry, io, indent + @indent_size)

            # Remaining entries on new lines
            item.entries.skip(1).each do |entry|
              io << "\n"
              io << " " * (indent + @indent_size)
              serialize_mapping_entry(entry, io, indent + @indent_size)
            end
          else
            serialize_node(item, io, indent + @indent_size, context: :sequence_item)
          end
        when AST::SequenceNode
          if item.style == AST::CollectionStyle::Block
            serialize_node(item, io, indent + @indent_size, context: :sequence_item)
          else
            serialize_node(item, io, indent + @indent_size, context: :flow)
          end
        else
          serialize_node(item, io, indent + @indent_size, context: :sequence_item)
        end

        # Add newline between items, but not after the last one
        io << "\n" unless index == node.items.size - 1
      end
    end

    private def serialize_mapping(node : AST::MappingNode, io : IO, indent : Int32, context : Symbol) : Nil
      if node.style == AST::CollectionStyle::Flow || node.entries.empty?
        serialize_flow_mapping(node, io)
      else
        serialize_block_mapping(node, io, indent, context)
      end
    end

    private def serialize_flow_mapping(node : AST::MappingNode, io : IO) : Nil
      io << "{"
      node.entries.each_with_index do |entry, index|
        io << ", " if index > 0
        serialize_node(entry.key, io, 0, context: :flow)
        io << ": "
        if value = entry.value
          serialize_node(value, io, 0, context: :flow)
        end
      end
      io << "}"
    end

    private def serialize_block_mapping(node : AST::MappingNode, io : IO, indent : Int32, context : Symbol) : Nil
      # If this is a value in a mapping, we need a newline before the first entry
      if context == :mapping_value
        io << "\n"
      end

      node.entries.each_with_index do |entry, index|
        # Serialize leading comments
        serialize_comments(entry.key.leading_comments, io, indent)

        io << " " * indent if indent > 0 || context == :mapping_value
        serialize_mapping_entry(entry, io, indent)
        # Add newline between entries, but not after the last one
        io << "\n" unless index == node.entries.size - 1
      end
    end

    private def serialize_mapping_entry(entry : AST::MappingEntry, io : IO, indent : Int32) : Nil
      # Serialize key
      serialize_node(entry.key, io, indent, context: :mapping_key)
      io << ":"

      # Serialize key comments
      entry.key_comments.each do |comment|
        io << " #" << comment.text
      end

      # Serialize value
      if value = entry.value
        case value
        when AST::MappingNode
          if value.style == AST::CollectionStyle::Block && !value.entries.empty?
            serialize_node(value, io, indent + @indent_size, context: :mapping_value)
          else
            io << " "
            serialize_node(value, io, indent, context: :flow)
          end
        when AST::SequenceNode
          if value.style == AST::CollectionStyle::Block && !value.items.empty?
            serialize_node(value, io, indent + @indent_size, context: :mapping_value)
          else
            io << " "
            serialize_node(value, io, indent, context: :flow)
          end
        else
          io << " "
          serialize_node(value, io, indent, context: :scalar_value)
        end
      end
    end

    private def serialize_mapping_entry_inline(entry : AST::MappingEntry, io : IO, indent : Int32) : Nil
      serialize_node(entry.key, io, indent, context: :mapping_key)
      io << ":"

      if value = entry.value
        io << " "
        case value
        when AST::MappingNode, AST::SequenceNode
          if value.style == AST::CollectionStyle::Block
            serialize_node(value, io, indent + @indent_size, context: :mapping_value)
          else
            serialize_node(value, io, indent, context: :flow)
          end
        else
          serialize_node(value, io, indent, context: :scalar_value)
        end
      end
    end

    private def serialize_comments(comments : Array(AST::Comment), io : IO, indent : Int32) : Nil
      comments.each do |comment|
        # Output preceding blank lines
        comment.preceding_blank_lines.times { io << "\n" }
        io << " " * indent
        io << "#" << comment.text << "\n"
      end
    end
  end
end
