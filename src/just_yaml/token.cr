module JustYAML
  enum TokenType
    # Structure
    StreamStart
    StreamEnd
    Newline

    # Indicators
    ValueIndicator # :

    # Content
    Scalar
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
