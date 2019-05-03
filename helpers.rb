module WakameHelpers
  def protect!
    return if current_user
    halt 401, "Unauthorized"
  end

  def current_user
    return nil unless session['user_id'].present?

    @current_user ||= User.find(session['user_id'])
    return @current_user
  end

  def current_level
    return 1 unless current_user

    @current_level ||= @current_user.current_level
    return @current_level
  end

  def bb_expand(text)
    text = text.gsub(/\[kanji\]([^\[]*)\[\/kanji\]/, "[%(k)\\1%]")
    text = text.gsub(/\[radical\]([^\[]*)\[\/radical\]/, "[%(r)\\1%]")
    text = text.gsub(/\[meaning\]([^\[]*)\[\/meaning\]/, "[%(m)\\1%]")
    text = text.gsub(/\[reading\]([^\[]*)\[\/reading\]/, "[%(y)\\1%]")
    text = text.gsub(/\[vocabulary\]([^\[]*)\[\/vocabulary\]/, "[%(w)\\1%]")
    return text
  end

  def bb_textile(text)
    RedCloth.new( bb_expand(text) ).to_html
  end

  def highlight(text, term)
    return text unless text.present? && term.present?

    termj = term.downcase.hiragana
    terms = termj.japanese? ? [term, termj, term.downcase.katakana] : [term]
    hhash = highlight_find(text, terms)
    return highlight_html(hhash)
  end

  def highlight_html(hhash)
    result = ""
    hhash.each do |h|
      result += h[:h] == true ? "<span class='highlight'>#{h[:t]}</span>" : h[:t]
    end
    return result
  end

  def highlight_find(text, terms)
    i, term = nil, nil
    terms.each do |t|
      next unless i.blank?
      i = text.index(Regexp.new(t, Regexp::IGNORECASE))
      term = t if i.present?
    end

    result = []
    if i != nil
      result << {t: text[0...i], h: false} if i > 0
      result << {t: text[i...(i+term.length)], h: true}
      if i + term.length < text.length
        result << highlight_find(text[(i+term.length)..-1], terms)
      end
    else
      result << {t: text, h: false}
    end
    return result.flatten
  end

  def wk_path(e)
    if e.kind_of?(WkWord)
      path_to(:wk_word).with(e.id)
    elsif e.kind_of?(WkKanji)
      path_to(:wk_kanji).with(e.id)
    elsif e.kind_of?(WkRadical)
      path_to(:wk_radical).with(e.id)
    else
      raise StandardError.new("Unknown WkElement kind: #{e}")
    end
  end

  SAFE_TYPES = [:radicals, :kanjis, :words]
  SAFE_GROUPS = [:just_unlocked, :just_learned, :expired, :failed]

  def safe_type(method)
    m = method.to_sym
    throw StandardError.new("Unknown method: #{method}") unless SAFE_TYPES.include?(m)
    return m
  end

  def safe_group(method)
    m = method.to_sym
    throw StandardError.new("Unknown method: #{method}") unless SAFE_GROUPS.include?(m)
    return m
  end

  def kr_common?(kreb)
    return false unless kreb && kreb['pri']
    kreb['pri'].each do |k,v|
      return true if %w(news ichi spec gai).include?(k) && v == 1
      return true if k == 'spec' && v == 2
    end
    return false
  end

  def jp_grade(grade)
    grade = grade.to_i
    if grade <= 3
      return "小#{grade}"
    elsif grade <= 6
      return "中#{grade-3}"
    elsif grade == 8
      return "高校"
    elsif grade == 9
      return "人名用"
    else
      return "Grade #{grade}"
    end
  end

  def kanji_json(kanji, prefetched = {})
    result = kanji.serializable_hash(only: [:id, :title, :jlptn, :english, :on, :kun])

    if (w = kanji.wk_kanji).present?
      result = result.merge({
        wk_level: w.level,
        emph: w.details['yomi']['emph'],
        mmne: w.details['mmne'],
        mhnt: w.details['mhnt'],
        rmne: w.details['rmne'],
        rhnt: w.details['rhnt']
      })
    end

    progress = prefetched[:progress] || kanji.progresses.where(user: current_user).take
    result[:progress] = progress.api_hash if progress.present?
    return result
  end

  def radical_json(id)
    radical = WkRadical.where(id: id).with_progress(current_user)[0]
    result = radical.serializable_hash(only: [:title, :details])
    result[:progress] = radical.progresses.where(user: current_user).take.try(:api_hash) || {}
    return result
  end

  def word_json(seq, prefetched = {})
    word = prefetched[:word] || Word.includes(:short_words, :long_words, :wk_words, :word_titles).find_by(seq: seq)
    result = word.serializable_hash(only: [:seq, :en, :ru, :jlptn, :nf])

    @title = word.word_titles.first.title
    result[:comment] = prefetched[:word_details] || word.word_details.where(user: current_user).take.try(:comment) || ''

    progresses = prefetched[:progresses] || Progress.where(seq: seq, user: current_user)
    result[:krebs] = word.word_titles.sort{|a,b| a.id <=> b.id}.map do |t|
      {
        title: t.title,
        is_common: t.is_common,
        progress: progresses.detect{|p| p.title == t.title}.try(:api_hash) || {}
      }
    end

#    result[:sentences] = word.all_sentences.map{|i| {jp: i.japanese, en: i.english, href: path_to(:sentence).with(i.id)}}
#    rawSentences = Sentence.where(structure: nil).where('japanese ~ ?', word.krebs.join('|')) # possible sentences
#    result[:rawSentences] = rawSentences.map{|i| {jp: i.japanese, en: i.english, href: path_to(:sentence).with(i.id)}}
    result = result.merge({sentences: [], rawSentences: []}) # Empty placeholder

    kanjis = prefetched[:kanjis] || (word.kanji.blank? ? {} : Kanji.includes(:wk_kanji).where(title: word.kanji.split('')))
    kanji_progresses = prefetched[:kanji_progresses] || Progress.where(kanji_id: kanjis.map{|i|i.id}, user: current_user)
    result[:kanjis] = kanjis.map do |k|
      _progress = kanji_progresses.detect{|i| i.kanji_id == k.id} || Progress.none
      kanji_json(k, _progress ? {progress: _progress} : {})
    end

    return result.merge({
      shortWords: word.short_words.map{|i| {seq: i.seq, title: i.krebs[0], href: path_to(:word).with(i.seq)}},
      longWords:  word.long_words.map{|i| {seq: i.seq, title: i.krebs[0], href: path_to(:word).with(i.seq)}},
      cards: word.wk_words.sort{|a,b| a.level <=> b.level}.map{|c|
        {
          title: c.title,
          level: c.level,
          readings: c.details['readings'].join(', '),
          en:    c.details['en'].join(', '),
          pos:   c.details['pos'],
          mexp:  c.details['mexp'],
          rexp:  c.details['rexp']
        }
      },
      paths: {
        connect: path_to(:word_connect),
        learn:   path_to(:word_learn),
        burn:    path_to(:word_burn),
        flag:    path_to(:word_flag),
        comment: path_to(:word_set_comment).with(word.seq),
        drill:   path_to(:drill_add_word),
        autocomplete: path_to(:autocomplete_word)
      }
    })
  end
end
