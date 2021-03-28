require 'aws-sdk-polly'

# paths with indent: already in use with new frontent
paths \
    word_details: '/api/word', # params: seq
    drill_add_word: '/api/drill/word',
    activity: '/api/activity/:category/:seconds',
api_word_autocomplete: '/api/word/autocomplete',
api_learn:   '/api/word/learn',
api_burn:    '/api/word/burn',
api_comment: '/api/comment',
kanji_readings: '/api/kanji_readings'

get :word_details do
  protect!
  return Collector.new(current_user, words: Word.where(seq: params[:seq])).to_json
end

post :drill_add_word do
  protect!

  drill = Drill.where(user: current_user).order(id: :desc).first
  halt(404, "Drill list not found") if drill.blank?

  word_title = params[:title] || Word.find_by(seq: params[:seq]).krebs.first
  progress = Progress.find_or_initialize_by(seq: params[:seq], title: word_title, user: current_user)
  progress.flagged = true
  progress.save

  drill.progresses << progress

  return 'ok'
end

get :api_word_autocomplete do
  protect!

  ww = Word.where(seq: WordTitle.where(title: params['term']).pluck(:seq)).map{|i|
        {
            id: i.seq,
            value: "#{i.krebs[0]}: #{i.en[0]['gloss'][0]}",
            title: i.krebs[0],
            gloss: i.en[0]['gloss'][0],
            href: path_to(:word).with(i.seq)
        }
  }
  return ww.to_json
end

def find_or_init_progress(p)
  kind = p[:kind].to_sym

  return case p[:kind].to_sym
    when :w
      Progress.find_or_initialize_by(seq: p[:id], title: p[:title], user: current_user)
    when :k
      i = Progress.find_or_initialize_by(kanji_id: p[:id], user: current_user)
      i.title = p[:title]
      i
    when :r
      i = Progress.find_or_initialize_by(wk_radical_id: p[:id], user: current_user)
      i.title = p[:title]
      i
    else
      raise ArgumentError.new('Incorrect "kind" value')
    end
end

post :api_learn do
  protect!

  progress = find_or_init_progress(params)
  progress.learn!

  return progress.api_json
end

post :api_burn do
  protect!

  progress = find_or_init_progress(params)
  progress.burn!

  return progress.api_json
end

post :api_comment do
  protect!

  comment = params[:comment].strip

  if params[:seq].present?
    wd = WordDetail.find_or_create_by(user: current_user, seq: params[:seq])
    wd.update_attribute(:comment, comment.present? ? comment : nil)

    return wd.comment
  elsif params[:kanji].present?
    kanji = Kanji.find_by(title: params[:kanji])
    halt(404, "Kanji not found") if kanji.blank?
    progress = find_or_init_progress({kind: :k, id: kanji.id})
    progress.update(comment: comment.present? ? comment : nil)

    return progress.api_json
  end
end

post :kanji_readings do
  protect!

  kanji = Kanji.find_by(title: params[:kanji])
  halt(404, "Kanji not found" + params.inspect) if kanji.blank?

  result = {}
  kanji.on.each do |on|
    result[on] = Kanji.joins(:kanji_readings).merge(
      KanjiReading.where(reading: on, kind: :on)
    ).where.not(grade: nil).distinct.sort{|a,b| a.grade <=> b.grade}.map{|i| [i.title, i.grade]}
  end if kanji.on.present?

  kanji.kun.map{|i| i.gsub(/\..*/, '')}.uniq.each do |kun|
    kun = kun.gsub(/\..*/, '') # Drop okurigana
    result[kun] = Kanji.joins(:kanji_readings).merge(
      KanjiReading.where('reading SIMILAR TO ?', kun + '(.%)?').where(kind: :kun)
    ).where.not(grade: nil).distinct.sort{|a,b| a.grade <=> b.grade}.map{|i| [i.title, i.grade]}
  end if kanji.kun.present?

  return result.to_json
end

post :activity do
  protect!

  halt(405, "Unknown category") unless %w(search srs kanji kokugo onomat).include?(params[:category])
  a = Activity.find_or_initialize_by(user: current_user, category: params[:category], date: custom_today)
  a.seconds += params[:seconds].to_i
  a.save

  a.seconds.to_s
end

