class Guide < ActiveRecord::Base
  include ContentIdentifiable
  validate :slug_format
  validate :slug_cant_be_changed_if_an_edition_has_been_published
  validate :new_edition_has_content_owner, if: :requires_content_owner?

  has_many :editions, dependent: :destroy

  scope :by_author, ->(author_id) { where(editions: { author_id: author_id }) if author_id.present? }
  scope :in_state, ->(state) { where(editions: { state: state }) if state.present? }
  scope :owned_by, ->(content_owner_id) { where(editions: { content_owner_id: content_owner_id }) if content_owner_id.present? }

  delegate :title, to: :latest_edition

  def self.with_published_editions
    joins(:editions)
      .where(editions: { state: "published" })
      .uniq
  end

  def self.search(search_terms)
    words = sanitize(search_terms.scan(/\w+/) * "|")
    where("tsv @@ to_tsquery('pg_catalog.english', #{words})")
      .order("ts_rank_cd(tsv, to_tsquery('pg_catalog.english', #{words})) DESC")
  end

  def latest_edition_per_edition_group
    editions
      .select("DISTINCT ON (version) *")
      .order("version DESC, created_at DESC")
  end

  def latest_edition
    editions.most_recent_first.first
  end


  def topic
    Topic.includes(topic_sections: :guides)
      .references(:guides)
      .where("guides.id = ?", id)
      .first
  end

  def included_in_a_topic?
    topic.present?
  end

  def has_published_edition?
    editions.where(state: "published").any?
  end

  def has_unpublished_edition?
    editions.where(state: "unpublished").any?
  end

  def can_be_unpublished?
    has_published_edition? && !has_unpublished_edition?
  end

  def editions_since_last_published
    latest_published_edition = editions.published.last
    return [] unless latest_published_edition.present?
    editions
      .where("created_at > ?", latest_published_edition.created_at)
  end

  def work_in_progress_edition?
    latest_edition.try(:published?) == false
  end

  def comments_for_rendering
    latest_edition.comments.for_rendering
  end

  def requires_content_owner?
    true
  end

private

  def slug_format
    if !slug.to_s.match(/\A\/service-manual\//)
      errors.add(:slug, "must be present and start with '/service-manual/'")
    elsif !slug.to_s.match(/\A\/service-manual\/\w+/)
      errors.add(:slug, "must be filled in")
    elsif !slug.to_s.match(/\A\/service-manual\/[a-z0-9\-\/]+$/i)
      errors.add(:slug, "can only contain letters, numbers and dashes")
    elsif !slug.to_s.match(/\A\/service-manual\/[a-z0-9-]+\/[a-z0-9-]+/)
      errors.add(:slug, "must be present and start with '/service-manual/[topic]'")
    end
  end

  def slug_cant_be_changed_if_an_edition_has_been_published
    if slug_changed? && has_published_edition?
      errors.add(:slug, "can't be changed if guide has a published edition")
    end
  end

  def new_edition_has_content_owner
    new_edition = editions.detect(&:new_record?)

    if new_edition && new_edition.content_owner.nil?
      errors.add(:latest_edition, 'must have a content owner')
    end
  end
end
