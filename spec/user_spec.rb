require 'rails_helper'

describe User do
  let(:user) { Fabricate(:user) }
  let(:profile_page_url) { "#{Discourse.base_url}/users/#{user.username}" }

  describe 'when a user is created' do
    it 'should initiate the bot' do
      user

      expected_raw = I18n.t('discourse_narrative_bot.new_user_narrative.hello.message',
        username: user.username, title: SiteSetting.title
      )

      expect(Post.last.raw).to include(expected_raw.chomp)
    end

    describe 'welcome post' do
      context 'disabled' do
        before do
          SiteSetting.discourse_narrative_bot_start_new_user_track_on_signup = false
        end

        it 'should not initiate the bot' do
          expect { user }.to_not change { Post.count }
        end

        describe "when send welcome message is enabled" do
          before do
            SiteSetting.discourse_narrative_bot_send_welcome_message = true
          end

          it 'should send the right welcome message' do
            expect { user }.to change { Topic.count }.by(1)

            expect(Topic.last.title).to eq(I18n.t(
              "system_messages.welcome_user.subject_template",
              site_name: SiteSetting.title
            ))
          end
        end
      end

      describe 'enabled' do
        before do
          SiteSetting.discourse_narrative_bot_start_new_user_track_on_signup = true
        end

        it 'initiate the bot' do
          expect { user }.to change { Topic.count }.by(1)

          expect(Topic.last.title).to eq(I18n.t(
            'discourse_narrative_bot.new_user_narrative.hello.title'
          ))
        end
      end
    end

    context 'when user is staged' do
      let(:user) { Fabricate(:user, staged: true) }

      it 'should not initiate the bot' do
        expect { user }.to_not change { Post.count }
      end
    end

    context 'when user is anonymous?' do
      let(:anonymous_user) { Fabricate(:anonymous) }

      it 'should not initiate the bot' do
        SiteSetting.allow_anonymous_posting = true

        expect { anonymous_user }.to_not change { Post.count }
      end
    end

    context "when user's username should be ignored" do
      let(:user) { Fabricate.build(:user) }

      before do
        SiteSetting.discourse_narrative_bot_ignored_usernames = 'discourse|test'
      end

      ['discourse', 'test'].each do |username|
        it 'should not initiate the bot' do
          expect { user.update!(username: username) }.to_not change { Post.count }
        end
      end
    end
  end

  describe 'when a user has been destroyed' do
    it "should clean up plugin's store" do
      DiscourseNarrativeBot::Store.set(user.id, 'test')

      user.destroy!

      expect(DiscourseNarrativeBot::Store.get(user.id)).to eq(nil)
    end
  end
end
