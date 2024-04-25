# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Project.value_streams', feature_category: :value_stream_management do
  include GraphqlHelpers

  let_it_be(:project) { create(:project) }
  let_it_be(:user) { create(:user) }

  let(:variables) { { fullPath: project.full_path } }

  let(:query) do
    <<~QUERY
      query($fullPath: ID!) {
        project(fullPath: $fullPath) {
          valueStreams {
            nodes {
              id
              name
              stages {
                id
                name
                startEventIdentifier
                endEventIdentifier
              }
            }
          }
        }
      }
    QUERY
  end

  context 'when user has permissions to read value streams' do
    let(:expected_value_stream) do
      {
        'project' => {
          'valueStreams' => {
            'nodes' => [
              {
                'id' => Gitlab::GlobalId.as_global_id('default',
                  model_name: Analytics::CycleAnalytics::ValueStream.to_s).to_s,
                'name' => 'default',
                'stages' => expected_stages
              }
            ]
          }
        }
      }
    end

    let(:expected_stages) do
      [
        {
          'name' => 'issue',
          'id' => stage_id('issue'),
          'startEventIdentifier' => 'ISSUE_CREATED',
          'endEventIdentifier' => 'ISSUE_STAGE_END'
        },
        {
          'name' => 'plan',
          'id' => stage_id('plan'),
          'startEventIdentifier' => 'PLAN_STAGE_START',
          'endEventIdentifier' => 'ISSUE_FIRST_MENTIONED_IN_COMMIT'
        },
        {
          'name' => 'code',
          'id' => stage_id('code'),
          'startEventIdentifier' => 'CODE_STAGE_START',
          'endEventIdentifier' => 'MERGE_REQUEST_CREATED'
        },
        {
          'name' => 'test',
          'id' => stage_id('test'),
          'startEventIdentifier' => 'MERGE_REQUEST_LAST_BUILD_STARTED',
          'endEventIdentifier' => 'MERGE_REQUEST_LAST_BUILD_FINISHED'
        },
        {
          'name' => 'review',
          'id' => stage_id('review'),
          'startEventIdentifier' => 'MERGE_REQUEST_CREATED',
          'endEventIdentifier' => 'MERGE_REQUEST_MERGED'
        },
        {
          'name' => 'staging',
          'id' => stage_id('staging'),
          'startEventIdentifier' => 'MERGE_REQUEST_MERGED',
          'endEventIdentifier' => 'MERGE_REQUEST_FIRST_DEPLOYED_TO_PRODUCTION'
        }
      ]
    end

    def stage_id(name)
      Gitlab::GlobalId.as_global_id(name, model_name: Analytics::CycleAnalytics::Stage.to_s).to_s
    end

    before_all do
      project.add_guest(user)
    end

    before do
      post_graphql(query, current_user: user, variables: variables)
    end

    it_behaves_like 'a working graphql query'

    it 'returns only `default` value stream' do
      expect(graphql_data).to eq(expected_value_stream)
    end

    context 'when specifying the value stream id argument' do
      let(:variables) { { fullPath: project.full_path } }

      let(:query) do
        <<~QUERY
          query($fullPath: ID!, $stageId: ID) {
            project(fullPath: $fullPath) {
              valueStreams {
                nodes {
                  name
                  stages(id: $stageId) {
                    name
                  }
                }
              }
            }
          }
        QUERY
      end

      it 'locates the default value stream' do
        expect(graphql_data_at(:project, :value_streams, :nodes)).to match([hash_including('name' => 'default')])
      end

      context 'when specifying the stage id argument' do
        let(:stage_id) { Gitlab::GlobalId.as_global_id('test', model_name: Analytics::CycleAnalytics::Stage.to_s).to_s }
        let(:variables) { { fullPath: project.full_path, stageId: stage_id } }

        it 'returns only the test stage' do
          expected_value_stream = hash_including(
            'name' => 'default',
            'stages' => [hash_including('name' => 'test')]
          )

          expect(graphql_data_at(:project, :value_streams, :nodes)).to match([expected_value_stream])
        end

        context 'when bogus stage id is given' do
          let(:stage_id) do
            Gitlab::GlobalId.as_global_id('bogus', model_name: Analytics::CycleAnalytics::Stage.to_s).to_s
          end

          let(:variables) { { fullPath: project.full_path, stageId: stage_id } }

          it 'returns no data error' do
            expect(graphql_data_at(:project, :value_streams, :nodes, 0, :stages, :nodes)).to be_empty
          end
        end
      end
    end
  end

  context 'when user does not have permission to read value streams' do
    before do
      post_graphql(query, current_user: user, variables: variables)
    end

    it 'returns nil' do
      expect(graphql_data_at(:project, :valueStreams)).to be_nil
    end
  end
end
