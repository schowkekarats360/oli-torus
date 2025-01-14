defmodule Oli.Delivery.Paywall.Providers.StripeTest do
  use Oli.DataCase

  alias Oli.Publishing
  alias Oli.Delivery.{Sections, Paywall}
  alias Oli.Delivery.Paywall.Providers.Stripe
  alias Lti_1p3.Tool.ContextRoles
  alias Oli.Delivery.Sections
  alias Oli.Repo.{Paging, Sorting}
  alias Oli.Delivery.Sections.{EnrollmentBrowseOptions}

  import Ecto.Query, warn: false

  alias Oli.Test.MockHTTP
  import Mox

  describe "intent-driven pending payment and finalization of payment" do
    setup do
      map = Seeder.base_project_with_resource2()

      {:ok, _} = Publishing.publish_project(map.project, "some changes")

      # Create a product using the initial publication
      {:ok, product} =
        Sections.create_section(%{
          type: :blueprint,
          requires_payment: true,
          amount: Money.new(:USD, 100),
          title: "1",
          timezone: "1",
          registration_open: true,
          grace_period_days: 1,
          context_id: UUID.uuid4(),
          institution_id: map.institution.id,
          base_project_id: map.project.id
        })

      user1 = user_fixture(%{email_confirmed_at: Timex.now()}) |> Repo.preload(:platform_roles)

      {:ok, section} =
        Sections.create_section(%{
          type: :enrollable,
          requires_payment: true,
          amount: Money.new(:USD, 100),
          title: "1",
          timezone: "1",
          registration_open: true,
          has_grace_period: false,
          grace_period_days: 1,
          context_id: UUID.uuid4(),
          start_date: DateTime.add(DateTime.utc_now(), -5),
          end_date: DateTime.add(DateTime.utc_now(), 5),
          institution_id: map.institution.id,
          base_project_id: map.project.id,
          blueprint_id: product.id
        })

      {:ok, enrollment} =
        Sections.enroll(user1.id, section.id, [ContextRoles.get_role(:context_learner)])

      %{
        product: product,
        section: section,
        map: map,
        user1: user1,
        enrollment: enrollment
      }
    end

    test "finalization fails when no pending payment found", %{} do
      assert {:error, "Payment does not exist"} ==
               Stripe.finalize_payment(%{"id" => "a_made_up_intent_id"})
    end

    test "finalization succeeds", %{
      section: section,
      product: product,
      user1: user,
      enrollment: enrollment
    } do
      url = "https://api.stripe.com/v1/payment_intents"

      MockHTTP
      |> expect(:post, fn ^url, _body, _headers ->
        {:ok,
         %HTTPoison.Response{
           status_code: 200,
           body: "{ \"client_secret\": \"secret\", \"id\": \"test_id\" }"
         }}
      end)

      {:ok, intent} = Stripe.create_intent(Money.new(:USD, 100), user, section, product)

      pending_payment = Paywall.get_provider_payment(:stripe, "test_id")
      assert pending_payment
      refute pending_payment.application_date
      assert is_nil(pending_payment.enrollment_id)
      assert pending_payment.pending_section_id == section.id
      assert pending_payment.pending_user_id == user.id
      assert pending_payment.section_id == product.id
      assert pending_payment.provider_type == :stripe
      assert pending_payment.provider_id == "test_id"

      assert {:ok, _} = Stripe.finalize_payment(intent)

      finalized = Paywall.get_provider_payment(:stripe, "test_id")
      assert finalized
      assert finalized.id == pending_payment.id
      assert finalized.enrollment_id == enrollment.id
      assert finalized.application_date
      assert finalized.pending_section_id == section.id
      assert finalized.pending_user_id == user.id
      assert finalized.section_id == product.id
      assert finalized.provider_type == :stripe
      assert finalized.provider_id == "test_id"

      e = Oli.Repo.get!(Oli.Delivery.Sections.Enrollment, finalized.enrollment_id)
      assert e.user_id == user.id
      assert e.section_id == section.id
    end

    test "multiple intent creation succeeds when first is not finalized",
         %{section: section, product: product, user1: user} do
      url = "https://api.stripe.com/v1/payment_intents"

      MockHTTP
      |> expect(:post, fn ^url, _body, _headers ->
        {:ok,
         %HTTPoison.Response{
           status_code: 200,
           body: "{ \"client_secret\": \"secret\", \"id\": \"test_id\" }"
         }}
      end)

      {:ok, _intent1} = Stripe.create_intent(Money.new(:USD, 100), user, section, product)

      MockHTTP
      |> expect(:post, fn ^url, _body, _headers ->
        {:ok,
         %HTTPoison.Response{
           status_code: 200,
           body: "{ \"client_secret\": \"secret\", \"id\": \"second_id\" }"
         }}
      end)

      {:ok, intent2} = Stripe.create_intent(Money.new(:USD, 100), user, section, product)

      assert is_nil(Paywall.get_provider_payment(:stripe, "test_id"))
      pending_payment = Paywall.get_provider_payment(:stripe, "second_id")
      assert pending_payment
      refute pending_payment.application_date
      assert pending_payment.pending_section_id == section.id
      assert pending_payment.pending_user_id == user.id
      assert pending_payment.section_id == product.id
      assert pending_payment.provider_type == :stripe
      assert pending_payment.provider_id == "second_id"

      assert {:ok, _} = Stripe.finalize_payment(intent2)

      finalized = Paywall.get_provider_payment(:stripe, "second_id")
      assert finalized
      assert finalized.id == pending_payment.id

      assert finalized.application_date
      assert finalized.pending_section_id == section.id
      assert finalized.pending_user_id == user.id
      assert finalized.section_id == product.id
      assert finalized.provider_type == :stripe
      assert finalized.provider_id == "second_id"

      e = Oli.Repo.get!(Oli.Delivery.Sections.Enrollment, finalized.enrollment_id)
      assert e.user_id == user.id
      assert e.section_id == section.id

      results =
        Sections.browse_enrollments(
          section,
          %Paging{offset: 0, limit: 3},
          %Sorting{field: :email, direction: :asc},
          %EnrollmentBrowseOptions{
            is_student: false,
            is_instructor: false,
            text_search: nil
          }
        )

      assert Enum.count(results) == 1
      refute is_nil(hd(results).payment_date)
    end

    test "multiple intent creation fails when first is finalized",
         %{section: section, product: product, user1: user} do
      url = "https://api.stripe.com/v1/payment_intents"

      MockHTTP
      |> expect(:post, fn ^url, _body, _headers ->
        {:ok,
         %HTTPoison.Response{
           status_code: 200,
           body: "{ \"client_secret\": \"secret\", \"id\": \"test_id\" }"
         }}
      end)

      {:ok, intent1} = Stripe.create_intent(Money.new(:USD, 100), user, section, product)

      assert {:ok, _} = Stripe.finalize_payment(intent1)

      MockHTTP
      |> expect(:post, fn ^url, _body, _headers ->
        {:ok,
         %HTTPoison.Response{
           status_code: 200,
           body: "{ \"client_secret\": \"secret\", \"id\": \"second_id\" }"
         }}
      end)

      assert {:error, {:payment_already_exists}} =
               Stripe.create_intent(Money.new(:USD, 100), user, section, product)
    end

    test "double finalization fails", %{section: section, product: product, user1: user} do
      url = "https://api.stripe.com/v1/payment_intents"

      MockHTTP
      |> expect(:post, fn ^url, _body, _headers ->
        {:ok,
         %HTTPoison.Response{
           status_code: 200,
           body: "{ \"client_secret\": \"secret\", \"id\": \"test_id\" }"
         }}
      end)

      {:ok, intent} = Stripe.create_intent(Money.new(:USD, 100), user, section, product)
      assert {:ok, _} = Stripe.finalize_payment(intent)
      assert {:error, "Payment already finalized"} = Stripe.finalize_payment(intent)
    end
  end
end
