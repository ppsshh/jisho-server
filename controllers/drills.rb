paths drills: '/drills',
    drill: '/drill/:id',
    flagged: '/flagged',
    kanjidrill: '/kanjidrill'

get :drills do
  protect!
  @drill_sets = Drill.where(user: current_user).order(created_at: :desc)
  slim :drills
end

post :drills do
  protect!

  drill = Drill.create(title: params[:title], user: current_user)

  redirect path_to(:drill).with(drill.id)
end

get :drill do
  protect!
  @drill = Drill.find_by(user: current_user, id: params[:id])
  halt(404, "Drill Set not found") if @drill.blank?

  @elements = @drill.progresses.eager_load(:word).map do |p|
    {
      title: p.title,
      reading: p.word.rebs.first,
      description: p.word.list_desc,
      html_class: p.html_class,
      href: path_to(:word).with(p.seq)
    }
  end

  slim :drill
end

get :flagged do
  @progresses = Progress.where.not(flagged_at: nil).order(flagged_at: :desc)
  slim :flagged
end
get :kanjidrill do
  kanjiused = []
  @words = WkWord.joins(:wk_kanji).merge(
             WkKanji.joins(:kanji).merge(
               Kanji.joins(:progresses).merge(
                 Progress.where(user: current_user, kind: :k).where.not(learned_at: nil)
               )
             )
           ).where(seq: Progress.where(user: current_user, kind: :w).where.not(learned_at: nil).pluck(:seq))
  slim :kanjidrill
end

