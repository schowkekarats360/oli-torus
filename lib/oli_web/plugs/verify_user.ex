defmodule Oli.Plugs.VerifyUser do
  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      if get_session(conn, :current_user_id) do
        conn
      else
        conn
          |> put_view(OliWeb.DeliveryView)
          |> render("signin_required.html")
          |> halt()
      end
    end
  end
end
