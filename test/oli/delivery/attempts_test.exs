defmodule Oli.Delivery.AttemptsTest do
  use Oli.DataCase

  alias Oli.Delivery.Attempts.Core, as: Attempts

  alias Oli.Delivery.Attempts.PageLifecycle
  alias Oli.Delivery.Attempts.PageLifecycle.{Hierarchy, VisitContext, AttemptState}
  alias Oli.Delivery.Attempts.ActivityLifecycle.Evaluate

  alias Oli.Activities.Model.{Part, Feedback}
  alias Oli.Delivery.Page.PageContext
  alias Oli.Delivery.Attempts.Core.{ClientEvaluation, StudentInput, ActivityAttempt}

  describe "creating the attempt tree records" do
    setup do
      content1 = %{
        "stem" => "1",
        "authoring" => %{
          "parts" => [
            %{
              "id" => "1",
              "responses" => [],
              "scoringStrategy" => "best",
              "evaluationStrategy" => "regex"
            }
          ]
        }
      }

      content2 = %{
        "stem" => "2",
        "authoring" => %{
          "parts" => [
            %{
              "id" => "1",
              "responses" => [],
              "scoringStrategy" => "best",
              "evaluationStrategy" => "regex"
            }
          ]
        }
      }

      map =
        Seeder.base_project_with_resource2()
        |> Seeder.create_section()
        |> Seeder.add_objective("objective one", :o1)
        |> Seeder.add_activity(%{title: "one", content: content1}, :a1)
        |> Seeder.add_activity(%{title: "two", content: content2}, :a2)
        |> Seeder.add_user(%{}, :user1)
        |> Seeder.add_user(%{}, :user2)

      attrs = %{
        title: "page1",
        content: %{
          "model" => [
            %{"type" => "activity-reference", "activity_id" => Map.get(map, :a1).resource.id},
            %{"type" => "activity-reference", "activity_id" => Map.get(map, :a2).resource.id}
          ]
        },
        objectives: %{"attached" => [Map.get(map, :o1).resource.id]},
        graded: true
      }

      Seeder.add_page(map, attrs, :p1)
      |> Seeder.create_section_resources()
    end

    test "create the attempt tree", %{
      p1: p1,
      user1: user,
      section: section,
      a1: a1,
      a2: a2,
      publication: pub
    } do
      Attempts.track_access(p1.resource.id, section.id, user.id)

      activity_provider = &Oli.Delivery.ActivityProvider.provide/3

      {:ok, resource_attempt} =
        Hierarchy.create(%VisitContext{
          latest_resource_attempt: nil,
          page_revision: p1.revision,
          section_slug: section.slug,
          user_id: user.id,
          activity_provider: activity_provider,
          blacklisted_activity_ids: [],
          publication_id: pub.id
        })

      # verify that creating the attempt tree returns both activity attempts
      {:ok, %AttemptState{resource_attempt: resource_attempt, attempt_hierarchy: attempts}} =
        AttemptState.fetch_attempt_state(resource_attempt, p1.revision)

      assert Map.has_key?(attempts, a1.resource.id)
      assert Map.has_key?(attempts, a2.resource.id)

      # verify that reading the latest attempts back from the db gives us
      # the same results
      attempts = Hierarchy.get_latest_attempts(resource_attempt.id)
      assert Map.has_key?(attempts, a1.resource.id)
      assert Map.has_key?(attempts, a2.resource.id)
    end

    test "tracking user resource access", %{
      user1: user1,
      user2: user2,
      section: section,
      p1: %{resource: resource}
    } do
      Attempts.track_access(resource.id, section.id, user1.id)
      Attempts.track_access(resource.id, section.id, user1.id)

      entries = Oli.Repo.all(Oli.Delivery.Attempts.Core.ResourceAccess)
      assert length(entries) == 1
      assert hd(entries).access_count == 2

      Attempts.track_access(resource.id, section.id, user2.id)
      entries = Oli.Repo.all(Oli.Delivery.Attempts.Core.ResourceAccess)
      assert length(entries) == 2

      # assert the access counts in a way that disregards the order of the access records
      first = Enum.at(entries, 0)
      second = Enum.at(entries, 1)

      if first.user_id == user2.id do
        assert first.access_count == 1
        assert second.access_count == 2
      else
        assert first.access_count == 2
        assert second.access_count == 1
      end
    end

    test "starting a graded resource attempt with one user", %{
      p1: %{revision: revision, resource: resource},
      section: section,
      user1: user1
    } do
      activity_provider = &Oli.Delivery.ActivityProvider.provide/3

      PageContext.create_for_visit(section, revision.slug, user1)

      # Page 1
      {:ok, %AttemptState{resource_attempt: resource_attempt}} =
        PageLifecycle.start(revision.slug, section.slug, user1.id, activity_provider)

      {:error, {:active_attempt_present}} =
        PageLifecycle.start(revision.slug, section.slug, user1.id, activity_provider)

      # No page
      {:error, {:not_found}} =
        PageLifecycle.start("garbage slug", section.slug, user1.id, activity_provider)

      # The started attempt should be the latest attempt for this user
      latest_attempt = Attempts.get_latest_resource_attempt(resource.id, section.slug, user1.id)
      assert latest_attempt.id == resource_attempt.id

      # Make sure the progress state is correct for the latest resource attempt
      {:ok, {:in_progress, _ra}} =
        PageLifecycle.visit(
          revision,
          section.slug,
          user1.id,
          activity_provider
        )
    end

    test "starting a graded resource attempt with two users", %{
      p1: %{revision: revision, resource: resource},
      section: section,
      user1: user1,
      user2: user2
    } do
      activity_provider = &Oli.Delivery.ActivityProvider.provide/3

      PageContext.create_for_visit(section, revision.slug, user1)
      PageContext.create_for_visit(section, revision.slug, user2)

      # User1 - same as above
      {:ok, %AttemptState{resource_attempt: resource_attempt}} =
        PageLifecycle.start(
          revision.slug,
          section.slug,
          user1.id,
          activity_provider
        )

      latest_attempt = Attempts.get_latest_resource_attempt(resource.id, section.slug, user1.id)
      assert latest_attempt.id == resource_attempt.id

      {:ok, {:in_progress, _ra}} =
        PageLifecycle.visit(
          revision,
          section.slug,
          user1.id,
          activity_provider
        )

      # User2
      # Should not have an attempt yet
      {:ok, {:not_started, _ra}} =
        PageLifecycle.visit(
          revision,
          section.slug,
          user2.id,
          activity_provider
        )

      # Start an attempt, should have same results as user1 above
      {:ok, %AttemptState{resource_attempt: resource_attempt2}} =
        PageLifecycle.start(revision.slug, section.slug, user2.id, activity_provider)

      latest_attempt2 = Attempts.get_latest_resource_attempt(resource.id, section.slug, user2.id)
      assert latest_attempt2.id == resource_attempt2.id

      {:ok, {:in_progress, _ra}} =
        PageLifecycle.visit(
          revision,
          section.slug,
          user2.id,
          activity_provider
        )
    end
  end

  describe "fetching attempt records" do
    setup do
      Seeder.base_project_with_resource2()
      |> Seeder.create_section()
      |> Seeder.add_user(%{}, :user1)
      |> Seeder.add_user(%{}, :user2)
      |> Seeder.add_activity(%{}, :publication, :project, :author, :activity_a)
      |> Seeder.add_page(%{graded: true}, :graded_page)
      |> Seeder.create_section_resources()
      |> Seeder.create_resource_attempt(
        %{attempt_number: 1},
        :user1,
        :page1,
        :revision1,
        :attempt1
      )
      |> Seeder.create_activity_attempt(
        %{attempt_number: 1, transformed_model: %{some: :thing}},
        :activity_a,
        :attempt1,
        :activity_attempt1
      )
      |> Seeder.create_part_attempt(
        %{attempt_number: 1},
        %Part{id: "1", responses: [], hints: []},
        :activity_attempt1,
        :part1_attempt1
      )
      |> Seeder.create_resource_attempt(
        %{attempt_number: 2},
        :user1,
        :page1,
        :revision1,
        :attempt2
      )
      |> Seeder.create_activity_attempt(
        %{attempt_number: 1, transformed_model: nil},
        :activity_a,
        :attempt2,
        :activity_attempt2
      )
      |> Seeder.create_part_attempt(
        %{attempt_number: 1},
        %Part{id: "1", responses: [], hints: []},
        :activity_attempt2,
        :part1_attempt1
      )
      |> Seeder.create_part_attempt(
        %{attempt_number: 2},
        %Part{id: "1", responses: [], hints: []},
        :activity_attempt2,
        :part1_attempt2
      )
      |> Seeder.create_part_attempt(
        %{attempt_number: 3},
        %Part{id: "1", responses: [], hints: []},
        :activity_attempt2,
        :part1_attempt3
      )
      |> Seeder.create_part_attempt(
        %{attempt_number: 1},
        %Part{id: "2", responses: [], hints: []},
        :activity_attempt2,
        :part2_attempt1
      )
      |> Seeder.create_part_attempt(
        %{attempt_number: 1},
        %Part{id: "3", responses: [], hints: []},
        :activity_attempt2,
        :part3_attempt1
      )
      |> Seeder.create_part_attempt(
        %{attempt_number: 2},
        %Part{id: "3", responses: [], hints: []},
        :activity_attempt2,
        :part3_attempt2
      )
    end

    test "model selection", %{
      activity_a: activity,
      activity_attempt1: activity_attempt1,
      activity_attempt2: activity_attempt2
    } do
      revision = activity.revision

      # Directly loading attempts will not preload the revision, which makes it suitable
      # to feed into select_model/2

      assert %{"some" => "thing"} ==
               Oli.Repo.get(ActivityAttempt, activity_attempt1.id)
               |> Attempts.select_model(revision)

      assert revision.content ==
               Oli.Repo.get(ActivityAttempt, activity_attempt2.id)
               |> Attempts.select_model(revision)

      # Using get_activity_attempt_by does preload, therefore we can use select_model/1

      assert %{"some" => "thing"} ==
               Attempts.get_activity_attempt_by(attempt_guid: activity_attempt1.attempt_guid)
               |> Attempts.select_model()

      assert revision.content ==
               Attempts.get_activity_attempt_by(attempt_guid: activity_attempt2.attempt_guid)
               |> Attempts.select_model()
    end

    test "get graded resource access", %{
      section: section,
      graded_page: %{revision: revision},
      user1: user1
    } do
      activity_provider = &Oli.Delivery.ActivityProvider.provide/3

      PageContext.create_for_visit(section, revision.slug, user1)

      {:ok, %AttemptState{} = _} =
        PageLifecycle.start(
          revision.slug,
          section.slug,
          user1.id,
          activity_provider
        )

      access =
        Attempts.get_graded_resource_access_for_context(section.slug)
        |> Enum.filter(fn a -> a.resource_id == revision.resource_id && a.user_id == user1.id end)
        |> hd

      assert access.access_count == 1
      assert is_nil(access.score)
    end

    test "get graded resource access for specific students", %{
      section: section,
      graded_page: %{revision: revision},
      user1: user1,
      user2: user2
    } do
      activity_provider = &Oli.Delivery.ActivityProvider.provide/3

      PageContext.create_for_visit(section, revision.slug, user1)

      {:ok, %AttemptState{} = _} =
        PageLifecycle.start(
          revision.slug,
          section.slug,
          user1.id,
          activity_provider
        )

      PageContext.create_for_visit(section, revision.slug, user2)

      {:ok, %AttemptState{} = _} =
        PageLifecycle.start(
          revision.slug,
          section.slug,
          user2.id,
          activity_provider
        )

      accesses1 = Attempts.get_graded_resource_access_for_context(section.slug, [user1.id])
      assert Enum.all?(accesses1, fn a -> a.user_id == user1.id end)

      accesses2 = Attempts.get_graded_resource_access_for_context(section.slug, [user2.id])
      assert Enum.all?(accesses2, fn a -> a.user_id == user2.id end)

      accesses_both =
        Attempts.get_graded_resource_access_for_context(section.slug, [user1.id, user2.id])

      assert length(accesses_both) == length(accesses1) + length(accesses2)
    end

    test "get latest attempt - activity attempts", %{
      attempt2: attempt2,
      activity_attempt2: activity_attempt2,
      activity_a: activity_a
    } do
      results = Hierarchy.get_latest_attempts(attempt2.id)

      assert length(Map.keys(results)) == 1
      assert Map.has_key?(results, activity_a.resource.id)

      id = activity_attempt2.id

      case results[activity_a.resource.id] do
        {%{id: ^id}, map} -> assert map["1"].attempt_number == 3
        _ -> assert false
      end

      case results[activity_a.resource.id] do
        {%{id: ^id}, map} -> assert map["2"].attempt_number == 1
        _ -> assert false
      end

      case results[activity_a.resource.id] do
        {%{id: ^id}, map} -> assert map["3"].attempt_number == 2
        _ -> assert false
      end
    end

    test "get latest attempts - part attempts", %{attempt1: attempt1} do
      [{_activity_attempt, part_attempt_map}] =
        Hierarchy.get_latest_attempts(attempt1.id)
        |> Map.values()

      [part_attempt] =
        part_attempt_map
        |> Map.values()

      assert %Oli.Delivery.Attempts.Core.PartAttempt{} = part_attempt
      assert part_attempt.attempt_number == 1
      assert is_nil(part_attempt.date_evaluated)
    end

    test "get_section_by_activity_attempt_guid", %{
      section: section,
      activity_attempt1: activity_attempt1
    } do
      assert section.id ==
               Attempts.get_section_by_activity_attempt_guid(activity_attempt1.attempt_guid).id
    end

    test "resource attempt history", %{
      graded_page: %{resource: resource, revision: revision},
      section: section,
      user1: user1
    } do
      activity_provider = &Oli.Delivery.ActivityProvider.provide/3

      PageContext.create_for_visit(section, revision.slug, user1)

      {:ok, %AttemptState{} = _} =
        PageLifecycle.start(
          revision.slug,
          section.slug,
          user1.id,
          activity_provider
        )

      {access, attempts} =
        Attempts.get_resource_attempt_history(resource.id, section.slug, user1.id)

      assert access.access_count == 1
      assert length(attempts) == 1
      assert hd(attempts).attempt_number == 1
      assert hd(attempts).date_evaluated == nil
    end
  end

  describe "submit_client_evaluations" do
    alias Oli.Activities
    alias Oli.Activities.Manifest
    alias Oli.Activities.ModeSpecification

    test "processes a set of client evaluations for an activity that permits client evaluation" do
      # create mock activity which allows client evaluation
      {:ok, %Activities.ActivityRegistration{}} =
        Activities.register_activity(%Manifest{
          id: "test_allow_client_eval",
          friendlyName: "Test Client Eval",
          description: "A test activity that allows client evaluation",
          delivery: %ModeSpecification{element: "test-client-eval", entry: "./delivery-entry.ts"},
          authoring: %ModeSpecification{
            element: "test-client-eval",
            entry: "./authoring-entry.ts"
          },
          allowClientEvaluation: true,
          global: true
        })

      # create an example project with the activity in a graded page
      %{activity_attempt1: activity_attempt1, part1_attempt1: part1_attempt1, section: section} =
        Seeder.base_project_with_resource2()
        |> Seeder.create_section()
        |> Seeder.add_user(%{}, :user1)
        |> Seeder.add_user(%{}, :user2)
        |> Seeder.add_activity(
          %{activity_type_id: Activities.get_registration_by_slug("test_allow_client_eval").id},
          :publication,
          :project,
          :author,
          :activity_a
        )
        |> Seeder.add_page(%{graded: true}, :graded_page)
        |> Seeder.create_resource_attempt(
          %{attempt_number: 1},
          :user1,
          :page1,
          :revision1,
          :attempt1
        )
        |> Seeder.create_activity_attempt(
          %{attempt_number: 1, transformed_model: nil},
          :activity_a,
          :attempt1,
          :activity_attempt1
        )
        |> Seeder.create_part_attempt(
          %{attempt_number: 1},
          %Part{id: "1", responses: [], hints: []},
          :activity_attempt1,
          :part1_attempt1
        )
        |> Seeder.create_resource_attempt(
          %{attempt_number: 2},
          :user1,
          :page1,
          :revision1,
          :attempt2
        )
        |> Seeder.create_activity_attempt(
          %{attempt_number: 1, transformed_model: nil},
          :activity_a,
          :attempt2,
          :activity_attempt2
        )
        |> Seeder.create_part_attempt(
          %{attempt_number: 1},
          %Part{id: "1", responses: [], hints: []},
          :activity_attempt2,
          :part1_attempt1
        )

      # simulate client evaluation request
      context_id = section.context_id
      activity_attempt_guid = activity_attempt1.attempt_guid
      {:ok, feedback} = Feedback.parse(%{"id" => "1", "content" => "some-feedback"})

      client_evaluations = [
        %{
          attempt_guid: part1_attempt1.attempt_guid,
          client_evaluation: %ClientEvaluation{
            input: %StudentInput{input: "some-input"},
            score: 1,
            out_of: 1,
            feedback: feedback
          }
        }
      ]

      # check that client evaluation submission succeeds
      assert Evaluate.apply_client_evaluation(
               context_id,
               activity_attempt_guid,
               client_evaluations
             ) ==
               {:ok,
                [
                  %Oli.Delivery.Evaluation.Actions.FeedbackActionResult{
                    attempt_guid: part1_attempt1.attempt_guid,
                    feedback: %Oli.Activities.Model.Feedback{content: "some-feedback", id: "1"},
                    out_of: 1,
                    score: 1,
                    error: nil,
                    type: "FeedbackActionResult"
                  }
                ]}
    end

    test "fails to process a set of client evaluations for an activity that does not permit client evaluation" do
      # create mock activity which does not allow client evaluation
      {:ok, %Activities.ActivityRegistration{}} =
        Activities.register_activity(%Manifest{
          id: "test_refuse_client_eval",
          friendlyName: "Test Client Eval",
          description: "A test activity that allows client evaluation",
          delivery: %ModeSpecification{element: "test-client-eval", entry: "./delivery-entry.ts"},
          authoring: %ModeSpecification{
            element: "test-client-eval",
            entry: "./authoring-entry.ts"
          },
          allowClientEvaluation: false,
          global: true
        })

      # create an example project with the activity in a graded page
      %{activity_attempt1: activity_attempt1, part1_attempt1: part1_attempt1, section: section} =
        Seeder.base_project_with_resource2()
        |> Seeder.create_section()
        |> Seeder.add_user(%{}, :user1)
        |> Seeder.add_user(%{}, :user2)
        |> Seeder.add_activity(
          %{activity_type_id: Activities.get_registration_by_slug("test_refuse_client_eval").id},
          :publication,
          :project,
          :author,
          :activity_a
        )
        |> Seeder.add_page(%{graded: true}, :graded_page)
        |> Seeder.create_resource_attempt(
          %{attempt_number: 1},
          :user1,
          :page1,
          :revision1,
          :attempt1
        )
        |> Seeder.create_activity_attempt(
          %{attempt_number: 1, transformed_model: nil},
          :activity_a,
          :attempt1,
          :activity_attempt1
        )
        |> Seeder.create_part_attempt(
          %{attempt_number: 1},
          %Part{id: "1", responses: [], hints: []},
          :activity_attempt1,
          :part1_attempt1
        )
        |> Seeder.create_resource_attempt(
          %{attempt_number: 2},
          :user1,
          :page1,
          :revision1,
          :attempt2
        )
        |> Seeder.create_activity_attempt(
          %{attempt_number: 1, transformed_model: nil},
          :activity_a,
          :attempt2,
          :activity_attempt2
        )
        |> Seeder.create_part_attempt(
          %{attempt_number: 1},
          %Part{id: "1", responses: [], hints: []},
          :activity_attempt2,
          :part1_attempt1
        )

      # simulate client evaluation request
      context_id = section.context_id
      activity_attempt_guid = activity_attempt1.attempt_guid
      {:ok, feedback} = Feedback.parse(%{"id" => "1", "content" => "some-feedback"})

      client_evaluations = [
        %{
          attempt_guid: part1_attempt1.attempt_guid,
          client_evaluation: %ClientEvaluation{
            input: %StudentInput{input: "some-input"},
            score: 1,
            out_of: 1,
            feedback: feedback
          }
        }
      ]

      # check that client evaluation submission succeeds
      assert Evaluate.apply_client_evaluation(
               context_id,
               activity_attempt_guid,
               client_evaluations
             ) == {:error, "Activity type does not allow client evaluation"}
    end
  end
end
