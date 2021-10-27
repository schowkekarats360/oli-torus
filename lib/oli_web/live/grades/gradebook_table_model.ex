defmodule OliWeb.Grades.GradebookTableModel do
  alias OliWeb.Common.Table.{ColumnSpec, SortableTableModel}
  use Surface.LiveComponent
  alias Oli.Delivery.Attempts.Core.ResourceAccess
  alias OliWeb.Router.Helpers, as: Routes

  def new(enrollments, graded_pages, resource_accesses, section_slug) do
    by_user =
      Enum.reduce(resource_accesses, %{}, fn ra, m ->
        case Map.has_key?(m, ra.user_id) do
          true ->
            user = Map.get(m, ra.user_id)
            Map.put(m, ra.user_id, Map.put(user, ra.resource_id, ra))

          false ->
            Map.put(m, ra.user_id, Map.put(%{}, ra.resource_id, ra))
        end
      end)

    rows =
      Enum.map(enrollments, fn user ->
        Map.get(by_user, user.id, %{})
        |> Map.merge(%{user: user, id: user.id, section_slug: section_slug})
      end)

    column_specs =
      [
        %ColumnSpec{
          name: :name,
          label: "Student",
          render_fn: &__MODULE__.render_student/3
        }
      ] ++
        Enum.map(graded_pages, fn revision ->
          %ColumnSpec{
            name: revision.resource_id,
            label: revision.title,
            render_fn: &__MODULE__.render_score/3
          }
        end)

    SortableTableModel.new(
      rows: rows,
      column_specs: column_specs,
      event_suffix: "",
      id_field: [:id]
    )
  end

  def render_student(_, row, _) do
    OliWeb.Common.Utils.name(row.user)
  end

  def render_score(assigns, row, %ColumnSpec{name: resource_id}) do
    case Map.get(row, resource_id) do
      # Indicates that this student has never visited this resource
      nil ->
        ""

      # Indicates that this student has visited, but not completed this assessment
      %ResourceAccess{score: nil, out_of: nil} ->
        ""

      # We have a rolled-up grade from at least one attempt
      %ResourceAccess{score: score, out_of: out_of} ->
        show_score(assigns, row, resource_id, score, out_of)
    end
  end

  defp show_score(assigns, row, resource_id, score, out_of) do
    case out_of do
      0 ->
        ~F"""
        <a href={Routes.live_path(OliWeb.Endpoint, OliWeb.Progress.StudentResourceView, row.section_slug, row.id, resource_id)}>
          <span>{score}/{out_of} 0%</span>
        </a>
        """

      _ ->
        percentage =
          ((score / out_of * 100)
           |> Float.round(2)
           |> Float.to_string()) <> "%"

        ~F"""
        <a href={Routes.live_path(OliWeb.Endpoint, OliWeb.Progress.StudentResourceView, row.section_slug, row.id, resource_id)}>
        {score}/{out_of} <small class="text-muted">{percentage}</small>
        </a>
        """
    end
  end

  def render(assigns) do
    ~F"""
    <div>nothing</div>
    """
  end
end