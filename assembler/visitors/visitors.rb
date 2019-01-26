module Assembler
  class SyntaxError < StandardError; end # FIXME ロード順に依存しないように別ファイルでまとめて作成しておく
  module Visitor
    class CommandVisitor
      def visit(node)
        if node.a_command?
          [ node.right.accept(AddressNodeVisitor.new) ].flatten.inject({}, &:merge)
        elsif node.c_command?
          [ node.right.accept(CCommandNodeVisitor.new) ].flatten.inject({}, &:merge)
        else
          raise SyntaxError, "unsupported command #{node.inspect}"
        end
      end
    end
  
    class CCommandNodeVisitor
      def visit(node)
        case node
        when Expression::DestNode
          [ node.left.accept(DestNodeVisitor.new), node.right.accept(CompNodeVisitor.new) ]
        when Expression::JumpNode
          [ node.left.accept(CCommandNodeVisitor.new), node.right.accept(JumpConditionVisitor.new) ]
        when Expression::RegisterNode, Expression::NumericNode, Expression::OperatorNode
          [ CompNodeVisitor.new.visit(node) ]
        else
          raise SyntaxError, "unsupported command type #{node.parent&.value} #{node.value}"
        end
      end
    end

    module ExtrinsicVisitor
      def dig_left(node)
        node.left&.accept(self)
      end
  
      def dig_right(node)
        node.right&.accept(self)
      end
    end

    class AddressNodeVisitor
      def visit(node)
        { address: node.value }
      end
    end

    class DestNodeVisitor
      def visit(node)
        { dest: node.value }
      end
    end

    class JumpConditionVisitor
      def visit(node)
        { jump: node.value }
      end
    end

    class CompNodeVisitor
      def visit(node)
        { comp: CompNodeElementVisitor.new.visit(node).flatten.compact.join }
      end
    end

    class CompNodeElementVisitor
      include ExtrinsicVisitor
      def visit(node)
        [dig_left(node), node.value, dig_right(node)]
      end
    end
  
    class ParentLinkVisitor
      include ExtrinsicVisitor
      def visit(node)
        node.left.parent = node if node.left
        node.right.parent = node if node.right
        dig_left(node)
        dig_right(node)
      end
    end
  
    # make sure to run this visitor after parent link is aded (see ParentLinkVisitor)
    class MeasureDepthVisitor
      include ExtrinsicVisitor
      def visit(node)
        node.depth = node.parent.nil? ? 0 : (node.parent.depth + 1)
        dig_left(node)
        dig_right(node)
      end
    end
  end
end
