require "rails_helper"

RSpec.describe ChangeNoteMigrator do
  let(:publishing_api) { double(:publishing_api) }
  let(:guide) { create(:guide) }
  let(:major_edition) { create(:edition, :published, update_type: "major", version: 2, guide: guide) }
  let(:minor_edition) { create(:edition, :published, update_type: "minor", version: 2, guide: guide) }
  let(:unpublished_edition) { create(:edition, :draft, guide: guide, version: 1) }
  let(:change_note) { "I am a change note" }

  context "with dry_run mode enabled" do
    subject { described_class.new(publishing_api: publishing_api, dry_run: true) }

    it "does not call the publishing API" do
      subject.update_change_note(major_edition.id, change_note)
      subject.make_major(minor_edition.id, change_note)
      subject.make_minor(major_edition.id)

      aggregate_failures do
        expect(publishing_api).to_not receive(:put_content)
        expect(publishing_api).to_not receive(:patch_links)
        expect(publishing_api).to_not receive(:publish)
      end
    end
  end

  context "with dry_run mode disabled" do
    subject { described_class.new(publishing_api: publishing_api, dry_run: false) }
    before do
      allow(publishing_api).to receive(:put_content)
      allow(publishing_api).to receive(:patch_links)
      allow(publishing_api).to receive(:publish)
    end

    describe "#update_change_note" do
      it "does not load non-published editions" do
        expect { subject.update_change_note(unpublished_edition.id, "foo") }.to raise_exception ActiveRecord::RecordNotFound
      end

      it "updates the edition's change note" do
        subject.update_change_note(major_edition.id, change_note)
        major_edition.reload
        expect(major_edition.change_note).to eq(change_note)
      end

      it "updates the guide in the publishing API" do
        aggregate_failures do
          expect(publishing_api).to receive(:put_content)
          expect(publishing_api).to receive(:patch_links)
          expect(publishing_api).to receive(:publish).with(guide.content_id, "republish")
        end

        subject.update_change_note(major_edition.id, change_note)
      end
    end

    describe "#make_major" do
      it "does not load non-published editions" do
        expect { subject.make_major(unpublished_edition.id, "foo") }.to raise_exception ActiveRecord::RecordNotFound
      end

      it "updates the edition's update type and change note" do
        subject.make_major(minor_edition.id, change_note)
        minor_edition.reload
        aggregate_failures do
          expect(minor_edition.update_type).to eq "major"
          expect(minor_edition.change_note).to eq change_note
        end
      end

      it "updates the guide in the publishing API" do
        aggregate_failures do
          expect(publishing_api).to receive(:put_content)
          expect(publishing_api).to receive(:patch_links)
          expect(publishing_api).to receive(:publish).with(guide.content_id, "republish")
        end

        subject.make_major(minor_edition.id, change_note)
      end
    end

    describe "#make_minor" do
      it "does not load non-published editions" do
        expect { subject.make_minor(unpublished_edition.id) }.to raise_exception ActiveRecord::RecordNotFound
      end

      it "updates the edition's update type" do
        subject.make_minor(major_edition.id)
        major_edition.reload
        expect(major_edition.update_type).to eq "minor"
      end

      it "updates the guide in the publishing API" do
        aggregate_failures do
          expect(publishing_api).to receive(:put_content)
          expect(publishing_api).to receive(:patch_links)
          expect(publishing_api).to receive(:publish).with(guide.content_id, "republish")
        end

        subject.make_minor(major_edition.id)
      end
    end

    describe "#revise_version" do
      it "updates any edition, even unpublished ones" do
        subject.revise_version(unpublished_edition.id, 2)

        unpublished_edition.reload
        expect(unpublished_edition.version).to eq(2)
      end
    end
  end
end
