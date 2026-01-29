# Agent guidelines

## Overview

Pure Crystal YAML 1.2 parser with comment preservation for round-trip parsing.
Zero dependencies. Requires Crystal 1.16.0+.

## Architecture

```
Input → Lexer → Tokens → Parser → AST → Serializer → Output
                                    ↓
                                 Resolver → Crystal Types
```

### Source files

| File | Purpose |
|------|---------|
| `lexer.cr` | Tokenizer using `Char::Reader`, tracks flow level and indentation |
| `parser.cr` | AST construction, handles directives/anchors/tags/scalars/comments |
| `ast.cr` | Node types: `StreamNode`, `DocumentNode`, `ScalarNode`, `SequenceNode`, `MappingNode` |
| `resolver.cr` | AST to Crystal types (YAML 1.2 Core Schema) |
| `serializer.cr` | AST to YAML text, preserves comments and styles |
| `token.cr` | Token types and `Token` class |
| `location.cr` | Line/column tracking |
| `error.cr` | `LexerError`, `ParseError`, `ResolveError` |

### Test files

| File | Purpose |
|------|---------|
| `lexer_spec.cr` | Token scanning |
| `parser_spec.cr` | AST construction |
| `comment_spec.cr` | Comment preservation |
| `resolver_spec.cr` | Type resolution |
| `serializer_spec.cr` | Output generation |
| `roundtrip_spec.cr` | Parse-serialize cycles |
| `yaml_test_suite_spec.cr` | Official test suite |

## Commands

```bash
git submodule update --init       # Initialize yaml-test-suite
crystal spec                      # Run tests
crystal spec spec/lexer_spec.cr   # Run specific test
crystal tool format src/          # Format code
crystal tool format --check       # Verify formatting (CI)
```

## Guidelines

### Code style

- Run `crystal tool format` before committing
- Use specific exception types with source location in errors
- Reference YAML spec sections when implementing spec behavior

### Pull requests

1. All tests pass: `crystal spec`
2. Formatting verified: `crystal tool format --check`
3. Tests added for new functionality or bug fixes

### Commits

- 50 char subject, imperative mood, capitalized, no period
- Body explains what and why (wrap at 72 chars)

Examples from this repo:
- "Validate tag handles are defined with %TAG directive"
- "End plain scalar when comment is encountered"
