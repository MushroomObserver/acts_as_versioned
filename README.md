# acts_as_versioned

Adds simple versioning to an ActiveRecord module. ActiveRecord is required.

## Resources

Install

* `gem install mo_acts_as_versioned`

GitHub

* `https://github.com/MushroomObserver/acts_as_versioned`

## Behaviors worth knowing

* **Destroying the host does not cascade to versions.** Versions are
  preserved as an audit trail with their FK still pointing at the
  deleted parent. To get cascade-delete, pass
  `association_options: { dependent: :delete_all }` to
  `acts_as_versioned`. To clear the FK on destroy, pass `:nullify`.
* **`belongs_to :user` is auto-wired on the version class** when the
  versioned table has a `user_id` column. Calls like `version.user`
  just work; no need to hand-define the association on every host
  model. The wiring is idempotent — if you've already defined
  `belongs_to :user` (via `:extend` or directly), the gem skips.
  Eager-load with `parent.versions.includes(:user)` to avoid N+1.
* **The `versions` cache stays in sync after a save.** When a new
  version is created, it's appended to the parent's loaded `versions`
  association (only if already loaded — no unwanted lazy loads or
  `strict_loading` violations). This prevents the stale-read bug where
  `parent.versions.last` would return the old top-of-collection right
  after a save.

Special thanks to Dreamer on ##rubyonrails for help in early testing.
His ServerSideWiki (http://serversidewiki.com)
was the first project to use `acts_as_versioned` **in the wild**.

Copyright (c) 2005 Rick Olson, 2018 Mushroom Observer, Inc.

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
