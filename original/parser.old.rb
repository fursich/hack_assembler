class Assembler
  class Error < StandardError; end
  class FileError < Error; end

  attr_reader :source, :codes
  def initialize(filename)
    @filename = filename
    lines     = []
    begin
      File.open(filename) do |file|
        lines = file.read.split("\n").map.with_index{ |l, i| [i, l] }
      end
    rescue => e
      raise FileError, "#{e.class} #{e.message}\n an error occured while reading the source file.\n"
    end

    @source = Source.new(lines)
    @codes  = Commands.new
  end

  def parse_all!
    while @source.has_more_commands?
      @source.advance
      @codes << @source.parsed
    end
    self
  end

  class Commands
    def initialize
      @commands = []
      @addresses = {}
      reset_counter!
    end

    def << (command)
      case command.command_type
      when :a_command
        store!(command, offset: @counter)
        increment_counter!
      when :l_command
        register!(command, offset: @counter + 1)
      when :c_command
        store!(command, offset: @counter)
        increment_counter!
      end
    end

    #FIXME TODO
    def walk_at(offset)
#      @commands[offset]
    end

    private

    def store!(command, offset: )
      command.offset = offset
      @commands.last.next = command unless @commands.empty?
      @commands << command
    end

    def register!(command, offset: )
      # FIXME アドレスととラベルのマッピングを即時解決する
      # l_command.register_key!
      if @addresses.has_key?(offset)
        @addresses[offset] << command
      else
        @addresses[offset] = [command]
      end
    end

    def reset_counter!
      @counter = 0
    end
    
    def increment_counter!
      @counter += 1
    end
  end

  class Source
    extend Forwardable
  
    def_delegators :@parsed, :command_type, :symbol, :dest, :comp, :jummp
    attr_reader :parsed
  
    def initialize(lines)
      @lines = lines
    end
  
    def advance
      return unless has_more_commands?
      parse_new_line!
      @parsed
    end
  
    def has_more_commands?
      !@lines.empty?
    end
  
    private
  
    def parse_new_line!
      lineno, command = @lines.shift
      parser = Parser::Generator.new(command, lineno: lineno).parser
      @parsed   = parser.parse!
    end
  end
end

module Code
  module Mnemonic
    COMP = {
      '0'  => '0_101010',
      '1'  => '0_111111',
      '-1' => '0_111010',
      'D'  => '0_001100',
      'A'  => '0_110000',
      'M'  => '1_110000',
      '!D' => '0_001101',
      '!A' => '0_110001',
      '!M' => '1_110001',
      '-D' => '0_001111',
      '-A' => '0_110011',
      '-M' => '1_110011',

      'D+1'=> '0_011111',
      'A+1'=> '0_110111',
      'M+1'=> '1_110111',
      'D-1'=> '0_001110',
      'A-1'=> '0_110010',
      'M-1'=> '1_110010',

      'D+A'=> '0_000010',
      'D+M'=> '1_000010',
      'D-A'=> '0_010011',
      'D-M'=> '1_010011',
      'A-D'=> '0_000111',
      'M-D'=> '1_000111',
      'D&A'=> '0_000000',
      'D&M'=> '1_000000',
      'D|A'=> '0_010101',
      'D|M'=> '1_010101',
    }

    DEST = {
      nil   => '000',
      'M'   => '001',
      'D'   => '010',
      'MD'  => '011',
      'A'   => '100',
      'AM'  => '101',
      'AD'  => '110',
      'AMD' => '111',
    }

    JUMMP = {
      nil   => '000',
      'JGT' => '001',
      'JEQ' => '010',
      'JGE' => '011',
      'JLT' => '100',
      'JNE' => '101',
      'JLE' => '110',
      'JMP' => '111',
    }
  end

  class EncoderBase
    def initialize(command)
      @command = command
    end

    def encode!
      raise NotImplementedError
    end
  end

  class AddressEncoder
    def encode!
    end
  end
end

module Parser
  class ParseError < Assembler::Error; end
  class InvalidStructure < ParseError; end
  class InvalidCommand < ParseError; end
  class UndefinedCommandPattern < ParseError; end

  class Generator

    def initialize(line, lineno: )
      @line   = strip_ignorables(line)
      @lineno = lineno
    end

    def parser
      return NullCommand.new(@line, lineno: @lineno) if null_command?
      return ACommand.new(@line, lineno: @lineno) if a_command?
      return LCommand.new(@line, lineno: @lineno) if l_command?
      return CCommand.new(@line, lineno: @lineno) if c_command?
      raise UndefinedCommandPattern, "Cannot interpret the command <#{@line}> at line #{@lineno}"
    end

    private

    def strip_ignorables(line)
      line.rstrip.lstrip.gsub(/\/\/.*\z/, '')
    end

    def null_command?
      NullCommand.has_type?(@line)
    end
    
    def a_command?
      ACommand.has_type?(@line)
    end
  
    def c_command?
      !(a_command? || l_command?)
    end
  
    def l_command?
      LCommand.has_type?(@line)
    end
  end
end

module Parser
  class CommandBase
    attr_accessor :next, :offset

    def initialize(line, lineno:)
      @line = line.lstrip.rstrip
      @lineno = lineno
    end

    def parse!
      @parsed ||= do_parse!
      self
    end

    def do_parse!
      raise NotImplementedError
    end

    def command_type
      raise NotImplementedError
    end
  end

  class CommandNode < CommandBase
    attr_accessor :children

    def accept(visitor)
      visitor.visit(self, *children.map {|child| child.accept(visitor) })
    end

    def value
      nil
    end
  end

  class CommandLeaf < CommandBase
    def accept(visitor)
      visitor.visit(self)
    end

    def value
      raise NotImplementedError
    end
  end
end

module Parser
  SYMBOL_FORMAT = /[a-zA-Z_\.$:][a-zA-Z0-9_\.$:]*/
  NUMERIC_FORMAT = /[0-9]+/

  class NullCommand < CommandLeaf
    NULL_TYPE = /\A[[:space:]]*(\/\/.*)?\z/
    def do_parse!
      []
    end

    def command_type
      :null_command
    end

    def self.has_type?(line)
      line =~ NULL_TYPE
    end
  end

  class ACommand < CommandLeaf
    ADDRESS_TYPE = /\A@\S*\z/
    ADDRESS = Regexp.union( /\A@(#{SYMBOL_FORMAT})\z/, /\A@(#{NUMERIC_FORMAT})\z/)

    def do_parse!
      # TODO 形式がおかしい場合を厳密にチェック
      # 特に@が２つ入るなど不正な形をはじく
      @line.scan(ADDRESS).flatten.compact
    end

    def value
      @parsed.first
    end
    alias_method :symbol, :value

    def command_type
      :a_command
    end

    def self.has_type?(line)
      line =~ ADDRESS_TYPE
    end
  end

  class LCommand < CommandLeaf
    LABEL_TYPE   = /\A\(\S*\)\z/
    LABEL = /\A\((#{SYMBOL_FORMAT})\)\z/

    def do_parse!
      @line.scan(LABEL).flatten
    end

    def value
      @parsed.first
    end
    alias_method :symbol, :value

    def command_type
      :l_command
    end

    def self.has_type?(line)
      line =~ LABEL_TYPE
    end
  end
  
  class CCommand < CommandNode
    DESTINATION_TOKEN  = '='
    JUMP_CONDITION_TOKEN = ';'

    attr_accessor :next, :offset

    def do_parse!
      validate_token_count!(DESTINATION_TOKEN)
      validate_token_count!(JUMP_CONDITION_TOKEN)
      validate_token_order!(DESTINATION_TOKEN, JUMP_CONDITION_TOKEN)
      validate_token_position!(DESTINATION_TOKEN)
      validate_token_position!(JUMP_CONDITION_TOKEN)

      dest, line = try_split(@line, by: DESTINATION_TOKEN)    || ['', @line]
      comp, jump = try_split(line,  by: JUMP_CONDITION_TOKEN) || [line, '']

      [
        DestinationParser.new(dest,   lineno: @lineno).parse!,
        ComputableParser.new(comp,    lineno: @lineno).parse!,
        JumpConditionParser.new(jump, lineno: @lineno).parse!,
      ]
    end

    def command_type
      :c_command
    end

    def dest
      @parsed[0].value
    end
  
    def comp
      @parsed[1].value
    end
  
    def jump
      @parsed[2].value
    end

    private

    def count_token(token, from: )
      from.count(token)
    end

    def try_split(str, by: )
      return str.split(by, -1) if count_token(by, from: str).nonzero?
      nil
    end

    def validate_token_count!(token)
      if count_token(token, from: @line) > 1
        raise InvalidStructure, "syntax error: multiple tokens \'#{token}\' detected at line: #{@lineno}"
      end
      true
    end

    def validate_token_order!(*tokens)
      tokens_indices = tokens.map{ |token| @line.index(token) }.compact
      if tokens_indices != tokens_indices.sort
        raise InvalidStructure, "syntax error: illegal command structure detected at line: #{@lineno}"
      end
      true
    end

    def validate_token_position!(token)
      if [@line[0], @line[-1]].include? token
        raise InvalidStructure, "syntax error: token \'#{token}\' is placed on either end of command at line: #{@lineno}"
      end
    end
  end
end

module Parser
  class DestinationParser < CommandLeaf
    COMMAND_DEST    = /\A(AM?D?|MD?|D)\z/

    def do_parse!
      validate_register_names!
      @line
    end

    def value
      @parsed.first
    end

    private

    def validate_register_names!
      return if @line.empty?
      raise InvalidCommand, "invalid register name \'#{@line}\' at line: #{@lineno}" if @line !~ COMMAND_DEST
    end
  end

  class ComputableParser < CommandLeaf
    COMMAND_COMP         = /\A[+\-&|!01ADM]+\z/
    SINGLE_ELEMENT_BASE  = /[1DAM]/
    SINGLE_ELEMENT       = /0|#{SINGLE_ELEMENT_BASE}/
    DOUBLE_ELEMENTS      = /[\-!]#{SINGLE_ELEMENT_BASE}/
    TRIPLE_ELEMENTS      = /[AMD][&|+\-]#{SINGLE_ELEMENT_BASE}/

    def do_parse!
      @line.gsub!(/\s/, '')
      validate_length!
      validate_charactors!
      validate_format!
      @line
    end

    def value
      @parsed.first
    end

    private

    def validate_charactors!
      raise InvalidCommand, "invalid charactor(s) used within command \'#{@line}\' at line: #{@lineno}" if @line !~ COMMAND_COMP
    end

    def validate_length!
      raise InvalidCommand, "comp is empty at line: #{@lineno}" if @line.empty?
      raise InvalidCommand, "comp \'#{@line}\' has too many charactors (>3) at line: #{@lineno}" if @line.length > 3
    end

    def validate_format!
      case @line.length
      when 1
        raise InvalidCommand, "invalid command \'#{@line}\' at line: #{@lineno}" if @line !~ SINGLE_ELEMENT
      when 2
        raise InvalidCommand, "invalid command \'#{@line}\' at line: #{@lineno}" if @line !~ DOUBLE_ELEMENTS
      when 3
        raise InvalidCommand, "invalid command \'#{@line}\' at line: #{@lineno}" if @line !~ TRIPLE_ELEMENTS
      end
      validate_duplication! # avoid commands such as M-M
    end

    def validate_duplication!
      duplicated = @line.each_char.select{ |c| @line.count(c) > 1}.first
      raise InvalidCommand, "same register \'#{duplicated}\' appears more than once within a single command \'#{@line}\' at line: #{@lineno}" if duplicated
    end
  end

  class JumpConditionParser < CommandLeaf
    COMMAND_JUMP = /\AJ(LT|MP|GT|LE|NE|GE)\z/

    def do_parse!
      validate_jump_conditions!
      @line
    end

    def value
      @parsed.first
    end

    private

    def validate_jump_conditions!
      return if @line.empty?
      raise InvalidCommand, "invalid jump condition \'#{@line}\' at line: #{@lineno}" if @line !~ COMMAND_JUMP
    end
  end
end
