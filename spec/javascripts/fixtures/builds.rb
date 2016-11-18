require 'spec_helper'

describe Projects::BuildsController, '(JavaScript fixtures)', type: :controller do
  include JavaScriptFixturesHelpers

  let(:admin) { create(:admin) }
  let(:project) { create(:project_empty_repo) }
  let(:pipeline) { create(:ci_empty_pipeline, project: project) }
  let!(:build_with_artifacts) { create(:ci_build, :success, :artifacts, :trace, pipeline: pipeline, stage: 'test', artifacts_expire_at: Time.now + 18.months) }
  let!(:failed_build) { create(:ci_build, :failed, pipeline: pipeline, stage: 'build') }
  let!(:pending_build) { create(:ci_build, :pending, pipeline: pipeline, stage: 'deploy') }

  render_views

  before(:all) do
    clean_frontend_fixtures('builds/')
  end

  before(:each) do
    sign_in(admin)
  end

  it 'builds/build-with-artifacts.html.raw' do |example|
    get :show,
      namespace_id: project.namespace.to_param,
      project_id: project.to_param,
      id: build_with_artifacts.to_param

    expect(response).to be_success
    store_frontend_fixture(response, example.description)
  end
end
