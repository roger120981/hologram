defmodule HologramFeatureTests.SessionTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Session.Page1
  alias HologramFeatureTests.Session.Page2
  alias HologramFeatureTests.Session.Page3
  alias HologramFeatureTests.Session.Page4
  alias HologramFeatureTests.Session.Page5
  alias HologramFeatureTests.Session.Page6
  alias Wallaby.Browser

  describe "page init session handling" do
    feature "write to session and read from session", %{session: session} do
      assert Browser.cookies(session) == []

      visit(session, Page1)

      assert [%{"name" => "phoenix_session"}] = Browser.cookies(session)

      session
      |> visit(Page2)
      |> assert_text("session_value = :abc")
    end

    feature "delete from session", %{session: session} do
      assert Browser.cookies(session) == []

      session
      |> visit(Page1)
      |> visit(Page3)
      |> visit(Page2)
      |> assert_text("session_value = nil")
    end
  end

  describe "command session handling" do
    feature "write to session", %{session: session} do
      assert Browser.cookies(session) == []

      session
      |> visit(Page4)
      |> click(button("Write to session"))
      |> assert_text("command_executed? = true")

      assert [%{"name" => "phoenix_session"}] = Browser.cookies(session)

      session
      |> visit(Page2)
      |> assert_text("session_value = :abc")
    end

    feature "read from session", %{session: session} do
      assert Browser.cookies(session) == []

      session
      |> visit(Page1)
      |> visit(Page5)
      |> click(button("Read from session"))
      |> assert_text("command_executed? = true, session_value = :abc")
    end

    feature "delete from session", %{session: session} do
      assert Browser.cookies(session) == []

      session
      |> visit(Page1)
      |> visit(Page6)
      |> click(button("Delete from session"))
      |> assert_text("command_executed? = true")
      |> visit(Page2)
      |> assert_text("session_value = nil")
    end
  end
end
