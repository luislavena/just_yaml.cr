# JustYAML - Crystal YAML Parser Specification

A pure Crystal YAML 1.2 parser with comment preservation.

## Goals

- Pure Crystal implementation with no external dependencies
- YAML 1.2 specification compliance
- Comment preservation for round-trip parsing
- Full support for anchors, aliases, and merge keys
- Strict parsing with detailed error messages
- Minimal, focused API

## Architecture

```
Input String → Lexer → Tokens → Parser → AST → Serializer → Output String
                                          ↓
                                       Resolver → Crystal Types
```

### Phase 1: Lexing

The `Lexer` converts raw YAML text into a stream of `Token` objects. Each token
carries its type, value, and source location. Comments become tokens rather than
being discarded.

### Phase 2: Parsing

The `Parser` consumes tokens and builds an Abstract Syntax Tree (AST). The AST
preserves structure and comments. Anchors are recorded; aliases reference them.

### Phase 3a: Serialization

The `Serializer` converts the AST back to YAML text, preserving comments and
applying formatting rules.

### Phase 3b: Resolution

The `Resolver` converts the AST to native Crystal types (`Hash`, `Array`,
`String`, etc.) with anchors/aliases resolved.

## Module structure

```
JustYAML
├── Lexer (tokenization)
├── Parser (AST construction)
├── AST (node types)
├── Serializer (YAML output)
├── Resolver (to Crystal types)
└── Error (exception types)
```

## Lexer

Uses `Char::Reader` for efficient UTF-8 scanning.

### Token types

```
# Structure
STREAM_START, STREAM_END
DOCUMENT_START (---), DOCUMENT_END (...)
INDENT, DEDENT, NEWLINE

# Indicators
KEY_INDICATOR (?), VALUE_INDICATOR (:)
SEQUENCE_ENTRY (-)
MAPPING_START ({), MAPPING_END (})
SEQUENCE_START ([), SEQUENCE_END (])
FLOW_SEPARATOR (,)

# Content
SCALAR (plain, single-quoted, double-quoted, literal, folded)
ANCHOR (&name), ALIAS (*name), TAG (!tag)
COMMENT (#...)

# Directives
DIRECTIVE (%YAML, %TAG)
```

### LexerContext

Tracks:
- Current position, line, column
- Mode stack: `BLOCK_KEY`, `BLOCK_VALUE`, `FLOW_SEQUENCE`, `FLOW_MAPPING`
- Indent stack for block structure
- Flow depth for nested `[]` and `{}`

### Scanner implementation

```crystal
class Lexer
  @reader : Char::Reader
  @line : Int32
  @column : Int32

  def initialize(input : String)
    @reader = Char::Reader.new(input)
    @line = 1
    @column = 1
  end

  private def current_char : Char
    @reader.current_char
  end

  private def peek_char : Char
    @reader.peek_next_char
  end

  private def advance : Char
    char = @reader.current_char
    @reader.next_char
    if char == '\n'
      @line += 1
      @column = 1
    else
      @column += 1
    end
    char
  end
end
```

### Scanner order

The lexer tries scanners in priority order:

1. Indentation (newlines, INDENT/DEDENT)
2. Double-quoted scalars
3. Single-quoted scalars
4. Document markers (---, ...)
5. Directives (%YAML, %TAG)
6. Tags (!!, !, custom)
7. Anchors (&name)
8. Aliases (*name)
9. Collection indicators ([ ] { })
10. Literal block scalars (|)
11. Folded block scalars (>)
12. Comments (#)
13. Plain scalars (fallback)

## AST nodes

### Base structure

```crystal
abstract class Node
  property start_location : Location
  property end_location : Location
  property leading_comments : Array(Comment)
  property trailing_comment : Comment?
  property anchor : String?
  property tag : String?
end

record Location, line : Int32, column : Int32
record Comment, text : String, location : Location
```

### Node types

```crystal
class StreamNode < Node
  property documents : Array(DocumentNode)
end

class DocumentNode < Node
  property root : Node?          # nil for empty documents
  property explicit_start : Bool # had explicit ---
  property explicit_end : Bool   # had explicit ...
end

class ScalarNode < Node
  property value : String
  property style : ScalarStyle   # :plain, :single_quoted,
                                 # :double_quoted, :literal, :folded
end

class SequenceNode < Node
  property items : Array(Node)
  property style : CollectionStyle  # :block, :flow
end

class MappingNode < Node
  property entries : Array(MappingEntry)
  property style : CollectionStyle  # :block, :flow
end

record MappingEntry,
  key : Node,
  value : Node?,                    # nil for implicit null
  key_comments : Array(Comment)     # comments between key and value
```

### Comment attachment rules

- Leading comments: blank-line-separated comments before a node
- Trailing comment: same-line comment after a node
- Key comments: comments between a mapping key and its value

## Parser

Uses recursive descent with context-aware parsing for block vs flow styles.

### Structure

```crystal
class Parser
  @lexer : Lexer
  @current_token : Token
  @anchors : Hash(String, Node)  # for later resolution

  def parse : StreamNode
    stream = StreamNode.new
    while !at_end?
      stream.documents << parse_document
    end
    stream
  end
end
```

### Key parsing methods

```crystal
private def parse_document : DocumentNode
private def parse_node : Node
private def parse_block_mapping : MappingNode
private def parse_block_sequence : SequenceNode
private def parse_flow_mapping : MappingNode
private def parse_flow_sequence : SequenceNode
private def parse_scalar : ScalarNode
private def parse_anchor : Node        # parses &anchor then the node
private def parse_alias : AliasNode    # temporary, resolved later
```

### Comment collection

```crystal
private def collect_leading_comments : Array(Comment)
  # Gather consecutive COMMENT tokens before content
end

private def collect_trailing_comment : Comment?
  # Check for same-line COMMENT after content
end
```

### Anchor handling

- When `&anchor` is seen, parse the following node and record it in `@anchors`
- When `*alias` is seen, create a temporary `AliasNode` with the reference name
- After parsing completes, a resolution pass replaces `AliasNode` with clones

## Serializer

Converts AST back to YAML text with comments preserved.

```crystal
class Serializer
  property indent_size : Int32 = 2

  def serialize(node : StreamNode) : String
end
```

### Serialization rules

- Output leading comments before each node (with proper indentation)
- Output trailing comments on the same line after content
- Respect `ScalarStyle` and `CollectionStyle` from the original parse
- Use block style for complex nested structures, flow for simple inline
- Handle multi-line scalars with literal (`|`) or folded (`>`) indicators

## Resolver

Converts AST to native Crystal types.

```crystal
class Resolver
  def resolve(node : StreamNode) : Array(Any)
  def resolve(node : DocumentNode) : Any
  def resolve(node : Node) : Any
end

alias Any = Nil | Bool | Int64 | Float64 | String |
            Array(Any) | Hash(String, Any)
```

### Resolution process

1. Walk the AST depth-first
2. Replace `AliasNode` references with resolved anchor values (deep clone)
3. Process merge keys (`<<`) by combining mappings
4. Apply YAML 1.2 type rules to scalars (null, bool, int, float, string)

## Error handling

All errors include precise source locations.

```crystal
module JustYAML
  class Error < Exception
    getter location : Location?

    def initialize(message, @location = nil)
      if @location
        super("#{message} at line #{@location.line}, column #{@location.column}")
      else
        super(message)
      end
    end
  end

  class LexerError < Error; end
  class ParseError < Error; end
  class ResolveError < Error; end
end
```

### Common error cases

Lexer errors:
- Unterminated quoted string
- Invalid escape sequence in double-quoted string
- Invalid character in plain scalar
- Tab used for indentation (YAML 1.2 forbids this)

Parser errors:
- Unexpected token (expected key, got sequence entry)
- Invalid indentation (dedent to non-existent level)
- Duplicate key in mapping
- Missing value after key indicator

Resolution errors:
- Undefined alias reference (`*unknown`)
- Circular alias reference without anchor

## Testing strategy

### YAML test suite integration

Use the 333 test cases from yaml-test-suite:

```crystal
# spec/yaml_test_suite_spec.cr
describe "YAML Test Suite" do
  Dir.glob("../yaml-test-suite/*/").each do |test_dir|
    id = File.basename(test_dir)

    # Skip metadata directories
    next if id == "tags" || id == "name"

    context id do
      has_error = File.exists?(File.join(test_dir, "error"))
      input = File.read(File.join(test_dir, "in.yaml"))

      if has_error
        it "rejects invalid YAML" do
          expect_raises(JustYAML::Error) { JustYAML.parse(input) }
        end
      else
        it "parses valid YAML" do
          ast = JustYAML.parse(input)
          ast.should_not be_nil
        end

        if File.exists?(File.join(test_dir, "in.json"))
          it "resolves to expected value" do
            expected = JSON.parse(File.read(File.join(test_dir, "in.json")))
            actual = JustYAML.load(input)
            actual.should eq(expected)
          end
        end
      end
    end
  end
end
```

### Unit specs by component

- `spec/lexer_spec.cr` - token generation, edge cases
- `spec/parser_spec.cr` - AST construction
- `spec/serializer_spec.cr` - round-trip preservation
- `spec/resolver_spec.cr` - type coercion, anchors, merge keys
- `spec/comment_spec.cr` - comment preservation specifically

### Priority test categories

From yaml-test-suite/tags/:

1. `spec` (116 tests) - core specification compliance
2. `comment` (41 tests) - critical for comment preservation goal
3. `mapping`, `sequence` (126, 84 tests) - data structures
4. `anchor`, `alias` (27, 20 tests) - reference handling
5. `error` (76 tests) - proper rejection of invalid input

## Public API

```crystal
module JustYAML
  # Parse YAML string to AST (preserves comments)
  def self.parse(input : String) : AST::StreamNode

  # Parse and resolve to Crystal types (loses comments)
  def self.load(input : String) : Any

  # Serialize AST back to YAML string
  def self.dump(node : AST::StreamNode, indent : Int32 = 2) : String
end
```

## Implementation order

### Step 1: End-to-end smoke test

Build a minimal vertical slice through the entire stack to validate the
architecture before expanding functionality.

Target: Parse a simple YAML document and resolve it correctly.

```yaml
name: JustYAML
version: 1.0
```

Expected result:
```crystal
{"name" => "JustYAML", "version" => "1.0"}
```

This step includes:
- Basic project structure (shard.yml, src/, spec/)
- Minimal Token types (SCALAR, VALUE_INDICATOR, NEWLINE, STREAM_END)
- Minimal Lexer (plain scalars, colon, newlines)
- Minimal AST (StreamNode, DocumentNode, MappingNode, ScalarNode)
- Minimal Parser (block mapping with scalar keys/values)
- Minimal Resolver (strings only, no type coercion)
- One passing spec that validates the full pipeline

### Step 2: Expand token types and lexer

- All token types
- Full scanner implementation with Char::Reader
- Quoted strings (single and double)
- Comments (captured as tokens)
- Block scalar indicators (|, >)
- Flow indicators ([], {}, comma)
- Anchors and aliases
- Document markers (---, ...)
- Directives

### Step 3: Complete AST nodes

- All node types with full properties
- Location tracking on all nodes
- Comment attachment (leading, trailing, key comments)

### Step 4: Full parser

- Block sequences
- Block mappings (including nested)
- Flow sequences
- Flow mappings
- Quoted scalars
- Block scalars (literal and folded)
- Anchor and alias parsing
- Document boundaries

### Step 5: Resolver

- YAML 1.2 scalar type resolution (null, bool, int, float, string)
- Anchor collection and alias resolution
- Merge key processing (<<)
- Circular reference detection

### Step 6: Serializer

- Basic YAML output
- Comment preservation in output
- Style preservation (block/flow, quote style)
- Proper indentation handling

### Step 7: Test suite integration

- Hook up yaml-test-suite
- Iterate through failures and fix edge cases
- Target: pass all non-error tests, reject all error tests
