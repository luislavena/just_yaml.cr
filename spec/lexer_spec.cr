require "./spec_helper"

describe JustYAML::TokenType do
  describe "enum values" do
    it "has structure tokens" do
      JustYAML::TokenType::StreamStart.should be_a(JustYAML::TokenType)
      JustYAML::TokenType::StreamEnd.should be_a(JustYAML::TokenType)
      JustYAML::TokenType::DocumentStart.should be_a(JustYAML::TokenType)
      JustYAML::TokenType::DocumentEnd.should be_a(JustYAML::TokenType)
      JustYAML::TokenType::Indent.should be_a(JustYAML::TokenType)
      JustYAML::TokenType::Dedent.should be_a(JustYAML::TokenType)
      JustYAML::TokenType::Newline.should be_a(JustYAML::TokenType)
    end

    it "has indicator tokens" do
      JustYAML::TokenType::KeyIndicator.should be_a(JustYAML::TokenType)
      JustYAML::TokenType::ValueIndicator.should be_a(JustYAML::TokenType)
      JustYAML::TokenType::SequenceEntry.should be_a(JustYAML::TokenType)
      JustYAML::TokenType::MappingStart.should be_a(JustYAML::TokenType)
      JustYAML::TokenType::MappingEnd.should be_a(JustYAML::TokenType)
      JustYAML::TokenType::SequenceStart.should be_a(JustYAML::TokenType)
      JustYAML::TokenType::SequenceEnd.should be_a(JustYAML::TokenType)
      JustYAML::TokenType::FlowSeparator.should be_a(JustYAML::TokenType)
    end

    it "has content tokens" do
      JustYAML::TokenType::Scalar.should be_a(JustYAML::TokenType)
      JustYAML::TokenType::Anchor.should be_a(JustYAML::TokenType)
      JustYAML::TokenType::Alias.should be_a(JustYAML::TokenType)
      JustYAML::TokenType::Tag.should be_a(JustYAML::TokenType)
    end

    it "has comment token" do
      JustYAML::TokenType::Comment.should be_a(JustYAML::TokenType)
    end

    it "has directive token" do
      JustYAML::TokenType::Directive.should be_a(JustYAML::TokenType)
    end
  end
end

describe JustYAML::Token do
  it "stores type, value, and location" do
    location = JustYAML::Location.new(1, 1)
    token = JustYAML::Token.new(JustYAML::TokenType::Scalar, "hello", location)

    token.type.should eq(JustYAML::TokenType::Scalar)
    token.value.should eq("hello")
    token.location.should eq(location)
  end

  it "formats to string representation" do
    location = JustYAML::Location.new(5, 10)
    token = JustYAML::Token.new(JustYAML::TokenType::ValueIndicator, ":", location)

    token.to_s.should eq("ValueIndicator(\":\") at line 5, column 10")
  end

  describe "token types for YAML elements" do
    it "creates document marker tokens" do
      loc = JustYAML::Location.new(1, 1)

      doc_start = JustYAML::Token.new(JustYAML::TokenType::DocumentStart, "---", loc)
      doc_start.type.should eq(JustYAML::TokenType::DocumentStart)
      doc_start.value.should eq("---")

      doc_end = JustYAML::Token.new(JustYAML::TokenType::DocumentEnd, "...", loc)
      doc_end.type.should eq(JustYAML::TokenType::DocumentEnd)
      doc_end.value.should eq("...")
    end

    it "creates flow collection tokens" do
      loc = JustYAML::Location.new(1, 1)

      mapping_start = JustYAML::Token.new(JustYAML::TokenType::MappingStart, "{", loc)
      mapping_start.type.should eq(JustYAML::TokenType::MappingStart)

      mapping_end = JustYAML::Token.new(JustYAML::TokenType::MappingEnd, "}", loc)
      mapping_end.type.should eq(JustYAML::TokenType::MappingEnd)

      sequence_start = JustYAML::Token.new(JustYAML::TokenType::SequenceStart, "[", loc)
      sequence_start.type.should eq(JustYAML::TokenType::SequenceStart)

      sequence_end = JustYAML::Token.new(JustYAML::TokenType::SequenceEnd, "]", loc)
      sequence_end.type.should eq(JustYAML::TokenType::SequenceEnd)

      separator = JustYAML::Token.new(JustYAML::TokenType::FlowSeparator, ",", loc)
      separator.type.should eq(JustYAML::TokenType::FlowSeparator)
    end

    it "creates anchor and alias tokens" do
      loc = JustYAML::Location.new(1, 1)

      anchor = JustYAML::Token.new(JustYAML::TokenType::Anchor, "myanchor", loc)
      anchor.type.should eq(JustYAML::TokenType::Anchor)
      anchor.value.should eq("myanchor")

      alias_token = JustYAML::Token.new(JustYAML::TokenType::Alias, "myanchor", loc)
      alias_token.type.should eq(JustYAML::TokenType::Alias)
      alias_token.value.should eq("myanchor")
    end

    it "creates tag token" do
      loc = JustYAML::Location.new(1, 1)

      tag = JustYAML::Token.new(JustYAML::TokenType::Tag, "!custom", loc)
      tag.type.should eq(JustYAML::TokenType::Tag)
      tag.value.should eq("!custom")
    end

    it "creates comment token" do
      loc = JustYAML::Location.new(1, 10)

      comment = JustYAML::Token.new(JustYAML::TokenType::Comment, " this is a comment", loc)
      comment.type.should eq(JustYAML::TokenType::Comment)
      comment.value.should eq(" this is a comment")
    end

    it "creates directive token" do
      loc = JustYAML::Location.new(1, 1)

      directive = JustYAML::Token.new(JustYAML::TokenType::Directive, "%YAML 1.2", loc)
      directive.type.should eq(JustYAML::TokenType::Directive)
      directive.value.should eq("%YAML 1.2")
    end

    it "creates indentation tokens" do
      loc = JustYAML::Location.new(2, 1)

      indent = JustYAML::Token.new(JustYAML::TokenType::Indent, "  ", loc)
      indent.type.should eq(JustYAML::TokenType::Indent)

      dedent = JustYAML::Token.new(JustYAML::TokenType::Dedent, "", loc)
      dedent.type.should eq(JustYAML::TokenType::Dedent)
    end

    it "creates block indicator tokens" do
      loc = JustYAML::Location.new(1, 1)

      key_indicator = JustYAML::Token.new(JustYAML::TokenType::KeyIndicator, "?", loc)
      key_indicator.type.should eq(JustYAML::TokenType::KeyIndicator)

      sequence_entry = JustYAML::Token.new(JustYAML::TokenType::SequenceEntry, "-", loc)
      sequence_entry.type.should eq(JustYAML::TokenType::SequenceEntry)
    end
  end
end

describe JustYAML::Lexer do
  describe "single-quoted strings" do
    it "scans simple single-quoted string" do
      lexer = JustYAML::Lexer.new("'hello'")
      lexer.next_token # StreamStart
      token = lexer.next_token

      token.type.should eq(JustYAML::TokenType::Scalar)
      token.value.should eq("hello")
      token.location.line.should eq(1)
      token.location.column.should eq(1)
    end

    it "scans single-quoted string with spaces" do
      lexer = JustYAML::Lexer.new("'hello world'")
      lexer.next_token # StreamStart
      token = lexer.next_token

      token.type.should eq(JustYAML::TokenType::Scalar)
      token.value.should eq("hello world")
    end

    it "scans empty single-quoted string" do
      lexer = JustYAML::Lexer.new("''")
      lexer.next_token # StreamStart
      token = lexer.next_token

      token.type.should eq(JustYAML::TokenType::Scalar)
      token.value.should eq("")
    end

    it "scans single-quoted string with escaped quote" do
      lexer = JustYAML::Lexer.new("'it''s'")
      lexer.next_token # StreamStart
      token = lexer.next_token

      token.type.should eq(JustYAML::TokenType::Scalar)
      token.value.should eq("it's")
    end

    it "scans single-quoted string with multiple escaped quotes" do
      lexer = JustYAML::Lexer.new("'it''s a ''test'''")
      lexer.next_token # StreamStart
      token = lexer.next_token

      token.type.should eq(JustYAML::TokenType::Scalar)
      token.value.should eq("it's a 'test'")
    end

    it "scans single-quoted string with special characters" do
      lexer = JustYAML::Lexer.new("'hello\\nworld'")
      lexer.next_token # StreamStart
      token = lexer.next_token

      # In single-quoted strings, backslash is literal
      token.type.should eq(JustYAML::TokenType::Scalar)
      token.value.should eq("hello\\nworld")
    end

    it "raises error for unterminated single-quoted string" do
      lexer = JustYAML::Lexer.new("'hello")
      lexer.next_token # StreamStart

      expect_raises(JustYAML::LexerError, /Unterminated single-quoted string/) do
        lexer.next_token
      end
    end

    it "raises error for unterminated string with escaped quote at end" do
      lexer = JustYAML::Lexer.new("'it''")
      lexer.next_token # StreamStart

      expect_raises(JustYAML::LexerError, /Unterminated single-quoted string/) do
        lexer.next_token
      end
    end
  end

  describe "double-quoted strings" do
    it "scans simple double-quoted string" do
      lexer = JustYAML::Lexer.new("\"hello\"")
      lexer.next_token # StreamStart
      token = lexer.next_token

      token.type.should eq(JustYAML::TokenType::Scalar)
      token.value.should eq("hello")
      token.location.line.should eq(1)
      token.location.column.should eq(1)
    end

    it "scans double-quoted string with spaces" do
      lexer = JustYAML::Lexer.new("\"hello world\"")
      lexer.next_token # StreamStart
      token = lexer.next_token

      token.type.should eq(JustYAML::TokenType::Scalar)
      token.value.should eq("hello world")
    end

    it "scans empty double-quoted string" do
      lexer = JustYAML::Lexer.new("\"\"")
      lexer.next_token # StreamStart
      token = lexer.next_token

      token.type.should eq(JustYAML::TokenType::Scalar)
      token.value.should eq("")
    end

    describe "escape sequences" do
      it "handles null escape (\\0)" do
        lexer = JustYAML::Lexer.new("\"a\\0b\"")
        lexer.next_token
        token = lexer.next_token
        token.value.should eq("a\0b")
      end

      it "handles bell escape (\\a)" do
        lexer = JustYAML::Lexer.new("\"a\\ab\"")
        lexer.next_token
        token = lexer.next_token
        token.value.should eq("a\ab")
      end

      it "handles backspace escape (\\b)" do
        lexer = JustYAML::Lexer.new("\"a\\bb\"")
        lexer.next_token
        token = lexer.next_token
        token.value.should eq("a\bb")
      end

      it "handles tab escape (\\t)" do
        lexer = JustYAML::Lexer.new("\"a\\tb\"")
        lexer.next_token
        token = lexer.next_token
        token.value.should eq("a\tb")
      end

      it "handles newline escape (\\n)" do
        lexer = JustYAML::Lexer.new("\"hello\\nworld\"")
        lexer.next_token
        token = lexer.next_token
        token.value.should eq("hello\nworld")
      end

      it "handles vertical tab escape (\\v)" do
        lexer = JustYAML::Lexer.new("\"a\\vb\"")
        lexer.next_token
        token = lexer.next_token
        token.value.should eq("a\vb")
      end

      it "handles form feed escape (\\f)" do
        lexer = JustYAML::Lexer.new("\"a\\fb\"")
        lexer.next_token
        token = lexer.next_token
        token.value.should eq("a\fb")
      end

      it "handles carriage return escape (\\r)" do
        lexer = JustYAML::Lexer.new("\"a\\rb\"")
        lexer.next_token
        token = lexer.next_token
        token.value.should eq("a\rb")
      end

      it "handles escape escape (\\e)" do
        lexer = JustYAML::Lexer.new("\"a\\eb\"")
        lexer.next_token
        token = lexer.next_token
        token.value.should eq("a\eb")
      end

      it "handles space escape (\\ )" do
        lexer = JustYAML::Lexer.new("\"a\\ b\"")
        lexer.next_token
        token = lexer.next_token
        token.value.should eq("a b")
      end

      it "handles double quote escape (\\\")" do
        lexer = JustYAML::Lexer.new("\"a\\\"b\"")
        lexer.next_token
        token = lexer.next_token
        token.value.should eq("a\"b")
      end

      it "handles slash escape (\\/)" do
        lexer = JustYAML::Lexer.new("\"a\\/b\"")
        lexer.next_token
        token = lexer.next_token
        token.value.should eq("a/b")
      end

      it "handles backslash escape (\\\\)" do
        lexer = JustYAML::Lexer.new("\"a\\\\b\"")
        lexer.next_token
        token = lexer.next_token
        token.value.should eq("a\\b")
      end

      it "handles NEL escape (\\N)" do
        lexer = JustYAML::Lexer.new("\"a\\Nb\"")
        lexer.next_token
        token = lexer.next_token
        token.value.should eq("a\u0085b")
      end

      it "handles NBSP escape (\\_)" do
        lexer = JustYAML::Lexer.new("\"a\\_b\"")
        lexer.next_token
        token = lexer.next_token
        token.value.should eq("a\u00A0b")
      end

      it "handles line separator escape (\\L)" do
        lexer = JustYAML::Lexer.new("\"a\\Lb\"")
        lexer.next_token
        token = lexer.next_token
        token.value.should eq("a\u2028b")
      end

      it "handles paragraph separator escape (\\P)" do
        lexer = JustYAML::Lexer.new("\"a\\Pb\"")
        lexer.next_token
        token = lexer.next_token
        token.value.should eq("a\u2029b")
      end

      it "handles hex escape (\\xNN)" do
        lexer = JustYAML::Lexer.new("\"\\x41\\x42\\x43\"")
        lexer.next_token
        token = lexer.next_token
        token.value.should eq("ABC")
      end

      it "handles unicode escape (\\uNNNN)" do
        lexer = JustYAML::Lexer.new("\"\\u0048\\u0065\\u006C\\u006C\\u006F\"")
        lexer.next_token
        token = lexer.next_token
        token.value.should eq("Hello")
      end

      it "handles unicode escape for non-ASCII" do
        lexer = JustYAML::Lexer.new("\"\\u4E2D\\u6587\"")
        lexer.next_token
        token = lexer.next_token
        token.value.should eq("\u4E2D\u6587") # Chinese characters
      end

      it "handles 8-digit unicode escape (\\UNNNNNNNN)" do
        lexer = JustYAML::Lexer.new("\"\\U0001F600\"")
        lexer.next_token
        token = lexer.next_token
        token.value.should eq("\u{1F600}") # Emoji grinning face
      end

      it "handles multiple escape sequences" do
        lexer = JustYAML::Lexer.new("\"line1\\nline2\\ttab\"")
        lexer.next_token
        token = lexer.next_token
        token.value.should eq("line1\nline2\ttab")
      end
    end

    describe "error handling" do
      it "raises error for unterminated double-quoted string" do
        lexer = JustYAML::Lexer.new("\"hello")
        lexer.next_token # StreamStart

        expect_raises(JustYAML::LexerError, /Unterminated double-quoted string/) do
          lexer.next_token
        end
      end

      it "raises error for invalid escape sequence" do
        lexer = JustYAML::Lexer.new("\"hello\\qworld\"")
        lexer.next_token # StreamStart

        expect_raises(JustYAML::LexerError, /Invalid escape sequence '\\q'/) do
          lexer.next_token
        end
      end

      it "raises error for incomplete hex escape" do
        # When hex escape is incomplete, the closing quote is hit as invalid hex
        lexer = JustYAML::Lexer.new("\"\\x4\"")
        lexer.next_token # StreamStart

        expect_raises(JustYAML::LexerError, /Invalid hex digit/) do
          lexer.next_token
        end
      end

      it "raises error for incomplete hex escape at end of input" do
        lexer = JustYAML::Lexer.new("\"\\x4")
        lexer.next_token # StreamStart

        expect_raises(JustYAML::LexerError, /Incomplete hex escape sequence/) do
          lexer.next_token
        end
      end

      it "raises error for invalid hex digit" do
        lexer = JustYAML::Lexer.new("\"\\xGG\"")
        lexer.next_token # StreamStart

        expect_raises(JustYAML::LexerError, /Invalid hex digit 'G'/) do
          lexer.next_token
        end
      end

      it "raises error for incomplete unicode escape" do
        # When unicode escape is incomplete, the closing quote is hit as invalid hex
        lexer = JustYAML::Lexer.new("\"\\u00\"")
        lexer.next_token # StreamStart

        expect_raises(JustYAML::LexerError, /Invalid hex digit/) do
          lexer.next_token
        end
      end

      it "raises error for incomplete unicode escape at end of input" do
        lexer = JustYAML::Lexer.new("\"\\u00")
        lexer.next_token # StreamStart

        expect_raises(JustYAML::LexerError, /Incomplete hex escape sequence/) do
          lexer.next_token
        end
      end

      it "raises error for invalid unicode surrogate" do
        lexer = JustYAML::Lexer.new("\"\\uD800\"")
        lexer.next_token # StreamStart

        expect_raises(JustYAML::LexerError, /Invalid Unicode surrogate codepoint/) do
          lexer.next_token
        end
      end

      it "raises error for unterminated escape at end of string" do
        lexer = JustYAML::Lexer.new("\"hello\\")
        lexer.next_token # StreamStart

        expect_raises(JustYAML::LexerError, /Unterminated escape sequence/) do
          lexer.next_token
        end
      end
    end
  end

  describe "quoted strings in context" do
    it "scans quoted string followed by newline" do
      lexer = JustYAML::Lexer.new("'hello'\n")
      lexer.next_token # StreamStart
      token1 = lexer.next_token
      token2 = lexer.next_token

      token1.type.should eq(JustYAML::TokenType::Scalar)
      token1.value.should eq("hello")
      token2.type.should eq(JustYAML::TokenType::Newline)
    end

    it "scans quoted string as value" do
      lexer = JustYAML::Lexer.new(": 'value'")
      lexer.next_token # StreamStart
      token1 = lexer.next_token
      token2 = lexer.next_token

      token1.type.should eq(JustYAML::TokenType::ValueIndicator)
      token2.type.should eq(JustYAML::TokenType::Scalar)
      token2.value.should eq("value")
    end

    it "scans double-quoted string with colon inside" do
      lexer = JustYAML::Lexer.new("\"key: value\"")
      lexer.next_token # StreamStart
      token = lexer.next_token

      token.type.should eq(JustYAML::TokenType::Scalar)
      token.value.should eq("key: value")
    end
  end

  describe "comments" do
    it "scans simple comment" do
      lexer = JustYAML::Lexer.new("# this is a comment")
      lexer.next_token # StreamStart
      token = lexer.next_token

      token.type.should eq(JustYAML::TokenType::Comment)
      token.value.should eq(" this is a comment")
      token.location.line.should eq(1)
      token.location.column.should eq(1)
    end

    it "scans empty comment" do
      lexer = JustYAML::Lexer.new("#")
      lexer.next_token # StreamStart
      token = lexer.next_token

      token.type.should eq(JustYAML::TokenType::Comment)
      token.value.should eq("")
    end

    it "scans comment followed by newline" do
      lexer = JustYAML::Lexer.new("# comment\nnext")
      lexer.next_token # StreamStart
      token1 = lexer.next_token
      token2 = lexer.next_token

      token1.type.should eq(JustYAML::TokenType::Comment)
      token1.value.should eq(" comment")
      token2.type.should eq(JustYAML::TokenType::Newline)
    end

    it "scans comment with special characters" do
      lexer = JustYAML::Lexer.new("# special: 'chars' \"here\" & * !")
      lexer.next_token # StreamStart
      token = lexer.next_token

      token.type.should eq(JustYAML::TokenType::Comment)
      token.value.should eq(" special: 'chars' \"here\" & * !")
    end
  end

  describe "anchors" do
    it "scans simple anchor" do
      lexer = JustYAML::Lexer.new("&myanchor")
      lexer.next_token # StreamStart
      token = lexer.next_token

      token.type.should eq(JustYAML::TokenType::Anchor)
      token.value.should eq("myanchor")
      token.location.line.should eq(1)
      token.location.column.should eq(1)
    end

    it "scans anchor with underscore" do
      lexer = JustYAML::Lexer.new("&my_anchor")
      lexer.next_token # StreamStart
      token = lexer.next_token

      token.type.should eq(JustYAML::TokenType::Anchor)
      token.value.should eq("my_anchor")
    end

    it "scans anchor with hyphen" do
      lexer = JustYAML::Lexer.new("&my-anchor")
      lexer.next_token # StreamStart
      token = lexer.next_token

      token.type.should eq(JustYAML::TokenType::Anchor)
      token.value.should eq("my-anchor")
    end

    it "scans anchor with numbers" do
      lexer = JustYAML::Lexer.new("&anchor123")
      lexer.next_token # StreamStart
      token = lexer.next_token

      token.type.should eq(JustYAML::TokenType::Anchor)
      token.value.should eq("anchor123")
    end

    it "scans anchor starting with underscore" do
      lexer = JustYAML::Lexer.new("&_private")
      lexer.next_token # StreamStart
      token = lexer.next_token

      token.type.should eq(JustYAML::TokenType::Anchor)
      token.value.should eq("_private")
    end

    it "scans anchor followed by whitespace" do
      lexer = JustYAML::Lexer.new("&anchor value")
      lexer.next_token # StreamStart
      token1 = lexer.next_token
      token2 = lexer.next_token

      token1.type.should eq(JustYAML::TokenType::Anchor)
      token1.value.should eq("anchor")
      token2.type.should eq(JustYAML::TokenType::Scalar)
      token2.value.should eq("value")
    end

    it "raises error for anchor starting with digit" do
      lexer = JustYAML::Lexer.new("&123abc")
      lexer.next_token # StreamStart

      expect_raises(JustYAML::LexerError, /Invalid anchor name/) do
        lexer.next_token
      end
    end

    it "raises error for empty anchor name" do
      lexer = JustYAML::Lexer.new("& value")
      lexer.next_token # StreamStart

      expect_raises(JustYAML::LexerError, /Invalid anchor name/) do
        lexer.next_token
      end
    end

    it "raises error for anchor at end of input" do
      lexer = JustYAML::Lexer.new("&")
      lexer.next_token # StreamStart

      expect_raises(JustYAML::LexerError, /Invalid anchor name/) do
        lexer.next_token
      end
    end
  end

  describe "aliases" do
    it "scans simple alias" do
      lexer = JustYAML::Lexer.new("*myanchor")
      lexer.next_token # StreamStart
      token = lexer.next_token

      token.type.should eq(JustYAML::TokenType::Alias)
      token.value.should eq("myanchor")
      token.location.line.should eq(1)
      token.location.column.should eq(1)
    end

    it "scans alias with underscore" do
      lexer = JustYAML::Lexer.new("*my_alias")
      lexer.next_token # StreamStart
      token = lexer.next_token

      token.type.should eq(JustYAML::TokenType::Alias)
      token.value.should eq("my_alias")
    end

    it "scans alias with hyphen" do
      lexer = JustYAML::Lexer.new("*my-alias")
      lexer.next_token # StreamStart
      token = lexer.next_token

      token.type.should eq(JustYAML::TokenType::Alias)
      token.value.should eq("my-alias")
    end

    it "scans alias with numbers" do
      lexer = JustYAML::Lexer.new("*alias123")
      lexer.next_token # StreamStart
      token = lexer.next_token

      token.type.should eq(JustYAML::TokenType::Alias)
      token.value.should eq("alias123")
    end

    it "scans alias followed by whitespace" do
      lexer = JustYAML::Lexer.new("*alias next")
      lexer.next_token # StreamStart
      token1 = lexer.next_token
      token2 = lexer.next_token

      token1.type.should eq(JustYAML::TokenType::Alias)
      token1.value.should eq("alias")
      token2.type.should eq(JustYAML::TokenType::Scalar)
      token2.value.should eq("next")
    end

    it "raises error for alias starting with digit" do
      lexer = JustYAML::Lexer.new("*123abc")
      lexer.next_token # StreamStart

      expect_raises(JustYAML::LexerError, /Invalid alias name/) do
        lexer.next_token
      end
    end

    it "raises error for empty alias name" do
      lexer = JustYAML::Lexer.new("* value")
      lexer.next_token # StreamStart

      expect_raises(JustYAML::LexerError, /Invalid alias name/) do
        lexer.next_token
      end
    end

    it "raises error for alias at end of input" do
      lexer = JustYAML::Lexer.new("*")
      lexer.next_token # StreamStart

      expect_raises(JustYAML::LexerError, /Invalid alias name/) do
        lexer.next_token
      end
    end
  end

  describe "tags" do
    it "scans non-specific tag (!)" do
      lexer = JustYAML::Lexer.new("! value")
      lexer.next_token # StreamStart
      token = lexer.next_token

      token.type.should eq(JustYAML::TokenType::Tag)
      token.value.should eq("!")
      token.location.line.should eq(1)
      token.location.column.should eq(1)
    end

    it "scans local tag (!custom)" do
      lexer = JustYAML::Lexer.new("!custom")
      lexer.next_token # StreamStart
      token = lexer.next_token

      token.type.should eq(JustYAML::TokenType::Tag)
      token.value.should eq("!custom")
    end

    it "scans secondary tag handle (!!str)" do
      lexer = JustYAML::Lexer.new("!!str")
      lexer.next_token # StreamStart
      token = lexer.next_token

      token.type.should eq(JustYAML::TokenType::Tag)
      token.value.should eq("!!str")
    end

    it "scans secondary tag handle (!!int)" do
      lexer = JustYAML::Lexer.new("!!int")
      lexer.next_token # StreamStart
      token = lexer.next_token

      token.type.should eq(JustYAML::TokenType::Tag)
      token.value.should eq("!!int")
    end

    it "scans secondary tag handle (!!map)" do
      lexer = JustYAML::Lexer.new("!!map")
      lexer.next_token # StreamStart
      token = lexer.next_token

      token.type.should eq(JustYAML::TokenType::Tag)
      token.value.should eq("!!map")
    end

    it "scans secondary tag handle (!!seq)" do
      lexer = JustYAML::Lexer.new("!!seq")
      lexer.next_token # StreamStart
      token = lexer.next_token

      token.type.should eq(JustYAML::TokenType::Tag)
      token.value.should eq("!!seq")
    end

    it "scans named tag handle (!prefix!suffix)" do
      lexer = JustYAML::Lexer.new("!e!foo")
      lexer.next_token # StreamStart
      token = lexer.next_token

      token.type.should eq(JustYAML::TokenType::Tag)
      token.value.should eq("!e!foo")
    end

    it "scans verbatim tag (!<uri>)" do
      lexer = JustYAML::Lexer.new("!<tag:yaml.org,2002:str>")
      lexer.next_token # StreamStart
      token = lexer.next_token

      token.type.should eq(JustYAML::TokenType::Tag)
      token.value.should eq("!<tag:yaml.org,2002:str>")
    end

    it "scans tag followed by value" do
      lexer = JustYAML::Lexer.new("!!str hello")
      lexer.next_token # StreamStart
      token1 = lexer.next_token
      token2 = lexer.next_token

      token1.type.should eq(JustYAML::TokenType::Tag)
      token1.value.should eq("!!str")
      token2.type.should eq(JustYAML::TokenType::Scalar)
      token2.value.should eq("hello")
    end

    it "scans tag at end of line" do
      lexer = JustYAML::Lexer.new("!!str\nvalue")
      lexer.next_token # StreamStart
      token1 = lexer.next_token
      token2 = lexer.next_token

      token1.type.should eq(JustYAML::TokenType::Tag)
      token1.value.should eq("!!str")
      token2.type.should eq(JustYAML::TokenType::Newline)
    end

    it "raises error for unterminated verbatim tag" do
      lexer = JustYAML::Lexer.new("!<unclosed")
      lexer.next_token # StreamStart

      expect_raises(JustYAML::LexerError, /Unterminated verbatim tag/) do
        lexer.next_token
      end
    end

    it "raises error for verbatim tag with newline" do
      lexer = JustYAML::Lexer.new("!<broken\ntag>")
      lexer.next_token # StreamStart

      expect_raises(JustYAML::LexerError, /Unterminated verbatim tag/) do
        lexer.next_token
      end
    end
  end

  describe "combined usage" do
    it "scans anchor followed by tag" do
      lexer = JustYAML::Lexer.new("&anchor !!str")
      lexer.next_token # StreamStart
      token1 = lexer.next_token
      token2 = lexer.next_token

      token1.type.should eq(JustYAML::TokenType::Anchor)
      token1.value.should eq("anchor")
      token2.type.should eq(JustYAML::TokenType::Tag)
      token2.value.should eq("!!str")
    end

    it "scans tag followed by anchor" do
      lexer = JustYAML::Lexer.new("!!str &anchor")
      lexer.next_token # StreamStart
      token1 = lexer.next_token
      token2 = lexer.next_token

      token1.type.should eq(JustYAML::TokenType::Tag)
      token1.value.should eq("!!str")
      token2.type.should eq(JustYAML::TokenType::Anchor)
      token2.value.should eq("anchor")
    end

    it "scans alias followed by comment" do
      lexer = JustYAML::Lexer.new("*alias # a comment")
      lexer.next_token # StreamStart
      token1 = lexer.next_token
      token2 = lexer.next_token

      token1.type.should eq(JustYAML::TokenType::Alias)
      token1.value.should eq("alias")
      token2.type.should eq(JustYAML::TokenType::Comment)
      token2.value.should eq(" a comment")
    end

    it "scans value with anchor and tag" do
      lexer = JustYAML::Lexer.new(": &name !!str value")
      lexer.next_token # StreamStart
      token1 = lexer.next_token
      token2 = lexer.next_token
      token3 = lexer.next_token
      token4 = lexer.next_token

      token1.type.should eq(JustYAML::TokenType::ValueIndicator)
      token2.type.should eq(JustYAML::TokenType::Anchor)
      token2.value.should eq("name")
      token3.type.should eq(JustYAML::TokenType::Tag)
      token3.value.should eq("!!str")
      token4.type.should eq(JustYAML::TokenType::Scalar)
      token4.value.should eq("value")
    end
  end
end
