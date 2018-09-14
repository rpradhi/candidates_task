require 'bundler/setup'
require 'pry'

module Rails
  extend self

  def env
    'test'
  end

  def root
    Dir.pwd
  end

  def logger
    @logger ||= Class.new do
      def info(*args)
      end
    end.new
  end
end

RSpec.configure do |config|
end

