defmodule EvercamMedia.CameraShareController do
  use EvercamMedia.Web, :controller
  alias EvercamMedia.CameraShareView
  alias EvercamMedia.CameraShareRequestView

  def show(conn, %{"id" => exid} = params) do
    current_user = conn.assigns[:current_user]
    camera = Camera.get_full(exid)
    user = User.by_username_or_email(params["user_id"])

    with :ok <- camera_exists(conn, exid, camera),
         :ok <- caller_has_permission(conn, current_user, camera),
         :ok <- user_exists(conn, params["user_id"], user),
         :ok <- user_can_list(conn, current_user, camera, params["user_id"])
    do
      shares =
        if user do
          CameraShare.user_camera_share(camera, user)
        else
          CameraShare.camera_shares(camera)
        end
      conn
      |> render(CameraShareView, "index.json", %{camera_shares: shares, camera: camera, user: current_user})
    end
  end

  def create(conn, params) do
    caller = conn.assigns[:current_user]
    camera = Camera.get_full(params["id"])
    sharee = User.by_username_or_email(params["email"])

    with :ok <- camera_exists(conn, params["id"], camera),
         :ok <- caller_has_permission(conn, caller, camera)
    do
      if sharee do
        case CameraShare.create_share(camera, sharee, caller, params["rights"], params["message"]) do
          {:ok, camera_share} ->
            EvercamMedia.UserMailer.camera_shared_notification(caller, camera, sharee.email, params["message"])
            conn |> render(CameraShareView, "show.json", %{camera_share: camera_share})
          {:error, changeset} ->
            render_error(conn, 400, Util.parse_changeset(changeset))
        end
      else
        case CameraShareRequest.create_share_request(camera, params["email"], caller, params["rights"], params["message"]) do
          {:ok, camera_share_request} ->
            EvercamMedia.UserMailer.camera_share_request_notification(caller, camera, params["email"], params["message"], camera_share_request.key)
            conn |> render(CameraShareRequestView, "show.json", %{camera_share_requests: camera_share_request})
          {:error, changeset} ->
            render_error(conn, 400, Util.parse_changeset(changeset))
        end
      end
    end
  end

  defp camera_exists(conn, camera_exid, nil), do: render_error(conn, 404, "The #{camera_exid} camera does not exist.")
  defp camera_exists(_conn, _camera_exid, _camera), do: :ok

  defp user_exists(_conn, nil, nil), do: :ok
  defp user_exists(conn, user_id, nil), do: render_error(conn, 404, "User '#{user_id}' does not exist.")
  defp user_exists(_conn, _user_id, _user), do: :ok

  defp caller_has_permission(conn, user, camera) do
    if Permission.Camera.can_edit?(user, camera) do
      :ok
    else
      render_error(conn, 401, "Unauthorized.")
    end
  end

  defp user_can_list(_conn, _user, _camera, nil), do: :ok
  defp user_can_list(conn, user, camera, user_id) do
    if !Permission.Camera.can_list?(user, camera) && (user.email != user_id && user.username != user_id) do
      render_error(conn, 401, "Unauthorized.")
    else
      :ok
    end
  end
end