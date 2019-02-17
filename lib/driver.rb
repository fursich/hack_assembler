# usage
# load 'assembler.rb'
# assembler = Assembler::Driver.new('add/Add.asm')
# assembler.run

require 'forwardable'
require_relative 'parser/strategy.rb'

require_relative 'utils/fileio.rb'
require_relative 'linker/linker.rb'
require_relative 'assembler/code.rb'
require_relative 'assembler/visitors.rb'

require_relative 'parser/commands.rb'
require_relative 'parser/command.rb'
require_relative 'parser/symbol.rb'
require_relative 'parser/expression.rb'

module Assembler
  class Driver
    attr_reader :source, :commands, :symbols

    def initialize(filename)
      @filename = Pathname.new(filename)
      raise FileError, 'illegal file type' if @filename.extname != '.asm'
      @output_filename = @filename.sub_ext('.hack')

      @source = read_file
      @commands = CommandCollection.new
      @symbols = Linker::SymbolTable.new
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
      visitor = Linker::SymbolResolver.new(@symbols)
      @commands.each do |command|
        command.accept(visitor)
      end
    end

    def convert
      Code::MLConverter.new(*structurize_commands).convert
    end

    def print
      Visitor::PrintCommand.new(*structurize_commands).perform
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
