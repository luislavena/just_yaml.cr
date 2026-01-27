# JustYAML

A pure Crystal YAML 1.2 parser with comment preservation for round-trip parsing.

## Why use JustYAML?

### Preserves comments

JustYAML is designed to preserve comments during parsing, enabling true round-trip editing of YAML files. Edit configuration files programmatically without losing valuable documentation.

```crystal
input = <<-YAML
# Server configuration
server:
  host: localhost  # Development only
  port: 8080
YAML

ast = JustYAML.parse(input)
output = JustYAML.dump(ast)
# Comments are preserved in the output
```

### Pure Crystal

JustYAML has zero dependencies. It's pure Crystal.

- **Just install**: No C extensions to compile, no libyaml required
- **Debuggable**: Step through the code with a debugger to understand exactly how your YAML is being parsed
- **Simple types**: Returns plain Crystal objects you can iterate over and inspect

### Compliant

Implements the YAML 1.2 specification with strict parsing and detailed error messages.

- Full support for anchors, aliases, and merge keys
- Block and flow collection styles
- All scalar styles: plain, single-quoted, double-quoted, literal, and folded

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     just_yaml:
       github: luislavena/just_yaml.cr
   ```

2. Run `shards install`

## Usage

### Basic parsing

```crystal
require "just_yaml"

# Parse YAML to native Crystal types
data = JustYAML.load(<<-YAML)
name: JustYAML
version: 1.0
features:
  - comment preservation
  - strict parsing
  - round-trip support
YAML

puts data["name"]     # => "JustYAML"
puts data["version"]  # => 1.0
```

### Comment preservation with AST

```crystal
require "just_yaml"

input = <<-YAML
# Application settings
app:
  name: MyApp      # Display name
  debug: false     # Enable for development

# Database configuration
database:
  host: localhost
  port: 5432
YAML

# Parse to AST (preserves comments)
ast = JustYAML.parse(input)

# Serialize back to YAML (comments preserved)
output = JustYAML.dump(ast)
puts output
```

### Working with anchors and aliases

```crystal
require "just_yaml"

data = JustYAML.load(<<-YAML)
defaults: &defaults
  adapter: postgres
  host: localhost

development:
  <<: *defaults
  database: dev_db

production:
  <<: *defaults
  database: prod_db
YAML

puts data["development"]["adapter"]  # => "postgres"
puts data["production"]["database"]  # => "prod_db"
```

### Error handling

JustYAML provides detailed error messages with precise source locations.

```crystal
require "just_yaml"

begin
  JustYAML.load("key: [unclosed")
rescue ex : JustYAML::ParseError
  puts ex.message  # => "Unexpected end of input at line 1, column 14"
end
```

## API reference

### Module methods

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

### Types

```crystal
# The Any type represents resolved YAML values
alias JustYAML::Any = Nil | Bool | Int64 | Float64 | String |
                      Array(Any) | Hash(String, Any)
```

### Exceptions

```crystal
JustYAML::Error         # Base exception class
JustYAML::LexerError    # Tokenization errors
JustYAML::ParseError    # AST construction errors
JustYAML::ResolveError  # Type resolution errors
```

All exceptions include the source location (line and column) where the error occurred.

## Development

### Running tests

```console
crystal spec
```

### Running YAML test suite

JustYAML is verified against the official [yaml-test-suite](https://github.com/yaml/yaml-test-suite). The tests are included as a git submodule.

1. Initialize the submodule:

   ```console
   git submodule update --init
   ```

2. Run the full test suite:

   ```console
   crystal spec
   ```

## Contributing

1. Fork it (<https://github.com/luislavena/just_yaml.cr/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Acknowledgments

This Crystal implementation was produced using [Claude Code](https://claude.ai/claude-code)
with the Opus model. The project is inspired by [justhtml](https://github.com/EmilStenstrom/justhtml),
a Python HTML5 parser, and its Crystal port [just_html.cr](https://github.com/luislavena/just_html.cr).

## License

MIT License. See [LICENSE](LICENSE) for details.

## Contributors

- [Luis Lavena](https://github.com/luislavena) - creator and maintainer
