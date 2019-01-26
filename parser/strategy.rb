require_relative 'strategy/base.rb'
require_relative 'strategy/null_command.rb'
require_relative 'strategy/a_command.rb'
require_relative 'strategy/l_command.rb'
require_relative 'strategy/c_command.rb'

module ParseTree
  class ParseError < StandardError; end
  module ParseStrategy
    class Mapper
      class UndefinedCommandPattern < ParseError; end

      def initialize(text, source_location:)
        @text   = strip_ignorables(text)
        @source_location = source_location
      end

      def parser
        return NullCommandParser.new(@text, source_location: @source_location) if null_command?
        return ACommandParser.new(@text, source_location: @source_location) if a_command?
        return LCommandParser.new(@text, source_location: @source_location) if l_command?
        return CCommandParser.new(@text, source_location: @source_location) if c_command?
        raise UndefinedCommandPattern, "Cannot interpret the command <#{@text}> at line #{@source_location}"
      end

      private

      def strip_ignorables(text)
        text.rstrip.lstrip.gsub(/\/\/.*\z/, '')
      end

      def null_command?
        NullCommandParser.has_type?(@text)
      end
      
      def a_command?
        ACommandParser.has_type?(@text)
      end
  
      def l_command?
        LCommandParser.has_type?(@text)
      end
  
      def c_command?
        !(a_command? || l_command?)
      end
    end
  end
end
