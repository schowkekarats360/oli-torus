defmodule Oli.Rendering.Content.Html do
  @moduledoc """
  Implements the Html writer for Oli content rendering.

  Important: any changes to this file must be replicated in writers/html.ts for activity rendering.
  """
  import Oli.Utils

  alias Oli.Rendering.Context
  alias Phoenix.HTML
  import Oli.Rendering.Utils

  @behaviour Oli.Rendering.Content

  def example(%Context{} = _context, next, _) do
    [
      ~s|<div class="content-purpose example"><div class="content-purpose-label">Example</div><div class="content-purpose-content">|,
      next.(),
      "</div></div>\n"
    ]
  end

  def learn_more(%Context{} = _context, next, _) do
    [
      ~s|<div class="content-purpose learnmore"><div class="content-purpose-label">Learn more</div><div class="content-purpose-content">|,
      next.(),
      "</div></div>\n"
    ]
  end

  def manystudentswonder(%Context{} = _context, next, _) do
    [
      ~s|<div class="content-purpose manystudentswonder"><div class="content-purpose-label">Many Students Wonder</div><div class="content-purpose-content">|,
      next.(),
      "</div></div>\n"
    ]
  end

  def p(%Context{} = _context, next, _) do
    ["<p>", next.(), "</p>\n"]
  end

  def h1(%Context{} = _context, next, _) do
    ["<h1>", next.(), "</h1>\n"]
  end

  def h2(%Context{} = _context, next, _) do
    ["<h2>", next.(), "</h2>\n"]
  end

  def h3(%Context{} = _context, next, _) do
    ["<h3>", next.(), "</h3>\n"]
  end

  def h4(%Context{} = _context, next, _) do
    ["<h4>", next.(), "</h4>\n"]
  end

  def h5(%Context{} = _context, next, _) do
    ["<h5>", next.(), "</h5>\n"]
  end

  def h6(%Context{} = _context, next, _) do
    ["<h6>", next.(), "</h6>\n"]
  end

  def img(%Context{} = _context, _, %{"src" => src} = attrs) do
    maybeAlt =
      case attrs do
        %{"alt" => alt} -> " alt=#{escape_xml!(alt)}"
        _ -> ""
      end

    maybeWidth =
      case attrs do
        %{"width" => width} -> " width=#{escape_xml!(width)}"
        _ -> ""
      end

    maybeHeight =
      case attrs do
        %{"height" => height} -> " height=#{escape_xml!(height)}"
        _ -> ""
      end

    figure(attrs, [
      ~s|<img class="figure-img img-fluid"#{maybeAlt}#{maybeWidth}#{maybeHeight} src="#{escape_xml!(src)}"/>\n|
    ])
  end

  def img(%Context{} = context, _, e) do
    missing_media_src(context, e)
  end

  def youtube(%Context{} = context, _, %{"src" => src} = attrs) do
    iframe(
      context,
      nil,
      Map.put(attrs, "src", "https://www.youtube.com/embed/#{escape_xml!(src)}")
    )
  end

  def youtube(%Context{} = context, _, e) do
    missing_media_src(context, e)
  end

  def iframe(%Context{} = _context, _, %{"src" => src} = attrs) do
    figure(attrs, [
      """
      <div class="embed-responsive embed-responsive-16by9">
        <iframe class="embed-responsive-item" allowfullscreen src="#{escape_xml!(src)}"></iframe>
      </div>
      """
    ])
  end

  def iframe(%Context{} = context, _, e) do
    missing_media_src(context, e)
  end

  def audio(%Context{} = _context, _, %{"src" => src} = attrs) do
    figure(attrs, [~s|<audio controls src="#{escape_xml!(src)}">
      Your browser does not support the <code>audio</code> element.
    </audio>\n|])
  end

  def audio(%Context{} = context, _, e) do
    missing_media_src(context, e)
  end

  def table(%Context{} = _context, next, attrs) do
    caption =
      case attrs do
        %{"caption" => caption} -> "<caption>#{escape_xml!(caption)}</caption>"
        _ -> ""
      end

    ["<table>#{caption}", next.(), "</table>\n"]
  end

  def tr(%Context{} = _context, next, _) do
    ["<tr>", next.(), "</tr>\n"]
  end

  def th(%Context{} = _context, next, _) do
    ["<th>", next.(), "</th>\n"]
  end

  def td(%Context{} = _context, next, _) do
    ["<td>", next.(), "</td>\n"]
  end

  def ol(%Context{} = _context, next, _) do
    ["<ol>", next.(), "</ol>\n"]
  end

  def ul(%Context{} = _context, next, _) do
    ["<ul>", next.(), "</ul>\n"]
  end

  def li(%Context{} = _context, next, _) do
    ["<li>", next.(), "</li>\n"]
  end

  def math(%Context{} = _context, next, _) do
    ["<div>\\[", next.(), "\\]</div>\n"]
  end

  def math_line(%Context{} = _context, next, _) do
    [next.(), "\n"]
  end

  def code(
        %Context{} = _context,
        next,
        %{
          "language" => language
        } = attrs
      ) do
    figure(attrs, [
      ~s|<pre><code class="language-#{escape_xml!(language)}">|,
      next.(),
      "</code></pre>\n"
    ])
  end

  def code(
        %Context{} = _context,
        next,
        attrs
      ) do
    {_error_id, _error_msg} =
      log_error("Malformed content element. Missing language attribute", attrs)

    figure(attrs, [
      ~s|<pre><code class="language-none">|,
      next.(),
      "</code></pre>\n"
    ])
  end

  def code_line(%Context{} = _context, next, _) do
    [next.(), "\n"]
  end

  def blockquote(%Context{} = _context, next, _) do
    ["<blockquote>", next.(), "</blockquote>\n"]
  end

  def a(%Context{} = context, next, %{"href" => href}) do
    if String.starts_with?(href, "/course/link") do
      internal_link(context, next, href)
    else
      external_link(context, next, href)
    end
  end

  def a(%Context{} = context, next, attrs) do
    {_error_id, _error_msg} =
      log_error("Malformed content element. Missing href attribute", attrs)

    external_link(context, next, "#")
  end

  defp internal_link(
         %Context{section_slug: section_slug, mode: mode, project_slug: project_slug},
         next,
         href
       ) do
    href =
      case section_slug do
        nil ->
          case mode do
            :author_preview ->
              "/authoring/project/#{project_slug}/preview/#{revision_slug_from_course_link(href)}"

            _ ->
              "#"
          end

        section_slug ->
          # rewrite internal link using section slug and revision slug
          case mode do
            :instructor_preview ->
              "/sections/#{section_slug}/preview/page/#{revision_slug_from_course_link(href)}"

            _ ->
              "/sections/#{section_slug}/page/#{revision_slug_from_course_link(href)}"
          end
      end

    [~s|<a class="internal-link" href="#{escape_xml!(href)}">|, next.(), "</a>\n"]
  end

  defp external_link(%Context{} = _context, next, href) do
    [~s|<a class="external-link" href="#{escape_xml!(href)}" target="_blank">|, next.(), "</a>\n"]
  end

  def popup(%Context{} = context, next, %{"trigger" => trigger, "content" => content}) do
    trigger =
      if escape_xml!(trigger) == "hover" do
        "hover focus"
      else
        "manual"
      end

    [
      ~s"""
      <span
        tabindex="0"
        role="button"
        class="popup__anchorText#{if !String.contains?(trigger, "hover") do
        " popup__click"
      else
        ""
      end}"
        data-trigger="#{trigger}"
        data-toggle="popover"
        data-placement="top"
        data-html="true"
        data-template='
          <div class="popover popup__content" role="tooltip">
            <div class="arrow"></div>
            <h3 class="popover-header"></h3>
            <div class="popover-body"></div>
          </div>'
        data-content="#{escape_xml!(parse_html_content(content, context))}">
        #{next.()}
      </span>\n
      """
    ]
  end

  def selection(%Context{} = context, _, selection) do
    Oli.Rendering.Content.Selection.render(context, selection, true)
  end

  defp revision_slug_from_course_link(href) do
    href
    |> String.replace_prefix("/course/link/", "")
  end

  def definition(%Context{} = _context, next, _) do
    ["<extra>", next.(), "</extra>\n"]
  end

  def text(%Context{} = _context, %{"text" => text} = text_entity) do
    escape_xml!(text) |> wrap_with_marks(text_entity)
  end

  def error(%Context{} = _context, element, error) do
    case error do
      {:unsupported, error_id, _error_msg} ->
        [
          ~s|<div class="content unsupported">Content element type '#{element["type"]}' is not supported. Please contact support with issue ##{error_id}</div>\n|
        ]

      {:invalid, error_id, _error_msg} ->
        [
          ~s|<div class="content invalid">Content element is invalid. Please contact support with issue ##{error_id}</div>\n|
        ]

      {_, error_id, _error_msg} ->
        [
          ~s|<div class="content invalid">An error occurred while rendering content. Please contact support with issue ##{error_id}</div>\n|
        ]
    end
  end

  def escape_xml!(text) do
    case HTML.html_escape(text) do
      {:safe, result} -> result
    end
  end

  defp wrap_with_marks(text, text_entity) do
    supported_mark_tags = %{
      "em" => "em",
      "strong" => "strong",
      "mark" => "mark",
      "del" => "del",
      "var" => "var",
      "code" => "code",
      "sub" => "sub",
      "sup" => "sup"
    }

    marks =
      Map.keys(text_entity)
      # only include marks that are set to true
      |> Enum.filter(fn attr_name -> Map.get(text_entity, attr_name) == true end)
      # convert mark to tag name
      |> Enum.map(fn attr_name -> Map.get(supported_mark_tags, attr_name) end)
      # filter out any unsupported marks
      |> Enum.filter(fn mark -> mark != nil end)

    Enum.reverse(marks)
    |> Enum.reduce(
      text,
      fn mark, acc ->
        "<#{mark}>#{acc}</#{mark}>"
      end
    )
  end

  # Accessible captions are created using a combination of the <figure /> and <figcaption /> elements.
  defp figure(%{"caption" => ""} = _attrs, content), do: content

  defp figure(%{"caption" => caption} = _attrs, content) do
    [~s|<div class="figure-wrapper">|] ++
      [~s|<figure class="figure embed-responsive text-center">|] ++
      content ++
      [~s|<figcaption class="figure-caption text-center">|] ++
      [escape_xml!(caption)] ++
      ["</figcaption>"] ++
      ["</figure>"] ++
      ["</div>"]
  end

  defp figure(_attrs, content), do: content

  defp missing_media_src(%Context{render_opts: render_opts} = context, element) do
    {error_id, error_msg} = log_error("Malformed content element. Missing src attribute", element)

    if render_opts.render_errors do
      error(context, element, {:invalid, error_id, error_msg})
    else
      []
    end
  end
end
