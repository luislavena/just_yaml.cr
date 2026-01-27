require "./just_yaml/location"
require "./just_yaml/error"
require "./just_yaml/token"
require "./just_yaml/lexer"
require "./just_yaml/ast"
require "./just_yaml/parser"
require "./just_yaml/resolver"

module JustYAML
  VERSION = "0.1.0"

  # Parse YAML string to AST (preserves comments)
  def self.parse(input : String) : AST::StreamNode
    parser = Parser.new(input)
    parser.parse
  end

  # Parse and resolve to Crystal types (loses comments)
  def self.load(input : String) : Any
    ast = parse(input)
    resolver = Resolver.new
    resolver.resolve(ast)
  end
end
