require 'katello_test_helper'

module Katello
  describe CustomInfo do
    include OrchestrationHelper
    include SystemHelperMethods

    let(:uuid) { '1234' }

    before(:each) do
      disable_org_orchestration

      @organization = get_organization
      @environment = katello_environments(:dev)

      Resources::Candlepin::Consumer.stubs(:create).returns(:uuid => uuid, :owner => {:key => uuid})
      Resources::Candlepin::Consumer.stubs(:update).returns(true)

      Katello.pulp_server.extensions.consumer.stubs(:create).returns(:id => uuid) if defined?(Runcible)

      @system = System.create!(:name => "test_system", :environment => @environment, :cp_type => 'system', :facts => {"distribution.name" => "Fedora"})

      CustomInfo.skip_callback(:save, :after, :reindex_informable)
      CustomInfo.skip_callback(:destroy, :after, :reindex_informable)
    end

    describe "CustomInfo in invalid state should not be valid" do
      specify { CustomInfo.new.wont_be :valid? }
      specify { CustomInfo.new(:keyname => "test").wont_be :valid? }
      specify { CustomInfo.new(:value => "1234").wont_be :valid? }
      specify { CustomInfo.new(:keyname => "test", :value => "1234").wont_be :valid? }
      specify { @system.custom_info.new(:keyname => ("key" * 256), :value => "normal length value").wont_be :valid? }
      specify { @system.custom_info.new(:keyname => "normal length key", :value => ("value" * 256)).wont_be :valid? }
    end

    describe "CustomInfo in valid state should be valid" do
      specify { @system.custom_info.new(:keyname => "test", :value => "1234").must_be :valid? }
      specify { @system.custom_info.new(:keyname => "test", :value => "abcd").must_be :valid? }
      specify { @system.custom_info.new(:keyname => "test").must_be :valid? }
    end

    it "should not allow duplicate keynames" do
      @system.custom_info.create!(:keyname => "test", :value => "1234")
      @system.custom_info.new(:keyname => "test", :value => "asdf").wont_be :valid?
    end
  end
end
