module Assembler
  class CommandCollection
    extend Forwardable
    def_delegators :@tree, :[]

    attr_reader :tree

    def initialize
      @tree = {}
      @source_locations = {}
    end
  
    def register(code, lineno: , source_location: nil)
      @tree[lineno]             = code if code
      @source_locations[lineno] = source_location # record source lineno
      @tree
    end

    def each(&block)
      return self.to_enum unless block_given?
      0.upto max_lineno do |lineno|
        yield(@tree[lineno])
      end
    end

    private

    def max_lineno
      @tree.keys.compact.max
    end
  end
end
