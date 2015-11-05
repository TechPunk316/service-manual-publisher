require 'rails_helper'
require 'capybara/rails'
require 'gds_api/publishing_api_v2'

RSpec.describe "creating guides", type: :feature do
  let(:api_double) { double(:publishing_api) }

  before do
    visit root_path
    click_link "Create a Guide"
  end

  it "has a prepopulated slug field" do
    expect(find_field('Slug').value).to eq "/service-manual/"
  end

  it "saves draft guide editions" do
    fill_in_guide_form

    expect(GdsApi::PublishingApiV2).to receive(:new).and_return(api_double).twice # save and update
    expect(api_double).to receive(:put_content)
                            .twice
                            .with(an_instance_of(String), be_valid_against_schema('service_manual_guide'))

    click_button "Save Draft"

    within ".alert" do
      expect(page).to have_content('created')
    end

    guide = Guide.find_by_slug("/service-manual/the/path")
    edition = guide.latest_edition
    content_id = guide.content_id
    expect(content_id).to be_present
    expect(edition.related_discussion_title).to eq "Discussion on HackPad"
    expect(edition.related_discussion_href).to eq "https://designpatterns.hackpad.com/"
    expect(edition.publisher_title).to eq "Design Community"
    expect(edition.phase).to eq "beta"
    expect(edition.title).to eq "First Edition Title"
    expect(edition.body).to eq "## First Edition Title"
    expect(edition.update_type).to eq "major"
    expect(edition.change_note).to eq "Change Note"
    expect(edition.draft?).to eq true
    expect(edition.published?).to eq false

    visit edit_guide_path(guide)
    fill_in "Title", with: "Second Edition Title"
    click_button "Save Draft"

    within ".alert" do
      expect(page).to have_content('updated')
    end

    guide = Guide.find_by_slug("/service-manual/the/path")
    edition = guide.latest_edition
    expect(guide.content_id).to eq content_id
    expect(edition.title).to eq "Second Edition Title"
    expect(edition.draft?).to eq true
    expect(edition.published?).to eq false
  end

  it "publishes guide editions" do
    fill_in_guide_form

    expect(GdsApi::PublishingApiV2).to receive(:new).and_return(api_double).twice
    expect(api_double).to receive(:put_content)
                            .twice
                            .with(an_instance_of(String), be_valid_against_schema('service_manual_guide'))
    expect(api_double).to receive(:publish)
                            .once
                            .with(an_instance_of(String), 'major')

    click_button "Save Draft"
    guide = Guide.first
    visit edit_guide_path(guide)
    click_button "Send for review"

    login_as(User.new(name: "Reviewer")) do
      visit edit_guide_path(guide)
      click_button "Mark as Approved"
    end

    visit edit_guide_path(guide)
    click_button "Publish"

    within ".alert" do
      expect(page).to have_content('updated')
    end

    guide = Guide.find_by_slug("/service-manual/the/path")
    edition = guide.latest_edition
    expect(edition.title).to eq "First Edition Title"
    expect(edition.draft?).to eq false
    expect(edition.published?).to eq true
  end

  context "when creating a new guide" do
    context "when publishing raises an exception" do
      before do
        api_error = GdsApi::HTTPClientError.new(422, "Error message stub", "error" => { "message" => "Error message stub" })
        expect_any_instance_of(GdsApi::PublishingApiV2).to receive(:put_content).and_raise(api_error)
      end

      it "shows api errors" do
        fill_in_guide_form
        click_button "Save Draft"

        within ".alert" do
          expect(page).to have_content('Error message stub')
        end
      end

      it "does not store a guide" do
        fill_in_guide_form
        click_button "Save Draft"

        expect(Guide.count).to eq 0
        expect(Edition.count).to eq 0
      end
    end
  end

  context "when updating a guide" do
    context "when publishing raises an exception" do
      let :api_error do
        GdsApi::HTTPClientError.new(422, "Error message stub", "error" => { "message" => "Error message stub" })
      end

      it "shows api errors" do
        edition = Generators.valid_edition(title: "something")
        guide = Guide.create!(slug: "/service-manual/something", latest_edition: edition)

        expect_any_instance_of(GuidePublisher).to receive(:process).once.and_raise(api_error)

        visit edit_guide_path(guide)
        click_button "Save Draft"

        within ".alert" do
          expect(page).to have_content('Error message stub')
        end
      end

      it "does not store a new extra edition" do
        edition = Generators.valid_edition(title: "Original Title")
        guide = Guide.create!(slug: "/service-manual/something", latest_edition: edition)

        expect_any_instance_of(GuidePublisher).to receive(:process).once.and_raise(api_error)

        visit edit_guide_path(guide)
        fill_in "Title", with: "Changed Title"
        click_button "Save Draft"

        expect(Guide.count).to eq 1
        expect(Guide.first.latest_edition.title).to_not eq "Changed Title"
        expect(Edition.count).to eq 1
      end
    end
  end

  it "allows discourse" do
    edition = Generators.valid_edition
    guide = Guide.create!(
      latest_edition: edition,
      slug: "/service-manual/test/slug_published"
    )

    visit edit_guide_path(guide)
    within ".comments" do
      fill_in "Comment", with: "This is my comment"
      click_button "Comment"
    end

    visit edit_guide_path(guide)
    within ".comments .comment" do
      expect(page).to have_content "Stub User"
      expect(page).to have_content "This is my comment"
    end
  end

private

  def fill_in_guide_form
    fill_in "Slug", with: "/service-manual/the/path"
    fill_in "Related discussion title", with: "Discussion on HackPad"
    fill_in "Link to related discussion", with: "https://designpatterns.hackpad.com/"
    select "Design Community", from: "Published by"
    select "Beta", from: "Phase"
    fill_in "Description", with: "This guide acts as a test case"

    fill_in "Title", with: "First Edition Title"
    fill_in "Body", with: "## First Edition Title"

    select "Major", from: "Update type"
    fill_in "Change note", with: "Change Note"
  end
end
