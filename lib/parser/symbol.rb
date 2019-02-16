module ParseTree
  class SymbolBase
    STRENGTH = {
      ACommandOperator: 0,
      LCommandOperator: 0,
      CCommandOperator: 0,
      BlankCommand:     0,
      JumpOperator:     1,
      SubstOperator:    3,
      OrOperator:       4,
      AndOperator:      5,
      SubtractOperator: 6,
      AddOperator:      6,
      NagateOperator:   8,
      NotOperator:      8,
      Condition:        10,
      Register:         10,
      Numeric:          10,
      Address:          10,
      Label:            10,
    }

    attr_accessor :value
    attr_reader :strength

    def initialize(value)
      @value = value
      @strength = fetch_strength
      raise ParseError, "strength not defined with symbol #{self.class.name}" unless @strength
    end
 
    def symbol?
      raise NotImplementedError
    end

    def operator?
      !symbol?
    end

    private
  
    def validate_child!(symbol)
      raise # no children accepted
    end

    def fetch_strength
      STRENGTH[self.class.name.split('::').last.to_sym]
    end
  end

  class Symbol < SymbolBase
    def value_as_array
      value
    end

    def symbol?
      true
    end
  end
  
  class Operator < SymbolBase
    attr_accessor :left, :right
  
    def initialize(value, left: nil, right: nil)
      super(value)
      @left, @right = left, right
    end

    def left=(symbol)
      validate_left_child!(symbol)
      @left = symbol
    end
  
    def right=(symbol)
      validate_right_child!(symbol)
      @right = symbol
    end
  
    def set_left!(symbol)
      @left = symbol
    end
  
    def set_right!(symbol)
      @right = symbol
    end

    def value_as_array
      [left&.value_as_array, value, right&.value_as_array]
    end

    def symbol?
      false
    end

    private

    def validate_left_child!(symbol)
      # override if necessary
      raise ParseError, "wrong structure detected in operating #{value_as_array} on \'#{symbol.value}\'" if @left
    end

    def validate_right_child!(symbol)
      # override if necessary
      raise ParseError, "wrong structure detected in operating #{value_as_array} on \'#{symbol.value}\'" if @right
    end
  end
  
  class UnaryOperator < Operator

    def initialize(value, right: nil)
      super(value, left: nil, right: right)
    end

    def value_as_array
      [value, right&.value_as_array]
    end
  end
  
  class BinaryOperator < Operator
  
    def initialize(value, left: nil, right: nil)
      super(value, left: left, right: right)
    end
  end
  
  class Address < Symbol
    def build
      Expression::AddressNode.new(value)
    end
  end
  
  class Label < Symbol
    attr_accessor :name
    def initialize(value=nil)
      super
    end

    def build
      Expression::AddressNode.new(value).tap { |node| node.name = name }
    end
  end
  
  class BlankCommand < Symbol
    def initialize(value='')
      super value
    end

    def build
      Expression::BlankNode.new(value)
    end
  end

  class ACommandOperator < UnaryOperator
    def initialize
      super('A')
    end

    def build
      Expression::ACommandNode.new(value, right.build)
    end
  end
  
  class LCommandOperator < UnaryOperator
    attr_accessor :name
    def initialize
      super('L')
    end

    def build
      Expression::LCommandNode.new(value, right.build)
    end
  end
  
  class CCommandOperator < UnaryOperator
    def initialize
      super('C')
    end

    def build
      Expression::CCommandNode.new(value, right.build)
    end
  end

  module CCommand
    class Condition < Symbol
      def build
        Expression::JumpConditionNode.new(value)
      end
    end

    class Register < Symbol
      def build
        Expression::RegisterNode.new(value)
      end
    end
  
    class Numeric < Symbol
      def build
        Expression::NumericNode.new(value)
      end
    end

    class NotOperator < UnaryOperator
      def build
        Expression::NotOperatorNode.new(value, right.build)
      end
    end
  
    class NagateOperator < UnaryOperator
      def build
        Expression::NagateOperatorNode.new(value, right.build)
      end
    end
  
    class JumpOperator < BinaryOperator
      def build
        Expression::JumpNode.new(value, left.build, right.build)
      end
    end
  
    class SubstOperator < BinaryOperator
      def build
        Expression::DestNode.new(value, left.build, right.build)
      end
    end
  
    class AddOperator < BinaryOperator
      def build
        Expression::AddOperatorNode.new(value, left.build, right.build)
      end
    end
  
    class SubtractOperator < BinaryOperator
      def build
        Expression::SubOperatorNode.new(value, left.build, right.build)
      end
    end
  
    class AndOperator < BinaryOperator
      def build
        Expression::AndOperatorNode.new(value, left.build, right.build)
      end
    end
  
    class OrOperator < BinaryOperator
      def build
        Expression::OrOperatorNode.new(value, left.build, right.build)
      end
    end
  end
end

