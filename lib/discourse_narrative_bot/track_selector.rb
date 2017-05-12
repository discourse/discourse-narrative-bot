module DiscourseNarrativeBot
  class TrackSelector
    include Actions

    GENERIC_REPLIES_COUNT_PREFIX = 'discourse-narrative-bot:track-selector-count:'.freeze
    PUBLIC_DISPLAY_BOT_HELP_KEY = 'discourse-narrative-bot:track-selector:display-bot-help'.freeze

    TRACKS = [
      NewUserNarrative,
      AdvancedUserNarrative
    ]

    RESET_TRIGGER = 'start'.freeze
    SKIP_TRIGGER = 'skip'.freeze
    HELP_TRIGGER = 'help'.freeze

    TOPIC_ACTIONS = [
      :delete,
      :topic_notification_level_changed
    ].each(&:freeze)

    def initialize(input, user, post_id:, topic_id: nil)
      @input = input
      @user = user
      @post_id = post_id
      @topic_id = topic_id
      @post = Post.find_by(id: post_id)
    end

    def select
      data = Store.get(@user.id)

      if @post && !is_topic_action?
        return if reset_track

        topic_id = @post.topic_id
        is_reply = @input == :reply

        if (data && data[:topic_id] == topic_id)
          state = data[:state]
          klass = (data[:track] || NewUserNarrative.to_s).constantize

          if is_reply && like_user_post
            Store.set(@user.id, data.merge!(state: nil, topic_id: nil))
          elsif state&.to_sym == :end && is_reply
            bot_commands(bot_mentioned?) || generic_replies(klass::RESET_TRIGGER)
          elsif is_reply
            previous_status = data[:attempted]
            current_status = klass.new.input(@input, @user, post: @post, skip: skip_track?)
            data = Store.get(@user.id)
            data[:attempted] = !current_status

            if previous_status && data[:attempted] == previous_status && !data[:skip_attempted]
              generic_replies(klass::RESET_TRIGGER, state)
            else
              $redis.del(generic_replies_key(@user))
            end

            Store.set(@user.id, data)
          else
            klass.new.input(@input, @user, post: @post, skip: skip_track?)
          end
        elsif is_reply && (pm_to_bot?(@post) || public_reply?)
          like_user_post
          bot_commands
        end
      elsif data && data.dig(:state)&.to_sym != :end && is_topic_action?
        klass = (data[:track] || NewUserNarrative.to_s).constantize
        klass.new.input(@input, @user, post: @post, topic_id: @topic_id)
      end
    end

    private

    def is_topic_action?
      @is_topic_action ||= TOPIC_ACTIONS.include?(@input)
    end

    def reset_track
      reset = false

      TRACKS.each do |klass|
        if selected_track(klass)
          klass.new.reset_bot(@user, @post)
          reset = true
          break
        end
      end

      reset
    end

    def selected_track(klass)
      return if klass.respond_to?(:can_start?) && !klass.can_start?(@user)
      match_trigger?(@post.raw, "#{RESET_TRIGGER} #{klass::RESET_TRIGGER}")
    end

    def bot_commands(display_help = true)
      post_raw = @post.raw

      raw =
        if match_data = match_trigger?(post_raw, 'roll (\d+)d(\d+)')
          DiscourseNarrativeBot::Dice.roll(match_data[1].to_i, match_data[2].to_i)
        elsif match_trigger?(post_raw, 'quote')
          DiscourseNarrativeBot::QuoteGenerator.generate(@user)
        elsif match_trigger?(post_raw, 'fortune')
          DiscourseNarrativeBot::Magic8Ball.generate_answer
        elsif match_trigger?(post_raw, HELP_TRIGGER)
          help_message
        end

      if raw
        fake_delay
        reply_to(@post, raw, skip_validations: true)
      end
    end

    def help_message
      tracks = [NewUserNarrative::RESET_TRIGGER]

      if @user.staff? ||
         @user.badges.where(name: DiscourseNarrativeBot::NewUserNarrative::BADGE_NAME).exists?

        tracks << AdvancedUserNarrative::RESET_TRIGGER
      end

      discobot_username = self.class.discobot_user.username

      message = I18n.t(
        i18n_key('random_mention.tracks'),
        discobot_username: discobot_username,
        reset_trigger: RESET_TRIGGER,
        default_track: NewUserNarrative::RESET_TRIGGER,
        tracks: tracks.join(', ')
      )

      message << "\n\n#{I18n.t(i18n_key('random_mention.bot_actions'), discobot_username: discobot_username)}"
    end

    def generic_replies_key(user)
      "#{GENERIC_REPLIES_COUNT_PREFIX}#{user.id}"
    end

    def generic_replies(reset_trigger, state = nil)
      reset_trigger = "#{RESET_TRIGGER} #{reset_trigger}"
      key = generic_replies_key(@user)
      count = ($redis.get(key) || $redis.setex(key, 900, 0)).to_i

      case count
      when 0
        raw = I18n.t(i18n_key('do_not_understand.first_response'))

        if state && state.to_sym != :end
          raw = "#{raw}\n\n#{I18n.t(i18n_key('do_not_understand.track_response'), reset_trigger: reset_trigger, skip_trigger: SKIP_TRIGGER)}"
        end

        reply_to(@post, raw)
      when 1
        reply_to(@post, I18n.t(i18n_key('do_not_understand.second_response'),
          reset_trigger: reset_trigger
        ))
      else
        # Stay out of the user's way
      end

      $redis.incr(key)
    end

    def i18n_key(key)
      "discourse_narrative_bot.track_selector.#{key}"
    end

    def skip_track?
      if pm_to_bot?(@post)
        post_raw = @post.raw

        post_raw.match(/^@#{self.class.discobot_user.username} #{SKIP_TRIGGER}/i) ||
          post_raw.strip == SKIP_TRIGGER
      else
        false
      end
    end

    def match_trigger?(text, trigger)
      match = text.match(Regexp.new("@#{self.class.discobot_user.username} #{trigger}", 'i'))

      if pm_to_bot?(@post)
        match || text.strip.match(Regexp.new("^#{trigger}$", 'i'))
      else
        match
      end
    end

    def like_user_post
      if @post.raw.match(/thank/i)
        PostAction.act(self.class.discobot_user, @post, PostActionType.types[:like])
      end
    end

    def bot_mentioned?
      @bot_mentioned ||= PostAnalyzer.new(@post.raw, @post.topic_id).raw_mentions.include?(
        self.class.discobot_user.username
      )
    end

    def public_reply?
      !SiteSetting.discourse_narrative_bot_disable_public_replies &&
        (bot_mentioned? || reply_to_bot_post?(@post))
    end
  end
end
