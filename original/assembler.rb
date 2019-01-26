module Assembler
  class Error < StandardError; end
  class FileError < Error; end

  class FileIO
    def initialize(filename)
      @filename = filename
    end

    def read
      source = []
      begin
        File.open(@filename) do |file|
          source = file.read.split(/\r?\n/).map.with_index(1){ |l, i| [i, l] }
        end
      rescue => e
        raise FileError, "#{e.class} #{e.message}\n an error occured while reading the source file.\n"
      end
      source
    end

    def write(arr)
      begin
        File.open(@filename, 'w') do |file|
          arr.each do |line|
            file.write("#{line}\n")
          end
        end
      rescue => e
        raise FileError, "#{e.class} #{e.message}\n an error occured while writing the output file.\n"
      end
    end
  end
end

# usage
# load 'assembler.rb'
# assembler = Assembler::Driver.new('add/Add.asm')
# assembler.run

class Assembler
  class Driver
    attr_reader :source, :commands, :symbols

    def initialize(filename)
      @filename = Pathname.new(filename)
      raise FileError, 'illegal file type' if @filename.extname != '.asm'
      @output_filename = @filename.sub_ext('.hack')

      @source = read_file
      @commands = CommandCollection.new
      @symbols = SymbolTable.new
      reset_line_counter!
    end

    def run
      parse_all!
      print
      resolve
      print
      @hack = convert
      write_file
    end

    def read_file
      FileIO.new(@filename).read
    end

    def write_file
      FileIO.new(@output_filename).write(@hack)
    end
  
    def parse_all!
      @source.each do |source_location, text|
        parser = ParseTree::ParseStrategy::Mapper.new(text, source_location: source_location).parser
        parser.parse!
        expression = parser.build! # expressionは単独のExpressionインスタンス（配列ではないことを仮定）
        next if expression.blank?

        if expression.l_command?
          @symbols.register(expression.name, as: line_counter)
        else
          @commands.register(expression, lineno: line_counter, source_location: source_location)
          increment_line_counter!
        end
      end
      add_parent!
      add_depth!
      @commands
    end

    def resolve
      visitor = Code::SymbolResolver.new(@symbols)
      @commands.each do |command|
        command.accept(visitor)
      end
    end

    def convert
      Code::MLConverter.new(*structurize_commands).convert
    end

    def print
      Util::PrintCommand.new(*structurize_commands).perform
    end

    def structurize_commands
      visitor = Visitor::CommandVisitor.new
      @commands.each.with_object([]) do |command, result|
        result << command.accept(visitor)
      end
    end

    private

    def add_parent!
      visitor = Visitor::ParentLinkVisitor.new
      @commands.each do |command|
        command.accept visitor
      end
    end

    def add_depth!
      visitor = Visitor::MeasureDepthVisitor.new
      @commands.each do |command|
        command.accept visitor
      end
    end

    def line_counter
      @line_counter ||= 0
    end
    
    def increment_line_counter!
      @line_counter = line_counter + 1
    end

    def reset_line_counter!
      @line_counter = 0
    end
  end
end

module Assembler
  module Util
    class PrintCommand
      def initialize(*commands)
        @commands = commands
      end

      def perform
        @commands.each.with_index do |command, idx|
          if command.keys.include? :address
            puts "#{idx}: @#{command[:address]}"
          else
            source_format = [[ command[:dest], command[:comp] ].compact.join('='), command[:jump] ].compact.join(';')
            puts "#{idx}: #{source_format}"
          end
        end
      end
    end
  end
end

module Assembler
  class SyntaxError < Error; end
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

  class SymbolTable
    class DoubleRegistration < Error; end
    
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

module Code
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

  class MLConverter
    def initialize(*commands)
      @commands = commands
    end

    def convert
      @commands.map do |command|
        if command.include? :address
          self.class.convert_a_command(**command)
        else
          self.class.convert_c_command(**command)
        end
      end
    end

    def address(val)
      sprintf("%.15d", val.to_i.to_s(2))
    end
    class << self
      def convert_a_command(**command)
        prefix(:a_command) + address(command[:address])
      end

      def address(val)
        sprintf("%.15d", val.to_i.to_s(2))
      end

      def convert_c_command(**command)
        prefix = prefix(:c_command)
        dest_part = retrieve_element(:dest, **command)
        jump_part = retrieve_element(:jump, **command)
        comp_part = comp[command[:comp]]
        prefix + comp_part + dest_part + jump_part
      end

      def retrieve_element(key, **command)
        command[key] ? send(key)[command[key]] : '000'
      end

      def prefix(type)
        type == :a_command ? '0' : '111'
      end

      def comp
        @comp ||= COMP.transform_values {|v| v.to_s.gsub('_', '')}
      end

      def jump
        @jump ||= JUMP.transform_values {|v| v.to_s.gsub('_', '')}
      end

      def dest
        @dest ||= DEST.transform_values {|v| v.to_s.gsub('_', '')}
      end
    end
  end

  COMP = {
    '0'   => '0_101010',
    '1'   => '0_111111',
    '-1'  => '0_111010',
    'D'   => '0_001100',
    'A'   => '0_110000',
    'M'   => '1_110000',
    '!D'  => '0_001101',
    '!A'  => '0_110001',
    '!M'  => '1_110001',
    '-D'  => '0_001111',
    '-A'  => '0_110011',
    '-M'  => '1_110011',

    'D+1' => '0_011111',
    'A+1' => '0_110111',
    'M+1' => '1_110111',
    'D-1' => '0_001110',
    'A-1' => '0_110010',
    'M-1' => '1_110010',

    'D+A' => '0_000010',
    'D+M' => '1_000010',
    'D-A' => '0_010011',
    'D-M' => '1_010011',
    'A-D' => '0_000111',
    'M-D' => '1_000111',
    'D&A' => '0_000000',
    'D&M' => '1_000000',
    'D|A' => '0_010101',
    'D|M' => '1_010101',
  }

  DEST = {
     nil  => '000',
    'M'   => '001',
    'D'   => '010',
    'MD'  => '011',
    'A'   => '100',
    'AM'  => '101',
    'AD'  => '110',
    'AMD' => '111',
  }

  JUMP = {
     nil  => '000',
    'JGT' => '001',
    'JEQ' => '010',
    'JGE' => '011',
    'JLT' => '100',
    'JNE' => '101',
    'JLE' => '110',
    'JMP' => '111',
  }
end

module ParseTree
  class ParseError < StandardError; end
  module ParseStrategy
    class Mapper
      class UndefinedCommandPattern < ParseError; end

      def initialize(text, source_location:)
        @text   = strip_ignorables(text)
        @source_location = source_location
      end

      def parser
        return NullCommandParser.new(@text, source_location: @source_location) if null_command?
        return ACommandParser.new(@text, source_location: @source_location) if a_command?
        return LCommandParser.new(@text, source_location: @source_location) if l_command?
        return CCommandParser.new(@text, source_location: @source_location) if c_command?
        raise UndefinedCommandPattern, "Cannot interpret the command <#{@text}> at line #{@source_location}"
      end

      private

      def strip_ignorables(text)
        text.rstrip.lstrip.gsub(/\/\/.*\z/, '')
      end

      def null_command?
        NullCommandParser.has_type?(@text)
      end
      
      def a_command?
        ACommandParser.has_type?(@text)
      end
  
      def l_command?
        LCommandParser.has_type?(@text)
      end
  
      def c_command?
        !(a_command? || l_command?)
      end
    end

    module Appendable
      def insert_symbol_or_number(symbol, command)
        # add symbol to table

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

    class ParserBase
      include Appendable

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

      NULL_TYPE        = /\A[[:space:]]*(\/\/.*)?\z/
      A_COMMAND_TYPE   = /\A@.*\z/
      L_COMMAND_TYPE   = /\A\(.*\)\z/

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
    end

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

    class ACommandParser < ParserBase

      def do_parse!(token) 
        if token.nil?
          raise # TODO should be end of line
        end

        case token
        when LABEL
          symbol = Label.new
          symbol.name = token
          insert_symbol_or_number(symbol, @command)
        when NUMBER
          number = Address.new(token)
          insert_symbol_or_number(number, @command)
        when A_COMMAND
          operator = ACommandOperator.new
          insert_operator(operator, @command)
        when BLANK_FILLER
          # do nothing
        else
          raise # unspoorted syntax
        end
      end

      def self.has_type?(text)
        text =~ A_COMMAND_TYPE
      end

      private

      def tokenizer
        A_COMMAND_TOKENIZER
      end
    end

    class LCommandParser < ParserBase
      def before_parse
        @depth = 0
      end

      def validate_status!
        raise ParseError, "unmatching parentesis detected. depth: #{@depth}" 
        super
      end

      def do_parse!(token)
        if token.nil?
          raise # TODO should be end of line
        end
  
        case token
        when LABEL
          symbol = Label.new
          symbol.name = token
          insert_symbol_or_number(symbol, @command)
        when L_COMMAND_START
          @depth += 1
          operator = LCommandOperator.new
          insert_operator(operator, @command)
        when L_COMMAND_END
          @depth -= 1
        when BLANK_FILLER
          # do nothing
        else
          raise # unspoorted syntax
        end
      end

      def self.has_type?(text)
        text =~ L_COMMAND_TYPE
      end

      private

      def tokenizer
        L_COMMAND_TOKENIZER
      end
    end

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

      private

      def tokenizer
        C_COMMAND_TOKENIZER
      end
    end
  end

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
