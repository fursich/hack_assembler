module Assembler
  class Command # 単純なArray継承でもいいのでは？
    extend Forwardable
    def_delegators :@tokens, :pop, :push, :size, :first
  
    def initialize
      @tokens = []
    end
  
    def peek
      @tokens.last
    end

    def none?
      @tokens.empty?
    end

    def each(&block)
      return self.to_enum unless block_given?
      @tokens.each {|token| yield token }
    end
  end
end
