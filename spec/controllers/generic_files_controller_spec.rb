# Copyright © 2012 The Pennsylvania State University
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'spec_helper'

describe GenericFilesController do
  before do
    controller.stub(:has_access?).and_return(true)

    GenericFile.any_instance.stub(:terms_of_service).and_return('1')
    @user = FactoryGirl.find_or_create(:user)
    sign_in @user
    User.any_instance.stub(:groups).and_return([])
    controller.stub(:clear_session_user) ## Don't clear out the authenticated session
  end
  describe "#create" do
    before do
      GenericFile.any_instance.stub(:terms_of_service).and_return('1')
      @file_count = GenericFile.count
      @mock = GenericFile.new({:pid => 'test:123'})
      GenericFile.stub(:new).and_return(@mock)
    end
    after do
      begin
        Batch.find("sample:batch_id").delete
      rescue
      end                                         
      @mock.delete unless @mock.inner_object.class == ActiveFedora::UnsavedDigitalObject 
    end

    it "should spawn a content deposit event job" do
      #GenericFile.any_instance.stub(:to_solr).and_return({})
      file = fixture_file_upload('/world.png','image/png')
      Resque.should_receive(:enqueue).with(ContentDepositEventJob, 'test:123', 'jilluser@example.com')
      Resque.should_receive(:enqueue).with(CharacterizeJob, 'test:123')
      xhr :post, :create, :files=>[file], :Filename=>"The world", :batch_id => "sample:batch_id", :permission=>{"group"=>{"public"=>"read"} }, :terms_of_service=>"1"
    end

    it "should expand zip files" do
      #GenericFile.any_instance.stub(:to_solr).and_return({})
      file = fixture_file_upload('/world.png','application/zip')
      Resque.should_receive(:enqueue).with(CharacterizeJob, 'test:123')
      Resque.should_receive(:enqueue).with(UnzipJob, 'test:123')
      Resque.should_receive(:enqueue).with(ContentDepositEventJob, 'test:123', 'jilluser@example.com')
      xhr :post, :create, :files=>[file], :Filename=>"The world", :batch_id => "sample:batch_id", :permission=>{"group"=>{"public"=>"read"} }, :terms_of_service=>"1"
    end

    it "should create and save a file asset from the given params" do
      file = fixture_file_upload('/world.png','image/png')
      xhr :post, :create, :files=>[file], :Filename=>"The world", :batch_id => "sample:batch_id", :permission=>{"group"=>{"public"=>"read"} }, :terms_of_service=>"1"
      response.should be_success
      GenericFile.count.should == @file_count + 1

      saved_file = GenericFile.find('test:123')

      # This is confirming that the correct file was attached
      saved_file.label.should == 'world.png'
      saved_file.content.checksum.should == 'f794b23c0c6fe1083d0ca8b58261a078cd968967'
      saved_file.content.dsChecksumValid.should be_true

      # Confirming that date_uploaded and date_modified were set
      saved_file.date_uploaded.should have_at_least(1).items
      saved_file.date_modified.should have_at_least(1).items
    end

    it "should record what user created the first version of content" do
      #GenericFile.any_instance.stub(:to_solr).and_return({})
      file = fixture_file_upload('/world.png','image/png')
      xhr :post, :create, :files=>[file], :Filename=>"The world", :terms_of_service=>"1"

      saved_file = GenericFile.find('test:123')
      version = saved_file.content.latest_version
      version.versionID.should == "content.0"
      saved_file.content.version_committer(version).should == @user.user_key
    end

    it "should create batch associations from batch_id" do
      Sufia::Engine.config.stub(:id_namespace).and_return('sample')
      file = fixture_file_upload('/world.png','image/png')
      controller.stub(:add_posted_blob_to_asset)
      xhr :post, :create, :files=>[file], :Filename=>"The world", :batch_id => "sample:batch_id", :permission=>{"group"=>{"public"=>"read"} }, :terms_of_service=>"1"
      lambda {Batch.find("sample:batch_id")}.should raise_error(ActiveFedora::ObjectNotFoundError) # The controller shouldn't actually save the Batch, but it should write the batch id to the files.
      b = Batch.create(pid: "sample:batch_id")
      b.generic_files.first.pid.should == "test:123"
    end
    it "should set the depositor id" do
      file = fixture_file_upload('/world.png','image/png')
      xhr :post, :create, :files => [file], :Filename => "The world", :batch_id => "sample:batch_id", :permission => {"group"=>{"public"=>"read"} }, :terms_of_service => "1"
      response.should be_success

      saved_file = GenericFile.find('test:123')
      # This is confirming that apply_depositor_metadata recorded the depositor
      #TODO make sure this is moved to scholarsphere:
      #saved_file.properties.depositor.should == ['jilluser']
      saved_file.properties.depositor.should == ['jilluser@example.com']
      #TODO make sure this is moved to scholarsphere:
      #saved_file.depositor.should == 'jilluser'
      saved_file.depositor.should == 'jilluser@example.com'
      saved_file.properties.to_solr.keys.should include('depositor_t')
      #TODO make sure this is moved to scholarsphere:
      #saved_file.properties.to_solr['depositor_t'].should == ['jilluser']
      saved_file.properties.to_solr['depositor_t'].should == ['jilluser@example.com']
      saved_file.to_solr.keys.should include('depositor_t')
      saved_file.to_solr['depositor_t'].should == ['jilluser@example.com']
    end
    it "Should call virus check" do
      controller.should_receive(:virus_check).and_return(0)      
      file = fixture_file_upload('/world.png','image/png')
      Resque.should_receive(:enqueue).with(ContentDepositEventJob, 'test:123', 'jilluser@example.com')
      Resque.should_receive(:enqueue).with(CharacterizeJob, 'test:123')
      xhr :post, :create, :files=>[file], :Filename=>"The world", :batch_id => "sample:batch_id", :permission=>{"group"=>{"public"=>"read"} }, :terms_of_service=>"1"
    end

    describe "#virus_check" do
      before do
        unless defined? ClamAV
          class ClamAV
            def self.instance
              new
            end
          end
          @stubbed_clamav = true
        end
      end
      after do
        Object.send(:remove_const, :ClamAV) if @stubbed_clamav
      end
      it "failing virus check should create flash" do
        GenericFile.any_instance.stub(:to_solr).and_return({})
        ClamAV.any_instance.should_receive(:scanfile).and_return(1)      
        file = fixture_file_upload('/world.png','image/png')
        controller.send :virus_check, file
        flash[:error].should_not be_empty
      end
    end


  end

  describe "audit" do
    before do
      #GenericFile.any_instance.stub(:to_solr).and_return({})
      @generic_file = GenericFile.new
      @generic_file.add_file_datastream(File.new(fixture_path + '/world.png'), :dsid=>'content')
      @generic_file.apply_depositor_metadata('mjg36')
      @generic_file.save
    end
    after do
      @generic_file.delete
    end
    it "should return json with the result" do
      xhr :post, :audit, :id=>@generic_file.pid
      response.should be_success
      lambda { JSON.parse(response.body) }.should_not raise_error
      audit_results = JSON.parse(response.body).collect { |result| result["pass"] }
      audit_results.reduce(true) { |sum, value| sum && value }.should be_true
    end
  end

  describe "destroy" do
    before(:each) do
      GenericFile.any_instance.stub(:terms_of_service).and_return('1')
      @generic_file = GenericFile.new
      @generic_file.apply_depositor_metadata(@user.user_key)
      @generic_file.save
      @user = FactoryGirl.find_or_create(:user)
      sign_in @user
    end
    after do
      @user.delete
    end    
    it "should delete the file" do
      GenericFile.find(@generic_file.pid).should_not be_nil
      delete :destroy, :id=>@generic_file.pid
      lambda { GenericFile.find(@generic_file.pid) }.should raise_error(ActiveFedora::ObjectNotFoundError)
    end
    it "should spawn a content delete event job" do
      Resque.should_receive(:enqueue).with(ContentDeleteEventJob, @generic_file.noid, @user.user_key)
      delete :destroy, :id=>@generic_file.pid
    end
  end

  describe "update" do
    before do
      GenericFile.any_instance.stub(:terms_of_service).and_return('1')
      #controller.should_receive(:virus_check).and_return(0)      
      @generic_file = GenericFile.new
      @generic_file.apply_depositor_metadata(@user.user_key)
      @generic_file.save
    end
    after do
      @generic_file.delete
    end

    it "should spawn a content update event job" do
      Resque.should_receive(:enqueue).with(ContentUpdateEventJob, @generic_file.pid, 'jilluser@example.com')
      @user = FactoryGirl.find_or_create(:user)
      sign_in @user
      post :update, :id=>@generic_file.pid, :generic_file=>{:terms_of_service=>"1", :title=>'new_title', :tag=>[''], :permissions=>{:new_user_name=>{'archivist1'=>'edit'}}}
      @user.delete      
    end

    it "should spawn a content new version event job" do
      Resque.should_receive(:enqueue).with(ContentNewVersionEventJob, @generic_file.pid, 'jilluser@example.com')
      Resque.should_receive(:enqueue).with(CharacterizeJob, @generic_file.pid)      
      @user = FactoryGirl.find_or_create(:user)
      sign_in @user

      file = fixture_file_upload('/world.png','image/png')
      post :update, :id=>@generic_file.pid, :filedata=>file, :Filename=>"The world", :generic_file=>{:terms_of_service=>"1", :tag=>[''],  :permissions=>{:new_user_name=>{'archivist1'=>'edit'}}}
      @user.delete
    end

    it "should record what user added a new version" do
      @user = FactoryGirl.find_or_create(:user)
      sign_in @user

      file = fixture_file_upload('/world.png','image/png')
      post :update, :id=>@generic_file.pid, :filedata=>file, :Filename=>"The world", :generic_file=>{:terms_of_service=>"1", :tag=>[''],  :permissions=>{:new_user_name=>{'archivist1@example.com'=>'edit'}}}

      posted_file = GenericFile.find(@generic_file.pid)
      version1 = posted_file.content.latest_version
      posted_file.content.version_committer(version1).should == @user.user_key

      # other user uploads new version 
      # TODO this should be a separate test
      archivist = FactoryGirl.find_or_create(:archivist)
      controller.stub(:current_user).and_return(archivist)

      Resque.should_receive(:enqueue).with(ContentUpdateEventJob, @generic_file.pid, 'jilluser@example.com').never
      Resque.should_receive(:enqueue).with(ContentNewVersionEventJob, @generic_file.pid, archivist.user_key).once
      Resque.should_receive(:enqueue).with(CharacterizeJob, @generic_file.pid).once
      file = fixture_file_upload('/image.jp2','image/jp2')
      post :update, :id=>@generic_file.pid, :filedata=>file, :Filename=>"The world", :generic_file=>{:terms_of_service=>"1", :tag=>[''] }

      edited_file = GenericFile.find(@generic_file.pid)
      version2 = edited_file.content.latest_version
      version2.versionID.should_not == version1.versionID
      edited_file.content.version_committer(version2).should == archivist.user_key

      # original user restores his or her version
      controller.stub(:current_user).and_return(@user)
      sign_in @user
      Resque.should_receive(:enqueue).with(ContentUpdateEventJob, @generic_file.pid, 'jilluser@example.com').never
      Resque.should_receive(:enqueue).with(ContentRestoredVersionEventJob, @generic_file.pid, @user.user_key, 'content.0').once
      Resque.should_receive(:enqueue).with(CharacterizeJob, @generic_file.pid).once
      post :update, :id=>@generic_file.pid, :revision=>'content.0', :generic_file=>{:terms_of_service=>"1", :tag=>['']}

      restored_file = GenericFile.find(@generic_file.pid)
      version3 = restored_file.content.latest_version
      version3.versionID.should_not == version2.versionID
      version3.versionID.should_not == version1.versionID
      restored_file.content.version_committer(version3).should == @user.user_key
      @user.delete
    end

    it "should add a new groups and users" do
      post :update, :id=>@generic_file.pid, :generic_file=>{:terms_of_service=>"1", :tag=>[''], :permissions=>{:new_group_name=>{'group1'=>'read'}, :new_user_name=>{'user1'=>'edit'}}}

      assigns[:generic_file].read_groups.should == ["group1"]
      assigns[:generic_file].edit_users.should include("user1", @user.user_key)
    end
    it "should update existing groups and users" do
      @generic_file.read_groups = ['group3']
      @generic_file.save
      post :update, :id=>@generic_file.pid, :generic_file=>{:terms_of_service=>"1", :tag=>[''], :permissions=>{:new_group_name=>'', :new_group_permission=>'', :new_user_name=>'', :new_user_permission=>'', :group=>{'group3' =>'read'}}}

      assigns[:generic_file].read_groups.should == ["group3"]
    end
    it "should spawn a virus check" do
      # The expectation is in the begin block
      controller.should_receive(:virus_check).and_return(0)      
      Resque.stub(:enqueue).with(ContentNewVersionEventJob, @generic_file.pid, 'jilluser@example.com')
      Resque.stub(:enqueue).with(CharacterizeJob, @generic_file.pid)
      GenericFile.stub(:save).and_return({})
      @user = FactoryGirl.find_or_create(:user)
      sign_in @user
      file = fixture_file_upload('/world.png','image/png')
      post :update, :id=>@generic_file.pid, :filedata=>file, :Filename=>"The world", :generic_file=>{:terms_of_service=>"1", :tag=>[''],  :permissions=>{:new_user_name=>{'archivist1'=>'edit'}}}
    end

  end

  describe "someone elses files" do
    before(:all) do
      GenericFile.any_instance.stub(:terms_of_service).and_return('1')
      f = GenericFile.new(:pid => 'sufia:test5')
      f.apply_depositor_metadata('archivist1@example.com')
      f.set_title_and_label('world.png')
      f.add_file_datastream(File.new(fixture_path +  '/world.png'))
      # grant public read access explicitly
      f.read_groups = ['public']
      f.should_receive(:characterize_if_changed).and_yield
      f.save
      @file = f
    end
    after(:all) do
      GenericFile.find('sufia:test5').delete
    end
    describe "edit" do
      it "should give me a flash error" do
        get :edit, id:"test5"
        response.should redirect_to @routes.url_helpers.generic_file_path('test5')
        flash[:alert].should_not be_nil
        flash[:alert].should_not be_empty
        flash[:alert].should include("You do not have sufficient privileges to edit this document")
      end
    end
    describe "view" do
      it "should show me the file" do
        get :show, id:"test5"
        response.should_not redirect_to(:action => 'show')
        flash[:alert].should be_nil
      end
    end
    describe "flash" do
      render_views
      it "should not let the user submit if they logout" do
        sign_out @user
        get :new
        response.should_not be_success
        flash[:alert].should_not be_nil
        flash[:alert].should include("You need to sign in or sign up before continuing")
      end
      it "should filter flash if they signin" do
        request.env['warden'].stub(:user).and_return(@user)
        sign_out @user
        get :new
        sign_in @user
        get :show, id:"test5"
        response.body.should_not include("You need to sign in or sign up before continuing")
      end
      describe "failing audit" do
        before(:all) do
          ActiveFedora::RelsExtDatastream.any_instance.stub(:dsChecksumValid).and_return(false)
          @archivist = FactoryGirl.find_or_create(:archivist)
        end
        after(:all) do
          @archivist.delete
        end
        it "should display failing audits" do
          sign_out @user
          sign_in @archivist
          @ds = @file.datastreams.first
          AuditJob.perform(@file.pid, @ds[0], @ds[1].versionID)
          get :show, id:"test5"
          assigns[:notify_number].should == 1
          response.body.should include('<span id="notify_number" class="overlay"> 1</span>') # notify should be 1 for failing job
          @archivist.mailbox.inbox[0].messages[0].subject.should == "Failing Audit Run"
        end
      end
    end
  end
end
