defmodule Oli.Factory do
  use ExMachina.Ecto, repo: Oli.Repo

  alias Oli.Accounts.{Author, User}
  alias Oli.Authoring.Course.{Family, Project, ProjectVisibility}
  alias Oli.Delivery.Sections.{Section, SectionsProjectsPublications, SectionResource}
  alias Oli.Delivery.Gating.GatingCondition
  alias Oli.Groups.{Community, CommunityAccount, CommunityInstitution, CommunityVisibility}
  alias Oli.Institutions.Institution
  alias Oli.Publishing.{Publication, PublishedResource}
  alias Oli.Resources.{Resource, Revision}

  def author_factory() do
    %Author{
      email: "#{sequence("author")}@example.edu",
      name: "Author name",
      given_name: sequence("Author given name"),
      family_name: "Author family name",
      system_role_id: Oli.Accounts.SystemRole.role_id().author
    }
  end

  def user_factory() do
    %User{
      email: "#{sequence("user")}@example.edu",
      name: sequence("User name"),
      given_name: sequence("User given name"),
      family_name: "User family name",
      sub: "#{sequence("usersub")}",
      author: insert(:author),
      guest: false,
      independent_learner: true,
      can_create_sections: true,
      locked_at: nil
    }
  end

  def community_factory() do
    %Community{
      name: sequence("Example Community"),
      description: "An awesome description",
      key_contact: "keycontact@example.com",
      global_access: true,
      status: :active
    }
  end

  def community_account_factory(), do: struct!(community_admin_account_factory())

  def community_admin_account_factory() do
    %CommunityAccount{
      community: insert(:community),
      author: insert(:author),
      is_admin: true
    }
  end

  def community_visibility_factory(), do: struct!(community_project_visibility_factory())

  def community_project_visibility_factory() do
    %CommunityVisibility{
      community: insert(:community),
      project: insert(:project)
    }
  end

  def community_product_visibility_factory() do
    %CommunityVisibility{
      community: insert(:community),
      section: insert(:section)
    }
  end

  def project_factory() do
    %Project{
      description: "Example description",
      title: "Example Course",
      slug: sequence("examplecourse"),
      version: "1",
      family: insert(:family),
      visibility: :global,
      authors: insert_list(2, :author)
    }
  end

  def project_visibility_factory(), do: struct!(project_author_visibility_factory())

  def project_author_visibility_factory() do
    project = insert(:project)
    author = insert(:author)

    %ProjectVisibility{
      project_id: project.id,
      author_id: author.id
    }
  end

  def project_institution_visibility_factory() do
    project = insert(:project)
    institution = insert(:institution)

    %ProjectVisibility{
      project_id: project.id,
      institution_id: institution.id
    }
  end

  def publication_factory() do
    {:ok, date, _timezone} = DateTime.from_iso8601("2019-05-22 20:30:00Z")

    %Publication{
      published: date,
      project: insert(:project)
    }
  end

  def family_factory() do
    %Family{
      description: "Family description",
      title: "Family title"
    }
  end

  def section_factory() do
    %Section{
      title: "Section",
      timezone: "America/New_York",
      registration_open: true,
      context_id: UUID.uuid4(),
      institution: insert(:institution),
      base_project: insert(:project),
      slug: sequence("examplesection"),
      type: :blueprint
    }
  end

  def institution_factory() do
    %Institution{
      name: sequence("Example Institution"),
      country_code: "US",
      institution_email: "ins@example.edu",
      institution_url: "example.edu",
      timezone: "America/New_York"
    }
  end

  def community_member_account_factory() do
    %CommunityAccount{
      community: insert(:community),
      user: insert(:user),
      is_admin: false
    }
  end

  def community_institution_factory() do
    %CommunityInstitution{
      community: insert(:community),
      institution: insert(:institution)
    }
  end

  def published_resource_factory() do
    %PublishedResource{
      resource: insert(:resource),
      publication: insert(:publication),
      revision: insert(:revision),
      author: insert(:author)
    }
  end

  def section_project_publication_factory() do
    %SectionsProjectsPublications{
      project: insert(:project),
      section: insert(:section),
      publication: insert(:publication)
    }
  end

  def section_resource_factory() do
    %SectionResource{
      project: insert(:project),
      section: insert(:section),
      resource_id: insert(:resource).id
    }
  end

  def revision_factory() do
    %Revision{
      title: "Example revision",
      slug: "example_revision",
      resource: insert(:resource)
    }
  end

  def resource_factory() do
    %Resource{}
  end

  def gating_condition_factory() do
    {:ok, start_date, _timezone} = DateTime.from_iso8601("2019-05-22 20:30:00Z")
    {:ok, end_date, _timezone} = DateTime.from_iso8601("2019-06-24 20:30:00Z")

    %GatingCondition{
      user: insert(:user),
      section: insert(:section),
      resource: insert(:resource),
      type: :schedule,
      data: %{end_datetime: end_date, start_datetime: start_date}
    }
  end
end
