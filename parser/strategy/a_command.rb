module ParseTree
  module ParseStrategy
    class ACommandParser < ParserBase

      def do_parse!(token) 
        if token.nil?
          raise # TODO should be end of line
        end

        case token
        when LABEL
          symbol = Label.new
          symbol.name = token
          insert_symbol_or_number(symbol, @command)
        when NUMBER
          number = Address.new(token)
          insert_symbol_or_number(number, @command)
        when A_COMMAND
          operator = ACommandOperator.new
          insert_operator(operator, @command)
        when BLANK_FILLER
          # do nothing
        else
          raise # unspoorted syntax
        end
      end

      def self.has_type?(text)
        text =~ A_COMMAND_TYPE
      end

      private

      def tokenizer
        A_COMMAND_TOKENIZER
      end
    end
  end
end

