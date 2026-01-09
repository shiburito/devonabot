# frozen_string_literal: true

module DevonaBot
  module Commands
    class DiscordCommand

      attr_reader :id, :command, :description, :subcommands
      def initialize(id, command, description, subcommands = [])
        @id = id
        @command = command
        @description = description
        @subcommands = subcommands
      end

      def register(sub)
        raise 'You must implement the register method in your command'
      end

      def execute(event)
        raise 'You must implement the execute method in your command'
      end

    end
  end
end