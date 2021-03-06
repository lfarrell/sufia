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

describe User do
  before(:all) do
    @user = FactoryGirl.find_or_create(:user)
    @another_user = FactoryGirl.find_or_create(:archivist)
  end
  after(:all) do
    @user.delete
    @another_user.delete
  end
  it "should have a login" do
    pending "Move to scholarsphere"
    @user.login.should == "jilluser"
  end
  it "should have an email" do
    @user.user_key.should == "jilluser@example.com"
  end
  it "should have activity stream-related methods defined" do
    @user.should respond_to(:stream)
    @user.should respond_to(:events)
    @user.should respond_to(:profile_events)
    @user.should respond_to(:create_event)
    @user.should respond_to(:log_event)
    @user.should respond_to(:log_profile_event)
  end
  it "should have social attributes" do
    @user.should respond_to(:twitter_handle)
    @user.should respond_to(:facebook_handle)
    @user.should respond_to(:googleplus_handle)
  end
  it "should redefine to_param to make redis keys more recognizable" do
    @user.to_param.should == @user.user_key
  end
  it "should have a cancan ability defined" do
    @user.should respond_to(:can?)
  end
  it "should not have any followers" do
    @user.followers_count.should == 0
    @another_user.follow_count.should == 0
  end
  describe "follow/unfollow" do
    before(:all) do
      @user = FactoryGirl.find_or_create(:user)
      @another_user = FactoryGirl.find_or_create(:archivist)
      @user.follow(@another_user)
    end
    after do
      @user.delete
      @another_user.delete
    end
    it "should be able to follow another user" do
      @user.following?(@another_user).should be_true
      @another_user.following?(@user).should be_false
      @another_user.followed_by?(@user).should be_true
      @user.followed_by?(@another_user).should be_false
    end
    it "should be able to unfollow another user" do
      @user.stop_following(@another_user)
      @user.following?(@another_user).should be_false
      @another_user.followed_by?(@user).should be_false
    end
  end
end
