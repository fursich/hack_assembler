module Assembler
  module Code
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
end
