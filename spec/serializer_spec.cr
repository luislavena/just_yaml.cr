require "./spec_helper"

describe JustYAML::Serializer do
  describe "scalars" do
    it "serializes plain scalar" do
      yaml = "hello"
      ast = JustYAML.parse(yaml)
      result = JustYAML.dump(ast).strip
      result.should eq("hello")
    end

    it "serializes single-quoted scalar" do
      yaml = "'hello world'"
      ast = JustYAML.parse(yaml)
      result = JustYAML.dump(ast).strip
      result.should eq("'hello world'")
    end

    it "serializes double-quoted scalar" do
      yaml = "\"hello world\""
      ast = JustYAML.parse(yaml)
      result = JustYAML.dump(ast).strip
      result.should eq("\"hello world\"")
    end

    it "escapes special values in plain scalars" do
      yaml = "\"null\""
      ast = JustYAML.parse(yaml)
      result = JustYAML.dump(ast).strip
      # Should preserve as quoted to avoid interpretation as null
      result.should eq("\"null\"")
    end
  end

  describe "sequences" do
    it "serializes flow sequence" do
      yaml = "[one, two, three]"
      ast = JustYAML.parse(yaml)
      result = JustYAML.dump(ast).strip
      result.should eq("[one, two, three]")
    end

    it "serializes block sequence" do
      yaml = <<-YAML
        - one
        - two
        - three
        YAML

      ast = JustYAML.parse(yaml)
      result = JustYAML.dump(ast).strip
      result.should contain("- one")
      result.should contain("- two")
      result.should contain("- three")
    end

    it "serializes empty sequence" do
      yaml = "[]"
      ast = JustYAML.parse(yaml)
      result = JustYAML.dump(ast).strip
      result.should eq("[]")
    end
  end

  describe "mappings" do
    it "serializes flow mapping" do
      yaml = "{name: Alice, age: 30}"
      ast = JustYAML.parse(yaml)
      result = JustYAML.dump(ast).strip
      result.should eq("{name: Alice, age: 30}")
    end

    it "serializes block mapping" do
      yaml = <<-YAML
        name: Alice
        age: 30
        YAML

      ast = JustYAML.parse(yaml)
      result = JustYAML.dump(ast).strip
      result.should contain("name: Alice")
      result.should contain("age: 30")
    end

    it "serializes empty mapping" do
      yaml = "{}"
      ast = JustYAML.parse(yaml)
      result = JustYAML.dump(ast).strip
      result.should eq("{}")
    end
  end

  describe "nested structures" do
    it "serializes nested mappings" do
      yaml = <<-YAML
        level1:
          level2:
            level3: value
        YAML

      ast = JustYAML.parse(yaml)
      result = JustYAML.dump(ast)
      result.should contain("level1:")
      result.should contain("level2:")
      result.should contain("level3: value")
    end

    it "serializes mapping with sequence value" do
      yaml = <<-YAML
        names:
          - Alice
          - Bob
        YAML

      ast = JustYAML.parse(yaml)
      result = JustYAML.dump(ast)
      result.should contain("names:")
      result.should contain("- Alice")
      result.should contain("- Bob")
    end
  end

  describe "anchors and aliases" do
    it "preserves anchors in output" do
      yaml = "name: &anchor value"
      ast = JustYAML.parse(yaml)
      result = JustYAML.dump(ast)
      result.should contain("&anchor")
    end
  end

  describe "round-trip" do
    it "round-trips simple mapping" do
      yaml = <<-YAML
        name: JustYAML
        version: 1.0
        YAML

      ast1 = JustYAML.parse(yaml)
      output = JustYAML.dump(ast1)
      ast2 = JustYAML.parse(output)

      # Both should resolve to same value
      resolver = JustYAML::Resolver.new
      value1 = resolver.resolve(ast1)
      value2 = resolver.resolve(ast2)

      value1.should eq(value2)
    end

    it "round-trips complex structure" do
      yaml = <<-YAML
        users:
          - name: Alice
            roles: [admin, user]
          - name: Bob
            roles: [user]
        YAML

      ast1 = JustYAML.parse(yaml)
      output = JustYAML.dump(ast1)
      ast2 = JustYAML.parse(output)

      resolver = JustYAML::Resolver.new
      value1 = resolver.resolve(ast1)
      value2 = resolver.resolve(ast2)

      value1.should eq(value2)
    end
  end
end
