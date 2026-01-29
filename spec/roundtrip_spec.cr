require "./spec_helper"

describe "JustYAML comment preservation" do
  describe "leading comments" do
    it "preserves leading comment on mapping key" do
      input = "# comment\nkey: value\n"
      ast = JustYAML.parse(input)
      output = JustYAML.dump(ast)

      output.should eq(input)
    end

    it "preserves multiple leading comments on mapping key" do
      input = "# first comment\n# second comment\nkey: value\n"
      ast = JustYAML.parse(input)
      output = JustYAML.dump(ast)

      output.should eq(input)
    end

    it "preserves leading comment on sequence item" do
      input = "items:\n  # comment\n  - item1\n"
      ast = JustYAML.parse(input)
      output = JustYAML.dump(ast)

      output.should eq(input)
    end

    it "preserves leading comments between mapping entries" do
      input = "key1: value1\n# comment for key2\nkey2: value2\n"
      ast = JustYAML.parse(input)
      output = JustYAML.dump(ast)

      output.should eq(input)
    end
  end

  describe "trailing comments" do
    it "preserves trailing comment on scalar value" do
      input = "key: value # trailing\n"
      ast = JustYAML.parse(input)
      output = JustYAML.dump(ast)

      output.should eq(input)
    end

    it "preserves trailing comment on mapping key line" do
      input = "key: # key comment\n  nested: value\n"
      ast = JustYAML.parse(input)
      output = JustYAML.dump(ast)

      output.should eq(input)
    end
  end

  describe "mixed comments" do
    it "preserves leading and trailing comments together" do
      input = "# leading\nkey: value # trailing\n"
      ast = JustYAML.parse(input)
      output = JustYAML.dump(ast)

      output.should eq(input)
    end
  end

  describe "full document round-trip" do
    it "preserves comments and blank lines in complex document" do
      input = <<-YAML
        name: just_yaml
        version: 0.1.0

        # authors
        authors:
          # Creator
          - Luis Lavena
          # Contributor
          - Claude Opus

        # minimum version
        crystal: ">= 1.16.0"

        # SPDX-License-Identifier: MIT
        license: MIT

        YAML
      ast = JustYAML.parse(input)
      output = JustYAML.dump(ast)

      output.should eq(input)
    end
  end
end
