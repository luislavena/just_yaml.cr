module JustYAML
  alias Any = Nil | Bool | Int64 | Float64 | String | Array(Any) | Hash(String, Any)

  class Resolver
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
      # For now, just return the string value
      # Full type resolution (null, bool, int, float) comes later
      node.value
    end

    private def resolve_sequence(node : AST::SequenceNode) : Any
      node.items.map { |item| resolve(item).as(Any) }
    end

    private def resolve_mapping(node : AST::MappingNode) : Any
      result = {} of String => Any
      node.entries.each do |entry|
        key = resolve_key(entry.key)
        value = entry.value ? resolve(entry.value.not_nil!) : nil
        result[key] = value
      end
      result
    end

    private def resolve_key(node : AST::Node) : String
      case node
      when AST::ScalarNode
        node.value
      else
        raise ResolveError.new("Non-scalar mapping keys not yet supported", node.start_location)
      end
    end
  end
end
