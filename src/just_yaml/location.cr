module JustYAML
  record Location, line : Int32, column : Int32 do
    def to_s(io : IO) : Nil
      io << "line " << line << ", column " << column
    end
  end
end
