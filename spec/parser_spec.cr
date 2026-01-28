require "./spec_helper"

describe JustYAML::Parser do
  describe "block sequences" do
    it "parses simple block sequence" do
      yaml = <<-YAML
        - one
        - two
        - three
        YAML

      ast = JustYAML.parse(yaml)
      doc = ast.documents.first
      doc.root.should be_a(JustYAML::AST::SequenceNode)

      seq = doc.root.as(JustYAML::AST::SequenceNode)
      seq.items.size.should eq(3)
      seq.items[0].as(JustYAML::AST::ScalarNode).value.should eq("one")
      seq.items[1].as(JustYAML::AST::ScalarNode).value.should eq("two")
      seq.items[2].as(JustYAML::AST::ScalarNode).value.should eq("three")
    end

    it "parses sequence with nested mapping" do
      yaml = <<-YAML
        - name: Alice
          age: 30
        - name: Bob
          age: 25
        YAML

      result = JustYAML.load(yaml)
      result.should eq([
        {"name" => "Alice", "age" => "30"},
        {"name" => "Bob", "age" => "25"},
      ])
    end

    it "parses mapping with sequence value" do
      yaml = <<-YAML
        names:
          - Alice
          - Bob
          - Charlie
        YAML

      result = JustYAML.load(yaml)
      result.should eq({"names" => ["Alice", "Bob", "Charlie"]})
    end
  end

  describe "flow sequences" do
    it "parses empty flow sequence" do
      yaml = "[]"
      result = JustYAML.load(yaml)
      result.should eq([] of String)
    end

    it "parses simple flow sequence" do
      yaml = "[one, two, three]"
      result = JustYAML.load(yaml)
      result.should eq(["one", "two", "three"])
    end

    it "parses nested flow sequences" do
      yaml = "[[1, 2], [3, 4]]"
      result = JustYAML.load(yaml)
      result.should eq([["1", "2"], ["3", "4"]])
    end

    it "allows trailing comma" do
      yaml = "[one, two, three,]"
      result = JustYAML.load(yaml)
      result.should eq(["one", "two", "three"])
    end
  end

  describe "flow mappings" do
    it "parses empty flow mapping" do
      yaml = "{}"
      result = JustYAML.load(yaml)
      result.should eq({} of String => String)
    end

    it "parses simple flow mapping" do
      yaml = "{name: Alice, age: 30}"
      result = JustYAML.load(yaml)
      result.should eq({"name" => "Alice", "age" => "30"})
    end

    it "parses nested flow mapping" do
      yaml = "{person: {name: Alice, age: 30}}"
      result = JustYAML.load(yaml)
      result.should eq({"person" => {"name" => "Alice", "age" => "30"}})
    end

    it "allows trailing comma" do
      yaml = "{name: Alice, age: 30,}"
      result = JustYAML.load(yaml)
      result.should eq({"name" => "Alice", "age" => "30"})
    end
  end

  describe "mixed flow and block" do
    it "parses block mapping with flow sequence value" do
      yaml = <<-YAML
        names: [Alice, Bob, Charlie]
        YAML

      result = JustYAML.load(yaml)
      result.should eq({"names" => ["Alice", "Bob", "Charlie"]})
    end

    it "parses block mapping with flow mapping value" do
      yaml = <<-YAML
        person: {name: Alice, age: 30}
        YAML

      result = JustYAML.load(yaml)
      result.should eq({"person" => {"name" => "Alice", "age" => "30"}})
    end

    it "parses block sequence with flow mapping items" do
      yaml = <<-YAML
        - {name: Alice}
        - {name: Bob}
        YAML

      result = JustYAML.load(yaml)
      result.should eq([{"name" => "Alice"}, {"name" => "Bob"}])
    end
  end

  describe "document markers" do
    it "parses explicit document start" do
      yaml = <<-YAML
        ---
        name: test
        YAML

      ast = JustYAML.parse(yaml)
      ast.documents.size.should eq(1)
      ast.documents.first.explicit_start.should be_true
    end

    it "parses multiple documents" do
      yaml = <<-YAML
        ---
        doc1
        ---
        doc2
        YAML

      ast = JustYAML.parse(yaml)
      ast.documents.size.should eq(2)
    end
  end

  describe "quoted scalars" do
    it "parses single-quoted scalars" do
      yaml = "'hello world'"
      result = JustYAML.load(yaml)
      result.should eq("hello world")
    end

    it "parses double-quoted scalars" do
      yaml = "\"hello world\""
      result = JustYAML.load(yaml)
      result.should eq("hello world")
    end

    it "parses single-quoted with escaped quotes" do
      yaml = "'it''s a test'"
      result = JustYAML.load(yaml)
      result.should eq("it's a test")
    end

    it "parses double-quoted with escape sequences" do
      yaml = "\"hello\\nworld\""
      result = JustYAML.load(yaml)
      result.should eq("hello\nworld")
    end

    it "parses mapping with quoted values" do
      yaml = <<-YAML
        name: "Alice Smith"
        greeting: 'Hello, World!'
        YAML

      result = JustYAML.load(yaml)
      result.should eq({"name" => "Alice Smith", "greeting" => "Hello, World!"})
    end

    it "parses quoted keys" do
      yaml = <<-YAML
        "quoted key": value
        'single quoted': another
        YAML

      result = JustYAML.load(yaml)
      result.should eq({"quoted key" => "value", "single quoted" => "another"})
    end
  end

  describe "block scalars" do
    it "parses literal block scalar" do
      yaml = <<-YAML
        text: |
          line one
          line two
        YAML

      ast = JustYAML.parse(yaml)
      mapping = ast.documents.first.root.as(JustYAML::AST::MappingNode)
      scalar = mapping.entries.first.value.as(JustYAML::AST::ScalarNode)
      scalar.style.should eq(JustYAML::AST::ScalarStyle::Literal)
    end

    it "parses folded block scalar" do
      yaml = <<-YAML
        text: >
          line one
          line two
        YAML

      ast = JustYAML.parse(yaml)
      mapping = ast.documents.first.root.as(JustYAML::AST::MappingNode)
      scalar = mapping.entries.first.value.as(JustYAML::AST::ScalarNode)
      scalar.style.should eq(JustYAML::AST::ScalarStyle::Folded)
    end
  end

  describe "nested structures" do
    it "parses deeply nested mappings" do
      yaml = <<-YAML
        level1:
          level2:
            level3: value
        YAML

      result = JustYAML.load(yaml)
      result.should eq({"level1" => {"level2" => {"level3" => "value"}}})
    end

    it "parses complex nested structure" do
      yaml = <<-YAML
        users:
          - name: Alice
            roles:
              - admin
              - user
          - name: Bob
            roles:
              - user
        YAML

      result = JustYAML.load(yaml)
      result.should eq({
        "users" => [
          {"name" => "Alice", "roles" => ["admin", "user"]},
          {"name" => "Bob", "roles" => ["user"]},
        ],
      })
    end
  end
end
