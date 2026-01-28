module JustYAML
  enum TokenType
    # Structure
    StreamStart
    StreamEnd
    DocumentStart # ---
    DocumentEnd   # ...
    Indent        # Virtual token for increased indentation
    Dedent        # Virtual token for decreased indentation
    Newline

    # Indicators
    KeyIndicator   # ?
    ValueIndicator # :
    SequenceEntry  # -
    MappingStart   # {
    MappingEnd     # }
    SequenceStart  # [
    SequenceEnd    # ]
    FlowSeparator  # ,

    # Content
    Scalar
    BlockScalarHeader # | or > with optional modifiers
    Anchor            # &name
    Alias             # *name
    Tag               # !tag

    # Comments
    Comment # #...

    # Directives
    Directive # %YAML, %TAG
  end

  enum ScalarTokenStyle
    Plain
    SingleQuoted
    DoubleQuoted
  end

  class Token
    getter type : TokenType
    getter value : String
    getter location : Location
    getter scalar_style : ScalarTokenStyle

    def initialize(@type : TokenType, @value : String, @location : Location, @scalar_style : ScalarTokenStyle = ScalarTokenStyle::Plain)
    end

    def to_s(io : IO) : Nil
      io << type << "(" << value.inspect << ") at " << location
    end
  end
end
