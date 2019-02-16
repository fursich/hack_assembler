module Expression
  class NodeBase
    attr_accessor :value
    attr_accessor :parent, :left, :right
    attr_accessor :depth

    def initialize(value)
      @value = value
    end

    def accept(visitor)
      visitor.visit(self)
    end

    def a_command?
      false
    end

    def c_command?
      false
    end

    def l_command?
      false
    end

    def blank?
      false
    end
  end

  class LeafNode < NodeBase
  end

  class BlankNode < LeafNode
    def blank?
      true
    end
  end

  class AddressNode < LeafNode
    attr_accessor :name
  end

  class NumericNode < LeafNode
  end

  class RegisterNode < LeafNode
  end

  class JumpConditionNode < LeafNode
  end

  class CompositeNode < NodeBase
    def initialize(value, left, right)
      @left = left
      @right = right
      super(value)
    end
  end

  class UnaryCompositeNode < CompositeNode
    def initialize(value, right)
      super(value, nil, right)
    end
  end

  class BinaryCompositeNode < CompositeNode
    def initialize(value, left, right)
      super(value, left, right)
    end
  end

  class NotOperatorNode < UnaryCompositeNode
  end

  class NagateOperatorNode < UnaryCompositeNode
  end

  class ACommandNode < UnaryCompositeNode
    def a_command?
      true
    end
  end

  class CCommandNode < UnaryCompositeNode
    def c_command?
      true
    end
  end

  class LCommandNode < UnaryCompositeNode
    def name
      right.name # assuming that LCommandNode should only contain a label with name
    end

    def l_command?
      true
    end
  end

  class JumpNode < BinaryCompositeNode
  end

  class DestNode < BinaryCompositeNode
  end

  class AddOperatorNode < BinaryCompositeNode
  end

  class SubOperatorNode < BinaryCompositeNode
  end

  class AndOperatorNode < BinaryCompositeNode
  end

  class OrOperatorNode < BinaryCompositeNode
  end
end

