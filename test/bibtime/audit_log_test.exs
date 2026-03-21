defmodule Bibtime.AuditLogTest do
  use Bibtime.DataCase

  alias Bibtime.AuditLog

  import Bibtime.AccountsFixtures

  describe "log/5" do
    test "creates an audit log entry with a user" do
      user = user_fixture()

      assert {:ok, entry} =
               AuditLog.log(user, "race.created", "race", 1, %{"name" => "Test Race"})

      assert entry.user_id == user.id
      assert entry.action == "race.created"
      assert entry.resource_type == "race"
      assert entry.resource_id == 1
      assert entry.metadata == %{"name" => "Test Race"}
    end

    test "creates an audit log entry without a user" do
      assert {:ok, entry} = AuditLog.log(nil, "system.action", "system")
      assert entry.user_id == nil
      assert entry.action == "system.action"
      assert entry.resource_type == "system"
    end

    test "creates an entry with defaults for resource_id and metadata" do
      user = user_fixture()
      assert {:ok, entry} = AuditLog.log(user, "test.action", "test")
      assert entry.resource_id == nil
      assert entry.metadata == %{}
    end
  end

  describe "list_entries/1" do
    test "returns entries ordered by most recent first" do
      user = user_fixture()
      {:ok, _entry1} = AuditLog.log(user, "first", "test")
      {:ok, _entry2} = AuditLog.log(user, "second", "test")

      entries = AuditLog.list_entries()
      actions = Enum.map(entries, & &1.action)
      assert actions == ["second", "first"]
    end

    test "respects limit option" do
      user = user_fixture()

      for i <- 1..5 do
        AuditLog.log(user, "action_#{i}", "test")
      end

      entries = AuditLog.list_entries(limit: 3)
      assert length(entries) == 3
    end

    test "preloads user" do
      user = user_fixture()
      {:ok, _entry} = AuditLog.log(user, "test", "test")

      [entry] = AuditLog.list_entries()
      assert entry.user.id == user.id
      assert entry.user.email == user.email
    end
  end
end
