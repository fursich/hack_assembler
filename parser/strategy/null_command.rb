module ParseTree
  module ParseStrategy
    class NullCommandParser < ParserBase

      def do_parse!(token)
        noop = BlankCommand.new
        insert_symbol_or_number(noop, @command)
      end

      private

      def tokenizer
        /.*/
      end

      def self.has_type?(text)
        text =~ NULL_TYPE
      end
    end
  end
end
