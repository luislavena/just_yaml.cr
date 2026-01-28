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

# Custom exception for JSON parsing errors with position info
class JSONParseError < Exception
  getter byte_offset : Int32
  getter snippet : String

  def initialize(message : String, @byte_offset : Int32, @snippet : String)
    super("#{message} at byte #{@byte_offset}: #{@snippet}")
  end
end

# Helper to compute a safe snippet around an error position
private def error_snippet(str : String, pos : Int32, context_bytes : Int32 = 20) : String
  start_pos = {0, pos - context_bytes}.max
  end_pos = {str.bytesize, pos + context_bytes}.min

  # Build the snippet safely
  snippet = String.build do |io|
    io << "..." if start_pos > 0
    io << str[start_pos...end_pos].gsub(/[\r\n\t]/) { |c|
      case c
      when "\r" then "\\r"
      when "\n" then "\\n"
      when "\t" then "\\t"
      else           c
      end
    }
    io << "..." if end_pos < str.bytesize
  end

  snippet
end

# Check if a character can start a valid JSON value
private def valid_json_start?(char : Char) : Bool
  case char
  when '"', '{', '[', 't', 'f', 'n', '-'
    true
  else
    char.number?
  end
end

# Parse multiple JSON values from a string
# Raises JSONParseError if parsing fails or trailing non-whitespace remains
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

    # Check if this could be the start of a valid JSON value
    start_char = str[pos]
    value_start = pos

    unless valid_json_start?(start_char)
      snippet = error_snippet(str, pos)
      raise JSONParseError.new("Unexpected trailing content", pos, snippet)
    end

    # Determine the end of the current JSON value
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
    rescue ex : JSON::ParseException
      snippet = error_snippet(str, value_start)
      raise JSONParseError.new("Failed to parse JSON value", value_start, snippet)
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

describe "parse_multiple_json_values" do
  describe "valid multi-value files" do
    it "parses a single JSON value" do
      result = parse_multiple_json_values(%({"key": "value"}))
      result.size.should eq(1)
      result[0].as_h["key"].as_s.should eq("value")
    end

    it "parses multiple newline-separated JSON objects" do
      json = %({"a": 1}\n{"b": 2}\n{"c": 3})
      result = parse_multiple_json_values(json)
      result.size.should eq(3)
      result[0].as_h["a"].as_i.should eq(1)
      result[1].as_h["b"].as_i.should eq(2)
      result[2].as_h["c"].as_i.should eq(3)
    end

    it "parses multiple JSON arrays" do
      json = %([1, 2, 3]\n["a", "b"])
      result = parse_multiple_json_values(json)
      result.size.should eq(2)
      result[0].as_a.size.should eq(3)
      result[1].as_a.size.should eq(2)
    end

    it "parses multiple primitive values" do
      json = %(true\nfalse\nnull\n42\n"string")
      result = parse_multiple_json_values(json)
      result.size.should eq(5)
      result[0].as_bool.should be_true
      result[1].as_bool.should be_false
      result[2].raw.should be_nil
      result[3].as_i.should eq(42)
      result[4].as_s.should eq("string")
    end

    it "handles leading and trailing whitespace" do
      json = %(  \n  {"key": 1}  \n  )
      result = parse_multiple_json_values(json)
      result.size.should eq(1)
      result[0].as_h["key"].as_i.should eq(1)
    end

    it "handles empty input" do
      result = parse_multiple_json_values("")
      result.size.should eq(0)
    end

    it "handles whitespace-only input" do
      result = parse_multiple_json_values("  \n\t\n  ")
      result.size.should eq(0)
    end
  end

  describe "trailing garbage detection" do
    it "raises error for trailing non-JSON content" do
      json = %({"valid": true} garbage)
      ex = expect_raises(JSONParseError) { parse_multiple_json_values(json) }
      ex.byte_offset.should eq(16)
      ex.message.to_s.should contain("Unexpected trailing content")
      ex.snippet.should contain("garbage")
    end

    it "raises error for incomplete JSON followed by garbage" do
      json = %([1, 2, 3] extra stuff here)
      ex = expect_raises(JSONParseError) { parse_multiple_json_values(json) }
      ex.message.to_s.should contain("Unexpected trailing content")
    end

    it "raises error for random characters after valid JSON" do
      json = %(42 @#$%)
      ex = expect_raises(JSONParseError) { parse_multiple_json_values(json) }
      ex.message.to_s.should contain("Unexpected trailing content")
    end
  end

  describe "invalid JSON in the middle" do
    it "raises error for malformed object" do
      json = %({"a": 1}\n{invalid}\n{"c": 3})
      ex = expect_raises(JSONParseError) { parse_multiple_json_values(json) }
      ex.message.to_s.should contain("Failed to parse JSON value")
      ex.byte_offset.should eq(9)
    end

    it "raises error for truncated array" do
      json = %({"ok": true}\n[1, 2,)
      ex = expect_raises(JSONParseError) { parse_multiple_json_values(json) }
      ex.message.to_s.should contain("Failed to parse JSON value")
    end

    it "raises error for invalid literal" do
      json = %(true\nfals\nnull)
      ex = expect_raises(JSONParseError) { parse_multiple_json_values(json) }
      ex.message.to_s.should contain("Failed to parse JSON value")
    end
  end

  describe "error_snippet helper" do
    it "provides context around error position" do
      json = %({"valid": true} this is garbage after the json)
      ex = expect_raises(JSONParseError) { parse_multiple_json_values(json) }
      ex.snippet.should_not be_empty
    end

    it "escapes newlines in snippet" do
      json = %({"a": 1}\ngarbage\nmore)
      ex = expect_raises(JSONParseError) { parse_multiple_json_values(json) }
      # Snippet should contain escaped newlines
      ex.snippet.should contain("\\n")
    end

    it "adds ellipsis for long content" do
      # Create a long string where the error is in the middle
      prefix = "x" * 50
      json = %({"a": 1}\n) + prefix + "garbage"
      ex = expect_raises(JSONParseError) { parse_multiple_json_values(json) }
      ex.snippet.should contain("...")
    end
  end
end
