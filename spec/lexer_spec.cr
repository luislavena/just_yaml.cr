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
