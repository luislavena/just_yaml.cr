require "./spec_helper"

describe "JustYAML comment parsing" do
  describe "leading comments" do
    it "attaches leading comment to first mapping entry key" do
      yaml = <<-YAML
        # comment
        key: value
        YAML

      ast = JustYAML.parse(yaml)
      doc = ast.documents.first
      mapping = doc.root.as(JustYAML::AST::MappingNode)
      key = mapping.entries.first.key

      key.leading_comments.size.should eq(1)
      key.leading_comments.first.text.should eq(" comment")
    end

    it "attaches multiple leading comments to mapping entry key" do
      yaml = <<-YAML
        # first
        # second
        key: value
        YAML

      ast = JustYAML.parse(yaml)
      doc = ast.documents.first
      mapping = doc.root.as(JustYAML::AST::MappingNode)
      key = mapping.entries.first.key

      key.leading_comments.size.should eq(2)
      key.leading_comments[0].text.should eq(" first")
      key.leading_comments[1].text.should eq(" second")
    end

    it "attaches leading comment to second mapping entry key" do
      yaml = <<-YAML
        key1: value1
        # comment for key2
        key2: value2
        YAML

      ast = JustYAML.parse(yaml)
      doc = ast.documents.first
      mapping = doc.root.as(JustYAML::AST::MappingNode)
      key2 = mapping.entries[1].key

      key2.leading_comments.size.should eq(1)
      key2.leading_comments.first.text.should eq(" comment for key2")
    end

    it "attaches leading comment to sequence item" do
      yaml = <<-YAML
        items:
          # item comment
          - item1
        YAML

      ast = JustYAML.parse(yaml)
      doc = ast.documents.first
      mapping = doc.root.as(JustYAML::AST::MappingNode)
      sequence = mapping.entries.first.value.as(JustYAML::AST::SequenceNode)
      item = sequence.items.first

      item.leading_comments.size.should eq(1)
      item.leading_comments.first.text.should eq(" item comment")
    end
  end

  describe "trailing comments" do
    it "attaches trailing comment to scalar value" do
      yaml = <<-YAML
        key: value # trailing
        YAML

      ast = JustYAML.parse(yaml)
      doc = ast.documents.first
      mapping = doc.root.as(JustYAML::AST::MappingNode)
      value = mapping.entries.first.value.as(JustYAML::AST::ScalarNode)

      value.trailing_comment.should_not be_nil
      value.trailing_comment.try(&.text).should eq(" trailing")
    end

    it "attaches trailing comment after mapping key with block value" do
      yaml = <<-YAML
        key: # key comment
          nested: value
        YAML

      ast = JustYAML.parse(yaml)
      doc = ast.documents.first
      mapping = doc.root.as(JustYAML::AST::MappingNode)
      entry = mapping.entries.first

      entry.key_comments.size.should eq(1)
      entry.key_comments.first.text.should eq(" key comment")
    end
  end

  describe "document level comments" do
    it "attaches leading comment to document" do
      yaml = <<-YAML
        # document comment
        key: value
        YAML

      ast = JustYAML.parse(yaml)
      doc = ast.documents.first
      mapping = doc.root.as(JustYAML::AST::MappingNode)
      key = mapping.entries.first.key

      # Comment should be on the first node (the key)
      key.leading_comments.size.should eq(1)
      key.leading_comments.first.text.should eq(" document comment")
    end
  end
end
