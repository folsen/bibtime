defmodule Bibtime.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Bibtime.Accounts` context.
  """

  import Ecto.Query

  alias Bibtime.Accounts
  alias Bibtime.Accounts.Scope

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "hello world!"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email()
    })
  end

  def unconfirmed_user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Accounts.register_user()

    user
  end

  def user_fixture(attrs \\ %{}) do
    user = unconfirmed_user_fixture(attrs)

    token =
      extract_user_token(fn ->
        Accounts.deliver_login_instructions(user)
      end)

    {:ok, {user, _expired_tokens}} =
      Accounts.login_user_by_magic_link(token)

    user
  end

  def admin_user_fixture(attrs \\ %{}) do
    user = user_fixture(attrs)
    {:ok, user} = Bibtime.Accounts.update_user_role(user, "admin")
    user
  end

  def timer_user_fixture(attrs \\ %{}) do
    user = user_fixture(attrs)
    {:ok, user} = Bibtime.Accounts.update_user_role(user, "timer")
    user
  end

  def user_scope_fixture do
    user = user_fixture()
    user_scope_fixture(user)
  end

  def user_scope_fixture(user) do
    Scope.for_user(user)
  end

  def set_password(user) do
    {:ok, {user, _expired_tokens}} =
      Accounts.update_user_password(user, %{password: valid_user_password()})

    user
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.()

    [_, token] =
      Regex.run(
        ~r"/users/(?:log-in|settings/confirm-email)/([A-Za-z0-9_-]+)",
        captured_email.text_body
      )

    token
  end

  def override_token_authenticated_at(token, authenticated_at) when is_binary(token) do
    Bibtime.Repo.update_all(
      from(t in Accounts.UserToken,
        where: t.token == ^token
      ),
      set: [authenticated_at: authenticated_at]
    )
  end

  def generate_user_magic_link_token(user) do
    {encoded_token, user_token} = Accounts.UserToken.build_email_token(user, "login")
    Bibtime.Repo.insert!(user_token)
    {encoded_token, user_token.token}
  end

  def offset_user_token(token, amount_to_add, unit) do
    dt = DateTime.add(DateTime.utc_now(:second), amount_to_add, unit)

    Bibtime.Repo.update_all(
      from(ut in Accounts.UserToken, where: ut.token == ^token),
      set: [inserted_at: dt, authenticated_at: dt]
    )
  end
end
