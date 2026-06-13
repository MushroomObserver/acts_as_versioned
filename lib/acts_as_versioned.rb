require "active_support/concern"
require "active_support/core_ext/kernel/reporting"

module ActiveRecord # :nodoc:
  module Acts # :nodoc:
    # Specify this act if you want to save a copy of the row in a versioned
    # table.  This assumes there is a versioned table ready and that your model
    # has a version field.  This works with optimistic locking if the
    # lock_version column is present as well.
    #
    # The class for the versioned model is derived the first time it is seen.
    # Therefore, if you change your database schema you have to restart
    # your container for the changes to be reflected. In development mode this
    # usually means restarting WEBrick.
    #
    #   class Page < ActiveRecord::Base
    #     # assumes pages_versions table
    #     acts_as_versioned
    #   end
    #
    # Example:
    #
    #   page = Page.create(:title => 'hello world!')
    #   page.version       # => 1
    #
    #   page.title = 'hello world'
    #   page.save
    #   page.version       # => 2
    #   page.versions.size # => 2
    #
    #   page.revert_to(1)  # using version number
    #   page.title         # => 'hello world!'
    #
    #   page.revert_to(page.versions.last) # using versioned instance
    #   page.title         # => 'hello world'
    #
    #   page.versions.earliest # efficient query to find the first version
    #   page.versions.latest   # efficient query to find the
    #                            most recently created version
    #
    #
    # Simple Queries to page between versions
    #
    #   page.versions.before(version)
    #   page.versions.after(version)
    #
    # Access the previous/next versions from the versioned model itself
    #
    #   version = page.versions.latest
    #   version.previous # go back one version
    #   version.next     # go forward one version
    #
    # See ActiveRecord::Acts::Versioned::ClassMethods#acts_as_versioned
    # for configuration options
    module Versioned
      VERSION   = "0.8.0"
      CALLBACKS = [:set_new_version, :save_version, :save_version?]

      # == Configuration options
      #
      # * <tt>class_name</tt> - versioned model class name
      #                         (default: PageVersion in the above example)
      # * <tt>table_name</tt> - versioned model table name
      #                         (default: page_versions in the above example)
      # * <tt>foreign_key</tt> - foreign key used to relate the versioned model
      #                          to the original model
      #                          (default: page_id in the above example)
      # * <tt>inheritance_column</tt> - name of the column to save the model's inheritance_column value for STI.  (default: versioned_type)
      # * <tt>version_column</tt> - name of the column in the model that keeps the version number (default: version)
      # * <tt>sequence_name</tt> - name of the custom sequence to be used by the versioned model.
      # * <tt>limit</tt> - number of revisions to keep, defaults to unlimited
      # * <tt>if</tt> - symbol of method to check before saving a new version.  If this method returns false, a new version is not saved.
      #   For finer control, pass either a Proc or modify Model#version_condition_met?
      #
      #     acts_as_versioned :if => Proc.new { |auction| !auction.expired? }
      #
      #   or...
      #
      #     class Auction
      #       def version_condition_met? # totally bypasses the <tt>:if</tt> option
      #         !expired?
      #       end
      #     end
      #
      # * <tt>if_changed</tt> - Simple way of specifying attributes that are required to be changed before saving a model.  This takes
      #   either a symbol or array of symbols.
      #
      # * <tt>association_options</tt> - Hash merged into the generated
      #   <tt>has_many :versions</tt> association on the host model.
      #   Useful for overriding <tt>:dependent</tt>, <tt>:foreign_key</tt>,
      #   or other has_many options. By default no <tt>:dependent</tt> is
      #   set, which means destroying the host record does NOT cascade to
      #   the version rows — they are kept as an audit trail with their
      #   FK still pointing at the now-deleted parent. This is the
      #   intended behavior for history/audit use cases. To get the
      #   pre-2014 cascade-delete behavior, pass
      #   <tt>:association_options => {:dependent => :delete_all}</tt>;
      #   to clear the FK on destroy (orphan-but-decoupled), pass
      #   <tt>:dependent => :nullify</tt>.
      #
      # * <tt>extend</tt> - Lets you specify a module to be mixed in both the original and versioned models.  You can also just pass a block
      #   to create an anonymous mixin:
      #
      #     class Auction
      #       acts_as_versioned do
      #         def started?
      #           !started_at.nil?
      #         end
      #       end
      #     end
      #
      #   or...
      #
      #     module AuctionExtension
      #       def started?
      #         !started_at.nil?
      #       end
      #     end
      #     class Auction
      #       acts_as_versioned :extend => AuctionExtension
      #     end
      #
      #  Example code:
      #
      #    @auction = Auction.find(1)
      #    @auction.started?
      #    @auction.versions.first.started?
      #
      # == Database Schema
      #
      # The model that you're versioning needs to have a 'version' attribute.
      # The model is versioned into a table called #{model}_versions where the
      # model name is singlular. The _versions table should contain all the
      # fields you want versioned, the same version column, and a #{model}_id
      # foreign key field.
      #
      # A lock_version field is also accepted if your model uses Optimistic
      # Locking.  If your table uses Single Table inheritance, then that field
      # is reflected in the versioned model as 'versioned_type' by default.
      #
      # Acts_as_versioned comes prepared with the ActiveRecord::Acts::
      # Versioned::ActMethods::ClassMethods#create_versioned_table
      # method, perfect for a migration.  It will also create the version
      # column if the main model does not already have it.
      #
      #   class AddVersions < ActiveRecord::Migration
      #     def self.up
      #       # create_versioned_table takes the same options hash
      #       # that create_table does
      #       Post.create_versioned_table
      #     end
      #
      #     def self.down
      #       Post.drop_versioned_table
      #     end
      #   end
      #
      # == Auto-wired belongs_to :user on the Version class
      #
      # If the versioned table has a <tt>user_id</tt> column, the gem
      # automatically defines <tt>belongs_to :user, class_name: "::User",
      # optional: true</tt> on the dynamic version class, so callers can
      # read <tt>version.user</tt> without hand-defining the association
      # on every host model.
      #
      # The wiring is idempotent: if you've already defined
      # <tt>belongs_to :user</tt> on the version class (e.g. via the
      # <tt>:extend</tt> module, or directly), the auto-wire skips and
      # your definition is preserved.
      #
      # To avoid N+1 when iterating versions, eager-load the user:
      #
      #   page.versions.includes(:user).each { |v| v.user.name }
      #
      # == Keeping the loaded versions cache consistent
      #
      # When a new version row is saved, the gem appends it to the
      # parent's <tt>versions</tt> association cache if (and only if) the
      # collection has already been loaded. This prevents this stale-read
      # bug:
      #
      #   page.versions.to_a       # loads collection [v1]
      #   page.update(title: "x")  # creates v2 in DB
      #   page.versions.last       # would otherwise return v1 from cache
      #
      # The <tt>loaded?</tt> guard means parents that never read
      # <tt>versions</tt> do not trigger an unwanted lazy-load (which
      # would itself be a strict_loading violation on host models that
      # set <tt>strict_loading_by_default = true</tt>).
      #
      # == Changing What Fields Are Versioned
      #
      # By default, acts_as_versioned will version all but these fields:
      #
      #   [self.primary_key, inheritance_column, 'version', 'lock_version',
      #    versioned_inheritance_column]
      #
      # You can add or change those by modifying #non_versioned_columns.
      # Note that this takes strings and not symbols.
      #
      #   class Post < ActiveRecord::Base
      #     acts_as_versioned
      #     self.non_versioned_columns << 'comments_count'
      #   end
      #
      def acts_as_versioned(options = {}, &extension)
        # don't allow multiple calls
        if included_modules.include?(ActiveRecord::Acts::Versioned::Behaviors)
          return
        end

        cattr_accessor(:versioned_class_name, :versioned_foreign_key,
                       :versioned_table_name, :versioned_inheritance_column,
                       :version_column, :max_version_limit,
                       :track_altered_attributes, :version_condition,
                       :version_sequence_name, :non_versioned_columns,
                       :version_association_options, :version_if_changed)

        self.versioned_class_name = options[:class_name] || "Version"
        self.versioned_foreign_key = options[:foreign_key] || to_s.foreign_key
        self.versioned_table_name =
          options[:table_name] ||
          "#{table_name_prefix}#{base_class.name.demodulize.underscore}" \
          "_versions#{table_name_suffix}"
        self.versioned_inheritance_column = options[:inheritance_column] ||
                                            "versioned_#{inheritance_column}"
        self.version_column = options[:version_column] || "version"
        self.version_sequence_name = options[:sequence_name]
        self.max_version_limit = options[:limit].to_i
        self.version_condition = options[:if] || true
        self.non_versioned_columns =
          [primary_key, inheritance_column, version_column, "lock_version",
           versioned_inheritance_column] +
          options[:non_versioned_columns].to_a.map(&:to_s)
        self.version_association_options = {
          class_name: "#{self}::#{versioned_class_name}",
          foreign_key: versioned_foreign_key
        }.merge(options[:association_options] || {})

        if extension
          extension_module_name = "#{versioned_class_name}Extension"
          silence_warnings do
            const_set(extension_module_name, Module.new(&extension))
          end

          options[:extend] = const_get(extension_module_name)
        end

        unless options[:if_changed].nil?
          self.track_altered_attributes = true
          unless options[:if_changed].is_a?(Array)
            options[:if_changed] =
              [options[:if_changed]]
          end
          self.version_if_changed = options[:if_changed].map(&:to_s)
        end

        include(options[:extend]) if options[:extend].is_a?(Module)

        include(ActiveRecord::Acts::Versioned::Behaviors)

        #
        # Create the dynamic versioned model
        #
        const_set(versioned_class_name,
                  Class.new(ApplicationRecord)).class_eval do
          def self.reloadable?
            false
          end

          # find first version before the given version
          def self.before(version)
            where(
              ["#{original_class.versioned_foreign_key} = ? and version < ?",
               version.send(original_class.versioned_foreign_key),
               version.version]
            ).order(version: :desc).first
          end

          # find first version after the given version.
          def self.after(version)
            where(
              ["#{original_class.versioned_foreign_key} = ? and version > ?",
               version.send(original_class.versioned_foreign_key),
               version.version]
            ).order(version: :asc).first
          end

          # finds earliest version of this record
          def self.earliest
            order(original_class.version_column.to_s).first
          end

          # find latest version of this record
          def self.latest
            order("#{original_class.version_column}": :desc).first
          end

          def previous
            self.class.before(self)
          end

          def next
            self.class.after(self)
          end

          def versions_count
            page.version
          end
        end

        versioned_class.cattr_accessor(:original_class)
        versioned_class.original_class = self
        versioned_class.table_name = versioned_table_name
        versioned_class.belongs_to(to_s.demodulize.underscore.to_sym,
                                   class_name: "::#{self}",
                                   foreign_key: versioned_foreign_key)

        if options[:extend].is_a?(Module)
          versioned_class.send(:include,
                               options[:extend])
        end

        # Auto-wire belongs_to :user on the version class when the versioned
        # table carries a user_id column, so callers get `version.user`
        # without hand-defining the association on every host model. Runs
        # AFTER the :extend module so any host-defined belongs_to :user
        # (different FK, different class_name, etc.) wins via the
        # reflect_on_association idempotency check.
        has_user_id = versioned_class.column_names.include?("user_id") rescue false
        if has_user_id && !versioned_class.reflect_on_association(:user)
          versioned_class.belongs_to(:user, class_name: "::User", optional: true)
        end
        return unless version_sequence_name

        versioned_class.sequence_name = version_sequence_name
      end

    end
  end
end

require_relative "behaviors"

ActiveSupport.on_load(:active_record) { extend ActiveRecord::Acts::Versioned }
