class Landmark < ActiveRecord::Base
  acts_as_versioned :if_changed => [ :name, :longitude, :latitude ]
end

class User < ActiveRecord::Base
end

# Exercises the :extend-overrides-autowire path: the table has user_id (so
# auto-wire would normally fire with class_name: "::User"), but the extend
# block defines belongs_to :user with a custom foreign_key. The extend
# definition must win.
class Sighting < ActiveRecord::Base
  acts_as_versioned do
    def self.included(base)
      base.belongs_to :user, :class_name => '::User',
                             :foreign_key => :reporter_id, :optional => true
    end
  end
end
