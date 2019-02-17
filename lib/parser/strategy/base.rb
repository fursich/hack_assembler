module ParseTree
  module ParseStrategy
    class ParserBase

      A_COMMAND        = /@/
      L_COMMAND_START  = /\(/
      L_COMMAND_END    = /\)/
      
      LABEL            = /[a-zA-Z_\.$:][a-zA-Z0-9_\.$:]*/
      NUMBER           = /[0-9]+/
      
      C_COMMAND_JUMP   = /;/
      C_COMMAND_COND   = /JLT|JMP|JGT|JLE|JNE|JGE|JEQ/
      C_COMMAND_JUMP_PART = /#{C_COMMAND_JUMP}|#{C_COMMAND_COND}/

      REGISTER         = /AM?D?|MD?|D/
      C_COMMAND_NUMBER = /0|1/

      C_COMMAND_SUBST  = /=/

      C_COMMAND_PLUS   = /\+/
      C_COMMAND_MINUS  = /\-/
      C_COMMAND_NOT    = /!/
      C_COMMAND_AND    = /&/
      C_COMMAND_OR     = /\|/
      C_COMMAND_OPERATORS = /#{C_COMMAND_SUBST}|#{C_COMMAND_PLUS}|#{C_COMMAND_MINUS}|#{C_COMMAND_NOT}|#{C_COMMAND_AND}|#{C_COMMAND_OR}/

      BLANK_FILLER     = /[[:space:]]+/
      SINGLE_LINE      = /[[:^cntrl:]]+/

      NULL_TYPE        = /\A[[:space:]]*(\/\/.*)?\z/
      A_COMMAND_TYPE   = /\A@#{SINGLE_LINE}\z/
      L_COMMAND_TYPE   = /\A\(#{SINGLE_LINE}\)\z/
      C_COMMAND_TYPE   = /\A(#{SINGLE_LINE})\z/

      A_COMMAND_TOKENIZER = /#{A_COMMAND}|#{LABEL}|#{NUMBER}|#{BLANK_FILLER}|./
      L_COMMAND_TOKENIZER = /#{L_COMMAND_START}|#{L_COMMAND_END}|#{LABEL}|#{NUMBER}|#{BLANK_FILLER}|./
      C_COMMAND_TOKENIZER = /#{C_COMMAND_OPERATORS}#{C_COMMAND_JUMP_PART}#{REGISTER}|#{LABEL}|#{NUMBER}|#{BLANK_FILLER}|./
      # TOKENIZER = /@|\(|\)|\+|\-|=|;|!|&|\||#{LABEL}|#{NUMBER}|#{BLANK_FILLER}|.?/

      def initialize(text, source_location: )
        @tokens = text.scan(tokenizer)
        @source_location = source_location
        @command = Assembler::Command.new
        @expression = nil
      end

      def next_token
        @tokens.shift
      end
  
      def parse!
        before_parse
        while token = next_token
          do_parse! token
        end
        validate_command!

#         optimize_parse_tree!  # TODO

        @command.each { |tree| p tree.value_as_array } # XXX: for checking
        @command
      end

      def build!
        tree = @command.first       # FIXME 配列のうち最初の要素だけを取り扱う（必ずしも１つとは保証されていない）。あとでエラー制御ちゃんとする
        @expression = tree.build # 本来、配列の要素が複数あるのは構文エラー
      end

      private

      def before_parse
        # TODO check global state for structure where necessary
      end

      def validate_command!
        raise ParseError, "more than two lines contained at line: #{@source_location}" if @command.size > 1
        # implement where necessary # TODO
      end

      def tokenizer
        raise NotImplementedError
      end

      def do_parse!
        raise NotImplementedError
      end

      def insert_symbol_or_number(symbol, command)
        if command.none?
          command.push symbol
        else
          parent = command.peek
          while parent.right&.operator?
            parent = parent.right
          end
          if parent.right.nil?
            parent.right = symbol
          else
            command.push symbol
          end
        end
      end

      def insert_operator(operator, command)
        if command.none?
          command.push operator
        else
          parent = command.peek
          if parent.strength >= operator.strength
            operator.left = command.pop
            command.push operator
          else
            while parent.right && parent.right.strength < operator.strength
              parent = parent.right
            end
            operator.left = parent.right
            parent.set_right! operator
          end
        end
      end
    end
  end
end

