module Linker
  class SymbolTable
    class DoubleRegistration < StandardError; end # FIXME エラークラスを統一する（ロード順に依存しない親エラークラスを作成しておく）

    DEFAULT = {
      'SP'     => 0x0000,
      'LCL'    => 0x0001, 
      'ARG'    => 0x0002, 
      'THIS'   => 0x0003, 
      'THAT'   => 0x0004, 
      'SCREEN' => 0x4000, 
      'KBD'    => 0x8000, 
    }.merge( 0.upto(15).map { |idx| ["R#{idx}", idx] }.to_h )

    VARIABLE_HEAP_START = 0x0010

    attr_reader :counter

    def initialize
      @table = DEFAULT.dup
      reset_variable_counter!
    end

    def register(key, as:)
      raise DoubleRegistration if registered?(key)
      @table[key.to_s] = as
    end

    def resolve(key)
      key = key.to_s
      registered?(key) ? @table[key] : set_new_variable!(key)
    end

    private

    def reset_variable_counter!(with: VARIABLE_HEAP_START)
      @counter = with
    end

    def set_new_variable!(key)
      @table[key.to_s] = counter
      @counter += 1
      counter - 1 # returns resolved address
    end

    def registered?(key)
      @table.has_key? key.to_s
    end

    class << self
      extend Forwardable
      def_delegators :@table, :register!, :resolve

      def init_table!
        @table = new
      end
    end
  end
end
