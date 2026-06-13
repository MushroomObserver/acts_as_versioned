require "rubygems"
require "bundler"
Bundler.setup(:default, :development)

$:.unshift(File.dirname(__FILE__) + '/../lib')
require 'minitest/autorun'
require 'active_support'
require 'active_support/test_case'
require 'active_record'
require 'active_record/fixtures'

require 'acts_as_versioned'

class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end

config = YAML::load(IO.read(File.dirname(__FILE__) + '/database.yml'))
ActiveRecord::Base.logger = Logger.new(File.dirname(__FILE__) + "/debug.log")
ActiveRecord::Base.establish_connection(config[ENV['DB'] || 'sqlite3'])

load(File.dirname(__FILE__) + "/schema.rb")

# set up custom sequence on widget_versions for DBs that support sequences
if ENV['DB'] == 'postgresql'
  ActiveRecord::Base.connection.execute "DROP SEQUENCE widgets_seq;" rescue nil
  ActiveRecord::Base.connection.remove_column :widget_versions, :id
  ActiveRecord::Base.connection.execute "CREATE SEQUENCE widgets_seq START 101;"
  ActiveRecord::Base.connection.execute "ALTER TABLE widget_versions ADD COLUMN id INTEGER PRIMARY KEY DEFAULT nextval('widgets_seq');"
end

class ActiveSupport::TestCase #:nodoc:
  include ActiveRecord::TestFixtures

  self.fixture_paths = [File.dirname(__FILE__) + "/fixtures/"]

  # Turn off transactional fixtures if you're working with MyISAM tables in MySQL
  self.use_transactional_tests = true

  # Instantiated fixtures are slow, but give you @david where you otherwise would need people(:david)
  self.use_instantiated_fixtures  = false
end

$:.unshift(ActiveSupport::TestCase.fixture_paths.first)