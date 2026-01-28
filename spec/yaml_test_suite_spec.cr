require "./spec_helper"
require "json"

# Integration tests against the official yaml-test-suite
# https://github.com/yaml/yaml-test-suite

describe "YAML Test Suite" do
  test_suite_path = File.join(__DIR__, "..", "yaml-test-suite")

  # Skip if yaml-test-suite is not available
  pending "yaml-test-suite not found" unless Dir.exists?(test_suite_path)

  # Get all test case directories
  test_dirs = Dir.glob(File.join(test_suite_path, "*")).select do |path|
    File.directory?(path) && File.basename(path) =~ /^[A-Z0-9]{4}$/
  end

  # Track statistics
  passed = 0
  failed = 0
  skipped = 0

  test_dirs.sort.each do |test_dir|
    test_id = File.basename(test_dir)
    in_yaml_path = File.join(test_dir, "in.yaml")
    error_path = File.join(test_dir, "error")
    in_json_path = File.join(test_dir, "in.json")
    desc_path = File.join(test_dir, "===")

    # Skip if no input file
    next unless File.exists?(in_yaml_path)

    # Get test description
    test_desc = if File.exists?(desc_path)
                  File.read(desc_path).strip
                else
                  test_id
                end

    has_error = File.exists?(error_path)
    input = File.read(in_yaml_path)

    describe "#{test_id}: #{test_desc}" do
      if has_error
        it "rejects invalid YAML" do
          expect_raises(JustYAML::Error) { JustYAML.parse(input) }
        end
      else
        it "parses valid YAML" do
          ast = JustYAML.parse(input)
          ast.should_not be_nil
        end

        if File.exists?(in_json_path)
          it "resolves to expected value" do
            expected_json = File.read(in_json_path)
            # Handle multi-document YAML which has newline-separated JSON values
            json_lines = expected_json.strip.split('\n').map(&.strip).reject(&.empty?)

            # Try to parse as single JSON first, fall back to multi-doc
            expected_values = begin
              [JSON.parse(expected_json)]
            rescue JSON::ParseException
              # Multi-document: parse each line as separate JSON
              json_lines.map { |line| JSON.parse(line) }
            end

            actual = JustYAML.load(input)

            if expected_values.size == 1
              compare_values(actual, expected_values.first)
            else
              # Multi-document result should be an array
              actual_arr = actual.as(Array)
              actual_arr.size.should eq(expected_values.size)
              actual_arr.zip(expected_values) do |a, e|
                compare_values(a, e)
              end
            end
          end
        end
      end
    end
  end
end

# Helper to compare JustYAML::Any with JSON::Any
private def compare_values(actual : JustYAML::Any, expected : JSON::Any) : Nil
  case expected.raw
  when Nil
    actual.should be_nil
  when Bool
    actual.should eq(expected.as_bool)
  when Int64
    actual.should eq(expected.as_i64)
  when Float64
    if expected.as_f.nan?
      actual.as(Float64).nan?.should be_true
    elsif expected.as_f.infinite?
      actual.should eq(expected.as_f)
    else
      actual.should eq(expected.as_f)
    end
  when String
    actual.should eq(expected.as_s)
  when Array
    actual_arr = actual.as(Array)
    expected_arr = expected.as_a
    actual_arr.size.should eq(expected_arr.size)
    actual_arr.zip(expected_arr) do |a, e|
      compare_values(a, e)
    end
  when Hash
    actual_hash = actual.as(Hash)
    expected_hash = expected.as_h
    actual_hash.size.should eq(expected_hash.size)
    expected_hash.each do |key, val|
      actual_hash.has_key?(key).should be_true, "Missing key: #{key}"
      compare_values(actual_hash[key], val)
    end
  end
end
