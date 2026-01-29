module JustYAML
  module AST
    record Comment, text : String, location : Location, preceding_blank_lines : Int32 = 0

    enum ScalarStyle
      Plain
      SingleQuoted
      DoubleQuoted
      Literal
      Folded
    end

    enum CollectionStyle
      Block
      Flow
    end

    abstract class Node
      property start_location : Location = Location.new(1, 1)
      property end_location : Location = Location.new(1, 1)
      property leading_comments : Array(Comment) = [] of Comment
      property trailing_comment : Comment?
      property anchor : String?
      property tag : String?
    end

    class StreamNode < Node
      property documents : Array(DocumentNode) = [] of DocumentNode
    end

    class DocumentNode < Node
      property root : Node?
      property explicit_start : Bool = false
      property explicit_end : Bool = false
    end

    class ScalarNode < Node
      property value : String
      property style : ScalarStyle

      def initialize(@value : String, @style : ScalarStyle = ScalarStyle::Plain)
      end
    end

    class SequenceNode < Node
      property items : Array(Node) = [] of Node
      property style : CollectionStyle = CollectionStyle::Block
    end

    class MappingNode < Node
      property entries : Array(MappingEntry) = [] of MappingEntry
      property style : CollectionStyle = CollectionStyle::Block
    end

    record MappingEntry,
      key : Node,
      value : Node?,
      key_comments : Array(Comment) = [] of Comment
  end
end
