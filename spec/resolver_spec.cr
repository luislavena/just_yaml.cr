require "./spec_helper"

describe JustYAML::Resolver do
  describe "null values" do
    it "resolves null keyword" do
      JustYAML.load("null").should be_nil
    end

    it "resolves Null keyword" do
      JustYAML.load("Null").should be_nil
    end

    it "resolves NULL keyword" do
      JustYAML.load("NULL").should be_nil
    end

    it "resolves tilde as null" do
      JustYAML.load("~").should be_nil
    end

    it "resolves empty document as null" do
      yaml = <<-YAML
        ---
        YAML
      JustYAML.load(yaml).should be_nil
    end

    it "resolves empty mapping value as null" do
      result = JustYAML.load("key:")
      result.should eq({"key" => nil})
    end
  end

  describe "boolean values" do
    it "resolves true" do
      JustYAML.load("true").should be_true
    end

    it "resolves True" do
      JustYAML.load("True").should be_true
    end

    it "resolves TRUE" do
      JustYAML.load("TRUE").should be_true
    end

    it "resolves false" do
      JustYAML.load("false").should be_false
    end

    it "resolves False" do
      JustYAML.load("False").should be_false
    end

    it "resolves FALSE" do
      JustYAML.load("FALSE").should be_false
    end
  end

  describe "integer values" do
    it "resolves positive integer" do
      JustYAML.load("123").should eq(123_i64)
    end

    it "resolves negative integer" do
      JustYAML.load("-456").should eq(-456_i64)
    end

    it "resolves zero" do
      JustYAML.load("0").should eq(0_i64)
    end

    it "resolves octal integer" do
      JustYAML.load("0o17").should eq(15_i64)
    end

    it "resolves hexadecimal integer" do
      JustYAML.load("0x1a").should eq(26_i64)
    end

    it "resolves hexadecimal with uppercase" do
      JustYAML.load("0xFF").should eq(255_i64)
    end
  end

  describe "float values" do
    it "resolves positive float" do
      JustYAML.load("1.5").should eq(1.5)
    end

    it "resolves negative float" do
      JustYAML.load("-0.5").should eq(-0.5)
    end

    it "resolves float starting with dot" do
      JustYAML.load(".5").should eq(0.5)
    end

    it "resolves scientific notation" do
      JustYAML.load("1.2e+3").should eq(1200.0)
    end

    it "resolves positive infinity" do
      JustYAML.load(".inf").should eq(Float64::INFINITY)
    end

    it "resolves negative infinity" do
      JustYAML.load("-.inf").should eq(-Float64::INFINITY)
    end

    it "resolves NaN" do
      result = JustYAML.load(".nan")
      result.as(Float64).nan?.should be_true
    end
  end

  describe "string values" do
    it "keeps plain string as string" do
      JustYAML.load("hello").should eq("hello")
    end

    it "keeps single-quoted string as string" do
      JustYAML.load("'true'").should eq("true")
    end

    it "keeps double-quoted string as string" do
      JustYAML.load("\"123\"").should eq("123")
    end

    it "preserves quoted null" do
      JustYAML.load("'null'").should eq("null")
    end
  end

  describe "merge keys" do
    it "merges mapping with <<" do
      yaml = <<-YAML
        defaults: &defaults
          adapter: postgres
          host: localhost
        development:
          <<: *defaults
          database: dev_db
        YAML

      result = JustYAML.load(yaml)
      result.should eq({
        "defaults" => {
          "adapter" => "postgres",
          "host"    => "localhost",
        },
        "development" => {
          "adapter"  => "postgres",
          "host"     => "localhost",
          "database" => "dev_db",
        },
      })
    end

    it "does not override existing keys on merge" do
      yaml = <<-YAML
        base: &base
          name: default
        derived:
          <<: *base
          name: custom
        YAML

      result = JustYAML.load(yaml)
      result.as(Hash)["derived"].as(Hash)["name"].should eq("custom")
    end
  end

  describe "complex structures" do
    it "resolves mixed types in sequence" do
      yaml = "[1, true, hello, null]"
      result = JustYAML.load(yaml)
      result.should eq([1_i64, true, "hello", nil])
    end

    it "resolves mixed types in mapping" do
      yaml = <<-YAML
        int: 42
        bool: true
        string: hello
        null_val: null
        YAML

      result = JustYAML.load(yaml)
      result.should eq({
        "int"      => 42_i64,
        "bool"     => true,
        "string"   => "hello",
        "null_val" => nil,
      })
    end
  end
end
