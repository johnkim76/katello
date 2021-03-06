# rubocop:disable AccessModifierIndentation

require 'util/password'

module Katello
  module Concerns
    module UserExtensions
      extend ActiveSupport::Concern

      included do
        include Glue::Pulp::User if Katello.config.use_pulp
        include Glue if Katello.config.use_cp || Katello.config.use_pulp
        include ForemanTasks::Concerns::ActionSubject
        include ForemanTasks::Concerns::ActionTriggering

        def create_action
          sync_action!
          ::Actions::Katello::User::Create
        end

        def destroy_action
          sync_action!
          ::Actions::Katello::User::Destroy
        end

        include Util::ThreadSession::UserModel

        has_many :user_notices, :dependent => :destroy, :class_name => "Katello::UserNotice"
        has_many :notices, :through => :user_notices, :class_name => "Katello::Notice"
        has_many :task_statuses, :dependent => :destroy, :class_name => "Katello::TaskStatus"
        has_many :activation_keys, :dependent => :destroy, :class_name => "Katello::ActivationKey"
        serialize :preferences, Hash

        after_validation :setup_remote_id
        before_save :setup_preferences

        def setup_preferences
          self.preferences = Hash.new unless self.preferences
        end

        def preferences_hash
          self.preferences.is_a?(Hash) ? self.preferences : self.preferences.unserialized_value
        end

        def self.cp_oauth_header
          fail Errors::UserNotSet, "unauthenticated to call a backend engine" if Thread.current[:cp_oauth_header].nil?
          Thread.current[:cp_oauth_header]
        end

        def cp_oauth_header
          { 'cp-user' => self.username }
        end

        # is the current user consumer? (rhsm)
        def self.consumer?
          User.current.is_a? CpConsumerUser
        end

        #Remove up to 5 un-viewed notices
        def pop_notices(organization = nil, count = 5)
          notices = Notice.for_user(self).for_org(organization).unread.limit(count == :all ? nil : count)
          notices.each { |notice| notice.user_notices.each(&:read!) }

          notices = notices.map do |notice|
            {:text => notice.text, :level => notice.level, :request_type => notice.request_type}
          end
          return notices
        end

        def cp_oauth_header
          { 'cp-user' => self.login }
        end

        def default_locale
          self.preferences_hash[:user][:locale] rescue nil
        end

        def default_locale=(locale)
          self.preferences_hash[:user] = { } unless self.preferences_hash.key? :user
          self.preferences_hash[:user][:locale] = locale
        end

        def legacy_mode
          self.preferences_hash[:user][:legacy_mode] rescue nil
        end

        def legacy_mode=(use_legacy_mode)
          self.preferences_hash[:user] = { } unless self.preferences_hash.key? :user
          self.preferences_hash[:user][:legacy_mode] = ::Foreman::Cast.to_bool(use_legacy_mode)
        end

        def default_org
          org_id = self.preferences_hash[:user][:default_org] rescue nil
          if org_id && !org_id.nil? && org_id != "nil"
            org = Organization.find_by_id(org_id)
            return org if self.organizations.include?(org)
          else
            return nil
          end
        end

        #set the default org if it's an actual org_id
        def default_org=(org_id)
          self.preferences_hash[:user] = { } unless self.preferences_hash.key? :user
          if !org_id.nil? && org_id != "nil"
            organization = Organization.find_by_id(org_id)
            self.preferences_hash[:user][:default_org] = organization.id
          else
            self.preferences_hash[:user][:default_org] = nil
          end
        end

        def subscriptions_match_system_preference
          self.preferences_hash[:user][:subscriptions_match_system] rescue false
        end

        def subscriptions_match_system_preference=(flag)
          self.preferences_hash[:user] = { } unless self.preferences_hash.key? :user
          self.preferences_hash[:user][:subscriptions_match_system] = flag
        end

        def subscriptions_match_installed_preference
          self.preferences_hash[:user][:subscriptions_match_installed] rescue false
        end

        def subscriptions_match_installed_preference=(flag)
          self.preferences_hash[:user] = { } unless self.preferences_hash.key? :user
          self.preferences_hash[:user][:subscriptions_match_installed] = flag
        end

        def subscriptions_no_overlap_preference
          self.preferences_hash[:user][:subscriptions_no_overlap] rescue false
        end

        def subscriptions_no_overlap_preference=(flag)
          self.preferences_hash[:user] = { } unless self.preferences_hash.key? :user
          self.preferences_hash[:user][:subscriptions_no_overlap] = flag
        end

        def empty_display_attributes?(a_search_string)
          tokens = a_search_string.strip.split(/\s/)
          return false if tokens.size > 1

          return false unless tokens.first.end_with?(':')
          true
        end

        def allowed_organizations
          admin? ? Organization.all : self.organizations
        end

        private

        # generate a random token, that is unique within the User table for the column provided
        def generate_token(column)
          loop do
            self[column] = SecureRandom.hex(32)
            break unless User.exists?(column => self[column])
          end
        end

        def setup_remote_id
          #if validation failed, don't setup
          return false unless self.errors.empty?
          if  self.remote_id.nil?
            self.remote_id = generate_remote_id
          end
          return true
        end

        def generate_remote_id
          if User.current.object_id == self.object_id
            # The case when the first user is being created.
            Katello.config.pulp.default_login
          elsif self.login.ascii_only?
            "#{Util::Model.labelize(self.login)}-#{SecureRandom.hex(4)}"
          else
            Util::Model.uuid
          end
        end
      end
    end
  end
end
