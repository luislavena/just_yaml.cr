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
    Anchor # &name
    Alias  # *name
    Tag    # !tag

    # Comments
    Comment # #...

    # Directives
    Directive # %YAML, %TAG
  end

  class Token
    getter type : TokenType
    getter value : String
    getter location : Location

    def initialize(@type : TokenType, @value : String, @location : Location)
    end

    def to_s(io : IO) : Nil
      io << type << "(" << value.inspect << ") at " << location
    end
  end
end
