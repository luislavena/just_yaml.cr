module JustYAML
  alias Any = Nil | Bool | Int64 | Float64 | String | Array(Any) | Hash(String, Any)

  class Resolver
    # YAML 1.2 Core Schema type patterns
    private NULL_PATTERN    = /\A(?:null|Null|NULL|~)?\z/
    private TRUE_PATTERN    = /\A(?:true|True|TRUE)\z/
    private FALSE_PATTERN   = /\A(?:false|False|FALSE)\z/
    private INT_PATTERN     = /\A[-+]?[0-9]+\z/
    private INT_OCT_PATTERN = /\A0o[0-7]+\z/
    private INT_HEX_PATTERN = /\A0x[0-9a-fA-F]+\z/
    private FLOAT_PATTERN   = /\A[-+]?(?:\.[0-9]+|[0-9]+(?:\.[0-9]*)?)(?:[eE][-+]?[0-9]+)?\z/
    private INF_PATTERN     = /\A[-+]?\.(?:inf|Inf|INF)\z/
    private NAN_PATTERN     = /\A\.(?:nan|NaN|NAN)\z/

    def resolve(node : AST::StreamNode) : Any
      if node.documents.size == 1
        resolve(node.documents.first)
      else
        node.documents.map { |doc| resolve(doc).as(Any) }
      end
    end

    def resolve(node : AST::DocumentNode) : Any
      if root = node.root
        resolve(root)
      else
        nil
      end
    end

    def resolve(node : AST::Node) : Any
      case node
      when AST::ScalarNode
        resolve_scalar(node)
      when AST::SequenceNode
        resolve_sequence(node)
      when AST::MappingNode
        resolve_mapping(node)
      else
        raise ResolveError.new("Unknown node type: #{node.class}")
      end
    end

    private def resolve_scalar(node : AST::ScalarNode) : Any
      value = node.value

      # Quoted strings are always strings (no type coercion)
      if node.style == AST::ScalarStyle::SingleQuoted ||
         node.style == AST::ScalarStyle::DoubleQuoted
        return value
      end

      # Block scalars are always strings
      if node.style == AST::ScalarStyle::Literal ||
         node.style == AST::ScalarStyle::Folded
        return value
      end

      # Check for explicit tag
      if tag = node.tag
        return resolve_tagged_scalar(value, tag)
      end

      # YAML 1.2 Core Schema type resolution for plain scalars
      resolve_plain_scalar(value)
    end

    private def resolve_tagged_scalar(value : String, tag : String) : Any
      case tag
      when "!!null"
        nil
      when "!!bool"
        value.downcase == "true"
      when "!!int"
        value.to_i64
      when "!!float"
        value.to_f64
      when "!!str"
        value
      else
        # Unknown tag, return as string
        value
      end
    end

    private def resolve_plain_scalar(value : String) : Any
      # Null
      if NULL_PATTERN.matches?(value)
        return nil
      end

      # Boolean
      if TRUE_PATTERN.matches?(value)
        return true
      end
      if FALSE_PATTERN.matches?(value)
        return false
      end

      # Integer (decimal)
      if INT_PATTERN.matches?(value)
        return value.to_i64? || value
      end

      # Integer (octal)
      if INT_OCT_PATTERN.matches?(value)
        return value[2..].to_i64(8)
      end

      # Integer (hexadecimal)
      if INT_HEX_PATTERN.matches?(value)
        return value[2..].to_i64(16)
      end

      # Float (special values)
      if INF_PATTERN.matches?(value)
        return value.starts_with?("-") ? -Float64::INFINITY : Float64::INFINITY
      end
      if NAN_PATTERN.matches?(value)
        return Float64::NAN
      end

      # Float (regular)
      if FLOAT_PATTERN.matches?(value)
        result = value.to_f64?
        return result if result
      end

      # Default: string
      value
    end

    private def resolve_sequence(node : AST::SequenceNode) : Any
      node.items.map { |item| resolve(item).as(Any) }
    end

    private def resolve_mapping(node : AST::MappingNode) : Any
      result = {} of String => Any

      node.entries.each do |entry|
        key = resolve_key(entry.key)
        value = entry.value ? resolve(entry.value.not_nil!) : nil

        # Handle merge key (<<)
        if key == "<<" && value.is_a?(Hash)
          # Merge the referenced mapping
          value.each do |k, v|
            result[k] = v unless result.has_key?(k)
          end
        elsif key == "<<" && value.is_a?(Array)
          # Multiple merges
          value.each do |merged|
            if merged.is_a?(Hash)
              merged.each do |k, v|
                result[k.as(String)] = v unless result.has_key?(k.as(String))
              end
            end
          end
        else
          result[key] = value
        end
      end

      result
    end

    private def resolve_key(node : AST::Node) : String
      case node
      when AST::ScalarNode
        node.value
      when AST::SequenceNode
        # Convert sequence key to string representation
        resolved = resolve_sequence(node)
        any_to_key_string(resolved)
      when AST::MappingNode
        # Convert mapping key to string representation
        resolved = resolve_mapping(node)
        any_to_key_string(resolved)
      else
        raise ResolveError.new("Unsupported mapping key type", node.start_location)
      end
    end

    private def any_to_key_string(value : Any) : String
      case value
      when Nil
        "null"
      when Bool
        value.to_s
      when Int64, Float64
        value.to_s
      when String
        value.inspect
      when Array
        "[" + value.map { |v| any_to_key_string(v) }.join(", ") + "]"
      when Hash
        "{" + value.map { |k, v| "#{k.inspect}: #{any_to_key_string(v)}" }.join(", ") + "}"
      else
        value.to_s
      end
    end
  end
end
