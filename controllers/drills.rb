paths drills: '/drills',
    drill: '/drill/:id'

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

  @elements = @drill.progresses.eager_load(:word, :srs_progresses).order(:id).map do |p|
    {
      title: p.title,
      reading: p.word.rebs.first,
      description: p.word.list_desc,
      reading_class: p.burned_at ? :burned : p.srs_progresses.detect{|i|
          i.learning_type == 'reading_question'}.try(:html_class_leitner) || :pristine,
      kanji_class: p.burned_at ? :burned : p.srs_progresses.detect{|i|
          i.learning_type == 'kanji_question'}.try(:html_class_leitner) || :pristine,
      href: path_to(:word).with(p.seq),
    }
  end

  slim :drill
end

patch :drill do
  protect!

  drill = Drill.find(params[:id])
  halt(403, "Access denied") if drill.user_id != current_user.id

  if params[:enabled].present?
    drill.update(is_active: params[:enabled] == '0' ? false : true)
    return {
      text: params[:enabled] == '0' ? 'Enable' : 'Disable',
      value: params[:enabled] == '0' ? 1 : 0
    }.to_json
  elsif params[:reset] == 'reading'
    drill.reset_leitner(:reading_question)
  elsif params[:reset] == 'kanji'
    drill.reset_leitner(:kanji_question)
  end

  return '{}'
end

