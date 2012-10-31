#
# Copyright 2012 Red Hat, Inc.
#
# This software is licensed to you under the GNU General Public
# License as published by the Free Software Foundation; either version
# 2 of the License (GPLv2) or (at your option) any later version.
# There is NO WARRANTY for this software, express or implied,
# including the implied warranties of MERCHANTABILITY,
# NON-INFRINGEMENT, or FITNESS FOR A PARTICULAR PURPOSE. You should
# have received a copy of GPLv2 along with this software; if not, see
# http://www.gnu.org/licenses/old-licenses/gpl-2.0.txt.

require 'minitest_helper'


class GluePulpRepoTestBase < MiniTest::Rails::ActiveSupport::TestCase
  extend ActiveRecord::TestFixtures

  fixtures :all
  @@admin = nil

  def self.before_suite
    load_fixtures
    configure_runcible

    services  = ['Candlepin', 'ElasticSearch', 'Foreman']
    models    = ['Repository', 'Package']
    disable_glue_layers(services, models)


    @@admin = User.find(@loaded_fixtures['users']['admin']['id'])
  end

  def self.wait_on_tasks(task_list)
    task_list.each do |task|
      while !(['finished', 'error', 'timed_out', 'canceled', 'reset', 'success'].include?(task['state'])) do
        task = PulpSyncStatus.pulp_task(Runcible::Resources::Task.poll(task["task_id"]))
        sleep 0.1 # do not overload backend engines
      end
    end
  end

  def self.wait_on_task(task)
    while !(['finished', 'error', 'timed_out', 'canceled', 'reset', 'success'].include?(task['state'])) do
      task = PulpSyncStatus.pulp_task(Runcible::Resources::Task.poll(task["uuid"]))
      sleep 0.1 # do not overload backend engines
    end
  end

  def setup
    VCR.insert_cassette('glue_pulp_repo', :match_requests_on => [:body_json, :path, :params, :method])
  end

  def teardown
    VCR.eject_cassette
  end

end


class GluePulpRepoTestCreateDestroy < GluePulpRepoTestBase

  def setup
    super
    @fedora_17_x86_64 = Repository.find(repositories(:fedora_17_x86_64).id)
    @fedora_17_x86_64.relative_path = '/test_path/'
    @fedora_17_x86_64.feed = "file://#{File.expand_path(File.dirname(__FILE__))}".gsub("glue/pulp", "fixtures/zoo5")
  end

  def test_create_pulp_repo
    assert @fedora_17_x86_64.create_pulp_repo
    @fedora_17_x86_64.destroy_repo
  end

  def test_destroy_repo
    @fedora_17_x86_64.create_pulp_repo
    assert @fedora_17_x86_64.destroy_repo
  end

end


class GluePulpRepoTest < GluePulpRepoTestBase

  @@fedora_17_x86_64 = nil

  def self.before_suite
    super
    @@fedora_17_x86_64 = Repository.find(@loaded_fixtures['repositories']['fedora_17_x86_64']['id'])
    @@fedora_17_x86_64.relative_path = '/test_path/'
    @@fedora_17_x86_64.feed = "file://#{File.expand_path(File.dirname(__FILE__))}".gsub("glue/pulp", "fixtures/zoo5")

    VCR.use_cassette('glue_pulp_repo_helper') do
      @@fedora_17_x86_64.create_pulp_repo
    end
  end

  def self.after_suite
    VCR.use_cassette('glue_pulp_repo_helper') do
      @@fedora_17_x86_64.destroy_repo
    end
  end

  def setup
    super
    User.current = @@admin
    @fedora_17_x86_64 = @@fedora_17_x86_64
    @fedora_17_x86_64.relative_path = '/test_path/'
  end

  def test_sync
    task_list = @fedora_17_x86_64.sync
    assert task_list.length > 0
    assert task_list.first.is_a? PulpSyncStatus
    @task = task_list.first
    self.class.wait_on_task(@task)
  end

  def test_set_sync_schedule
    VCR.use_cassette('glue_pulp_repo_sync_schedule', :match_requests_on => [:path, :params, :method]) do
      assert @fedora_17_x86_64.set_sync_schedule(Time.now.advance(:years => 1).iso8601 << "/P1D")
    end
  end

  def test_cancel_sync
    #@@fedora_17_x86_64.sync
    #assert @@fedora_17_x86_64.cancel_sync
  end

  def test_relative_path
    assert @fedora_17_x86_64.relative_path == '/test_path/'
  end

  def test_relative_path=
    @fedora_17_x86_64.relative_path = '/new_path/'
    assert @fedora_17_x86_64.relative_path != '/test_path/'
  end

  def test_generate_distributor
    assert @fedora_17_x86_64.generate_distributor.is_a? Runcible::Extensions::YumDistributor
  end

  def test_repo_id
    @fedora             = Product.find(products(:fedora).id)
    @library            = KTEnvironment.find(environments(:library).id)
    @acme_corporation   = Organization.find(organizations(:acme_corporation).id)

    repo_id = Glue::Pulp::Repo.repo_id(@fedora.label, @fedora_17_x86_64.label, @library.label, @acme_corporation.label)
    assert repo_id == "acme_corporation_label-library_label-fedora_label-fedora_17_x86_64_label"
  end

  def test_populate_from
    assert @fedora_17_x86_64.populate_from({ @fedora_17_x86_64.pulp_id => {} })
  end

end


class GluePulpRepoRequiresSyncTest < GluePulpRepoTestBase

  @@fedora_17_x86_64 = nil
  @@fedora_17_x86_64_dev = nil

  def self.before_suite
    super
    User.current = @@admin
    @@fedora_17_x86_64 = Repository.find(@loaded_fixtures['repositories']['fedora_17_x86_64']['id'])
    @@fedora_17_x86_64_dev = Repository.find(@loaded_fixtures['repositories']['fedora_17_x86_64_dev']['id'])

    @@fedora_17_x86_64.relative_path = '/test_path/'
    @@fedora_17_x86_64.feed = "file://#{File.expand_path(File.dirname(__FILE__))}".gsub("glue/pulp", "fixtures/zoo5")

    VCR.use_cassette('glue_pulp_repo_helper') do
      @@fedora_17_x86_64.create_pulp_repo
      task = @@fedora_17_x86_64.sync.first
      wait_on_task(task)
    end
  rescue => e
    puts e
  end

  def self.after_suite
    VCR.use_cassette('glue_pulp_repo_helper') do
      @@fedora_17_x86_64.destroy_repo
    end
  rescue
  end

  def test_last_sync
    assert @@fedora_17_x86_64.last_sync
  end

  def test_generate_metadata
    assert @@fedora_17_x86_64.generate_metadata
  end

  def test_sync_status
    assert @@fedora_17_x86_64.sync_status.is_a? PulpSyncStatus
  end

  def test_sync_state
    assert @@fedora_17_x86_64.sync_state == ::PulpSyncStatus::SUCCESS
  end

  def test_successful_sync?
    assert @@fedora_17_x86_64.successful_sync?(@@fedora_17_x86_64.sync_status)
  end

  def test_synced?
    assert @@fedora_17_x86_64.synced?
  end

  def test_sync_finish
    assert !@@fedora_17_x86_64.sync_finish.nil?
  end

  def test_sync_start
    assert !@@fedora_17_x86_64.sync_start.nil?
  end

  def test_packages
    assert @@fedora_17_x86_64.packages.select { |package| package.name == 'elephant' }.length > 0
  end

  def test_has_package?
    pkg_id = @@fedora_17_x86_64.packages.first.id
    assert @@fedora_17_x86_64.has_package?(pkg_id)
  end

  def test_errata
    assert @@fedora_17_x86_64.errata.select { |errata| errata.id == "RHEA-2010:0002" }.length > 0
  end

  def test_has_erratum?
    assert @@fedora_17_x86_64.has_erratum?("RHEA-2010:0002")
  end

  def test_distributions
    VCR.use_cassette('glue_pulp_repo_distributions', :match_requests_on => [:body_json, :uri, :method]) do
      distributions = @@fedora_17_x86_64.distributions
      assert distributions.select { |distribution| distribution.id == "ks-Test Family-TestVariant-16-x86_64" }.length > 0
    end
  end

  def test_has_distribution?
    VCR.use_cassette('glue_pulp_repo_distributions', :match_requests_on => [:body_json, :uri, :method]) do
      assert @@fedora_17_x86_64.has_distribution?("ks-Test Family-TestVariant-16-x86_64")
    end
  end

  def test_find_packages_by_name
    assert @@fedora_17_x86_64.find_packages_by_name('elephant').length > 0
  end

  def test_find_packages_by_nvre
    assert @@fedora_17_x86_64.find_packages_by_nvre('elephant', '0.3', '0.8', '0').length > 0
  end

  def test_find_latest_packages_by_name
    assert @@fedora_17_x86_64.find_latest_packages_by_name('elephant').length > 0
  end

  def test_package_groups
    package_groups = @@fedora_17_x86_64.package_groups
    assert package_groups.select { |group| group['name'] == 'mammal' }.length > 0
  end

  def test_package_group_categories
    categories = @@fedora_17_x86_64.package_group_categories
    assert categories.select { |category| category['name'] == 'all' }.length > 0
  end

  def test_create_clone
    staging = KTEnvironment.find(environments(:staging).id)

    clone = @@fedora_17_x86_64.create_clone(staging)
    assert clone.is_a? Repository

    clone.destroy
  end

  def test_clone_contents
    dev = KTEnvironment.find(environments(:dev).id)
    @@fedora_17_x86_64_dev.relative_path = Glue::Pulp::Repos.clone_repo_path(@@fedora_17_x86_64, dev)
    @@fedora_17_x86_64_dev.create_pulp_repo

    task_list = @@fedora_17_x86_64.clone_contents(@@fedora_17_x86_64_dev)
    assert task_list.length == 3

    self.class.wait_on_tasks(task_list)
    @@fedora_17_x86_64_dev.destroy_repo
  end

  def test_promote
    library = KTEnvironment.find(environments(:library).id)
    staging = KTEnvironment.find(environments(:staging).id)

    task_list = @@fedora_17_x86_64.promote(library, staging)
    assert task_list.length == 3

    self.class.wait_on_tasks(task_list)
    clone_id = @@fedora_17_x86_64.clone_id(staging)
    cloned_repo = Repository.where(:pulp_id => clone_id).first
    cloned_repo.destroy
  end

end


class GluePulpRepoRequiresEmptyPromoteTest < GluePulpRepoTestBase

  @@fedora_17_x86_64  = nil
  @@cloned_repo       = nil
  @@staging           = nil
  @@library           = nil

  def self.before_suite
    super
    User.current = @@admin

    @@fedora_17_x86_64 = Repository.find(@loaded_fixtures['repositories']['fedora_17_x86_64']['id'])
    @@fedora_17_x86_64.relative_path = '/test_path/'
    @@fedora_17_x86_64.feed = "file://#{File.expand_path(File.dirname(__FILE__))}".gsub("glue/pulp", "fixtures/zoo5")

    @@library = KTEnvironment.find(@loaded_fixtures['environments']['library']['id'])
    @@staging = KTEnvironment.find(@loaded_fixtures['environments']['staging']['id'])

    VCR.use_cassette('glue_pulp_repo_helper') do
      @@fedora_17_x86_64.create_pulp_repo

      task_list = @@fedora_17_x86_64.promote(@@library, @@staging)
      wait_on_tasks(task_list)

      task = @@fedora_17_x86_64.sync.first
      wait_on_task(task)

      clone_id = @@fedora_17_x86_64.clone_id(@@staging)
      @@cloned_repo = Repository.where(:pulp_id => clone_id).first
    end
  rescue => e
    puts "ERROR: " + e.to_s
  end

  def self.after_suite
    VCR.use_cassette('glue_pulp_repo_helper') do
      @@cloned_repo.destroy
      @@fedora_17_x86_64.destroy_repo
    end
  rescue => e
    puts "ERROR: " + e.to_s
  end

  def test_add_packages
    package = @@fedora_17_x86_64.find_packages_by_name('elephant').first
    assert @@cloned_repo.add_packages([package['id']])
  end

  def test_add_errata
    assert @@cloned_repo.add_errata(["RHEA-2010:0002"])
  end

  def test_add_distribution
    assert @@cloned_repo.add_distribution("ks-Test Family-TestVariant-16-x86_64")
  end

end


class GluePulpRepoRequiresSyncAndPromoteTest < GluePulpRepoTestBase

  @@fedora_17_x86_64  = nil
  @@cloned_repo       = nil
  @@staging           = nil
  @@library           = nil

  def self.before_suite
    super
    User.current = @@admin

    @@fedora_17_x86_64 = Repository.find(@loaded_fixtures['repositories']['fedora_17_x86_64']['id'])
    @@fedora_17_x86_64.relative_path = '/test_path/'
    @@fedora_17_x86_64.feed = "file://#{File.expand_path(File.dirname(__FILE__))}".gsub("glue/pulp", "fixtures/zoo5")

    @@library = KTEnvironment.find(@loaded_fixtures['environments']['library']['id'])
    @@staging = KTEnvironment.find(@loaded_fixtures['environments']['staging']['id'])

    VCR.use_cassette('glue_pulp_repo_helper') do
      @@fedora_17_x86_64.create_pulp_repo
      task = @@fedora_17_x86_64.sync.first
      wait_on_task(task)

      clone_id = @@fedora_17_x86_64.clone_id(@@staging)

      task_list = @@fedora_17_x86_64.promote(@@library, @@staging)
      wait_on_tasks(task_list)

      @@cloned_repo = Repository.where(:pulp_id => clone_id).first
    end
  rescue => e
    puts "ERROR: " + e.to_s
  end

  def self.after_suite
    VCR.use_cassette('glue_pulp_repo_helper') do
      @@fedora_17_x86_64.destroy_repo
      @@cloned_repo.destroy
    end
  rescue => e
    puts "ERROR: " + e.to_s
  end
    
  def test_delete_packages
    package = @@fedora_17_x86_64.find_packages_by_name('elephant').first
    assert @@cloned_repo.delete_packages([package['id']])
  end

  def test_delete_errata
    assert @@cloned_repo.delete_errata(["RHEA-2010:0002"])
  end

  def test_delete_distribution
    assert @@cloned_repo.delete_distribution("ks-Test Family-TestVariant-16-x86_64")
  end

end