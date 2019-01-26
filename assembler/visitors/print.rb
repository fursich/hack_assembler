module Assembler
  module Visitor
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

