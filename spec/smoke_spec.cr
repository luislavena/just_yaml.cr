require "./spec_helper"

describe "JustYAML smoke test" do
  it "parses a simple key-value mapping" do
    yaml = <<-YAML
      name: JustYAML
      version: 1.0
      YAML

    result = JustYAML.load(yaml)

    result.should eq({"name" => "JustYAML", "version" => "1.0"})
  end

  it "returns AST with parse" do
    yaml = <<-YAML
      name: JustYAML
      version: 1.0
      YAML

    ast = JustYAML.parse(yaml)

    ast.should be_a(JustYAML::AST::StreamNode)
    ast.documents.size.should eq(1)

    doc = ast.documents.first
    doc.root.should be_a(JustYAML::AST::MappingNode)

    mapping = doc.root.as(JustYAML::AST::MappingNode)
    mapping.entries.size.should eq(2)

    mapping.entries[0].key.as(JustYAML::AST::ScalarNode).value.should eq("name")
    mapping.entries[0].value.as(JustYAML::AST::ScalarNode).value.should eq("JustYAML")

    mapping.entries[1].key.as(JustYAML::AST::ScalarNode).value.should eq("version")
    mapping.entries[1].value.as(JustYAML::AST::ScalarNode).value.should eq("1.0")
  end
end
