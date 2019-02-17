module ParseTree
  module ParseStrategy
    class CCommandParser < ParserBase
      def before_parse
        @command.push CCommandOperator.new
      end

      def do_parse!(token)
        if token.nil?
          raise # TODO should be end of line
        end

        case token
        when C_COMMAND_JUMP
          symbol = CCommand::JumpOperator.new(token)
          insert_operator(symbol, @command)
        when C_COMMAND_SUBST
          symbol = CCommand::SubstOperator.new(token)
          insert_operator(symbol, @command)
        when C_COMMAND_PLUS
          symbol = CCommand::AddOperator.new(token)
          insert_operator(symbol, @command)
        when C_COMMAND_MINUS
          if @last_symbol.is_a? Symbol
            symbol = CCommand::SubtractOperator.new(token)
            insert_operator(symbol, @command)
          else
            symbol = CCommand::NagateOperator.new(token)
            insert_operator(symbol, @command)
          end
        when C_COMMAND_NOT
          symbol = CCommand::NotOperator.new(token)
          insert_operator(symbol, @command)
        when C_COMMAND_AND
          symbol = CCommand::AndOperator.new(token)
          insert_operator(symbol, @command)
        when C_COMMAND_OR
          symbol = CCommand::OrOperator.new(token)
          insert_operator(symbol, @command)
        when C_COMMAND_COND
          symbol = CCommand::Condition.new(token)
          insert_symbol_or_number(symbol, @command)
        when REGISTER
          symbol = CCommand::Register.new(token)
          insert_symbol_or_number(symbol, @command)
        when C_COMMAND_NUMBER
          symbol = CCommand::Numeric.new(token)
          insert_symbol_or_number(symbol, @command)
        when BLANK_FILLER
          # do nothing
        else
          raise ParseError, "unparseable syntax #{token}" # unspoorted syntax
        end

        @last_symbol = symbol
      end

      def self.has_type?(text)
        text =~ C_COMMAND_TYPE
      end

      private

      def tokenizer
        C_COMMAND_TOKENIZER
      end
    end
  end
end

