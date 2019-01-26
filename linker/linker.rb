require_relative 'symbol_table.rb'

module Linker
  class InvalidStructure; end

  class SymbolResolver
    def initialize(symbols)
      @symbols = symbols
    end

    def visit(node)
      if node.a_command?
        label = node.right
        raise InvalidStructure, 'invalid structure: a-command must have a label' unless label.is_a? Expression::AddressNode
        label.value = @symbols.resolve(label.name) unless label.value
      end
    end
  end
end

