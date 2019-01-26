module ParseTree
  module ParseStrategy
    class LCommandParser < ParserBase

      def before_parse
        @depth = 0
      end

      def validate_status!
        raise ParseError, "unmatching parentesis detected. depth: #{@depth}" 
        super
      end

      def do_parse!(token)
        if token.nil?
          raise # TODO should be end of line
        end
  
        case token
        when LABEL
          symbol = Label.new
          symbol.name = token
          insert_symbol_or_number(symbol, @command)
        when L_COMMAND_START
          @depth += 1
          operator = LCommandOperator.new
          insert_operator(operator, @command)
        when L_COMMAND_END
          @depth -= 1
        when BLANK_FILLER
          # do nothing
        else
          raise # unspoorted syntax
        end
      end

      def self.has_type?(text)
        text =~ L_COMMAND_TYPE
      end

      private

      def tokenizer
        L_COMMAND_TOKENIZER
      end
    end
  end
end

