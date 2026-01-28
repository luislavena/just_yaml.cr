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

            # Parse all JSON values from the file (handles multi-document)
            expected_values = parse_multiple_json_values(expected_json)

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

# Parse multiple JSON values from a string
private def parse_multiple_json_values(json_str : String) : Array(JSON::Any)
  results = [] of JSON::Any
  pos = 0
  str = json_str

  while pos < str.bytesize
    # Skip whitespace
    while pos < str.bytesize && str[pos].whitespace?
      pos += 1
    end

    break if pos >= str.bytesize

    # Determine the end of the current JSON value
    start_char = str[pos]

    value_end = case start_char
                when '"'
                  # String: find matching unescaped quote
                  find_string_end(str, pos)
                when '{', '['
                  # Object/Array: find matching bracket
                  find_bracket_end(str, pos)
                when 't'
                  pos + 4 # true
                when 'f'
                  pos + 5 # false
                when 'n'
                  pos + 4 # null
                else
                  # Number: find end of number
                  find_number_end(str, pos)
                end

    # Extract and parse the value
    value_str = str[pos...value_end]
    begin
      result = JSON.parse(value_str)
      results << result
      pos = value_end
    rescue JSON::ParseException
      break
    end
  end

  results
end

private def find_string_end(str : String, start : Int32) : Int32
  pos = start + 1 # Skip opening quote
  while pos < str.bytesize
    if str[pos] == '\\'
      pos += 2 # Skip escaped char
    elsif str[pos] == '"'
      return pos + 1
    else
      pos += 1
    end
  end
  str.bytesize
end

private def find_bracket_end(str : String, start : Int32) : Int32
  open_bracket = str[start]
  close_bracket = open_bracket == '{' ? '}' : ']'
  depth = 0
  in_string = false
  pos = start

  while pos < str.bytesize
    char = str[pos]
    if in_string
      if char == '\\'
        pos += 1 # Skip next char
      elsif char == '"'
        in_string = false
      end
    else
      case char
      when '"'
        in_string = true
      when open_bracket
        depth += 1
      when close_bracket
        depth -= 1
        if depth == 0
          return pos + 1
        end
      end
    end
    pos += 1
  end

  str.bytesize
end

private def find_number_end(str : String, start : Int32) : Int32
  pos = start
  while pos < str.bytesize
    char = str[pos]
    break unless char == '-' || char == '+' || char == '.' ||
                 char == 'e' || char == 'E' || char.number?
    pos += 1
  end
  pos
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
