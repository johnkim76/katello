module Katello
  module ContentSearchHelper
    def content_types
      types = [
        [_("Products"), "products"],
        [_("Repositories"), "repos"],
        [_("Packages"), "packages"],
        [_("Puppet Modules"), "puppet_modules"]
      ]

      types.unshift([_("Content Views"), "views"]) if ContentView.readable?

      types
    end

    def errata_display(errata)
      {
        :errata_type => errata[:type],
        :id => errata.id,
        :errata_id => errata.errata_id
      }
    end

    def package_display(package)
      {
        :name => package.name,
        :vel_rel_arch => package.send(:nvrea).sub(package.send(:name) + '-', ''),
        :id => package.id
      }
    end

    def puppet_module_display(puppet_module)
      {
        :name_version => [puppet_module.name, puppet_module.version].join('-'),
        :author => puppet_module.author,
        :id => puppet_module.id
      }
    end

    def repo_compare_name_display(repo)
      {
        :environment_name => repo.environment.name,
        :repo_name => repo.name,
        :content_view_name => repo.content_view.name,
        :type => "repo-comparison",
        :custom => true
      }
    end
  end
end
