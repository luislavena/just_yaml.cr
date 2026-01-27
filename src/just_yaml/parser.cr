module JustYAML
  class Parser
    @lexer : Lexer
    @current_token : Token

    def initialize(input : String)
      @lexer = Lexer.new(input)
      @current_token = @lexer.next_token
    end

    def parse : AST::StreamNode
      stream = AST::StreamNode.new
      stream.start_location = @current_token.location

      expect(TokenType::StreamStart)

      skip_newlines

      unless check(TokenType::StreamEnd)
        stream.documents << parse_document
      end

      stream.end_location = @current_token.location
      stream
    end

    private def parse_document : AST::DocumentNode
      doc = AST::DocumentNode.new
      doc.start_location = @current_token.location

      doc.root = parse_node

      doc.end_location = @current_token.location
      doc
    end

    private def parse_node : AST::Node
      case @current_token.type
      when TokenType::Scalar
        parse_mapping_or_scalar
      else
        raise ParseError.new(
          "Unexpected token #{@current_token.type}",
          @current_token.location
        )
      end
    end

    private def parse_mapping_or_scalar : AST::Node
      first_scalar = parse_scalar
      skip_whitespace_tokens

      if check(TokenType::ValueIndicator)
        parse_block_mapping(first_scalar)
      else
        first_scalar
      end
    end

    private def parse_block_mapping(first_key : AST::ScalarNode) : AST::MappingNode
      mapping = AST::MappingNode.new
      mapping.start_location = first_key.start_location

      key = first_key

      loop do
        expect(TokenType::ValueIndicator)
        skip_whitespace_tokens

        value = if check(TokenType::Scalar)
                  parse_scalar
                else
                  nil
                end

        mapping.entries << AST::MappingEntry.new(key: key, value: value)

        skip_newlines

        break if check(TokenType::StreamEnd)

        unless check(TokenType::Scalar)
          raise ParseError.new(
            "Expected mapping key, got #{@current_token.type}",
            @current_token.location
          )
        end

        key = parse_scalar
        skip_whitespace_tokens
      end

      mapping.end_location = @current_token.location
      mapping
    end

    private def parse_scalar : AST::ScalarNode
      token = @current_token
      advance
      node = AST::ScalarNode.new(token.value)
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

    private def skip_newlines : Nil
      while check(TokenType::Newline)
        advance
      end
    end

    private def skip_whitespace_tokens : Nil
      # Currently no whitespace tokens, but placeholder for future
    end
  end
end
