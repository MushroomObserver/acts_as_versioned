require File.join(File.dirname(__FILE__), 'abstract_unit')

class Thing < ActiveRecord::Base
  attr_accessor :version
  acts_as_versioned
end

class MigrationTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  MIGRATIONS_PATH = File.dirname(__FILE__) + '/fixtures/migrations/'

  def teardown
    ActiveRecord::Base.connection.execute("DELETE FROM schema_migrations") rescue nil
    Thing.connection.drop_table "things" rescue nil
    Thing.connection.drop_table "thing_versions" rescue nil
  end

  def setup
    ActiveRecord::Base.connection.execute("DELETE FROM schema_migrations") rescue nil
    Thing.connection.drop_table "things" rescue nil
    Thing.connection.drop_table "thing_versions" rescue nil
  end

  def test_versioned_migration
    assert_raises(ActiveRecord::StatementInvalid) { Thing.create :title => 'blah blah' }
    # take 'er up
    ActiveRecord::MigrationContext.new(MIGRATIONS_PATH).migrate
    ActiveRecord::Base.connection.schema_cache.clear!
    Thing.reset_column_information

    t = Thing.create :title => 'blah blah', :price => 123.45, :type => 'Thing'
    assert_equal 1, t.versions.size

    # check that the price column has remembered its value correctly
    assert_equal t.price,  t.versions.first.price
    assert_equal t.title,  t.versions.first.title
    assert_equal t[:type], t.versions.first[:versioned_type]

    # make sure that the precision of the price column has been preserved
    assert_equal 7, Thing::Version.columns.find { |c| c.name == "price" }.precision
    assert_equal 2, Thing::Version.columns.find { |c| c.name == "price" }.scale

    # now lets take 'er back down
    ActiveRecord::MigrationContext.new(MIGRATIONS_PATH).migrate(0)
    ActiveRecord::Base.connection.schema_cache.clear!
    Thing.reset_column_information
    assert_raises(ActiveRecord::StatementInvalid) { Thing.create :title => 'blah blah' }
  end
end
