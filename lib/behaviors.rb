module ActiveRecord::Acts::Versioned::Behaviors
  extend ActiveSupport::Concern

  included do
    has_many :versions, **version_association_options

    before_save :set_new_version
    after_save :save_version
    after_save :clear_old_versions
  end

  # Saves a version of the model in the versioned table.
  # This is called in the after_save callback by default
  def save_version
    return unless @saving_version

    @saving_version = nil
    rev = self.class.versioned_class.new
    clone_versioned_model(self, rev)
    rev.send(:"#{self.class.version_column}=",
             send(self.class.version_column))
    rev.send(:"#{self.class.versioned_foreign_key}=", id)
    rev.save
    # Keep the parent's loaded `versions` cache in sync with the new row so
    # callers don't see stale data after a save. The `loaded?` guard avoids
    # triggering an unwanted lazy-load (which would itself be a
    # strict_loading violation) on parents that never read `versions` in the
    # same request.
    versions << rev if versions.loaded?
  end

  # Clears old revisions if a limit is set with the :limit option in
  # <tt>acts_as_versioned</tt>.
  # Override this method to set your own criteria for clearing old
  # versions.
  def clear_old_versions
    return if self.class.max_version_limit.zero?

    excess_baggage = send(self.class.version_column).to_i -
                     self.class.max_version_limit
    return unless excess_baggage.positive?

    self.class.versioned_class.where(
      ["#{self.class.version_column} <= ? and " \
       "#{self.class.versioned_foreign_key} = ?",
       excess_baggage, id]
    ).delete_all
  end

  # Reverts a model to a given version.
  # Takes either a version number or an instance of the versioned model
  def revert_to(version)
    if version.is_a?(self.class.versioned_class)
      unless version.send(self.class.versioned_foreign_key) == id &&
             !version.new_record?
        return false
      end
    else
      unless (
        version =
          versions.where(self.class.version_column => version).first
      )
        return false
      end
    end
    clone_versioned_model(version, self)
    send(:"#{self.class.version_column}=",
         version.send(self.class.version_column))
    true
  end

  # Reverts a model to a given version and saves the model.
  # Takes either a version number or an instance of the versioned model
  def revert_to!(version)
    revert_to(version) ? save_without_revision : false
  end

  # Temporarily turns off Optimistic Locking while saving.
  # Used when reverting so that a new version is not created.
  def save_without_revision
    save_without_revision!
    true
  rescue StandardError
    false
  end

  def save_without_revision!
    without_locking do
      without_revision do
        save!
      end
    end
  end

  def altered?
    if track_altered_attributes
      (version_if_changed - changed).length < version_if_changed.length
    else
      changed?
    end
  end

  # Clones a model.
  # Used when saving a new version or reverting a model's version.
  def clone_versioned_model(orig_model, new_model)
    self.class.versioned_columns.each do |col|
      next unless orig_model.has_attribute?(col.name)

      val = orig_model[col.name]
      if orig_model.defined_enums.has_key?(col.name)
        val = orig_model.defined_enums[col.name][val]
      end
      new_model[col.name] = val
    end

    clone_inheritance_column(orig_model, new_model)
  end

  def clone_inheritance_column(orig_model, new_model)
    if orig_model.is_a?(self.class.versioned_class) &&
       new_model.class.column_names.include?(
         new_model.class.inheritance_column.to_s
       )
      new_model[new_model.class.inheritance_column] =
        orig_model[self.class.versioned_inheritance_column]
    elsif new_model.is_a?(self.class.versioned_class) &&
          new_model.class.column_names.include?(
            self.class.versioned_inheritance_column.to_s
          )
      new_model[self.class.versioned_inheritance_column] =
        orig_model[orig_model.class.inheritance_column]
    end
  end

  # Checks whether a new version shall be saved or not.
  # Calls <tt>version_condition_met?</tt> and <tt>changed?</tt>.
  def save_version?
    version_condition_met? && altered?
  end

  # Checks condition set in the :if option to check whether a revision
  # should be created or not.
  # Override this for custom version condition checking.
  def version_condition_met?
    if version_condition.is_a?(Symbol)
      send(version_condition)
    elsif version_condition.respond_to?(:call) &&
          (version_condition.arity == 1 || version_condition.arity == -1)
      version_condition.call(self)
    else
      version_condition
    end
  end

  # Executes the block with the versioning callbacks disabled.
  #
  #   @foo.without_revision do
  #     @foo.save
  #   end
  #
  def without_revision(&block)
    self.class.without_revision(&block)
  end

  # Turns off optimistic locking for the duration of the block
  #
  #   @foo.without_locking do
  #     @foo.save
  #   end
  #
  def without_locking(&block)
    self.class.without_locking(&block)
  end

  def empty_callback; end

  # :nodoc:

  protected

  # sets the new version before saving, unless you're using optimistic
  # locking.  In that case, let it take care of the version.
  def set_new_version
    @saving_version = new_record? || save_version?
    return unless new_record? || (!locking_enabled? && save_version?)

    send(:"#{self.class.version_column}=", next_version)
  end

  # Gets the next available version for the current record,
  # or 1 for a new record
  def next_version
    (if new_record?
       0
     else
       versions.calculate(:maximum, version_column).to_i
     end) + 1
  end

  class_methods do
    # Returns an array of columns that are versioned.
    # See non_versioned_columns
    def versioned_columns
      @versioned_columns ||=
        columns.reject do |c|
          non_versioned_columns.include?(c.name)
        end
    end

    # Returns an instance of the dynamic versioned model
    def versioned_class
      const_get(versioned_class_name)
    end

    # Rake migration task to create the versioned table using options
    # passed to acts_as_versioned
    def create_versioned_table(create_table_options = {})
      # create version column in main table if it does not exist
      unless content_columns.find do |c|
               [version_column.to_s, "lock_version"].include?(c.name)
             end
        connection.add_column(table_name, version_column, :integer)
        reset_column_information
      end

      return if connection.table_exists?(versioned_table_name)

      connection.create_table(versioned_table_name,
                              **create_table_options) do |t|
        t.column(versioned_foreign_key, :integer)
        t.column(version_column, :integer)
      end

      versioned_columns.each do |col|
        limit = col.limit
        if col.limit == 10 && col.type == :integer
          # Avoid 'No integer type has byte size 10' under MySQL
          limit = 8
        end
        connection.add_column(versioned_table_name, col.name, col.type,
                              limit: limit,
                              default: col.default,
                              scale: col.scale,
                              precision: col.precision)
      end

      if type_col = columns_hash[inheritance_column]
        connection.add_column(
          versioned_table_name,
          versioned_inheritance_column,
          type_col.type,
          limit: type_col.limit,
          default: type_col.default,
          scale: type_col.scale,
          precision: type_col.precision
        )
      end

      # Make sure not to create an index that is too long
      # (rails limits index names to 64 characters from version 3.0.3)
      name = "index_#{versioned_table_name}_on_#{versioned_foreign_key}"
      connection.add_index(versioned_table_name, versioned_foreign_key,
                           name: name[0, 63])
    end

    # Rake migration task to drop the versioned table
    def drop_versioned_table
      connection.drop_table(versioned_table_name)
    end

    # Executes the block with the versioning callbacks disabled.
    #
    #   Foo.without_revision do
    #     @foo.save
    #   end
    #
    def without_revision
      class_eval do
        ActiveRecord::Acts::Versioned::CALLBACKS.each do |attr_name|
          alias_method(:"orig_#{attr_name}", attr_name)
          alias_method(attr_name, :empty_callback)
        end
      end
      yield
    ensure
      class_eval do
        ActiveRecord::Acts::Versioned::CALLBACKS.each do |attr_name|
          alias_method(attr_name, :"orig_#{attr_name}")
        end
      end
    end

    # Turns off optimistic locking for the duration of the block
    #
    #   Foo.without_locking do
    #     @foo.save
    #   end
    #
    def without_locking
      current = ActiveRecord::Base.lock_optimistically
      ActiveRecord::Base.lock_optimistically = false if current
      begin
        yield
      ensure
        ActiveRecord::Base.lock_optimistically = true if current
      end
    end
  end
end
