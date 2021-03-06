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

describe UsersController do
  before(:each) do
    @user = FactoryGirl.find_or_create(:user)
    @another_user = FactoryGirl.find_or_create(:archivist)
    sign_in @user
    User.any_instance.stub(:groups).and_return([])
    controller.stub(:clear_session_user) ## Don't clear out the authenticated session
  end
  after(:all) do
    @user = FactoryGirl.find(:user) rescue
    @user.delete if @user
    @another_user = FactoryGirl.find(:archivist) rescue
    @another_user.delete if @user
  end
  describe "#show" do
    it "show the user profile if user exists" do
      get :show, uid: @user.user_key
      response.should be_success
      response.should_not redirect_to(root_path)
      flash[:alert].should be_nil
    end
    it "redirects to root if user does not exist" do
      get :show, uid: 'johndoe666'
      response.should redirect_to(root_path)
      flash[:alert].should include ("User 'johndoe666' does not exist")
    end
  end
  describe "#edit" do
    it "show edit form when user edits own profile" do
      get :edit, uid: @user.user_key
      response.should be_success
      response.should render_template('users/edit')
      flash[:alert].should be_nil
    end
    it "redirects to show profile when user attempts to edit another profile" do
      get :edit, uid: @another_user.user_key
      response.should redirect_to(@routes.url_helpers.profile_path(URI.escape(@another_user.user_key,'@.')))
      flash[:alert].should include("You cannot edit archivist1@example.com's profile")
    end
  end
  describe "#update" do
    it "should not allow other users to update" do
      post :update, uid: @another_user.user_key, user: { avatar: nil }
      response.should redirect_to(@routes.url_helpers.profile_path(URI.escape(@another_user.user_key,'@.')))
      flash[:alert].should include("You cannot edit archivist1@example.com's profile")
    end
    it "should set an avatar and redirect to profile" do
      @user.avatar.file?.should be_false
      Resque.should_receive(:enqueue).with(UserEditProfileEventJob, @user.user_key).once
      f = fixture_file_upload('/world.png', 'image/png')
      post :update, uid: @user.user_key, user: { avatar: f }
      response.should redirect_to(@routes.url_helpers.profile_path(URI.escape(@user.user_key,'@.')))
      flash[:notice].should include("Your profile has been updated")
      User.find_by_user_key(@user.user_key).avatar.file?.should be_true
    end
    it "should validate the content type of an avatar" do
      Resque.should_receive(:enqueue).with(UserEditProfileEventJob, @user.user_key).never
      f = fixture_file_upload('/image.jp2', 'image/jp2')
      post :update, uid: @user.user_key, user: { avatar: f }
      response.should redirect_to(@routes.url_helpers.edit_profile_path(URI.escape(@user.user_key,'@.')))
      flash[:alert].should include("Avatar content type is invalid")
    end
    it "should validate the size of an avatar" do
      f = fixture_file_upload('/4-20.png', 'image/png')
      Resque.should_receive(:enqueue).with(UserEditProfileEventJob, @user.user_key).never
      post :update, uid: @user.user_key, user: { avatar: f }
      response.should redirect_to(@routes.url_helpers.edit_profile_path(URI.escape(@user.user_key,'@.')))
      flash[:alert].should include("Avatar file size must be less than 2097152 Bytes")
    end
    it "should delete an avatar" do
      Resque.should_receive(:enqueue).with(UserEditProfileEventJob, @user.user_key).once
      post :update, uid: @user.user_key, delete_avatar: true
      response.should redirect_to(@routes.url_helpers.profile_path(URI.escape(@user.user_key,'@.')))
      flash[:notice].should include("Your profile has been updated")
      @user.avatar.file?.should be_false
    end
    it "should refresh directory attributes" do
      Resque.should_receive(:enqueue).with(UserEditProfileEventJob, @user.user_key).once
      User.any_instance.should_receive(:populate_attributes).once
      post :update, uid: @user.user_key, update_directory: true
      response.should redirect_to(@routes.url_helpers.profile_path(URI.escape(@user.user_key,'@.')))
      flash[:notice].should include("Your profile has been updated")
    end
    it "should set an social handles" do
      @user.twitter_handle.blank?.should be_true
      @user.facebook_handle.blank?.should be_true
      @user.googleplus_handle.blank?.should be_true
      post :update, uid: @user.user_key, user: { twitter_handle: 'twit', facebook_handle: 'face', googleplus_handle: 'goo' }
      response.should redirect_to(@routes.url_helpers.profile_path(URI.escape(@user.user_key,'@.')))
      flash[:notice].should include("Your profile has been updated")
      u = User.find_by_user_key(@user.user_key)
      u.twitter_handle.should == 'twit'
      u.facebook_handle.should == 'face'
      u.googleplus_handle.should == 'goo'
    end
  end
  describe "#follow" do
    after(:all) do
      @user.unfollow(@another_user) rescue nil
    end
    it "should follow another user if not already following, and log an event" do
      @user.following?(@another_user).should be_false
      Resque.should_receive(:enqueue).with(UserFollowEventJob, @user.user_key, @another_user.user_key).once
      post :follow, uid: @another_user.user_key
      response.should redirect_to(@routes.url_helpers.profile_path(URI.escape(@another_user.user_key,'@.')))
      flash[:notice].should include("You are following #{@another_user.user_key}")
    end
    it "should redirect to profile if already following and not log an event" do
      User.any_instance.stub(:following?).with(@another_user).and_return(true)
      Resque.should_receive(:enqueue).with(UserFollowEventJob, @user.user_key, @another_user.user_key).never
      post :follow, uid: @another_user.user_key
      response.should redirect_to(@routes.url_helpers.profile_path(URI.escape(@another_user.user_key,'@.')))
      flash[:notice].should include("You are following #{@another_user.user_key}")
    end
    it "should redirect to profile if user attempts to self-follow and not log an event" do
      Resque.should_receive(:enqueue).with(UserFollowEventJob, @user.user_key, @user.user_key).never
      post :follow, uid: @user.user_key
      response.should redirect_to(@routes.url_helpers.profile_path(URI.escape(@user.user_key,'@.')))
      flash[:alert].should include("You cannot follow or unfollow yourself")
    end
  end
  describe "#unfollow" do
    it "should unfollow another user if already following, and log an event" do
      User.any_instance.stub(:following?).with(@another_user).and_return(true)
      Resque.should_receive(:enqueue).with(UserUnfollowEventJob, @user.user_key, @another_user.user_key).once
      post :unfollow, uid: @another_user.user_key
      response.should redirect_to(@routes.url_helpers.profile_path(URI.escape(@another_user.user_key,'@.')))
      flash[:notice].should include("You are no longer following #{@another_user.user_key}")
    end
    it "should redirect to profile if not following and not log an event" do
      @user.stub(:following?).with(@another_user).and_return(false)
      Resque.should_receive(:enqueue).with(UserUnfollowEventJob, @user.user_key, @another_user.user_key).never
      post :unfollow, uid: @another_user.user_key
      response.should redirect_to(@routes.url_helpers.profile_path(URI.escape(@another_user.user_key,'@.')))
      flash[:notice].should include("You are no longer following #{@another_user.user_key}")
    end
    it "should redirect to profile if user attempts to self-follow and not log an event" do
      Resque.should_receive(:enqueue).with(UserUnfollowEventJob, @user.user_key, @user.user_key).never
      post :unfollow, uid: @user.user_key
      response.should redirect_to(@routes.url_helpers.profile_path(URI.escape(@user.user_key,'@.')))
      flash[:alert].should include("You cannot follow or unfollow yourself")
    end
  end
end
