require File.expand_path('../../lib/driver', __FILE__)
require 'minitest/autorun'

module ParseTree
  module ParseStrategy
    class ParseStrategyTestHelper
      def self.strategy_with_input(text, source_location:, &block)
        strategy = ParseTree::ParseStrategy::Mapper.new(text, source_location: source_location)
        block.call strategy
      end

      def self.parser_with_input(text, source_location:, &block)
        strategy = ParseTree::ParseStrategy::Mapper.new(text, source_location: source_location)
        block.call strategy.parser
      end
    end

    class TestParseLabel < Minitest::Test
      def test_source_location
        ParseStrategyTestHelper.parser_with_input(
          "",
          source_location: 123,
        ) do |parser|
          assert_equal 123, parser.instance_eval { @source_location }
        end
      end

      def test_null_command_strategy
        ParseStrategyTestHelper.parser_with_input(
          "  ",
          source_location: 123,
        ) do |parser|
          assert_instance_of NullCommandParser, parser
        end
      end

      def test_a_command_strategy
        ParseStrategyTestHelper.parser_with_input(
          "@LABEL",
          source_location: 123,
        ) do |parser|
          assert_instance_of ACommandParser, parser
        end
      end

      def test_l_command_strategy
        ParseStrategyTestHelper.parser_with_input(
          "(this.is.a-valid-LABEL)",
          source_location: 123,
        ) do |parser|
          assert_instance_of LCommandParser, parser
        end
      end

      def test_c_command_strategy
        ParseStrategyTestHelper.parser_with_input(
          "M=M+1",
          source_location: 123,
        ) do |parser|
          assert_instance_of CCommandParser, parser
        end
      end

      def test_invalid_l_command
        ParseStrategyTestHelper.strategy_with_input(
          "(MULTIPLE\nLINES)",
          source_location: 123,
        ) do |strategy|
          assert_raises(Mapper::UndefinedCommandPattern) { strategy.parser }
        end
      end

      def test_empty_l_command # FIXME: empty strings are treated as valid l_command
        ParseStrategyTestHelper.parser_with_input(
          "( )",
          source_location: 123,
        ) do |parser|
          assert_instance_of LCommandParser, parser
        end
      end

      def test_invalid_a_command
        ParseStrategyTestHelper.strategy_with_input(
          "@MULTIPLE\nLINES",
          source_location: 123,
        ) do |strategy|
          assert_raises(Mapper::UndefinedCommandPattern) { strategy.parser }
        end
      end

      def test_empty_a_command # FIXME: '@' with empty string are treated as c_command
        ParseStrategyTestHelper.parser_with_input(
          "@ ",
          source_location: 123,
        ) do |parser|
          skip '"@" with empty string should be ACommand, but interpreted as CCommand currently'
          assert_instance_of ACommandParser, parser
        end
      end

      def test_invalid_c_command
        ParseStrategyTestHelper.strategy_with_input(
          "M=\nM+1",
          source_location: 123,
        ) do |strategy|
          assert_raises(Mapper::UndefinedCommandPattern) { strategy.parser }
        end
      end
    end
  end
end
